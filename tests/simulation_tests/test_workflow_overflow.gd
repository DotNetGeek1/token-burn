extends TestCase

## Safe capacity is the Workflow Backplane's bays and nothing else. Everything
## that used to widen the board — the infrastructure, meta unlocks, Wide Bus,
## monitors — now widens the overflow allowance instead, and every overflow
## stage is added deliberately with + STAGE. Overflow stages still resolve, but
## they cost instability, cascade chance and heat. The first tiers stay scarce.

## The backplane tier each Infrastructure Tier opens with, by its room
## (infrastructure.json `cabinet_entry_tiers`), and the bays that tier is worth.
const SAFE_BY_DWELLING := {
	"bedroom": 3,
	"garage": 5,
	"office_unit": 5,
	"warehouse": 7,
	"datacentre_campus": 7,
	"private_power_grid": 10,
	"moon_facility": 10,
}

## `infrastructure.json` `overflow_allowance` per tier, keyed by the tier's room.
const BASE_ALLOWANCE_BY_DWELLING := {
	"bedroom": 0,
	"garage": 0,
	"office_unit": 2,
	"warehouse": 3,
	"datacentre_campus": 4,
	"private_power_grid": 5,
	"moon_facility": 6,
}


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	FeatureFlags.reload()
	_test_bedroom_stays_at_three()
	_test_safe_capacity_is_the_backplane_per_dwelling()
	_test_bedroom_cannot_overflow()
	_test_office_can_overflow()
	_test_plus_stage_adds_exactly_one()
	_test_overflow_is_not_trimmed()
	_test_overflow_stage_pays_the_tax()
	_test_meta_bonus_widens_the_allowance_not_the_backplane()
	_test_wide_bus_widens_the_allowance_not_the_backplane()
	_test_second_monitor_widens_the_allowance_not_the_backplane()
	_test_buying_the_backplane_widens_safe_capacity()
	_test_chapter_move_does_not_lengthen_the_pipeline()
	_test_max_pipeline_length_is_capped()
	_test_capacity_debug_adds_up()
	_test_overflow_pressure_curve()
	_test_first_overflow_stage_pays_the_flat_tax()
	_test_deeper_overflow_stages_pay_more()


## Pressure is `ordinal ^ pressure_exponent`: 1.0 for the first bolted-on
## stage, then superlinear, so a long overflow tail is far more than the sum
## of its stages.
func _test_overflow_pressure_curve() -> void:
	var exponent: float = float(BoardSystem.overflow_config(ContentDatabase).get("pressure_exponent", 0.0))
	assert_almost_eq(exponent, 1.5, 1e-9, "The authored pressure exponent is 1.5")
	assert_eq(BoardSystem.overflow_pressure(0), 0.0, "A supported stage has no pressure")
	assert_eq(BoardSystem.overflow_pressure(-3), 0.0, "Nor does a negative ordinal")
	assert_almost_eq(BoardSystem.overflow_pressure(1), 1.0, 1e-9, "The first overflow stage is 1×")
	assert_almost_eq(BoardSystem.overflow_pressure(4), 8.0, 1e-9, "The fourth is 8×")
	var previous: float = 0.0
	var previous_step: float = 0.0
	for ordinal in range(1, 15):
		var pressure: float = BoardSystem.overflow_pressure(ordinal)
		assert_true(pressure > previous, "Pressure rises with every stage (ordinal %d)" % ordinal)
		var step: float = pressure - previous
		assert_true(step >= previous_step, "And rises faster each time — superlinear (ordinal %d)" % ordinal)
		assert_true(pressure >= float(ordinal), "Never below linear (ordinal %d)" % ordinal)
		previous = pressure
		previous_step = step


