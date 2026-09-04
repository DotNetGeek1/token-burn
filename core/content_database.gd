extends Node

## Loads and validates JSON content into definition Resources.

var jobs: Array[JobDefinition] = []
var perks: Array[PerkDefinition] = []
var upgrades: Array[UpgradeDefinition] = []
var events: Array[EventDefinition] = []
var modules: Array[ModuleDefinition] = []
var balance: Dictionary = {}
## The five tiered cabinet systems (`content/upgrades/cabinet_systems.json`):
## tier values, costs, generation thresholds and the dwelling migration table.
## Read through `CabinetSystems`.
var cabinet_systems: Dictionary = {}
var comparisons: Array = []
var rarity_weights: Dictionary = {}
var synergies: Array = []
## The contract each location is played for. Exactly one per location.
var ascension_contracts: Array = []
var _ascension_contracts_by_id: Dictionary = {}
## Permanent awards. Plain dictionaries rather than Resources: nothing reads
## them in the hot path, and the gallery wants the raw copy verbatim.
var achievements: Array = []
var _achievements_by_id: Dictionary = {}

var _jobs_by_id: Dictionary = {}
var _perks_by_id: Dictionary = {}
var _upgrades_by_id: Dictionary = {}
var _events_by_id: Dictionary = {}
var _modules_by_id: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	jobs.clear()
	perks.clear()
	upgrades.clear()
	events.clear()
	modules.clear()
	synergies.clear()
	ascension_contracts.clear()
	achievements.clear()
	_achievements_by_id.clear()
	_jobs_by_id.clear()
	_perks_by_id.clear()
	_upgrades_by_id.clear()
	_events_by_id.clear()
	_modules_by_id.clear()
	_ascension_contracts_by_id.clear()
	_load_jobs()
	_load_perks()
	_load_upgrades()
	_load_events()
	_load_modules()
	_load_ascension_contracts()
	_load_achievements()
	_load_balance()
	_validate_content()


func get_job(id: String) -> JobDefinition:
	return _jobs_by_id.get(id, null)


func get_perk(id: String) -> PerkDefinition:
	return _perks_by_id.get(id, null)


func get_upgrade(id: String) -> UpgradeDefinition:
	return _upgrades_by_id.get(id, null)


func get_event(id: String) -> EventDefinition:
	return _events_by_id.get(id, null)


func get_module(id: String) -> ModuleDefinition:
	return _modules_by_id.get(id, null)


func get_ascension_contract(id: String) -> Dictionary:
	return Dictionary(_ascension_contracts_by_id.get(id, {})).duplicate(true)


func get_achievement(id: String) -> Dictionary:
	return Dictionary(_achievements_by_id.get(id, {})).duplicate(true)


## The achievement that has to be earned before a module can appear in the Market,
## or "" for the modules everybody starts with access to.
func module_unlock_achievement(module_id: String) -> String:
	var module: ModuleDefinition = get_module(module_id)
	return module.unlock_achievement if module != null else ""


func starter_modules() -> Array[String]:
	var ids: Array[String] = []
	for module in modules:
		if module.starter:
			ids.append(module.id)
	return ids


## The modules a run begins with already placed. The rest of the starters wait
## on the bench, which is the first decision the board asks for.
func opening_pipeline_modules() -> Array[String]:
	var ids: Array[String] = []
	for module in modules:
		if module.starter and module.opens_pipeline:
			ids.append(module.id)
	return ids


## A gated module stays out of the Market until every authored gate is met:
## achievement, total victories, and Hard victories are ANDed together so a
## veteran card cannot leak into a fresh profile through any single path.
func module_is_unlocked(module: ModuleDefinition) -> bool:
	if module.unlock_achievement != "" and not MetaProgress.has_achievement(module.unlock_achievement):
		return false
	if MetaProgress.victories() < module.min_victories:
		return false
	if MetaProgress.victories_on("hard") < module.min_hard_victories:
		return false
	return true


func unlocked_modules() -> Array[ModuleDefinition]:
	var result: Array[ModuleDefinition] = []
	for module in modules:
		if module_is_unlocked(module):
			result.append(module)
	return result


## Modules that become eligible exactly when the profile reaches these victory
## counts. Used by the run-end report so crossing 1/2/3/5 or Hard 1/3 is visible.
func modules_unlocked_at_victory_counts(total_victories: int, hard_victories: int) -> Array[ModuleDefinition]:
	var total_thresholds := [1, 2, 3, 5]
	var hard_thresholds := [1, 3]
	var result: Array[ModuleDefinition] = []
	for module in modules:
		var crossed_total: bool = (
			module.min_victories > 0
			and module.min_victories == total_victories
			and total_victories in total_thresholds
		)
		var crossed_hard: bool = (
			module.min_hard_victories > 0
			and module.min_hard_victories == hard_victories
			and hard_victories in hard_thresholds
		)
		if not crossed_total and not crossed_hard:
			continue
		if not module_is_unlocked(module):
			continue
		result.append(module)
	return result


## Human-readable reasons a module is still out of the Market.
func module_lock_reasons(module: ModuleDefinition) -> PackedStringArray:
	var reasons: PackedStringArray = []
	if module.unlock_achievement != "":
		if not MetaProgress.has_achievement(module.unlock_achievement):
			var achievement: Dictionary = get_achievement(module.unlock_achievement)
			var label: String = str(achievement.get("name", module.unlock_achievement))
			reasons.append("Earn achievement: %s" % label)
	if MetaProgress.victories() < module.min_victories:
		var wins: int = module.min_victories
		reasons.append("Win %d run%s" % [wins, "" if wins == 1 else "s"])
	if MetaProgress.victories_on("hard") < module.min_hard_victories:
		var hard_wins: int = module.min_hard_victories
		if hard_wins == 1:
			reasons.append("Win Hard once")
		else:
			reasons.append("Win Hard %d times" % hard_wins)
	if module.min_location_tier > 0:
		var order: Array = MetaProgress.location_order()
		var highest_tier: int = 0
		for location_id in MetaProgress.unlocked_locations():
			highest_tier = maxi(highest_tier, order.find(str(location_id)))
		if highest_tier < module.min_location_tier and module.min_location_tier < order.size():
			reasons.append(
				"Requires %s or later" % MetaProgress.location_name(str(order[module.min_location_tier]))
			)
	return reasons


func perk_is_unlocked(perk: PerkDefinition) -> bool:
	if perk.unlock_achievement == "":
		return true
	return MetaProgress.has_achievement(perk.unlock_achievement)


## Whether a perk is eligible for His Table this round: unlocked, allowed on
## the current difficulty and location, not already collected, and not blocked.
func perk_is_eligible(
	perk: PerkDefinition,
	run_state: RunState,
	blocked_ids: Array = []
) -> bool:
	if perk == null:
		return false
	var collected: Array = run_state.build.get("perk_inventory", [])
	if perk.id in collected or perk.id in blocked_ids:
		return false
	if not perk_is_unlocked(perk):
		return false
	if not _difficulty_allows_run(run_state, perk.difficulty):
		return false
	var tier: int = _location_tier_for_run(run_state)
	if not _location_tier_allows(tier, perk.min_location_tier, perk.max_location_tier):
		return false
	return true


