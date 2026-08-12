extends Node

## Central simulation controller. Authoritative over game state; UI submits actions here.

## A round is the whole cycle: ROUND_PREP is where contracts are taken and the
## Market is open, IN_ROUND is the work itself (one prompt per burn or cool, for
## as many prompts as the contracts need), and ROUND_END is where the bills land.
enum Phase {
	IDLE,
	ROUND_PREP,
	IN_ROUND,
	ROUND_END,
	## An angel investor draft: free picks only. Paid upgrades live on the Market.
	ANGEL_ROUND,
	RUN_END,
}

## Rounds in the year. The location's contract is the win condition and this is
## its deadline: finishing the contract wins the run, and reaching the end of
## the year without it ends the run. There is no overtime.
const ROUNDS_PER_RUN := 12

## Stands in for "this layout never delivers" when scoring pipelines.
const MAX_ESTIMATED_BURNS := 99.0

## Cloud burst is bought, not given: the account below unlocks the key, and the
## multiplier starts low enough that the repeatable upgrade is the way to power.
const CLOUD_ACCOUNT_UPGRADE := "upgrade.cloud_account"
const CLOUD_BURST_UPGRADE := "upgrade.cloud_compute"
const CLOUD_BURST_BASE_MULTIPLIER := 1.5
const CLOUD_BURST_PER_LEVEL := 0.5

signal work_tick_completed
signal work_session_finished(result: Dictionary)
signal round_statement_ready(statement: Dictionary)
signal burn_resolved(burn: Dictionary)

var run_state: RunState = RunState.new()
var rng: DeterministicRng = DeterministicRng.new()
var effect_resolver: EffectResolver = EffectResolver.new()
var phase: int = Phase.IDLE
var run_seed: int = 0
var round_log: Array[String] = []
var pending_choices: Array = []
var autosave_enabled: bool = true
var tuning: Dictionary = {
	"economy_multiplier": 1.0,
	"token_multiplier": 1.0,
	"cloud_cost_multiplier": 1.0,
	"event_probability_multiplier": 1.0,
}

var _job_system := JobSystem.new()
var _economy_system := EconomySystem.new()
var _compute_system := ComputeSystem.new()
var _heat_system := HeatSystem.new()
var _demand_system := DemandSystem.new()
var _progression_system := ProgressionSystem.new()
var _event_system := EventSystem.new()
var _perk_system := PerkSystem.new()
var _upgrade_system := UpgradeSystem.new()
var _board_system := BoardSystem.new()
var _ascension_system := AscensionSystem.new()
var _achievement_system := AchievementSystem.new()
var queued_boost: bool = false
var queued_cloud: bool = false
var last_session_summary: Dictionary = {}
var last_round_statement: Dictionary = {}

var _work_running: bool = false
var _session_cash_start: float = 0.0
var _round_end_pending: bool = false
var _settling_victory: bool = false
var _subscriptions_cache: Array = []
var _subscriptions_dirty: bool = true
var _action_counter: int = 0
var _work_tick: int = 0
var _auto_arrange_signature: String = ""


func _ready() -> void:
	pass


# --- Test seams --------------------------------------------------------------
# Deliberate public surface onto internals that tests otherwise have to reach
# into by underscore-prefixed name. Kept together and named `debug_*`/system
# accessors so a future split of this file (RunLifecycle/WorkSession/
# SimulationPreview/MarketService) only has to move what is behind them,
# rather than hunt down every test that poked a private field directly.

func compute_system() -> ComputeSystem:
	return _compute_system


func heat_system() -> HeatSystem:
	return _heat_system


func economy_system() -> EconomySystem:
	return _economy_system


func job_system() -> JobSystem:
	return _job_system


func debug_collect_subscriptions() -> Array:
	return _collect_subscriptions()


func debug_invalidate_subscriptions() -> void:
	_invalidate_subscriptions()


func debug_finish_prompt(result: Dictionary) -> void:
	_finish_prompt(result)


func debug_end_session(reason: String) -> void:
	_end_session(reason)


func debug_end_round() -> void:
	_end_round()


func debug_end_run(victory: bool, outcome: String = "") -> void:
	_end_run(victory, outcome)


func debug_settle_reputation(completed: Array, failed: Array) -> float:
	return _settle_reputation(completed, failed)


func debug_apply_cloud_burst() -> bool:
	return _apply_cloud_burst()


func debug_present_angel_offers() -> void:
	_present_angel_offers()


func debug_expire_status_effects() -> void:
	_expire_status_effects()


func debug_set_work_running(value: bool) -> void:
	_work_running = value


func debug_set_round_end_pending(value: bool) -> void:
	_round_end_pending = value


func debug_round_end_pending() -> bool:
	return _round_end_pending


func ensure_job_board() -> void:
	repair_after_load()


func repair_after_load() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_work_running = false
	_invalidate_subscriptions()
	_board_system.ensure_board(run_state, ContentDatabase)
	_compute_system.recalculate(run_state, effect_resolver, _collect_subscriptions(), rng)

	match phase:
		Phase.IN_ROUND:
			if run_state.business.get("active_jobs", []).is_empty():
				phase = Phase.ROUND_PREP
			else:
				# The running flag is transient, but the round it belonged to is
				# in the save. Without resuming the session the loaded board
				# prints no BURN line and DELIVER silently refuses.
				_work_running = _job_system.begin_work_session(run_state, ContentDatabase)
		Phase.ROUND_END:
			phase = Phase.ROUND_PREP
		Phase.ANGEL_ROUND:
			if pending_choices.is_empty():
				_present_angel_offers()
			if pending_choices.is_empty():
				phase = Phase.ROUND_PREP

	_ensure_job_offers()


func _ensure_job_offers() -> void:
	if phase != Phase.ROUND_PREP:
		return
	if run_state.has_active_job() or _work_running:
		return
	# The board is stable for a given round: UI refreshes must not reroll it
	# (that churned the offers and let the simulation rng advance on taps).
	var stamp: String = _board_stamp()
	var offers: Array = run_state.business.get("job_offers", [])
	if not offers.is_empty() and str(run_state.business.get("job_board_stamp", "")) == stamp:
		return
	_demand_system.refresh_demand(run_state)
	_compute_system.recalculate(run_state, effect_resolver, _collect_subscriptions(), rng)
	_job_system.refresh_contract_board(run_state, rng.derive("job_board.%s" % stamp), ContentDatabase, tuning)
	run_state.business["job_board_stamp"] = stamp


## Stable per work session rather than per prompt, which would otherwise reroll
## the board mid-round.
func _board_stamp() -> String:
	return "%d.%d" % [int(run_state.calendar.get("round", 1)), int(run_state.business.get("job_board_seq", 0))]


## Refreshes the job board when in ROUND_PREP. Safe for UI to call on tab open.
func ensure_job_offers() -> void:
	_ensure_job_offers()


func reset_run(p_seed: int = 0) -> void:
	run_seed = p_seed if p_seed != 0 else int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	rng.set_seed(run_seed)
	var difficulty_id: String = MetaProgress.difficulty()
	var difficulty_profiles: Dictionary = ContentDatabase.balance.get("difficulty_profiles", {})
	var profile: Dictionary = difficulty_profiles.get(difficulty_id, difficulty_profiles.get("normal", {}))
	run_state.reset(profile)
	# Contract scaling reads this back rather than the profile dictionary
	# directly, so the difficulty a run started on cannot drift once it is
	# under way — and so an offer scaled mid-run still asks the questions the
	# player actually agreed to.
	run_state.flags["difficulty"] = difficulty_id
	effect_resolver.clear_trace()
	effect_resolver.clear_guard()
	phase = Phase.IDLE
	round_log.clear()
	pending_choices.clear()
	_work_running = false
	_round_end_pending = false
	queued_boost = false
	queued_cloud = false
	last_session_summary = {}
	last_round_statement = {}
	_action_counter = 0
	_work_tick = 0
	_auto_arrange_signature = ""
	_invalidate_subscriptions()
	# Where the run happens is decided before it starts and never moves again,
	# so rent and floor space are settled before anything is bought.
	apply_run_location(run_state, MetaProgress.selected_location())
	# Permanent unlocks land before the board is sized, so an unlocked slot is
	# there to be filled rather than turning up a round late.
	MetaProgress.apply_to_run(run_state)
	_install_permanent_rig()
	_board_system.ensure_board(run_state, ContentDatabase)
	# The location's contract is the run's win condition, not something taken on
	# part-way through, so it is live before the first prompt is spent.
	_ascension_system.activate(run_state, ContentDatabase)
	_compute_system.recalculate(run_state, effect_resolver, _collect_subscriptions(), rng)


## Settles the run into its location. A location is a chapter, not a purchase:
## its rent, floor space and environmental cooling replace the defaults once,
## at the start, rather than being added to whatever was already there.
## `grant_starter_rig` is only turned off by tests that are measuring the room
## itself — its cooling, its floor space, its shelves — where the machine the
## room comes with would be counted as part of the answer.
func apply_run_location(state: RunState, location_id: String, grant_starter_rig: bool = true) -> void:
	var dwelling_costs: Dictionary = ContentDatabase.balance.get("dwelling_costs", {})
	var location: String = location_id
	if not dwelling_costs.has(location):
		location = MetaProgress.DEFAULT_LOCATION
	state.build["dwelling"] = location
	if not dwelling_costs.has(location):
		return
	var stats: Dictionary = dwelling_costs[location]
	var rent_multiplier: float = float(state.economy.get("rent_multiplier", 1.0))
	state.economy["round_rent"] = float(
		stats.get("rent", state.economy.get("round_rent", 0.0))
	) * rent_multiplier
	# The stake the investor puts in when he buys the room. A chapter whose rent
	# is three times the last one's cannot be started on the last one's float.
	if stats.has("starting_cash"):
		state.economy["cash"] = float(stats["starting_cash"]) * float(
			state.economy.get("cash_multiplier", 1.0)
		)
	# A bigger room takes longer to cook. Heat is measured against this rather
	# than a fixed hundred, so moving up buys headroom as well as floor space.
	state.compute["heat_capacity"] = float(
		stats.get("heat_capacity", state.compute.get("heat_capacity", 100.0))
	)
	if grant_starter_rig:
		_grant_location_starter_rig(state, stats)
	state.compute["cooling"] = ComputeSystem.derive_cooling(state)
	# The contract belongs to the location, so moving the run moves the contract
	# with it. Nothing else can set it: a run measured against the chapter it is
	# no longer in has no way to be won.
	_ascension_system.activate(state, ContentDatabase)


