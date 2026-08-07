extends Node

## Loads and validates JSON content into definition Resources.

var jobs: Array[JobDefinition] = []
var perks: Array[PerkDefinition] = []
var upgrades: Array[UpgradeDefinition] = []
var events: Array[EventDefinition] = []
var operations: Array[OperationDefinition] = []
var balance: Dictionary = {}
var comparisons: Array = []
var rarity_weights: Dictionary = {}
var synergies: Array = []
## Angel investor personas. Pure flavour: they front the free offers.
var investors: Array = []
## Ascension Contracts and the qualification thresholds that unlock them.
var ascension_contracts: Array = []
var ascension_qualification: Dictionary = {}
var _ascension_contracts_by_id: Dictionary = {}
## Permanent awards. Plain dictionaries rather than Resources: nothing reads
## them in the hot path, and the gallery wants the raw copy verbatim.
var achievements: Array = []
var _achievements_by_id: Dictionary = {}

var _jobs_by_id: Dictionary = {}
var _perks_by_id: Dictionary = {}
var _upgrades_by_id: Dictionary = {}
var _events_by_id: Dictionary = {}
var _operations_by_id: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	jobs.clear()
	perks.clear()
	upgrades.clear()
	events.clear()
	operations.clear()
	synergies.clear()
	investors.clear()
	ascension_contracts.clear()
	ascension_qualification.clear()
	achievements.clear()
	_achievements_by_id.clear()
	_jobs_by_id.clear()
	_perks_by_id.clear()
	_upgrades_by_id.clear()
	_events_by_id.clear()
	_operations_by_id.clear()
	_ascension_contracts_by_id.clear()
	_load_jobs()
	_load_perks()
	_load_upgrades()
	_load_events()
	_load_operations()
	_load_investors()
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


func get_operation(id: String) -> OperationDefinition:
	return _operations_by_id.get(id, null)


func get_ascension_contract(id: String) -> Dictionary:
	return Dictionary(_ascension_contracts_by_id.get(id, {})).duplicate(true)


func get_achievement(id: String) -> Dictionary:
	return Dictionary(_achievements_by_id.get(id, {})).duplicate(true)


## The achievement that has to be earned before an operation can appear in a
## draft, or "" for the modules everybody starts with access to.
func operation_unlock_achievement(operation_id: String) -> String:
	var operation: OperationDefinition = get_operation(operation_id)
	return operation.unlock_achievement if operation != null else ""


func starter_operations() -> Array[String]:
	var ids: Array[String] = []
	for operation in operations:
		if operation.starter:
			ids.append(operation.id)
	return ids


## The modules a run begins with already placed. The rest of the starters wait
## on the bench, which is the first decision the board asks for.
func opening_pipeline_operations() -> Array[String]:
	var ids: Array[String] = []
	for operation in operations:
		if operation.starter and operation.opens_pipeline:
			ids.append(operation.id)
	return ids


## An achievement-gated module is not in the pool until its award has been
## earned, which is the whole point of earning it: the draft itself gets deeper
## rather than the player getting a one-off handout.
func operation_is_unlocked(operation: OperationDefinition) -> bool:
	if operation.unlock_achievement == "":
		return true
	return MetaProgress.has_achievement(operation.unlock_achievement)


func unlocked_operations() -> Array[OperationDefinition]:
	var result: Array[OperationDefinition] = []
	for operation in operations:
		if operation_is_unlocked(operation):
			result.append(operation)
	return result


func draw_operations(
	rng: DeterministicRng,
	count: int = 2,
	owned_ids: Array = [],
	rarity_bias: float = 0.0
) -> Array[OperationDefinition]:
	var pool: Array = []
	for operation in operations:
		if operation.id in owned_ids:
			continue
		if not operation_is_unlocked(operation):
			continue
		pool.append({"item": operation, "weight": _rarity_weight(operation.rarity, rarity_bias)})
	if pool.is_empty():
		return []
	var picks: Array[OperationDefinition] = []
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


func draw_perks(
	rng: DeterministicRng,
	count: int = 3,
	owned_ids: Array = [],
	rarity_bias: float = 0.0
) -> Array[PerkDefinition]:
	var pool: Array = []
	for perk in perks:
		if perk.id in owned_ids:
			continue
		pool.append({"item": perk, "weight": _rarity_weight(perk.rarity, rarity_bias)})
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
		job.reward = float(entry.get("reward", 0.0))
		job.token_requirement = float(entry.get("token_requirement", 0.0))
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
		event.trigger_event = str(entry.get("trigger_event", "round.ended"))
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


func _load_operations() -> void:
	var data: Array = _load_json_array("res://content/operations/operations.json")
	for entry in data:
		var operation := OperationDefinition.new()
		operation.id = str(entry.get("id", ""))
		operation.name = str(entry.get("name", ""))
		operation.category = str(entry.get("category", ""))
		operation.rarity = str(entry.get("rarity", "common"))
		operation.tags = PackedStringArray(Array(entry.get("tags", [])))
		operation.description_template = str(entry.get("description_template", ""))
		operation.badge = str(entry.get("badge", ""))
		operation.parameters = entry.get("parameters", {})
		operation.slot_effects = Array(entry.get("slot_effects", []), TYPE_DICTIONARY, "", null)
		operation.priority = int(entry.get("priority", 50))
		operation.starter = bool(entry.get("starter", false))
		operation.opens_pipeline = bool(entry.get("opens_pipeline", false))
		operation.unlock_achievement = str(entry.get("unlock_achievement", ""))
		operation.combos = Array(entry.get("combos", []), TYPE_DICTIONARY, "", null)
		operations.append(operation)
		_operations_by_id[operation.id] = operation


