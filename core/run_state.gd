class_name RunState
extends RefCounted

## Authoritative simulation state. UI observes this; it does not contain economic logic.

const SAVE_VERSION := 22

## Upgrades that no longer exist in content. Migration refunds the original
## purchase total from this table rather than looking the defs up.
const REMOVED_UPGRADE_COSTS := {
	"upgrade.cloud_account": {"cost": 600.0, "repeatable": false, "cost_growth": 1.0},
	"upgrade.cloud_reserved": {"cost": 400000.0, "repeatable": false, "cost_growth": 1.0},
	"upgrade.cloud_multicloud": {"cost": 3000000.0, "repeatable": false, "cost_growth": 1.0},
	"upgrade.cloud_unlimited": {"cost": 40000000.0, "repeatable": false, "cost_growth": 1.0},
	"upgrade.cloud_payg": {"cost": 500.0, "repeatable": false, "cost_growth": 1.0},
	"upgrade.cloud_spot": {"cost": 900.0, "repeatable": false, "cost_growth": 1.0},
	"upgrade.cloud_compute": {"cost": 350.0, "repeatable": true, "cost_growth": 1.4},
	"upgrade.ads_basic": {"cost": 300.0, "repeatable": false, "cost_growth": 1.0},
	"upgrade.sales_investment": {"cost": 400.0, "repeatable": true, "cost_growth": 1.35},
}

const REMOVED_PERKS := [
	"perk.free_trial",
	"perk.founder_mode",
	"perk.cloud_baron",
	"perk.ad_tech_goblin",
	"perk.cloud_native",
	"perk.spot_survivor",
	"perk.egress_panic",
]

const REMOVED_MODULES := [
	"op.spot_fleet",
	"op.egress_shield",
]

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
	## What upgrades actually bill. Recurring cost is re-derived from this on
	## every recalculation so a perk that multiplies it multiplies it once.
	"recurring_costs_base": 0.0,
	"recurring_costs": 0.0,
	"income": 0.0,
	"pending_bills": [],
	"rent_unpaid_streak": 0,
	"rent_multiplier": 1.0,
	"round_rent": 400.0,
	"power_base_cost_per_prompt": 10.0,
	"power_cost_per_prompt": 10.0,
	"costs_this_round": 0.0,
	"last_round_costs": 0.0,
}

var compute: Dictionary = {
	"local_capacity": 1_000_000.0,
	"token_rate": 1_000_000.0,
	"local_rate": 1_000_000.0,
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
	"instability": 0.0,
	"efficiency": 1.0,
	"efficiency_base": 1.0,
	"rate_modifiers": [],
}

