class_name WorkSession
extends RefCounted

## In-round work: opening the Burn Board, burning and cooling, settling a
## session. Owned by Simulation as `_work`; ephemeral flags live here so the
## facade can forward `queued_boost` / `is_work_running` without UI churn.
##
## `sim` is the owning Simulation node, taken as a plain `Node` to avoid a
## circular class reference. Cross-concern calls (end round, victory) go back
## through Simulation routing methods, not to RunLifecycle directly.

const POLICY_MANUAL := "manual"
const POLICY_AUTO := "auto"
const POLICY_YOLO := "yolo"

var work_running: bool = false
var work_tick: int = 0
var action_counter: int = 0
var session_cash_start: float = 0.0
var queued_boost: bool = false
var last_session_summary: Dictionary = {}
var work_policy: String = POLICY_MANUAL


func reset() -> void:
	work_running = false
	work_tick = 0
	action_counter = 0
	session_cash_start = 0.0
	queued_boost = false
	last_session_summary = {}
	work_policy = POLICY_MANUAL


func can_start_work(sim: Node) -> bool:
	return sim.phase == sim.Phase.ROUND_PREP and sim.run_state.has_pending_work() and not work_running


func is_work_running(sim: Node) -> bool:
	return work_running and sim.phase == sim.Phase.IN_ROUND


func can_burn(sim: Node) -> bool:
	if sim.phase != sim.Phase.IN_ROUND or not work_running:
		return false
	if sim.job_system().focused_job(sim.run_state).is_empty():
		return false
	return sim.board_system().filled_slot_count(sim.run_state) > 0


func set_queued_boost(sim: Node, enabled: bool) -> void:
	if can_start_work(sim):
		queued_boost = enabled


## Opens the Burn Board. Nothing is produced until the player burns a batch:
## from here the session waits on burn_batch / cool_hardware / ship_focused_job.
func start_work(sim: Node) -> void:
	if not can_start_work(sim):
		return
	# The pre-board behaviour, kept for balance sweeps and headless drives.
	if FeatureFlags.is_enabled("auto_work_loop_enabled"):
		start_work_sync(sim)
		sim.work_session_finished.emit({"phase": sim.phase, "summary": last_session_summary})
		return
	work_running = true
	sim.round_log.clear()
	work_tick = 0
	session_cash_start = float(sim.run_state.economy.get("cash", 0.0))
	sim.board_system().ensure_board(sim.run_state, ContentDatabase)
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	if not sim.job_system().begin_work_session(sim.run_state, ContentDatabase):
		work_running = false
		return
	sim.phase = sim.Phase.IN_ROUND
	_fire_queued_options(sim)
	_follow_focused_workflow(sim)
	for job in sim.run_state.business.get("active_jobs", []):
		EventBus.emit_event(EventBus.EVENT_JOB_STARTED, {"job_id": job.get("id", "")})
	sim.work_tick_completed.emit()
	sim._autosave()


func _fire_queued_options(sim: Node) -> void:
	if queued_boost:
		_apply_boost(sim)
	queued_boost = false


func start_work_sync(sim: Node) -> Dictionary:
	if not can_start_work(sim):
		return {"ok": false}
	work_running = true
	sim.round_log.clear()
	work_tick = 0
	session_cash_start = float(sim.run_state.economy.get("cash", 0.0))
	sim.board_system().ensure_board(sim.run_state, ContentDatabase)
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	if not sim.job_system().begin_work_session(sim.run_state, ContentDatabase):
		work_running = false
		return {"ok": false}
	sim.phase = sim.Phase.IN_ROUND
	_fire_queued_options(sim)
	for job in sim.run_state.business.get("active_jobs", []):
		EventBus.emit_event(EventBus.EVENT_JOB_STARTED, {"job_id": job.get("id", "")})
	# Nobody is here to arrange the board, so the auto-drive does it: without this
	# the bench would fill up with modules that never reach the pipeline.
	sim.auto_arrange_board()
	var safety: int = 0
	while sim.phase == sim.Phase.IN_ROUND and safety < 500:
		safety += 1
		if _should_auto_ship(sim):
			ship_focused_job(sim)
			if sim.phase != sim.Phase.IN_ROUND:
				break
			continue
		var result: Dictionary = _execute_tick(sim)
		if not result.get("ok", true):
			end_session(sim, "collapsed")
			break
		for message in result.get("messages", []):
			sim.round_log.append(str(message))
		_advance_prompt(sim, result)
		var stop: String = _session_stop_reason(result)
		if stop != "":
			end_session(sim, stop)
			break
	# A round that cannot resolve itself inside the safety limit is a stuck round
	# rather than an endless one, so it settles as if the contracts had run out.
	if sim.phase == sim.Phase.IN_ROUND:
		end_session(sim, "stalled")
	work_running = false
	return {"ok": true, "phase": sim.phase}