## The machine the room comes with. Contracts are sized against the rig a
## location expects rather than against whatever the player happens to own, so a
## run that starts in the warehouse on a second-hand laptop would be handed work
## a thousand times beyond it.
func _grant_location_starter_rig(state: RunState, stats: Dictionary) -> void:
	for upgrade_id in Array(stats.get("starting_hardware", [])):
		var upgrade: UpgradeDefinition = ContentDatabase.get_upgrade(str(upgrade_id))
		if upgrade == null:
			continue
		if UpgradeSystem.installed_count(state, UpgradeSystem.installed_key(upgrade)) > 0:
			continue
		_upgrade_system.install_carried(state, str(upgrade_id), ContentDatabase, effect_resolver)


## Racks the machines earned through the permanent starting-rig unlock ladder.
## A fresh run is otherwise a fresh game from the start — nothing a previous run
## bought arrives — so this is the one place hardware crosses runs, and only
## because a pick was spent on it after beating the whole campaign.
##
## Free of charge but not of floor space: a small room racks what fits, and the
## call from `advance_to_next_chapter` racks the rest once a bigger room opens.
## That second call is why a rung already standing is skipped rather than
## installed again.
func _install_permanent_rig() -> void:
	var installed: int = 0
	for upgrade_id in MetaProgress.starting_rig():
		var upgrade: UpgradeDefinition = ContentDatabase.get_upgrade(str(upgrade_id))
		if upgrade == null:
			continue
		if UpgradeSystem.installed_key(upgrade) in Array(run_state.build.get("hardware", [])):
			continue
		if _upgrade_system.install_carried(
			run_state, str(upgrade_id), ContentDatabase, effect_resolver
		):
			installed += 1
	if installed > 0:
		round_log.append("Your permanent rig is already racked: %d machine(s)." % installed)


func start_run(p_seed: int = 0) -> void:
	reset_run(p_seed)
	phase = Phase.ROUND_PREP
	EventBus.emit_event(EventBus.EVENT_RUN_STARTED)
	_begin_round()


## Opens a fresh round: a clean prompt counter, a new contract board, and the
## Market open. Nothing carries over from the last round except what the player
## owns, because a round only ends once its contracts have all resolved.
func _begin_round() -> void:
	EventBus.emit_event(EventBus.EVENT_ROUND_STARTED)
	run_state.calendar["prompt"] = 1
	run_state.business["job_board_seq"] = 0
	run_state.economy["costs_this_round"] = 0.0
	# Perks contribute their demand during round.started, so the modifier is put
	# back to its permanent base first. Without this a perk worth "+1 demand"
	# added another +1 every round until the board was permanently full.
	run_state.business["demand_modifier"] = float(
		run_state.business.get("demand_modifier_base", 0.0)
	)
	effect_resolver.begin_action("round.started")
	var mod_ctx := ModifierContext.new("round.started", run_state)
	mod_ctx.rng = rng.derive("round.started")
	effect_resolver.dispatch("round.started", mod_ctx, _collect_subscriptions())
	# Read after the dispatch, so this round's board reflects this round's perks.
	_demand_system.refresh_demand(run_state)
	_compute_system.recalculate(run_state, effect_resolver, _collect_subscriptions(), rng)
	_job_system.generate_offers(run_state, rng.derive("job_offers"), ContentDatabase, tuning)
	run_state.business["job_board_stamp"] = _board_stamp()
	phase = Phase.ROUND_PREP


func accept_job(job_id: String) -> bool:
	if phase != Phase.ROUND_PREP or _work_running:
		return false
	if not can_accept_offer(job_id):
		return false
	if not _job_system.accept_job(run_state, job_id):
		return false
	run_state.statistics["jobs_accepted"] = int(run_state.statistics.get("jobs_accepted", 0)) + 1
	EventBus.emit_event(EventBus.EVENT_JOB_ACCEPTED, {"job_id": job_id})
	_autosave()
	return true


## How loaded the round's slate is relative to its tightest deadline.
## Pass an offer to preview the load if that offer were also accepted.
## ratio 1.0 means the slate needs exactly every prompt its tightest deadline
## allows. Parallel lanes do not make the slate lighter — they share one batch —
## so throughput is measured against the rig's rate either way.
func queue_load_info(extra_offer: Dictionary = {}) -> Dictionary:
	var rate: float = maxf(1.0, float(run_state.compute.get("token_rate", 1.0)))
	var tokens: float = 0.0
	var deadline: int = 0
	var jobs: Array = []
	jobs.append_array(run_state.business.get("active_jobs", []))
	jobs.append_array(run_state.business.get("job_queue", []))
	if not extra_offer.is_empty():
		jobs.append(extra_offer)
	for job in jobs:
		tokens += maxf(0.0, float(job.get("tokens_remaining", job.get("token_requirement", 0.0))))
		var job_deadline: int = int(job.get("prompts_remaining", job.get("deadline_prompts", 0)))
		if job_deadline > 0:
			deadline = job_deadline if deadline == 0 else mini(deadline, job_deadline)
	var prompts_needed: float = tokens / rate
	var ratio: float = 0.0 if deadline <= 0 else prompts_needed / float(deadline)
	return {
		"jobs": jobs.size(),
		"tokens": tokens,
		"prompts_needed": prompts_needed,
		"deadline_prompts": deadline,
		"ratio": ratio,
		"over_capacity": ratio > 1.0,
		"cap": queue_capacity_cap(),
		"job_slots": job_slots(),
	}


## Live picture of the round's costs: the flat charges that fall due when the
## round ends, and the metered ones that have already been paid prompt by prompt.
## Rent does not grow with a long round; the power bill does.
func cost_forecast() -> Dictionary:
	var cloud_multiplier: float = float(tuning.get("cloud_cost_multiplier", 1.0))
	var rent: float = float(run_state.economy.get("round_rent", 0.0))
	var recurring: float = float(run_state.economy.get("recurring_costs", 0.0))
	# Already carries the multiplier from accrual; billed at face value.
	var cloud_bill: float = float(run_state.economy.get("cloud_surcharge_liability", 0.0))
	var power_per_prompt: float = float(run_state.economy.get("power_cost_per_prompt", 0.0))
	var cloud_per_prompt: float = float(run_state.economy.get("cloud_cost_per_prompt", 0.0)) * cloud_multiplier
	var operating_per_prompt: float = power_per_prompt + cloud_per_prompt
	var operating_so_far: float = float(run_state.economy.get("costs_this_round", 0.0))
	var fixed_due: float = rent + recurring + cloud_bill
	return {
		"rent": rent,
		"recurring": recurring,
		"cloud_bill": cloud_bill,
		"power_per_prompt": power_per_prompt,
		"cloud_per_prompt": cloud_per_prompt,
		"operating_per_prompt": operating_per_prompt,
		"operating_so_far": operating_so_far,
		"fixed_due": fixed_due,
		"accrued_total": operating_so_far + fixed_due,
		"prompts_used": prompts_used_this_round(),
		"power_draw": float(run_state.compute.get("power_draw", 0.0)),
	}


## What this round still owes and therefore what is genuinely free to spend, so
## the player is never surprised by a bill they had already spent.
func bills_outlook() -> Dictionary:
	var costs: Dictionary = cost_forecast()
	# Only the end-of-round lump is held back. Power and cloud are metered prompt
	# by prompt out of the income the same prompts bring in, so counting a whole
	# round of them here would say "safe to spend nothing" every round.
	var still_due: float = float(costs.get("fixed_due", 0.0))
	var cash: float = float(run_state.economy.get("cash", 0.0))
	return {
		"due": still_due,
		"rent": float(costs.get("rent", 0.0)),
		"prompts_used": int(costs.get("prompts_used", 0)),
		"cash": cash,
		"spendable": maxf(0.0, cash - still_due),
		"shortfall": maxf(0.0, still_due - cash),
	}


## Warning text for a purchase that would leave this round's bills unpayable.
func purchase_bill_warning(cost: float) -> String:
	if cost <= 0.0:
		return ""
	var outlook: Dictionary = bills_outlook()
	var left: float = float(outlook.get("cash", 0.0)) - cost
	var due: float = float(outlook.get("due", 0.0))
	if left >= due:
		return ""
	return "Leaves you %s short of the %s due when this round ends." % [
		NumberFormat.format_cash(due - left),
		NumberFormat.format_cash(due),
	]


## Cooling an upgrade brings with it, for previewing a purchase.
func _cooling_from_effects(effects: Array) -> float:
	var total: float = 0.0
	for effect in effects:
		if effect is EffectDefinition and effect.target == "compute.cooling":
			total += float(effect.value)
	return total


## Whether cooling can keep up with a given power draw, and by how much. Used to
## warn the player before they buy hardware their space cannot cool.
func heat_outlook(extra_power: float = 0.0, extra_cooling: float = 0.0) -> Dictionary:
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	var gain_factor: float = float(heat_cfg.get("gain_per_power", 0.025))
	var cooling_factor: float = float(heat_cfg.get("cooling_factor", 0.35))
	var power: float = float(run_state.compute.get("power_draw", 0.0)) + extra_power
	var cooling: float = float(run_state.compute.get("cooling", 0.0)) + extra_cooling
	var gain: float = power * gain_factor
	var shed: float = cooling * cooling_factor
	return {
		"power_draw": power,
		"cooling": cooling,
		"heat_per_prompt": gain - shed,
		"sustainable": shed >= gain,
		"cooling_needed": gain / maxf(0.0001, cooling_factor),
	}


## Warning text for a hardware purchase that cooling could not keep up with.
func upgrade_heat_warning(upgrade_id: String) -> String:
	var upgrade: UpgradeDefinition = ContentDatabase.get_upgrade(upgrade_id)
	if upgrade == null or upgrade.hardware_key == "":
		return ""
	var hardware: Dictionary = ContentDatabase.balance.get("hardware_curves", {}).get(upgrade.hardware_key, {})
	var extra_cooling: float = _cooling_from_effects(upgrade.effects)
	var outlook: Dictionary = heat_outlook(float(hardware.get("power_draw", 0.0)), extra_cooling)
	if bool(outlook.get("sustainable", true)):
		return ""
	var shortfall: float = float(outlook.get("cooling_needed", 0.0)) - float(outlook.get("cooling", 0.0))
	var warning: String = "Your space cannot cool this: +%.0f heat per prompt. Needs %d cooling, you would have %d." % [
		float(outlook.get("heat_per_prompt", 0.0)),
		int(ceil(float(outlook.get("cooling_needed", 0.0)))),
		int(outlook.get("cooling", 0.0)),
	]
	var remedy: String = cooling_remedy(shortfall)
	if remedy != "":
		warning += " %s" % remedy
	return warning


