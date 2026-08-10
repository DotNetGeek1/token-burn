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
	"board.batch_finished",
]

## Contributions the Burn Board knows how to fold. An operation writing anywhere
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
	"stage.next_multiplier",
	"stage.next_cost_mult",
]


## A declared combo is a promise printed in the pipeline editor, so its partners
## have to exist and its text has to render with the module's own numbers.
func _validate_combos(operation: OperationDefinition, evaluator: ExpressionEvaluator) -> void:
	for combo in operation.combos:
		assert_true(str(combo.get("name", "")) != "", "Combo on %s is named" % operation.id)
		var partners: Array = Array(combo.get("after", [])) + Array(combo.get("before", []))
		assert_true(partners.size() > 0, "Combo '%s' names something to pair with" % str(combo.get("name", "")))
		for partner_id in partners:
			assert_true(
				ContentDatabase.get_operation(str(partner_id)) != null,
				"Combo on %s pairs with a real module, not '%s'" % [operation.id, str(partner_id)]
			)
		var text: String = evaluator.render_template(str(combo.get("description", "")), operation.parameters)
		assert_false(text.contains("{"), "Combo '%s' resolves every parameter" % str(combo.get("name", "")))


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


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	assert_true(ContentDatabase.jobs.size() > 0, "Content loads jobs after reload")
	_validate_every_machine_can_be_cooled()
	_validate_ascension_contracts()
	_test_shipped_content_passes_validation()
	_test_validation_catches_synthetic_bad_content()
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

	assert_true(ContentDatabase.operations.size() >= 8, "Burn Board ships a starting set of operations")
	assert_true(ContentDatabase.starter_operations().size() >= 2, "A new run owns enough modules to fill a pipeline")
	var evaluator := ExpressionEvaluator.new()
	for operation in ContentDatabase.operations:
		assert_true(operation.id.begins_with("op."), "Operation id is namespaced: %s" % operation.id)
		assert_true(operation.slot_effects.size() > 0, "Operation %s does something" % operation.id)
		for effect in operation.slot_effects:
			var target: String = str(effect.get("target", ""))
			assert_true(target in VALID_STAGE_TARGETS, "Operation %s targets a real stage field, not '%s'" % [operation.id, target])
		var rendered: String = evaluator.render_template(operation.description_template, operation.parameters)
		assert_false(rendered.contains("{"), "Operation %s description resolves every parameter" % operation.id)
		_validate_combos(operation, evaluator)

	assert_true(ContentDatabase.achievements.size() > 0, "Content loads the achievement catalogue")
	# The draft pool has to reward a long game as well as a first run, so every
	# rarity band needs somebody in it.
	var rarities: Dictionary = {}
	for operation in ContentDatabase.operations:
		rarities[operation.rarity] = int(rarities.get(operation.rarity, 0)) + 1
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
		for operation in ContentDatabase.operations:
			if bool(board.pipeline_capabilities([operation.id]).get(str(match_spec["capability"]), false)):
				answered = true
				break
		assert_true(answered, "Some module can answer demand %s" % demand_id)
