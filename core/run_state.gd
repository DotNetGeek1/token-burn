class_name RunState
extends RefCounted

## Authoritative simulation state. UI observes this; it does not contain economic logic.

const SAVE_VERSION := 17

## What a run on Normal starts the first chapter with, and the figure every
## location's stake and every difficulty profile is expressed relative to.
const DEFAULT_STARTING_CASH := 500.0

## A round is one full cycle of the game: take contracts, work them to
## resolution, pay the bills. A prompt is one action inside a round — a burn or
## a cool — and is the unit deadlines and running costs are measured in.
var calendar: Dictionary = {
	"round": 1,
	"prompt": 1,
	"deadline_progress": 0.0,
}

var economy: Dictionary = {
	"cash": DEFAULT_STARTING_CASH,
	"cash_multiplier": 1.0,
	"debt": 0.0,
	"recurring_costs": 0.0,
	"income": 0.0,
	"cloud_surcharge_liability": 0.0,
	"pending_bills": [],
	"rent_unpaid_streak": 0,
	"rent_multiplier": 1.0,
	"round_rent": 400.0,
	"power_base_cost_per_prompt": 10.0,
	"power_cost_per_prompt": 10.0,
	## What the run's cloud tier bills per prompt before anything discounts it.
	## Upgrades write here; perks discount the derived figure below.
	"cloud_base_cost_per_prompt": 0.0,
	## Re-derived from the base on every recalculation, so a perk that halves it
	## halves it once rather than once per recalculation for the rest of the run.
	"cloud_cost_per_prompt": 0.0,
	"costs_this_round": 0.0,
	"last_round_costs": 0.0,
}

var compute: Dictionary = {
	"local_capacity": 1_000_000.0,
	"cloud_capacity": 0.0,
	"cloud_burst": 0.0,
	"cloud_burst_prompts": 0,
	"token_rate": 1_000_000.0,
	## The two halves of `token_rate`, split so a perk can favour owned iron over
	## rented capacity or the other way round. Both derived every recalculation.
	"local_rate": 1_000_000.0,
	"cloud_rate": 0.0,
	"cloud_share": 0.0,
	"prompt_rate": 1_000_000.0,
	"power_draw": 65.0,
	## Derived by ComputeSystem from the run's location, what is installed in it
	## and `meta_cooling`. Never added to directly: see ComputeSystem.derive_cooling.
	"cooling": 0.0,
	## Cooling from permanent unlocks, which is the one part of the total that
	## nothing in the run can be read back from.
	"meta_cooling": 0.0,
	"heat": 0.0,
	"heat_capacity": 100.0,
	"efficiency": 1.0,
	"efficiency_base": 1.0,
	"rate_modifiers": [],
}

var business: Dictionary = {
	"reputation": 10.0,
	"demand": 3.0,
	## Re-seeded from the base at the top of every round, so a perk advertising
	## "+1 demand" is worth +1 in round twelve as well as in round one.
	"demand_modifier": 0.0,
	## Permanent changes to demand — events, upgrades — as opposed to the
	## per-round contributions perks make.
	"demand_modifier_base": 0.0,
	"advertising": 0.0,
	"active_jobs": [],
	"active_job": {},
	"job_offers": [],
	"job_queue": [],
	"focused_job_id": "",
	"job_board_stamp": "",
	"job_board_seq": 0,
}

var build: Dictionary = {
	"perks": [],
	"perk_inventory": [],
	"perk_liabilities": [],
	"draft_state": {"sequence": 0, "rerolls": 0},
	"hardware": ["used_laptop"],
	"upgrades": [],
	"status_effects": [],
	"modules": [],
	"board": {"slot_count": BoardSystem.DEFAULT_SLOT_COUNT, "active_workflow": 0},
	"workflows": [],
	"workflow_capacity": BoardSystem.DEFAULT_WORKFLOW_CAPACITY,
	"dwelling": "bedroom",
	"cloud_tier": "none",
	"advertising_tier": "none",
	"upgrade_levels": {},
	## The one ledger of "how many of upgrade X does this run own", repeatable
	## and one-off alike (a one-off sits in here at 1). `hardware`/`upgrades`/
	## `upgrade_levels` above are the older, split representation of the same
	## fact and are being folded into this one incrementally — see
	## `UpgradeSystem.upgrade_counts()` — rather than removed outright, since
	## UI and save data still address them directly.
	"upgrade_counts": {},
}

