class_name JobSystem
extends RefCounted

const DEFAULT_TICK_SECONDS: float = 1.0


func generate_offers(run_state: RunState, rng: DeterministicRng, content_db: Node, tuning: Dictionary) -> void:
	var count: int = clampi(int(run_state.business.get("demand", 3.0)), 1, 5)
	var round_number: int = int(run_state.calendar.get("round", 1))
	var max_tier: int = _player_max_job_tier(run_state, round_number, content_db)
	var eligible: Array = _collect_eligible_jobs(content_db, round_number, max_tier)
	if eligible.is_empty():
		run_state.business["job_offers"] = []
		return
	eligible = rng.shuffle(eligible)
	var offers: Array = []
	var index: int = 0
	while offers.size() < count:
		var job_def: JobDefinition = eligible[index % eligible.size()]
		# Each offer gets its own rng stream so repeated definitions still
		# differ, and so the board is reproducible for a given seed.
		var offer_rng: DeterministicRng = rng.derive("offer_%d_%s" % [index, job_def.id])
		offers.append(_scale_job(job_def, round_number, content_db, tuning, run_state, offer_rng))
		index += 1
		# Only reuse definitions once the pool is exhausted.
		if index >= eligible.size() and offers.size() < count:
			eligible = rng.shuffle(eligible)
	run_state.business["job_offers"] = offers


## The capstone is a round-twelve headliner, not the whole board: overtime still
## has rent to pay, so the ordinary pool stays open alongside it rather than the
## run being left with one impossible contract and no way to earn.
func _collect_eligible_jobs(content_db: Node, round_number: int, max_tier: int) -> Array:
	var eligible: Array = []
	for job_def in content_db.jobs:
		if round_number < 12 and job_def.id == "job.capstone_simulation":
			continue
		if _job_tier(job_def, content_db) > max_tier:
			continue
		eligible.append(job_def)
	if eligible.is_empty():
		var fallback_pool: Array = content_db.jobs.duplicate()
		fallback_pool.sort_custom(func(a: JobDefinition, b: JobDefinition) -> bool:
			return _job_tier(a, content_db) < _job_tier(b, content_db)
		)
		for job_def in fallback_pool:
			if _job_tier(job_def, content_db) > max_tier:
				continue
			if round_number < 12 and job_def.id == "job.capstone_simulation":
				continue
			eligible.append(job_def)
	return eligible


func accept_job(run_state: RunState, job_id: String) -> bool:
	for i in range(run_state.business.get("job_offers", []).size()):
		var offer: Dictionary = run_state.business["job_offers"][i]
		if offer.get("id", "") != job_id:
			continue
		var queued: Dictionary = offer.duplicate(true)
		run_state.business["job_offers"].remove_at(i)
		run_state.business["job_queue"].append(queued)
		return true
	return false


## Everything the player accepted this round is prepared here. A round runs until
## all of it resolves, so nothing is ever half-prepared from a previous round.
func begin_work_session(run_state: RunState, content_db: Node) -> bool:
	var active_jobs: Array = run_state.business.get("active_jobs", []).duplicate()
	for offer in run_state.business.get("job_queue", []):
		active_jobs.append(_prepare_job(offer, run_state, content_db))
	if active_jobs.is_empty():
		return false
	run_state.business["active_jobs"] = active_jobs
	run_state.business["job_queue"] = []
	run_state.business["active_job"] = active_jobs[0] if active_jobs.size() == 1 else {}
	_refresh_focus(run_state)
	return true


## The contract the board screen is pointed at. It always gets a lane when a
## prompt is burned; whether anything else does depends on how many machines the
## rig has.
func focused_job(run_state: RunState) -> Dictionary:
	var focus_id: String = str(run_state.business.get("focused_job_id", ""))
	for job in run_state.business.get("active_jobs", []):
		if job is Dictionary and str(job.get("id", "")) == focus_id and _is_in_progress(job):
			return job
	return {}


func set_focus(run_state: RunState, job_id: String) -> bool:
	for job in run_state.business.get("active_jobs", []):
		if job is Dictionary and str(job.get("id", "")) == job_id and _is_in_progress(job):
			run_state.business["focused_job_id"] = job_id
			return true
	return false


## Keeps the focus pointed at something workable, so finishing a contract moves
## the board onto the next one instead of stalling.
func _refresh_focus(run_state: RunState) -> void:
	if not focused_job(run_state).is_empty():
		return
	for job in run_state.business.get("active_jobs", []):
		if job is Dictionary and _is_in_progress(job):
			run_state.business["focused_job_id"] = str(job.get("id", ""))
			return
	run_state.business["focused_job_id"] = ""


func _is_in_progress(job: Dictionary) -> bool:
	if float(job.get("tokens_remaining", 0.0)) <= 0.0:
		return false
	return int(job.get("prompts_remaining", 0)) >= 0


## The contracts one prompt advances. One machine works one contract, so the
## rig's floor slots are how many lanes run side by side: the focused contract
## always takes a lane, and the rest go to whatever is nearest its deadline.
## Running two contracts at once does not double throughput — it splits the same
## batch — but it does move two deadlines instead of one.
func burn_lane_jobs(run_state: RunState) -> Array:
	var focus: Dictionary = focused_job(run_state)
	if focus.is_empty():
		return []
	var lanes: Array = [focus]
	var focus_id: String = str(focus.get("id", ""))
	var waiting: Array = []
	for job in run_state.business.get("active_jobs", []):
		if not job is Dictionary or not _is_in_progress(job):
			continue
		if str(job.get("id", "")) == focus_id:
			continue
		waiting.append(job)
	waiting.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("prompts_remaining", 0)) < int(b.get("prompts_remaining", 0))
	)
	var slots: int = ComputeSystem.job_slots(run_state)
	for job in waiting:
		if lanes.size() >= slots:
			break
		lanes.append(job)
	return lanes


