extends TestCase

## Reproduces early-game reports: token rate drifting down and COOL adding heat.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_sustained_rate_stable_without_overheating()
	_test_realistic_early_burns_track_heat_and_rate()
	_test_cool_only_adds_heat_when_vent_is_tiny()
	_test_heat_throttle_does_not_stack()
	_test_same_source_rate_modifier_replaces()
	_test_bedroom_sustains_starting_laptop()


func _test_bedroom_sustains_starting_laptop() -> void:
	var outlook: Dictionary = Simulation.heat_outlook()
	assert_true(
		bool(outlook.get("sustainable", false)),
		"Starting bedroom cooling should keep up with the used laptop (need %d, have %d)" % [
			int(ceil(float(outlook.get("cooling_needed", 0.0)))),
			int(outlook.get("cooling", 0.0)),
		]
	)
	assert_true(
		float(outlook.get("heat_per_prompt", 0.0)) <= 0.0,
		"Ambient heat should not climb every prompt before any burns"
	)


func _test_same_source_rate_modifier_replaces() -> void:
	var state := RunState.new()
	state.add_rate_modifier(0.75, 1, "heat_throttle")
	state.add_rate_modifier(0.75, 1, "heat_throttle")
	var count: int = 0
	for entry in state.compute.get("rate_modifiers", []):
		if entry is Dictionary and str(entry.get("source", "")) == "heat_throttle":
			count += 1
	assert_eq(count, 1, "Same-source modifiers replace rather than stack")


func _make_sim(seed: int = 777) -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(seed)
	return sim


func _test_sustained_rate_stable_without_overheating() -> void:
	var sim := _make_sim(777)
	sim.run_state.business["job_queue"] = [{
		"id": "job.rate_check",
		"name": "Rate Check",
		"token_requirement": 50_000_000.0,
		"tokens_remaining": 50_000_000.0,
		"deadline_prompts": 99,
		"prompts_remaining": 99,
		"reward": 500.0,
		"quality": 0.0,
		"quality_threshold": 0.0,
		"revision_risk": 0.0,
		"bug_chance": 0.0,
	}]
	sim.start_work()

	var baseline: float = float(sim.run_state.compute.get("token_rate", 0.0))
	assert_true(baseline > 0.0, "Baseline rate is positive")

	# Keep heat low so throttling never engages; sustained rate must not drift.
	sim.run_state.compute["heat"] = 0.0
	for i in range(12):
		sim.run_state.compute["heat"] = 0.0
		var before: float = float(sim.run_state.compute.get("token_rate", 0.0))
		var result: Dictionary = sim.burn_batch()
		assert_true(result.get("ok", false), "Burn %d succeeds" % i)
		var after: float = float(sim.run_state.compute.get("token_rate", 0.0))
		assert_almost_eq(after, baseline, 0.01, "Sustained rate stays flat on burn %d (%s vs %s)" % [
			i, NumberFormat.format_token_rate(after), NumberFormat.format_token_rate(baseline),
		])
		assert_almost_eq(after, before, 0.01, "Rate does not drop stepwise on burn %d" % i)
	sim.free()


func _test_realistic_early_burns_track_heat_and_rate() -> void:
	var sim := _make_sim(779)
	sim.run_state.business["job_queue"] = [{
		"id": "job.long_early",
		"name": "Long Early Job",
		"token_requirement": 500_000_000.0,
		"tokens_remaining": 500_000_000.0,
		"deadline_prompts": 99,
		"prompts_remaining": 99,
		"reward": 500.0,
		"quality": 0.0,
		"quality_threshold": 0.0,
		"revision_risk": 0.0,
		"bug_chance": 0.0,
	}]
	sim.start_work()
	# Force a hot stage so pipeline heat is visible; ambient alone is now sustainable.
	var slots: Array = sim.board_slots()
	if slots.size() > 2:
		slots[2] = "op.agent_swarm"
		sim.run_state.build["board"]["slots"] = slots

	var baseline: float = float(sim.run_state.compute.get("token_rate", 0.0))
	var rates: Array[float] = []
	var heats: Array[float] = []
	for i in range(12):
		rates.append(float(sim.run_state.compute.get("token_rate", 0.0)))
		heats.append(float(sim.run_state.compute.get("heat", 0.0)))
		var result: Dictionary = sim.burn_batch()
		assert_true(result.get("ok", false), "Realistic burn %d succeeds" % i)

	# Sustained rate should only step down when heat throttling engages, not every prompt.
	var throttle_hits: int = 0
	for i in range(1, rates.size()):
		if rates[i] + 0.01 < rates[i - 1]:
			throttle_hits += 1
	assert_true(throttle_hits <= 1, "Rate stepped down at most once before heavy heat (drops=%d, rates=%s)" % [
		throttle_hits, rates,
	])
	# Once throttled, rate should plateau rather than keep falling.
	if throttle_hits > 0:
		var throttled: float = rates[-1]
		assert_almost_eq(throttled, baseline * 0.75, baseline * 0.01, "Throttle is a single 25% cut")
	assert_true(heats[-1] > heats[0], "Natural play should build heat in a bedroom (%s -> %s)" % [heats[0], heats[-1]])
	sim.free()


func _test_cool_only_adds_heat_when_vent_is_tiny() -> void:
	var sim := _make_sim(778)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work()

	sim.run_state.compute["heat"] = 30.0
	var preview: Dictionary = sim.preview_cool()
	assert_true(preview.get("ok", false), "Cool preview works")
	assert_true(
		float(preview.get("total_heat", 0.0)) < 0.0,
		"At moderate heat COOL should net negative"
	)

	sim.run_state.compute["heat"] = 5.0
	preview = sim.preview_cool()
	assert_true(
		float(preview.get("total_heat", 0.0)) < 0.0,
		"Starting bedroom cooling lets COOL shed heat even at low levels"
	)
	sim.free()


func _test_heat_throttle_does_not_stack() -> void:
	var state := RunState.new()
	var heat := HeatSystem.new()
	var resolver := EffectResolver.new()
	var rng := DeterministicRng.new(9)
	state.compute["heat"] = 95.0

	for _i in range(12):
		state.tick_rate_modifiers()
		heat.process_prompt(state, [], resolver, rng)

	var throttle_count: int = 0
	for entry in state.compute.get("rate_modifiers", []):
		if entry is Dictionary and str(entry.get("source", "")) == "heat_throttle":
			throttle_count += 1
	assert_eq(throttle_count, 1, "Heat throttle replaces rather than stacks")

	var compute := ComputeSystem.new()
	compute.recalculate(state, resolver, [], rng)
	var throttled: float = float(state.compute.get("token_rate", 0.0))
	state.tick_rate_modifiers()
	compute.recalculate(state, resolver, [], rng)
	assert_true(
		float(state.compute.get("token_rate", 0.0)) > throttled,
		"Throttle lifts after it expires"
	)