var statistics: Dictionary = {
	"lifetime_tokens": 0.0,
	"failed_jobs": 0,
	"completed_jobs": 0,
	"last_job_reward": 0.0,
	"absurdity_metrics": {},
	"peak_token_rate": 0.0,
	"peak_cash": 0.0,
	"peak_debt": 0.0,
	"peak_prompt_tokens": 0.0,
	"hidden_bugs_shipped": 0,
	"max_cloud_share": 0.0,
	"stage_repeats": 0,
	"max_heat_ratio": 0.0,
	"jobs_accepted": 0,
	"angel_offers_taken": 0,
	"angel_offers_declined": 0,
	"hardware_sold": 0,
	"modules_drafted": 0,
}

## The location's contract, which is live from the first prompt of the run; see
## AscensionSystem for what each field means. There is only ever one contract per
## run, so nothing here outlives it.
var ascension: Dictionary = {
	"status": "",
	"contract_id": "",
	"baseline_tokens": 0.0,
	"tokens_burned": 0.0,
	"deadline_round": 0,
	"quality_sum": 0.0,
	"quality_count": 0,
}

var flags: Dictionary = {
	"loss_reason": "",
	"victory": false,
	"outcome": "",
	"ascension_tier": 0,
	"fire_risk": false,
	"post_victory": false,
	"post_victory_phase": "",
	"legacy_banked": false,
	"location_completed": false,
	"next_location": "",
	"draft_kind": "",
	## Set once at `reset_run` from the profile's chosen difficulty, and read
	## back by job scaling rather than re-reading the profile mid-run — so a
	## difficulty change in the menu cannot reach into a run already going.
	"difficulty": "normal",
}


func reset(profile: Dictionary = {}) -> void:
	calendar = _default_calendar()
	economy = _default_economy(profile)
	compute = _default_compute()
	business = _default_business()
	build = _default_build()
	statistics = _default_statistics()
	ascension = _default_ascension()
	flags = _default_flags()


func add_rate_modifier(multiplier: float, duration_prompts: int = 1, source: String = "") -> void:
	var modifiers: Array = []
	for entry in compute.get("rate_modifiers", []):
		if not entry is Dictionary:
			continue
		# Heat throttle and boost are refreshed each prompt; stacking the same
		# source would multiply throughput down every end_prompt tick miss.
		if source != "" and str(entry.get("source", "")) == source:
			continue
		modifiers.append(entry)
	modifiers.append({
		"multiplier": multiplier,
		"prompts_remaining": duration_prompts,
		"source": source,
	})
	compute["rate_modifiers"] = modifiers


## Ages temporary rate modifiers by one prompt. Must be called when a prompt
## *ends*: a one-prompt modifier added mid-prompt has to survive long enough to
## multiply that prompt's batch, which is exactly what BOOST depends on. Heat
## throttling is added after this runs, by which point the prompt's batch is
## already resolved — so a throttle only ever slows the prompt that follows.
func tick_rate_modifiers() -> void:
	var modifiers: Array = compute.get("rate_modifiers", [])
	var remaining: Array = []
	for entry in modifiers:
		if not entry is Dictionary:
			continue
		var prompts_left: int = int(entry.get("prompts_remaining", 0)) - 1
		if prompts_left > 0:
			var copy: Dictionary = entry.duplicate(true)
			copy["prompts_remaining"] = prompts_left
			remaining.append(copy)
	compute["rate_modifiers"] = remaining


## Rented cloud capacity is returned when its lease runs out. Kept separate from
## `cloud_capacity`, which upgrades own permanently.
func tick_cloud_burst() -> void:
	var prompts_left: int = int(compute.get("cloud_burst_prompts", 0)) - 1
	if prompts_left > 0:
		compute["cloud_burst_prompts"] = prompts_left
		return
	compute["cloud_burst_prompts"] = 0
	compute["cloud_burst"] = 0.0