## Whether a module can appear on the Market shelf this round.
func module_is_eligible(
	module: ModuleDefinition,
	run_state: RunState,
	blocked_ids: Array = []
) -> bool:
	if module == null:
		return false
	var owned_modules: Array = run_state.build.get("modules", [])
	if module.id in owned_modules or module.id in blocked_ids:
		return false
	if not module_is_unlocked(module):
		return false
	if not _difficulty_allows_run(run_state, module.difficulty):
		return false
	var tier: int = _location_tier_for_run(run_state)
	if not _location_tier_allows(tier, module.min_location_tier, module.max_location_tier):
		return false
	return true


## Perk-only angel table. Modules never appear here.
func draw_angel_perks(
	rng: DeterministicRng,
	run_state: RunState,
	count: int = 3,
	owned_tags: Array = [],
	blocked_ids: Array = [],
	rarity_bias: float = 0.0
) -> Array:
	var pool: Array = []
	for perk in perks:
		if not perk_is_eligible(perk, run_state, blocked_ids):
			continue
		pool.append({
			"type": "perk",
			"id": perk.id,
			"label": perk.name,
			"rarity": perk.rarity,
			"tags": Array(perk.tags),
			"weight": _weighted_tag_affinity(perk.rarity, perk.draft_weight, perk.tags, owned_tags, rarity_bias),
		})
	return _weighted_picks(rng, pool, count)


## Backwards-compatible alias: the angel table is perk-only now.
func draw_angel_offers(
	rng: DeterministicRng,
	run_state: RunState,
	count: int = 3,
	owned_tags: Array = [],
	rarity_bias: float = 0.0,
	blocked_ids: Array = []
) -> Array:
	return draw_angel_perks(rng, run_state, count, owned_tags, blocked_ids, rarity_bias)


## Market shelf draw. Same unlock/location/difficulty gates as profile eligibility,
## minus owned modules and any IDs blocked for this draw (e.g. previous shelf).
func draw_market_modules(
	rng: DeterministicRng,
	run_state: RunState,
	count: int,
	owned_tags: Array = [],
	blocked_ids: Array = [],
	rarity_bias: float = 0.0
) -> Array[ModuleDefinition]:
	var pool: Array = []
	for module in modules:
		if not module_is_eligible(module, run_state, blocked_ids):
			continue
		pool.append({
			"item": module,
			"weight": _weighted_tag_affinity(
				module.rarity, module.draft_weight, module.tags, owned_tags, rarity_bias
			),
		})
	var picks: Array[ModuleDefinition] = []
	for entry in _weighted_picks(rng, pool, count):
		picks.append(entry["item"])
	return picks


func _location_tier_for_run(run_state: RunState) -> int:
	var order: Array = MetaProgress.location_order()
	if order.is_empty():
		order = Array(balance.get("economy", {}).get("location_order", []))
	var dwelling: String = str(run_state.build.get("dwelling", "bedroom"))
	var index: int = order.find(dwelling)
	return maxi(0, index)


func location_tier_for_run(run_state: RunState) -> int:
	return _location_tier_for_run(run_state)


func _difficulty_allows_run(run_state: RunState, allowed: PackedStringArray) -> bool:
	if allowed.is_empty():
		return true
	return str(run_state.flags.get("difficulty", "normal")) in allowed


func _location_tier_allows(tier: int, min_tier: int, max_tier: int) -> bool:
	if min_tier > 0 and tier < min_tier:
		return false
	if max_tier >= 0 and tier > max_tier:
		return false
	return true


func _weighted_tag_affinity(
	rarity: String,
	draft_weight: float,
	tags: PackedStringArray,
	owned_tags: Array,
	rarity_bias: float = 0.0
) -> float:
	var affinity: float = float(_build_tuning().get("draft_tag_affinity", 1.5))
	var affinity_cap: float = float(_build_tuning().get("draft_tag_affinity_cap", 4.0))
	var weight: float = _rarity_weight(rarity, rarity_bias) * maxf(draft_weight, 0.01)
	var matches: int = 0
	for tag in tags:
		if tag in owned_tags:
			matches += 1
	if matches > 0:
		weight *= minf(pow(affinity, float(matches)), affinity_cap)
	return weight


func _weighted_picks(rng: DeterministicRng, pool: Array, count: int) -> Array:
	if pool.is_empty() or count <= 0:
		return []
	var picks: Array = []
	var mutable_pool: Array = pool.duplicate()
	for _i in range(count):
		if mutable_pool.is_empty():
			break
		var picked = rng.weighted_pick(mutable_pool, "weight")
		if picked == null:
			break
		picks.append(picked)
		mutable_pool.erase(picked)
	return picks


## Legacy helper retained for older tests/tools. Prefer `draw_market_modules`.
func draw_modules(
	rng: DeterministicRng,
	count: int = 2,
	owned_ids: Array = [],
	rarity_bias: float = 0.0
) -> Array[ModuleDefinition]:
	var state := RunState.new()
	state.reset()
	state.build["modules"] = owned_ids.duplicate()
	return draw_market_modules(rng, state, count, [], [], rarity_bias)


## Legacy helper. Prefer `draw_angel_perks` for production angel tables.
func draw_perks(
	rng: DeterministicRng,
	count: int = 3,
	owned_ids: Array = [],
	rarity_bias: float = 0.0,
	owned_tags: Array = [],
	blocked_ids: Array = []
) -> Array[PerkDefinition]:
	var state := RunState.new()
	state.reset()
	state.build["perk_inventory"] = owned_ids.duplicate()
	var offers: Array = draw_angel_perks(rng, state, count, owned_tags, blocked_ids, rarity_bias)
	var picks: Array[PerkDefinition] = []
	for offer in offers:
		var perk: PerkDefinition = get_perk(str(offer.get("id", "")))
		if perk != null:
			picks.append(perk)
	return picks


func draw_upgrades(rng: DeterministicRng, count: int = 3, owned_ids: Array = []) -> Array[UpgradeDefinition]:
	var pool: Array[UpgradeDefinition] = []
	for upgrade in upgrades:
		if upgrade.id in owned_ids:
			continue
		pool.append(upgrade)
	if pool.is_empty():
		return []
	return rng.shuffle(pool).slice(0, mini(count, pool.size()))


func draw_event(rng: DeterministicRng) -> EventDefinition:
	var pool: Array = []
	for event in events:
		pool.append({"item": event, "weight": event.weight})
	var picked = rng.weighted_pick(pool, "weight")
	return picked["item"] if picked != null else null


func get_all_subscription_events() -> Array[String]:
	var events_found: Dictionary = {}
	for perk in perks:
		for sub in perk.subscriptions:
			if sub is Dictionary:
				events_found[str(sub.get("event", ""))] = true
	var result: Array[String] = []
	for key in events_found.keys():
		if key != "":
			result.append(key)
	return result