## The size of the batch this prompt can push through the board. Throughput stays
## a property of the rig: the board decides what a batch achieves, not how big
## it is.
func prepare_batch(
	run_state: RunState,
	rng: DeterministicRng,
	effect_resolver: EffectResolver,
	subscriptions: Array,
	tuning: Dictionary,
	compute_system: ComputeSystem
) -> float:
	compute_system.recalculate(run_state, effect_resolver, subscriptions, rng)
	var sustained_rate: float = float(run_state.compute.get("token_rate", 0.0))
	var token_rate: float = sustained_rate * float(tuning.get("token_multiplier", 1.0))
	effect_resolver.begin_action("prompt.started")
	var mod_ctx := ModifierContext.new("prompt.started", run_state)
	mod_ctx.rng = rng.derive("prompt.started")
	mod_ctx.set_value("compute.token_rate", token_rate)
	effect_resolver.dispatch("prompt.started", mod_ctx, subscriptions)
	token_rate = float(mod_ctx.get_value("compute.token_rate", token_rate))
	var scaling: Dictionary = ContentDatabase.balance.get("job_scaling", {})
	var burst_cap: float = float(scaling.get("max_burst_multiplier", 8.0))
	# However the perks stack, one prompt can only ever be worth so many prompts
	# of the rig the player actually owns.
	token_rate = minf(token_rate, sustained_rate * burst_cap)
	# The burst belongs to this prompt only. Leaving it in the state would show it
	# as the player's rate and, worse, unlock contract tiers off a single spike.
	run_state.compute["token_rate"] = sustained_rate
	run_state.compute["prompt_rate"] = token_rate
	return token_rate


## Resolves the pipeline against the focused contract without applying anything,
## for the board screen's readout of what BURN TOKENS would do.
func inspect_burn(
	run_state: RunState,
	rng: DeterministicRng,
	effect_resolver: EffectResolver,
	subscriptions: Array,
	tuning: Dictionary,
	compute_system: ComputeSystem,
	board_system: BoardSystem,
	stage_limit: int = -1
) -> Dictionary:
	var job: Dictionary = focused_job(run_state)
	if job.is_empty():
		return {"ok": false, "reason": "No contract in progress."}
	var batch: float = prepare_batch(run_state, rng, effect_resolver, subscriptions, tuning, compute_system)
	return board_system.resolve_burn(run_state, job, batch, rng, effect_resolver, subscriptions, stage_limit)


## One prompt of work: a batch through the board for every contract the rig can
## run in parallel, then the consequences.
##
## `stage_limit` stops the pipeline early — KILL PROCESS — which keeps whatever
## the completed stages produced and loses the rest of the batch.
func run_burn(
	run_state: RunState,
	rng: DeterministicRng,
	effect_resolver: EffectResolver,
	subscriptions: Array,
	tuning: Dictionary,
	compute_system: ComputeSystem,
	heat_system: HeatSystem,
	economy_system: EconomySystem,
	board_system: BoardSystem,
	stage_limit: int = -1,
	emit_events: bool = true
) -> Dictionary:
	var active_jobs: Array = run_state.business.get("active_jobs", [])
	if active_jobs.is_empty():
		return {"ok": false, "reason": "No active jobs"}
	var lanes: Array = burn_lane_jobs(run_state)
	if lanes.is_empty():
		return {"ok": false, "reason": "No contract in progress."}

	var messages: Array[String] = []
	var batch: float = prepare_batch(run_state, rng, effect_resolver, subscriptions, tuning, compute_system)
	if emit_events:
		EventBus.emit_event("tokens.generated", {"amount": batch})

	# The batch is the rig's output, not each contract's, so parallel lanes share
	# it. Two machines finish two contracts in the time one machine finishes one.
	var share: float = batch / float(lanes.size())
	var primary: Dictionary = {}
	var lane_reports: Array = []
	for job in lanes:
		var lane_rng: DeterministicRng = rng.derive("lane.%s" % str(job.get("id", "")))
		var lane_burn: Dictionary = board_system.resolve_burn(
			run_state, job, share, lane_rng, effect_resolver, subscriptions, stage_limit
		)
		if not lane_burn.get("ok", false):
			# The focused lane failing means the pipeline itself cannot run, which
			# is a refusal rather than a wasted prompt.
			if primary.is_empty():
				return {"ok": false, "reason": str(lane_burn.get("reason", "The pipeline produced nothing."))}
			continue
		_apply_burn(run_state, job, lane_burn, rng, messages, emit_events, effect_resolver, subscriptions)
		_roll_job_risks(
			run_state, job, lane_rng, messages, float(lane_burn.get("bug_chance_mult", 1.0))
		)
		if primary.is_empty():
			primary = lane_burn
		lane_reports.append({
			"job_id": str(job.get("id", "")),
			"name": str(job.get("name", "Contract")),
			"workflow_name": str(lane_burn.get("workflow_name", "")),
			"progress_tokens": float(lane_burn.get("progress_tokens", 0.0)),
			"quality": float(lane_burn.get("quality", 0.0)),
			"tokens_remaining": float(job.get("tokens_remaining", 0.0)),
			"prompts_remaining": int(job.get("prompts_remaining", 0)),
		})
	if lane_reports.size() > 1:
		messages.append("Ran %d contracts in parallel — the batch was split %d ways." % [
			lane_reports.size(), lane_reports.size()
		])
	primary = primary.duplicate(true)
	primary["lanes"] = lane_reports
	primary["lane_count"] = lane_reports.size()

	var prompt_result: Dictionary = end_prompt(
		run_state, subscriptions, effect_resolver, rng, tuning,
		compute_system, heat_system, economy_system, messages
	)
	prompt_result["burn"] = primary
	return prompt_result


## A prompt spent on the hardware instead of the work: the deadlines still run,
## but the rig comes back down out of the danger band.
func run_cooling_prompt(
	run_state: RunState,
	rng: DeterministicRng,
	effect_resolver: EffectResolver,
	subscriptions: Array,
	tuning: Dictionary,
	compute_system: ComputeSystem,
	heat_system: HeatSystem,
	economy_system: EconomySystem
) -> Dictionary:
	if run_state.business.get("active_jobs", []).is_empty():
		return {"ok": false, "reason": "No active jobs"}
	var messages: Array[String] = []
	compute_system.recalculate(run_state, effect_resolver, subscriptions, rng)
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	var vented: float = float(run_state.compute.get("heat", 0.0)) * clampf(
		float(heat_cfg.get("vent_ratio", 0.45)), 0.0, 1.0
	)
	run_state.compute["heat"] = maxf(0.0, float(run_state.compute.get("heat", 0.0)) - vented)
	messages.append("Vented %d heat. The fans have earned their keep." % int(round(vented)))
	var result: Dictionary = end_prompt(
		run_state, subscriptions, effect_resolver, rng, tuning,
		compute_system, heat_system, economy_system, messages
	)
	result["vented"] = vented
	return result