var business: Dictionary = {
	"reputation": 10.0,
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
	"upgrade_levels": {},
	## The one ledger of "how many of upgrade X does this run own", repeatable
	## and one-off alike (a one-off sits in here at 1). `hardware`/`upgrades`/
	## `upgrade_levels` above are the older, split representation of the same
	## fact and are being folded into this one incrementally — see
	## `UpgradeSystem.upgrade_counts()` — rather than removed outright, since
	## UI and save data still address them directly.
	"upgrade_counts": {},
	## The subset of upgrade_counts that was actually bought for cash. Location
	## starters and permanent grants are owned and billable, but cannot be sold.
	"purchased_upgrade_counts": {},
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
	"stage_repeats": 0,
	"max_heat_ratio": 0.0,
	"jobs_accepted": 0,
	"angel_offers_taken": 0,
	"angel_offers_declined": 0,
	"hardware_sold": 0,
	"modules_drafted": 0,
	"cascades_triggered": 0,
	"faults_suffered": 0,
	"max_instability": 0.0,
	"peak_overkill": 0.0,
	"lifetime_overkill": 0.0,
	"depth_reached": 0,
	"depth_score": 0.0,
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

var depth: Dictionary = {
	"level": 0,
	"affixes": [],
	"stacks": {},
	"status": "",
	"score_mult": 1.0,
	"requirement_mult": 1.0,
	"tokens_needed": 0.0,
	"baseline_tokens": 0.0,
	"pending_picks": [],
}

var flags: Dictionary = {
	"loss_reason": "",
	"victory": false,
	"outcome": "",
	"ascension_tier": 0,
	"fire_risk": false,
	"post_victory": false,
	"post_victory_phase": "",
	"depth_complete": false,
	"depth_complete_pending": false,
	"legacy_banked": false,
	"location_completed": false,
	"next_location": "",
	"draft_kind": "",
	## Set once at `reset_run` from the profile's chosen difficulty, and read
	## back by job scaling rather than re-reading the profile mid-run — so a
	## difficulty change in the menu cannot reach into a run already going.
	"difficulty": "normal",
	## Set-piece investor calls already delivered this run. The desk is torn
	## down on every venue trip, so this has to live on the run rather than
	## on the shell that showed the phone.
	"investor_beats": {},
}


func reset(profile: Dictionary = {}) -> void:
	calendar = _default_calendar()
	economy = _default_economy(profile)
	compute = _default_compute()
	business = _default_business()
	build = _default_build()
	statistics = _default_statistics()
	ascension = _default_ascension()
	depth = _default_depth()
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


## Vince's halfway and last-call beats fire once per run. Remembered here so a
## trip to the market — which unloads the desk — cannot ring the same call again.
func investor_beat_heard(trigger: String) -> bool:
	var beats: Variant = flags.get("investor_beats", {})
	return beats is Dictionary and beats.has(trigger)


func mark_investor_beat(trigger: String) -> void:
	var stored: Variant = flags.get("investor_beats", {})
	var beats: Dictionary = {}
	if stored is Dictionary:
		beats = stored
	beats[trigger] = true
	flags["investor_beats"] = beats


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
		"depth": depth.duplicate(true),
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
	depth = _merge_section(_default_depth(), data.get("depth", {}))
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
	if from_version < 18:
		_migrate_to_derived_recurring_costs()
	if from_version < 19:
		_migrate_to_v19()
	if from_version < 20:
		_migrate_to_v20()
	if from_version < 21:
		_migrate_to_v21(from_version)
	if from_version < 22:
		_migrate_to_v22()


## Workflows become trained engines: each layout keeps run-long OUTPUT / QUALITY
## / THERMAL multipliers, and live contracts remember how they were burned.
func _migrate_to_v22() -> void:
	_clear_removed_workflow_slots()
	for workflow in Array(build.get("workflows", [])):
		if workflow is Dictionary:
			BoardSystem.normalize_workflow_fields(workflow)
	for collection in ["active_jobs", "job_queue", "job_offers"]:
		for job in Array(business.get(collection, [])):
			if job is Dictionary:
				JobSystem.normalize_job_evidence(job)


## Cloud, sales and advertising are gone. Refund paid purchases, drop the
## leftover state, and rebuild the standing bill from what the run still owns.
func _migrate_to_v21(from_version: int) -> void:
	var refund: float = _refund_removed_upgrades(from_version)
	if refund > 0.0:
		economy["cash"] = float(economy.get("cash", 0.0)) + refund
	build["upgrades"] = _without_removed_ids(Array(build.get("upgrades", [])), REMOVED_UPGRADE_COSTS.keys())
	_strip_removed_dict_keys(build.get("upgrade_levels", {}), REMOVED_UPGRADE_COSTS.keys())
	_strip_removed_dict_keys(build.get("upgrade_counts", {}), REMOVED_UPGRADE_COSTS.keys())
	_strip_removed_dict_keys(build.get("purchased_upgrade_counts", {}), REMOVED_UPGRADE_COSTS.keys())
	build["perks"] = _without_removed_ids(Array(build.get("perks", [])), REMOVED_PERKS)
	build["perk_inventory"] = _without_removed_ids(Array(build.get("perk_inventory", [])), REMOVED_PERKS)
	build["modules"] = _without_removed_ids(Array(build.get("modules", [])), REMOVED_MODULES)
	_clear_removed_workflow_slots()
	for stale in [
		"cloud_surcharge_liability", "cloud_base_cost_per_prompt", "cloud_cost_per_prompt",
		"cloud_liability", "cloud_cost_per_round",
	]:
		economy.erase(stale)
	for stale in [
		"cloud_capacity", "cloud_burst", "cloud_burst_prompts", "cloud_rate", "cloud_share",
		"cloud_burst_rounds",
	]:
		compute.erase(stale)
	for stale in ["demand", "demand_modifier", "demand_modifier_base", "advertising"]:
		business.erase(stale)
	build.erase("cloud_tier")
	build.erase("advertising_tier")
	statistics.erase("max_cloud_share")
	_migrate_to_derived_recurring_costs()


func _refund_removed_upgrades(from_version: int) -> float:
	var purchased: Dictionary = Dictionary(build.get("purchased_upgrade_counts", {}))
	var counts: Dictionary = UpgradeSystem.upgrade_counts(self)
	var refund: float = 0.0
	for upgrade_id in REMOVED_UPGRADE_COSTS.keys():
		var spec: Dictionary = REMOVED_UPGRADE_COSTS[upgrade_id]
		var paid: int = 0
		if from_version >= 19:
			paid = int(purchased.get(upgrade_id, 0))
		else:
			paid = int(counts.get(upgrade_id, 0))
			if upgrade_id == "upgrade.cloud_account" and _cloud_account_was_granted():
				paid = maxi(0, paid - 1)
		refund += _removed_purchase_total(spec, paid)
	return refund


func _removed_purchase_total(spec: Dictionary, count: int) -> float:
	var total: float = 0.0
	var cost: float = float(spec.get("cost", 0.0))
	var growth: float = float(spec.get("cost_growth", 1.0))
	var repeatable: bool = bool(spec.get("repeatable", false))
	for level in range(maxi(0, count)):
		if repeatable:
			total += cost * pow(growth, float(level))
		else:
			total += cost
	return total


func _cloud_account_was_granted() -> bool:
	if not MetaProgress.enabled:
		return false
	return (
		MetaProgress.retired_cloud_unlocks()
		or MetaProgress.unlock_count("unlock.cloud_account") > 0
		or MetaProgress.unlock_count("unlock.starting_cloud") > 0
	)


func _clear_removed_workflow_slots() -> void:
	for workflow in Array(build.get("workflows", [])):
		if not workflow is Dictionary:
			continue
		var slots: Array = Array(workflow.get("slots", []))
		for i in range(slots.size()):
			if str(slots[i]) in REMOVED_MODULES:
				slots[i] = ""
		workflow["slots"] = slots


func _without_removed_ids(owned: Array, removed: Array) -> Array:
	var kept: Array = []
	for entry in owned:
		if not (str(entry) in removed):
			kept.append(entry)
	return kept


func _strip_removed_dict_keys(table: Variant, removed: Array) -> void:
	if not table is Dictionary:
		return
	for key in removed:
		table.erase(key)


## Revision scope creep could add outstanding work without increasing the total
## requirement, leaving saved contracts with negative displayed progress.
func _migrate_to_v20() -> void:
	for job in business.get("active_jobs", []):
		if not job is Dictionary:
			continue
		var remaining: float = maxf(0.0, float(job.get("tokens_remaining", 0.0)))
		var requirement: float = maxf(0.0, float(job.get("token_requirement", 0.0)))
		job["token_requirement"] = maxf(requirement, remaining)


## The pipeline pieces were called operations in code and modules everywhere the
## player could see. The state key follows the player's word; a save written
## under the old name keeps its modules.
## Recurring cost used to be one field that recalculation both read and wrote,
## so Executive Committee compounded it every prompt. Rebuild from owned
## upgrades instead of trusting that derived (and possibly compounded) value.
func _migrate_to_derived_recurring_costs() -> void:
	var counts: Dictionary = UpgradeSystem.upgrade_counts(self)
	var base: float = 0.0
	for upgrade_id in counts.keys():
		var upgrade: UpgradeDefinition = ContentDatabase.get_upgrade(str(upgrade_id))
		if upgrade == null:
			continue
		base += upgrade.recurring_cost_delta * maxf(0.0, float(counts.get(upgrade_id, 0)))
	economy["recurring_costs_base"] = base
	# ComputeSystem applies active modifiers on load. Until then the derived
	# field is an honest unmodified answer rather than stale inflation.
	economy["recurring_costs"] = base


## v19 adds sale provenance and finishes the instance-id migration for jobs
## already alive in a v18 save. Existing hardware cannot be classified safely,
## so it is deliberately treated as granted; only later purchases are refundable.
func _migrate_to_v19() -> void:
	build["purchased_upgrade_counts"] = {}
	# A v18 save may already have persisted the bad v17-derived base, so every
	# pre-v19 save gets the authoritative rebuild, not only saves older than v18.
	_migrate_to_derived_recurring_costs()
	_migrate_job_instance_ids()


## Gives every live contract an authored definition id plus a unique instance
## id. Modern unique ids survive unchanged; legacy or duplicate ids are replaced
## deterministically so save/load never changes which contract is focused.
func _migrate_job_instance_ids() -> void:
	var seen: Dictionary = {}
	var old_focus: String = str(business.get("focused_job_id", ""))
	var migrated_focus: String = ""
	var collection_labels: Dictionary = {
		"job_offers": "offer",
		"job_queue": "queue",
		"active_jobs": "active",
	}
	for collection in ["job_offers", "job_queue", "active_jobs"]:
		var jobs: Array = Array(business.get(collection, []))
		for index in range(jobs.size()):
			var job: Variant = jobs[index]
			if not job is Dictionary:
				continue
			var old_id: String = str(job.get("id", ""))
			var definition_id: String = str(job.get("definition_id", ""))
			var legacy: bool = definition_id == ""
			if definition_id == "":
				definition_id = old_id
			job["definition_id"] = definition_id
			var instance_id: String = old_id
			if legacy or instance_id == "" or seen.has(instance_id):
				var stem: String = definition_id if definition_id != "" else "job.legacy"
				instance_id = "%s.legacy.%s.%d" % [
					stem, str(collection_labels[collection]), index,
				]
				var collision: int = 1
				while seen.has(instance_id):
					instance_id = "%s.legacy.%s.%d.%d" % [
						stem, str(collection_labels[collection]), index, collision,
					]
					collision += 1
			job["id"] = instance_id
			seen[instance_id] = true
			jobs[index] = job
			if collection == "active_jobs" and migrated_focus == "" and old_id == old_focus:
				migrated_focus = instance_id
		business[collection] = jobs
	business["focused_job_id"] = migrated_focus
	var active_jobs: Array = Array(business.get("active_jobs", []))
	business["active_job"] = active_jobs[0] if active_jobs.size() == 1 else {}


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
	# Permanent starting cloud is not an upgrade; without this a base rebuild
	# would drop the invoice the unlock is supposed to keep charging.
	if MetaProgress.enabled:
		var rank: int = MetaProgress.unlock_count("unlock.starting_cloud")
		if rank > 0:
			var unlock: Dictionary = MetaProgress.get_unlock("unlock.starting_cloud")
			total += float(unlock.get("recurring_cost", 0.0)) * float(rank)
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
		"recurring_costs_base": 0.0,
		"recurring_costs": 0.0,
		"income": 0.0,
		"pending_bills": [],
		"rent_unpaid_streak": 0,
		"rent_multiplier": float(profile.get("rent_multiplier", 1.0)),
		"round_rent": float(economy_balance.get("starting_rent", 400.0)) * float(profile.get("rent_multiplier", 1.0)),
		"power_base_cost_per_prompt": base_power,
		"power_cost_per_prompt": base_power,
		"costs_this_round": 0.0,
		"last_round_costs": 0.0,
	}