## Rare things carry small weights, so flattening the curve is how a draft comes
## to hold them. `bias` runs from 0 (the ordinary odds) to 1 (rarity ignored
## entirely, every item as likely as any other).
func _rarity_weight(rarity: String, bias: float = 0.0) -> float:
	var weight: float = float(rarity_weights.get(rarity, 1.0))
	if bias <= 0.0 or weight <= 0.0:
		return weight
	return pow(weight, 1.0 - clampf(bias, 0.0, 1.0))


func _load_jobs() -> void:
	var data: Array = _load_json_array("res://content/jobs/jobs.json")
	for entry in data:
		var job := JobDefinition.new()
		job.id = str(entry.get("id", ""))
		job.name = str(entry.get("name", ""))
		job.description = str(entry.get("description", ""))
		job.tier = int(entry.get("tier", 0))
		job.work_units = float(entry.get("work_units", 1.0))
		job.reward_units = float(entry.get("reward_units", 1.0))
		job.deadline_pressure = float(entry.get("deadline_pressure", 1.0))
		job.windfall = bool(entry.get("windfall", false))
		job.quality_threshold = float(entry.get("quality_threshold", 0.0))
		job.deadline_days = float(entry.get("deadline_days", 0.0))
		job.context_requirement = str(entry.get("context_requirement", ""))
		job.revision_risk = float(entry.get("revision_risk", 0.0))
		job.tags = PackedStringArray(Array(entry.get("tags", [])))
		job.complications = Array(entry.get("complications", []), TYPE_DICTIONARY, "", null)
		job.stretch_goals = Array(entry.get("stretch_goals", []), TYPE_DICTIONARY, "", null)
		job.board_rules = Array(entry.get("board_rules", []), TYPE_DICTIONARY, "", null)
		job.demands = PackedStringArray(Array(entry.get("demands", [])))
		jobs.append(job)
		_jobs_by_id[job.id] = job


func _load_perks() -> void:
	var data: Array = _load_json_array("res://content/perks/perks.json")
	for entry in data:
		var perk := PerkDefinition.new()
		perk.id = str(entry.get("id", ""))
		perk.name = str(entry.get("name", ""))
		perk.rarity = str(entry.get("rarity", "common"))
		perk.tags = PackedStringArray(Array(entry.get("tags", [])))
		perk.description_template = str(entry.get("description_template", ""))
		perk.parameters = entry.get("parameters", {})
		perk.subscriptions = Array(entry.get("subscriptions", []), TYPE_DICTIONARY, "", null)
		perk.requires_tags = PackedStringArray(Array(entry.get("requires_tags", [])))
		perk.excludes_tags = PackedStringArray(Array(entry.get("excludes_tags", [])))
		perk.incompatible_ids = PackedStringArray(Array(entry.get("incompatible_ids", [])))
		perk.stacking = entry.get("stacking", {})
		perk.unlock_achievement = str(entry.get("unlock_achievement", ""))
		perk.min_location_tier = int(entry.get("min_location_tier", 0))
		perk.max_location_tier = int(entry.get("max_location_tier", -1))
		perk.draft_weight = float(entry.get("draft_weight", 1.0))
		perk.difficulty = PackedStringArray(Array(entry.get("difficulty", ["normal", "hard"])))
		perk.grants = entry.get("grants", {})
		perks.append(perk)
		_perks_by_id[perk.id] = perk


func _load_upgrades() -> void:
	var data: Array = _load_json_array("res://content/upgrades/upgrades.json")
	for entry in data:
		var upgrade := UpgradeDefinition.new()
		upgrade.id = str(entry.get("id", ""))
		upgrade.name = str(entry.get("name", ""))
		upgrade.category = str(entry.get("category", ""))
		upgrade.description = str(entry.get("description", ""))
		upgrade.cost = float(entry.get("cost", 0.0))
		upgrade.tags = PackedStringArray(Array(entry.get("tags", [])))
		upgrade.recurring_cost_delta = float(entry.get("recurring_cost_delta", 0.0))
		upgrade.hardware_key = str(entry.get("hardware_key", ""))
		upgrade.component_key = str(entry.get("component_key", ""))
		upgrade.requires_hardware = str(entry.get("requires_hardware", ""))
		var system_gate: Variant = entry.get("requires_system", {})
		var gates: Dictionary = {}
		if system_gate is Dictionary:
			for system_id in Dictionary(system_gate).keys():
				gates[str(system_id)] = int(Dictionary(system_gate)[system_id])
		upgrade.requires_system = gates
		upgrade.requires_chapter = str(entry.get("requires_chapter", ""))
		upgrade.requires_upgrade = str(entry.get("requires_upgrade", ""))
		upgrade.repeatable = bool(entry.get("repeatable", false))
		upgrade.cost_growth = float(entry.get("cost_growth", 1.35))
		upgrade.max_level = int(entry.get("max_level", 0))
		var effects: Array[EffectDefinition] = []
		for effect_entry in entry.get("effects", []):
			var effect := EffectDefinition.new()
			effect.operation = str(effect_entry.get("operation", "add"))
			effect.target = str(effect_entry.get("target", ""))
			effect.value = effect_entry.get("value", 0.0)
			effects.append(effect)
		upgrade.effects = effects
		upgrades.append(upgrade)
		_upgrades_by_id[upgrade.id] = upgrade


func _load_events() -> void:
	var data: Array = _load_json_array("res://content/events/events.json")
	for entry in data:
		var event := EventDefinition.new()
		event.id = str(entry.get("id", ""))
		event.name = str(entry.get("name", ""))
		event.description = str(entry.get("description", ""))
		event.trigger_event = str(entry.get("trigger_event", EventBus.EVENT_ROUND_ENDED))
		event.weight = float(entry.get("weight", 1.0))
		event.conditions = Array(entry.get("conditions", []), TYPE_DICTIONARY, "", null)
		var effects: Array[EffectDefinition] = []
		for effect_entry in entry.get("effects", []):
			var effect := EffectDefinition.new()
			effect.operation = str(effect_entry.get("operation", "add"))
			effect.target = str(effect_entry.get("target", ""))
			effect.value = effect_entry.get("value", 0.0)
			effects.append(effect)
		event.effects = effects
		events.append(event)
		_events_by_id[event.id] = event


