extends TestCase

const VALID_EVENTS := [
	"prompt.started",
	"quality.calculated",
	"reward.calculated",
	"compute.recalculate",
	"heat.threshold_crossed",
	"round.started",
	"perk.acquired",
	"board.batch_started",
	"board.stage_resolved",
	"board.batch_finalizing",
	"board.batch_finished",
]

## Contributions the Burn Board knows how to fold. A module writing anywhere
## else silently does nothing, which is the worst kind of content bug.
const VALID_STAGE_TARGETS := [
	"stage.progress_mult",
	"stage.token_mult",
	"stage.quality",
	"stage.bugs",
	"stage.hidden_bugs",
	"stage.heat",
	"stage.cost",
	"stage.reveal_bugs",
	"stage.fix_bugs",
	"stage.hide_bugs",
	"stage.quality_to_progress",
	"stage.repeat_previous",
	"stage.repeat_strength",
	"stage.repeat_count",
	"stage.next_multiplier",
	"stage.next_cost_mult",
	"stage.fix_hidden_bugs",
]


## A declared combo is a promise printed in the pipeline editor, so its partners
## have to exist and its text has to render with the module's own numbers.
func _validate_combos(module: ModuleDefinition, evaluator: ExpressionEvaluator) -> void:
	for combo in module.combos:
		assert_true(str(combo.get("name", "")) != "", "Combo on %s is named" % module.id)
		var partners: Array = Array(combo.get("after", [])) + Array(combo.get("before", []))
		assert_true(partners.size() > 0, "Combo '%s' names something to pair with" % str(combo.get("name", "")))
		for partner_id in partners:
			assert_true(
				ContentDatabase.get_module(str(partner_id)) != null,
				"Combo on %s pairs with a real module, not '%s'" % [module.id, str(partner_id)]
			)
		var text: String = evaluator.render_template(str(combo.get("description", "")), module.parameters)
		assert_false(text.contains("{"), "Combo '%s' resolves every parameter" % str(combo.get("name", "")))
		# The combo is what the editor advertises, so it has to be what the
		# board actually resolves. An advertised pairing with no effects is a
		# tooltip promising something nothing implements.
		var effects: Array = Array(combo.get("effects", []))
		assert_true(
			effects.size() > 0,
			"Combo '%s' on %s carries the effects it advertises" % [str(combo.get("name", "")), module.id]
		)
		for effect in effects:
			var target: String = str(effect.get("target", ""))
			assert_true(
				target in VALID_STAGE_TARGETS,
				"Combo '%s' targets a real stage field, not '%s'" % [str(combo.get("name", "")), target]
			)

	# Adjacency belongs to the combos, so a slot effect testing its neighbours
	# is a second source of truth for the same pairing.
	for effect in module.slot_effects:
		for condition in Array(effect.get("conditions", [])):
			var left: String = str(condition.get("left", ""))
			assert_false(
				left in ["$prev_op", "$next_op", "$prev_module", "$next_module"],
				"%s declares adjacency in its combos rather than in slot_effects" % module.id
			)


## Percentages are printed exactly as authored, so a display parameter has to
## already be a whole percent. A `convert_pct` of 0.45 renders as "0.45%" beside
## a mechanic doing 45%, which is the card lying about the build.
func _validate_percent_parameters(source_id: String, parameters: Dictionary) -> void:
	for key in parameters.keys():
		var name: String = str(key)
		if not (name.ends_with("_pct") or name.ends_with("_percent")):
			continue
		var value: Variant = parameters[key]
		if not (value is int or value is float):
			continue
		var percent: float = float(value)
		assert_false(
			percent > 0.0 and percent < 1.0,
			"%s writes %s as a whole percent, not the ratio %s" % [source_id, name, str(percent)]
		)
		assert_true(
			percent >= 0.0 and percent <= 200.0,
			"%s keeps %s in a range a card can print: %s" % [source_id, name, str(percent)]
		)


## Cooling a machine should cost less than a couple of the machine. Above this
## the Cooling shelf exists on paper but nobody can afford to use it, which is
## the same cliff as having no cooling on sale at all.
const COOLING_BUDGET_RATIO := 2.0


