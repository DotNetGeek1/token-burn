class_name JobSystem
extends RefCounted

## How many authored contracts a band needs before the board stops borrowing
## from the band below it. Under this a thin location shows the same posting
## three times, which reads as a bug rather than as a quiet week.
const MIN_BAND_POOL := 3


func generate_offers(run_state: RunState, rng: DeterministicRng, content_db: Node, tuning: Dictionary) -> void:
	var slots: int = ComputeSystem.job_slots(run_state)
	var offer_cap: int = maxi(DemandSystem.MAX_DEMAND, slots)
	var interest: int = clampi(int(run_state.business.get("demand", 3.0)), 1, offer_cap)
	var count: int = maxi(interest, slots)
	var round_number: int = int(run_state.calendar.get("round", 1))
	var here: int = location_tier(run_state, content_db)
	var eligible: Array = _collect_eligible_jobs(content_db, round_number, here)
	if eligible.is_empty():
		run_state.business["job_offers"] = []
		return
	eligible = rng.shuffle(eligible)

	var offers: Array = []
	var index: int = 0
	# A board holds at most one of each kind of gamble, so a run is never handed
	# three jackpots or three contracts it was built to fail.
	var windfall_placed: bool = false
	var attempts: int = 0
	var attempt_limit: int = maxi(eligible.size() * 4, count * 4)
	while offers.size() < count and attempts < attempt_limit:
		var job_def: JobDefinition = eligible[index % eligible.size()]
		index += 1
		attempts += 1
		if job_def.windfall and windfall_placed:
			continue
		# Each offer gets its own rng stream so repeated definitions still
		# differ, and so the board is reproducible for a given seed.
		var offer_rng: DeterministicRng = rng.derive("offer_%d_%s" % [index, job_def.id])
		offers.append(_scale_job(
			job_def, round_number, content_db, tuning, run_state, offer_rng, offers.size()
		))
		windfall_placed = windfall_placed or job_def.windfall
		# Only reuse definitions once the pool is exhausted.
		if index % eligible.size() == 0 and offers.size() < count:
			eligible = rng.shuffle(eligible)

	var stretch_index: int = offers.size() - 1 if offers.size() > 1 else offers.size()
	var stretch: Dictionary = _stretch_offer(
		run_state, rng, content_db, tuning, round_number, stretch_index
	)
	if not stretch.is_empty() and offers.size() > 1:
		offers[offers.size() - 1] = stretch
	elif not stretch.is_empty():
		offers.append(stretch)

	# The room still advertises some familiar work, but a rig that has reached
	# the next hardware era must not be shown a whole board it can erase in one
	# click. These are authored contracts from a fixed band, not live-scaled
	# copies of the local work: buying power opens a bigger market without moving
	# the numbers on a posting that already exists.
	var service_tier: int = rig_work_tier(run_state, content_db)
	if service_tier > here:
		var matched_count: int = 0
		if offers.size() > 1:
			matched_count = offers.size() - 1
		var matched: Array = _rig_matched_offers(
			run_state, rng.derive("rig_matched"), content_db, tuning,
			round_number, service_tier, matched_count
		)
		for matched_index in range(matched.size()):
			offers[matched_index] = matched[matched_index]
	var matched_tier: int = maxi(here, service_tier)
	for offer in offers:
		if offer is Dictionary:
			offer["rig_matched"] = int(offer.get("tier", -1)) == matched_tier

	run_state.business["job_offers"] = _classify_offers(offers, run_state, content_db)


## The strongest authored band this installed fleet is meant to serve. This is
## metadata on the machine, deliberately not inferred from the live token rate:
## perks and throttles may change output without silently changing the market.
static func rig_work_tier(run_state: RunState, content_db: Node) -> int:
	var curves: Dictionary = content_db.balance.get("hardware_curves", {})
	var tier: int = 0
	for hardware_id in run_state.build.get("hardware", []):
		var curve: Dictionary = Dictionary(curves.get(str(hardware_id), {}))
		tier = maxi(tier, int(curve.get("work_tier", 0)))
	var bands: Array = location_bands(content_db)
	return clampi(tier, 0, maxi(0, bands.size() - 1))


func _rig_matched_offers(
	run_state: RunState,
	rng: DeterministicRng,
	content_db: Node,
	tuning: Dictionary,
	round_number: int,
	tier: int,
	count: int
) -> Array:
	if count <= 0:
		return []
	var pool: Array = []
	for job_def in content_db.jobs:
		if _job_tier(job_def, content_db) != tier:
			continue
		if round_number < 12 and job_def.id == "job.capstone_simulation":
			continue
		pool.append(job_def)
	if pool.is_empty():
		return []
	pool = rng.shuffle(pool)
	var result: Array = []
	var used_windfall: bool = false
	var cursor: int = 0
	var attempts: int = 0
	var attempt_limit: int = maxi(pool.size() * 3, count * 4)
	while result.size() < count and attempts < attempt_limit:
		var job_def: JobDefinition = pool[cursor % pool.size()]
		cursor += 1
		attempts += 1
		if job_def.windfall and used_windfall:
			continue
		var offer: Dictionary = _scale_job(
			job_def, round_number, content_db, tuning, run_state,
			rng.derive("offer_%d_%s" % [cursor, job_def.id]), result.size()
		)
		offer["rig_matched"] = true
		result.append(offer)
		used_windfall = used_windfall or job_def.windfall
	return result


