extends TestCase


func run() -> void:
	_test_wide_bus_slots_derive_from_active_perk()
	_test_benching_wide_bus_shrinks_slots()
	_test_technical_debt_loan_once()
	_test_wrapper_freezes_passive_value()


func _sim() -> Node:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	return sim


func _test_wide_bus_slots_derive_from_active_perk() -> void:
	var sim := _sim()
	sim.start_run(8901)
	var board := BoardSystem.new()
	var before: int = board.derived_slot_count(sim.run_state, ContentDatabase)
	sim._perk_system.collect_perk(sim.run_state, "perk.stack_overflow_tab", ContentDatabase)
	sim._perk_system.equip_perk(sim.run_state, "perk.stack_overflow_tab", ContentDatabase)
	sim._perk_system.collect_perk(sim.run_state, "perk.wide_bus", ContentDatabase)
	sim._perk_system.equip_perk(sim.run_state, "perk.wide_bus", ContentDatabase)
	sim._board_system.ensure_board(sim.run_state, ContentDatabase)
	assert_eq(
		board.derived_slot_count(sim.run_state, ContentDatabase),
		before + 1,
		"Wide Bus adds one derived slot while active"
	)
	sim.free()


func _test_benching_wide_bus_shrinks_slots() -> void:
	var sim := _sim()
	sim.start_run(8902)
	sim._perk_system.collect_perk(sim.run_state, "perk.stack_overflow_tab", ContentDatabase)
	sim._perk_system.equip_perk(sim.run_state, "perk.stack_overflow_tab", ContentDatabase)
	sim._perk_system.collect_perk(sim.run_state, "perk.wide_bus", ContentDatabase)
	sim._perk_system.equip_perk(sim.run_state, "perk.wide_bus", ContentDatabase)
	sim._board_system.ensure_board(sim.run_state, ContentDatabase)
	var with_bus: int = BoardSystem.new().derived_slot_count(sim.run_state, ContentDatabase)
	sim._perk_system.bench_perk(sim.run_state, "perk.wide_bus", ContentDatabase)
	sim._board_system.ensure_board(sim.run_state, ContentDatabase)
	var without_bus: int = BoardSystem.new().derived_slot_count(sim.run_state, ContentDatabase)
	assert_eq(without_bus, with_bus - 1, "Benching Wide Bus removes its slot bonus")
	sim.free()


func _test_technical_debt_loan_once() -> void:
	var sim := _sim()
	sim.start_run(8903)
	var cash_before: float = float(sim.run_state.economy.get("cash", 0.0))
	var debt_before: float = float(sim.run_state.economy.get("debt", 0.0))
	sim.collect_perk("perk.technical_debt")
	var cash_after_first: float = float(sim.run_state.economy.get("cash", 0.0))
	var debt_after_first: float = float(sim.run_state.economy.get("debt", 0.0))
	assert_true(cash_after_first > cash_before, "Technical Debt grants cash on first collect")
	assert_true(debt_after_first > debt_before, "Technical Debt records debt on first collect")
	var statuses: Array = Array(sim.run_state.build.get("status_effects", []))
	assert_eq(statuses.size(), 1, "Pickup leaves one permanent liability behind")
	sim.equip_perk("perk.technical_debt")
	sim.bench_perk("perk.technical_debt")
	assert_eq(
		Array(sim.run_state.build.get("status_effects", [])).size(),
		1,
		"Benching Technical Debt does not remove the liability"
	)
	sim._dispatch_perk_acquired("perk.technical_debt")
	assert_eq(
		float(sim.run_state.economy.get("cash", 0.0)),
		cash_after_first,
		"Re-equipping does not grant a second loan"
	)
	assert_eq(
		float(sim.run_state.economy.get("debt", 0.0)),
		debt_after_first,
		"Re-equipping does not add more debt"
	)
	sim.free()


func _test_wrapper_freezes_passive_value() -> void:
	var sim := _sim()
	sim.start_run(8904)
	sim._perk_system.collect_perk(sim.run_state, "perk.the_wrapper", ContentDatabase)
	sim._perk_system.equip_perk(sim.run_state, "perk.the_wrapper", ContentDatabase)
	sim.run_state.statistics["last_job_reward"] = 10_000.0
	sim.effect_resolver.begin_action("reward.test")
	var mod_ctx := ModifierContext.new("reward.calculated", sim.run_state)
	mod_ctx.rng = sim.rng.derive("reward.test")
	var perk := ContentDatabase.get_perk("perk.the_wrapper")
	for sub in perk.subscriptions:
		if str(sub.get("event", "")) != "reward.calculated":
			continue
		sim.effect_resolver.dispatch("reward.calculated", mod_ctx, [sub])
	sim.run_state.statistics["last_job_reward"] = 100_000.0
	sim.effect_resolver.begin_action("reward.test2")
	mod_ctx = ModifierContext.new("reward.calculated", sim.run_state)
	mod_ctx.rng = sim.rng.derive("reward.test2")
	for sub in perk.subscriptions:
		if str(sub.get("event", "")) != "reward.calculated":
			continue
		sim.effect_resolver.dispatch("reward.calculated", mod_ctx, [sub])
	var statuses: Array = sim.run_state.build.get("status_effects", [])
	assert_eq(statuses.size(), 2, "Each job spawns its own wrapper passive")
	var first_value: float = float(
		statuses[0]["subscriptions"][0]["effects"][0].get("value", 0.0)
	)
	var second_value: float = float(
		statuses[1]["subscriptions"][0]["effects"][0].get("value", 0.0)
	)
	assert_almost_eq(first_value, 300.0, 0.01, "First wrapper passive frozen at 3% of £10k")
	assert_almost_eq(second_value, 3000.0, 0.01, "Second wrapper passive frozen at 3% of £100k")
	sim.free()