## Burns one batch through the pipeline, which spends one prompt.
##
## `stage_limit` is how KILL PROCESS lands: the stages that had already fired
## keep their output and the rest of the batch is lost.
func burn_batch(sim: Node, stage_limit: int = -1) -> Dictionary:
	if not can_burn(sim):
		return {"ok": false, "reason": "Not working."}
	var job: Dictionary = sim.job_system().focused_job(sim.run_state)
	var result: Dictionary = sim.job_system().run_burn(
		sim.run_state,
		burn_rng(sim),
		sim.effect_resolver,
		sim.debug_collect_subscriptions(),
		sim.tuning,
		sim.compute_system(),
		sim.heat_system(),
		sim.economy_system(),
		sim.board_system(),
		stage_limit
	)
	if not result.get("ok", false):
		return result
	# Only a committed action spends a prompt's worth of RNG. A refusal that
	# touched nothing must not shift the seed the next attempt rolls against —
	# otherwise a failed action rerolls a deterministic outcome for free.
	work_tick += 1
	var burn: Dictionary = result.get("burn", {})
	sim.burn_resolved.emit(burn)
	finish_prompt(sim, result)
	if work_policy == POLICY_YOLO and (
		JobSystem.is_shipped(job) or bool(job.get("abandoned", false))
	):
		set_work_policy(sim, POLICY_MANUAL)
	if (
		work_policy == POLICY_YOLO
		and sim.phase == sim.Phase.IN_ROUND
		and work_running
		and _should_auto_ship(sim)
	):
		ship_focused_job(sim)
	if work_policy == POLICY_YOLO and (
		JobSystem.is_shipped(job) or bool(job.get("abandoned", false))
	):
		set_work_policy(sim, POLICY_MANUAL)
	return result


## Spends a prompt on the hardware rather than the work.
func cool_hardware(sim: Node) -> Dictionary:
	if not can_burn(sim):
		return {"ok": false, "reason": "Not working."}
	var result: Dictionary = sim.job_system().run_cooling_prompt(
		sim.run_state,
		burn_rng(sim),
		sim.effect_resolver,
		sim.debug_collect_subscriptions(),
		sim.tuning,
		sim.compute_system(),
		sim.heat_system(),
		sim.economy_system()
	)
	if not result.get("ok", false):
		return result
	work_tick += 1
	finish_prompt(sim, result)
	return result


## Delivers the focused contract now, finished or not.
func ship_focused_job(sim: Node) -> bool:
	if sim.phase != sim.Phase.IN_ROUND or not work_running:
		return false
	var result: Dictionary = sim.job_system().ship_focused_job(sim.run_state)
	if not result.get("ok", false):
		return false
	sim.round_log.append("Shipped %s." % str(result.get("job", {}).get("name", "the contract")))
	_settle_if_resolved(sim)
	return true


func abandon_focused_job(sim: Node) -> bool:
	if sim.phase != sim.Phase.IN_ROUND or not work_running:
		return false
	var result: Dictionary = sim.job_system().abandon_focused_job(sim.run_state)
	if not result.get("ok", false):
		return false
	sim.round_log.append("Walked away from %s." % str(result.get("job", {}).get("name", "the contract")))
	_settle_if_resolved(sim)
	return true


func focus_job(sim: Node, job_id: String) -> bool:
	if sim.phase != sim.Phase.IN_ROUND:
		return false
	if not sim.job_system().set_focus(sim.run_state, job_id):
		return false
	_follow_focused_workflow(sim)
	return true