## The board is drawn from the location's own band. The capstone is a
## round-twelve headliner, not the whole board: overtime still has rent to pay,
## so the ordinary pool stays open alongside it rather than the run being left
## with one impossible contract and no way to earn.
func _collect_eligible_jobs(content_db: Node, round_number: int, tier: int) -> Array:
	# Walk down from the run's own band until there is enough authored work for a
	# board that is not the same contract three times over.
	var eligible: Array = []
	for candidate_tier in range(tier, -1, -1):
		for job_def in content_db.jobs:
			if round_number < 12 and job_def.id == "job.capstone_simulation":
				continue
			if _job_tier(job_def, content_db) != candidate_tier:
				continue
			eligible.append(job_def)
		if eligible.size() >= MIN_BAND_POOL:
			break
	return eligible


## Bread and butter, stretch, or temptation — read off what the run's own
## workflows can actually answer. A contract nobody's pipeline can serve used to
## arrive at the same fee as one it was built for, so a ×0.6 throughput penalty
## read as the maths breaking rather than as a risk that was taken knowingly.
## Mismatched work now pays for the trouble and says so on the card.
func _classify_offers(offers: Array, run_state: RunState, content_db: Node) -> Array:
	var board := BoardSystem.new()
	var available_workflows: Array = board.workflows(run_state)
	var bonus_per_gap: float = float(
		content_db.balance.get("job_scaling", {}).get("mismatch_reward_bonus", 0.2)
	)
	for offer in offers:
		if not offer is Dictionary:
			continue
		# A contract runs through one workflow. Capabilities from different lanes
		# cannot be combined into a fictional perfect pipeline on the job card.
		var unmet: int = -1
		for workflow in available_workflows:
			if not workflow is Dictionary:
				continue
			var match_summary: Dictionary = board.workflow_match(run_state, offer, workflow)
			var workflow_unmet: int = int(match_summary.get("total", 0)) - int(
				match_summary.get("met", 0)
			)
			unmet = workflow_unmet if unmet < 0 else mini(unmet, workflow_unmet)
		if unmet < 0:
			var empty_match: Dictionary = board.workflow_match(
				run_state, offer, {"id": "", "name": "", "slots": []}
			)
			unmet = int(empty_match.get("total", 0)) - int(empty_match.get("met", 0))
		offer["unmet_demands"] = unmet
		if unmet == 0:
			offer["fit"] = "bread_and_butter"
			continue
		offer["fit"] = "stretch" if unmet == 1 else "temptation"
		offer["reward"] = snappedf(float(offer.get("reward", 0.0)) * (1.0 + bonus_per_gap * unmet), 5.0)
	return offers


## One posting from the band above, paying a premium for work the location was
## not built for. Empty until reputation opens the rung.
func _stretch_offer(
	run_state: RunState,
	rng: DeterministicRng,
	content_db: Node,
	tuning: Dictionary,
	round_number: int,
	offer_index: int = 0
) -> Dictionary:
	var stretch_tier: int = _stretch_tier_available(run_state, content_db)
	if stretch_tier < 0:
		return {}
	# Strictly the band above: a stretch that is really more of the same work is
	# a lie on the card and a fee the run did not earn.
	var pool: Array = []
	for candidate in _collect_eligible_jobs(content_db, round_number, stretch_tier):
		if _job_tier(candidate, content_db) == stretch_tier:
			pool.append(candidate)
	if pool.is_empty():
		return {}
	var job_def: JobDefinition = rng.derive("stretch_pool").shuffle(pool)[0]
	var offer: Dictionary = _scale_job(
		job_def, round_number, content_db, tuning, run_state, rng.derive("stretch_offer"),
		offer_index
	)
	var bonus: float = float(
		content_db.balance.get("job_scaling", {}).get("stretch_reward_bonus", 0.35)
	)
	offer["reward"] = snappedf(float(offer.get("reward", 0.0)) * (1.0 + bonus), 5.0)
	offer["stretch"] = true
	return offer


## Authored contract id for a live offer or job. Instance `id` is unique per
## card; content lookups still want the definition, and old saves only have `id`.
static func definition_id_of(job: Dictionary) -> String:
	var definition_id: String = str(job.get("definition_id", ""))
	return definition_id if definition_id != "" else str(job.get("id", ""))