func _load_modules() -> void:
	var data: Array = _load_json_array("res://content/modules/modules.json")
	for entry in data:
		var module := ModuleDefinition.new()
		module.id = str(entry.get("id", ""))
		module.name = str(entry.get("name", ""))
		module.category = str(entry.get("category", ""))
		module.rarity = str(entry.get("rarity", "common"))
		module.tags = PackedStringArray(Array(entry.get("tags", [])))
		module.description_template = str(entry.get("description_template", ""))
		module.badge = str(entry.get("badge", ""))
		module.parameters = entry.get("parameters", {})
		module.slot_effects = Array(entry.get("slot_effects", []), TYPE_DICTIONARY, "", null)
		module.priority = int(entry.get("priority", 50))
		module.starter = bool(entry.get("starter", false))
		module.opens_pipeline = bool(entry.get("opens_pipeline", false))
		module.unlock_achievement = str(entry.get("unlock_achievement", ""))
		module.min_victories = int(entry.get("min_victories", 0))
		module.min_hard_victories = int(entry.get("min_hard_victories", 0))
		module.min_location_tier = int(entry.get("min_location_tier", 0))
		module.max_location_tier = int(entry.get("max_location_tier", -1))
		module.draft_weight = float(entry.get("draft_weight", 1.0))
		module.difficulty = PackedStringArray(Array(entry.get("difficulty", ["normal", "hard"])))
		module.combos = Array(entry.get("combos", []), TYPE_DICTIONARY, "", null)
		module.finalizing_effects = Array(entry.get("finalizing_effects", []), TYPE_DICTIONARY, "", null)
		module.folded_effects = Array(entry.get("folded_effects", []), TYPE_DICTIONARY, "", null)
		module.completion_effects = Array(entry.get("completion_effects", []), TYPE_DICTIONARY, "", null)
		modules.append(module)
		_modules_by_id[module.id] = module


func _load_achievements() -> void:
	for entry in _load_json_array("res://content/achievements/achievements.json"):
		if not entry is Dictionary:
			continue
		achievements.append(entry)
		_achievements_by_id[str(entry.get("id", ""))] = entry


## Build-layer knobs: the perk cap and how hard drafts lean into owned tags.
func _build_tuning() -> Dictionary:
	var economy: Dictionary = balance.get("economy", {})
	var block: Variant = economy.get("build", {})
	return block if block is Dictionary else {}


func _load_balance() -> void:
	balance["economy"] = _load_json_dict("res://content/balance/economy.json")
	balance["job_scaling"] = _load_json_dict("res://content/balance/job_scaling.json")
	balance["dwelling_costs"] = _load_json_dict("res://content/balance/dwelling_costs.json")
	balance["hardware_curves"] = _load_json_dict("res://content/balance/hardware_curves.json")
	balance["difficulty_profiles"] = _load_json_dict("res://content/balance/difficulty_profiles.json")
	balance["job_demands"] = _load_json_dict("res://content/balance/job_demands.json")
	balance["pacing_targets"] = _load_json_dict("res://content/balance/pacing_targets.json")
	cabinet_systems = _load_json_dict("res://content/upgrades/cabinet_systems.json")
	rarity_weights = _load_json_dict("res://content/balance/rarity_weights.json")
	comparisons = _load_json_array("res://content/balance/comparisons.json")
	synergies = _load_json_array("res://content/balance/synergies.json")


## Operation names the effect resolver actually understands (see the `match`
## in `EffectResolver._apply_effect_dict`). Content authoring a typo'd op name
## must fail here, at load time, rather than silently doing nothing at the
## table where nobody is watching for it.
const KNOWN_EFFECT_OPERATIONS := [
	"add", "multiply", "set", "cap_min", "cap_max", "convert", "copy",
	"discount", "defer_cost", "borrow", "trigger", "spawn", "remove",
	"reroll", "repeat",
]
## Category enums recognised by `Simulation`/`UpgradeSystem` when installing
## an upgrade. Anything else is a typo that would silently fail to install.
const KNOWN_UPGRADE_CATEGORIES := ["hardware", "component"]
## Module categories the Burn Board and draft affinity already understand.
const KNOWN_MODULE_CATEGORIES := [
	"prompt", "context", "model", "agent", "cache", "test", "hardware", "deploy",
]
## Rarity bands that have draft weights. An unknown rarity drafts at a default
## weight of 1.0 and looks like a balance change rather than a typo.
const KNOWN_MODULE_RARITIES := ["common", "uncommon", "rare", "legendary"]
## Prefixes an effect target may use without resolving against `RunState`:
## `job.`/`batch.`/`stage.` are per-resolution scratch values (see
## `ModifierContext` and `BoardSystem`'s per-stage batch dictionary),
## `build.`/`business.` accept new keys by design (`EffectResolver._finalize_to_run_state`).
const DYNAMIC_TARGET_PREFIXES := ["job.", "batch.", "stage.", "build.", "business.", "mastery."]
const KNOWN_MASTERY_TARGETS := [
	"mastery.output_gain",
	"mastery.quality_gain",
	"mastery.thermal_gain",
	"mastery.gain_mult",
	"mastery.output_gain_mult",
	"mastery.quality_gain_mult",
	"mastery.thermal_gain_mult",
	"mastery.propagate_ratio",
	"mastery.silo",
	"mastery.strip_output",
	"mastery.strip_quality",
]


func _validate_content() -> void:
	for message in ContentValidator.validate(self):
		push_error("ContentDatabase: %s" % message)