func _test_first_overflow_stage_pays_the_flat_tax() -> void:
	var pack: Dictionary = _board("warehouse")
	var board: BoardSystem = pack["board"]
	var state: RunState = pack["state"]
	var cfg: Dictionary = BoardSystem.overflow_config(ContentDatabase)
	var safe: int = board.derived_supported_capacity(state, ContentDatabase)
	var first: int = board.append_overflow_stage(state, ContentDatabase)
	assert_eq(first, safe, "The first overflow stage sits at the safe boundary")
	assert_eq(board.overflow_ordinal(state, first, ContentDatabase), 1, "It is overflow stage #1")
	assert_eq(board.overflow_ordinal(state, safe - 1, ContentDatabase), 0, "The last supported slot is not")
	assert_almost_eq(
		board._overflow_instability(state, first), float(cfg.get("instability", 0.05)), 1e-9,
		"The first overflow stage costs exactly the authored instability"
	)
	var stage := {"cascade_chance": 0.0, "heat": 10.0}
	assert_true(board._apply_overflow_penalties(state, stage, first), "It is taxed")
	assert_almost_eq(
		float(stage["cascade_chance"]), float(cfg.get("cascade_chance", 0.03)), 1e-9,
		"Exactly the authored cascade chance"
	)
	assert_almost_eq(
		float(stage["heat"]),
		10.0 + 10.0 * float(cfg.get("heat_pct", 0.04)) + float(cfg.get("heat_flat", 2.0)),
		1e-9,
		"Exactly the authored heat tax"
	)
	assert_almost_eq(float(stage.get("overflow_pressure", 0.0)), 1.0, 1e-9, "At 1× pressure")
	var untouched := {"cascade_chance": 0.0, "heat": 10.0}
	assert_false(board._apply_overflow_penalties(state, untouched, safe - 1), "Supported stages are not taxed")
	assert_eq(float(untouched["heat"]), 10.0, "And keep their heat")


func _test_deeper_overflow_stages_pay_more() -> void:
	var pack: Dictionary = _board("moon_facility")
	var board: BoardSystem = pack["board"]
	var state: RunState = pack["state"]
	var cfg: Dictionary = BoardSystem.overflow_config(ContentDatabase)
	var safe: int = board.derived_supported_capacity(state, ContentDatabase)
	var indices: Array = []
	for _i in range(4):
		var index: int = board.append_overflow_stage(state, ContentDatabase)
		assert_true(index >= 0, "The moon can bolt on four overflow stages")
		indices.append(index)
	var base_instability: float = float(cfg.get("instability", 0.05))
	var base_cascade: float = float(cfg.get("cascade_chance", 0.03))
	var base_heat_tax: float = 10.0 * float(cfg.get("heat_pct", 0.04)) + float(cfg.get("heat_flat", 2.0))
	var last_instability: float = 0.0
	var last_cascade: float = 0.0
	var last_heat: float = 10.0
	for n in range(indices.size()):
		var index: int = int(indices[n])
		var ordinal: int = n + 1
		assert_eq(board.overflow_ordinal(state, index, ContentDatabase), ordinal, "Ordinals count from the safe boundary")
		var pressure: float = BoardSystem.overflow_pressure(ordinal)
		var instability: float = board._overflow_instability(state, index)
		assert_almost_eq(instability, base_instability * pressure, 1e-9, "Instability scales by pressure (stage %d)" % ordinal)
		assert_true(instability > last_instability, "And grows stage over stage")
		last_instability = instability
		var stage := {"cascade_chance": 0.0, "heat": 10.0}
		board._apply_overflow_penalties(state, stage, index)
		assert_almost_eq(float(stage["cascade_chance"]), base_cascade * pressure, 1e-9, "Cascade chance scales by pressure (stage %d)" % ordinal)
		assert_almost_eq(float(stage["heat"]), 10.0 + base_heat_tax * pressure, 1e-9, "Heat tax scales by pressure (stage %d)" % ordinal)
		assert_true(float(stage["cascade_chance"]) > last_cascade, "Cascade chance grows stage over stage")
		assert_true(float(stage["heat"]) > last_heat, "Heat grows stage over stage")
		last_cascade = float(stage["cascade_chance"])
		last_heat = float(stage["heat"])
	assert_almost_eq(
		board._overflow_instability(state, int(indices[3])), base_instability * 8.0, 1e-9,
		"The fourth overflow stage is eight times as unstable as the first"
	)