## Finds a board offer by instance id first. A definition id matches only when
## exactly one offer has that definition, so `accept_job("job.test_hopeless")`
## and two copies of the same contract can both be right.
func find_offer(run_state: RunState, job_id: String) -> Dictionary:
	var offers: Array = run_state.business.get("job_offers", [])
	for offer in offers:
		if offer is Dictionary and str(offer.get("id", "")) == job_id:
			return offer
	var definition_matches: Array = []
	for offer in offers:
		if offer is Dictionary and definition_id_of(offer) == job_id:
			definition_matches.append(offer)
	if definition_matches.size() == 1:
		return definition_matches[0]
	return {}


func accept_job(run_state: RunState, job_id: String) -> bool:
	var offer: Dictionary = find_offer(run_state, job_id)
	if offer.is_empty():
		return false
	var offers: Array = run_state.business["job_offers"]
	var index: int = offers.find(offer)
	if index < 0:
		return false
	var queued: Dictionary = offer.duplicate(true)
	offers.remove_at(index)
	run_state.business["job_queue"].append(queued)
	return true


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


## A deadline of N prompts means N actions remain. Once `prompts_remaining`
## reaches zero the job has had its last action and, if it is not done, it has
## missed its deadline — so zero is terminal, not one more free prompt.
func _is_in_progress(job: Dictionary) -> bool:
	if float(job.get("tokens_remaining", 0.0)) <= 0.0:
		return false
	return int(job.get("prompts_remaining", 0)) > 0


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
	effect_resolver.begin_action(EventBus.EVENT_PROMPT_STARTED)
	var mod_ctx := ModifierContext.new(EventBus.EVENT_PROMPT_STARTED, run_state)
	mod_ctx.rng = rng.derive(EventBus.EVENT_PROMPT_STARTED)
	mod_ctx.set_value("compute.token_rate", token_rate)
	effect_resolver.dispatch(EventBus.EVENT_PROMPT_STARTED, mod_ctx, subscriptions)
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
	mode: int = ResolveMode.COMMIT
) -> Dictionary:
	var active_jobs: Array = run_state.business.get("active_jobs", [])
	if active_jobs.is_empty():
		return {"ok": false, "reason": "No active jobs"}
	var lanes: Array = burn_lane_jobs(run_state)
	if lanes.is_empty():
		return {"ok": false, "reason": "No contract in progress."}

	var messages: Array[String] = []
	var batch: float = prepare_batch(run_state, rng, effect_resolver, subscriptions, tuning, compute_system)
	if mode == ResolveMode.COMMIT:
		EventBus.emit_event(EventBus.EVENT_TOKENS_GENERATED, {"amount": batch})

	# The batch is the rig's output, not each contract's, so parallel lanes share
	# it. Two machines finish two contracts in the time one machine finishes one.
	var share: float = batch / float(lanes.size())
	var primary: Dictionary = {}
	var lane_reports: Array = []
	var prompt_tokens: float = 0.0
	# Snapshot before resolving so a completion can be told apart from a job
	# that was already done: scope creep further down can even un-finish one.
	var was_complete_before: Dictionary = {}
	for job in lanes:
		was_complete_before[str(job.get("id", ""))] = float(job.get("tokens_remaining", 0.0)) <= 0.0
	for job in lanes:
		var lane_rng: DeterministicRng = rng.derive("lane.%s" % str(job.get("id", "")))
		var lane_burn: Dictionary = board_system.resolve_burn(
			run_state, job, share, lane_rng, effect_resolver, subscriptions, stage_limit, mode
		)
		if not lane_burn.get("ok", false):
			# The focused lane failing means the pipeline itself cannot run, which
			# is a refusal rather than a wasted prompt.
			if primary.is_empty():
				return {"ok": false, "reason": str(lane_burn.get("reason", "The pipeline produced nothing."))}
			continue
		prompt_tokens += float(lane_burn.get("tokens", 0.0))
		_apply_burn(
			run_state, job, lane_burn, rng, messages, mode, heat_system, economy_system,
			effect_resolver, subscriptions
		)
		_roll_job_risks(
			run_state, job, lane_rng, messages, float(lane_burn.get("bug_chance_mult", 1.0)), mode
		)
		if primary.is_empty():
			primary = lane_burn
		lane_reports.append({
			"job_id": str(job.get("id", "")),
			"name": str(job.get("name", "Contract")),
			"workflow_name": str(lane_burn.get("workflow_name", "")),
			"tokens": float(lane_burn.get("tokens", 0.0)),
			"progress_tokens": float(lane_burn.get("progress_tokens", 0.0)),
			"quality": float(lane_burn.get("quality", 0.0)),
			"tokens_remaining": float(job.get("tokens_remaining", 0.0)),
			"prompts_remaining": int(job.get("prompts_remaining", 0)),
		})
	run_state.statistics["peak_prompt_tokens"] = maxf(
		float(run_state.statistics.get("peak_prompt_tokens", 0.0)), prompt_tokens
	)
	if lane_reports.size() > 1:
		messages.append("Ran %d contracts in parallel — the batch was split %d ways." % [
			lane_reports.size(), lane_reports.size()
		])
	# A contract is complete the moment its tokens run out — the only real
	# transition worth telling anyone about. `end_prompt`'s own bookkeeping
	# runs afterwards and never itself produces this transition, so it cannot
	# be told apart from a job that had already finished a prompt earlier.
	for job in lanes:
		var job_id: String = str(job.get("id", ""))
		if was_complete_before.get(job_id, false):
			continue
		# The contract was live when this prompt started, so this prompt comes
		# off its deadline whether or not it was the one that finished it.
		# `end_prompt` skips finished work, so without this a contract
		# delivered on its very last allowed prompt kept a phantom spare
		# prompt and collected an early-delivery bonus it had not earned.
		job["_deadline_pending"] = true
		if mode == ResolveMode.COMMIT and float(job.get("tokens_remaining", 0.0)) <= 0.0:
			EventBus.emit_event(EventBus.EVENT_JOB_COMPLETED, {"job_id": job_id})
	primary = primary.duplicate(true)
	primary["lanes"] = lane_reports
	primary["lane_count"] = lane_reports.size()

	var prompt_result: Dictionary = end_prompt(
		run_state, subscriptions, effect_resolver, rng, tuning,
		compute_system, heat_system, economy_system, messages, mode
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
	economy_system: EconomySystem,
	mode: int = ResolveMode.COMMIT
) -> Dictionary:
	if run_state.business.get("active_jobs", []).is_empty():
		return {"ok": false, "reason": "No active jobs"}
	var messages: Array[String] = []
	compute_system.recalculate(run_state, effect_resolver, subscriptions, rng)
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	var vented: float = float(run_state.compute.get("heat", 0.0)) * clampf(
		float(heat_cfg.get("vent_ratio", 0.45)), 0.0, 1.0
	)
	heat_system.add_heat(run_state, -vented)
	messages.append("Vented %d heat. The fans have earned their keep." % int(round(vented)))
	var result: Dictionary = end_prompt(
		run_state, subscriptions, effect_resolver, rng, tuning,
		compute_system, heat_system, economy_system, messages, mode
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
	mode: int,
	heat_system: HeatSystem,
	economy_system: EconomySystem,
	effect_resolver: EffectResolver = null,
	subscriptions: Array = []
) -> void:
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var remaining_before: float = float(job.get("tokens_remaining", 0.0))
	var progress: float = minf(remaining_before, float(burn.get("progress_tokens", 0.0)))
	job["tokens_remaining"] = maxf(0.0, remaining_before - progress)
	if remaining_before > 0.0 and float(job["tokens_remaining"]) <= 0.0:
		_record_overkill(run_state, job, burn, requirement, mode)

	var tokens_burned: float = float(burn.get("tokens", 0.0))
	run_state.statistics["lifetime_tokens"] = float(run_state.statistics.get("lifetime_tokens", 0.0)) + tokens_burned
	if mode == ResolveMode.COMMIT:
		DepthSystem.record_tokens(run_state, tokens_burned)
		EventBus.emit_event(EventBus.EVENT_TOKENS_CONSUMED, {"amount": tokens_burned})

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
	if mode == ResolveMode.COMMIT:
		EventBus.emit_event(EventBus.EVENT_QUALITY_CALCULATED, {"value": job["quality"]})

	job["known_bugs"] = maxi(0, int(burn.get("known_bugs", 0)))
	job["hidden_bugs"] = maxi(0, int(burn.get("hidden_bugs", 0)))
	job["bugs_this_job"] = int(job["known_bugs"]) + int(job["hidden_bugs"])
	if int(burn.get("bugs_added", 0)) > 0 or int(burn.get("hidden_added", 0)) > 0:
		if mode == ResolveMode.COMMIT:
			EventBus.emit_event(EventBus.EVENT_BUG_GENERATED)
	if int(burn.get("revealed", 0)) > 0:
		messages.append("Tests surfaced %d hidden bug(s)." % int(burn.get("revealed", 0)))
	if int(burn.get("fixed", 0)) > 0:
		messages.append("Fixed %d bug(s)." % int(burn.get("fixed", 0)))

	var scope_tokens: float = float(burn.get("scope_tokens", 0.0))
	if scope_tokens > 0.0:
		job["token_requirement"] = requirement + scope_tokens
		job["tokens_remaining"] = float(job.get("tokens_remaining", 0.0)) + scope_tokens

	HeatSystem.apply_pipeline_heat(heat_system, run_state, float(burn.get("heat", 0.0)))
	var cost: float = float(burn.get("cost", 0.0))
	if cost > 0.0:
		economy_system.debit(run_state, cost, "pipeline_cost", {"job_id": job.get("id", "")})
		run_state.economy["costs_this_round"] = float(run_state.economy.get("costs_this_round", 0.0)) + cost

	for message in burn.get("messages", []):
		messages.append(str(message))
	if bool(burn.get("truncated", false)):
		messages.append("Process killed mid-batch. The rest of the tokens are gone.")