## The Burn Board edits whichever workflow is active, so focusing a contract
## points the editor at the pipeline that contract is actually worked through.
## Without this, tuning the board mid-job would quietly edit someone else's.
func _follow_focused_workflow(sim: Node) -> void:
	var job: Dictionary = sim.job_system().focused_job(sim.run_state)
	if job.is_empty():
		return
	var workflow_id: String = str(job.get("workflow_id", ""))
	var list: Array = sim.board_system().workflows(sim.run_state)
	for index in range(list.size()):
		if str(list[index].get("id", "")) == workflow_id:
			sim.board_system().set_active_workflow(sim.run_state, index)
			return


func focused_job(sim: Node) -> Dictionary:
	return sim.job_system().focused_job(sim.run_state)


## The contract the machine will boot with when the first BURN opens the
## session: the head of the accepted queue, prepared exactly as `start_work`
## will prepare it. Display only — nothing in the queue is mutated. Empty when
## nothing has been accepted, or once the session is running and `focused_job`
## is the real answer.
func queued_job_preview(sim: Node) -> Dictionary:
	if work_running:
		return {}
	var queue: Array = sim.run_state.business.get("job_queue", [])
	if queue.is_empty() or not queue[0] is Dictionary:
		return {}
	return sim.job_system().prepare_offer_preview(queue[0], sim.run_state, ContentDatabase)


## Seeded from the run and the exact prompt, so a preview and the burn it
## previewed roll the same numbers.
func burn_rng(sim: Node) -> DeterministicRng:
	var stream_seed: int = hash("%d.%d.%d.%d" % [
		sim.run_seed,
		int(sim.run_state.calendar.get("round", 1)),
		int(sim.run_state.calendar.get("prompt", 1)),
		work_tick,
	])
	return DeterministicRng.new(absi(stream_seed) | 1)


## Folds any job that finished this prompt into the contract's quality average,
## exactly once each. Called both mid-session (so the ordinary evaluate/expire
## path always sees settled quality) and again from `end_session` for jobs
## shipped or abandoned without going through `finish_prompt` — the guard
## flag is what keeps a job from being counted by both.
func record_completed_quality(sim: Node, state: RunState) -> void:
	for job in state.business.get("active_jobs", []):
		if not job is Dictionary:
			continue
		if FeatureFlags.is_enabled("ready_to_ship_enabled") and not JobSystem.is_shipped(job):
			continue
		if float(job.get("tokens_remaining", 0.0)) > 0.0:
			continue
		if bool(job.get("_ascension_quality_recorded", false)):
			continue
		# Judged on what the client receives, not what the pipeline produced:
		# unfinished delivery and shipped known bugs both come off first.
		sim.ascension_system().record_job_quality(state, JobSystem.delivered_quality(job))
		job["_ascension_quality_recorded"] = true


## Bookkeeping shared by every action that consumes a prompt.
func finish_prompt(sim: Node, result: Dictionary) -> void:
	for message in result.get("messages", []):
		sim.round_log.append(str(message))
	sim.run_state.update_peaks()
	_advance_prompt(sim, result)
	sim.work_tick_completed.emit()
	if sim.progression_system().check_loss(sim.run_state):
		work_running = false
		sim.round_log.append(
			"%s — the run is over." % str(sim.run_state.flags.get("loss_reason", "Run collapsed"))
		)
		sim._end_run(false)
		sim.work_session_finished.emit({"phase": sim.phase, "summary": last_session_summary})
		return
	if sim.ascension_system().is_active(sim.run_state):
		# A job's quality has to be settled against the contract's average
		# before the contract is judged, not after: judging first and
		# recording second is how a losing final job can win on last round's
		# quality, and a winning one can be refused for it.
		record_completed_quality(sim, sim.run_state)
		var ascension_result: Dictionary = sim.ascension_system().evaluate_prompt(
			sim.run_state, ContentDatabase
		)
		for message in ascension_result.get("messages", []):
			sim.round_log.append(str(message))
		var outcome: String = str(ascension_result.get("outcome", ""))
		if outcome == AscensionSystem.STATUS_COMPLETED:
			work_running = false
			sim._reach_victory(sim.ascension_system().current_contract(sim.run_state, ContentDatabase))
			sim.work_session_finished.emit({"phase": sim.phase, "summary": last_session_summary})
			return
		elif outcome == AscensionSystem.STATUS_FAILED:
			work_running = false
			sim.run_state.flags["loss_reason"] = "Ascension contract failed."
			sim._end_run(false, "ascension_failed")
			sim.work_session_finished.emit({"phase": sim.phase, "summary": last_session_summary})
			return
	elif DepthSystem.is_active(sim.run_state):
		var depth_result: Dictionary = sim.depth_system().evaluate_prompt(sim.run_state)
		for message in depth_result.get("messages", []):
			sim.round_log.append(str(message))
		# Latch only. Forcing end_session here failed every unfinished
		# contract on the desk the moment the target was crossed.
		if bool(depth_result.get("newly_complete", false)):
			sim.run_state.flags["depth_complete_pending"] = true
	var stop: String = _session_stop_reason(result)
	if stop != "":
		_close_session(sim, stop)
	else:
		sim._autosave()