## Legacy auto-drive: burns the whole pipeline for the focused contract. Used by
## headless runs and the batch balance sweeps, where nobody is there to press
## BURN TOKENS.
func run_production_tick(
	run_state: RunState,
	rng: DeterministicRng,
	effect_resolver: EffectResolver,
	subscriptions: Array,
	tuning: Dictionary,
	compute_system: ComputeSystem,
	heat_system: HeatSystem,
	economy_system: EconomySystem,
	board_system: BoardSystem = null
) -> Dictionary:
	if board_system == null:
		board_system = BoardSystem.new()
	board_system.ensure_board(run_state, ContentDatabase)
	_refresh_focus(run_state)
	board_system.compact_for_job(run_state, focused_job(run_state))
	# The auto-drive stands in for a player, and a player watching the rig climb
	# into the danger band would reach for COOL rather than burn another batch.
	if _should_cool(run_state):
		return run_cooling_prompt(
			run_state, rng, effect_resolver, subscriptions, tuning,
			compute_system, heat_system, economy_system
		)
	if focused_job(run_state).is_empty():
		# Nothing workable left; still close the prompt so deadlines and bills
		# move and the round can settle.
		var messages: Array[String] = []
		return end_prompt(
			run_state, subscriptions, effect_resolver, rng, tuning,
			compute_system, heat_system, economy_system, messages
		)
	return run_burn(
		run_state, rng, effect_resolver, subscriptions, tuning,
		compute_system, heat_system, economy_system, board_system
	)


func _should_cool(run_state: RunState) -> bool:
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	var capacity: float = maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))
	var ratio: float = float(run_state.compute.get("heat", 0.0)) / capacity
	if ratio < float(heat_cfg.get("throttle_ratio", 0.8)):
		return false
	# Only worth a round if venting would actually buy headroom.
	return float(heat_cfg.get("vent_ratio", 0.45)) > 0.0


func _apply_burn(
	run_state: RunState,
	job: Dictionary,
	burn: Dictionary,
	rng: DeterministicRng,
	messages: Array[String],
	emit_events: bool,
	effect_resolver: EffectResolver = null,
	subscriptions: Array = []
) -> void:
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var progress: float = minf(float(job.get("tokens_remaining", 0.0)), float(burn.get("progress_tokens", 0.0)))
	job["tokens_remaining"] = maxf(0.0, float(job.get("tokens_remaining", 0.0)) - progress)

	var tokens_burned: float = float(burn.get("tokens", 0.0))
	run_state.statistics["lifetime_tokens"] = float(run_state.statistics.get("lifetime_tokens", 0.0)) + tokens_burned
	run_state.statistics["peak_prompt_tokens"] = maxf(
		float(run_state.statistics.get("peak_prompt_tokens", 0.0)), tokens_burned
	)
	if emit_events:
		EventBus.emit_event("tokens.consumed", {"amount": tokens_burned})

	# Shipped work is worth something even from a pipeline that generates no
	# quality of its own, so a throughput build lands short of the bar rather
	# than at zero.
	var scaling: Dictionary = ContentDatabase.balance.get("job_scaling", {})
	var base_ratio: float = float(scaling.get("board", {}).get("base_quality_ratio", 0.45))
	var quality_gain: float = float(burn.get("quality", 0.0))
	quality_gain += (progress / requirement) * 100.0 * base_ratio * float(run_state.compute.get("efficiency", 1.0))
	job["quality"] = clampf(float(job.get("quality", 0.0)) + quality_gain, 0.0, 150.0)
	# Perks get a look at the figure the contract will actually be judged on,
	# after the board and the passive share have both been counted.
	if effect_resolver != null and not subscriptions.is_empty():
		effect_resolver.begin_action("quality.calculated.%s" % job.get("id", ""))
		var mod_ctx := ModifierContext.new("quality.calculated", run_state)
		mod_ctx.rng = rng.derive("quality.calculated")
		mod_ctx.job = job
		mod_ctx.set_value("job.quality", float(job["quality"]))
		effect_resolver.dispatch("quality.calculated", mod_ctx, subscriptions)
		job["quality"] = clampf(float(mod_ctx.get_value("job.quality", job["quality"])), 0.0, 150.0)
	if emit_events:
		EventBus.emit_event("quality.calculated", {"value": job["quality"]})

	job["known_bugs"] = maxi(0, int(burn.get("known_bugs", 0)))
	job["hidden_bugs"] = maxi(0, int(burn.get("hidden_bugs", 0)))
	job["bugs_this_job"] = int(job["known_bugs"]) + int(job["hidden_bugs"])
	if int(burn.get("bugs_added", 0)) > 0 or int(burn.get("hidden_added", 0)) > 0:
		if emit_events:
			EventBus.emit_event("bug.generated")
	if int(burn.get("revealed", 0)) > 0:
		messages.append("Tests surfaced %d hidden bug(s)." % int(burn.get("revealed", 0)))
	if int(burn.get("fixed", 0)) > 0:
		messages.append("Fixed %d bug(s)." % int(burn.get("fixed", 0)))

	var scope_tokens: float = float(burn.get("scope_tokens", 0.0))
	if scope_tokens > 0.0:
		job["token_requirement"] = requirement + scope_tokens
		job["tokens_remaining"] = float(job.get("tokens_remaining", 0.0)) + scope_tokens

	run_state.compute["heat"] = clampf(
		float(run_state.compute.get("heat", 0.0)) + float(burn.get("heat", 0.0)), 0.0, 200.0
	)
	var cost: float = float(burn.get("cost", 0.0))
	if cost > 0.0:
		run_state.economy["cash"] = float(run_state.economy.get("cash", 0.0)) - cost
		run_state.economy["costs_this_round"] = float(run_state.economy.get("costs_this_round", 0.0)) + cost

	for message in burn.get("messages", []):
		messages.append(str(message))
	if bool(burn.get("truncated", false)):
		messages.append("Process killed mid-batch. The rest of the tokens are gone.")