func _record_overkill(
	run_state: RunState,
	job: Dictionary,
	burn: Dictionary,
	requirement: float,
	mode: int
) -> void:
	var delivered: float = maxf(float(burn.get("progress_tokens", 0.0)), requirement)
	var ratio: float = delivered / maxf(1.0, requirement)
	burn["overkill_ratio"] = ratio
	job["overkill_ratio"] = ratio
	run_state.statistics["peak_overkill"] = maxf(
		float(run_state.statistics.get("peak_overkill", 0.0)), ratio
	)
	run_state.statistics["lifetime_overkill"] = float(
		run_state.statistics.get("lifetime_overkill", 0.0)
	) + maxf(0.0, ratio - 1.0)
	if mode == ResolveMode.COMMIT and ratio >= 1.25:
		EventBus.emit_event(EventBus.EVENT_OVERKILL, {
			"ratio": ratio,
			"job_id": str(job.get("id", "")),
		})


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
	bug_chance_mult: float = 1.0,
	mode: int = ResolveMode.COMMIT
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
		if mode == ResolveMode.COMMIT:
			EventBus.emit_event(EventBus.EVENT_BUG_GENERATED)

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
	messages: Array[String],
	mode: int = ResolveMode.COMMIT
) -> Dictionary:
	var active_jobs: Array = run_state.business.get("active_jobs", [])
	for job in active_jobs:
		if not job is Dictionary:
			continue
		# Set by the burn for every contract that was live when the prompt
		# started, so work finished by this prompt still pays for it.
		var worked_this_prompt: bool = bool(job.get("_deadline_pending", false))
		job.erase("_deadline_pending")
		var complete: bool = float(job.get("tokens_remaining", 0.0)) <= 0.0
		if complete and not worked_this_prompt:
			continue
		# A deadline already at zero has had its last action: it failed the
		# prompt that took it there and does not get another free one.
		if int(job.get("prompts_remaining", 0)) <= 0:
			continue
		job["prompts_remaining"] = int(job.get("prompts_remaining", 1)) - 1
		job["time_remaining_ratio"] = maxf(
			0.0, float(job.get("prompts_remaining", 0)) / maxf(1.0, float(job.get("deadline_prompts", 4)))
		)
		if not complete and int(job.get("prompts_remaining", 0)) <= 0:
			messages.append("%s: deadline missed." % job.get("name", "Job"))

	run_state.business["active_jobs"] = active_jobs
	run_state.business["active_job"] = active_jobs[0] if active_jobs.size() == 1 else {}

	# Expire this prompt's temporary boosts before heat is processed. The
	# batch this prompt burned has already been resolved by this point, so a
	# throttle raised by the heat this same batch generated cannot reach back
	# and slow it down — it only applies to the prompt that follows.
	run_state.tick_rate_modifiers()
	run_state.tick_cloud_burst()
	messages.append_array(heat_system.process_prompt(run_state, subscriptions, effect_resolver, rng, mode))
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
		elif int(job.get("prompts_remaining", 0)) <= 0:
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
	EventBus.emit_event(EventBus.EVENT_JOB_COMPLETED, {"job_id": job.get("id", "")})
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
		# Same event as a completed payout so the pipeline stays one place, but
		# completion-worded perks read this flag and stay off consolation fees.
		job["completed"] = false
		effect_resolver.begin_action("reward.failed.%s" % job.get("id", ""))
		var mod_ctx := ModifierContext.new("reward.calculated", run_state)
		mod_ctx.rng = rng.derive("reward.failed.%s" % job.get("id", ""))
		mod_ctx.job = job
		mod_ctx.set_value("job.reward", base_reward)
		mod_ctx.set_value("job.completed", false)
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
	# Settled first so a perk paid per undetected bug is looking at the delivery
	# that actually happened rather than at a field nothing had written yet.
	resolve_hidden_bugs(job, rng.derive("hidden_bugs.%s" % job.get("id", "")))
	job["completed"] = true
	effect_resolver.begin_action("reward.%s" % job.get("id", ""))
	var mod_ctx := ModifierContext.new("reward.calculated", run_state)
	mod_ctx.rng = rng.derive("reward.%s" % job.get("id", ""))
	mod_ctx.job = job
	mod_ctx.set_value("job.reward", reward)
	mod_ctx.set_value("job.completed", true)
	effect_resolver.dispatch("reward.calculated", mod_ctx, subscriptions)
	reward = float(mod_ctx.get_value("job.reward", reward))
	reward *= _delivery_penalty(run_state, job, rng, messages, economy_system)
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