func get_value_at_path(path: String) -> Variant:
	var parts := path.split(".")
	if parts.is_empty():
		return null
	var current: Variant = _get_section(parts[0])
	if current == null:
		return null
	for i in range(1, parts.size()):
		var part: String = parts[i]
		if current is Dictionary and current.has(part):
			current = current[part]
		else:
			return null
	return current


func set_value_at_path(path: String, value: Variant) -> void:
	var parts := path.split(".")
	if parts.size() < 2:
		return
	var current: Variant = _get_section(parts[0])
	if not current is Dictionary:
		return
	var section: Dictionary = current
	for i in range(1, parts.size() - 1):
		var part: String = parts[i]
		if not section.has(part) or not section[part] is Dictionary:
			section[part] = {}
		section = section[part]
	section[parts[-1]] = value


func has_active_job() -> bool:
	return business.get("active_jobs", []).size() > 0 or business.get("active_job", {}).size() > 0


func has_queued_jobs() -> bool:
	return business.get("job_queue", []).size() > 0


func has_pending_work() -> bool:
	return has_queued_jobs() or has_active_job()


func update_peaks() -> void:
	statistics["peak_token_rate"] = maxf(float(statistics.get("peak_token_rate", 0.0)), float(compute.get("token_rate", 0.0)))
	statistics["peak_cash"] = maxf(float(statistics.get("peak_cash", 0.0)), float(economy.get("cash", 0.0)))
	statistics["peak_debt"] = maxf(float(statistics.get("peak_debt", 0.0)), float(economy.get("debt", 0.0)))
	var heat_capacity: float = maxf(1.0, float(compute.get("heat_capacity", 100.0)))
	statistics["max_heat_ratio"] = maxf(
		float(statistics.get("max_heat_ratio", 0.0)),
		float(compute.get("heat", 0.0)) / heat_capacity
	)


## A typed snapshot of `economy`, for code that wants real property names and
## static types instead of `.get("cash", 0.0)`. It is a snapshot, not a live
## view: write changes back with `apply_economy_state`, the same way a UI
## screen edits a form and then submits it, rather than expecting field
## assignment to reach back into the dictionary on its own.
func economy_state() -> EconomyState:
	return EconomyState.from_dict(economy)


func apply_economy_state(state: EconomyState) -> void:
	economy = state.to_dict()


## A typed snapshot of `compute`. See `economy_state()`.
func compute_state() -> ComputeState:
	return ComputeState.from_dict(compute)


func apply_compute_state(state: ComputeState) -> void:
	compute = state.to_dict()


func to_dict() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"calendar": calendar.duplicate(true),
		"economy": economy.duplicate(true),
		"compute": compute.duplicate(true),
		"business": business.duplicate(true),
		"build": build.duplicate(true),
		"statistics": statistics.duplicate(true),
		"ascension": ascension.duplicate(true),
		"flags": flags.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	var version: int = int(data.get("save_version", 1))
	calendar = _merge_section(_default_calendar(), data.get("calendar", {}))
	economy = _merge_section(_default_economy({}), data.get("economy", {}))
	compute = _merge_section(_default_compute(), data.get("compute", {}))
	business = _merge_section(_default_business(), data.get("business", {}))
	build = _merge_section(_default_build(), data.get("build", {}))
	statistics = _merge_section(_default_statistics(), data.get("statistics", {}))
	ascension = _merge_section(_default_ascension(), data.get("ascension", {}))
	flags = _merge_section(_default_flags(), data.get("flags", {}))
	_migrate(version)


func _merge_section(defaults: Dictionary, saved: Variant) -> Dictionary:
	var merged: Dictionary = defaults.duplicate(true)
	if saved is Dictionary:
		for key in saved.keys():
			merged[key] = saved[key]
	return merged