## Pure pass over the loaded content, returning every problem found rather
## than pushing errors directly — a compiler's diagnostics list, testable
## with synthetic content without needing to intercept `push_error`.
func collect_validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var hardware_curves: Dictionary = balance.get("hardware_curves", {})
	var dwelling_costs: Dictionary = balance.get("dwelling_costs", {})
	var known_paths: Dictionary = _known_run_state_paths()
	var seen_ids: Dictionary = {}

	for upgrade in upgrades:
		_check_unique_id(errors, seen_ids, "upgrade", upgrade.id)
		if not KNOWN_UPGRADE_CATEGORIES.has(upgrade.category):
			errors.append("upgrade '%s' has unknown category '%s'" % [upgrade.id, upgrade.category])
		if upgrade.cost < 0.0:
			errors.append("upgrade '%s' has negative cost %s" % [upgrade.id, upgrade.cost])
		if upgrade.repeatable and upgrade.cost_growth <= 0.0:
			errors.append("upgrade '%s' is repeatable with non-positive cost_growth %s" % [upgrade.id, upgrade.cost_growth])
		if upgrade.max_level < 0:
			errors.append("upgrade '%s' has negative max_level %s" % [upgrade.id, upgrade.max_level])
		if upgrade.category == "hardware" and upgrade.hardware_key != "":
			if not hardware_curves.has(upgrade.hardware_key):
				errors.append("upgrade '%s' references missing hardware_key '%s'" % [upgrade.id, upgrade.hardware_key])
		if upgrade.category == "component":
			if not hardware_curves.has(upgrade.component_key):
				errors.append("upgrade '%s' references missing component_key '%s'" % [upgrade.id, upgrade.component_key])
			if not hardware_curves.has(upgrade.requires_hardware):
				errors.append("upgrade '%s' fits missing host hardware '%s'" % [upgrade.id, upgrade.requires_hardware])
		if upgrade.requires_chapter != "" and not dwelling_costs.has(upgrade.requires_chapter):
			errors.append("upgrade '%s' requires missing chapter '%s'" % [upgrade.id, upgrade.requires_chapter])
		_validate_system_gate(errors, "upgrade '%s'" % upgrade.id, upgrade.requires_system)
		if upgrade.requires_upgrade != "" and not _upgrades_by_id.has(upgrade.requires_upgrade):
			errors.append("upgrade '%s' requires missing upgrade '%s'" % [upgrade.id, upgrade.requires_upgrade])
		for effect in upgrade.effects:
			_validate_effect(errors, known_paths, "upgrade '%s'" % upgrade.id, effect.operation, effect.target)

	for perk in perks:
		_check_unique_id(errors, seen_ids, "perk", perk.id)
		if perk.unlock_achievement != "" and not _achievements_by_id.has(perk.unlock_achievement):
			errors.append("perk '%s' is gated behind missing achievement '%s'" % [
				perk.id, perk.unlock_achievement,
			])
		_check_draft_gates(
			errors, "perk", perk.id, perk.difficulty, perk.min_location_tier, perk.max_location_tier
		)
		for sub in perk.subscriptions:
			if sub is Dictionary:
				_validate_effect_list(errors, known_paths, "perk '%s'" % perk.id, Array(sub.get("effects", [])))

	for event in events:
		_check_unique_id(errors, seen_ids, "event", event.id)
		for effect in event.effects:
			_validate_effect(errors, known_paths, "event '%s'" % event.id, effect.operation, effect.target)

	for module in modules:
		_check_unique_id(errors, seen_ids, "module", module.id)
		if module.name.strip_edges() == "":
			errors.append("module '%s' has an empty name" % module.id)
		if module.category.strip_edges() == "":
			errors.append("module '%s' has an empty category" % module.id)
		elif not KNOWN_MODULE_CATEGORIES.has(module.category):
			errors.append("module '%s' has unknown category '%s'" % [module.id, module.category])
		if module.rarity.strip_edges() == "":
			errors.append("module '%s' has an empty rarity" % module.id)
		elif not KNOWN_MODULE_RARITIES.has(module.rarity):
			errors.append("module '%s' has unknown rarity '%s'" % [module.id, module.rarity])
		if module.description_template.strip_edges() == "":
			errors.append("module '%s' has an empty description" % module.id)
		if module.tags.is_empty():
			errors.append("module '%s' has no tags" % module.id)
		if module.min_victories < 0:
			errors.append("module '%s' has negative min_victories %d" % [module.id, module.min_victories])
		if module.min_hard_victories < 0:
			errors.append(
				"module '%s' has negative min_hard_victories %d" % [module.id, module.min_hard_victories]
			)
		if module.draft_weight <= 0.0:
			errors.append(
				"module '%s' has non-positive draft_weight %s" % [module.id, str(module.draft_weight)]
			)
		_check_draft_gates(
			errors,
			"module",
			module.id,
			module.difficulty,
			module.min_location_tier,
			module.max_location_tier
		)
		if module.unlock_achievement != "" and not _achievements_by_id.has(module.unlock_achievement):
			errors.append("module '%s' is gated behind missing achievement '%s'" % [
				module.id, module.unlock_achievement,
			])
		for partner_id in module.combo_partners():
			if not _modules_by_id.has(partner_id):
				errors.append("module '%s' declares a combo with missing module '%s'" % [
					module.id, partner_id,
				])
		var has_effects: bool = (
			module.slot_effects.size() > 0
			or module.folded_effects.size() > 0
			or module.finalizing_effects.size() > 0
			or module.completion_effects.size() > 0
		)
		if not has_effects:
			for combo in module.combos:
				if combo is Dictionary and Array(combo.get("effects", [])).size() > 0:
					has_effects = true
					break
		if not has_effects:
			errors.append(
				"module '%s' has no slot, folded, finalizing, completion, or combo effects" % module.id
			)
		_validate_effect_list(errors, known_paths, "module '%s'" % module.id, module.slot_effects)
		_validate_effect_list(
			errors, known_paths, "module '%s' finalizing" % module.id, module.finalizing_effects
		)
		_validate_effect_list(
			errors, known_paths, "module '%s' folded" % module.id, module.folded_effects
		)
		_validate_effect_list(
			errors, known_paths, "module '%s' completion" % module.id, module.completion_effects
		)
		for combo in module.combos:
			if combo is Dictionary:
				_validate_effect_list(
					errors, known_paths,
					"module '%s' combo" % module.id, Array(combo.get("effects", []))
				)
		_validate_module_parameters(
			errors,
			module,
			[
				module.slot_effects,
				module.folded_effects,
				module.finalizing_effects,
				module.completion_effects,
			]
		)
	var demands: Dictionary = balance.get("job_demands", {})
	# Built locally rather than as constants so this file keeps no load-time
	# dependency on BoardSystem, which reads back from this database.
	var known_rule_types: Array = [
		BoardSystem.RULE_BLOCKED_SLOTS,
		BoardSystem.RULE_TAG_BONUS,
		BoardSystem.RULE_MAX_HIDDEN_BUGS,
		BoardSystem.RULE_RECURSION_RISK,
		BoardSystem.RULE_AGENT_SCOPE,
		BoardSystem.RULE_FEATURE_CREEP,
	]
	var known_capabilities: Array = [
		BoardSystem.CAPABILITY_FIX_BUGS,
		BoardSystem.CAPABILITY_REVEAL_BUGS,
		BoardSystem.CAPABILITY_HEAVY_QUALITY,
		BoardSystem.CAPABILITY_THROUGHPUT,
		BoardSystem.CAPABILITY_COOLING,
	]
	# A demand naming a capability nothing can ever report is a demand no
	# workflow can satisfy, which reads in game as an unwinnable contract.
	for demand_id in demands:
		var definition: Variant = demands[demand_id]
		if not definition is Dictionary:
			errors.append("demand '%s' is not an object" % str(demand_id))
			continue
		var match_spec: Dictionary = Dictionary(definition.get("match", {}))
		if match_spec.is_empty():
			errors.append("demand '%s' has no 'match' rule" % str(demand_id))
			continue
		if not match_spec.has("capability"):
			continue
		var capability: String = str(match_spec["capability"])
		if not known_capabilities.has(capability):
			errors.append("demand '%s' asks for unknown capability '%s'" % [
				str(demand_id), capability,
			])
	for job in jobs:
		_check_unique_id(errors, seen_ids, "job", job.id)
		if job.revision_risk < 0.0 or job.revision_risk > 1.0:
			errors.append("job '%s' has revision_risk %s outside [0,1]" % [job.id, job.revision_risk])
		for demand_id in job.demands:
			if not demands.has(str(demand_id)):
				errors.append("job '%s' asks for missing demand '%s'" % [
					job.id, str(demand_id),
				])
		for rule in job.board_rules:
			if not rule is Dictionary:
				continue
			if not rule.has("type"):
				errors.append("job '%s' has a board rule with no 'type'" % job.id)
				continue
			# A rule type BoardSystem does not recognise is silently ignored at
			# the table, so the contract quietly plays without the constraint
			# its card advertises.
			if not known_rule_types.has(str(rule["type"])):
				errors.append("job '%s' has an unknown board rule type '%s'" % [
					job.id, str(rule["type"]),
				])
	for achievement in achievements:
		var reward: Dictionary = Dictionary(achievement.get("reward", {}))
		var reward_type: String = str(reward.get("type", "none"))
		if reward_type == "unlock_module":
			var module_id: String = str(reward.get("module_id", ""))
			if not _modules_by_id.has(module_id):
				errors.append("achievement '%s' unlocks missing module '%s'" % [
					str(achievement.get("id", "")), module_id,
				])
			var module = _modules_by_id.get(module_id)
			if module != null and module.unlock_achievement != str(achievement.get("id", "")):
				errors.append("achievement '%s' unlocks module '%s' but the module points at '%s'" % [
					str(achievement.get("id", "")), module_id, module.unlock_achievement,
				])
		elif reward_type == "unlock_perk":
			var perk_id: String = str(reward.get("perk_id", ""))
			if not _perks_by_id.has(perk_id):
				errors.append("achievement '%s' unlocks missing perk '%s'" % [
					str(achievement.get("id", "")), perk_id,
				])
			var perk = _perks_by_id.get(perk_id)
			if perk != null and perk.unlock_achievement != str(achievement.get("id", "")):
				errors.append("achievement '%s' unlocks perk '%s' but the perk points at '%s'" % [
					str(achievement.get("id", "")), perk_id, perk.unlock_achievement,
				])
	for perk in perks:
		if perk.unlock_achievement == "":
			continue
		var linked: bool = false
		for achievement in achievements:
			var reward: Dictionary = Dictionary(achievement.get("reward", {}))
			if str(reward.get("type", "")) == "unlock_perk" and str(reward.get("perk_id", "")) == perk.id:
				linked = true
				break
		if not linked:
			errors.append("perk '%s' requires achievement '%s' but no achievement unlocks it" % [
				perk.id, perk.unlock_achievement,
			])
	for module in modules:
		if module.unlock_achievement == "":
			continue
		var module_linked: bool = false
		for achievement in achievements:
			var reward: Dictionary = Dictionary(achievement.get("reward", {}))
			if str(reward.get("type", "")) == "unlock_module" and str(reward.get("module_id", "")) == module.id:
				module_linked = true
				break
		if not module_linked:
			errors.append("module '%s' requires achievement '%s' but no achievement unlocks it" % [
				module.id, module.unlock_achievement,
			])
	_validate_module_market_tuning(errors)
	_validate_ascension_contracts(errors)
	_validate_cabinet_systems(errors)
	return errors