## A board standing on the Infrastructure Tier whose presentation room is
## `location`; the tables above are keyed by room for readability.
func _board(location: String = "bedroom") -> Dictionary:
	var state := RunState.new()
	var board := BoardSystem.new()
	Simulation.apply_infrastructure_tier(state, InfrastructureSystem.tier_for_room(location))
	board.ensure_board(state, ContentDatabase)
	return {"state": state, "board": board}


func _test_bedroom_stays_at_three() -> void:
	var pack: Dictionary = _board("bedroom")
	assert_eq(
		pack["board"].derived_supported_capacity(pack["state"], ContentDatabase),
		3,
		"A bedroom backs three stages"
	)
	assert_eq(pack["board"].slots(pack["state"]).size(), 3, "And the pipeline is that wide")
	assert_false(
		pack["board"].overflow_unlocked(pack["state"], ContentDatabase),
		"The laptop room cannot grow past what it supports"
	)


func _test_safe_capacity_is_the_backplane_per_dwelling() -> void:
	for location in SAFE_BY_DWELLING.keys():
		var pack: Dictionary = _board(str(location))
		var state: RunState = pack["state"]
		var board: BoardSystem = pack["board"]
		var tier: int = CabinetSystems.tier(state, "backplane")
		var bays: int = int(CabinetSystems.tier_value("backplane", "bays", tier))
		assert_eq(
			bays, int(SAFE_BY_DWELLING[location]),
			"%s opens on a tier %d backplane worth %d bays" % [location, tier, int(SAFE_BY_DWELLING[location])]
		)
		assert_eq(
			board.derived_supported_capacity(state, ContentDatabase), bays,
			"%s safe capacity is exactly its backplane's bays" % location
		)
		assert_eq(
			board.slots(state).size(), bays,
			"%s opens with a pipeline exactly as wide as its backplane" % location
		)
		assert_eq(
			board.overflow_allowance(state, ContentDatabase),
			int(BASE_ALLOWANCE_BY_DWELLING[location]),
			"%s base overflow allowance is the table's" % location
		)
		assert_true(
			board.max_pipeline_length(state, ContentDatabase) <= BoardSystem.MAX_PIPELINE_STAGES,
			"%s never exceeds the resolver's ceiling" % location
		)


func _test_bedroom_cannot_overflow() -> void:
	var pack: Dictionary = _board("bedroom")
	assert_eq(
		pack["board"].append_overflow_stage(pack["state"], ContentDatabase),
		-1,
		"Bedroom overflow is refused"
	)
	assert_eq(pack["board"].slots(pack["state"]).size(), 3, "The board stays three wide")


func _test_office_can_overflow() -> void:
	var pack: Dictionary = _board("office_unit")
	assert_true(
		pack["board"].overflow_unlocked(pack["state"], ContentDatabase),
		"An office can grow past supported capacity"
	)
	assert_eq(
		pack["board"].derived_supported_capacity(pack["state"], ContentDatabase),
		5,
		"The office backs five stages: its tier-2 backplane, not a chapter table"
	)
	assert_eq(
		pack["board"].max_pipeline_length(pack["state"], ContentDatabase),
		7,
		"Five safe plus two allowance is the office's longest pipeline"
	)
	var index: int = pack["board"].append_overflow_stage(pack["state"], ContentDatabase)
	assert_eq(index, 5, "The first overflow stage is slot 6")
	assert_eq(pack["board"].slots(pack["state"]).size(), 6, "The pipeline grew")
	assert_true(
		pack["board"].is_overflow_index(pack["state"], 5, ContentDatabase),
		"Stage 6 is unsupported"
	)