func _migrate(from_version: int) -> void:
	if from_version < 2:
		if not compute.has("rate_modifiers"):
			compute["rate_modifiers"] = []
		if not business.has("demand_modifier"):
			business["demand_modifier"] = 0.0
	if from_version < 3:
		# Rounds used to advance once per work session; they now advance once per
		# production tick, so an old round index means nothing in the new budget.
		economy["power_base_cost_per_prompt"] = float(economy.get("power_cost_per_prompt", 10.0))
		economy["costs_this_round"] = 0.0
	if from_version < 4:
		# Efficiency used to be one field that recalculation both read and wrote,
		# so old saves carry a compounded value. Only permanent changes belong in
		# the base, and a runaway value cannot be told apart from a legitimate
		# one, so anything absurd resets.
		var stored: float = float(compute.get("efficiency", 1.0))
		compute["efficiency_base"] = stored if stored <= 4.0 else 1.0
		compute["efficiency"] = float(compute["efficiency_base"])
		compute["prompt_rate"] = float(compute.get("token_rate", 1_000_000.0))
	if from_version < 5:
		# Work used to resolve itself; it is now a pipeline the player builds.
		# BoardSystem.ensure_board grants the starter modules and lays them out,
		# so an old save just needs the empty structures to exist.
		build["modules"] = []
		build["board"] = {"slots": [], "slot_count": BoardSystem.DEFAULT_SLOT_COUNT}
		for job in business.get("active_jobs", []):
			if job is Dictionary:
				job["known_bugs"] = int(job.get("bugs_this_job", 0))
				job["hidden_bugs"] = 0
	if from_version < 6:
		# Ascension Contracts and their score stats are additive: older saves
		# simply start with no contract underway and a zeroed scoreboard.
		ascension = _default_ascension()
		if not statistics.has("hidden_bugs_shipped"):
			statistics["hidden_bugs_shipped"] = 0
	if from_version < 7:
		_migrate_to_round_and_prompt()
	if from_version < 8:
		_migrate_to_workflows()
	if from_version < 10:
		# Cooling used to be a running total that moving premises added to, so an
		# old save can be carrying several locations' worth of it at once. The
		# stored figure is discarded and rebuilt from what the run actually has
		# the first time ComputeSystem recalculates, which happens on load.
		compute["cooling"] = 0.0
		compute["meta_cooling"] = 0.0
	if from_version < 11:
		_migrate_off_the_ascension_ladder()
	if from_version < 12:
		_migrate_to_the_contract_as_the_level()
	if from_version < 13:
		_migrate_cloud_liability_rename()
	if from_version < 14:
		_migrate_upgrade_counts()
	if from_version < 15:
		_migrate_to_derived_cloud_cost_and_demand()
	if from_version < 16:
		_migrate_to_perk_inventory()
	if from_version < 17:
		_migrate_operations_to_modules()


## The pipeline pieces were called operations in code and modules everywhere the
## player could see. The state key follows the player's word; a save written
## under the old name keeps its modules.
func _migrate_operations_to_modules() -> void:
	if not build.has("operations"):
		return
	if Array(build.get("modules", [])).is_empty():
		build["modules"] = Array(build["operations"])
	build.erase("operations")


## Active perks and collected perks split apart: everything the run has ever
## picked up lives in inventory; only the equipped subset is active.
func _migrate_to_perk_inventory() -> void:
	var active: Array = Array(build.get("perks", []))
	var inventory: Array = Array(build.get("perk_inventory", []))
	if inventory.is_empty():
		inventory = active.duplicate()
	for perk_id in active:
		if not (str(perk_id) in inventory):
			inventory.append(perk_id)
	build["perk_inventory"] = inventory


## Cloud cost and demand were both stats that read and wrote themselves: a perk
## discounting cloud spend discounted its own last answer on every
## recalculation, and a perk worth "+1 demand" added another +1 every round. Both
## now derive from a base, so an old save carries a compounded figure that cannot
## be told apart from a legitimate one. The base is rebuilt from what the run
## demonstrably bought, and the derived value is left for the next recalculation.
func _migrate_to_derived_cloud_cost_and_demand() -> void:
	economy["cloud_base_cost_per_prompt"] = _cloud_cost_of_owned_tiers()
	economy["cloud_cost_per_prompt"] = float(economy["cloud_base_cost_per_prompt"])
	business["demand_modifier_base"] = 0.0
	business["demand_modifier"] = 0.0