## Contract-side risk: revisions, defects the pipeline never noticed, and the
## client remembering another feature they always wanted.
## `bug_chance_mult` is the workflow's verdict on this contract: a pipeline that
## answers what the job asked for makes defects rarer, and one that ignores it
## makes them routine.
func _roll_job_risks(
	run_state: RunState,
	job: Dictionary,
	rng: DeterministicRng,
	messages: Array[String],
	bug_chance_mult: float = 1.0
) -> void:
	if not _is_in_progress(job):
		return
	if rng.next_float() < float(job.get("revision_risk", 0.1)):
		var creep_pct: float = float(job.get("scope_creep_pct", 0.05))
		job["tokens_remaining"] = float(job.get("tokens_remaining", 0.0)) + float(job.get("token_requirement", 0.0)) * creep_pct
		job["deadline_prompts"] = int(job.get("deadline_prompts", 4)) + 1
		job["prompts_remaining"] = int(job.get("prompts_remaining", 0)) + 1
		messages.append("%s: scope creep added tokens." % job.get("name", "Job"))

	# Defects the pipeline generated on its own are visible; the ones the
	# contract itself hides are not, until something tests for them.
	if rng.next_float() < float(job.get("bug_chance", 0.12)) * maxf(0.0, bug_chance_mult):
		job["hidden_bugs"] = int(job.get("hidden_bugs", 0)) + 1
		job["bugs_this_job"] = int(job.get("known_bugs", 0)) + int(job["hidden_bugs"])
		EventBus.emit_event("bug.generated")

	_roll_feature_creep(job, rng, messages)


func _roll_feature_creep(job: Dictionary, rng: DeterministicRng, messages: Array[String]) -> void:
	for rule in Array(job.get("board_rules", [])):
		if not rule is Dictionary or str(rule.get("type", "")) != BoardSystem.RULE_FEATURE_CREEP:
			continue
		if rng.next_float() >= float(rule.get("chance", 0.0)):
			continue
		var features: Array = Array(rule.get("features", []))
		var added: Array = Array(job.get("features_added", []))
		var remaining: Array = []
		for feature in features:
			if not (str(feature) in added):
				remaining.append(str(feature))
		if remaining.is_empty():
			continue
		var picked: String = str(rng.pick(remaining))
		added.append(picked)
		job["features_added"] = added
		var extra: float = float(job.get("token_requirement", 0.0)) * float(rule.get("value", 0.05))
		job["token_requirement"] = float(job.get("token_requirement", 0.0)) + extra
		job["tokens_remaining"] = float(job.get("tokens_remaining", 0.0)) + extra
		messages.append("Client added a requirement: %s." % picked)


## Closes the prompt for every contract on the books, not just the ones that got
## a lane: a deadline does not pause because attention went elsewhere.
func end_prompt(
	run_state: RunState,
	subscriptions: Array,
	effect_resolver: EffectResolver,
	rng: DeterministicRng,
	tuning: Dictionary,
	compute_system: ComputeSystem,
	heat_system: HeatSystem,
	economy_system: EconomySystem,
	messages: Array[String]
) -> Dictionary:
	var active_jobs: Array = run_state.business.get("active_jobs", [])
	for job in active_jobs:
		if not job is Dictionary:
			continue
		if float(job.get("tokens_remaining", 0.0)) <= 0.0:
			continue
		if int(job.get("prompts_remaining", 0)) < 0:
			continue
		job["prompts_remaining"] = int(job.get("prompts_remaining", 1)) - 1
		job["time_remaining_ratio"] = maxf(
			0.0, float(job.get("prompts_remaining", 0)) / maxf(1.0, float(job.get("deadline_prompts", 4)))
		)
		if float(job.get("tokens_remaining", 0.0)) <= 0.0:
			EventBus.emit_event("job.completed", {"job_id": job.get("id", "")})
		elif int(job.get("prompts_remaining", 0)) < 0:
			messages.append("%s: deadline missed." % job.get("name", "Job"))

	run_state.business["active_jobs"] = active_jobs
	run_state.business["active_job"] = active_jobs[0] if active_jobs.size() == 1 else {}

	# Expire this prompt's temporary boosts before heat is processed, so a
	# throttle raised here still applies to the prompt it is warning about.
	run_state.tick_rate_modifiers()
	run_state.tick_cloud_burst()
	messages.append_array(heat_system.process_prompt(run_state, subscriptions, effect_resolver, rng))
	# Heat may have added a throttle modifier; recalculate so the HUD's sustained
	# rate matches what the next prompt will actually use.
	compute_system.recalculate(run_state, effect_resolver, subscriptions, rng)
	economy_system.process_pending_bills(run_state)
	economy_system.accrue_prompt_costs(run_state, tuning)
	_refresh_focus(run_state)

	# Single counting pass so each job is counted exactly once, including
	# jobs that were already resolved before this prompt.
	var completed_count: int = 0
	var failed_count: int = 0
	for job in active_jobs:
		if float(job.get("tokens_remaining", 0.0)) <= 0.0:
			completed_count += 1
		elif int(job.get("prompts_remaining", 0)) < 0:
			failed_count += 1

	return {
		"ok": true,
		"all_resolved": completed_count + failed_count >= active_jobs.size(),
		"all_completed": completed_count >= active_jobs.size(),
		"any_failed": failed_count > 0,
		"completed_count": completed_count,
		"failed_count": failed_count,
		"total_jobs": active_jobs.size(),
		"messages": messages,
	}


## Delivers the focused contract as it stands. Anything unfinished is delivered
## unfinished, which is a decision the player is allowed to make.
func ship_focused_job(run_state: RunState) -> Dictionary:
	var job: Dictionary = focused_job(run_state)
	if job.is_empty():
		return {"ok": false, "reason": "No contract in progress."}
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var remaining: float = maxf(0.0, float(job.get("tokens_remaining", 0.0)))
	job["shipped_progress"] = clampf(1.0 - remaining / requirement, 0.0, 1.0)
	job["shipped_unfinished"] = remaining > 0.0
	job["tokens_remaining"] = 0.0
	EventBus.emit_event("job.completed", {"job_id": job.get("id", "")})
	_refresh_focus(run_state)
	return {"ok": true, "progress": float(job["shipped_progress"]), "job": job}


