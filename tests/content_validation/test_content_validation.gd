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
	"board.cascade_triggered",
	"board.stage_folded",
	"workflow.mastery_evaluated",
]

## Contributions the Burn Board knows how to fold. A module writing anywhere
## else silently does nothing, which is the worst kind of content bug.
const VALID_STAGE_TARGETS := [
	"stage.progress_mult",
	"stage.token_mult",
	"stage.quality_mult",
	"stage.thermal_mult",
	"stage.next_block_hidden",
	"stage.next_hidden_on_bug",
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
	"stage.cascade_chance",
	"stage.cascade_strength",
]

const VALID_BATCH_TARGETS := [
	"batch.progress_mult",
	"batch.token_mult",
	"batch.quality_mult",
	"batch.thermal_mult",
	"batch.quality",
	"batch.heat",
	"batch.cost",
	"batch.known_bugs",
	"batch.hidden_bugs",
	"batch.revealed",
	"batch.fixed",
	"batch.bugs_created",
	"batch.hidden_bugs_created",
	"batch.total_bugs_created",
	"batch.quality_to_progress",
	"batch.progress_tokens",
	"batch.scope_tokens",
]

const VALID_MASTERY_TARGETS := [
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

## Completion effects may also write lasting run-state fields (Benchmark Harness
## discounts the next hardware buy via build.hardware_discount).
const VALID_BUILD_TARGETS := [
	"build.hardware_discount",
]

const EXPANSION_MODULE_IDS := [
	"op.system_prompt", "op.few_shot_examples", "op.repo_map", "op.vector_index",
	"op.context_pruner", "op.requirements_doc", "op.dependency_graph", "op.prompt_mutator",
	"op.constraint_solver", "op.memory_palace", "op.small_specialist", "op.moe_router",
	"op.draft_model", "op.judge_model", "op.self_consistency", "op.sparse_expert",
	"op.speculative_router", "op.verifier_model", "op.distilled_specialist", "op.world_model",
	"op.static_analysis", "op.integration_tests", "op.property_tests", "op.fuzz_tester",
	"op.mutation_testing", "op.golden_dataset", "op.canary_test", "op.formal_verification",
	"op.snapshot_tests", "op.root_cause_analysis", "op.kernel_fusion", "op.cuda_graph",
	"op.pinned_memory", "op.hbm_burst", "op.fan_wall", "op.heat_pipe", "op.phase_change",
	"op.thermal_throttle", "op.voltage_spike", "op.cold_boot", "op.planner_agent",
	"op.reviewer_agent", "op.parallel_workers", "op.watchdog_agent", "op.self_critique",
	"op.tree_search", "op.backtracking_agent", "op.autonomous_loop", "op.prefix_cache",
	"op.semantic_cache", "op.kv_cache", "op.canary_release", "op.blue_green",
	"op.rollback_plan", "op.friday_deploy", "op.singularity_cache",
	"op.thermodynamic_computer", "op.proof_carrying_code", "op.benchmark_daemon",
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


func _module_has_combo_effects(module: ModuleDefinition) -> bool:
	for combo in module.combos:
		if combo is Dictionary and Array(combo.get("effects", [])).size() > 0:
			return true
	return false


func _validate_module_effect_targets(module: ModuleDefinition) -> void:
	_validate_effect_target_list(module.id, "slot", module.slot_effects, true)
	_validate_effect_target_list(module.id, "folded", module.folded_effects, false)
	_validate_effect_target_list(module.id, "finalizing", module.finalizing_effects, false)
	_validate_effect_target_list(module.id, "completion", module.completion_effects, false)
	for combo in module.combos:
		if combo is Dictionary:
			_validate_effect_target_list(
				module.id, "combo", Array(combo.get("effects", [])), true
			)


func _validate_effect_target_list(
	module_id: String,
	kind: String,
	effects: Array,
	stage_only: bool
) -> void:
	for effect in effects:
		if not effect is Dictionary:
			continue
		var target: String = str(effect.get("target", ""))
		if target == "":
			continue
		var ok: bool = target in VALID_STAGE_TARGETS
		if not stage_only:
			ok = (
				ok
				or target in VALID_BATCH_TARGETS
				or target in VALID_MASTERY_TARGETS
				or target in VALID_BUILD_TARGETS
			)
		assert_true(
			ok,
			"Module %s %s targets a real field, not '%s'" % [module_id, kind, target]
		)
		_validate_effect_target_list(
			module_id, kind, Array(effect.get("effects", [])), stage_only
		)


func _validate_expansion_distributions() -> void:
	var open_count: int = 0
	var achievement_count: int = 0
	var v1: int = 0
	var v2: int = 0
	var v3: int = 0
	var v5: int = 0
	var h1: int = 0
	var h3: int = 0
	var rarities: Dictionary = {}
	for module_id in EXPANSION_MODULE_IDS:
		var module: ModuleDefinition = ContentDatabase.get_module(module_id)
		assert_true(module != null, "Expansion module %s exists" % module_id)
		if module == null:
			continue
		rarities[module.rarity] = int(rarities.get(module.rarity, 0)) + 1
		if module.unlock_achievement != "":
			achievement_count += 1
		elif module.min_hard_victories >= 3:
			h3 += 1
		elif module.min_hard_victories >= 1:
			h1 += 1
		elif module.min_victories >= 5:
			v5 += 1
		elif module.min_victories >= 3:
			v3 += 1
		elif module.min_victories >= 2:
			v2 += 1
		elif module.min_victories >= 1:
			v1 += 1
		else:
			open_count += 1
	assert_eq(open_count, 11, "Expansion OPEN gate count")
	assert_eq(achievement_count, 20, "Expansion achievement gate count")
	assert_eq(v1, 11, "Expansion V1 gate count")
	assert_eq(v2, 6, "Expansion V2 gate count")
	assert_eq(v3, 5, "Expansion V3 gate count")
	assert_eq(v5, 3, "Expansion V5 gate count")
	assert_eq(h1, 2, "Expansion H1 gate count")
	assert_eq(h3, 1, "Expansion H3 gate count")
	assert_eq(int(rarities.get("common", 0)), 9, "Expansion common count")
	assert_eq(int(rarities.get("uncommon", 0)), 17, "Expansion uncommon count")
	assert_eq(int(rarities.get("rare", 0)), 23, "Expansion rare count")
	assert_eq(int(rarities.get("legendary", 0)), 10, "Expansion legendary count")


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
	var gain_factor: float = float(heat_cfg.get("gain_per_power", 0.06))
	var cooling_factor: float = float(heat_cfg.get("cooling_factor", 0.25))
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
	bad.name = "Synthetic"
	bad.category = "test"
	bad.rarity = "common"
	bad.description_template = "Broken."
	bad.tags = PackedStringArray(["test"])
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


func _test_validation_catches_module_gate_and_shape_errors() -> void:
	var bad := ModuleDefinition.new()
	bad.id = "op.synthetic_gates"
	bad.name = ""
	bad.category = "not_a_category"
	bad.rarity = "mythic"
	bad.description_template = ""
	bad.tags = PackedStringArray([])
	bad.difficulty = PackedStringArray(["normal", "hard"])
	bad.min_victories = -1
	bad.min_hard_victories = -2
	bad.draft_weight = 0.0
	bad.slot_effects = []
	ContentDatabase.modules.append(bad)
	var errors: Array[String] = ContentDatabase.collect_validation_errors()
	ContentDatabase.modules.pop_back()
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("empty name")),
		"Validation catches an empty module name"
	)
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("unknown category")),
		"Validation catches an unknown module category"
	)
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("unknown rarity")),
		"Validation catches an unknown module rarity"
	)
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("negative min_victories")),
		"Validation catches a negative victory gate"
	)
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("non-positive draft_weight")),
		"Validation catches a non-positive draft weight"
	)
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("no slot, folded, finalizing, completion, or combo effects")),
		"Validation catches a module with no mechanical effects"
	)
	assert_true(
		ContentDatabase.collect_validation_errors().is_empty(),
		"Removing the synthetic gated module restores a clean validation pass"
	)