## What the cloud shelf the run has actually bought bills per prompt, summed
## back out of the upgrades rather than trusted from the saved figure.
func _cloud_cost_of_owned_tiers() -> float:
	var total: float = 0.0
	for upgrade_id in Array(build.get("upgrades", [])):
		var upgrade: UpgradeDefinition = ContentDatabase.get_upgrade(str(upgrade_id))
		if upgrade == null:
			continue
		for effect in upgrade.effects:
			if effect is EffectDefinition and effect.target == "economy.cloud_base_cost_per_prompt":
				total += float(effect.value)
	return total


## The liability was always the surcharge on metered cloud spend, not cloud
## spend itself — the rename says so, and lands alongside the fix that had
## been applying its multiplier twice.
func _migrate_cloud_liability_rename() -> void:
	if economy.has("cloud_liability"):
		economy["cloud_surcharge_liability"] = float(economy.get("cloud_liability", 0.0))
		economy.erase("cloud_liability")
	if not flags.has("difficulty"):
		flags["difficulty"] = "normal"


## `upgrade_counts` is a new, unified ledger folding together the older split
## representation (`hardware` + `upgrades` + `upgrade_levels`); a save from
## before it existed has all the facts, just spread across those three
## fields, so it is rebuilt from them rather than starting empty.
func _migrate_upgrade_counts() -> void:
	if not build.has("upgrade_counts") or not (build["upgrade_counts"] is Dictionary):
		build["upgrade_counts"] = {}
	if not Dictionary(build["upgrade_counts"]).is_empty():
		return
	var counts: Dictionary = {}
	for upgrade_id in Array(build.get("upgrades", [])):
		counts[str(upgrade_id)] = int(counts.get(str(upgrade_id), 0)) + 1
	for upgrade_id in Dictionary(build.get("upgrade_levels", {})).keys():
		counts[str(upgrade_id)] = int(build["upgrade_levels"][upgrade_id])
	build["upgrade_counts"] = counts


## The three-rung ladder became one boss contract per location. A save taken
## part-way up it keeps whichever contract was committed — that is now the run's
## boss, and clearing it wins — while the rungs already climbed and any reward
## picks not yet spent are dropped. Neither has anywhere to go in the new model,
## and carrying them would leave a run owed a draft nothing can ever open.
func _migrate_off_the_ascension_ladder() -> void:
	for stale in ["completed_ids", "highest_tier_completed", "pending_picks"]:
		ascension.erase(stale)


## The contract stopped being something taken on part-way through a run and
## became the run's win condition, stated up front and measured from round one.
## A save that had committed keeps its contract and its progress; one that never
## did is put under its location's contract from wherever it currently stands,
## since there is no longer any other way for the run to end well. The
## prompt-by-prompt policing the Final Burn used — throughput floors, heat
## ceilings, violation counts — has no equivalent and is dropped, as is overtime.
func _migrate_to_the_contract_as_the_level() -> void:
	for stale in ["committed_round", "prompts_remaining", "violations"]:
		ascension.erase(stale)
	economy.erase("overtime_levy")
	economy.erase("overtime_income_mark")
	statistics.erase("overtime_rounds")
	flags.erase("overtime")
	flags.erase("ascension_qualified")
	if str(ascension.get("status", "")) == "committed":
		ascension["status"] = "active"
	if not ascension.has("deadline_round") or int(ascension.get("deadline_round", 0)) <= 0:
		ascension["deadline_round"] = 12


## One global pipeline became a list of named workflows, each assignable to a
## contract. The layout the save was built around becomes the first workflow and
## a second saved lane, if the run had earned one, becomes the second — so a run
## in progress opens on exactly the pipeline it was left on. BoardSystem does
## the structural half; this only has to make sure nothing points at the old
## shape and that the capacity matches what the run already had.
func _migrate_to_workflows() -> void:
	build["workflow_capacity"] = maxi(
		int(build.get("workflow_capacity", BoardSystem.DEFAULT_WORKFLOW_CAPACITY)),
		maxi(1, int(build.get("lane_count", 1)))
	)
	if not build.get("workflows", null) is Array:
		build["workflows"] = []