## Shipping or abandoning the last live contract ends the round there and then,
## without spending another prompt on it.
func _settle_if_resolved(sim: Node) -> void:
	for job in sim.run_state.business.get("active_jobs", []):
		if not job is Dictionary:
			continue
		if JobSystem.is_shipped(job) or bool(job.get("abandoned", false)):
			continue
		if FeatureFlags.is_enabled("ready_to_ship_enabled"):
			if int(job.get("prompts_remaining", 0)) > 0:
				sim.work_tick_completed.emit()
				sim._autosave()
				return
		elif float(job.get("tokens_remaining", 0.0)) > 0.0 and int(job.get("prompts_remaining", 0)) > 0:
			sim.work_tick_completed.emit()
			sim._autosave()
			return
	_close_session(sim, "resolved")


## One place the desk actually closes. Ship, abandon, and a resolved burn all
## land here so a latched Deep Burn crossing still opens DEPTH COMPLETE after
## the current contracts settle normally.
func _close_session(sim: Node, reason: String) -> void:
	var depth_pending: bool = bool(sim.run_state.flags.get("depth_complete_pending", false))
	if depth_pending:
		sim._settling_depth = true
	end_session(sim, reason)
	sim._settling_depth = false
	if depth_pending and sim.phase != sim.Phase.RUN_END:
		sim._reach_depth_complete()
	elif depth_pending:
		sim.run_state.flags["depth_complete_pending"] = false
	sim.work_session_finished.emit({"phase": sim.phase, "summary": last_session_summary})


## One burn or cool is one prompt. Prompts are not rationed — the round runs for
## as long as its contracts do — but every one of them ages the deadlines and
## meters the power.
func _advance_prompt(sim: Node, result: Dictionary) -> void:
	if not result.get("ok", true):
		return
	sim.run_state.calendar["prompt"] = int(sim.run_state.calendar["prompt"]) + 1


## A round ends when there is nothing left on the books, and only then. Rent can
## no longer interrupt a contract halfway through, because the bills wait for the
## work to finish rather than the other way round.
func _session_stop_reason(result: Dictionary) -> String:
	if not result.get("ok", true):
		return "collapsed"
	if result.get("all_resolved", false):
		return "resolved"
	return ""


func _should_auto_ship(sim: Node) -> bool:
	var job: Dictionary = sim.job_system().focused_job(sim.run_state)
	if not JobSystem.is_ready(job):
		return false
	if work_policy == POLICY_YOLO:
		return JobSystem.delivered_quality(job) >= float(job.get("quality_threshold", 0.0))
	return true


func set_work_policy(sim: Node, policy: String) -> void:
	if policy != POLICY_MANUAL and policy != POLICY_AUTO and policy != POLICY_YOLO:
		return
	work_policy = policy
	sim.run_state.flags["work_policy"] = policy


func yolo_unlocked(sim: Node) -> bool:
	if not FeatureFlags.is_enabled("yolo_mode_enabled"):
		return false
	return JobSystem.location_tier(sim.run_state, ContentDatabase) >= 3


func _execute_tick(sim: Node) -> Dictionary:
	var tick_rng: DeterministicRng = sim.rng.derive("work_%d" % work_tick)
	work_tick += 1
	return sim.job_system().run_production_tick(
		sim.run_state,
		tick_rng,
		sim.effect_resolver,
		sim.debug_collect_subscriptions(),
		sim.tuning,
		sim.compute_system(),
		sim.heat_system(),
		sim.economy_system(),
		sim.board_system(),
		work_policy != POLICY_YOLO
	)