## Walks away. The contract is written off, but the prompts it would have eaten
## are back on the table.
func abandon_focused_job(run_state: RunState) -> Dictionary:
	var job: Dictionary = focused_job(run_state)
	if job.is_empty():
		return {"ok": false, "reason": "No contract in progress."}
	job["abandoned"] = true
	job["prompts_remaining"] = -1
	_refresh_focus(run_state)
	return {"ok": true, "job": job}


func finalize_completed_jobs(
	run_state: RunState,
	jobs: Array,
	effect_resolver: EffectResolver,
	subscriptions: Array,
	tuning: Dictionary,
	economy_system: EconomySystem,
	messages: Array[String],
	rng: DeterministicRng
) -> Dictionary:
	var total_reward: float = 0.0
	for job in jobs:
		if float(job.get("tokens_remaining", 0.0)) > 0.0:
			continue
		total_reward += _calculate_reward(run_state, job, effect_resolver, subscriptions, tuning, economy_system, messages, true, rng)
	return {"reward": total_reward}


func finalize_failed_jobs(
	run_state: RunState,
	jobs: Array,
	effect_resolver: EffectResolver,
	subscriptions: Array,
	tuning: Dictionary,
	economy_system: EconomySystem,
	content_db: Node,
	messages: Array[String],
	rng: DeterministicRng
) -> Dictionary:
	var scaling: Dictionary = content_db.balance.get("job_scaling", {})
	var consolation_ratio: float = float(scaling.get("failed_job_consolation_ratio", 0.2))
	var total_reward: float = 0.0
	for job in jobs:
		# Walking away pays nothing. That is the point of walking away.
		if bool(job.get("abandoned", false)):
			messages.append("%s: abandoned, no fee." % job.get("name", "Job"))
			continue
		var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
		var remaining: float = maxf(0.0, float(job.get("tokens_remaining", 0.0)))
		var progress: float = clampf(1.0 - (remaining / requirement), 0.0, 1.0)
		if progress <= 0.0:
			continue
		var base_reward: float = float(job.get("reward", 0.0)) * progress * consolation_ratio
		if base_reward <= 0.0:
			continue
		effect_resolver.begin_action("reward.failed.%s" % job.get("id", ""))
		var mod_ctx := ModifierContext.new("reward.calculated", run_state)
		mod_ctx.rng = rng.derive("reward.failed.%s" % job.get("id", ""))
		mod_ctx.job = job
		mod_ctx.set_value("job.reward", base_reward)
		effect_resolver.dispatch("reward.calculated", mod_ctx, subscriptions)
		base_reward = float(mod_ctx.get_value("job.reward", base_reward))
		economy_system.add_income(run_state, base_reward, tuning)
		total_reward += base_reward
		messages.append("%s: partial pay %s (%.0f%% done)." % [
			job.get("name", "Job"),
			NumberFormat.format_cash(base_reward),
			progress * 100.0,
		])
	return {"reward": total_reward}


func _calculate_reward(
	run_state: RunState,
	job: Dictionary,
	effect_resolver: EffectResolver,
	subscriptions: Array,
	tuning: Dictionary,
	economy_system: EconomySystem,
	messages: Array[String],
	pay_now: bool,
	rng: DeterministicRng
) -> float:
	var reward: float = float(job.get("reward", 0.0))
	effect_resolver.begin_action("reward.%s" % job.get("id", ""))
	var mod_ctx := ModifierContext.new("reward.calculated", run_state)
	mod_ctx.rng = rng.derive("reward.%s" % job.get("id", ""))
	mod_ctx.job = job
	mod_ctx.set_value("job.reward", reward)
	effect_resolver.dispatch("reward.calculated", mod_ctx, subscriptions)
	reward = float(mod_ctx.get_value("job.reward", reward))
	reward *= _delivery_penalty(run_state, job, rng, messages)
	var quality: float = float(job.get("quality", 0.0))
	var threshold: float = float(job.get("quality_threshold", 0.0))
	var quality_multiplier: float = quality_payout_multiplier(quality, threshold)
	reward *= quality_multiplier
	job["quality_multiplier"] = quality_multiplier
	var early_bonus: float = early_delivery_bonus(job)
	job["early_bonus_pct"] = early_bonus
	if early_bonus > 0.0:
		reward *= 1.0 + early_bonus
		messages.append("%s: delivered with %d prompt(s) to spare — bonus +%d%%." % [
			job.get("name", "Job"),
			maxi(0, int(job.get("prompts_remaining", 0))),
			int(round(early_bonus * 100.0)),
		])
	if quality_multiplier < 0.999:
		messages.append("%s: quality %d against a bar of %d — paid ×%.2f." % [
			job.get("name", "Job"), int(round(quality)), int(round(threshold)), quality_multiplier,
		])
	elif quality_multiplier > 1.001:
		messages.append("%s: quality %d clears the bar of %d — bonus ×%.2f." % [
			job.get("name", "Job"), int(round(quality)), int(round(threshold)), quality_multiplier,
		])
	if pay_now:
		economy_system.add_income(run_state, reward, tuning)
	return reward


## What a client pays on top for getting the work back before they expected it.
## Beating a deadline used to be worth nothing beyond the prompts it freed up, so
## there was no reason to buy throughput past "fast enough". Work shipped
## unfinished is excluded: cutting the scope is not the same as being quick.
static func early_delivery_bonus(job: Dictionary) -> float:
	if bool(job.get("shipped_unfinished", false)):
		return 0.0
	var spare: int = maxi(0, int(job.get("prompts_remaining", 0)))
	if spare <= 0:
		return 0.0
	var cfg: Dictionary = ContentDatabase.balance.get("job_scaling", {}).get("early_delivery_bonus", {})
	var per_prompt: float = float(cfg.get("per_spare_prompt", 0.0))
	var cap: float = float(cfg.get("cap", 0.0))
	return minf(cap, per_prompt * float(spare))