## + STAGE is the only way a pipeline grows, and it grows by one.
func _test_plus_stage_adds_exactly_one() -> void:
	var pack: Dictionary = _board("warehouse")
	var board: BoardSystem = pack["board"]
	var state: RunState = pack["state"]
	var safe: int = board.derived_supported_capacity(state, ContentDatabase)
	var longest: int = board.max_pipeline_length(state, ContentDatabase)
	assert_eq(board.slots(state).size(), safe, "The warehouse opens at safe capacity")
	var expected: int = safe
	var guard: int = 0
	while board.can_append_overflow(state, ContentDatabase) and guard < 32:
		guard += 1
		var before: int = board.slots(state).size()
		var index: int = board.append_overflow_stage(state, ContentDatabase)
		expected += 1
		assert_eq(index, before, "The new stage lands at the end")
		assert_eq(board.slots(state).size(), before + 1, "+ STAGE adds exactly one stage")
		assert_eq(board.slots(state).size(), expected, "And nothing else grew it")
	assert_eq(board.slots(state).size(), longest, "The pipeline stops at max_pipeline_length")
	assert_eq(board.append_overflow_stage(state, ContentDatabase), -1, "One more is refused")
	board.ensure_board(state, ContentDatabase)
	assert_eq(board.slots(state).size(), longest, "ensure_board keeps the explicit stages")


func _test_overflow_is_not_trimmed() -> void:
	var pack: Dictionary = _board("office_unit")
	var board: BoardSystem = pack["board"]
	var state: RunState = pack["state"]
	board.append_overflow_stage(state, ContentDatabase)
	var owned: Array = board.owned_modules(state)
	if not ("op.linter" in owned):
		owned.append("op.linter")
	state.build["modules"] = owned
	assert_true(board.place_module(state, {}, "op.linter", 5), "An overflow stage can hold a module")
	board.ensure_board(state, ContentDatabase)
	assert_eq(board.slots(state).size(), 6, "ensure_board does not trim a filled overflow stage")
	assert_eq(str(board.slots(state)[5]), "op.linter", "And the module stays put")


func _test_overflow_stage_pays_the_tax() -> void:
	var pack: Dictionary = _board("warehouse")
	var board: BoardSystem = pack["board"]
	var state: RunState = pack["state"]
	var pipeline := [
		"op.prompt", "op.cheap_model", "op.unit_tests",
		"op.linter", "op.token_cache", "op.premium_model", "op.overclock",
		"op.recursive_compiler",
	]
	var owned: Array = board.owned_modules(state)
	for module_id in pipeline:
		if not (module_id in owned):
			owned.append(module_id)
	state.build["modules"] = owned
	var layout: Array = board.slots(state)
	while layout.size() < pipeline.size():
		if board.append_overflow_stage(state, ContentDatabase) < 0:
			break
	layout = board.slots(state)
	assert_eq(layout.size(), pipeline.size(), "The warehouse can take an eight-stage pipeline")
	for i in range(pipeline.size()):
		layout[i] = pipeline[i]
	var job := {
		"id": "job.overflow",
		"name": "Overflow",
		"token_requirement": 10000.0,
		"tokens_remaining": 10000.0,
		"quality": 0.0,
		"quality_threshold": 60.0,
		"known_bugs": 0,
		"hidden_bugs": 0,
		"blocked_slots": 0,
		"board_rules": [],
		"tags": [],
	}
	var safe: Dictionary = board.resolve_burn(
		state, job, 1000.0, DeterministicRng.new(11), EffectResolver.new(), []
	)
	assert_true(safe.get("ok", false), "An overflow pipeline still burns")
	var overflow_stage: Dictionary = {}
	for stage in Array(safe.get("stages", [])):
		if bool(Dictionary(stage).get("overflow", false)):
			overflow_stage = Dictionary(stage)
			break
	assert_false(overflow_stage.is_empty(), "The last stage is marked overflow")
	assert_eq(int(overflow_stage.get("slot_index", -1)), 7, "Only the stage past the seven bays is overflow")
	assert_true(
		float(Dictionary(overflow_stage.get("stage", {})).get("cascade_chance", 0.0)) >= 0.03,
		"Overflow adds cascade chance"
	)
	assert_true(
		float(Dictionary(overflow_stage.get("stage", {})).get("heat", 0.0)) >= 2.0,
		"Overflow adds thermal load"
	)