## Settles the round. Every contract taken this round is resolved here — nothing
## carries into the next round, which is what makes "the round is over" mean the
## same thing every time and lets the bills follow the work rather than cut
## across it.
func end_session(sim: Node, reason: String) -> void:
	var completed: Array = []
	var failed: Array = []
	for job in sim.run_state.business.get("active_jobs", []):
		if JobSystem.is_shipped(job) or (
			not FeatureFlags.is_enabled("ready_to_ship_enabled")
			and float(job.get("tokens_remaining", 0.0)) <= 0.0
		):
			completed.append(job)
		else:
			failed.append(job)

	if sim.ascension_system().is_active(sim.run_state):
		# Covers jobs settled by ship/abandon, which never pass through
		# `finish_prompt`. Jobs already recorded there are skipped.
		record_completed_quality(sim, sim.run_state)

	var messages: Array[String] = []
	var reward: float = 0.0
	if not completed.is_empty():
		var completed_payout: Dictionary = sim.job_system().finalize_completed_jobs(
			sim.run_state, completed, sim.effect_resolver, sim.debug_collect_subscriptions(),
			sim.tuning, sim.economy_system(), messages, sim.rng
		)
		reward += float(completed_payout.get("reward", 0.0))
	if not failed.is_empty():
		var failed_payout: Dictionary = sim.job_system().finalize_failed_jobs(
			sim.run_state, failed, sim.effect_resolver, sim.debug_collect_subscriptions(),
			sim.tuning, sim.economy_system(), ContentDatabase, messages, sim.rng
		)
		reward += float(failed_payout.get("reward", 0.0))
	for message in messages:
		sim.round_log.append(str(message))
	if reward > 0.0:
		sim.round_log.append("Paid %s for delivered work." % NumberFormat.format_cash(reward))
	elif not completed.is_empty() or not failed.is_empty():
		sim.round_log.append("No payout — contracts missed deadline or quality bar.")
	# Wrapper (and anything else that spawns a status on payout) only reaches
	# the next round.started once the cached subscription list is rebuilt.
	sim.debug_invalidate_subscriptions()

	_build_session_summary(sim, completed, failed, reward, reason)

	for job in failed:
		EventBus.emit_event(EventBus.EVENT_JOB_FAILED, {"job_id": job.get("id", "")})
	sim.run_state.statistics["completed_jobs"] = int(sim.run_state.statistics.get("completed_jobs", 0)) + completed.size()
	# What the last delivered work was worth, so a perk paying "a percentage of
	# the job" has a figure to take a percentage of. A flat sum instead means the
	# same perk is a lifeline in the bedroom and invisible on the moon.
	if reward > 0.0:
		sim.run_state.statistics["last_job_reward"] = reward
	sim.run_state.statistics["failed_jobs"] = int(sim.run_state.statistics.get("failed_jobs", 0)) + failed.size()
	sim.achievement_system().evaluate_tick(sim.run_state, ContentDatabase)
	last_session_summary["reputation_delta"] = settle_reputation(sim, completed, failed)
	sim.run_state.business["active_jobs"] = []
	sim.run_state.business["active_job"] = {}
	sim.run_state.business["focused_job_id"] = ""
	set_work_policy(sim, POLICY_MANUAL)
	# New board next round, without rerolling on every prompt.
	sim.run_state.business["job_board_seq"] = int(sim.run_state.business.get("job_board_seq", 0)) + 1
	work_running = false

	# A won run is not re-judged on its way out: the check would only write a
	# loss reason onto a victory that `_end_run` then refuses to act on.
	if not sim._settling_victory and sim.progression_system().check_loss(sim.run_state):
		sim._end_run(false)
		return

	EventBus.emit_event(EventBus.EVENT_REWARD_CALCULATED, {"amount": reward})
	# Bills settle before the shop opens. Spending money that rent already has a
	# claim on is how a player gets evicted holding a new GPU.
	sim._round_end_pending = false
	sim._end_round()
	# A chapter win settles the round (next calendar, maybe a draft) and then
	# `_reach_victory` flips to RUN_END. Saving here would write a live next
	# round under the verdict; Continue from title then resurrected a run the
	# overlay had just called closed. The victory path saves once, after the
	# phase is honest. Depth complete does the same: settle, then overlay.
	if not sim._settling_victory and not sim._settling_depth:
		sim._autosave()


