extends Node

## Loads and validates JSON content into definition Resources.

var jobs: Array[JobDefinition] = []
var perks: Array[PerkDefinition] = []
var upgrades: Array[UpgradeDefinition] = []
var events: Array[EventDefinition] = []
var modules: Array[ModuleDefinition] = []
var balance: Dictionary = {}
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


## The achievement that has to be earned before a module can appear in a draft,
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


## An achievement-gated module is not in the pool until its award has been
## earned, which is the whole point of earning it: the draft itself gets deeper
## rather than the player getting a one-off handout.
func module_is_unlocked(module: ModuleDefinition) -> bool:
	if module.unlock_achievement == "":
		return true
	return MetaProgress.has_achievement(module.unlock_achievement)


func unlocked_modules() -> Array[ModuleDefinition]:
	var result: Array[ModuleDefinition] = []
	for module in modules:
		if module_is_unlocked(module):
			result.append(module)
	return result


func perk_is_unlocked(perk: PerkDefinition) -> bool:
	if perk.unlock_achievement == "":
		return true
	return MetaProgress.has_achievement(perk.unlock_achievement)


func draw_angel_offers(
	rng: DeterministicRng,
	run_state: RunState,
	count: int = 3,
	owned_tags: Array = [],
	rarity_bias: float = 0.0
) -> Array:
	var pool: Array = []
	var collected: Array = run_state.build.get("perk_inventory", [])
	var owned_modules: Array = run_state.build.get("modules", [])
	var tier: int = _location_tier_for_run(run_state)
	var affinity: float = float(_build_tuning().get("draft_tag_affinity", 1.5))
	var affinity_cap: float = float(_build_tuning().get("draft_tag_affinity_cap", 4.0))
	for perk in perks:
		if perk.id in collected:
			continue
		if not perk_is_unlocked(perk):
			continue
		if not _difficulty_allows_run(run_state, perk.difficulty):
			continue
		if not _location_tier_allows(tier, perk.min_location_tier, perk.max_location_tier):
			continue
		var weight: float = _rarity_weight(perk.rarity, rarity_bias) * maxf(perk.draft_weight, 0.01)
		var matches: int = 0
		for tag in perk.tags:
			if tag in owned_tags:
				matches += 1
		if matches > 0:
			weight *= minf(pow(affinity, float(matches)), affinity_cap)
		pool.append({
			"type": "perk",
			"id": perk.id,
			"label": perk.name,
			"rarity": perk.rarity,
			"tags": Array(perk.tags),
			"weight": weight,
		})
	for module in modules:
		if module.id in owned_modules:
			continue
		if not module_is_unlocked(module):
			continue
		if not _difficulty_allows_run(run_state, module.difficulty):
			continue
		if not _location_tier_allows(tier, module.min_location_tier, module.max_location_tier):
			continue
		var module_weight: float = _rarity_weight(module.rarity, rarity_bias) * maxf(module.draft_weight, 0.01)
		var module_matches: int = 0
		for tag in module.tags:
			if tag in owned_tags:
				module_matches += 1
		if module_matches > 0:
			module_weight *= minf(pow(affinity, float(module_matches)), affinity_cap)
		pool.append({
			"type": "module",
			"id": module.id,
			"label": module.name,
			"rarity": module.rarity,
			"tags": Array(module.tags),
			"weight": module_weight,
		})
	if pool.is_empty():
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


func _location_tier_for_run(run_state: RunState) -> int:
	var order: Array = MetaProgress.location_order()
	if order.is_empty():
		order = Array(balance.get("economy", {}).get("location_order", []))
	var dwelling: String = str(run_state.build.get("dwelling", "bedroom"))
	var index: int = order.find(dwelling)
	return maxi(0, index)


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


func draw_modules(
	rng: DeterministicRng,
	count: int = 2,
	owned_ids: Array = [],
	rarity_bias: float = 0.0
) -> Array[ModuleDefinition]:
	var pool: Array = []
	for module in modules:
		if module.id in owned_ids:
			continue
		if not module_is_unlocked(module):
			continue
		pool.append({"item": module, "weight": _rarity_weight(module.rarity, rarity_bias)})
	if pool.is_empty():
		return []
	var picks: Array[ModuleDefinition] = []
	var mutable_pool: Array = pool.duplicate()
	for _i in range(count):
		if mutable_pool.is_empty():
			break
		var picked = rng.weighted_pick(mutable_pool, "weight")
		if picked == null:
			break
		picks.append(picked["item"])
		mutable_pool.erase(picked)
	return picks


