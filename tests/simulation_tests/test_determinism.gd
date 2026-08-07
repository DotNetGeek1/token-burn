extends TestCase


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var sim_script: GDScript = load("res://core/simulation.gd")

	var sim_a: Node = sim_script.new()
	sim_a.autosave_enabled = false
	sim_a.start_run(777)
	_drive_to_same_point(sim_a)

	var sim_b: Node = sim_script.new()
	sim_b.autosave_enabled = false
	sim_b.start_run(777)
	_drive_to_same_point(sim_b)

	assert_eq(sim_a.run_state.economy.get("cash", 0.0), sim_b.run_state.economy.get("cash", 0.0), "Same seed same cash")
	assert_eq(sim_a.run_state.calendar.get("round", 0), sim_b.run_state.calendar.get("round", 0), "Same seed same round")
	assert_eq(sim_a.run_state.statistics.get("lifetime_tokens", 0.0), sim_b.run_state.statistics.get("lifetime_tokens", 0.0), "Same seed same tokens")
	_test_rng_injected_on_dispatch(sim_a)
	sim_a.free()
	sim_b.free()


func _test_rng_injected_on_dispatch(sim: Node) -> void:
	sim.effect_resolver.begin_action("rng.test")
	var mod_ctx := ModifierContext.new("prompt.started", sim.run_state)
	mod_ctx.rng = sim.rng.derive("prompt.started")
	mod_ctx.set_value("job.reward", 10.0)
	var subs: Array = [{
		"event": "prompt.started",
		"priority": 0,
		"source_id": "test.reroll",
		"conditions": [],
		"effects": [{"operation": "reroll", "target": "job.reward", "value": {"min": 1.0, "max": 5.0}}],
	}]
	sim.effect_resolver.dispatch("prompt.started", mod_ctx, subs)
	var breakdown: Dictionary = sim.query_effect_breakdown("job.reward", "rng.test")
	assert_true(breakdown.get("entries", []).size() >= 1, "Simulation exposes effect trace breakdown")


func _drive_to_same_point(sim: Node) -> void:
	var offers: Array = sim.run_state.business.get("job_offers", [])
	if offers.is_empty():
		return
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work_sync()