## The month/round split became round/prompt: a round is the whole cycle that
## ends in rent, and a prompt is one burn or cool inside it. Old saves carry the
## previous vocabulary in both their keys and their live contracts, so every one
## of them is translated rather than reset — a run in progress keeps its
## progress, its deadlines and its money.
func _migrate_to_round_and_prompt() -> void:
	var old_prompt: int = maxi(1, int(calendar.get("round", 1)))
	calendar["round"] = maxi(1, int(calendar.get("month", 1)))
	calendar["prompt"] = old_prompt
	for stale in ["month", "day", "rounds_per_month"]:
		calendar.erase(stale)

	economy["round_rent"] = float(economy.get("monthly_rent", economy.get("round_rent", 400.0)))
	economy["power_base_cost_per_prompt"] = float(
		economy.get("power_base_cost_per_round", economy.get("power_base_cost_per_prompt", 10.0))
	)
	economy["power_cost_per_prompt"] = float(
		economy.get("power_cost_per_round", economy.get("power_cost_per_prompt", 10.0))
	)
	economy["cloud_cost_per_prompt"] = float(
		economy.get("cloud_cost_per_round", economy.get("cloud_cost_per_prompt", 0.0))
	)
	economy["costs_this_round"] = float(economy.get("costs_this_month", 0.0))
	economy["last_round_costs"] = float(economy.get("last_month_costs", 0.0))
	for stale in [
		"monthly_rent", "power_base_cost_per_round", "power_cost_per_round",
		"cloud_cost_per_round", "costs_this_month", "last_month_costs",
		"passive_income_per_month",
	]:
		economy.erase(stale)

	compute["prompt_rate"] = float(compute.get("round_rate", compute.get("token_rate", 1_000_000.0)))
	compute["cloud_burst_prompts"] = int(compute.get("cloud_burst_rounds", 0))
	compute.erase("round_rate")
	compute.erase("cloud_burst_rounds")
	var modifiers: Array = []
	for entry in compute.get("rate_modifiers", []):
		if not entry is Dictionary:
			continue
		var copy: Dictionary = entry.duplicate(true)
		copy["prompts_remaining"] = int(copy.get("rounds_remaining", copy.get("prompts_remaining", 1)))
		copy.erase("rounds_remaining")
		modifiers.append(copy)
	compute["rate_modifiers"] = modifiers

	statistics["peak_prompt_tokens"] = float(statistics.get("peak_round_tokens", 0.0))
	statistics.erase("peak_round_tokens")
	statistics["endless_rounds"] = int(statistics.get("endless_months", 0))
	statistics.erase("endless_months")

	ascension.erase("committed_month")
	ascension.erase("rounds_remaining")

	for collection in ["active_jobs", "job_queue", "job_offers"]:
		for job in business.get(collection, []):
			if job is Dictionary:
				_migrate_job_deadline(job)


func _migrate_job_deadline(job: Dictionary) -> void:
	if job.has("deadline_rounds"):
		job["deadline_prompts"] = int(job["deadline_rounds"])
		job.erase("deadline_rounds")
	if job.has("rounds_remaining"):
		job["prompts_remaining"] = int(job["rounds_remaining"])
		job.erase("rounds_remaining")


func _default_calendar() -> Dictionary:
	return {
		"round": 1,
		"prompt": 1,
		"deadline_progress": 0.0,
	}


func _default_economy(profile: Dictionary = {}) -> Dictionary:
	var economy_balance: Dictionary = ContentDatabase.balance.get("economy", {})
	var base_power: float = float(profile.get("power_cost_per_prompt", 10.0))
	var starting_cash: float = float(profile.get("starting_cash", DEFAULT_STARTING_CASH))
	return {
		"cash": starting_cash,
		# Every location has a stake sized for its own rent; the difficulty is a
		# multiplier on all of them rather than a figure that only bites in the
		# bedroom, so a hard run is short of money in the warehouse too.
		"cash_multiplier": starting_cash / DEFAULT_STARTING_CASH,
		"debt": 0.0,
		"recurring_costs": 0.0,
		"income": 0.0,
		"cloud_surcharge_liability": 0.0,
		"pending_bills": [],
		"rent_unpaid_streak": 0,
		"rent_multiplier": float(profile.get("rent_multiplier", 1.0)),
		"round_rent": float(economy_balance.get("starting_rent", 400.0)) * float(profile.get("rent_multiplier", 1.0)),
		"power_base_cost_per_prompt": base_power,
		"power_cost_per_prompt": base_power,
		"cloud_base_cost_per_prompt": 0.0,
		"cloud_cost_per_prompt": 0.0,
		"costs_this_round": 0.0,
		"last_round_costs": 0.0,
	}