## Every machine on the ladder has to be coolable at the space it needs, out of
## cooling that is actually on sale there and at a price the machine justifies.
## Without this the ladder can grow a rung whose heat nothing on the shelf can
## answer — the rig cooks, and COOL is net-positive with no way to fix it.
func _validate_every_machine_can_be_cooled() -> void:
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	var gain_factor: float = float(heat_cfg.get("gain_per_power", 0.025))
	var cooling_factor: float = float(heat_cfg.get("cooling_factor", 0.35))
	var curves: Dictionary = ContentDatabase.balance.get("hardware_curves", {})
	var starting_draw: float = float(Dictionary(curves.get("used_laptop", {})).get("power_draw", 0.0))

	for upgrade in ContentDatabase.upgrades:
		if upgrade.category != "hardware" or upgrade.hardware_key == "":
			continue
		var power: float = float(Dictionary(curves.get(upgrade.hardware_key, {})).get("power_draw", 0.0))
		if power <= 0.0:
			continue
		var dwelling: String = upgrade.requires_dwelling if upgrade.requires_dwelling != "" else "bedroom"
		var have: float = _location_cooling(dwelling) + _cooling_of(upgrade)
		var needed: float = (power + starting_draw) * gain_factor / cooling_factor
		var shortfall: float = needed - have
		if shortfall <= 0.0:
			continue

		var tier: int = UpgradeSystem.dwelling_tier(dwelling, ContentDatabase)
		var repeatable_cooler: bool = false
		var cheapest: float = -1.0
		var cheapest_name: String = ""
		for cooler in ContentDatabase.upgrades:
			if not ("cooling" in Array(cooler.tags)):
				continue
			if UpgradeSystem.dwelling_tier(cooler.requires_dwelling, ContentDatabase) > tier:
				continue
			var per_unit: float = _cooling_of(cooler)
			if per_unit <= 0.0:
				continue
			if cooler.repeatable:
				repeatable_cooler = true
			elif per_unit < shortfall:
				continue
			var total: float = _cost_of_units(cooler, int(ceil(shortfall / per_unit)))
			if cheapest < 0.0 or total < cheapest:
				cheapest = total
				cheapest_name = cooler.name
		assert_true(
			repeatable_cooler,
			"Some cooling on sale in the %s can be bought again and again, so %s never hits a shelf that is out of stock" % [
				dwelling, upgrade.name,
			]
		)
		assert_true(cheapest >= 0.0, "Something on the Cooling shelf can cool a %s" % upgrade.name)
		assert_true(
			cheapest <= upgrade.cost * COOLING_BUDGET_RATIO,
			"Cooling a %s (%s, %s) costs less than %.1f× the machine (%s)" % [
				upgrade.name,
				cheapest_name,
				NumberFormat.format_cash(maxf(0.0, cheapest)),
				COOLING_BUDGET_RATIO,
				NumberFormat.format_cash(upgrade.cost),
			]
		)


## Validation is only useful if it stays quiet on the content the game
## actually ships — a check that also flags real content is one nobody can
## leave switched on.
func _test_shipped_content_passes_validation() -> void:
	var errors: Array[String] = ContentDatabase.collect_validation_errors()
	assert_true(errors.is_empty(), "Shipped content passes validation: %s" % str(errors))


## Corrupts the loaded catalogue in memory just long enough to prove the
## compiler-style checks actually catch the mistakes they claim to, then
## reloads real content so every later suite still sees the shipped game.
func _test_validation_catches_synthetic_bad_content() -> void:
	var bad_upgrade := UpgradeDefinition.new()
	bad_upgrade.id = ContentDatabase.upgrades[0].id if not ContentDatabase.upgrades.is_empty() else "upgrade.duplicate_probe"
	bad_upgrade.category = "not_a_real_category"
	bad_upgrade.cost = -50.0
	bad_upgrade.repeatable = true
	bad_upgrade.cost_growth = 0.0
	bad_upgrade.max_level = -1
	var bad_effect := EffectDefinition.new()
	bad_effect.operation = "explode"
	bad_effect.target = "economy.does_not_exist"
	bad_upgrade.effects = [bad_effect]
	ContentDatabase.upgrades.append(bad_upgrade)

	var errors: Array[String] = ContentDatabase.collect_validation_errors()
	ContentDatabase.upgrades.pop_back()

	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("duplicate upgrade id")),
		"Validation catches a duplicate upgrade id"
	)
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("unknown category")),
		"Validation catches an unknown upgrade category"
	)
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("negative cost")),
		"Validation catches a negative cost"
	)
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("non-positive cost_growth")),
		"Validation catches a repeatable upgrade with no cost growth"
	)
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("negative max_level")),
		"Validation catches a negative max_level"
	)
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("unknown effect operation 'explode'")),
		"Validation catches an unknown effect operation"
	)
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("unknown path 'economy.does_not_exist'")),
		"Validation catches an effect targeting a path RunState doesn't have"
	)

	var clean_errors: Array[String] = ContentDatabase.collect_validation_errors()
	assert_true(clean_errors.is_empty(), "Removing the synthetic upgrade restores a clean validation pass")