## The quality the client actually receives, as opposed to the quality the
## pipeline produced: work cut short is only worth the fraction that shipped,
## and defects the player knew about and shipped anyway cost three points each.
## Read without mutating so the Ascension contract can be judged on the same
## number the fee is paid against, before payout has settled it.
static func delivered_quality(job: Dictionary) -> float:
	var quality: float = float(job.get("quality", 0.0))
	if bool(job.get("shipped_unfinished", false)):
		quality *= clampf(float(job.get("shipped_progress", 1.0)), 0.0, 1.0)
	quality -= 3.0 * float(maxi(0, int(job.get("known_bugs", 0))))
	return maxf(0.0, quality)


## Rolls which buried defects the client finds. Settled before the fee is
## calculated so perks paid per bug shipped (Known Unknowns) and perks that ask
## for a clean delivery (Audit Trail) can both read the outcome, and guarded so
## the roll happens once per job however many times it is asked for.
static func resolve_hidden_bugs(job: Dictionary, rng: DeterministicRng) -> void:
	if job.has("hidden_bugs_discovered"):
		return
	var hidden: int = maxi(0, int(job.get("hidden_bugs", 0)))
	var discovery_chance: float = float(
		ContentDatabase.balance.get("job_scaling", {}).get("board", {}).get("hidden_bug_discovery_chance", 0.6)
	)
	var discovered: int = 0
	for _i in range(hidden):
		if rng.next_float() < discovery_chance:
			discovered += 1
	job["hidden_bugs_discovered"] = discovered
	job["hidden_bugs_shipped"] = hidden - discovered