## The cooling on sale right now that would close a shortfall, named and
## counted. A warning that only says "not enough cooling" leaves the player
## hunting the Market for a shelf that may look empty; this says what to buy.
func cooling_remedy(shortfall: float) -> String:
	if shortfall <= 0.0:
		return ""
	var best: UpgradeDefinition = null
	var best_cooling: float = 0.0
	for upgrade in ContentDatabase.upgrades:
		if not ("cooling" in Array(upgrade.tags)):
			continue
		if not UpgradeSystem.prerequisites_met(run_state, upgrade, ContentDatabase):
			continue
		if UpgradeSystem.is_maxed(run_state, upgrade):
			continue
		if not upgrade.repeatable and upgrade.id in run_state.build.get("upgrades", []):
			continue
		var cooling: float = _cooling_from_effects(upgrade.effects)
		if cooling <= 0.0:
			continue
		# The smallest unit that still closes the gap in a sensible number of
		# purchases, so the advice is the cheap thing rather than the biggest.
		if best == null or cooling < best_cooling:
			best = upgrade
			best_cooling = cooling
	if best == null:
		return "Nothing on the Cooling shelf reaches this yet — take the next property up first."
	var units: int = int(ceil(shortfall / best_cooling))
	if units <= 1:
		return "A %s from the Market's Cooling shelf would cover it." % best.name
	return "About %d × %s from the Market's Cooling shelf would cover it." % [units, best.name]


func queue_capacity_cap() -> float:
	return float(ContentDatabase.balance.get("job_scaling", {}).get("queue_capacity_cap", 2.0))


## Offers may load the queue up to (or slightly over) throughput capacity,
## but not so far past it that the deadline is hopeless.
func can_accept_offer(job_id: String) -> bool:
	if phase != Phase.ROUND_PREP or _work_running:
		return false
	var offer: Dictionary = {}
	for candidate in run_state.business.get("job_offers", []):
		if candidate is Dictionary and str(candidate.get("id", "")) == job_id:
			offer = candidate
			break
	if offer.is_empty():
		return false
	if run_state.business.get("job_queue", []).is_empty():
		return true
	var info: Dictionary = queue_load_info(offer)
	return float(info.get("ratio", 0.0)) <= queue_capacity_cap()


func can_start_work() -> bool:
	return phase == Phase.ROUND_PREP and run_state.has_pending_work() and not _work_running


func is_work_running() -> bool:
	return _work_running and phase == Phase.IN_ROUND


## How many contracts the rig works at once, and which ones a burn would advance.
func job_slots() -> int:
	return ComputeSystem.job_slots(run_state)


func burn_lanes() -> Array:
	return _job_system.burn_lane_jobs(run_state)


## Prompts spent on the round so far. Open-ended: a round lasts as long as its
## contracts do, so this is a tally rather than a budget.
func prompts_used_this_round() -> int:
	return maxi(0, int(run_state.calendar.get("prompt", 1)) - 1)


## Queues BOOST to fire as soon as work starts. Only allowed pre-session.
func set_queued_boost(enabled: bool) -> void:
	if can_start_work():
		queued_boost = enabled


## Queues a cloud burst to fire as soon as work starts. Only allowed pre-session,
## and only once the run has an account to bill it to.
func set_queued_cloud(enabled: bool) -> void:
	if can_start_work() and cloud_enabled():
		queued_cloud = enabled


## Opens the Burn Board. Nothing is produced until the player burns a batch:
## from here the session waits on burn_batch / cool_hardware / ship_focused_job.
func start_work() -> void:
	if not can_start_work():
		return
	# The pre-board behaviour, kept for balance sweeps and headless drives.
	if FeatureFlags.is_enabled("auto_work_loop_enabled"):
		start_work_sync()
		work_session_finished.emit({"phase": phase, "summary": last_session_summary})
		return
	_work_running = true
	round_log.clear()
	_work_tick = 0
	_session_cash_start = float(run_state.economy.get("cash", 0.0))
	_board_system.ensure_board(run_state, ContentDatabase)
	_compute_system.recalculate(run_state, effect_resolver, _collect_subscriptions(), rng)
	if not _job_system.begin_work_session(run_state, ContentDatabase):
		_work_running = false
		return
	phase = Phase.IN_ROUND
	_fire_queued_options()
	_follow_focused_workflow()
	for job in run_state.business.get("active_jobs", []):
		EventBus.emit_event(EventBus.EVENT_JOB_STARTED, {"job_id": job.get("id", "")})
	work_tick_completed.emit()
	_autosave()


func _fire_queued_options() -> void:
	if queued_boost:
		_apply_boost()
	if queued_cloud:
		_apply_cloud_burst()
	queued_boost = false
	queued_cloud = false


func start_work_sync() -> Dictionary:
	if not can_start_work():
		return {"ok": false}
	_work_running = true
	round_log.clear()
	_work_tick = 0
	_session_cash_start = float(run_state.economy.get("cash", 0.0))
	_board_system.ensure_board(run_state, ContentDatabase)
	_compute_system.recalculate(run_state, effect_resolver, _collect_subscriptions(), rng)
	if not _job_system.begin_work_session(run_state, ContentDatabase):
		_work_running = false
		return {"ok": false}
	phase = Phase.IN_ROUND
	_fire_queued_options()
	for job in run_state.business.get("active_jobs", []):
		EventBus.emit_event(EventBus.EVENT_JOB_STARTED, {"job_id": job.get("id", "")})
	# Nobody is here to arrange the board, so the auto-drive does it: without this
	# the bench would fill up with modules that never reach the pipeline.
	auto_arrange_board()
	var safety: int = 0
	while phase == Phase.IN_ROUND and safety < 500:
		safety += 1
		var result: Dictionary = _execute_tick()
		if not result.get("ok", true):
			_end_session("collapsed")
			break
		for message in result.get("messages", []):
			round_log.append(str(message))
		_advance_prompt(result)
		var stop: String = _session_stop_reason(result)
		if stop != "":
			_end_session(stop)
			break
	# A round that cannot resolve itself inside the safety limit is a stuck round
	# rather than an endless one, so it settles as if the contracts had run out.
	if phase == Phase.IN_ROUND:
		_end_session("stalled")
	_work_running = false
	return {"ok": true, "phase": phase}


# --- Burn Board actions ------------------------------------------------------

## What BURN TOKENS would produce right now, resolved on a throwaway copy of the
## state so the board screen can show the outcome without causing it.
##
## `burn.heat` is only the pipeline's own stage heat. Every prompt — burn or
## cool — also gains ambient heat from powered-on hardware and loses some to
## cooling capacity (`HeatSystem.process_prompt`), which `run_burn` applies too.
## `total_heat` is the two combined: the number the heat bar will actually move
## by, which is what the UI should show instead of the stage heat alone.
func preview_burn(stage_limit: int = -1) -> Dictionary:
	if phase != Phase.IN_ROUND:
		return {"ok": false, "reason": "Not working."}
	var clone := RunState.new()
	clone.from_dict(run_state.to_dict())
	var heat_before: float = float(clone.compute.get("heat", 0.0))
	var preview_resolver := EffectResolver.new()
	var result: Dictionary = _job_system.run_burn(
		clone,
		_burn_rng(),
		preview_resolver,
		_collect_subscriptions(),
		tuning,
		_compute_system,
		_heat_system,
		_economy_system,
		_board_system,
		stage_limit,
		ResolveMode.PREVIEW
	)
	var burn: Dictionary = result.get("burn", {"ok": false, "reason": "The pipeline is empty."})
	if burn.get("ok", false):
		burn = burn.duplicate(true)
		burn["total_heat"] = float(clone.compute.get("heat", 0.0)) - heat_before
	return burn


## What COOL would actually do to the heat bar right now: the vent, plus the
## same ambient heat/cooling pass a burn prompt gets, since `end_prompt` runs
## either way. This is what makes COOL sometimes barely move the bar — the
## ambient gain can eat most or all of the vent.
func preview_cool() -> Dictionary:
	if not can_burn():
		return {"ok": false, "reason": "Not working."}
	var clone := RunState.new()
	clone.from_dict(run_state.to_dict())
	var heat_before: float = float(clone.compute.get("heat", 0.0))
	var preview_resolver := EffectResolver.new()
	var result: Dictionary = _job_system.run_cooling_prompt(
		clone,
		_burn_rng(),
		preview_resolver,
		_collect_subscriptions(),
		tuning,
		_compute_system,
		_heat_system,
		_economy_system,
		ResolveMode.PREVIEW
	)
	if not result.get("ok", false):
		return result
	result["heat_before"] = heat_before
	result["heat_after"] = float(clone.compute.get("heat", 0.0))
	result["total_heat"] = float(result["heat_after"]) - heat_before
	return result


## Burns one batch through the pipeline, which spends one prompt.
##
## `stage_limit` is how KILL PROCESS lands: the stages that had already fired
## keep their output and the rest of the batch is lost.
func burn_batch(stage_limit: int = -1) -> Dictionary:
	if not can_burn():
		return {"ok": false, "reason": "Not working."}
	var result: Dictionary = _job_system.run_burn(
		run_state,
		_burn_rng(),
		effect_resolver,
		_collect_subscriptions(),
		tuning,
		_compute_system,
		_heat_system,
		_economy_system,
		_board_system,
		stage_limit
	)
	if not result.get("ok", false):
		return result
	# Only a committed action spends a prompt's worth of RNG. A refusal that
	# touched nothing must not shift the seed the next attempt rolls against —
	# otherwise a failed action rerolls a deterministic outcome for free.
	_work_tick += 1
	var burn: Dictionary = result.get("burn", {})
	burn_resolved.emit(burn)
	_finish_prompt(result)
	return result


## Spends a prompt on the hardware rather than the work.
func cool_hardware() -> Dictionary:
	if not can_burn():
		return {"ok": false, "reason": "Not working."}
	var result: Dictionary = _job_system.run_cooling_prompt(
		run_state,
		_burn_rng(),
		effect_resolver,
		_collect_subscriptions(),
		tuning,
		_compute_system,
		_heat_system,
		_economy_system
	)
	if not result.get("ok", false):
		return result
	_work_tick += 1
	_finish_prompt(result)
	return result