## A board rule BoardSystem does not recognise is ignored at the table, and a
## demand naming a capability nothing reports can never be met — both read to
## the player as a contract behaving differently to the card it is printed on,
## so both have to fail at load rather than in a run.
func _test_validation_catches_unknown_rules_and_capabilities() -> void:
	var job: JobDefinition = ContentDatabase.jobs[0]
	var original_rules: Array = job.board_rules.duplicate(true)
	job.board_rules.append({"type": "not_a_real_rule", "label": "Nonsense"})

	var demands: Dictionary = ContentDatabase.balance.get("job_demands", {})
	demands["demand.synthetic_probe"] = {
		"name": "Probe",
		"requirement": "Something impossible",
		"unmet_note": "Nothing can answer this.",
		"match": {"capability": "not_a_real_capability"},
	}

	var errors: Array[String] = ContentDatabase.collect_validation_errors()
	job.board_rules = original_rules
	demands.erase("demand.synthetic_probe")

	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("unknown board rule type 'not_a_real_rule'")),
		"Validation catches a board rule BoardSystem would ignore"
	)
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("unknown capability 'not_a_real_capability'")),
		"Validation catches a demand no workflow could ever satisfy"
	)
	assert_true(
		ContentDatabase.collect_validation_errors().is_empty(),
		"Removing the synthetic content restores a clean validation pass"
	)


## Module slot effects used to skip the operation-name check that perks get, so
## a typo like `multipyl` shipped as a silent no-op.
func _test_validation_catches_unknown_module_operation() -> void:
	var bad := ModuleDefinition.new()
	bad.id = "op.synthetic_multipyl"
	bad.difficulty = PackedStringArray(["normal", "hard"])
	bad.slot_effects = [{"operation": "multipyl", "target": "stage.quality", "value": 1}]
	ContentDatabase.modules.append(bad)
	var errors: Array[String] = ContentDatabase.collect_validation_errors()
	ContentDatabase.modules.pop_back()
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("unknown effect operation 'multipyl'")),
		"Validation catches an unknown module operation"
	)
	assert_true(
		ContentDatabase.collect_validation_errors().is_empty(),
		"Removing the synthetic module restores a clean validation pass"
	)


## A typo'd operation must not silently no-op when it is actually resolved,
## matching the load-time check above with the runtime path it guards.
func _test_effect_resolver_errors_on_unknown_operation() -> void:
	var state := RunState.new()
	var resolver := EffectResolver.new()
	resolver.apply_effects(state, [{"operation": "not_a_real_op", "target": "economy.cash", "value": 5.0}])
	assert_eq(
		float(state.economy.get("cash", -1.0)), float(RunState.new().economy.get("cash", 0.0)),
		"An unknown operation leaves the target untouched rather than silently applying"
	)


## A run happens in one location and gets that location's cooling, once. Nothing
## from the chapters below it carries over, because it was never bought.
func _location_cooling(key: String) -> float:
	var dwellings: Dictionary = ContentDatabase.balance.get("dwelling_costs", {})
	return float(Dictionary(dwellings.get(key, {})).get("cooling_capacity", 0.0))


func _cooling_of(upgrade: UpgradeDefinition) -> float:
	var total: float = 0.0
	for effect in upgrade.effects:
		if effect is EffectDefinition and effect.target == "compute.cooling":
			total += float(effect.value)
	return total


## What buying `units` of a repeatable upgrade costs in total, growth included.
func _cost_of_units(upgrade: UpgradeDefinition, units: int) -> float:
	var total: float = 0.0
	for level in range(maxi(1, units)):
		total += UpgradeSystem.purchase_cost(upgrade, level if upgrade.repeatable else 0)
		if not upgrade.repeatable:
			break
	return total