func _load_achievements() -> void:
	for entry in _load_json_array("res://content/achievements/achievements.json"):
		if not entry is Dictionary:
			continue
		achievements.append(entry)
		_achievements_by_id[str(entry.get("id", ""))] = entry


func _load_balance() -> void:
	balance["economy"] = _load_json_dict("res://content/balance/economy.json")
	balance["job_scaling"] = _load_json_dict("res://content/balance/job_scaling.json")
	balance["dwelling_costs"] = _load_json_dict("res://content/balance/dwelling_costs.json")
	balance["hardware_curves"] = _load_json_dict("res://content/balance/hardware_curves.json")
	balance["difficulty_profiles"] = _load_json_dict("res://content/balance/difficulty_profiles.json")
	balance["job_demands"] = _load_json_dict("res://content/balance/job_demands.json")
	rarity_weights = _load_json_dict("res://content/balance/rarity_weights.json")
	comparisons = _load_json_array("res://content/balance/comparisons.json")
	synergies = _load_json_array("res://content/balance/synergies.json")


func _validate_content() -> void:
	var hardware_curves: Dictionary = balance.get("hardware_curves", {})
	var dwelling_costs: Dictionary = balance.get("dwelling_costs", {})
	for upgrade in upgrades:
		if upgrade.category == "hardware" and upgrade.hardware_key != "":
			if not hardware_curves.has(upgrade.hardware_key):
				push_error("ContentDatabase: upgrade '%s' references missing hardware_key '%s'" % [upgrade.id, upgrade.hardware_key])
		if upgrade.category == "component":
			if not hardware_curves.has(upgrade.component_key):
				push_error("ContentDatabase: upgrade '%s' references missing component_key '%s'" % [upgrade.id, upgrade.component_key])
			if not hardware_curves.has(upgrade.requires_hardware):
				push_error("ContentDatabase: upgrade '%s' fits missing host hardware '%s'" % [upgrade.id, upgrade.requires_hardware])
		if upgrade.category == "dwelling" and upgrade.dwelling_key != "":
			if not dwelling_costs.has(upgrade.dwelling_key):
				push_error("ContentDatabase: upgrade '%s' references missing dwelling_key '%s'" % [upgrade.id, upgrade.dwelling_key])
		if upgrade.requires_dwelling != "" and not dwelling_costs.has(upgrade.requires_dwelling):
			push_error("ContentDatabase: upgrade '%s' requires missing dwelling '%s'" % [upgrade.id, upgrade.requires_dwelling])
		if upgrade.requires_upgrade != "" and not _upgrades_by_id.has(upgrade.requires_upgrade):
			push_error("ContentDatabase: upgrade '%s' requires missing upgrade '%s'" % [upgrade.id, upgrade.requires_upgrade])
	for operation in operations:
		if operation.unlock_achievement != "" and not _achievements_by_id.has(operation.unlock_achievement):
			push_error("ContentDatabase: operation '%s' is gated behind missing achievement '%s'" % [
				operation.id, operation.unlock_achievement,
			])
		for partner_id in operation.combo_partners():
			if not _operations_by_id.has(partner_id):
				push_error("ContentDatabase: operation '%s' declares a combo with missing module '%s'" % [
					operation.id, partner_id,
				])
	var demands: Dictionary = balance.get("job_demands", {})
	for job in jobs:
		for demand_id in job.demands:
			if not demands.has(str(demand_id)):
				push_error("ContentDatabase: job '%s' asks for missing demand '%s'" % [
					job.id, str(demand_id),
				])
	for achievement in achievements:
		var reward: Dictionary = Dictionary(achievement.get("reward", {}))
		if str(reward.get("type", "none")) != "unlock_module":
			continue
		var operation_id: String = str(reward.get("operation_id", ""))
		if not _operations_by_id.has(operation_id):
			push_error("ContentDatabase: achievement '%s' unlocks missing module '%s'" % [
				str(achievement.get("id", "")), operation_id,
			])


func _load_ascension_contracts() -> void:
	var data: Dictionary = _load_json_dict("res://content/ascension/contracts.json")
	ascension_qualification = Dictionary(data.get("qualification", {}))
	for entry in Array(data.get("contracts", [])):
		if not entry is Dictionary:
			continue
		ascension_contracts.append(entry)
		_ascension_contracts_by_id[str(entry.get("id", ""))] = entry


func _load_investors() -> void:
	for entry in _load_json_array("res://content/meta/investors.json"):
		if entry is Dictionary:
			investors.append(entry)


## One investor per offer, without repeats inside a round: the joke lands better
## when three different people are each certain they are helping.
func draw_investors(rng: DeterministicRng, count: int) -> Array:
	if investors.is_empty():
		return []
	var pool: Array = investors.duplicate()
	var picked: Array = []
	while picked.size() < count:
		if pool.is_empty():
			pool = investors.duplicate()
		var index: int = rng.next_int_range(0, pool.size() - 1)
		picked.append(pool[index].duplicate(true))
		pool.remove_at(index)
	return picked


func _load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("ContentDatabase: missing %s" % path)
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Array else []


func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("ContentDatabase: missing %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
