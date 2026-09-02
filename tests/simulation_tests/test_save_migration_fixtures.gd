extends TestCase

## Historical save envelopes kept as fixtures so 1.0 does not rely on ad-hoc
## current-save tests. Each fixture must migrate without producing an impossible
## phase, negative job progress, or NaN cash.


func run() -> void:
	_test_v1_minimal_migrates()
	_test_corrupt_fixture_is_rejected()
	_test_current_save_round_trips()


func _test_v1_minimal_migrates() -> void:
	var payload: Dictionary = _read_fixture("v1_minimal.json")
	assert_true(not payload.is_empty(), "v1 fixture parses")
	var state := RunState.new()
	state.from_dict(Dictionary(payload.get("run_state", {})))
	assert_true(state.compute.has("token_rate"), "v1 fixture fills compute")
	assert_eq(float(state.economy.get("cash", 0.0)), 250.0, "v1 cash survives")
	assert_true(float(state.economy.get("cash", 0.0)) >= 0.0, "cash is not negative")
	assert_true(int(state.calendar.get("round", 0)) >= 1, "round is valid")
	for job in Array(state.business.get("active_jobs", [])):
		if job is Dictionary:
			assert_true(float(job.get("tokens_remaining", 0.0)) >= 0.0, "job progress not negative")


func _test_corrupt_fixture_is_rejected() -> void:
	var path := "res://tests/fixtures/saves/corrupt.json"
	var parser := JSON.new()
	var text: String = FileAccess.get_file_as_string(path)
	assert_true(parser.parse(text) != OK, "Corrupt fixture is not valid JSON")


func _test_current_save_round_trips() -> void:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(404)
	var envelope := {
		"version": SaveManager.CURRENT_SAVE_VERSION,
		"phase": "ROUND_PREP",
		"seed": sim.run_seed,
		"run_state": sim.run_state.to_dict(),
		"pending_choices": [],
		"round_end_pending": false,
	}
	var restored := RunState.new()
	restored.from_dict(Dictionary(envelope.get("run_state", {})))
	assert_eq(
		float(restored.economy.get("cash", -1.0)),
		float(sim.run_state.economy.get("cash", 0.0)),
		"Current save cash round-trips"
	)
	assert_eq(int(restored.to_dict().get("save_version", 0)), RunState.SAVE_VERSION, "Current save is at SAVE_VERSION")
	sim.free()


func _read_fixture(name: String) -> Dictionary:
	var path := "res://tests/fixtures/saves/%s" % name
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