func _default_compute() -> Dictionary:
	return {
		"local_capacity": 1_000_000.0,
		"token_rate": 1_000_000.0,
		"local_rate": 1_000_000.0,
		"prompt_rate": 1_000_000.0,
		"power_draw": 65.0,
		"cooling": 0.0,
		"meta_cooling": 0.0,
		"heat": 0.0,
		"heat_capacity": 100.0,
		"instability": 0.0,
		"efficiency": 1.0,
		"efficiency_base": 1.0,
		"rate_modifiers": [],
	}


func _default_business() -> Dictionary:
	return {
		"reputation": 10.0,
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
		"upgrade_levels": {},
		"upgrade_counts": {},
		"purchased_upgrade_counts": {},
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
		"stage_repeats": 0,
		"max_heat_ratio": 0.0,
		"jobs_accepted": 0,
		"angel_offers_taken": 0,
		"angel_offers_declined": 0,
	"hardware_sold": 0,
	"modules_drafted": 0,
	"cascades_triggered": 0,
	"faults_suffered": 0,
	"max_instability": 0.0,
	"peak_overkill": 0.0,
	"lifetime_overkill": 0.0,
	"depth_reached": 0,
	"depth_score": 0.0,
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


func _default_depth() -> Dictionary:
	return {
		"level": 0,
		"affixes": [],
		"stacks": {},
		"status": "",
		"score_mult": 1.0,
		"requirement_mult": 1.0,
		"tokens_needed": 0.0,
		"baseline_tokens": 0.0,
		"pending_picks": [],
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
		"depth_complete": false,
		"depth_complete_pending": false,
		"legacy_banked": false,
		"location_completed": false,
		"next_location": "",
		"draft_kind": "",
		"difficulty": "normal",
		"investor_beats": {},
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
		"depth":
			return depth
		"flags":
			return flags
		_:
			return null
