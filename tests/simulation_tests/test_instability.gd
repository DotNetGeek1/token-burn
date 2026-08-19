extends TestCase

## Wave 2: heat becomes temper. Bedroom fire is still 100%. From GPU Rack the
## bar has bands; from the cluster, recoverable faults; fire waits for 150%.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_bedroom_has_no_instability()
	_test_office_overclock_band()
	_test_overclock_does_not_accelerate_cloud()
	_test_redline_rerun_reaches_the_repeat_fold()
	_test_cluster_can_fault_without_ending_the_run()
	_test_fire_thresholds()
	_test_fault_expires()
	_test_heat_state_names_the_late_bands()


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


func _test_overclock_does_not_accelerate_cloud() -> void:
	var cold := _sim_office(9203)
	cold.run_state.compute["cloud_capacity"] = 50000.0
	cold.run_state.compute["heat"] = 0.0
	cold.compute_system().recalculate(
		cold.run_state, cold.effect_resolver, cold.debug_collect_subscriptions(), cold.rng
	)
	var cold_local: float = float(cold.run_state.compute.get("local_rate", 0.0))
	var cold_cloud: float = float(cold.run_state.compute.get("cloud_rate", 0.0))
	assert_true(cold_cloud > 0.0, "The office has rented compute to compare")
	var hot := _sim_office(9203)
	hot.run_state.compute["cloud_capacity"] = 50000.0
	hot.run_state.compute["heat"] = float(hot.run_state.compute.get("heat_capacity", 100.0)) * 0.75
	hot.compute_system().recalculate(
		hot.run_state, hot.effect_resolver, hot.debug_collect_subscriptions(), hot.rng
	)
	assert_almost_eq(
		float(hot.run_state.compute.get("cloud_rate", 0.0)), cold_cloud, 0.01,
		"A hot rack does not overclock rented compute"
	)
	assert_true(
		float(hot.run_state.compute.get("local_rate", 0.0)) > cold_local,
		"The overclock bonus lands on the local machines"
	)
	cold.free()
	hot.free()


func _test_redline_rerun_reaches_the_repeat_fold() -> void:
	var hit := false
	for seed_value in range(80):
		var board := BoardSystem.new()
		var state := RunState.new()
		board.ensure_board(state, ContentDatabase)
		state.build["hardware"] = ["gpu_rack"]
		state.build["modules"] = ["op.prompt", "op.fractal_split"]
		state.compute["heat"] = 140.0
		state.compute["heat_capacity"] = 100.0
		var slots: Array = board.slots(state)
		for i in range(slots.size()):
			slots[i] = str(["op.prompt", "op.fractal_split"][i]) if i < 2 else ""
		var job := {
			"id": "job.redline",
			"name": "Redline",
			"token_requirement": 10000.0,
			"tokens_remaining": 10000.0,
			"quality": 0.0,
			"quality_threshold": 0.0,
			"known_bugs": 0,
			"hidden_bugs": 0,
			"blocked_slots": 0,
			"board_rules": [],
			"tags": [],
		}
		var result: Dictionary = board.resolve_burn(
			state, job, 1000.0, DeterministicRng.new(seed_value + 9600), EffectResolver.new(), []
		)
		var split: Dictionary = {}
		for stage in result.get("stages", []):
			if stage is Dictionary and str(stage.get("module_id", "")) == "op.fractal_split":
				split = stage
				break
		if split.is_empty() or bool(split.get("dropped", false)):
			continue
		if int(split.get("repeat_count", 0)) > 2:
			hit = true
			break
	assert_true(hit, "A redline rerun increases the repeat fold, not just stage heat")


func _test_cluster_can_fault_without_ending_the_run() -> void:
	var found := false
	var heat := HeatSystem.new()
	var progression := ProgressionSystem.new()
	for seed_value in range(64):
		var state := _rig(["compute_cluster"], 90.0)
		state.compute["power_draw"] = 0.0
		state.compute["cooling"] = 0.0
		for _i in range(16):
			# Ambient can vent a little; hold the bar in the fault band after that.
			state.compute["heat"] = 120.0
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


func _test_heat_state_names_the_late_bands() -> void:
	assert_eq(HeatSystem.heat_state(1.0, 0), HeatSystem.HEAT_FIRE, "Bedroom 100% is still FIRE")
	assert_eq(HeatSystem.heat_state_label(HeatSystem.HEAT_FIRE), "FIRE", "And it is labelled FIRE")
	assert_eq(HeatSystem.heat_state(0.82, 2), HeatSystem.HEAT_THROTTLE, "A rack at 82% is THROTTLE")
	assert_eq(HeatSystem.heat_state(0.90, 2), HeatSystem.HEAT_UNSTABLE, "Then UNSTABLE")
	assert_eq(HeatSystem.heat_state(1.10, 2), HeatSystem.HEAT_REDLINE, "100–140% is REDLINE, not fire")
	assert_eq(HeatSystem.heat_state(1.40, 2), HeatSystem.HEAT_FIRE_RISK, "140% is FIRE RISK")
	assert_eq(HeatSystem.heat_state(1.50, 2), HeatSystem.HEAT_CATASTROPHE, "150% is CATASTROPHE")
	var late := _rig(["gpu_rack"], 110.0)
	var outlook := {}
	HeatSystem.decorate_heat_outlook(outlook, 90.0, late)
	assert_eq(str(outlook.get("heat_state", "")), HeatSystem.HEAT_REDLINE, "A 110% forecast is redline")
	assert_eq(str(outlook.get("heat_state_label", "")), "REDLINE", "The Burn Board can print REDLINE")
	assert_false(bool(outlook.get("crosses_fire", true)), "Redline is not a fire")
	assert_false(bool(outlook.get("crosses_catastrophe", true)), "And does not cross the kill line")
	late.compute["heat"] = 155.0
	var lethal := {}
	HeatSystem.decorate_heat_outlook(lethal, 130.0, late)
	assert_eq(str(lethal.get("heat_state", "")), HeatSystem.HEAT_CATASTROPHE, "155% is catastrophe")
	assert_true(bool(lethal.get("crosses_catastrophe", false)), "Crossing 150% is the kill line")
	assert_true(bool(lethal.get("crosses_fire", false)), "crosses_fire follows the kill line")


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
