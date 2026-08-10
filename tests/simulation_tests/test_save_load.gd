extends TestCase


func run() -> void:
	var state := RunState.new()
	state.economy["cash"] = 999.0
	state.business["reputation"] = 42.0
	state.compute["rate_modifiers"] = [{"multiplier": 1.5, "prompts_remaining": 3, "source": "test"}]
	var data: Dictionary = state.to_dict()
	var loaded := RunState.new()
	loaded.from_dict(data)
	assert_eq(loaded.economy.get("cash", 0.0), 999.0, "Save round-trip preserves cash")
	assert_eq(loaded.business.get("reputation", 0.0), 42.0, "Save round-trip preserves reputation")
	assert_true(loaded.compute.has("rate_modifiers"), "Save includes rate modifiers")

	var partial: Dictionary = {"economy": {"cash": 123.0}, "save_version": 1}
	var migrated := RunState.new()
	migrated.from_dict(partial)
	assert_true(migrated.compute.has("token_rate"), "Migration fills missing compute keys")
	assert_true(migrated.business.has("demand_modifier"), "Migration adds demand_modifier")
	assert_eq(migrated.economy.get("cash", 0.0), 123.0, "Migration preserves saved values")

	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(200)
	sim.run_state.business["active_jobs"] = [{
		"id": "job.test",
		"name": "Test Job",
		"tokens_remaining": 50.0,
		"token_requirement": 100.0,
		"deadline_prompts": 5,
		"prompts_remaining": 3,
		"reward": 500.0,
		"quality": 10.0,
		"quality_threshold": 50.0,
	}]
	sim.phase = sim.Phase.IN_ROUND
	var saved: Dictionary = sim.run_state.to_dict()
	var sim2: Node = sim_script.new()
	sim2.autosave_enabled = false
	sim2.run_state.from_dict(saved)
	sim2.phase = sim.Phase.IN_ROUND
	assert_true(sim2.run_state.business.get("active_jobs", []).size() > 0, "In-flight jobs survive save/load")
	sim.free()
	sim2.free()

	_test_round_end_pending_survives_load(sim_script)
	_test_a_pre_round_save_keeps_its_progress()
	_test_a_pre_workflow_save_keeps_its_pipelines()
	_test_corrupt_primary_save_recovers_from_backup()


func _test_round_end_pending_survives_load(sim_script: GDScript) -> void:
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(201)
	sim.phase = sim.Phase.ANGEL_ROUND
	sim.debug_set_round_end_pending(true)
	sim.debug_present_angel_offers()
	# Written with the phase's old name on purpose: saves made before the angel
	# round was split out of the market still have to load.
	SaveManager.save_run(sim.run_state, "UPGRADE_CHOICE", sim.run_seed, sim.pending_choices, sim.debug_round_end_pending())

	var sim2: Node = sim_script.new()
	sim2.autosave_enabled = false
	assert_true(sim2.load_saved_run(), "Save with a pending round end loads")
	assert_eq(sim2.phase, sim2.Phase.ANGEL_ROUND, "A pre-split save resumes in the angel phase")
	assert_true(sim2.debug_round_end_pending(), "Round-end pending flag restored on load")
	var round_before: int = int(sim2.run_state.calendar["round"])
	sim2.decline_offers()
	assert_eq(int(sim2.run_state.calendar["round"]), round_before + 1, "The round rolls after loading mid angel phase")
	SaveManager.delete_save()
	sim.free()
	sim2.free()