## A `requires_system` gate names cabinet systems `cabinet_systems.json` knows
## and asks for a tier inside its tier range; anything else could never be met.
func _validate_system_gate(errors: Array[String], owner: String, gate: Dictionary) -> void:
	if gate.is_empty():
		return
	var systems: Array = []
	for entry in Array(cabinet_systems.get("systems", [])):
		if entry is Dictionary:
			systems.append(str(Dictionary(entry).get("id", "")))
	var range_value: Variant = cabinet_systems.get("tier_range", [1, 4])
	var lo: int = 1
	var hi: int = 4
	if range_value is Array and Array(range_value).size() == 2:
		lo = int(Array(range_value)[0])
		hi = int(Array(range_value)[1])
	for system_id in gate.keys():
		if not (str(system_id) in systems):
			errors.append("%s requires unknown cabinet system '%s'" % [owner, str(system_id)])
			continue
		var tier: int = int(gate[system_id])
		if tier < lo or tier > hi:
			errors.append("%s requires %s tier %d outside %d..%d" % [owner, str(system_id), tier, lo, hi])


## `cabinet_systems.json` is the source of every capacity the board, the rig
## and the Market read, so a malformed row fails at load: ids unique and
## covering the migration order, every tier table exactly tier_range long,
## costs one shorter than that and non-negative, generation thresholds strictly
## ascending, and the dwelling tables naming only rooms `dwelling_costs` knows.
func _validate_cabinet_systems(errors: Array[String]) -> void:
	var data: Dictionary = cabinet_systems
	if data.is_empty():
		errors.append("cabinet_systems content is missing")
		return
	var range_value: Variant = data.get("tier_range", null)
	var lo: int = 1
	var hi: int = 4
	if not range_value is Array or Array(range_value).size() != 2:
		errors.append("cabinet_systems.tier_range must be [min, max]")
	else:
		lo = int(Array(range_value)[0])
		hi = int(Array(range_value)[1])
		if lo < 1 or hi < lo:
			errors.append("cabinet_systems.tier_range %s is not a valid range" % str(range_value))
	var tier_count: int = maxi(1, hi - lo + 1)
	var systems: Variant = data.get("systems", null)
	var system_ids: Array = []
	if not systems is Array or Array(systems).is_empty():
		errors.append("cabinet_systems.systems must be a non-empty array")
	else:
		for entry in Array(systems):
			if not entry is Dictionary:
				errors.append("cabinet_systems.systems has a non-object entry")
				continue
			var system: Dictionary = entry
			var id: String = str(system.get("id", ""))
			if id == "":
				errors.append("cabinet system has an empty id")
				continue
			if id in system_ids:
				errors.append("duplicate cabinet system id '%s'" % id)
			system_ids.append(id)
			if str(system.get("name", "")).strip_edges() == "":
				errors.append("cabinet system '%s' has an empty name" % id)
			var tier_names: Variant = system.get("tier_names", null)
			if not tier_names is Array or Array(tier_names).size() != tier_count:
				errors.append("cabinet system '%s' needs %d tier_names" % [id, tier_count])
			var values: Variant = system.get("tier_values", null)
			if not values is Dictionary or Dictionary(values).is_empty():
				errors.append("cabinet system '%s' has no tier_values" % id)
			else:
				for stat_key in Dictionary(values).keys():
					var column: Variant = Dictionary(values)[stat_key]
					if not column is Array or Array(column).size() != tier_count:
						errors.append("cabinet system '%s' tier_values.%s needs %d entries" % [
							id, str(stat_key), tier_count,
						])
						continue
					var previous: float = -INF
					for value in Array(column):
						if not (value is int or value is float):
							errors.append("cabinet system '%s' tier_values.%s has a non-numeric entry" % [
								id, str(stat_key),
							])
							break
						if float(value) < previous:
							errors.append("cabinet system '%s' tier_values.%s must not decrease" % [
								id, str(stat_key),
							])
							break
						previous = float(value)
			var costs: Variant = system.get("cost", null)
			if not costs is Array or Array(costs).size() != tier_count - 1:
				errors.append("cabinet system '%s' needs %d cost entries (tiers %d..%d)" % [
					id, tier_count - 1, lo + 1, hi,
				])
			else:
				for cost in Array(costs):
					if not (cost is int or cost is float) or float(cost) < 0.0:
						errors.append("cabinet system '%s' has a negative or non-numeric cost" % id)
						break
	var order: Variant = data.get("migration_value_order", null)
	if not order is Array or Array(order).is_empty():
		errors.append("cabinet_systems.migration_value_order is missing")
	else:
		for entry in Array(order):
			if str(entry) not in system_ids:
				errors.append("cabinet_systems.migration_value_order names unknown system '%s'" % str(entry))
		for id in system_ids:
			if id not in Array(order):
				errors.append("cabinet_systems.migration_value_order is missing system '%s'" % id)
	var thresholds: Variant = data.get("generation_thresholds", null)
	if not thresholds is Array or Array(thresholds).is_empty():
		errors.append("cabinet_systems.generation_thresholds is missing")
	else:
		var last_sum: int = -1
		for entry in Array(thresholds):
			if not entry is Dictionary:
				errors.append("cabinet_systems.generation_thresholds has a non-object entry")
				continue
			var min_sum: int = int(Dictionary(entry).get("min_sum", -1))
			if str(Dictionary(entry).get("name", "")).strip_edges() == "":
				errors.append("cabinet_systems generation at min_sum %d has no name" % min_sum)
			if min_sum <= last_sum:
				errors.append("cabinet_systems.generation_thresholds must ascend (min_sum %d after %d)" % [
					min_sum, last_sum,
				])
			last_sum = min_sum
	var dwelling_costs: Dictionary = balance.get("dwelling_costs", {})
	var order_size: int = Array(order).size() if order is Array else system_ids.size()
	var migration: Variant = data.get("migration_from_dwelling", null)
	if not migration is Dictionary or Dictionary(migration).is_empty():
		errors.append("cabinet_systems.migration_from_dwelling is missing")
	else:
		for dwelling in Dictionary(migration).keys():
			if not dwelling_costs.has(str(dwelling)):
				errors.append("cabinet_systems.migration_from_dwelling names unknown dwelling '%s'" % str(dwelling))
			var row: Variant = Dictionary(migration)[dwelling]
			if not row is Array or Array(row).size() != order_size:
				errors.append("cabinet_systems.migration_from_dwelling.%s needs %d tiers" % [str(dwelling), order_size])
				continue
			for value in Array(row):
				if int(value) < lo or int(value) > hi:
					errors.append("cabinet_systems.migration_from_dwelling.%s has tier %s outside %d..%d" % [
						str(dwelling), str(value), lo, hi,
					])
					break
		for dwelling in dwelling_costs.keys():
			if not Dictionary(migration).has(str(dwelling)):
				errors.append("cabinet_systems.migration_from_dwelling has no row for dwelling '%s'" % str(dwelling))
	var caps: Variant = data.get("chapter_max_tier", null)
	if not caps is Dictionary or Dictionary(caps).is_empty():
		errors.append("cabinet_systems.chapter_max_tier is missing")
	else:
		for dwelling in Dictionary(caps).keys():
			if not dwelling_costs.has(str(dwelling)):
				errors.append("cabinet_systems.chapter_max_tier names unknown dwelling '%s'" % str(dwelling))
			var cap: int = int(Dictionary(caps)[dwelling])
			if cap < lo or cap > hi:
				errors.append("cabinet_systems.chapter_max_tier.%s is outside %d..%d" % [str(dwelling), lo, hi])
		for dwelling in dwelling_costs.keys():
			if not Dictionary(caps).has(str(dwelling)):
				errors.append("cabinet_systems.chapter_max_tier has no entry for dwelling '%s'" % str(dwelling))