## "One More Pipeline Slot" is permission to bolt on a stage, not a wider rail.
func _test_meta_bonus_widens_the_allowance_not_the_backplane() -> void:
	var pack: Dictionary = _board("bedroom")
	var board: BoardSystem = pack["board"]
	var state: RunState = pack["state"]
	state.build["board"]["meta_overflow_bonus"] = 1
	board.ensure_board(state, ContentDatabase)
	assert_eq(board.derived_supported_capacity(state, ContentDatabase), 3, "Safe capacity is still the 3-Bay Rail")
	assert_eq(board.slots(state).size(), 3, "The board did not grow on its own")
	assert_eq(board.overflow_allowance(state, ContentDatabase), 1, "The unlock is one stage of allowance")
	assert_eq(board.max_pipeline_length(state, ContentDatabase), 4, "So the pipeline may reach four")
	assert_true(board.overflow_unlocked(state, ContentDatabase), "Allowance opens overflow even in the bedroom")
	assert_eq(board.append_overflow_stage(state, ContentDatabase), 3, "+ STAGE bolts it on")
	assert_eq(board.slots(state).size(), 4, "Now the board is four wide")
	assert_true(board.is_overflow_index(state, 3, ContentDatabase), "And the fourth stage is overflow")
	assert_eq(board.append_overflow_stage(state, ContentDatabase), -1, "A second is refused")


func _test_wide_bus_widens_the_allowance_not_the_backplane() -> void:
	var pack: Dictionary = _board("garage")
	var board: BoardSystem = pack["board"]
	var state: RunState = pack["state"]
	var before: int = board.overflow_allowance(state, ContentDatabase)
	state.build["perks"] = ["perk.wide_bus"]
	board.ensure_board(state, ContentDatabase)
	assert_eq(board.derived_supported_capacity(state, ContentDatabase), 5, "Wide Bus leaves the 5-Bay Rail at five")
	assert_eq(board.slots(state).size(), 5, "And the pipeline where it was")
	assert_eq(board.overflow_allowance(state, ContentDatabase), before + 1, "Wide Bus is one stage of allowance")
	assert_eq(BoardSystem.perk_overflow_bonus(state, ContentDatabase), 1, "Attributed to perks")


func _test_second_monitor_widens_the_allowance_not_the_backplane() -> void:
	var pack: Dictionary = _board("bedroom")
	var board: BoardSystem = pack["board"]
	var state: RunState = pack["state"]
	UpgradeSystem.record_free_grant(state, "upgrade.second_monitor", ContentDatabase)
	UpgradeSystem.record_free_grant(state, "upgrade.standing_desk", ContentDatabase)
	board.ensure_board(state, ContentDatabase)
	assert_eq(board.derived_supported_capacity(state, ContentDatabase), 3, "Monitors do not widen the rail")
	assert_eq(board.slots(state).size(), 3, "The pipeline stays three wide until + STAGE")
	assert_eq(BoardSystem.upgrade_overflow_bonus(state, ContentDatabase), 2, "Monitor and desk are one stage each")
	assert_eq(board.overflow_allowance(state, ContentDatabase), 2, "Both land in the allowance")
	assert_eq(board.max_pipeline_length(state, ContentDatabase), 5, "So the bedroom may reach five stages")


func _test_buying_the_backplane_widens_safe_capacity() -> void:
	var pack: Dictionary = _board("bedroom")
	var board: BoardSystem = pack["board"]
	var state: RunState = pack["state"]
	CabinetSystems.set_tier(state, "backplane", 2)
	board.ensure_board(state, ContentDatabase)
	assert_eq(board.derived_supported_capacity(state, ContentDatabase), 5, "A 5-Bay Rail backs five")
	assert_eq(board.slots(state).size(), 5, "And the pipeline is laid out to it")
	assert_eq(board.overflow_allowance(state, ContentDatabase), 0, "The tier adds no allowance")