## Delivers the focused contract now, finished or not.
func ship_focused_job() -> bool:
	if phase != Phase.IN_ROUND or not _work_running:
		return false
	var result: Dictionary = _job_system.ship_focused_job(run_state)
	if not result.get("ok", false):
		return false
	round_log.append("Shipped %s." % str(result.get("job", {}).get("name", "the contract")))
	_settle_if_resolved()
	return true


func abandon_focused_job() -> bool:
	if phase != Phase.IN_ROUND or not _work_running:
		return false
	var result: Dictionary = _job_system.abandon_focused_job(run_state)
	if not result.get("ok", false):
		return false
	round_log.append("Walked away from %s." % str(result.get("job", {}).get("name", "the contract")))
	_settle_if_resolved()
	return true


func focus_job(job_id: String) -> bool:
	if phase != Phase.IN_ROUND:
		return false
	if not _job_system.set_focus(run_state, job_id):
		return false
	_follow_focused_workflow()
	return true


## The Burn Board edits whichever workflow is active, so focusing a contract
## points the editor at the pipeline that contract is actually worked through.
## Without this, tuning the board mid-job would quietly edit someone else's.
func _follow_focused_workflow() -> void:
	var job: Dictionary = _job_system.focused_job(run_state)
	if job.is_empty():
		return
	var workflow_id: String = str(job.get("workflow_id", ""))
	var list: Array = _board_system.workflows(run_state)
	for index in range(list.size()):
		if str(list[index].get("id", "")) == workflow_id:
			_board_system.set_active_workflow(run_state, index)
			return


func focused_job() -> Dictionary:
	return _job_system.focused_job(run_state)


## The contract the machine will boot with when the first BURN opens the
## session: the head of the accepted queue, prepared exactly as `start_work`
## will prepare it. Display only — nothing in the queue is mutated. Empty when
## nothing has been accepted, or once the session is running and `focused_job`
## is the real answer.
func queued_job_preview() -> Dictionary:
	if _work_running:
		return {}
	var queue: Array = run_state.business.get("job_queue", [])
	if queue.is_empty() or not queue[0] is Dictionary:
		return {}
	return _job_system.prepare_offer_preview(queue[0], run_state, ContentDatabase)


func can_burn() -> bool:
	if phase != Phase.IN_ROUND or not _work_running:
		return false
	if _job_system.focused_job(run_state).is_empty():
		return false
	return _board_system.filled_slot_count(run_state) > 0


func board_slots() -> Array:
	return _board_system.slots(run_state)


func owned_operations() -> Array:
	return _board_system.owned_operations(run_state)


func filled_slot_count() -> int:
	return _board_system.filled_slot_count(run_state)


## Slots a contract has taken over are locked only on the workflow that contract
## is being worked through. Editing a different workflow is unconstrained: it is
## not the pipeline the legacy code is sitting in.
func _editing_job() -> Dictionary:
	var job: Dictionary = focused_job()
	if job.is_empty():
		return {}
	var editing_id: String = str(_board_system.active_workflow(run_state).get("id", ""))
	return job if str(job.get("workflow_id", "")) == editing_id else {}


func place_operation(operation_id: String, slot_index: int) -> bool:
	if not _board_system.place_operation(run_state, _editing_job(), operation_id, slot_index):
		return false
	_autosave()
	return true


func clear_slot(slot_index: int) -> bool:
	if not _board_system.clear_slot(run_state, _editing_job(), slot_index):
		return false
	_autosave()
	return true


func swap_slots(from_index: int, to_index: int) -> bool:
	if not _board_system.swap_slots(run_state, _editing_job(), from_index, to_index):
		return false
	_autosave()
	return true


## The contract whose constraints the workflow editor should honour: the focused
## one only while its own pipeline is on screen.
func editing_job() -> Dictionary:
	return _editing_job()


## Greedily improves the pipeline by trying each benched module in each usable
## slot and keeping any swap that scores better. Used by the auto-drive and
## offered to the player as a starting point; a human can always do better by
## caring about heat, cash and the contract's rules.
func auto_arrange_board(max_passes: int = 2) -> bool:
	if phase != Phase.IN_ROUND:
		return false
	var job: Dictionary = focused_job()
	if job.is_empty():
		return false
	var slots: Array = _board_system.slots(run_state)
	# Scoring a layout means resolving a burn, so skip the work entirely when
	# neither the modules nor the contract have changed since the last pass.
	var signature: String = "%s|%s|%s" % [
		str(_board_system.owned_operations(run_state)), str(slots), str(job.get("id", ""))
	]
	if signature == _auto_arrange_signature:
		return false
	var changed: bool = false
	for _pass in range(max_passes):
		var best_score: float = _layout_score(job)
		var best_slot: int = -1
		var best_module: String = ""
		for operation_id in _board_system.owned_operations(run_state):
			if str(operation_id) in slots:
				continue
			for index in range(slots.size()):
				if not _board_system.is_slot_usable(run_state, job, index):
					continue
				var displaced: String = str(slots[index])
				slots[index] = str(operation_id)
				var score: float = _layout_score(job)
				slots[index] = displaced
				if score > best_score + 0.001:
					best_score = score
					best_slot = index
					best_module = str(operation_id)
		if best_slot < 0:
			break
		slots[best_slot] = best_module
		changed = true
	_auto_arrange_signature = "%s|%s|%s" % [
		str(_board_system.owned_operations(run_state)), str(slots), str(job.get("id", ""))
	]
	if changed:
		_autosave()
	return changed


## Scores a layout by the cash it would earn per prompt spent, which is the thing
## that actually keeps a run alive. Everything else folds into that: bugs shrink
## the fee, tokens and quality set how many burns delivery takes, and heat adds
## the cooling prompts needed to survive them.
func _layout_score(job: Dictionary) -> float:
	var preview: Dictionary = preview_burn()
	if not preview.get("ok", false):
		return -MAX_ESTIMATED_BURNS
	if float(preview.get("cost", 0.0)) > float(run_state.economy.get("cash", 0.0)):
		return -MAX_ESTIMATED_BURNS

	# A contract needs its tokens and its quality gate, so the binding constraint
	# is whichever is further away. Quality past the threshold buys nothing.
	var remaining: float = maxf(1.0, float(job.get("tokens_remaining", 1.0)))
	var burns: float = remaining / maxf(1.0, float(preview.get("progress_tokens", 0.0)))
	var quality_gap: float = maxf(
		0.0, float(job.get("quality_threshold", 0.0)) - float(job.get("quality", 0.0))
	)
	if quality_gap > 0.0:
		var quality_per_burn: float = float(preview.get("quality", 0.0))
		burns = maxf(burns, (
			quality_gap / quality_per_burn if quality_per_burn > 0.0 else MAX_ESTIMATED_BURNS
		))
	burns = minf(maxf(1.0, burns), MAX_ESTIMATED_BURNS)

	# `total_heat` is the authoritative figure the burn would actually put on
	# the bar — ambient gain and cooling already netted against each other by
	# HeatSystem — rather than the stage's own heat re-derived by hand against
	# a cooling factor this scorer used to ignore entirely.
	var net_heat: float = maxf(0.0, float(preview.get("total_heat", 0.0)))
	var prompts: float = burns * (
		1.0 + net_heat / maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))
	)

	# What the client will actually pay for what this pipeline delivers.
	var known: float = float(preview.get("bugs_added", 0)) * burns + float(job.get("known_bugs", 0))
	var hidden: float = float(preview.get("hidden_added", 0)) * burns + float(job.get("hidden_bugs", 0))
	var fee: float = float(job.get("reward", 0.0))
	fee *= maxf(0.3, 1.0 - 0.08 * known)
	fee *= maxf(0.25, 1.0 - 0.06 * hidden)

	# Metered running costs, not just power: a cloud-heavy layout's per-prompt
	# bill is what `cost_forecast` already tracks for the bills screen, so the
	# same figure — power and cloud metering both — is what should be scored.
	var operating_per_prompt: float = float(cost_forecast().get("operating_per_prompt", 0.0))
	# Pipeline stage costs are only paid on a burn, but the metered power and
	# cloud bills land on every prompt the run spends — cooling prompts
	# included. Charging them per burn alone made hot layouts look cheaper
	# than the cooling they force.
	var outgoings: float = burns * float(preview.get("cost", 0.0)) + prompts * operating_per_prompt
	return (fee - outgoings) / prompts


func board_system() -> BoardSystem:
	return _board_system


# --- Ascension ----------------------------------------------------------

func infrastructure_tier() -> int:
	return _ascension_system.infrastructure_tier(run_state, ContentDatabase)


func ascension_active() -> bool:
	return _ascension_system.is_active(run_state)


func ascension_active_contract() -> Dictionary:
	return _ascension_system.active_contract(run_state, ContentDatabase)


func ascension_progress() -> Dictionary:
	return _ascension_system.progress(run_state, ContentDatabase)


## Where the run stands against the contract of the location it is being played
## in, for the readouts that have to say so without re-deriving any of the rules.
func ascension_summary() -> Dictionary:
	return _ascension_system.summary(run_state, ContentDatabase)


## The contract this run is being played for.
func ascension_boss_contract() -> Dictionary:
	return _ascension_system.location_contract(run_state, ContentDatabase)


## The location's boss has cleared: the game is beaten. The run is not thrown away
## with it. The round it happened in is settled properly — the work pays out, the
## bills land, the angels call if the rent cleared — and the phase that would have
## come next is remembered, so continuing into endless mode resumes from a clean
## round boundary instead of the middle of a burn.
func _reach_victory(contract: Dictionary) -> void:
	_ascension_system.record_final(run_state, contract)
	run_state.flags["victory"] = true
	run_state.flags["outcome"] = "ascended"
	run_state.flags["ascension_tier"] = int(contract.get("tier", 1))
	round_log.append("%s is complete. You have ascended." % str(contract.get("name", "The contract")))
	MetaProgress.record_best_score(RunScore.compute(run_state, ContentDatabase))
	MetaProgress.record_ascension(str(contract.get("id", "")))
	_complete_run_location()
	# Permanence is the reward for finishing the whole campaign. A chapter goal
	# cleared on the way up is a level-up inside the run — it banks no picks,
	# advances no age and hands over no rule unlocks; only the summit pays.
	if _run_is_final_chapter():
		MetaProgress.bank_victory(maxi(1, int(contract.get("picks", 1))))
		if bool(contract.get("unlocks_age", false)):
			MetaProgress.advance_age(Ages.max_age_index())
		var ending_unlock: String = str(contract.get("ending_unlock", ""))
		if ending_unlock != "":
			MetaProgress.grant_ending_unlock(ending_unlock)
	_bank_run_legacy(true)
	_settling_victory = true
	_end_session("ascended")
	_settling_victory = false
	# Settling normally leaves the round closed out into either a draft or the next
	# round's prep, but a loss check swallowed mid-settle can leave it in neither.
	# The phase to resume on is therefore taken from what is actually on the table
	# rather than from wherever the settle happened to stop.
	run_state.flags["post_victory_phase"] = _phase_name(
		Phase.ANGEL_ROUND if not pending_choices.is_empty() else Phase.ROUND_PREP
	)
	phase = Phase.RUN_END
	EventBus.emit_event(EventBus.EVENT_RUN_ENDED, {"victory": true})
	_autosave()


