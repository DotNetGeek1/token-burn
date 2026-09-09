extends TestCase

## Wave 2: heat becomes temper. Bedroom fire is still 100%. From GPU Rack the
## bar has bands; from the cluster, recoverable faults; fire waits for 150%.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_bedroom_has_no_instability()
	_test_office_overclock_band()
	_test_redline_rerun_reaches_the_repeat_fold()
	_test_cluster_can_fault_without_ending_the_run()
	_test_fire_thresholds()
	_test_fault_expires()
	_test_heat_state_names_the_late_bands()
	_test_multiplier_pressure_curve()
	_test_million_multiplier_adds_pressure_to_instability()
	_test_multiplier_pressure_is_consumed_per_prompt()
	_test_endless_escalation_ramps_heat_and_faults()
	_test_endless_round_past_the_deadline_ramps_heat_and_faults()
	_test_fault_multiplier_reaches_the_roll()


func _test_multiplier_pressure_curve() -> void:
	var cfg := {"multiplier_pressure_coeff": 0.015}
	assert_eq(HeatSystem.multiplier_pressure(1.0, cfg), 0.0, "A ×1 burn has no multiplier pressure")
	assert_eq(HeatSystem.multiplier_pressure(0.5, cfg), 0.0, "A sub-×1 burn is clamped to none")
	assert_almost_eq(HeatSystem.multiplier_pressure(2.0, cfg), 0.015, 1e-6, "One doubling is one coefficient")
	assert_almost_eq(HeatSystem.multiplier_pressure(1024.0, cfg), 0.15, 1e-6, "Ten doublings are ten")
	assert_almost_eq(
		HeatSystem.multiplier_pressure(1_000_000.0, cfg), 0.299, 0.002,
		"×1M is worth about 0.3 instability before the clamp"
	)
	var previous: float = -1.0
	for mult in [1.0, 4.0, 64.0, 1e4, 1e6, 1e9, 1e15]:
		var pressure: float = HeatSystem.multiplier_pressure(float(mult), cfg)
		assert_true(pressure >= previous, "Multiplier pressure never falls as the multiplier grows")
		previous = pressure


func _test_million_multiplier_adds_pressure_to_instability() -> void:
	var heat := HeatSystem.new()
	var calm := _rig(["gpu_rack"], 0.0)
	heat.process_prompt(calm, [], EffectResolver.new(), DeterministicRng.new(3), ResolveMode.COMMIT)
	assert_eq(float(calm.compute.get("instability", -1.0)), 0.0, "A cold rack with a ×1 burn is stable")
	var big := _rig(["gpu_rack"], 0.0)
	big.compute["last_batch_multiplier"] = 1_000_000.0
	heat.process_prompt(big, [], EffectResolver.new(), DeterministicRng.new(3), ResolveMode.COMMIT)
	assert_almost_eq(
		float(big.compute.get("instability", 0.0)), 0.299, 0.002,
		"A ×1M burn on a cold rack adds ~0.3 instability"
	)
	var debug: Dictionary = HeatSystem.pressure_debug(big)
	assert_almost_eq(float(debug.get("multiplier_pressure", 0.0)), 0.299, 0.002, "The debug dict names the pressure")
	assert_eq(float(debug.get("heat_instability", -1.0)), 0.0, "And the heat component separately")
	assert_almost_eq(float(debug.get("batch_multiplier", 0.0)), 1_000_000.0, 0.5, "And the multiplier it saw")
	var hot := _rig(["gpu_rack"], 130.0)
	hot.compute["last_batch_multiplier"] = 1e30
	heat.process_prompt(hot, [], EffectResolver.new(), DeterministicRng.new(3), ResolveMode.COMMIT)
	assert_true(
		float(hot.compute.get("instability", 0.0)) <= 1.0,
		"Total instability is clamped at 1 after pressure is added"
	)
	assert_true(
		float(hot.compute.get("instability_multiplier_pressure", 0.0)) > 1.0,
		"But the raw pressure component is reported unclamped"
	)


func _test_multiplier_pressure_is_consumed_per_prompt() -> void:
	var heat := HeatSystem.new()
	var state := _rig(["gpu_rack"], 0.0)
	state.compute["last_batch_multiplier"] = 1024.0
	heat.process_prompt(state, [], EffectResolver.new(), DeterministicRng.new(4), ResolveMode.PREVIEW)
	assert_true(state.compute.has("last_batch_multiplier"), "A preview does not spend the burn's multiplier")
	heat.process_prompt(state, [], EffectResolver.new(), DeterministicRng.new(4), ResolveMode.COMMIT)
	assert_almost_eq(float(state.compute.get("instability", 0.0)), 0.15, 1e-6, "The commit reads it")
	assert_false(state.compute.has("last_batch_multiplier"), "And spends it")
	heat.process_prompt(state, [], EffectResolver.new(), DeterministicRng.new(4), ResolveMode.COMMIT)
	assert_eq(float(state.compute.get("instability", -1.0)), 0.0, "A prompt with no burn carries no pressure")