## What the client pays for the quality they got, as a fraction of the fee.
## Under the bar the fee tapers rather than halving on a knife edge, and over it
## there is something to aim at: shipping at exactly the threshold used to pay
## the same as shipping something genuinely good.
static func quality_payout_multiplier(quality: float, threshold: float) -> float:
	var cfg: Dictionary = ContentDatabase.balance.get("job_scaling", {}).get("quality_payout", {})
	var floor_mult: float = float(cfg.get("penalty_floor", 0.5))
	var bonus_max: float = float(cfg.get("bonus_max", 0.3))
	var bonus_span: float = maxf(1.0, float(cfg.get("bonus_span", 40.0)))
	if threshold <= 0.0:
		return 1.0
	if quality < threshold:
		return lerpf(floor_mult, 1.0, clampf(quality / threshold, 0.0, 1.0))
	return 1.0 + bonus_max * clampf((quality - threshold) / bonus_span, 0.0, 1.0)


## What delivery costs: work that went out unfinished, defects the client can
## see, and the ones nobody looked for. Hidden bugs are resolved here and only
## here, which is what makes skipping the tests a gamble rather than a saving.
func _delivery_penalty(
	run_state: RunState,
	job: Dictionary,
	rng: DeterministicRng,
	messages: Array[String]
) -> float:
	var multiplier: float = 1.0
	var job_name: String = str(job.get("name", "Job"))

	if bool(job.get("shipped_unfinished", false)):
		var shipped: float = clampf(float(job.get("shipped_progress", 1.0)), 0.0, 1.0)
		multiplier *= shipped
		job["quality"] = float(job.get("quality", 0.0)) * shipped
		messages.append("%s: shipped at %d%% — paid for what was delivered." % [job_name, int(shipped * 100.0)])

	var known: int = maxi(0, int(job.get("known_bugs", 0)))
	if known > 0:
		multiplier *= maxf(0.3, 1.0 - 0.08 * float(known))
		job["quality"] = maxf(0.0, float(job.get("quality", 0.0)) - 3.0 * float(known))
		messages.append("%s: shipped with %d known bug(s)." % [job_name, known])

	var hidden: int = maxi(0, int(job.get("hidden_bugs", 0)))
	var discovery_chance: float = float(
		ContentDatabase.balance.get("job_scaling", {}).get("board", {}).get("hidden_bug_discovery_chance", 0.6)
	)
	var discovered: int = 0
	for _i in range(hidden):
		if rng.next_float() < discovery_chance:
			discovered += 1
	job["hidden_bugs_discovered"] = discovered
	if discovered > 0:
		multiplier *= maxf(0.25, 1.0 - 0.1 * float(discovered))
		run_state.business["reputation"] = maxf(-10.0, float(run_state.business.get("reputation", 0.0)) - float(discovered))
		messages.append("%s: %d bug(s) surfaced in production. The client noticed." % [job_name, discovered])
	var shipped_undetected: int = hidden - discovered
	if shipped_undetected > 0:
		run_state.statistics["hidden_bugs_shipped"] = int(
			run_state.statistics.get("hidden_bugs_shipped", 0)
		) + shipped_undetected
		# Rule-changer: a shadow market pays for defects nobody has found yet.
		if "unlock.rule_bug_market" in Array(run_state.build.get("meta_unlocks", [])):
			var bounty: float = 40.0 * float(shipped_undetected)
			run_state.economy["cash"] = float(run_state.economy.get("cash", 0.0)) + bounty
			messages.append("%s: sold %d undetected bug(s) to the bug market for %s." % [
				job_name, shipped_undetected, NumberFormat.format_cash(bounty)
			])
	if hidden > 0 and discovered <= 0:
		messages.append("%s: %d undetected bug(s) shipped. Nobody has found them yet." % [job_name, hidden])

	for rule in Array(job.get("board_rules", [])):
		if not rule is Dictionary or str(rule.get("type", "")) != BoardSystem.RULE_MAX_HIDDEN_BUGS:
			continue
		if hidden <= int(rule.get("value", 0)):
			continue
		multiplier *= 0.5
		run_state.business["reputation"] = maxf(-10.0, float(run_state.business.get("reputation", 0.0)) - 2.0)
		messages.append("%s: the audit found unresolved defects. Half the fee withheld." % job_name)

	return multiplier


func _prepare_job(offer: Dictionary, run_state: RunState, content_db: Node) -> Dictionary:
	var job: Dictionary = offer.duplicate(true)
	_enforce_minimum_workload(job, run_state, content_db)
	job["tokens_remaining"] = float(job.get("token_requirement", 0.0))
	job["quality"] = 0.0
	job["prompts_remaining"] = int(job.get("deadline_prompts", 4))
	job["time_remaining_ratio"] = 1.0
	job["bugs_this_job"] = 0
	job["known_bugs"] = 0
	job["hidden_bugs"] = 0
	job["features_added"] = []
	job["blocked_slots"] = _blocked_slots_from_rules(job)
	if str(job.get("workflow_id", "")) == "":
		job["workflow_id"] = default_workflow_id(run_state)
	return job


## The pipeline a contract is worked through until the player says otherwise.
func default_workflow_id(run_state: RunState) -> String:
	var list: Array = Array(run_state.build.get("workflows", []))
	if list.is_empty() or not list[0] is Dictionary:
		return ""
	return str(list[0].get("id", ""))


## Routes a contract through a different workflow. Allowed mid-run: switching a
## job onto the pipeline that answers its demands is the decision the whole
## system is built around, and it should be reversible.
func assign_workflow(run_state: RunState, job_id: String, workflow_id: String) -> bool:
	var exists: bool = false
	for workflow in Array(run_state.build.get("workflows", [])):
		if workflow is Dictionary and str(workflow.get("id", "")) == workflow_id:
			exists = true
			break
	if not exists:
		return false
	for collection in ["active_jobs", "job_queue", "job_offers"]:
		for job in run_state.business.get(collection, []):
			if job is Dictionary and str(job.get("id", "")) == job_id:
				job["workflow_id"] = workflow_id
				return true
	return false


