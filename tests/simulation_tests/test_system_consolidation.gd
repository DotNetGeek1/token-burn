extends TestCase

func run() -> void:
	_test_catalog_and_purchase_routes()
	_test_chapter_capacity_and_cooling()
	_test_legacy_conversion()
	_test_upgrade_changes_and_quotes()


func _sim(location: String = "bedroom") -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(1091)
	sim.apply_run_location(sim.run_state, location)
	sim.compute_system().recalculate(sim.run_state, sim.effect_resolver, [], sim.rng)
	sim.phase = sim.Phase.ROUND_PREP
	return sim


func _test_catalog_and_purchase_routes() -> void:
	var sim: Node = _sim()
	sim.run_state.economy["cash"] = 1e15
	assert_true(ContentDatabase.upgrades.is_empty(), "Retired catalogue is not active stock")
	assert_eq(ContentDatabase.legacy_upgrades.size(), 19, "All retired definitions remain available to old saves")
	for upgrade in ContentDatabase.legacy_upgrades:
		assert_false(sim.can_buy_upgrade(upgrade.id), "Cannot offer retired " + upgrade.id)
		assert_false(sim.buy_upgrade(upgrade.id), "Cannot buy retired " + upgrade.id)
	assert_eq(sim.run_state.build.get("hardware"), [], "Fresh cabinet owns no legacy machines")
	sim.free()


func _test_chapter_capacity_and_cooling() -> void:
	var previous_rate: float = 0.0
	for location in ContentDatabase.balance.economy.location_order:
		var sim: Node = _sim(str(location))
		var state: RunState = sim.run_state
		assert_true(float(state.compute.token_rate) > previous_rate, str(location) + " enters the next throughput scale")
		previous_rate = float(state.compute.token_rate)
		assert_eq(state.build.hardware, [], str(location) + " chapter uses systems only")
		assert_true(bool(sim.heat_outlook().get("sustainable", false)), str(location) + " can sustain its baseline")
		state.compute["heat"] = float(state.compute.heat_capacity) * 0.8
		assert_true(HeatSystem.ambient_delta(state) <= 0.0, str(location) + " cooling offsets ambient heat before venting")
		var cooling: float = 0.0
		for level in range(1, 5):
			CabinetSystems.set_tier(state, "cooling", level)
			var next: float = CabinetSystems.capacity(state, "cooling", "cooling_capacity")
			assert_true(next > cooling, str(location) + " every cooling tier improves its sink")
			cooling = next
		sim.free()


func _test_legacy_conversion() -> void:
	var state := RunState.new()
	state.from_dict({"save_version": 23, "build": {
		"dwelling": "garage", "hardware": ["used_laptop", "gpu_rack", "gpu_rack", "immersion_cooling"],
		"cabinet_systems": {"compute": 2, "cooling": 2, "power": 2, "backplane": 2, "control": 1},
		"upgrade_counts": {"upgrade.gpu_rack": 2, "upgrade.immersion_cooling": 1},
		"hardware_discount": 0.1,
	}, "economy": {"cash": 4567.0, "recurring_costs_base": 160.0}, "compute": {"heat_capacity": 180.0}})
	assert_eq(state.build.hardware, [], "Legacy hardware absorbed")
	assert_almost_eq(CabinetSystems.capacity(state, "compute", "base_token_rate"), 103000000.0, 1.0, "Old throughput and tier bonus preserved exactly once")
	assert_true(CabinetSystems.capacity(state, "cooling", "cooling_capacity") >= 607.0, "Installed cooling survives")
	assert_true(ComputeSystem.job_slots(state) >= 3, "Parallel capacity survives")
	assert_almost_eq(float(state.economy.cash), 4567.0, 0.01, "Conversion neither charges nor grants cash")
	assert_almost_eq(float(state.economy.recurring_costs_base), 160.0, 0.01, "Conversion preserves standing bills")
	assert_almost_eq(float(state.build.system_discount), 0.1, 0.001, "Unspent coupon migrated")
	var before: Dictionary = state.to_dict()
	var copy := RunState.new()
	copy.from_dict(before)
	assert_eq(copy.build.cabinet_legacy_floor, state.build.cabinet_legacy_floor, "Capacity floors round trip without stacking")
	for i in range(10):
		ComputeSystem.new().recalculate(copy, EffectResolver.new(), [], DeterministicRng.new(i))
	assert_almost_eq(float(copy.compute.local_capacity), 103000000.0, 1.0, "Recalculation cannot duplicate migrated capacity")


func _test_upgrade_changes_and_quotes() -> void:
	var sim: Node = _sim()
	var state: RunState = sim.run_state
	state.economy["cash"] = 100000.0
	state.build["system_discount"] = 0.1
	var quote: float = CabinetSystems.next_tier_cost(state, "compute")
	var cash: float = float(state.economy.cash)
	var before: float = float(state.compute.local_capacity)
	var bought: Dictionary = sim.upgrade_cabinet_system("compute")
	assert_true(bool(bought.ok), "Compute upgrade succeeds")
	assert_almost_eq(float(state.economy.cash), cash - quote, 0.01, "Quoted discounted cost is charged")
	assert_true(float(state.compute.local_capacity) > before, "Compute tier raises throughput without a machine")
	assert_almost_eq(float(state.build.system_discount), 0.0, 0.001, "Coupon consumed once")
	var lanes: int = sim.job_slots()
	assert_true(bool(sim.upgrade_cabinet_system("power").ok), "Power upgrade succeeds")
	assert_eq(sim.job_slots(), lanes + 1, "Power supplies another parallel lane")
	var cooling: float = float(state.compute.cooling)
	assert_true(bool(sim.upgrade_cabinet_system("cooling").ok), "Cooling upgrade succeeds")
	assert_true(float(state.compute.cooling) > cooling, "Cooling is refreshed immediately")
	sim.phase = sim.Phase.IN_ROUND
	cash = float(state.economy.cash)
	assert_false(bool(sim.upgrade_cabinet_system("control").ok), "Systems cannot be installed mid burn")
	assert_almost_eq(float(state.economy.cash), cash, 0.01, "Refusal preserves cash")
	sim.free()