## The angel's offer. `owned_tags` bends the draw towards whatever the build has
## already committed to, so a run that has bought into local hardware keeps being
## shown local hardware rather than three unrelated cards a round. `blocked_ids`
## are perks the build could not take even if offered — a dead card on the table
## is a wasted pick, so they never appear.
func draw_perks(
	rng: DeterministicRng,
	count: int = 3,
	owned_ids: Array = [],
	rarity_bias: float = 0.0,
	owned_tags: Array = [],
	blocked_ids: Array = []
) -> Array[PerkDefinition]:
	var affinity: float = float(_build_tuning().get("draft_tag_affinity", 1.5))
	var affinity_cap: float = float(_build_tuning().get("draft_tag_affinity_cap", 4.0))
	var pool: Array = []
	for perk in perks:
		if perk.id in owned_ids or perk.id in blocked_ids:
			continue
		var weight: float = _rarity_weight(perk.rarity, rarity_bias)
		var matches: int = 0
		for tag in perk.tags:
			if tag in owned_tags:
				matches += 1
		if matches > 0:
			weight *= minf(pow(affinity, float(matches)), affinity_cap)
		pool.append({"item": perk, "weight": weight})
	if pool.is_empty():
		return []
	var picks: Array[PerkDefinition] = []
	var mutable_pool: Array = pool.duplicate()
	for _i in range(count):
		if mutable_pool.is_empty():
			break
		var picked = rng.weighted_pick(mutable_pool, "weight")
		if picked == null:
			break
		picks.append(picked["item"])
		mutable_pool.erase(picked)
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
		upgrade.dwelling_key = str(entry.get("dwelling_key", ""))
		upgrade.component_key = str(entry.get("component_key", ""))
		upgrade.requires_hardware = str(entry.get("requires_hardware", ""))
		upgrade.requires_dwelling = str(entry.get("requires_dwelling", ""))
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
		module.min_location_tier = int(entry.get("min_location_tier", 0))
		module.max_location_tier = int(entry.get("max_location_tier", -1))
		module.draft_weight = float(entry.get("draft_weight", 1.0))
		module.difficulty = PackedStringArray(Array(entry.get("difficulty", ["normal", "hard"])))
		module.combos = Array(entry.get("combos", []), TYPE_DICTIONARY, "", null)
		module.finalizing_effects = Array(entry.get("finalizing_effects", []), TYPE_DICTIONARY, "", null)
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
const KNOWN_UPGRADE_CATEGORIES := ["hardware", "component", "dwelling", "cloud", "advertising"]
## Prefixes an effect target may use without resolving against `RunState`:
## `job.`/`batch.`/`stage.` are per-resolution scratch values (see
## `ModifierContext` and `BoardSystem`'s per-stage batch dictionary),
## `build.`/`business.` accept new keys by design (`EffectResolver._finalize_to_run_state`).
const DYNAMIC_TARGET_PREFIXES := ["job.", "batch.", "stage.", "build.", "business."]


func _validate_content() -> void:
	for message in collect_validation_errors():
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
		if upgrade.category == "dwelling" and upgrade.dwelling_key != "":
			if not dwelling_costs.has(upgrade.dwelling_key):
				errors.append("upgrade '%s' references missing dwelling_key '%s'" % [upgrade.id, upgrade.dwelling_key])
		if upgrade.requires_dwelling != "" and not dwelling_costs.has(upgrade.requires_dwelling):
			errors.append("upgrade '%s' requires missing dwelling '%s'" % [upgrade.id, upgrade.requires_dwelling])
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
		_validate_effect_list(errors, known_paths, "module '%s'" % module.id, module.slot_effects)
		_validate_effect_list(
			errors, known_paths, "module '%s' finalizing" % module.id, module.finalizing_effects
		)
		for combo in module.combos:
			if combo is Dictionary:
				_validate_effect_list(
					errors, known_paths,
					"module '%s' combo" % module.id, Array(combo.get("effects", []))
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
	_validate_ascension_contracts(errors)
	return errors


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


func _validate_effect(errors: Array[String], known_paths: Dictionary, context: String, operation: String, target: String) -> void:
	if not KNOWN_EFFECT_OPERATIONS.has(operation.to_lower()):
		errors.append("%s has unknown effect operation '%s'" % [context, operation])
	if target == "" or operation.to_lower() == "convert":
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
