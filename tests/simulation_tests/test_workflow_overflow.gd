extends TestCase

## Supported capacity is a location floor, not a hard wall. Overflow stages
## still resolve, but they cost instability, cascade chance and heat. Bedroom
## and garage stay scarce.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	FeatureFlags.reload()
	_test_bedroom_stays_at_three()
	_test_location_baselines()
	_test_bedroom_cannot_overflow()
	_test_office_can_overflow()
	_test_overflow_is_not_trimmed()
	_test_overflow_stage_pays_the_tax()
	_test_bonuses_add_to_supported()


func _board(location: String = "bedroom") -> Dictionary:
	var state := RunState.new()
	var board := BoardSystem.new()
	Simulation.apply_run_location(state, location, false)
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


func _test_location_baselines() -> void:
	var expected := {
		"bedroom": 3,
		"garage": 5,
		"office_unit": 7,
		"warehouse": 9,
		"datacentre_campus": 10,
		"private_power_grid": 11,
		"moon_facility": 12,
	}
	for location in expected.keys():
		var pack: Dictionary = _board(str(location))
		assert_eq(
			pack["board"].derived_supported_capacity(pack["state"], ContentDatabase),
			int(expected[location]),
			"%s backs %d stages" % [location, int(expected[location])]
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
		7,
		"The office backs seven stages"
	)
	var index: int = pack["board"].append_overflow_stage(pack["state"], ContentDatabase)
	assert_eq(index, 7, "The first overflow stage is slot 8")
	assert_eq(pack["board"].slots(pack["state"]).size(), 8, "The pipeline grew")
	assert_true(
		pack["board"].is_overflow_index(pack["state"], 7, ContentDatabase),
		"Stage 8 is unsupported"
	)


func _test_overflow_is_not_trimmed() -> void:
	var pack: Dictionary = _board("office_unit")
	var board: BoardSystem = pack["board"]
	var state: RunState = pack["state"]
	board.append_overflow_stage(state, ContentDatabase)
	var owned: Array = board.owned_modules(state)
	if not ("op.linter" in owned):
		owned.append("op.linter")
	state.build["modules"] = owned
	assert_true(board.place_module(state, {}, "op.linter", 7), "An overflow stage can hold a module")
	board.ensure_board(state, ContentDatabase)
	assert_eq(board.slots(state).size(), 8, "ensure_board does not trim a filled overflow stage")
	assert_eq(str(board.slots(state)[7]), "op.linter", "And the module stays put")


func _test_overflow_stage_pays_the_tax() -> void:
	var pack: Dictionary = _board("office_unit")
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
		board.append_overflow_stage(state, ContentDatabase)
	layout = board.slots(state)
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
	assert_true(
		float(Dictionary(overflow_stage.get("stage", {})).get("cascade_chance", 0.0)) >= 0.03,
		"Overflow adds cascade chance"
	)
	assert_true(
		float(Dictionary(overflow_stage.get("stage", {})).get("heat", 0.0)) >= 2.0,
		"Overflow adds thermal load"
	)


func _test_bonuses_add_to_supported() -> void:
	var pack: Dictionary = _board("bedroom")
	pack["state"].build["board"]["meta_slot_bonus"] = 1
	pack["board"].ensure_board(pack["state"], ContentDatabase)
	assert_eq(
		pack["board"].derived_supported_capacity(pack["state"], ContentDatabase),
		4,
		"A meta slot widens supported capacity, not a separate wall"
	)
	assert_eq(pack["board"].slots(pack["state"]).size(), 4, "And the bedroom board grows with it")
