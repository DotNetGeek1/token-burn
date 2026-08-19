extends TestCase

## Wave 0.A: bedroom heat stays generation − sink; from GPU Rack onward ambient
## heat is a slice of the local bar so megawatt cooling cannot erase an
## Overclock-sized kick.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_bedroom_uses_generation_minus_sink()
	_test_office_rack_is_warm()
	_test_moon_campus_stays_on_the_bar()
	_test_overclock_scale_moves_the_moon_bar()
	_test_outlook_matches_ambient_delta()


func _test_bedroom_uses_generation_minus_sink() -> void:
	var sim: Node = _sim_at("bedroom", 8801)
	var power: float = float(sim.run_state.compute.get("power_draw", 0.0))
	var cooling: float = float(sim.run_state.compute.get("cooling", 0.0))
	var expected: float = HeatSystem.generation(power) - HeatSystem.sink(cooling)
	assert_almost_eq(
		HeatSystem.ambient_delta(sim.run_state), expected, 0.01,
		"Bedroom ambient heat is still generation minus sink"
	)
	sim.free()


func _test_office_rack_is_warm() -> void:
	var sim: Node = _sim_at("office_unit", 8802)
	assert_true(HeatSystem.work_tier(sim.run_state) >= 2, "The office starts on a GPU rack")
	assert_true(
		HeatSystem.ambient_delta(sim.run_state) > 0.0,
		"A stock office rack still produces a little ambient heat"
	)
	sim.free()


func _test_moon_campus_stays_on_the_bar() -> void:
	var sim: Node = _sim_at("moon_facility", 8803)
	var capacity: float = maxf(1.0, float(sim.run_state.compute.get("heat_capacity", 100.0)))
	var delta: float = HeatSystem.ambient_delta(sim.run_state)
	assert_true(
		absf(delta) < capacity * 0.2,
		"Moon ambient heat stays on the local bar (delta %.1f, capacity %.0f)" % [delta, capacity]
	)
	sim.free()


func _test_overclock_scale_moves_the_moon_bar() -> void:
	var sim: Node = _sim_at("moon_facility", 8804)
	var capacity: float = maxf(1.0, float(sim.run_state.compute.get("heat_capacity", 100.0)))
	var before: float = float(sim.run_state.compute.get("heat", 0.0))
	HeatSystem.apply_pipeline_heat(sim.heat_system(), sim.run_state, 18.0)
	var gained: float = float(sim.run_state.compute.get("heat", 0.0)) - before
	assert_true(
		gained >= capacity * 0.05,
		"An Overclock-scale apply is at least 5%% of the moon bar (gained %.1f of %.0f)" % [
			gained, capacity,
		]
	)
	sim.free()


func _test_outlook_matches_ambient_delta() -> void:
	for location in ["bedroom", "office_unit", "moon_facility"]:
		var sim: Node = _sim_at(location, 8805)
		var outlook: Dictionary = sim.heat_outlook()
		assert_almost_eq(
			float(outlook.get("heat_per_prompt", 0.0)),
			HeatSystem.ambient_delta(sim.run_state),
			0.01,
			"%s outlook heat_per_prompt matches HeatSystem.ambient_delta" % location
		)
		sim.free()


func _sim_at(location: String, seed_value: int) -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(seed_value)
	if location != "bedroom":
		sim.apply_run_location(sim.run_state, location)
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	return sim