## Beating the boss retires the chapter and opens the next one. Guarded once-only
## because `_end_run`'s "ascended" branch settles the same victory from the other
## direction, and a location must not be completed twice.
##
## The profile records the clear, but the campaign selection stays put: the win
## continues in place through `advance_to_next_chapter`, and a run started fresh
## afterwards is a fresh game from the bedroom, not a resume.
func _complete_run_location() -> void:
	if bool(run_state.flags.get("location_completed", false)):
		return
	run_state.flags["location_completed"] = true
	var location: String = str(run_state.build.get("dwelling", ""))
	if location == "":
		return
	run_state.flags["next_location"] = MetaProgress.next_location_after(location)
	MetaProgress.complete_location(location)


## Whether the run is being played in the campaign's last location — the only
## place a victory is the end of the game rather than of a chapter, and so the
## only place permanent rewards are paid out.
func _run_is_final_chapter() -> bool:
	return MetaProgress.next_location_after(str(run_state.build.get("dwelling", ""))) == ""


## The location this victory opened up, empty if the run was played in the last
## chapter there is.
func next_location_unlocked() -> String:
	return str(run_state.flags.get("next_location", ""))


## True while a victory is being settled: the bills landing in that window cannot
## take the win back, and no overlay should open in front of the verdict.
func is_settling_victory() -> bool:
	return _settling_victory


## Carries a won run on rather than starting over. Everything the run owns stays
## put; from here the calendar is behind it and the costs climb every round, so
## the tail lasts exactly as long as the build can hold it up.
##
## Only the last chapter offers this. A mid-campaign win is a level-up — the next
## location is the continuation, and an endless tail there would just be a bigger
## bedroom. The tail exists for the run with nowhere further up to go.
func continue_after_victory() -> bool:
	if phase != Phase.RUN_END or not bool(run_state.flags.get("victory", false)):
		return false
	if next_location_unlocked() != "":
		return false
	run_state.flags["post_victory"] = true
	run_state.flags["victory"] = false
	run_state.flags["outcome"] = ""
	phase = _phase_from_name(str(run_state.flags.get("post_victory_phase", "ROUND_PREP")))
	if phase == Phase.RUN_END or phase == Phase.IDLE:
		phase = Phase.ROUND_PREP
	round_log.append(
		"The contract is signed and the company does not stop. "
		+ "From here the bills climb every round and nothing is left to prove."
	)
	_ensure_job_offers()
	_autosave()
	return true


## Whether the run has already beaten a Tier 3 contract and chosen to carry on.
func in_post_victory() -> bool:
	return bool(run_state.flags.get("post_victory", false))


## Moves a mid-campaign win into the next chapter as the same business. The
## angel's goal is the end of a chapter, not the end of the game: cash, perks,
## modules, workflows, upgrades and reputation all carry forward — what changes
## is the room, the rent, and the contract the run is measured against, which
## is the next location's bigger one. Only the last chapter has no next room;
## its continuation is `continue_after_victory`.
func advance_to_next_chapter() -> bool:
	if phase != Phase.RUN_END or not bool(run_state.flags.get("victory", false)):
		return false
	var next_location: String = next_location_unlocked()
	if next_location == "":
		return false
	run_state.flags["victory"] = false
	run_state.flags["outcome"] = ""
	run_state.flags["location_completed"] = false
	run_state.flags["next_location"] = ""
	run_state.flags["post_victory_phase"] = ""
	# The investor's stake pays for the room, but the company keeps its own
	# float: the stake is a floor under the new rent, not a replacement for
	# what the last chapter earned.
	var cash_carried: float = float(run_state.economy.get("cash", 0.0))
	# The next room's own machine is a stake for a run that starts there. A run
	# that won its way up arrives with the rig it won on, and nothing else.
	apply_run_location(run_state, next_location, false)
	run_state.economy["cash"] = maxf(cash_carried, float(run_state.economy.get("cash", 0.0)))
	# A permanent rig rung the old room had no floor for is racked now that
	# there is a room that fits it.
	_install_permanent_rig()
	# A new room starts cold, and the new chapter starts its year at round one.
	run_state.compute["heat"] = 0.0
	run_state.flags["fire_risk"] = false
	run_state.calendar["round"] = 1
	round_log.append(
		"Moved into the %s. Everything comes with you — the contract is bigger."
		% MetaProgress.location_name(next_location)
	)
	_begin_round()
	# A draft pick earned on the winning round is still on the table; the new
	# chapter opens once it has been taken, exactly as a round boundary would.
	if not pending_choices.is_empty():
		phase = Phase.ANGEL_ROUND
	_autosave()
	return true


# --- Workflows ----------------------------------------------------------

func workflows() -> Array:
	return _board_system.workflows(run_state)


func workflow_count() -> int:
	return _board_system.workflow_count(run_state)


func workflow_capacity() -> int:
	return _board_system.workflow_capacity(run_state)


func active_workflow_index() -> int:
	return _board_system.active_workflow_index(run_state)


func active_workflow() -> Dictionary:
	return _board_system.active_workflow(run_state)


## Points the workflow editor at another pipeline. Purely a view change: which
## workflow a contract burns through is set by its assignment.
func set_active_workflow(index: int) -> bool:
	if not _board_system.set_active_workflow(run_state, index):
		return false
	_autosave()
	return true


func create_workflow(name: String = "") -> Dictionary:
	var created: Dictionary = _board_system.create_workflow(run_state, name)
	if created.is_empty():
		return {}
	_autosave()
	return created


func rename_workflow(index: int, name: String) -> bool:
	if not _board_system.rename_workflow(run_state, index, name):
		return false
	_autosave()
	return true


func delete_workflow(index: int) -> bool:
	if not _board_system.delete_workflow(run_state, index):
		return false
	_autosave()
	return true


## The pipeline a contract will actually be worked through, which is what the
## Burn Board shows rather than whatever the editor was last pointed at.
func workflow_for_job(job: Dictionary) -> Dictionary:
	return _board_system.workflow_for_job(run_state, job)


func assign_workflow(job_id: String, workflow_id: String) -> bool:
	if not _job_system.assign_workflow(run_state, job_id, workflow_id):
		return false
	_autosave()
	return true


## How every workflow the run owns scores against one contract's demands, in
## editor order, for the assignment picker.
func workflow_matches(job: Dictionary) -> Array:
	var matches: Array = []
	for workflow in _board_system.workflows(run_state):
		matches.append(_board_system.workflow_match(run_state, job, workflow))
	return matches


## What a contract is asking for, judged against the workflow it is assigned.
func job_demands(job: Dictionary) -> Array:
	return _board_system.demand_report(
		job, _board_system.slots_for_job(run_state, job), _board_system.blocked_slots(job)
	)


func get_operation_description(operation_id: String) -> String:
	var operation: OperationDefinition = ContentDatabase.get_operation(operation_id)
	if operation == null:
		return ""
	return ExpressionEvaluator.new().render_template(operation.description_template, operation.parameters)


## Seeded from the run and the exact prompt, so a preview and the burn it
## previewed roll the same numbers.
func _burn_rng() -> DeterministicRng:
	var stream_seed: int = hash("%d.%d.%d.%d" % [
		run_seed,
		int(run_state.calendar.get("round", 1)),
		int(run_state.calendar.get("prompt", 1)),
		_work_tick,
	])
	return DeterministicRng.new(absi(stream_seed) | 1)


## Folds any job that finished this prompt into the contract's quality average,
## exactly once each. Called both mid-session (so the ordinary evaluate/expire
## path always sees settled quality) and again from `_end_session` for jobs
## shipped or abandoned without going through `_finish_prompt` — the guard
## flag is what keeps a job from being counted by both.
func _record_completed_quality(run_state: RunState) -> void:
	for job in run_state.business.get("active_jobs", []):
		if not job is Dictionary:
			continue
		if float(job.get("tokens_remaining", 0.0)) > 0.0:
			continue
		if bool(job.get("_ascension_quality_recorded", false)):
			continue
		# Judged on what the client receives, not what the pipeline produced:
		# unfinished delivery and shipped known bugs both come off first.
		_ascension_system.record_job_quality(run_state, JobSystem.delivered_quality(job))
		job["_ascension_quality_recorded"] = true


## Bookkeeping shared by every action that consumes a prompt.
func _finish_prompt(result: Dictionary) -> void:
	for message in result.get("messages", []):
		round_log.append(str(message))
	run_state.update_peaks()
	_advance_prompt(result)
	work_tick_completed.emit()
	if _progression_system.check_loss(run_state):
		_work_running = false
		round_log.append(
			"%s — the run is over." % str(run_state.flags.get("loss_reason", "Run collapsed"))
		)
		_end_run(false)
		work_session_finished.emit({"phase": phase, "summary": last_session_summary})
		return
	if _ascension_system.is_active(run_state):
		# A job's quality has to be settled against the contract's average
		# before the contract is judged, not after: judging first and
		# recording second is how a losing final job can win on last round's
		# quality, and a winning one can be refused for it.
		_record_completed_quality(run_state)
		var ascension_result: Dictionary = _ascension_system.evaluate_prompt(run_state, ContentDatabase)
		for message in ascension_result.get("messages", []):
			round_log.append(str(message))
		var outcome: String = str(ascension_result.get("outcome", ""))
		if outcome == AscensionSystem.STATUS_COMPLETED:
			_work_running = false
			_reach_victory(_ascension_system.current_contract(run_state, ContentDatabase))
			work_session_finished.emit({"phase": phase, "summary": last_session_summary})
			return
		elif outcome == AscensionSystem.STATUS_FAILED:
			_work_running = false
			run_state.flags["loss_reason"] = "Ascension contract failed."
			_end_run(false, "ascension_failed")
			work_session_finished.emit({"phase": phase, "summary": last_session_summary})
			return
	var stop: String = _session_stop_reason(result)
	if stop != "":
		_end_session(stop)
		work_session_finished.emit({"phase": phase, "summary": last_session_summary})
	else:
		_autosave()