## Ascension Contracts are the only exit from a run, so a location without one is
## an unfinishable chapter rather than a missing bonus.
func _validate_ascension_contracts() -> void:
	var contracts: Array = ContentDatabase.ascension_contracts
	assert_true(contracts.size() > 0, "Content loads the contract pool")
	var bosses: Dictionary = {}
	for contract in contracts:
		var id: String = str(contract.get("id", ""))
		assert_true(id.begins_with("ascension."), "Contract id is namespaced: %s" % id)
		assert_true(str(contract.get("name", "")) != "", "Contract %s is named" % id)
		assert_true(float(contract.get("total_burn", 0.0)) > 0.0, "Contract %s asks for a burn" % id)
		assert_true(int(contract.get("deadline_rounds", 0)) > 0, "Contract %s has a deadline" % id)
		assert_true(int(contract.get("picks", 0)) > 0, "Contract %s pays out at least one pick" % id)
		if bool(contract.get("alternate", false)):
			continue
		var location: String = str(contract.get("location", ""))
		assert_true(location != "", "Primary contract %s names the location it is played for" % id)
		assert_false(bosses.has(location), "%s has exactly one contract" % location)
		bosses[location] = id
	for location in MetaProgress.location_order():
		assert_true(bosses.has(str(location)), "%s has a way out of it" % str(location))