## Contracts that arrive with the pipeline already partly occupied: COBOL, an
## undocumented API, Steve's script.
func _blocked_slots_from_rules(job: Dictionary) -> int:
	var blocked: int = 0
	for rule in Array(job.get("board_rules", [])):
		if rule is Dictionary and str(rule.get("type", "")) == BoardSystem.RULE_BLOCKED_SLOTS:
			blocked += int(rule.get("value", 0))
	return clampi(blocked, 0, BoardSystem.DEFAULT_SLOT_COUNT - 1)


func _enforce_minimum_workload(job: Dictionary, run_state: RunState, content_db: Node) -> void:
	var scaling: Dictionary = content_db.balance.get("job_scaling", {})
	var min_prompts: float = float(scaling.get("min_work_prompts", 6))
	var rate: float = maxf(1.0, float(run_state.compute.get("token_rate", 1.0)))
	var min_requirement: float = rate * min_prompts
	var requirement: float = float(job.get("token_requirement", 0.0))
	if requirement >= min_requirement:
		return
	job["token_requirement"] = min_requirement
	var slack: int = int(scaling.get("deadline_slack_prompts", 2))
	var board_multiplier: float = maxf(
		1.0, float(scaling.get("board", {}).get("expected_progress_multiplier", 2.0))
	)
	var needed_prompts: int = int(ceil(min_requirement / (rate * board_multiplier)))
	job["deadline_prompts"] = maxi(int(job.get("deadline_prompts", 4)), needed_prompts + slack)


func _scale_job(
	job_def: JobDefinition,
	round_number: int,
	content_db: Node,
	tuning: Dictionary,
	run_state: RunState,
	offer_rng: DeterministicRng = null
) -> Dictionary:
	var scaling: Dictionary = content_db.balance.get("job_scaling", {})
	var economy_cfg: Dictionary = content_db.balance.get("economy", {})
	var baseline_rate: float = float(scaling.get("baseline_token_rate", 1_000_000.0))
	var token_curve: Dictionary = economy_cfg.get("token_requirement_curve", {})
	var curve_base: float = float(token_curve.get("base", baseline_rate))
	var curve_exp: float = float(token_curve.get("exponent", 1.0))
	var round_rate: float = curve_base * pow(maxf(1.0, float(round_number)), curve_exp)
	var actual_rate: float = maxf(1.0, float(run_state.compute.get("token_rate", baseline_rate)))
	var player_rate: float = maxf(maxf(baseline_rate * 0.25, round_rate), actual_rate)

	var reward_mult: float = float(scaling.get("reward_scaling", {}).get("base_multiplier", 1.0))
	reward_mult += float(scaling.get("reward_scaling", {}).get("per_round_growth", 0.12)) * (round_number - 1)
	var token_mult: float = float(scaling.get("token_scaling", {}).get("base_multiplier", 1.0))
	token_mult += float(scaling.get("token_scaling", {}).get("per_round_growth", 0.15)) * (round_number - 1)

	var profile: Dictionary = content_db.balance.get("difficulty_profiles", {}).get("normal", {})
	reward_mult *= float(profile.get("job_reward_multiplier", 1.0))
	token_mult *= float(profile.get("token_requirement_multiplier", 1.0))
	# Compute Ages scale both sides together: a later age is a bigger game,
	# not just a harder one.
	reward_mult *= float(run_state.business.get("age_reward_multiplier", 1.0))
	token_mult *= float(run_state.business.get("age_token_multiplier", 1.0))
	# A studio clients have heard of can charge more for the same work, so
	# reputation is felt on every offer rather than only at a tier threshold.
	reward_mult *= reputation_reward_multiplier(run_state, content_db)

	var base_work_prompts: float = maxf(2.0, job_def.token_requirement / baseline_rate)
	var tier: int = _job_tier(job_def, content_db)
	var max_prompts_by_tier: Array = scaling.get("max_work_prompts_by_tier", [8, 16, 24, 40, 60, 100])
	var max_work_prompts: float = float(max_prompts_by_tier[mini(tier, max_prompts_by_tier.size() - 1)])
	var work_prompts: float = minf(base_work_prompts * token_mult, max_work_prompts)
	var min_work_prompts: float = float(scaling.get("min_work_prompts", 6))
	var token_requirement: float = maxf(
		player_rate * work_prompts,
		actual_rate * min_work_prompts
	) * float(tuning.get("token_multiplier", 1.0))
	# Per-offer variance so two postings of the same contract type are not
	# identical. Skipped when no rng is supplied (balance tests, rescaling).
	var reward_variance: float = 1.0
	if offer_rng != null:
		token_requirement *= 1.0 + (offer_rng.next_float() - 0.5) * 0.3
		reward_variance = 1.0 + (offer_rng.next_float() - 0.5) * 0.2
	# A batch is worth more than its raw token count once it has been through a
	# pipeline, so deadlines are measured in burns rather than in bare prompts.
	var board_multiplier: float = maxf(
		1.0, float(scaling.get("board", {}).get("expected_progress_multiplier", 2.0))
	)
	var effective_work_prompts: float = token_requirement / maxf(1.0, actual_rate * board_multiplier)

	var slack_by_tier: Array = scaling.get("deadline_slack_by_tier", [3, 2, 2, 2, 2, 2])
	var slack: int = int(slack_by_tier[mini(tier, slack_by_tier.size() - 1)])
	# The deadline is what the round costs in real time, so it is capped by the
	# tier's work budget rather than by how far behind the curve the rig has
	# fallen. A player whose rig cannot keep up gets a contract they will miss —
	# visible on the offer as more prompts needed than the deadline allows — not
	# a round that grinds on for a hundred prompts.
	var deadline_cap: int = int(ceil(max_work_prompts)) + slack
	var deadline_prompts: int = clampi(int(ceil(effective_work_prompts)) + slack, 3, deadline_cap)

	# economy_multiplier is applied once at payout time (EconomySystem.add_income).
	var reward: float = job_def.reward * reward_mult * reward_variance
	var power_per_prompt: float = float(run_state.economy.get("power_cost_per_prompt", 10.0))
	# A contract has to pay for the round it occupies, not only the power it
	# burns: rent lands once the work is done, so a fee that cannot clear it is a
	# contract nobody could take and stay solvent. Rent is added at face value —
	# the multiplier is on the metered costs — so one contract roughly breaks
	# even and filling the round is what makes it profitable.
	var round_rent: float = float(run_state.economy.get("round_rent", 400.0))
	var min_reward: float = power_per_prompt * ceil(effective_work_prompts) * float(
		scaling.get("min_reward_cost_multiplier", 3.0)
	) + round_rent
	# Snapped so varied offers still advertise tidy figures.
	reward = snappedf(maxf(reward, min_reward), 5.0)

	var revision_caps: Array = scaling.get("revision_risk_cap_by_tier", [0.04, 0.08, 0.12, 0.16, 0.2, 0.25])
	var revision_risk: float = minf(job_def.revision_risk, float(revision_caps[mini(tier, revision_caps.size() - 1)]))
	var bug_chances: Array = scaling.get("bug_chance_by_tier", [0.04, 0.07, 0.1, 0.12, 0.12, 0.12])
	var bug_chance: float = float(bug_chances[mini(tier, bug_chances.size() - 1)])
	var creep_pcts: Array = scaling.get("scope_creep_pct_by_tier", [0.02, 0.03, 0.04, 0.05, 0.05, 0.05])
	var scope_creep_pct: float = float(creep_pcts[mini(tier, creep_pcts.size() - 1)])

	var quality_base: float = float(scaling.get("quality_scaling", {}).get("base_threshold", 50.0))
	var quality_per_tier: float = float(scaling.get("quality_scaling", {}).get("per_tier_increase", 8.0))
	var quality_threshold: float = clampf(
		minf(float(job_def.quality_threshold), quality_base + tier * quality_per_tier),
		35.0,
		92.0
	)

	return {
		"id": job_def.id,
		"name": job_def.name,
		"description": job_def.description,
		"reward": reward,
		"token_requirement": token_requirement,
		"quality_threshold": quality_threshold,
		"deadline_days": job_def.deadline_days,
		"deadline_prompts": deadline_prompts,
		"revision_risk": revision_risk,
		"bug_chance": bug_chance,
		"scope_creep_pct": scope_creep_pct,
		"tags": Array(job_def.tags),
		"complications": job_def.complications,
		"board_rules": job_def.board_rules.duplicate(true),
		"demands": Array(job_def.demands),
		"tier": tier,
	}