## What the round did to the run's standing, and the reason it did it. A missed
## deadline still costs a flat two per contract; delivered work is now paid in
## reputation by how good it was, so clearing a client's bar by a mile is worth
## more than scraping under it and taking the reduced fee.
func settle_reputation(sim: Node, completed: Array, failed: Array) -> float:
	var before: float = float(sim.run_state.business.get("reputation", 0.0))
	if not failed.is_empty():
		sim.run_state.business["reputation"] = maxf(-10.0, before - 2.0 * float(failed.size()))
		# Rule-changer: a failed job is not a total loss — whatever went wrong
		# still teaches the rig something.
		if "unlock.rule_failed_research" in Array(sim.run_state.build.get("meta_unlocks", [])):
			sim.run_state.compute["efficiency_base"] = (
				float(sim.run_state.compute.get("efficiency_base", 1.0)) + 0.01 * float(failed.size())
			)
		return float(sim.run_state.business["reputation"]) - before
	if completed.is_empty():
		return 0.0
	var cfg: Dictionary = ContentDatabase.balance.get("job_scaling", {}).get("reputation", {})
	var quality: float = 0.0
	var threshold: float = 0.0
	for job in completed:
		quality += float(job.get("quality", 0.0))
		threshold += float(job.get("quality_threshold", 0.0))
	quality /= float(completed.size())
	threshold /= float(completed.size())
	var gain: float = float(cfg.get("session_gain_under", 0))
	if quality >= threshold + float(cfg.get("excellent_margin", 20)):
		gain = float(cfg.get("session_gain_excellent", 3))
	elif quality >= threshold:
		gain = float(cfg.get("session_gain_met", 2))
	sim.run_state.business["reputation"] = before + gain
	if gain <= 0.0:
		sim.round_log.append("Delivered under the client's quality bar. Word does not get around.")
	return gain


## Both surges last one batch, so a second press in the same prompt is refused
## rather than stacked.
func boost(sim: Node) -> bool:
	if sim.phase != sim.Phase.IN_ROUND or not work_running or boost_engaged(sim):
		return false
	_apply_boost(sim)
	return true


## Whether this prompt's batch is already running hot off a boost.
func boost_engaged(sim: Node) -> bool:
	for entry in sim.run_state.compute.get("rate_modifiers", []):
		if entry is Dictionary and str(entry.get("source", "")) == "boost":
			return true
	return false


func _apply_boost(sim: Node) -> void:
	if boost_engaged(sim):
		return
	sim.run_state.add_rate_modifier(1.35, 1, "boost")
	var capacity: float = maxf(1.0, float(sim.run_state.compute.get("heat_capacity", 100.0)))
	var boost_heat: float = HeatSystem.boost_heat_for(capacity)
	sim.heat_system().add_heat(sim.run_state, boost_heat)
	sim.round_log.append("BOOST engaged: +35%% token rate, +%d heat." % int(round(boost_heat)))