## Shipping or abandoning the last live contract ends the round there and then,
## without spending another prompt on it.
func _settle_if_resolved() -> void:
	for job in run_state.business.get("active_jobs", []):
		if not job is Dictionary:
			continue
		if float(job.get("tokens_remaining", 0.0)) > 0.0 and int(job.get("prompts_remaining", 0)) > 0:
			work_tick_completed.emit()
			_autosave()
			return
	_end_session("resolved")
	work_session_finished.emit({"phase": phase, "summary": last_session_summary})


## One burn or cool is one prompt. Prompts are not rationed — the round runs for
## as long as its contracts do — but every one of them ages the deadlines and
## meters the power.
func _advance_prompt(result: Dictionary) -> void:
	if not result.get("ok", true):
		return
	run_state.calendar["prompt"] = int(run_state.calendar["prompt"]) + 1


## A round ends when there is nothing left on the books, and only then. Rent can
## no longer interrupt a contract halfway through, because the bills wait for the
## work to finish rather than the other way round.
func _session_stop_reason(result: Dictionary) -> String:
	if not result.get("ok", true):
		return "collapsed"
	if result.get("all_resolved", false):
		return "resolved"
	return ""


func _execute_tick() -> Dictionary:
	var tick_rng: DeterministicRng = rng.derive("work_%d" % _work_tick)
	_work_tick += 1
	return _job_system.run_production_tick(
		run_state,
		tick_rng,
		effect_resolver,
		_collect_subscriptions(),
		tuning,
		_compute_system,
		_heat_system,
		_economy_system,
		_board_system
	)


## Settles the round. Every contract taken this round is resolved here — nothing
## carries into the next round, which is what makes "the round is over" mean the
## same thing every time and lets the bills follow the work rather than cut
## across it.
func _end_session(reason: String) -> void:
	var completed: Array = []
	var failed: Array = []
	for job in run_state.business.get("active_jobs", []):
		if float(job.get("tokens_remaining", 0.0)) <= 0.0:
			completed.append(job)
		else:
			failed.append(job)

	if _ascension_system.is_active(run_state):
		# Covers jobs settled by ship/abandon, which never pass through
		# `_finish_prompt`. Jobs already recorded there are skipped.
		_record_completed_quality(run_state)

	var messages: Array[String] = []
	var reward: float = 0.0
	if not completed.is_empty():
		var completed_payout: Dictionary = _job_system.finalize_completed_jobs(
			run_state, completed, effect_resolver, _collect_subscriptions(),
			tuning, _economy_system, messages, rng
		)
		reward += float(completed_payout.get("reward", 0.0))
	if not failed.is_empty():
		var failed_payout: Dictionary = _job_system.finalize_failed_jobs(
			run_state, failed, effect_resolver, _collect_subscriptions(),
			tuning, _economy_system, ContentDatabase, messages, rng
		)
		reward += float(failed_payout.get("reward", 0.0))
	for message in messages:
		round_log.append(str(message))
	if reward > 0.0:
		round_log.append("Paid %s for delivered work." % NumberFormat.format_cash(reward))
	elif not completed.is_empty() or not failed.is_empty():
		round_log.append("No payout — contracts missed deadline or quality bar.")

	_build_session_summary(completed, failed, reward, reason)

	for job in failed:
		EventBus.emit_event(EventBus.EVENT_JOB_FAILED, {"job_id": job.get("id", "")})
	run_state.statistics["completed_jobs"] = int(run_state.statistics.get("completed_jobs", 0)) + completed.size()
	# What the last delivered work was worth, so a perk paying "a percentage of
	# the job" has a figure to take a percentage of. A flat sum instead means the
	# same perk is a lifeline in the bedroom and invisible on the moon.
	if reward > 0.0:
		run_state.statistics["last_job_reward"] = reward
	run_state.statistics["failed_jobs"] = int(run_state.statistics.get("failed_jobs", 0)) + failed.size()
	_achievement_system.evaluate_tick(run_state, ContentDatabase)
	last_session_summary["reputation_delta"] = _settle_reputation(completed, failed)
	run_state.business["active_jobs"] = []
	run_state.business["active_job"] = {}
	run_state.business["focused_job_id"] = ""
	# New board next round, without rerolling on every prompt.
	run_state.business["job_board_seq"] = int(run_state.business.get("job_board_seq", 0)) + 1
	_work_running = false

	if _progression_system.check_loss(run_state):
		_end_run(false)
		return

	EventBus.emit_event(EventBus.EVENT_REWARD_CALCULATED, {"amount": reward})
	# Bills settle before the shop opens. Spending money that rent already has a
	# claim on is how a player gets evicted holding a new GPU.
	_round_end_pending = false
	_end_round()
	_autosave()


## What the round did to the run's standing, and the reason it did it. A missed
## deadline still costs a flat two per contract; delivered work is now paid in
## reputation by how good it was, so clearing a client's bar by a mile is worth
## more than scraping under it and taking the reduced fee.
func _settle_reputation(completed: Array, failed: Array) -> float:
	var before: float = float(run_state.business.get("reputation", 0.0))
	if not failed.is_empty():
		run_state.business["reputation"] = maxf(-10.0, before - 2.0 * float(failed.size()))
		# Rule-changer: a failed job is not a total loss — whatever went wrong
		# still teaches the rig something.
		if "unlock.rule_failed_research" in Array(run_state.build.get("meta_unlocks", [])):
			run_state.compute["efficiency_base"] = (
				float(run_state.compute.get("efficiency_base", 1.0)) + 0.01 * float(failed.size())
			)
		return float(run_state.business["reputation"]) - before
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
	run_state.business["reputation"] = before + gain
	if gain <= 0.0:
		round_log.append("Delivered under the client's quality bar. Word does not get around.")
	return gain


## Both surges last one batch, so a second press in the same prompt is refused
## rather than stacked.
func boost() -> bool:
	if phase != Phase.IN_ROUND or not _work_running or boost_engaged():
		return false
	_apply_boost()
	return true


func cloud_burst() -> bool:
	if phase != Phase.IN_ROUND or not _work_running or cloud_engaged():
		return false
	if not cloud_enabled():
		return false
	return _apply_cloud_burst()


## Cloud is a capability the run buys, not one it starts with. Without the
## account there is nobody to rent capacity from and nobody to bill.
func cloud_enabled() -> bool:
	return CLOUD_ACCOUNT_UPGRADE in run_state.build.get("upgrades", [])


func cloud_burst_multiplier() -> float:
	var level: int = int(run_state.build.get("upgrade_levels", {}).get(CLOUD_BURST_UPGRADE, 0))
	return CLOUD_BURST_BASE_MULTIPLIER + float(level) * CLOUD_BURST_PER_LEVEL


## Rented tokens are metered, and the provider charges for the privilege of
## turning the tap on at all. The flat fee is what makes an early burst a real
## decision instead of loose change.
func cloud_burst_cost() -> float:
	var economy: Dictionary = ContentDatabase.balance.get("economy", {})
	var burst: float = float(run_state.compute["local_capacity"]) * cloud_burst_multiplier()
	var rate: float = float(economy.get("cloud_burst_cost_per_token", 0.00008))
	var fee: float = float(economy.get("cloud_burst_activation_fee", 0.0))
	return burst * rate + fee


func can_afford_cloud_burst() -> bool:
	return _economy_system.can_afford(run_state, cloud_burst_cost())


## Whether this prompt's batch is already running hot off a boost.
func boost_engaged() -> bool:
	for entry in run_state.compute.get("rate_modifiers", []):
		if entry is Dictionary and str(entry.get("source", "")) == "boost":
			return true
	return false


func cloud_engaged() -> bool:
	return int(run_state.compute.get("cloud_burst_prompts", 0)) > 0


func _apply_boost() -> void:
	if boost_engaged():
		return
	run_state.add_rate_modifier(1.35, 1, "boost")
	_heat_system.add_heat(run_state, 12.0)
	round_log.append("BOOST engaged: +35% token rate, +12 heat.")


## Rents capacity for one prompt. Cash is deducted immediately so the player
## sees the cost land on the balance sheet, not as a hidden end-of-round liability.
func _apply_cloud_burst() -> bool:
	if cloud_engaged() or not cloud_enabled():
		return false
	var burst: float = float(run_state.compute["local_capacity"]) * cloud_burst_multiplier()
	var price: float = cloud_burst_cost()
	if not _economy_system.purchase(run_state, price, "cloud_burst"):
		round_log.append(
			"CLOUD BURST: not enough cash (%s needed)." % NumberFormat.format_cash(price)
		)
		return false
	run_state.compute["cloud_burst"] = burst
	run_state.compute["cloud_burst_prompts"] = 1
	round_log.append(
		"CLOUD BURST: rented %s for %s." % [
			NumberFormat.format_token_rate(burst),
			NumberFormat.format_cash(price),
		]
	)
	return true


