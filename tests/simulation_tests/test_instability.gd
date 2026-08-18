extends TestCase

## Wave 2: heat becomes temper. Bedroom fire is still 100%. From GPU Rack the
## bar has bands; from the cluster, recoverable faults; fire waits for 150%.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_bedroom_has_no_instability()
	_test_office_overclock_band()
	_test_cluster_can_fault_without_ending_the_run()
	_test_fire_thresholds()
	_test_fault_expires()


func _test_bedroom_has_no_instability() -> void:
	assert_eq(HeatSystem.instability_from_ratio(0.90, 0), 0.0, "Bedroom heat has no instability")
	assert_eq(HeatSystem.overclock_band_bonus(0.75, 0), 1.0, "And no overclock band")
	assert_eq(HeatSystem.catastrophe_ratio(0), 1.0, "Bedroom fire is still the old 100% line")
	var state := _rig(["used_laptop"], 90.0)
	var heat := HeatSystem.new()
	heat.process_prompt(state, [], EffectResolver.new(), DeterministicRng.new(1), ResolveMode.COMMIT)
	assert_eq(float(state.compute.get("instability", -1.0)), 0.0, "A laptop never derives instability")
	assert_eq(Array(state.build.get("status_effects", [])).size(), 0, "And never rolls a rack fault")


func _test_office_overclock_band() -> void:
	assert_true(HeatSystem.instability_from_ratio(0.75, 2) > 0.0, "A rack at 75% is unstable")
	assert_true(HeatSystem.overclock_band_bonus(0.75, 2) > 1.0, "And the overclock band pays")
	var cold := _sim_office(9201)
	cold.run_state.compute["heat"] = 0.0
	cold.compute_system().recalculate(
		cold.run_state, cold.effect_resolver, cold.debug_collect_subscriptions(), cold.rng
	)
	var cold_rate: float = float(cold.run_state.compute.get("token_rate", 0.0))
	var hot := _sim_office(9201)
	hot.run_state.compute["heat"] = float(hot.run_state.compute.get("heat_capacity", 100.0)) * 0.75
	hot.compute_system().recalculate(
		hot.run_state, hot.effect_resolver, hot.debug_collect_subscriptions(), hot.rng
	)
	assert_true(
		float(hot.run_state.compute.get("token_rate", 0.0)) >= cold_rate,
		"75% heat on a GPU rack is at least as fast as a cold rack"
	)
	cold.free()
	hot.free()


func _test_cluster_can_fault_without_ending_the_run() -> void:
	var found := false
	var heat := HeatSystem.new()
	var progression := ProgressionSystem.new()
	for seed_value in range(40):
		var state := _rig(["compute_cluster"], 90.0)
		state.compute["power_draw"] = 0.0
		state.compute["cooling"] = 0.0
		for _i in range(8):
			state.compute["heat"] = 90.0
			heat.process_prompt(
				state, [], EffectResolver.new(), DeterministicRng.new(seed_value * 17 + _i),
				ResolveMode.COMMIT
			)
			if _has_fault(state):
				found = true
				assert_true(
					float(state.statistics.get("faults_suffered", 0)) >= 1.0,
					"A fault is counted"
				)
				assert_false(progression.check_loss(state), "A dead rack is not a run end")
				break
		if found:
			break
	assert_true(found, "A cluster sitting at 90% heat can lose a rack")


func _test_fire_thresholds() -> void:
	var bedroom := _rig(["used_laptop"], 100.0)
	bedroom.flags["fire_risk"] = true
	var progression := ProgressionSystem.new()
	assert_true(progression.check_loss(bedroom), "A bedroom fire still lands at 100%")

	var cluster := _rig(["compute_cluster"], 100.0)
	cluster.flags["fire_risk"] = true
	assert_false(progression.check_loss(cluster), "A cluster at 100% heat is not a fire loss")
	cluster.compute["heat"] = 150.0
	assert_true(progression.check_loss(cluster), "A cluster fire waits for 150%")


func _test_fault_expires() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(9202)
	sim.run_state.build["status_effects"] = [{
		"id": "status.fault.dead_rack",
		"name": "Rack offline",
		"rounds": 2,
		"subscriptions": [],
	}]
	sim.debug_invalidate_subscriptions()
	sim._expire_status_effects()
	assert_eq(sim.run_state.build["status_effects"].size(), 1, "A two-round fault survives one expiry")
	sim._expire_status_effects()
	assert_eq(sim.run_state.build["status_effects"].size(), 0, "And is gone after the second")
	sim.free()


func _rig(hardware: Array, heat: float) -> RunState:
	var state := RunState.new()
	state.build["hardware"] = hardware.duplicate()
	state.compute["heat"] = heat
	state.compute["heat_capacity"] = 100.0
	state.compute["power_draw"] = 0.0
	state.compute["cooling"] = 0.0
	return state


func _sim_office(seed_value: int) -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(seed_value)
	sim.apply_run_location(sim.run_state, "office_unit")
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	return sim


func _has_fault(state: RunState) -> bool:
	for status in Array(state.build.get("status_effects", [])):
		if status is Dictionary and str(status.get("id", "")) == "status.fault.dead_rack":
			return true
	return false