func _test_folded_only_module_is_accepted() -> void:
	var folded := ModuleDefinition.new()
	folded.id = "op.synthetic_folded_only"
	folded.name = "Folded Only"
	folded.category = "test"
	folded.rarity = "common"
	folded.description_template = "Reacts after the fold."
	folded.tags = PackedStringArray(["test"])
	folded.difficulty = PackedStringArray(["normal", "hard"])
	folded.folded_effects = [{
		"operation": "multiply",
		"target": "stage.next_multiplier",
		"value": 1.3,
		"conditions": [{"left": "$stage_caught", "operator": ">", "right": 0}],
	}]
	ContentDatabase.modules.append(folded)
	ContentDatabase._modules_by_id[folded.id] = folded
	var errors: Array[String] = ContentDatabase.collect_validation_errors()
	ContentDatabase.modules.pop_back()
	ContentDatabase._modules_by_id.erase(folded.id)
	assert_false(
		errors.any(func(e: String) -> bool: return e.contains("op.synthetic_folded_only")),
		"A folded-only module is mechanically non-empty"
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
## the readouts on the wall and the workstation bay are all placed from rects
## authored beside each location's picture. A location that ships without them,
## or with a bay that falls outside the column the console is mounted in,
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
		var bay: Rect2 = AssetCatalog.board_workstation_bay(location)
		assert_true(bay.size.x > 0.0, "%s reserves a workstation bay" % location)
		assert_true(
			column.encloses(bay),
			"%s keeps its workstation bay inside the work column" % location
		)
		assert_true(
			bay.position.x >= 0.0 and bay.position.y >= 0.0
				and bay.end.x <= 1.0 and bay.end.y <= 1.0,
			"%s keeps its workstation bay inside the picture" % location
		)
		assert_true(
			bay.size.x * bay.size.y >= 0.55,
			"%s leaves enough clearance for the triple-screen workstation" % location
		)


func _validate_workstation_art() -> void:
	var workstation_scene: PackedScene = load("res://ui/board/burn_rig.tscn")
	var workstation: Control = workstation_scene.instantiate()
	assert_eq(
		workstation.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"Transparent workstation root does not block room furniture"
	)
	var bay: Control = workstation.get_node("Bay")
	assert_eq(
		bay.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"Transparent workstation bay does not block the post-it navigation"
	)
	workstation.free()
	var expected_screens: Array[int] = [1, 1, 2, 2, 3]
	for stage_index in range(1, 6):
		var data: Dictionary = AssetCatalog.rig_stage(stage_index)
		assert_false(data.is_empty(), "Workstation stage %d has valid artwork" % stage_index)
		assert_true(data.get("texture") is Texture2D, "Workstation stage %d loads its texture" % stage_index)
		var screens: Array = Array(data.get("screens", []))
		assert_eq(
			screens.size(), expected_screens[stage_index - 1],
			"Workstation stage %d has its expected display count" % stage_index
		)
		for raw_rect in screens:
			assert_true(raw_rect is Rect2, "Stage %d screen geometry is a rectangle" % stage_index)
			if not raw_rect is Rect2:
				continue
			var rect: Rect2 = raw_rect
			assert_true(
				rect.size.x > 0.0 and rect.size.y > 0.0
					and rect.position.x >= 0.0 and rect.position.y >= 0.0
					and rect.end.x <= 1.0 and rect.end.y <= 1.0,
				"Stage %d keeps every display on its artwork" % stage_index
			)


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	assert_true(ContentDatabase.jobs.size() > 0, "Content loads jobs after reload")
	_validate_every_machine_can_be_cooled()
	_validate_ascension_contracts()
	_validate_room_art()
	_validate_workstation_art()
	_test_shipped_content_passes_validation()
	_test_validation_catches_synthetic_bad_content()
	_test_validation_catches_unknown_rules_and_capabilities()
	_test_validation_catches_unknown_module_operation()
	_test_validation_catches_module_gate_and_shape_errors()
	_test_folded_only_module_is_accepted()
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
	var expansion_present: int = 0
	for module in ContentDatabase.modules:
		assert_true(module.id.begins_with("op."), "Module id is namespaced: %s" % module.id)
		assert_true(
			module.slot_effects.size() > 0
				or module.folded_effects.size() > 0
				or module.finalizing_effects.size() > 0
				or module.completion_effects.size() > 0
				or _module_has_combo_effects(module),
			"Module %s does something" % module.id
		)
		_validate_module_effect_targets(module)
		var rendered: String = evaluator.render_template(module.description_template, module.parameters)
		assert_false(rendered.contains("{"), "Module %s description resolves every parameter" % module.id)
		_validate_percent_parameters(module.id, module.parameters)
		_validate_combos(module, evaluator)
		if module.id in EXPANSION_MODULE_IDS:
			expansion_present += 1
	if ContentDatabase.modules.size() >= 120:
		assert_eq(ContentDatabase.modules.size(), 120, "Expanded catalogue is exactly 120 modules")
		assert_eq(expansion_present, EXPANSION_MODULE_IDS.size(), "All 59 expansion module ids are present")
		_validate_expansion_distributions()
	else:
		assert_eq(
			ContentDatabase.modules.size(), 61,
			"Baseline catalogue stays at 61 until the expansion lands"
		)

	for perk in ContentDatabase.perks:
		_validate_percent_parameters(perk.id, perk.parameters)
		var perk_text: String = evaluator.render_template(perk.description_template, perk.parameters)
		assert_false(perk_text.contains("{"), "Perk %s description resolves every parameter" % perk.id)

	assert_true(ContentDatabase.achievements.size() > 0, "Content loads the achievement catalogue")
	# The Market shelf has to reward a long game as well as a first run, so every
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