## What reputation is worth on an offer's fee. Only the good half counts: a
## damaged reputation already costs the run its contract tiers and, low enough,
## the run itself.
static func reputation_reward_multiplier(run_state: RunState, content_db: Node) -> float:
	var cfg: Dictionary = content_db.balance.get("job_scaling", {}).get("reputation", {})
	var per_point: float = float(cfg.get("reward_per_point", 0.0))
	var cap: float = float(cfg.get("reward_bonus_cap", 0.0))
	var reputation: float = maxf(0.0, float(run_state.business.get("reputation", 0.0)))
	return 1.0 + minf(cap, reputation * per_point)


## The reputation the next contract tier is waiting on, and what it opens, for
## the job board's header. Empty when every tier is already reachable.
static func next_reputation_tier(run_state: RunState, content_db: Node) -> Dictionary:
	var scaling: Dictionary = content_db.balance.get("job_scaling", {})
	var thresholds: Array = scaling.get("tier_unlock_by_reputation", [])
	var sales_level: int = int(run_state.build.get("upgrade_levels", {}).get("upgrade.sales_investment", 0))
	var reduction: float = float(scaling.get("sales_level_rep_reduction", 2))
	var reputation: float = float(run_state.business.get("reputation", 0.0))
	for index in range(thresholds.size()):
		var needed: float = float(thresholds[index]) - float(sales_level) * reduction
		if reputation < needed:
			return {"tier": index, "reputation": needed}
	return {}


func rescale_offer(
	job_def: JobDefinition,
	round_number: int,
	content_db: Node,
	tuning: Dictionary,
	run_state: RunState
) -> Dictionary:
	return _scale_job(job_def, round_number, content_db, tuning, run_state)


func refresh_contract_board(run_state: RunState, rng: DeterministicRng, content_db: Node, tuning: Dictionary) -> void:
	generate_offers(run_state, rng.derive("job_offers"), content_db, tuning)


func _job_tier(job_def: JobDefinition, content_db: Node) -> int:
	var baseline_rate: float = float(content_db.balance.get("job_scaling", {}).get("baseline_token_rate", 1_000_000.0))
	var workload_prompts: float = job_def.token_requirement / baseline_rate
	if workload_prompts <= 20.0:
		return 0
	if workload_prompts <= 80.0:
		return 1
	if workload_prompts <= 400.0:
		return 2
	if workload_prompts <= 5000.0:
		return 3
	if workload_prompts <= 500_000.0:
		return 4
	return 5


func _player_max_job_tier(run_state: RunState, round_number: int, content_db: Node) -> int:
	var scaling: Dictionary = content_db.balance.get("job_scaling", {})
	var round_unlocks: Array = scaling.get("tier_unlock_by_round", [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5])
	var tier_from_round: int = int(round_unlocks[mini(round_number - 1, round_unlocks.size() - 1)])

	var tier_from_rate: int = 0
	var rate: float = float(run_state.compute.get("token_rate", 1_000_000.0))
	for entry in scaling.get("tier_unlock_by_token_rate", []):
		if entry is Dictionary and rate >= float(entry.get("rate", 0.0)):
			tier_from_rate = int(entry.get("tier", 0))

	var tier_from_rep: int = 0
	var rep: float = float(run_state.business.get("reputation", 0.0))
	var sales_level: int = int(run_state.build.get("upgrade_levels", {}).get("upgrade.sales_investment", 0))
	var rep_reduction: float = float(scaling.get("sales_level_rep_reduction", 2))
	var rep_thresholds: Array = scaling.get("tier_unlock_by_reputation", [0, 5, 10, 15, 20, 25])
	for index in range(rep_thresholds.size()):
		var threshold: float = float(rep_thresholds[index]) - float(sales_level) * rep_reduction
		if rep >= threshold:
			tier_from_rep = index

	return mini(5, maxi(tier_from_round, maxi(tier_from_rate, tier_from_rep)))