func _test_endless_escalation_ramps_heat_and_faults() -> void:
	var state := _rig(["used_laptop"], 10.0)
	assert_eq(HeatSystem.heat_gain_mult(state), 1.0, "A fresh run has no heat pressure")
	assert_eq(HeatSystem.fault_chance_mult(state), 1.0, "Or fault pressure")
	var tuning := {"heat": {"endless_heat_escalation": 1.05, "endless_fault_escalation": 1.08}}
	HeatSystem.escalate_endless(state, tuning)
	assert_almost_eq(float(state.compute.get("endless_heat_mult", 0.0)), 1.05, 1e-6, "One endless round ramps ambient heat 5%")
	assert_almost_eq(float(state.compute.get("endless_fault_mult", 0.0)), 1.08, 1e-6, "And fault chance 8%")
	for _i in range(9):
		HeatSystem.escalate_endless(state, tuning)
	assert_almost_eq(float(state.compute.get("endless_heat_mult", 0.0)), pow(1.05, 10), 1e-6, "Ten rounds compound")
	assert_almost_eq(float(state.compute.get("endless_fault_mult", 0.0)), pow(1.08, 10), 1e-6, "Uncapped")
	assert_almost_eq(HeatSystem.heat_gain_mult(state), pow(1.05, 10), 1e-6, "The heat pass reads the ramp")
	# Ambient gain follows the multiplier; ambient cooling does not.
	state.compute["power_draw"] = 100.0
	state.compute["cooling"] = 0.0
	var base: float = HeatSystem.generation(100.0)
	assert_almost_eq(HeatSystem.ambient_delta(state), base * pow(1.05, 10), 1e-4, "Positive ambient heat is scaled")
	state.compute["power_draw"] = 0.0
	state.compute["cooling"] = 100.0
	assert_almost_eq(HeatSystem.ambient_delta(state), -HeatSystem.sink(100.0), 1e-4, "Cooling is left alone")
	# Pipeline heat follows it too, but only heat the pipeline adds.
	assert_almost_eq(HeatSystem.scale_pipeline_heat(state, 10.0), 10.0 * pow(1.05, 10), 1e-4, "Pipeline heat is scaled")
	assert_almost_eq(HeatSystem.scale_pipeline_heat(state, -10.0), -10.0, 1e-4, "A cooling stage is not")
	# The default config path works without an explicit tuning dictionary.
	var plain := _rig(["used_laptop"], 10.0)
	HeatSystem.escalate_endless(plain)
	assert_true(float(plain.compute.get("endless_heat_mult", 1.0)) > 1.0, "escalate_endless reads economy.heat by default")
	assert_true(float(plain.compute.get("endless_fault_mult", 1.0)) > 1.0, "For both multipliers")


## The lifecycle hook: ending a round past the contract deadline in a run that
## carried on past its victory ramps heat and fault pressure alongside the
## rent and power creep, and a round inside the calendar leaves them alone.
func _test_endless_round_past_the_deadline_ramps_heat_and_faults() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(9203)
	# Enough cash that the bills past the deadline never end the run.
	sim.run_state.economy["cash"] = 1e9
	sim.run_state.calendar["round"] = 1
	sim.debug_end_round()
	assert_eq(float(sim.run_state.compute.get("endless_heat_mult", 1.0)), 1.0, "A round inside the calendar adds no endless heat pressure")
	assert_eq(float(sim.run_state.compute.get("endless_fault_mult", 1.0)), 1.0, "Or fault pressure")

	sim.run_state.flags["post_victory"] = true
	# Well past any contract's deadline, whatever the chapter's terms.
	sim.run_state.calendar["round"] = sim.ROUNDS_PER_RUN * 3
	var rent_before: float = float(sim.run_state.economy.get("round_rent", 0.0))
	sim.debug_end_round()
	assert_true(sim.phase != sim.Phase.RUN_END, "A post-victory run is not ended by the deadline")
	assert_true(float(sim.run_state.economy.get("round_rent", 0.0)) > rent_before, "The bills climb")
	var cfg: Dictionary = HeatSystem.heat_config()
	assert_almost_eq(
		float(sim.run_state.compute.get("endless_heat_mult", 1.0)),
		maxf(1.0, float(cfg.get("endless_heat_escalation", 1.05))), 1e-6,
		"And one endless round ramps ambient heat by the configured step"
	)
	assert_almost_eq(
		float(sim.run_state.compute.get("endless_fault_mult", 1.0)),
		maxf(1.0, float(cfg.get("endless_fault_escalation", 1.08))), 1e-6,
		"And fault chance by its step"
	)
	assert_true(HeatSystem.heat_gain_mult(sim.run_state) > 1.0, "Which the heat pass reads")
	sim.debug_end_round()
	assert_almost_eq(
		float(sim.run_state.compute.get("endless_heat_mult", 1.0)),
		pow(maxf(1.0, float(cfg.get("endless_heat_escalation", 1.05))), 2), 1e-6,
		"A second round past the deadline compounds"
	)
	sim.free()


func _test_fault_multiplier_reaches_the_roll() -> void:
	var heat := HeatSystem.new()
	var never := _rig(["compute_cluster"], 95.0)
	never.compute["endless_fault_mult"] = 0.0
	for i in range(32):
		never.compute["heat"] = 95.0
		heat.process_prompt(never, [], EffectResolver.new(), DeterministicRng.new(500 + i), ResolveMode.COMMIT)
	assert_false(_has_fault(never), "A zero fault multiplier means no rack ever drops")
	var always := _rig(["compute_cluster"], 95.0)
	always.compute["depth_fault_mult"] = 1e6
	heat.process_prompt(always, [], EffectResolver.new(), DeterministicRng.new(501), ResolveMode.COMMIT)
	assert_true(_has_fault(always), "A huge fault multiplier drops a rack on the first hot prompt")
	assert_almost_eq(HeatSystem.fault_chance_mult(always), 1e6, 1.0, "Endless and depth multipliers compose uncapped")


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
	sim.apply_infrastructure_tier(sim.run_state, InfrastructureSystem.tier_for_room("office_unit"))
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	return sim


func _has_fault(state: RunState) -> bool:
	for status in Array(state.build.get("status_effects", [])):
		if status is Dictionary and str(status.get("id", "")) == "status.fault.dead_rack":
			return true
	return false