## The shell mounts itself onto the room art: the work column, the side panel,
## the readouts on the wall and the laptop console are all placed from rects
## authored beside each location's picture. A location that ships without them,
## or with a laptop that falls outside the column the console is mounted in,
## lands the player in a room where the UI does not line up with the furniture.
func _validate_room_art() -> void:
	var props: Array[String] = ["plan_board", "heat_readout", "power_meter", "phone"]
	for raw_location in MetaProgress.location_order():
		var location: String = str(raw_location)
		assert_true(
			AssetCatalog.board_scene_art(location) != null,
			"%s has a room painted for it" % location
		)
		var column: Rect2 = AssetCatalog.board_region(location, "work_column")
		assert_true(column.size.x > 0.0, "%s places its work column" % location)
		assert_true(
			AssetCatalog.board_region(location, "side_panel").size.x > 0.0,
			"%s places its side panel" % location
		)
		for key in props:
			var rect: Rect2 = AssetCatalog.board_prop(location, key)
			assert_true(rect.size.x > 0.0, "%s carries a %s" % [location, key])
			assert_true(
				rect.position.x >= 0.0 and rect.position.y >= 0.0
					and rect.end.x <= 1.0 and rect.end.y <= 1.0,
				"%s keeps its %s inside the picture" % [location, key]
			)
		var laptop: Rect2 = AssetCatalog.board_laptop_screen(location)
		assert_true(laptop.size.x > 0.0, "%s stands a laptop on the desk" % location)
		assert_true(
			column.encloses(laptop),
			"%s keeps its laptop inside the work column the console mounts in" % location
		)
		# The laptop drives the whole game, so a room that paints it small enough
		# to be scenery would leave the player squinting at the only screen they
		# can act on. A quarter of the frame is roughly the size the art was
		# recomposed to.
		assert_true(
			laptop.size.x * laptop.size.y >= 0.14,
			"%s paints its laptop large enough to run the game from" % location
		)


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	assert_true(ContentDatabase.jobs.size() > 0, "Content loads jobs after reload")
	_validate_every_machine_can_be_cooled()
	_validate_ascension_contracts()
	_validate_room_art()
	_test_shipped_content_passes_validation()
	_test_validation_catches_synthetic_bad_content()
	_test_validation_catches_unknown_rules_and_capabilities()
	_test_validation_catches_unknown_module_operation()
	_test_effect_resolver_errors_on_unknown_operation()

	for upgrade in ContentDatabase.upgrades:
		if upgrade.category == "hardware" and upgrade.hardware_key != "":
			var curves: Dictionary = ContentDatabase.balance.get("hardware_curves", {})
			assert_true(curves.has(upgrade.hardware_key), "Hardware key '%s' resolves for %s" % [upgrade.hardware_key, upgrade.id])
		if upgrade.category == "dwelling" and upgrade.dwelling_key != "":
			var dwellings: Dictionary = ContentDatabase.balance.get("dwelling_costs", {})
			assert_true(dwellings.has(upgrade.dwelling_key), "Dwelling key '%s' resolves for %s" % [upgrade.dwelling_key, upgrade.id])

	for event_name in ContentDatabase.get_all_subscription_events():
		assert_true(event_name in VALID_EVENTS, "Unknown subscription event: %s" % event_name)

	assert_true(ContentDatabase.modules.size() >= 8, "Burn Board ships a starting set of modules")
	assert_true(ContentDatabase.starter_modules().size() >= 2, "A new run owns enough modules to fill a pipeline")
	var evaluator := ExpressionEvaluator.new()
	for module in ContentDatabase.modules:
		assert_true(module.id.begins_with("op."), "Module id is namespaced: %s" % module.id)
		assert_true(module.slot_effects.size() > 0, "Module %s does something" % module.id)
		for effect in module.slot_effects:
			var target: String = str(effect.get("target", ""))
			assert_true(target in VALID_STAGE_TARGETS, "Module %s targets a real stage field, not '%s'" % [module.id, target])
		var rendered: String = evaluator.render_template(module.description_template, module.parameters)
		assert_false(rendered.contains("{"), "Module %s description resolves every parameter" % module.id)
		_validate_percent_parameters(module.id, module.parameters)
		_validate_combos(module, evaluator)

	for perk in ContentDatabase.perks:
		_validate_percent_parameters(perk.id, perk.parameters)
		var perk_text: String = evaluator.render_template(perk.description_template, perk.parameters)
		assert_false(perk_text.contains("{"), "Perk %s description resolves every parameter" % perk.id)

	assert_true(ContentDatabase.achievements.size() > 0, "Content loads the achievement catalogue")
	# The draft pool has to reward a long game as well as a first run, so every
	# rarity band needs somebody in it.
	var rarities: Dictionary = {}
	for module in ContentDatabase.modules:
		rarities[module.rarity] = int(rarities.get(module.rarity, 0)) + 1
	for rarity in ["common", "uncommon", "rare", "legendary"]:
		assert_true(int(rarities.get(rarity, 0)) > 0, "The module pool has %s entries" % rarity)
		assert_true(
			ContentDatabase.rarity_weights.has(rarity),
			"Rarity '%s' has a draft weight" % rarity
		)

	for job in ContentDatabase.jobs:
		for rule in job.board_rules:
			var rule_type: String = str(rule.get("type", ""))
			assert_true(rule_type in [
				BoardSystem.RULE_BLOCKED_SLOTS,
				BoardSystem.RULE_TAG_BONUS,
				BoardSystem.RULE_MAX_HIDDEN_BUGS,
				BoardSystem.RULE_RECURSION_RISK,
				BoardSystem.RULE_AGENT_SCOPE,
				BoardSystem.RULE_FEATURE_CREEP,
			], "Job %s uses a known board rule, not '%s'" % [job.id, rule_type])
			assert_true(str(rule.get("label", "")) != "", "Board rule on %s explains itself to the player" % job.id)
		for demand_id in job.demands:
			assert_true(
				ContentDatabase.balance.get("job_demands", {}).has(str(demand_id)),
				"Job %s asks for a demand that exists, not '%s'" % [job.id, str(demand_id)]
			)

	# A demand nothing can answer is a permanent penalty rather than a decision,
	# so every archetype has to be satisfiable by something in the module pool.
	var board := BoardSystem.new()
	for demand_id in ContentDatabase.balance.get("job_demands", {}).keys():
		var definition: Dictionary = ContentDatabase.balance["job_demands"][demand_id]
		var match_spec: Dictionary = Dictionary(definition.get("match", {}))
		assert_true(str(definition.get("requirement", "")) != "", "Demand %s says what it wants" % demand_id)
		assert_true(str(definition.get("unmet_note", "")) != "", "Demand %s says what ignoring it costs" % demand_id)
		if not match_spec.has("capability"):
			continue
		var answered: bool = false
		for module in ContentDatabase.modules:
			if bool(board.pipeline_capabilities([module.id]).get(str(match_spec["capability"]), false)):
				answered = true
				break
		assert_true(answered, "Some module can answer demand %s" % demand_id)