## Snapshot of the round just finished, for the debrief screen. Every contract
## the round took is in one of the two lists, so the headline can never claim a
## success the player did not have.
func _build_session_summary(
	sim: Node, completed_jobs: Array, failed_jobs: Array, reward: float, reason: String
) -> void:
	var jobs: Array = completed_jobs + failed_jobs
	var completed: int = completed_jobs.size()
	var failed: int = failed_jobs.size()
	var tokens_done: float = 0.0
	var quality_total: float = 0.0
	var threshold_total: float = 0.0
	var multiplier_total: float = 0.0
	var paid_jobs: int = 0
	var bugs: int = 0
	var hidden_bugs: int = 0
	var discovered_bugs: int = 0
	var early_bonus_total: float = 0.0
	var early_jobs: int = 0
	for job in completed_jobs:
		var bonus: float = float(job.get("early_bonus_pct", 0.0))
		if bonus > 0.0:
			early_bonus_total += bonus
			early_jobs += 1
	for job in jobs:
		var requirement: float = float(job.get("token_requirement", 0.0))
		tokens_done += requirement - maxf(0.0, float(job.get("tokens_remaining", 0.0)))
		quality_total += float(job.get("quality", 0.0))
		threshold_total += float(job.get("quality_threshold", 0.0))
		if job.has("quality_multiplier"):
			multiplier_total += float(job["quality_multiplier"])
			paid_jobs += 1
		bugs += int(job.get("known_bugs", job.get("bugs_this_job", 0)))
		hidden_bugs += int(job.get("hidden_bugs", 0))
		discovered_bugs += int(job.get("hidden_bugs_discovered", 0))
	var cash_after: float = float(sim.run_state.economy.get("cash", 0.0))
	last_session_summary = {
		# Delivering something is the bar for a good round. A round that
		# delivered nothing is not a success, whatever else happened in it.
		"success": completed > 0 and failed == 0,
		"completed": completed,
		"failed": failed,
		"reward": reward,
		"spent": maxf(0.0, session_cash_start + reward - cash_after),
		"cash_after": cash_after,
		"tokens_processed": tokens_done,
		"avg_quality": quality_total / maxf(1.0, float(jobs.size())),
		"avg_quality_threshold": threshold_total / maxf(1.0, float(jobs.size())),
		"quality_multiplier": multiplier_total / float(paid_jobs) if paid_jobs > 0 else 1.0,
		"reputation_delta": 0.0,
		"bugs": bugs,
		"hidden_bugs": hidden_bugs,
		"discovered_bugs": discovered_bugs,
		"ticks": work_tick,
		"tokens_per_tick": tokens_done / maxf(1.0, float(work_tick)),
		"round": int(sim.run_state.calendar.get("round", 1)),
		"prompts_used": sim.prompts_used_this_round(),
		"job_slots": sim.job_slots(),
		"early_jobs": early_jobs,
		"early_bonus_pct": early_bonus_total / float(early_jobs) if early_jobs > 0 else 0.0,
		"stop_reason": reason,
		"behind_on_contract": _behind_on_contract(sim),
		"workflows": _workflow_mastery_lines(sim),
		"mastery_events": _workflow_mastery_events(jobs),
	}


func _workflow_mastery_lines(sim: Node) -> Array:
	var lines: Array = []
	for workflow in sim.workflows():
		if not workflow is Dictionary:
			continue
		lines.append({
			"name": str(workflow.get("name", "Workflow")),
			"output_mult": float(workflow.get("output_mult", 1.0)),
			"quality_mult": float(workflow.get("quality_mult", 1.0)),
			"thermal_mult": float(workflow.get("thermal_mult", 1.0)),
		})
	return lines


func _workflow_mastery_events(jobs: Array) -> Array:
	var events: Array = []
	for job in jobs:
		if not job is Dictionary:
			continue
		var report: Dictionary = Dictionary(job.get("mastery_report", {}))
		if bool(report.get("applied", false)):
			events.append(report.duplicate(true))
	return events


## Whether the contract is further behind than the year has left to give it. A
## run three quarters through the calendar with a quarter of the burn done is
## losing, however well the individual round went, and the debrief says so.
func _behind_on_contract(sim: Node) -> bool:
	var progress: Dictionary = sim.ascension_progress()
	if progress.is_empty():
		return false
	var deadline: int = maxi(1, int(progress.get("deadline_round", sim.ROUNDS_PER_RUN)))
	var elapsed: float = clampf(
		float(int(sim.run_state.calendar.get("round", 1))) / float(deadline), 0.0, 1.0
	)
	return elapsed >= 0.5 and float(progress.get("burn_ratio", 0.0)) < elapsed * 0.75


func fire_queued_options(sim: Node) -> void:
	_fire_queued_options(sim)


func follow_focused_workflow(sim: Node) -> void:
	_follow_focused_workflow(sim)


func settle_if_resolved(sim: Node) -> void:
	_settle_if_resolved(sim)


func close_session(sim: Node, reason: String) -> void:
	_close_session(sim, reason)


func advance_prompt(sim: Node, result: Dictionary) -> void:
	_advance_prompt(sim, result)


func session_stop_reason(result: Dictionary) -> String:
	return _session_stop_reason(result)


func should_auto_ship(sim: Node) -> bool:
	return _should_auto_ship(sim)


func execute_tick(sim: Node) -> Dictionary:
	return _execute_tick(sim)


func apply_boost(sim: Node) -> void:
	_apply_boost(sim)


func build_session_summary(
	sim: Node, completed_jobs: Array, failed_jobs: Array, reward: float, reason: String
) -> void:
	_build_session_summary(sim, completed_jobs, failed_jobs, reward, reason)


func behind_on_contract(sim: Node) -> bool:
	return _behind_on_contract(sim)