## Snapshot of the round just finished, for the debrief screen. Every contract
## the round took is in one of the two lists, so the headline can never claim a
## success the player did not have.
func _build_session_summary(
	completed_jobs: Array, failed_jobs: Array, reward: float, reason: String
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
	var cash_after: float = float(run_state.economy.get("cash", 0.0))
	last_session_summary = {
		# Delivering something is the bar for a good round. A round that
		# delivered nothing is not a success, whatever else happened in it.
		"success": completed > 0 and failed == 0,
		"completed": completed,
		"failed": failed,
		"reward": reward,
		"spent": maxf(0.0, _session_cash_start + reward - cash_after),
		"cash_after": cash_after,
		"tokens_processed": tokens_done,
		"avg_quality": quality_total / maxf(1.0, float(jobs.size())),
		"avg_quality_threshold": threshold_total / maxf(1.0, float(jobs.size())),
		"quality_multiplier": multiplier_total / float(paid_jobs) if paid_jobs > 0 else 1.0,
		"reputation_delta": 0.0,
		"bugs": bugs,
		"hidden_bugs": hidden_bugs,
		"discovered_bugs": discovered_bugs,
		"ticks": _work_tick,
		"tokens_per_tick": tokens_done / maxf(1.0, float(_work_tick)),
		"round": int(run_state.calendar.get("round", 1)),
		"prompts_used": prompts_used_this_round(),
		"job_slots": job_slots(),
		"early_jobs": early_jobs,
		"early_bonus_pct": early_bonus_total / float(early_jobs) if early_jobs > 0 else 0.0,
		"stop_reason": reason,
		"behind_on_contract": _behind_on_contract(),
	}


## Whether the contract is further behind than the year has left to give it. A
## run three quarters through the calendar with a quarter of the burn done is
## losing, however well the individual round went, and the debrief says so.
func _behind_on_contract() -> bool:
	var progress: Dictionary = ascension_progress()
	if progress.is_empty():
		return false
	var deadline: int = maxi(1, int(progress.get("deadline_round", ROUNDS_PER_RUN)))
	var elapsed: float = clampf(
		float(int(run_state.calendar.get("round", 1))) / float(deadline), 0.0, 1.0
	)
	return elapsed >= 0.5 and float(progress.get("burn_ratio", 0.0)) < elapsed * 0.75


## Takes one of the angel's offers. Everything on the table is free, so the only
## question is which one, and the draft closes either way.
func accept_offer(offer_type: String, offer_id: String) -> bool:
	match offer_type:
		"perk":
			return _accept_perk(offer_id)
		"operation":
			return _accept_operation(offer_id)
		_:
			return false


## Walks away with nothing. Always allowed: a full board and a bad offer is a
## real situation.
func decline_offers() -> void:
	if phase != Phase.ANGEL_ROUND:
		return
	run_state.statistics["angel_offers_declined"] = int(
		run_state.statistics.get("angel_offers_declined", 0)
	) + 1
	_after_angel_round()


## Spends the draft's one pick and closes it.
func _spend_draft_pick(_offer_type: String, _offer_id: String) -> void:
	_after_angel_round()


func _accept_perk(perk_id: String) -> bool:
	if phase != Phase.ANGEL_ROUND:
		return false
	if not _perk_system.acquire(run_state, perk_id, ContentDatabase):
		return false
	run_state.statistics["angel_offers_taken"] = int(
		run_state.statistics.get("angel_offers_taken", 0)
	) + 1
	_invalidate_subscriptions()
	EventBus.emit_event(EventBus.EVENT_PERK_ACQUIRED, {"perk_id": perk_id})
	_dispatch_perk_acquired(perk_id)
	# A perk may have widened the board, so the slot array is resized before
	# anything tries to place a module in the slot it just gained.
	_board_system.ensure_board(run_state, ContentDatabase)
	_compute_system.recalculate(run_state, effect_resolver, _collect_subscriptions(), rng)
	_spend_draft_pick("perk", perk_id)
	return true


## Drafts a pipeline module. Unlike a perk it changes nothing on its own: it has
## to be placed on the board to do anything, and on a full board that means
## taking something else out.
func _accept_operation(operation_id: String) -> bool:
	if phase != Phase.ANGEL_ROUND:
		return false
	if not _board_system.grant_operation(run_state, operation_id):
		return false
	run_state.statistics["angel_offers_taken"] = int(
		run_state.statistics.get("angel_offers_taken", 0)
	) + 1
	run_state.statistics["modules_drafted"] = int(
		run_state.statistics.get("modules_drafted", 0)
	) + 1
	EventBus.emit_event(EventBus.EVENT_OPERATION_ACQUIRED, {"operation_id": operation_id})
	_achievement_system.evaluate_tick(run_state, ContentDatabase)
	_spend_draft_pick("operation", operation_id)
	return true


func _dispatch_perk_acquired(perk_id: String) -> void:
	var perk := ContentDatabase.get_perk(perk_id)
	if perk == null:
		return
	var subs: Array = []
	for sub in perk.subscriptions:
		if str(sub.get("event", "")) != "perk.acquired":
			continue
		var copy: Dictionary = sub.duplicate(true)
		copy["source_id"] = perk.id
		copy["parameters"] = perk.parameters.duplicate(true)
		subs.append(copy)
	if subs.is_empty():
		return
	effect_resolver.begin_action("perk.acquired.%s" % perk_id)
	var mod_ctx := ModifierContext.new("perk.acquired", run_state)
	mod_ctx.rng = rng.derive("perk.acquired")
	effect_resolver.dispatch("perk.acquired", mod_ctx, subs)


## Market operations (buying, selling, and the "is the counter open" gate
## they share) are pulled out into `MarketService`; these stay as the public
## facade every screen already calls.

func can_buy_upgrade(upgrade_id: String) -> bool:
	return MarketService.can_buy_upgrade(self, upgrade_id)


func buy_upgrade(upgrade_id: String) -> bool:
	return MarketService.buy_upgrade(self, upgrade_id)


func market_open() -> bool:
	return MarketService.market_open(self)


func hardware_sale_reason(hardware_key: String) -> String:
	return MarketService.hardware_sale_reason(self, hardware_key)


func hardware_sale_refund(hardware_key: String) -> float:
	return MarketService.hardware_sale_refund(self, hardware_key)


func can_sell_hardware(hardware_key: String) -> bool:
	return MarketService.can_sell_hardware(self, hardware_key)


func sell_hardware(hardware_key: String) -> bool:
	return MarketService.sell_hardware(self, hardware_key)


func set_tuning(key: String, value: float) -> void:
	if tuning.has(key):
		tuning[key] = value


func set_advertising(amount: float) -> void:
	run_state.business["advertising"] = maxf(0.0, amount)
	_demand_system.refresh_demand(run_state)
	_autosave()




func get_perk_description(perk_id: String) -> String:
	var perk := ContentDatabase.get_perk(perk_id)
	if perk == null:
		return ""
	return _render_perk(perk)


## How many perks the build holds against its ceiling, for screens that need to
## warn the player that picks are running out.
func perk_capacity() -> Dictionary:
	return {
		"owned": run_state.build["perks"].size(),
		"cap": _perk_system.perk_cap(ContentDatabase),
	}


func get_synergies() -> Array[String]:
	return _perk_system.detect_synergies(run_state, ContentDatabase)


func query_effect_breakdown(target_path: String, chain_id: String = "") -> Dictionary:
	return effect_resolver.query_trace_breakdown(target_path, chain_id)


## The only draft there is: the round's free offer, one pick and out.
const DRAFT_ANGEL := "angel"

## The round's angel draft. Everything here is free: somebody with more money
## than sense is handing out modules and perks. Anything with a price tag is sold
## on the Market tab instead, where the player goes looking for it.
func _present_angel_offers() -> void:
	pending_choices = []
	for operation in ContentDatabase.draw_operations(rng.derive("operation_choice"), 2, owned_operations()):
		pending_choices.append({
			"type": "operation",
			"id": operation.id,
			"label": operation.name,
			"description": get_operation_description(operation.id),
			"cost": 0.0,
		})
	var perk_draw: Array = ContentDatabase.draw_perks(
		rng.derive("angel_perks"),
		2,
		run_state.build["perks"],
		0.0,
		_perk_system.owned_tags(run_state, ContentDatabase),
		_perk_system.blocked_ids(run_state, ContentDatabase)
	)
	for perk in perk_draw:
		pending_choices.append({"type": "perk", "id": perk.id, "label": perk.name, "description": _render_perk(perk), "cost": 0.0})
	if pending_choices.is_empty():
		_after_angel_round()
		return
	# No persona is attached to the offers any more: there is one investor in the
	# game and the table is his, so the screen speaks for him rather than casting
	# a different fictional fund onto every card.
	run_state.flags["draft_kind"] = DRAFT_ANGEL
	phase = Phase.ANGEL_ROUND


## Which draft is on the table, so a screen can title itself.
func draft_kind() -> String:
	if phase != Phase.ANGEL_ROUND:
		return ""
	return str(run_state.flags.get("draft_kind", DRAFT_ANGEL))


## Picks still to spend on the draft. An angel draft is always worth exactly one.
func draft_picks_remaining() -> int:
	return 1 if phase == Phase.ANGEL_ROUND else 0


## Closes the round: the bills land, the rig cools off, and — if the rent
## cleared — the angels call. Reached only once every contract has resolved, so
## the player is never billed in the middle of a job.
func _end_round() -> void:
	phase = Phase.ROUND_END
	var statement: Dictionary = _economy_system.apply_round_bills(run_state, tuning)
	_expire_status_effects()
	var event := _event_system.maybe_trigger(run_state, rng.derive("events"), ContentDatabase, effect_resolver, tuning)
	if event != null:
		statement["event"] = event.name
		round_log.append("Event: %s" % event.name)
		# An event may have spawned a status effect, which only reaches the
		# dispatcher once the cached subscription list is rebuilt.
		_invalidate_subscriptions()
	# The shed runs after the event so a spike the event just caused is cooled
	# by the same downtime as the heat the round itself made. Shedding first
	# left a fresh +25 sitting on the rig with nothing to take it back off.
	_heat_system.shed_between_rounds(run_state)
	last_round_statement = statement
	# Deferred so the statement screen opens on a settled state: the round
	# rollover below happens first.
	round_statement_ready.emit.call_deferred(statement)
	_compute_system.recalculate(run_state, effect_resolver, _collect_subscriptions(), rng)
	if _progression_system.check_loss(run_state):
		_end_run(false)
		return
	if int(run_state.calendar["round"]) >= _contract_deadline_round():
		if in_post_victory() or MetaProgress.endless_enabled():
			# Endless keeps going instead of stopping: the bills get harder every
			# round past the twelfth, so staying alive is the challenge rather
			# than survival being a foregone conclusion.
			_escalate_endless_costs()
		else:
			# The terms were stated before the first prompt: the contract is done
			# inside the year or it is not done at all. Completing it ends the run
			# the moment it happens, mid-round, well before this check is reached.
			_ascension_system.fail_on_deadline(run_state)
			run_state.flags["loss_reason"] = "The year ran out with the contract unfinished."
			round_log.append(
				"The year is up and the contract is not complete. The investor is done with you."
			)
			_end_run(false, "contract_expired")
			return
	run_state.calendar["round"] = int(run_state.calendar["round"]) + 1
	_achievement_system.evaluate_tick(run_state, ContentDatabase)
	_begin_round()
	# Angels only call on a tenant in good standing. Clearing the round's bills
	# is the price of admission; miss the rent and nobody with money wants to be
	# seen anywhere near the operation. `_begin_round` has already opened round
	# prep, which is where a defaulting run stays.
	if bool(statement.get("paid_in_full", false)):
		_present_angel_offers()


## Ages the run's status effects by one round and drops the ones that have run
## out. A status that declares no `rounds` is permanent by design — that is what
## a perk's standing bonus is — so only the ones with a stated duration expire.
## Without this, an event that hangs a per-prompt cost on the rig (a fan dying,
## an incident war room) charged it for the rest of the run.
func _expire_status_effects() -> void:
	var statuses: Array = Array(run_state.build.get("status_effects", []))
	var surviving: Array = []
	var expired: Array = []
	for status in statuses:
		if not status is Dictionary or not status.has("rounds"):
			surviving.append(status)
			continue
		var remaining: int = int(status.get("rounds", 0)) - 1
		if remaining <= 0:
			expired.append(str(status.get("name", status.get("id", "A status effect"))))
			continue
		var aged: Dictionary = status.duplicate(true)
		aged["rounds"] = remaining
		surviving.append(aged)
	run_state.build["status_effects"] = surviving
	if expired.is_empty():
		return
	_invalidate_subscriptions()
	for name in expired:
		round_log.append("%s has worn off." % name)


const ENDLESS_COST_ESCALATION := 1.08

## Each round past the twelfth, rent and power creep up 8%: the same rig that
## coasted through the final act starts to strain again, keeping an endless
## run a real challenge instead of a victory lap.
func _escalate_endless_costs() -> void:
	run_state.economy["round_rent"] = float(run_state.economy.get("round_rent", 400.0)) * ENDLESS_COST_ESCALATION
	run_state.economy["power_base_cost_per_prompt"] = float(
		run_state.economy.get("power_base_cost_per_prompt", 10.0)
	) * ENDLESS_COST_ESCALATION
	run_state.statistics["endless_rounds"] = int(run_state.statistics.get("endless_rounds", 0)) + 1


## The last round the contract can be finished in. A won run carrying on into
## endless mode is past its deadline by definition, so the calendar length is
## used there instead.
func _contract_deadline_round() -> int:
	var contract: Dictionary = _ascension_system.current_contract(run_state, ContentDatabase)
	if contract.is_empty():
		contract = _ascension_system.location_contract(run_state, ContentDatabase)
	if contract.is_empty():
		return ROUNDS_PER_RUN
	return _ascension_system.deadline_round(contract)


## Rounds left before the contract's deadline, this round included.
func rounds_remaining() -> int:
	return maxi(0, _contract_deadline_round() - int(run_state.calendar.get("round", 1)) + 1)


func _after_angel_round() -> void:
	pending_choices.clear()
	run_state.flags["draft_kind"] = ""
	if _progression_system.check_loss(run_state):
		_end_run(false)
		return
	if _round_end_pending:
		_round_end_pending = false
		_end_round()
		return
	phase = Phase.ROUND_PREP
	_ensure_job_offers()


## `outcome` names how the run ended. "ascended" is the only way to win: an
## Ascension Contract completed. "retired" survives only for saves and profiles
## written before overtime existed — the calendar no longer ends a run, so
## nothing reaches it any more. Left blank it falls back to the old two-state
## behaviour ("ascended" on victory, "lost" otherwise), which is what the batch
## runner, screenshot tool, and older tests still call.
func _end_run(victory: bool, outcome: String = "") -> void:
	# Bills landing while an ascension is being settled cannot take the win back.
	# The endless tail the player is about to be offered may be short, but the
	# contract was completed and the run was won.
	if _settling_victory and not victory:
		return
	if outcome == "":
		outcome = "ascended" if victory else "lost"
	run_state.flags["victory"] = victory
	run_state.flags["outcome"] = outcome
	if not victory and run_state.flags.get("loss_reason", "") == "":
		run_state.flags["loss_reason"] = "Run collapsed."
	phase = Phase.RUN_END
	MetaProgress.record_best_score(RunScore.compute(run_state, ContentDatabase))
	match outcome:
		"ascended":
			var contract: Dictionary = _ascension_system.current_contract(run_state, ContentDatabase)
			run_state.flags["ascension_tier"] = int(contract.get("tier", 1))
			MetaProgress.record_ascension(str(contract.get("id", "")))
			_complete_run_location()
			# Same rule as `_reach_victory`: only finishing the campaign's last
			# chapter pays out anything permanent.
			if _run_is_final_chapter():
				MetaProgress.bank_victory(maxi(1, int(contract.get("picks", 1))))
				if bool(contract.get("unlocks_age", false)):
					MetaProgress.advance_age(Ages.max_age_index())
				var ending_unlock: String = str(contract.get("ending_unlock", ""))
				if ending_unlock != "":
					MetaProgress.grant_ending_unlock(ending_unlock)
		"retired":
			MetaProgress.record_retirement()
		_:
			pass
	_bank_run_legacy(victory)
	EventBus.emit_event(EventBus.EVENT_RUN_ENDED, {"victory": victory})
	_autosave()


## Lifetime counters and end-of-run awards, folded in once per run whatever
## finally closes it. A won run can carry on into endless and end again later, so
## banking on every ending would count the same run's legacy twice.
##
## Lifetime counters are folded in before the awards are judged, so an achievement
## that asks for ten losses can be earned by the tenth loss rather than the
## eleventh.
func _bank_run_legacy(victory: bool) -> void:
	if bool(run_state.flags.get("legacy_banked", false)):
		return
	run_state.flags["legacy_banked"] = true
	MetaProgress.add_lifetime_stats(AchievementSystem.lifetime_deltas(run_state, victory))
	_achievement_system.evaluate_run_end(
		run_state, RunScore.compute(run_state, ContentDatabase), ContentDatabase
	)


## The permanent unlocks on offer after beating the campaign. Picks are rare —
## one batch per completion — so the debrief lays out every area still open
## (rig, cooling, cloud, cash, workflows, board width) and the player chooses
## which to boost permanently, rather than being dealt three at random.
func debrief_choices() -> Array:
	if MetaProgress.pending_picks() <= 0:
		return []
	return MetaProgress.available_choices()


func spend_debrief_pick(unlock_id: String) -> bool:
	return MetaProgress.spend_pick(unlock_id)


func _invalidate_subscriptions() -> void:
	_subscriptions_dirty = true


func _collect_subscriptions() -> Array:
	if not _subscriptions_dirty:
		return _subscriptions_cache
	var subs: Array = []
	for perk_id in run_state.build["perks"]:
		var perk := ContentDatabase.get_perk(str(perk_id))
		if perk != null:
			for sub in perk.subscriptions:
				var copy: Dictionary = sub.duplicate(true)
				copy["source_id"] = perk.id
				copy["parameters"] = perk.parameters.duplicate(true)
				subs.append(copy)
	# A completed set pays out for itself. Without this a synergy was a caption
	# on the build screen telling the player something had happened when nothing
	# had.
	for synergy in _perk_system.active_synergies(run_state, ContentDatabase):
		for sub in synergy.get("subscriptions", []):
			if sub is Dictionary:
				var synergy_sub: Dictionary = sub.duplicate(true)
				synergy_sub["source_id"] = "synergy.%s" % str(synergy.get("name", "set"))
				synergy_sub["parameters"] = synergy.get("parameters", {})
				subs.append(synergy_sub)
	for status in run_state.build["status_effects"]:
		if status is Dictionary:
			for sub in status.get("subscriptions", []):
				if sub is Dictionary:
					var copy: Dictionary = sub.duplicate(true)
					if not copy.has("parameters"):
						copy["parameters"] = status.get("parameters", {})
					if not copy.has("source_id"):
						copy["source_id"] = str(status.get("source_perk", status.get("id", "status")))
					subs.append(copy)
	_subscriptions_cache = subs
	_subscriptions_dirty = false
	return subs


func _render_perk(perk: PerkDefinition) -> String:
	return ExpressionEvaluator.new().render_template(perk.description_template, perk.parameters)


const PHASE_NAMES := ["IDLE", "ROUND_PREP", "IN_ROUND", "ROUND_END", "ANGEL_ROUND", "RUN_END"]


func _phase_name(value: int) -> String:
	return PHASE_NAMES[value] if value >= 0 and value < PHASE_NAMES.size() else "IDLE"


func _autosave() -> void:
	if not autosave_enabled:
		return
	SaveManager.save_run(run_state, _phase_name(phase), run_seed, pending_choices, _round_end_pending)


func load_saved_run() -> bool:
	var data: Dictionary = SaveManager.load_run()
	if data.is_empty():
		return false
	run_seed = int(data.get("seed", 0))
	rng.set_seed(run_seed)
	run_state.from_dict(data.get("run_state", {}))
	var saved_choices = data.get("pending_choices", [])
	pending_choices = saved_choices if saved_choices is Array else []
	var phase_name: String = str(data.get("phase", "IDLE"))
	phase = _phase_from_name(phase_name)
	_work_running = false
	# Saves written before the redesign called the round a month.
	_round_end_pending = bool(data.get("round_end_pending", data.get("month_end_pending", false)))
	_invalidate_subscriptions()
	# A save from before the campaign existed can be mid-warehouse, having
	# climbed there with cash. That rung and everything under it is earned, so
	# the profile catches up rather than stranding the run somewhere it is no
	# longer allowed to be.
	MetaProgress.ensure_location_unlocked_through(str(run_state.build.get("dwelling", "")))
	# Cooling from permanent unlocks is a function of the profile, not of the
	# run, so it is read back rather than restored from the save.
	run_state.compute["meta_cooling"] = MetaProgress.cooling_bonus()
	if phase == Phase.IDLE:
		start_run(run_seed)
		return true
	repair_after_load()
	return true


func _phase_from_name(name: String) -> int:
	match name:
		"ROUND_PREP", "JOB_SELECT": return Phase.ROUND_PREP
		"IN_ROUND", "IN_JOB": return Phase.IN_ROUND
		"ROUND_END", "MONTH_END": return Phase.ROUND_END
		"ANGEL_ROUND": return Phase.ANGEL_ROUND
		# Saves written before the angel draft was split out of the market.
		"UPGRADE_CHOICE": return Phase.ANGEL_ROUND
		"RUN_END": return Phase.RUN_END
		_: return Phase.IDLE


func is_running() -> bool:
	return phase != Phase.IDLE and phase != Phase.RUN_END