func _default_compute() -> Dictionary:
	return {
		"local_capacity": 1_000_000.0,
		"cloud_capacity": 0.0,
		"cloud_burst": 0.0,
		"cloud_burst_prompts": 0,
		"token_rate": 1_000_000.0,
		"local_rate": 1_000_000.0,
		"cloud_rate": 0.0,
		"cloud_share": 0.0,
		"prompt_rate": 1_000_000.0,
		"power_draw": 65.0,
		"cooling": 0.0,
		"meta_cooling": 0.0,
		"heat": 0.0,
		"heat_capacity": 100.0,
		"efficiency": 1.0,
		"efficiency_base": 1.0,
		"rate_modifiers": [],
	}


func _default_business() -> Dictionary:
	return {
		"reputation": 10.0,
		"demand": 3.0,
		"demand_modifier": 0.0,
		"demand_modifier_base": 0.0,
		"advertising": 0.0,
		"active_jobs": [],
		"active_job": {},
		"job_offers": [],
		"job_queue": [],
		"focused_job_id": "",
		"job_board_stamp": "",
		"job_board_seq": 0,
	}


func _default_build() -> Dictionary:
	return {
		"perks": [],
		"perk_inventory": [],
		"perk_liabilities": [],
	"draft_state": {"sequence": 0, "rerolls": 0},
		"hardware": ["used_laptop"],
		"upgrades": [],
		"status_effects": [],
		"modules": [],
		"board": {"slot_count": BoardSystem.DEFAULT_SLOT_COUNT, "active_workflow": 0},
		"workflows": [],
		"workflow_capacity": BoardSystem.DEFAULT_WORKFLOW_CAPACITY,
		"dwelling": "bedroom",
		"cloud_tier": "none",
		"advertising_tier": "none",
		"upgrade_levels": {},
	}


func _default_statistics() -> Dictionary:
	return {
		"lifetime_tokens": 0.0,
		"failed_jobs": 0,
		"completed_jobs": 0,
		## What the last round of delivered work paid, for perks that earn a
		## share of the fee rather than a flat sum.
		"last_job_reward": 0.0,
		"absurdity_metrics": {},
		"peak_token_rate": 0.0,
		"peak_cash": 0.0,
		"peak_debt": 0.0,
		"peak_prompt_tokens": 0.0,
		"hidden_bugs_shipped": 0,
	"max_cloud_share": 0.0,
	"stage_repeats": 0,
		"max_heat_ratio": 0.0,
		"jobs_accepted": 0,
		"angel_offers_taken": 0,
		"angel_offers_declined": 0,
		"hardware_sold": 0,
		"modules_drafted": 0,
	}


func _default_ascension() -> Dictionary:
	return {
		"status": "",
		"contract_id": "",
		"baseline_tokens": 0.0,
		"tokens_burned": 0.0,
		"deadline_round": 0,
		"quality_sum": 0.0,
		"quality_count": 0,
	}


func _default_flags() -> Dictionary:
	return {
		"loss_reason": "",
		"victory": false,
		"outcome": "",
		"ascension_tier": 0,
		"fire_risk": false,
		"post_victory": false,
		"post_victory_phase": "",
		"legacy_banked": false,
		"location_completed": false,
		"next_location": "",
		"draft_kind": "",
		"difficulty": "normal",
	}


func _get_section(section_name: String) -> Variant:
	match section_name:
		"calendar":
			return calendar
		"economy":
			return economy
		"compute":
			return compute
		"business":
			return business
		"build":
			return build
		"statistics":
			return statistics
		"ascension":
			return ascension
		"flags":
			return flags
		_:
			return null
