extends TestCase

## Shop cards show raw curve rates; the HUD applies modifiers. These tests
## guard the buy path and the presentation helpers that bridge the two.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_gpu_rack_adds_full_rate_without_modifiers()
	_test_gpu_rack_respects_efficiency_debuff()
	_test_cooling_shortfall_reports_heat_per_prompt()
	_test_effect_line_shows_effective_rate_when_modified()
	_test_current_rate_scale_matches_recalculation()


## A rack belongs to the garage chapter, so these run there rather than buying
## their way out of a bedroom.
func _make_sim(run_seed: int = 601, location: String = "garage") -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(run_seed)
	# What one rack contributes, measured against a bare room: the machine the
	# garage comes with would otherwise be folded into the delta.
	sim.apply_run_location(sim.run_state, location, false)
	sim.run_state.economy["cash"] = 500_000.0
	return sim


func _test_gpu_rack_adds_full_rate_without_modifiers() -> void:
	var sim := _make_sim(601)
	var before: float = float(sim.run_state.compute.get("token_rate", 0.0))
	assert_true(sim.buy_upgrade("upgrade.gpu_rack"), "GPU rack purchased")
	var after: float = float(sim.run_state.compute.get("token_rate", 0.0))
	assert_almost_eq(
		after - before,
		50_000_000.0,
		1.0,
		"GPU rack adds the full 50M curve rate when nothing is throttling the rig"
	)
	sim.free()


func _test_gpu_rack_respects_efficiency_debuff() -> void:
	var sim := _make_sim(602)
	sim.run_state.compute["efficiency_base"] = 0.82
	sim._compute_system.recalculate(
		sim.run_state, sim.effect_resolver, sim._collect_subscriptions(), sim.rng
	)
	var before: float = float(sim.run_state.compute.get("token_rate", 0.0))
	assert_true(sim.buy_upgrade("upgrade.gpu_rack"), "GPU rack purchased under debuff")
	var after: float = float(sim.run_state.compute.get("token_rate", 0.0))
	assert_almost_eq(
		after - before,
		50_000_000.0 * 0.82,
		50_000.0,
		"GPU rack contribution scales with the current efficiency debuff"
	)
	sim.free()


func _test_cooling_shortfall_reports_heat_per_prompt() -> void:
	var prior_autosave: bool = Simulation.autosave_enabled
	Simulation.autosave_enabled = false
	Simulation.start_run(603)
	Simulation.apply_run_location(Simulation.run_state, "garage")
	Simulation.run_state.economy["cash"] = 500_000.0
	var gpu_rack: UpgradeDefinition = ContentDatabase.get_upgrade("upgrade.gpu_rack")
	assert_true(gpu_rack != null, "GPU rack upgrade exists")
	var shortfall: Dictionary = UpgradePresentation.cooling_shortfall(gpu_rack)
	assert_false(shortfall.is_empty(), "A rack in the garage should warn about cooling")
	assert_true(
		float(shortfall.get("heat_per_prompt", 0.0)) > 0.0,
		"Cooling shortfall reports heat per prompt, not zero"
	)
	Simulation.autosave_enabled = prior_autosave


func _test_effect_line_shows_effective_rate_when_modified() -> void:
	var prior_autosave: bool = Simulation.autosave_enabled
	Simulation.autosave_enabled = false
	Simulation.start_run(604)
	Simulation.run_state.compute["efficiency_base"] = 0.82
	Simulation._compute_system.recalculate(
		Simulation.run_state,
		Simulation.effect_resolver,
		Simulation._collect_subscriptions(),
		Simulation.rng,
	)
	var gpu_rack: UpgradeDefinition = ContentDatabase.get_upgrade("upgrade.gpu_rack")
	var line: String = UpgradePresentation.effect_line(gpu_rack)
	assert_true(
		line.contains("(41.0M/prompt now)"),
		"Market line shows the effective contribution when modifiers are active (%s)" % line
	)
	Simulation.autosave_enabled = prior_autosave


func _test_current_rate_scale_matches_recalculation() -> void:
	var compute := ComputeSystem.new()
	var resolver := EffectResolver.new()
	var state := RunState.new()
	var rng := DeterministicRng.new(605)
	resolver.apply_effects(
		state,
		[{"operation": "multiply", "target": "compute.efficiency_base", "value": 0.82}],
		"event.test"
	)
	compute.recalculate(state, resolver, [], rng)
	var expected: float = float(state.compute.get("token_rate", 0.0)) / float(
		state.compute.get("local_capacity", 1.0)
	)
	assert_almost_eq(
		ComputeSystem.current_rate_scale(state),
		expected,
		0.0001,
		"Rate scale matches the ratio the HUD uses after recalculation"
	)