## A run saved under the old month/round vocabulary has to come back as a
## round/prompt run with its money, its position and its contracts intact —
## dropping a run in progress on an update is not an acceptable migration.
func _test_a_pre_round_save_keeps_its_progress() -> void:
	var legacy: Dictionary = {
		"save_version": 6,
		"calendar": {"month": 5, "day": 1, "round": 7, "rounds_per_month": 12},
		"economy": {
			"cash": 2500.0,
			"monthly_rent": 900.0,
			"power_cost_per_round": 22.0,
			"costs_this_month": 60.0,
		},
		"compute": {
			"token_rate": 500.0,
			"round_rate": 750.0,
			"cloud_burst_rounds": 1,
			"rate_modifiers": [{"multiplier": 1.5, "rounds_remaining": 2, "source": "legacy"}],
		},
		"statistics": {"peak_round_tokens": 4200.0},
		"business": {
			"active_jobs": [{
				"id": "job.legacy",
				"name": "Legacy",
				"tokens_remaining": 30.0,
				"token_requirement": 100.0,
				"deadline_rounds": 9,
				"rounds_remaining": 4,
			}],
		},
	}
	var migrated := RunState.new()
	migrated.from_dict(legacy)
	assert_eq(int(migrated.calendar.get("round", 0)), 5, "The old month becomes the round")
	assert_eq(int(migrated.calendar.get("prompt", 0)), 7, "And the old round becomes the prompt")
	assert_false(migrated.calendar.has("rounds_per_month"), "The prompt budget is gone")
	assert_eq(float(migrated.economy.get("cash", 0.0)), 2500.0, "Cash survives the migration")
	assert_eq(float(migrated.economy.get("round_rent", 0.0)), 900.0, "Rent carries over at the same amount")
	assert_eq(float(migrated.economy.get("power_cost_per_prompt", 0.0)), 22.0, "Power is now metered per prompt")
	assert_eq(float(migrated.economy.get("costs_this_round", 0.0)), 60.0, "Costs already accrued stay accrued")
	assert_eq(float(migrated.compute.get("prompt_rate", 0.0)), 750.0, "The burst rate becomes the prompt rate")
	assert_eq(int(migrated.compute.get("cloud_burst_prompts", 0)), 1, "A live cloud burst keeps its remaining prompt")
	assert_eq(
		int(Array(migrated.compute.get("rate_modifiers", []))[0].get("prompts_remaining", 0)),
		2,
		"Temporary boosts keep their remaining duration"
	)
	assert_eq(float(migrated.statistics.get("peak_prompt_tokens", 0.0)), 4200.0, "The peak-burn record is kept")
	var job: Dictionary = Array(migrated.business.get("active_jobs", []))[0]
	assert_eq(int(job.get("deadline_prompts", 0)), 9, "Contract deadlines convert one-for-one")
	assert_eq(int(job.get("prompts_remaining", 0)), 4, "And so does the time left on them")


## A run saved when there was one global pipeline, plus a saved second lane it
## had earned, has to come back as two named workflows with both layouts and the
## room to keep them.
func _test_a_pre_workflow_save_keeps_its_pipelines() -> void:
	var legacy: Dictionary = {
		"save_version": 7,
		"build": {
			"operations": ["op.prompt", "op.unit_tests", "op.cheap_model"],
			"lane_count": 2,
			"board": {
				"slot_count": 3,
				"active_lane": 1,
				"lane_slots": [
					["op.prompt", "op.cheap_model", ""],
					["op.unit_tests", "", "op.prompt"],
				],
			},
		},
	}
	var migrated := RunState.new()
	migrated.from_dict(legacy)
	var board := BoardSystem.new()
	board.ensure_board(migrated, ContentDatabase)

	assert_eq(board.workflow_count(migrated), 2, "Both saved lanes became workflows")
	assert_eq(board.workflow_capacity(migrated), 2, "And the run keeps the room it had earned")
	assert_eq(
		Array(board.workflow_at(migrated, 0).get("slots", [])),
		["op.prompt", "op.cheap_model", ""],
		"The first layout is untouched"
	)
	assert_eq(
		Array(board.workflow_at(migrated, 1).get("slots", [])),
		["op.unit_tests", "", "op.prompt"],
		"And so is the second"
	)
	assert_eq(board.active_workflow_index(migrated), 1, "The run resumes on the lane it was left on")
	assert_true(str(board.workflow_at(migrated, 0).get("name", "")) != "", "Every workflow arrives named")


## Saving is what produces the `.bak` in the first place: a truncated write to
## the live save must not cost the player the previous, good save it replaced.
func _test_corrupt_primary_save_recovers_from_backup() -> void:
	var state := RunState.new()
	state.economy["cash"] = 4242.0
	var saved: bool = SaveManager.save_run(state, "IN_ROUND", 777, [], false)
	assert_true(saved, "First save succeeds and becomes the backup on the next save")

	state.economy["cash"] = 9999.0
	saved = SaveManager.save_run(state, "IN_ROUND", 777, [], false)
	assert_true(saved, "Second save succeeds, demoting the first to .bak")

	var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string("{not valid json")
	file.close()

	var loaded: Dictionary = SaveManager.load_run()
	assert_true(not loaded.is_empty(), "A corrupt primary save falls back to the backup")
	var recovered_state: Dictionary = loaded.get("run_state", {})
	assert_eq(
		float(recovered_state.get("economy", {}).get("cash", 0.0)), 4242.0,
		"The recovered save is the last good write, not the corrupt one"
	)
	SaveManager.delete_save()