func _validate_module_market_tuning(errors: Array[String]) -> void:
	var economy: Dictionary = balance.get("economy", {})
	var market: Variant = economy.get("module_market", {})
	if not market is Dictionary or market.is_empty():
		errors.append("economy.module_market tuning is missing")
		return
	var locations: Array = Array(economy.get("location_order", []))
	var slots: Array = Array(market.get("slots_by_location_tier", []))
	if slots.size() < locations.size():
		errors.append(
			"economy.module_market.slots_by_location_tier has %d entries; need at least %d for location_order"
			% [slots.size(), locations.size()]
		)
	for index in range(slots.size()):
		if int(slots[index]) <= 0:
			errors.append(
				"economy.module_market.slots_by_location_tier[%d] must be positive" % index
			)
	var price_mults: Variant = market.get("rarity_price_rent_mult", {})
	if not price_mults is Dictionary:
		errors.append("economy.module_market.rarity_price_rent_mult must be an object")
	else:
		for rarity in KNOWN_MODULE_RARITIES:
			if not price_mults.has(rarity):
				errors.append(
					"economy.module_market.rarity_price_rent_mult is missing '%s'" % rarity
				)
			elif float(price_mults[rarity]) <= 0.0:
				errors.append(
					"economy.module_market.rarity_price_rent_mult.%s must be positive" % rarity
				)
		for rarity in price_mults.keys():
			if not KNOWN_MODULE_RARITIES.has(str(rarity)):
				errors.append(
					"economy.module_market.rarity_price_rent_mult has unknown rarity '%s'" % rarity
				)
	for key in ["reroll_rent_mult", "reroll_job_reward_mult", "reroll_growth", "price_floor"]:
		if float(market.get(key, 0.0)) <= 0.0:
			errors.append("economy.module_market.%s must be positive" % key)


## One authoritative record of every place an upgrade/perk/event effect can
## legally write. Anything outside this plus `DYNAMIC_TARGET_PREFIXES` is a
## target that would silently no-op against a `RunState` that never had it.
func _known_run_state_paths() -> Dictionary:
	var state := RunState.new()
	var sections: Dictionary = state.to_dict()
	var paths: Dictionary = {}
	for section in sections.keys():
		var value: Variant = sections[section]
		if value is Dictionary:
			for key in value.keys():
				paths["%s.%s" % [section, key]] = true
	for derived in EffectResolver.DERIVED_PATHS:
		paths[derived] = true
	return paths


func _validate_effect_list(errors: Array[String], known_paths: Dictionary, context: String, effects: Array) -> void:
	for effect in effects:
		if not effect is Dictionary:
			continue
		_validate_effect(
			errors, known_paths, context, str(effect.get("operation", "add")), str(effect.get("target", ""))
		)
		_validate_effect_list(errors, known_paths, context, Array(effect.get("effects", [])))


## Every `$parameter` referenced by a module's effects or description has to
## exist on the module. A missing key silently resolves to null at the table.
## Runtime context keys (`$heat_ratio`, `$is_first_stage`, …) are exempt.
const KNOWN_CONTEXT_PARAMETER_KEYS := [
	"is_first_stage", "is_last_stage", "stage_count", "slot_count", "slot_index",
	"stage_position", "stage_index", "heat_ratio", "start_heat_ratio", "stage_roll",
	"instability", "overflow", "prev_module", "next_module", "prev_op", "next_op",
	"op_id", "op_category", "module_id", "module_category", "stage_created_bugs",
	"stage_known_bugs_created", "stage_hidden_bugs_created", "stage_revealed",
	"stage_fixed", "stage_caught", "one_shot", "clean", "cool", "overkill_ratio",
	"bugs_created", "workflow_id", "workflow_name", "batch_faulted", "batch_survived",
]