## What delivery costs: work that went out unfinished, defects the client can
## see, and the ones nobody looked for. Hidden bug discovery is rolled by
## `resolve_hidden_bugs`, which is what makes skipping the tests a gamble
## rather than a saving.
func _delivery_penalty(
	run_state: RunState,
	job: Dictionary,
	rng: DeterministicRng,
	messages: Array[String],
	economy_system: EconomySystem = null
) -> float:
	var multiplier: float = 1.0
	var job_name: String = str(job.get("name", "Job"))

	# Settled in one place so the recorded figure can never drift from the one
	# the Ascension contract was judged against.
	job["quality"] = delivered_quality(job)

	if bool(job.get("shipped_unfinished", false)):
		var shipped: float = clampf(float(job.get("shipped_progress", 1.0)), 0.0, 1.0)
		multiplier *= shipped
		messages.append("%s: shipped at %d%% — paid for what was delivered." % [job_name, int(shipped * 100.0)])

	var known: int = maxi(0, int(job.get("known_bugs", 0)))
	if known > 0:
		multiplier *= maxf(0.3, 1.0 - 0.08 * float(known))
		messages.append("%s: shipped with %d known bug(s)." % [job_name, known])

	var hidden: int = maxi(0, int(job.get("hidden_bugs", 0)))
	resolve_hidden_bugs(job, rng)
	var discovered: int = maxi(0, int(job.get("hidden_bugs_discovered", 0)))
	if discovered > 0:
		multiplier *= maxf(0.25, 1.0 - 0.1 * float(discovered))
		run_state.business["reputation"] = maxf(-10.0, float(run_state.business.get("reputation", 0.0)) - float(discovered))
		messages.append("%s: %d bug(s) surfaced in production. The client noticed." % [job_name, discovered])
	var shipped_undetected: int = maxi(0, int(job.get("hidden_bugs_shipped", 0)))
	if shipped_undetected > 0:
		run_state.statistics["hidden_bugs_shipped"] = int(
			run_state.statistics.get("hidden_bugs_shipped", 0)
		) + shipped_undetected
		# Rule-changer: a shadow market pays for defects nobody has found yet.
		if "unlock.rule_bug_market" in Array(run_state.build.get("meta_unlocks", [])):
			var bounty: float = 40.0 * float(shipped_undetected)
			if economy_system != null:
				economy_system.credit(run_state, bounty, "bug_market_bounty:%s" % job.get("id", ""))
			else:
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


## A queued offer as it will look once `begin_work_session` prepares it, for
## screens that show the contract before the session opens. Pure: the offer in
## the queue is not touched — `_prepare_job` works on a deep copy.
func prepare_offer_preview(offer: Dictionary, run_state: RunState, content_db: Node) -> Dictionary:
	return _prepare_job(offer, run_state, content_db)


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


