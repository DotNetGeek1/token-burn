extends TestCase

## Headless coverage for Android pause autosave. Uses a scratch path so the
## developer's real save is never touched.


const SCRATCH := "user://lifecycle_hooks_save.json"


func run() -> void:
	SaveManager.use_scratch(SCRATCH)
	_autosave_writes_when_active()
	_autosave_skips_idle()
	_autosave_skips_when_disabled()
	_reload_round_trips_phase()
	SaveManager.delete_save()
	SaveManager.restore_default()


func _make_sim(seed: int, enabled: bool) -> Node:
	var sim: Node = (load("res://core/simulation.gd") as GDScript).new()
	sim.autosave_enabled = enabled
	sim.start_run(seed)
	return sim


func _autosave_writes_when_active() -> void:
	SaveManager.delete_save()
	var sim: Node = _make_sim(311, true)
	assert_true(sim.phase != sim.Phase.IDLE, "start_run leaves a playable phase")
	var cash: float = float(sim.run_state.economy.get("cash", 0.0))
	var round_number: int = int(sim.run_state.calendar.get("round", 0))
	sim.autosave_now()
	assert_true(SaveManager.has_save(), "autosave_now writes a save mid-run")
	var data: Dictionary = SaveManager.load_run()
	assert_eq(str(data.get("phase", "")), "ROUND_PREP", "autosave records the live phase")
	assert_eq(
		int(Dictionary(data.get("run_state", {})).get("calendar", {}).get("round", 0)),
		round_number,
		"autosave records the live round"
	)
	assert_almost_eq(
		float(Dictionary(data.get("run_state", {})).get("economy", {}).get("cash", -1.0)),
		cash,
		0.01,
		"autosave records the live cash"
	)
	sim.free()


func _autosave_skips_idle() -> void:
	SaveManager.delete_save()
	var sim: Node = (load("res://core/simulation.gd") as GDScript).new()
	sim.autosave_enabled = true
	assert_eq(sim.phase, sim.Phase.IDLE, "fresh sim is IDLE")
	sim.autosave_now()
	assert_false(SaveManager.has_save(), "autosave_now is a no-op in IDLE")
	sim.free()


func _autosave_skips_when_disabled() -> void:
	SaveManager.delete_save()
	var sim: Node = _make_sim(312, false)
	sim.autosave_now()
	assert_false(SaveManager.has_save(), "autosave_now is a no-op when disabled")
	sim.free()


func _reload_round_trips_phase() -> void:
	SaveManager.delete_save()
	var sim: Node = _make_sim(313, true)
	sim.phase = sim.Phase.IN_ROUND
	sim.run_state.business["active_jobs"] = [{
		"id": "job.lifecycle",
		"name": "Lifecycle Job",
		"tokens_remaining": 40.0,
		"token_requirement": 80.0,
		"deadline_prompts": 5,
		"prompts_remaining": 4,
		"reward": 200.0,
		"quality": 10.0,
		"quality_threshold": 50.0,
	}]
	sim.autosave_now()
	assert_eq(str(SaveManager.load_run().get("phase", "")), "IN_ROUND", "envelope stores IN_ROUND")
	var restored: Node = (load("res://core/simulation.gd") as GDScript).new()
	restored.autosave_enabled = false
	assert_true(restored.load_saved_run(), "saved run loads")
	assert_eq(restored.phase, restored.Phase.IN_ROUND, "load restores IN_ROUND when work is still on the board")
	assert_eq(
		int(restored.run_state.calendar.get("round", 0)),
		int(sim.run_state.calendar.get("round", 0)),
		"load restores the saved round"
	)
	sim.free()
	restored.free()