func _validate_module_parameters(
	errors: Array[String],
	module: ModuleDefinition,
	effect_collections: Array
) -> void:
	var referenced: Dictionary = {}
	_collect_parameter_refs(referenced, module.description_template)
	for collection in effect_collections:
		_collect_effect_parameter_refs(referenced, Array(collection))
	for combo in module.combos:
		if not combo is Dictionary:
			continue
		_collect_parameter_refs(referenced, str(combo.get("description", "")))
		_collect_effect_parameter_refs(referenced, Array(combo.get("effects", [])))
	for key in referenced.keys():
		if KNOWN_CONTEXT_PARAMETER_KEYS.has(key):
			continue
		if key.begins_with("stage_") or key.begins_with("batch_") or key.begins_with("job_"):
			continue
		if not module.parameters.has(key):
			errors.append("module '%s' references missing parameter '$%s'" % [module.id, key])


func _collect_effect_parameter_refs(out: Dictionary, effects: Array) -> void:
	for effect in effects:
		if not effect is Dictionary:
			continue
		_collect_parameter_refs(out, str(effect.get("value", "")))
		_collect_parameter_refs(out, str(effect.get("from", "")))
		_collect_parameter_refs(out, str(effect.get("to", "")))
		_collect_parameter_refs(out, str(effect.get("ratio", "")))
		for condition in Array(effect.get("conditions", [])):
			if not condition is Dictionary:
				continue
			_collect_parameter_refs(out, str(condition.get("left", "")))
			_collect_parameter_refs(out, str(condition.get("right", "")))
		_collect_effect_parameter_refs(out, Array(effect.get("effects", [])))
		var pick: Variant = effect.get("pick", null)
		if pick is Array:
			for entry in pick:
				_collect_parameter_refs(out, str(entry))


func _collect_parameter_refs(out: Dictionary, text: Variant) -> void:
	var source: String = str(text)
	if source == "" or not source.contains("$"):
		return
	var i: int = 0
	while i < source.length():
		if source[i] != "$":
			i += 1
			continue
		var start: int = i + 1
		var end: int = start
		while end < source.length():
			var ch: String = source[end]
			var code: int = ch.unicode_at(0)
			var is_alnum: bool = (
				(code >= 48 and code <= 57)
				or (code >= 65 and code <= 90)
				or (code >= 97 and code <= 122)
				or ch == "_"
			)
			if not is_alnum:
				break
			end += 1
		if end > start:
			out[source.substr(start, end - start)] = true
		i = maxi(end, start + 1)


func _validate_effect(errors: Array[String], known_paths: Dictionary, context: String, operation: String, target: String) -> void:
	if not KNOWN_EFFECT_OPERATIONS.has(operation.to_lower()):
		errors.append("%s has unknown effect operation '%s'" % [context, operation])
	if target == "" or operation.to_lower() == "convert":
		return
	if target.begins_with("mastery.") and not KNOWN_MASTERY_TARGETS.has(target):
		errors.append("%s targets unknown mastery field '%s'" % [context, target])
		return
	for prefix in DYNAMIC_TARGET_PREFIXES:
		if target.begins_with(prefix):
			return
	if not known_paths.has(target):
		errors.append("%s targets unknown path '%s'" % [context, target])


func _check_unique_id(errors: Array[String], seen_ids: Dictionary, kind: String, id: String) -> void:
	var key: String = "%s:%s" % [kind, id]
	if seen_ids.has(key):
		errors.append("duplicate %s id '%s'" % [kind, id])
	seen_ids[key] = true


## The draft gates a perk or module can author. All three fail silently at the
## table if they are wrong — an unknown difficulty or an out-of-range tier just
## means the card never appears, which reads as missing content rather than a
## typo, so they are caught here instead.
func _check_draft_gates(
	errors: Array[String],
	kind: String,
	id: String,
	difficulty: PackedStringArray,
	min_tier: int,
	max_tier: int
) -> void:
	if difficulty.is_empty():
		errors.append("%s '%s' lists no difficulties, so it can never be drafted" % [kind, id])
	var known_difficulties: Dictionary = balance.get("difficulty_profiles", {})
	for entry in difficulty:
		if not known_difficulties.has(str(entry)):
			errors.append("%s '%s' allows unknown difficulty '%s'" % [kind, id, str(entry)])
	var top_tier: int = maxi(0, MetaProgress.location_order().size() - 1)
	if min_tier < 0:
		errors.append("%s '%s' has negative min_location_tier %d" % [kind, id, min_tier])
	if min_tier > top_tier:
		errors.append("%s '%s' needs location tier %d, above the campaign's top tier %d" % [
			kind, id, min_tier, top_tier,
		])
	if max_tier >= 0:
		if max_tier > top_tier:
			errors.append("%s '%s' caps at location tier %d, above the campaign's top tier %d" % [
				kind, id, max_tier, top_tier,
			])
		if max_tier < min_tier:
			errors.append("%s '%s' has max_location_tier %d below min_location_tier %d" % [
				kind, id, max_tier, min_tier,
			])


## Every campaign location the player can actually reach must have exactly
## one contract to play it for; a location with none is unplayable, and one
## with two makes ascension evaluate against whichever loaded last.
func _validate_ascension_contracts(errors: Array[String]) -> void:
	var counts: Dictionary = {}
	for contract in ascension_contracts:
		if bool(contract.get("alternate", false)):
			continue
		var location_id: String = str(contract.get("location", ""))
		if location_id == "":
			errors.append("ascension contract '%s' has no location" % str(contract.get("id", "")))
			continue
		counts[location_id] = int(counts.get(location_id, 0)) + 1
	for location_id in counts.keys():
		if int(counts[location_id]) > 1:
			errors.append("location '%s' has %d non-alternate ascension contracts, expected 1" % [
				location_id, counts[location_id],
			])
	var dwelling_costs: Dictionary = balance.get("dwelling_costs", {})
	for location_id in dwelling_costs.keys():
		if int(counts.get(location_id, 0)) == 0:
			errors.append("campaign location '%s' has no ascension contract" % location_id)


func _load_ascension_contracts() -> void:
	var data: Dictionary = _load_json_dict("res://content/ascension/contracts.json")
	for entry in Array(data.get("contracts", [])):
		if not entry is Dictionary:
			continue
		ascension_contracts.append(entry)
		_ascension_contracts_by_id[str(entry.get("id", ""))] = entry


## Content is authored, not generated: a malformed file is a mistake that
## should fail a dev build loudly, with the file and line to go fix, rather
## than silently falling back to an empty list that only shows up later as
## missing jobs or a broken draft.
func _parse_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("ContentDatabase: missing %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ContentDatabase: could not open %s" % path)
		return null
	var text: String = file.get_as_text()
	file.close()
	var parser := JSON.new()
	var err: Error = parser.parse(text)
	if err != OK:
		push_error("ContentDatabase: failed to parse %s at line %d: %s" % [
			path, parser.get_error_line(), parser.get_error_message()
		])
		return null
	return parser.get_data()


func _load_json_array(path: String) -> Array:
	var parsed: Variant = _parse_json_file(path)
	return parsed if parsed is Array else []


func _load_json_dict(path: String) -> Dictionary:
	var parsed: Variant = _parse_json_file(path)
	return parsed if parsed is Dictionary else {}