## Buying a bigger Infrastructure Tier lifts the backplane (so the pipeline
## widens to the new rail) but never bolts on the tier's overflow allowance by
## itself.
func _test_chapter_move_does_not_lengthen_the_pipeline() -> void:
	var pack: Dictionary = _board("garage")
	var board: BoardSystem = pack["board"]
	var state: RunState = pack["state"]
	Simulation.apply_infrastructure_tier(state, InfrastructureSystem.tier_for_room("warehouse"))
	board.ensure_board(state, ContentDatabase)
	assert_eq(CabinetSystems.tier(state, "backplane"), 3, "The warehouse tier lifts the backplane to tier 3")
	assert_eq(board.derived_supported_capacity(state, ContentDatabase), 7, "Safe capacity follows the tier")
	assert_eq(board.slots(state).size(), 7, "The pipeline is exactly safe capacity, no overflow bolted on")
	assert_eq(board.overflow_allowance(state, ContentDatabase), 3, "The allowance is there to be used")


func _test_max_pipeline_length_is_capped() -> void:
	var pack: Dictionary = _board("moon_facility")
	var board: BoardSystem = pack["board"]
	var state: RunState = pack["state"]
	state.build["board"]["meta_overflow_bonus"] = 40
	assert_eq(
		board.max_pipeline_length(state, ContentDatabase),
		BoardSystem.MAX_PIPELINE_STAGES,
		"No amount of allowance takes the pipeline past the resolver's ceiling"
	)
	assert_eq(board.derived_supported_capacity(state, ContentDatabase), 10, "Safe capacity is untouched")


func _test_capacity_debug_adds_up() -> void:
	var pack: Dictionary = _board("office_unit")
	var board: BoardSystem = pack["board"]
	var state: RunState = pack["state"]
	state.build["board"]["meta_overflow_bonus"] = 1
	state.build["perks"] = ["perk.wide_bus"]
	UpgradeSystem.record_free_grant(state, "upgrade.second_monitor", ContentDatabase)
	board.ensure_board(state, ContentDatabase)
	board.append_overflow_stage(state, ContentDatabase)
	var debug: Dictionary = board.capacity_debug(state, ContentDatabase)
	for key in [
		"room", "infrastructure_tier", "backplane_tier", "backplane_safe_capacity", "legacy_bonus",
		"perk_bonus", "upgrade_bonus", "safe_capacity", "overflow_capacity", "max_pipeline_length",
		"workflow_slots_size",
	]:
		assert_true(debug.has(key), "capacity_debug carries %s" % key)
	assert_eq(str(debug.get("room", "")), "office_unit", "Debug names the room")
	assert_eq(int(debug.get("infrastructure_tier", -1)), 2, "Debug names the Infrastructure Tier")
	assert_eq(int(debug.get("backplane_tier", 0)), 2, "Debug names the tier")
	assert_eq(int(debug.get("backplane_safe_capacity", 0)), 5, "Debug quotes the tier's bays")
	assert_eq(int(debug.get("safe_capacity", 0)), 5, "Safe capacity is the tier's bays")
	assert_eq(int(debug.get("legacy_bonus", 0)), 1, "Legacy bonus is the meta rank")
	assert_eq(int(debug.get("perk_bonus", 0)), 1, "Perk bonus is Wide Bus")
	assert_eq(int(debug.get("upgrade_bonus", 0)), 1, "Upgrade bonus is the monitor")
	assert_eq(int(debug.get("overflow_capacity", 0)), 2 + 1 + 1 + 1, "Allowance is base plus every bonus")
	assert_eq(int(debug.get("max_pipeline_length", 0)), 5 + 5, "Max length is safe plus allowance")
	assert_eq(int(debug.get("workflow_slots_size", 0)), 6, "And the live pipeline has one stage bolted on")