## A contract that would be over in a single burn is not a round, so postings are
## floored at a few prompts of the band's expected rig. Anchored to the band and
## not to the player: the floor exists to keep a contract worth playing, not to
## claw back the upgrade that made it easy.
func _enforce_minimum_workload(job: Dictionary, run_state: RunState, content_db: Node) -> void:
	var scaling: Dictionary = content_db.balance.get("job_scaling", {})
	var min_prompts: float = float(scaling.get("min_work_prompts", 3))
	var band: Dictionary = _band_for_tier(int(job.get("tier", 0)), content_db)
	var rate: float = maxf(
		1.0, float(band.get("expected_token_rate", scaling.get("baseline_token_rate", 1_000_000.0)))
	)
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
	offer_rng: DeterministicRng = null,
	offer_index: int = 0
) -> Dictionary:
	var scaling: Dictionary = content_db.balance.get("job_scaling", {})
	# What the contract is worth and how big it is come from the band it was
	# authored into, never from the rig reading the board. A rig that has
	# doubled has to feel twice as strong against the same posting; sizing work
	# off the player's own rate moved the goalposts with every upgrade.
	var tier: int = _job_tier(job_def, content_db)
	var band: Dictionary = _band_for_tier(tier, content_db)
	var expected_rate: float = maxf(
		1.0, float(band.get("expected_token_rate", scaling.get("baseline_token_rate", 1_000_000.0)))
	)
	var target_prompts: float = maxf(1.0, float(band.get("target_work_prompts", 6.0)))

	var reward_mult: float = float(scaling.get("reward_scaling", {}).get("base_multiplier", 1.0))
	reward_mult += float(scaling.get("reward_scaling", {}).get("per_round_growth", 0.04)) * (round_number - 1)
	var token_mult: float = float(scaling.get("token_scaling", {}).get("base_multiplier", 1.0))
	token_mult += float(scaling.get("token_scaling", {}).get("per_round_growth", 0.03)) * (round_number - 1)

	var difficulty_id: String = str(run_state.flags.get("difficulty", "normal"))
	var profile: Dictionary = content_db.balance.get("difficulty_profiles", {}).get(
		difficulty_id, content_db.balance.get("difficulty_profiles", {}).get("normal", {})
	)
	reward_mult *= float(profile.get("job_reward_multiplier", 1.0))
	token_mult *= float(profile.get("token_requirement_multiplier", 1.0))
	# Compute Ages scale both sides together: a later age is a bigger game,
	# not just a harder one.
	reward_mult *= float(run_state.business.get("age_reward_multiplier", 1.0))
	token_mult *= float(run_state.business.get("age_token_multiplier", 1.0))
	# A studio clients have heard of can charge more for the same work, so
	# reputation is felt on every offer rather than only at a tier threshold.
	reward_mult *= reputation_reward_multiplier(run_state, content_db)

	var work_prompts: float = target_prompts * maxf(0.1, job_def.work_units)
	var token_requirement: float = expected_rate * work_prompts * token_mult * float(
		tuning.get("token_multiplier", 1.0)
	)
	# Per-offer variance so two postings of the same contract type are not
	# identical. Skipped when no rng is supplied (balance tests, rescaling).
	var reward_variance: float = 1.0
	if offer_rng != null:
		token_requirement *= 1.0 + (offer_rng.next_float() - 0.5) * 0.3
		reward_variance = 1.0 + (offer_rng.next_float() - 0.5) * 0.2
	# A batch is worth more than its raw token count once it has been through a
	# pipeline, so deadlines are measured in burns rather than in bare prompts.
	# The clock is set against the band's expected rig, not the player's: that is
	# what makes a strong rig deliver early and a weak one run out of days.
	var board_multiplier: float = maxf(
		1.0, float(scaling.get("board", {}).get("expected_progress_multiplier", 2.0))
	)
	var effective_work_prompts: float = token_requirement / (expected_rate * board_multiplier)

	var slack_by_tier: Array = scaling.get("deadline_slack_by_tier", [3, 2, 2, 2, 2, 2, 2])
	var slack: int = int(slack_by_tier[mini(tier, slack_by_tier.size() - 1)])
	var pressure: float = clampf(job_def.deadline_pressure, 0.5, 2.0)
	var deadline_prompts: int = maxi(3, int(ceil(effective_work_prompts / pressure)) + slack)

	# economy_multiplier is applied once at payout time (EconomySystem.add_income).
	var base_reward: float = float(band.get("base_reward", 0.0))
	var reward: float = base_reward * maxf(0.0, job_def.reward_units) * reward_mult * reward_variance
	var power_per_prompt: float = float(run_state.economy.get("power_cost_per_prompt", 10.0))
	# A contract has to pay for the round it occupies, not only the power it
	# burns: rent lands once the work is done, so a fee that cannot clear it is a
	# contract nobody could take and stay solvent. Only a share of the rent
	# counts, because a round holds more than one contract — charging every
	# posting the whole rent flattened the cheap end of a band into one price.
	var round_rent: float = float(run_state.economy.get("round_rent", 400.0)) * float(
		scaling.get("min_reward_rent_share", 0.5)
	)
	# Metered cloud cost is real per-prompt spend too, so a cloud-heavy build's
	# contracts must be able to cover it — not just the power they draw.
	var cloud_per_prompt: float = float(run_state.economy.get("cloud_cost_per_prompt", 0.0)) * float(
		tuning.get("cloud_cost_multiplier", 1.0)
	)
	var min_reward: float = (power_per_prompt + cloud_per_prompt) * ceil(effective_work_prompts) * float(
		scaling.get("min_reward_cost_multiplier", 3.0)
	) + round_rent
	# Snapped so varied offers still advertise tidy figures.
	reward = snappedf(maxf(reward, min_reward), 5.0)
	var depth_mult: float = maxf(1.0, float(run_state.depth.get("requirement_mult", 1.0)))
	if depth_mult > 1.0:
		token_requirement *= depth_mult

	var revision_caps: Array = scaling.get("revision_risk_cap_by_tier", [0.04, 0.08, 0.12, 0.16, 0.2, 0.25])
	var revision_risk: float = minf(job_def.revision_risk, float(revision_caps[mini(tier, revision_caps.size() - 1)]))
	var bug_chances: Array = scaling.get("bug_chance_by_tier", [0.04, 0.07, 0.1, 0.12, 0.12, 0.12])
	var bug_chance: float = float(bug_chances[mini(tier, bug_chances.size() - 1)])
	var creep_pcts: Array = scaling.get("scope_creep_pct_by_tier", [0.02, 0.03, 0.04, 0.05, 0.05, 0.05])
	var scope_creep_pct: float = float(creep_pcts[mini(tier, creep_pcts.size() - 1)])

	# What the contract asks for is what the contract asks for. This used to be
	# capped at the tier's own baseline, so every tier-0 posting was judged at 50
	# however demanding its brief said it was, and no build could miss the bar.
	# The baseline now only stands in for a contract that authored no figure.
	var quality_base: float = float(scaling.get("quality_scaling", {}).get("base_threshold", 50.0))
	var quality_per_tier: float = float(scaling.get("quality_scaling", {}).get("per_tier_increase", 8.0))
	var authored: float = float(job_def.quality_threshold)
	if authored <= 0.0:
		authored = quality_base + tier * quality_per_tier
	var quality_threshold: float = clampf(authored, 35.0, 92.0)

	return {
		"definition_id": job_def.id,
		"id": "%s.r%d.i%d" % [job_def.id, round_number, offer_index],
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
		"windfall": job_def.windfall,
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


## The reputation the next band's stretch contract is waiting on, for the job
## board's header. The ordinary board is set by the location; reputation is what
## buys a look at the work above it. Empty when every band is already reachable.
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


static func location_bands(content_db: Node) -> Array:
	return Array(content_db.balance.get("job_scaling", {}).get("location_bands", []))


static func _band_for_tier(tier: int, content_db: Node) -> Dictionary:
	var bands: Array = location_bands(content_db)
	if bands.is_empty():
		return {}
	return Dictionary(bands[clampi(tier, 0, bands.size() - 1)])


## The band the run is currently standing in. Contracts are offered from here,
## so moving up a location is what puts bigger work on the board — the job pool
## follows the seven-chapter ladder rather than a round counter that ran out of
## rungs after twelve.
static func location_tier(run_state: RunState, content_db: Node) -> int:
	var bands: Array = location_bands(content_db)
	var dwelling: String = str(run_state.build.get("dwelling", "bedroom"))
	for index in range(bands.size()):
		if str(Dictionary(bands[index]).get("location", "")) == dwelling:
			return index
	return 0


func _job_tier(job_def: JobDefinition, content_db: Node) -> int:
	var bands: Array = location_bands(content_db)
	var top: int = maxi(0, bands.size() - 1)
	return clampi(job_def.tier, 0, top)


## The band above the run's own, offered at most once a board as a temptation:
## work the location was not built for, paying enough to be worth the risk.
## Reputation is what opens it, so the ladder still has something to climb.
func _stretch_tier_available(run_state: RunState, content_db: Node) -> int:
	var scaling: Dictionary = content_db.balance.get("job_scaling", {})
	var here: int = location_tier(run_state, content_db)
	var stretch: int = here + 1
	if stretch > maxi(0, location_bands(content_db).size() - 1):
		return -1
	var thresholds: Array = scaling.get("tier_unlock_by_reputation", [])
	if stretch >= thresholds.size():
		return -1
	var sales_level: int = int(run_state.build.get("upgrade_levels", {}).get("upgrade.sales_investment", 0))
	var reduction: float = float(scaling.get("sales_level_rep_reduction", 2))
	var needed: float = float(thresholds[stretch]) - float(sales_level) * reduction
	if float(run_state.business.get("reputation", 0.0)) < needed:
		return -1
	return stretch
