extends TestCase

## The five cabinet systems: what a tier is worth, what the next one costs and
## why it cannot be bought yet, how a dwelling maps onto tiers, and the one
## rule generation obeys — it is a label on the tier sum and nothing more.

const DWELLINGS := [
	"bedroom", "garage", "office_unit", "warehouse",
	"datacentre_campus", "private_power_grid", "moon_facility",
]

var _board := BoardSystem.new()


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_generation_is_a_function_of_the_sum_only()
	_test_derive_from_dwelling_matches_the_table()
	_test_fresh_run_opens_with_the_rooms_tiers()
	_test_tier_one_leaves_bedroom_numbers_alone()
	_test_upgrade_charges_cash_and_raises_tier()
	_test_upgrade_widens_the_board_and_cools_the_room()
	_test_blocked_reasons()
	_test_facade_row_is_presentable()
	_test_market_closed_refuses()
	_test_migration_never_reduces_capacity()
	_test_migration_clamps_stray_tiers()
	_test_round_trip_keeps_tiers()


## A run at the bottom of everything, with cash to spend and the Market open.
func _make_sim(run_seed: int = 901, location: String = "bedroom") -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(run_seed)
	if location != "bedroom":
		sim.apply_run_location(sim.run_state, location, true)
		sim.board_system().ensure_board(sim.run_state, ContentDatabase)
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	sim.phase = sim.Phase.ROUND_PREP
	return sim


func _set_tiers(state: RunState, tiers: Array) -> void:
	var order: Array = CabinetSystems.system_ids()
	var block: Dictionary = {}
	for i in range(order.size()):
		block[str(order[i])] = int(tiers[i])
	state.build["cabinet_systems"] = block


func _test_generation_is_a_function_of_the_sum_only() -> void:
	var expected := {
		5: "Improvised Cabinet", 7: "Improvised Cabinet",
		8: "Spliced Rig", 10: "Spliced Rig",
		11: "Token Furnace", 14: "Token Furnace",
		15: "Grid Eater", 18: "Grid Eater",
		19: "Impossible Engine", 20: "Impossible Engine",
	}
	for total in expected.keys():
		var generation: Dictionary = CabinetSystems.generation_for_sum(int(total))
		assert_eq(str(generation.get("name", "")), str(expected[total]), "Sum %d is %s" % [int(total), str(expected[total])])
	assert_eq(int(CabinetSystems.generation_for_sum(5).get("index", -1)), 0, "Improvised Cabinet is index 0")
	assert_eq(int(CabinetSystems.generation_for_sum(20).get("index", -1)), 4, "Impossible Engine is index 4")

	# Two cabinets with the same sum but nothing else in common are the same
	# generation, and neither generation reads back into a capacity.
	var lopsided := RunState.new()
	_set_tiers(lopsided, [4, 1, 1, 1, 1])
	var even := RunState.new()
	_set_tiers(even, [2, 2, 2, 1, 1])
	assert_eq(CabinetSystems.tier_sum(lopsided), 8, "Lopsided cabinet sums to 8")
	assert_eq(CabinetSystems.tier_sum(even), 8, "Even cabinet sums to 8")
	assert_eq(
		CabinetSystems.generation(lopsided).get("name"), CabinetSystems.generation(even).get("name"),
		"Same sum, same generation"
	)
	assert_true(
		CabinetSystems.capacity(lopsided, "compute", "base_token_rate")
			!= CabinetSystems.capacity(even, "compute", "base_token_rate"),
		"Same generation, different numbers: generation is not a capacity"
	)
	var keys: Array = CabinetSystems.generation(even).keys()
	keys.sort()
	assert_eq(keys, ["index", "name", "sum"], "Generation carries a label and a sum, no stats")


func _test_derive_from_dwelling_matches_the_table() -> void:
	var table: Dictionary = Dictionary(ContentDatabase.cabinet_systems.get("migration_from_dwelling", {}))
	var order: Array = Array(ContentDatabase.cabinet_systems.get("migration_value_order", []))
	assert_eq(order, ["compute", "cooling", "power", "backplane", "control"], "Migration order is the pack's")
	for dwelling in DWELLINGS:
		var derived: Dictionary = CabinetSystems.derive_from_dwelling(dwelling)
		var row: Array = Array(table.get(dwelling, []))
		for i in range(order.size()):
			assert_eq(
				int(derived.get(str(order[i]), 0)), int(row[i]),
				"%s derives %s tier %d" % [dwelling, str(order[i]), int(row[i])]
			)
	var unknown: Dictionary = CabinetSystems.derive_from_dwelling("houseboat")
	for system_id in order:
		assert_eq(int(unknown.get(str(system_id), 0)), 1, "Unknown dwelling: %s is tier 1" % str(system_id))
	var missing: Dictionary = CabinetSystems.derive_from_dwelling("")
	assert_eq(CabinetSystems.default_tiers(), missing, "Missing dwelling is the default cabinet")
	assert_eq(int(CabinetSystems.max_tier_for_dwelling("bedroom")), 2, "Bedroom caps systems at tier 2")
	assert_eq(int(CabinetSystems.max_tier_for_dwelling("office_unit")), 3, "Office caps systems at tier 3")
	assert_eq(int(CabinetSystems.max_tier_for_dwelling("moon_facility")), 4, "Moon opens tier 4")
	assert_eq(int(CabinetSystems.max_tier_for_dwelling("houseboat")), 2, "Unknown dwelling gets the lowest cap")


func _test_fresh_run_opens_with_the_rooms_tiers() -> void:
	var sim := _make_sim(902, "garage")
	var tiers: Dictionary = sim.cabinet_system_tiers()
	assert_eq(tiers, CabinetSystems.derive_from_dwelling("garage"), "A fresh garage run has garage tiers")
	assert_eq(_board.derived_supported_capacity(sim.run_state, ContentDatabase), 5, "Garage backplane backs 5 bays")
	assert_eq(UpgradeSystem.hardware_slots_total(sim.run_state, ContentDatabase), 4, "Garage power bus gives 4 slots")
	assert_almost_eq(UpgradeSystem.location_cooling(sim.run_state, ContentDatabase), 97.0, 0.001, "Garage cooling loop cools 97")
	assert_almost_eq(float(sim.run_state.compute.get("heat_capacity", 0.0)), 140.0, 0.001, "Garage heat capacity is 140")
	assert_eq(str(sim.cabinet_generation().get("name", "")), "Spliced Rig", "Garage cabinet (sum 9) is a Spliced Rig")
	# Moving up never lowers a system bought below.
	CabinetSystems.set_tier(sim.run_state, "control", 2)
	sim.apply_run_location(sim.run_state, "office_unit", false)
	assert_eq(CabinetSystems.tier(sim.run_state, "control"), 2, "Control kept at 2 on the move to the office")
	assert_eq(CabinetSystems.tier(sim.run_state, "backplane"), 2, "Office does not raise the backplane beyond its row")
	sim.free()


func _test_tier_one_leaves_bedroom_numbers_alone() -> void:
	var sim := _make_sim(903)
	assert_eq(sim.cabinet_system_tiers(), CabinetSystems.default_tiers(), "Bedroom is every system at tier 1")
	assert_almost_eq(ComputeSystem.cabinet_base_rate(sim.run_state), 0.0, 0.001, "Tier 1 compute adds no base rate")
	var laptop_rate: float = float(
		Dictionary(ContentDatabase.balance.get("hardware_curves", {})).get("used_laptop", {}).get("token_rate", 0.0)
	)
	assert_almost_eq(
		float(sim.run_state.compute.get("local_capacity", 0.0)), laptop_rate, 0.001,
		"Bedroom local capacity is exactly the laptop"
	)
	assert_eq(_board.derived_supported_capacity(sim.run_state, ContentDatabase), 3, "Bedroom backs 3 bays")
	assert_eq(_board.derived_workflow_capacity(sim.run_state, ContentDatabase), 1, "Bedroom holds 1 workflow")
	assert_eq(UpgradeSystem.hardware_slots_total(sim.run_state, ContentDatabase), 2, "Bedroom has 2 slots")
	assert_almost_eq(UpgradeSystem.location_cooling(sim.run_state, ContentDatabase), 16.0, 0.001, "Bedroom cools 16")
	assert_almost_eq(float(sim.run_state.compute.get("heat_capacity", 0.0)), 100.0, 0.001, "Bedroom heat capacity is 100")
	sim.free()


func _test_upgrade_charges_cash_and_raises_tier() -> void:
	var sim := _make_sim(904)
	sim.run_state.economy["cash"] = 10_000.0
	var cost: float = CabinetSystems.next_tier_cost(sim.run_state, "backplane")
	assert_almost_eq(cost, 2000.0, 0.001, "Backplane tier 2 costs 2000")
	var emitted: Array = []
	var on_upgraded := func(system_id: String, tier: int) -> void:
		emitted.append([system_id, tier])
	EventBus.cabinet_system_upgraded.connect(on_upgraded)
	var result: Dictionary = sim.upgrade_cabinet_system("backplane")
	EventBus.cabinet_system_upgraded.disconnect(on_upgraded)
	assert_true(bool(result.get("ok", false)), "Backplane upgrade succeeds: %s" % str(result.get("reason", "")))
	assert_eq(int(result.get("tier", 0)), 2, "Result reports tier 2")
	assert_eq(int(result.get("previous_tier", 0)), 1, "Result reports it came from tier 1")
	assert_almost_eq(float(result.get("cost", 0.0)), cost, 0.001, "Result reports the price paid")
	assert_almost_eq(float(sim.run_state.economy.get("cash", 0.0)), 10_000.0 - cost, 0.001, "Cash falls by the cost")
	assert_eq(CabinetSystems.tier(sim.run_state, "backplane"), 2, "Backplane is now tier 2")
	assert_eq(emitted, [["backplane", 2]], "cabinet_system_upgraded fired once with id and tier")
	var delta: Dictionary = Dictionary(result.get("delta", {}))
	assert_true(delta.has("bays"), "Delta names the stat that moved")
	assert_almost_eq(float(Dictionary(delta.get("bays", {})).get("before", 0.0)), 3.0, 0.001, "Bays before: 3")
	assert_almost_eq(float(Dictionary(delta.get("bays", {})).get("after", 0.0)), 5.0, 0.001, "Bays after: 5")
	assert_eq(str(result.get("effect", "")), "3 → 5 BAYS", "Effect text reads 3 → 5 BAYS")
	sim.free()


func _test_upgrade_widens_the_board_and_cools_the_room() -> void:
	var sim := _make_sim(905)
	sim.run_state.economy["cash"] = 50_000.0
	assert_true(bool(sim.upgrade_cabinet_system("backplane").get("ok", false)), "Backplane bought")
	assert_eq(_board.derived_supported_capacity(sim.run_state, ContentDatabase), 5, "Board now backs 5 bays")
	assert_eq(int(Dictionary(sim.run_state.build.get("board", {})).get("slot_count", 0)), 5, "Board resized to 5")
	assert_true(bool(sim.upgrade_cabinet_system("control").get("ok", false)), "Control bought")
	assert_eq(_board.derived_workflow_capacity(sim.run_state, ContentDatabase), 2, "Two workflows now fit")
	assert_eq(int(sim.run_state.build.get("workflow_capacity", 0)), 2, "workflow_capacity written to the run")
	assert_true(bool(sim.upgrade_cabinet_system("power").get("ok", false)), "Power bought")
	assert_eq(UpgradeSystem.hardware_slots_total(sim.run_state, ContentDatabase), 4, "Four floor slots now")
	var cooling_before: float = float(sim.run_state.compute.get("cooling", 0.0))
	var cooling_result: Dictionary = sim.upgrade_cabinet_system("cooling")
	assert_true(bool(cooling_result.get("ok", false)), "Cooling bought")
	assert_almost_eq(float(sim.run_state.compute.get("heat_capacity", 0.0)), 140.0, 0.001, "Heat capacity now 140")
	assert_almost_eq(
		float(sim.run_state.compute.get("cooling", 0.0)), cooling_before + (97.0 - 16.0), 0.001,
		"Cooling rises by the tier difference and nothing more"
	)
	var delta: Dictionary = Dictionary(cooling_result.get("delta", {}))
	assert_true(delta.has("cooling_capacity") and delta.has("heat_capacity"), "Cooling delta names both stats")
	var rate_before: float = float(sim.run_state.compute.get("local_capacity", 0.0))
	assert_true(bool(sim.upgrade_cabinet_system("compute").get("ok", false)), "Compute bought")
	assert_almost_eq(
		float(sim.run_state.compute.get("local_capacity", 0.0)), rate_before + 2_000_000.0, 1.0,
		"Compute tier 2 adds its 2M base rate to local capacity"
	)
	assert_eq(CabinetSystems.tier_sum(sim.run_state), 10, "Five tier-2 systems sum to 10")
	assert_eq(str(sim.cabinet_generation().get("name", "")), "Spliced Rig", "Sum 10 is still a Spliced Rig")
	sim.free()


func _test_blocked_reasons() -> void:
	var sim := _make_sim(906)
	sim.run_state.economy["cash"] = 1_760.0
	var short: Dictionary = CabinetSystems.can_upgrade(sim.run_state, "backplane")
	assert_false(bool(short.get("ok", true)), "Cannot afford the backplane")
	assert_eq(str(short.get("reason", "")), "NEED $240 MORE", "Shortfall is spelled out")
	var refused: Dictionary = sim.upgrade_cabinet_system("backplane")
	assert_false(bool(refused.get("ok", true)), "Facade refuses too")
	assert_eq(str(refused.get("reason", "")), "NEED $240 MORE", "Facade carries the same words")
	assert_eq(CabinetSystems.tier(sim.run_state, "backplane"), 1, "Refused upgrade does not move the tier")
	assert_almost_eq(float(sim.run_state.economy.get("cash", 0.0)), 1_760.0, 0.001, "Refused upgrade does not charge")

	sim.run_state.economy["cash"] = 1_000_000.0
	CabinetSystems.set_tier(sim.run_state, "backplane", 2)
	var capped: Dictionary = CabinetSystems.can_upgrade(sim.run_state, "backplane")
	assert_false(bool(capped.get("ok", true)), "Bedroom cannot buy tier 3")
	assert_eq(str(capped.get("reason", "")), "NEXT CHAPTER UNLOCKS TIER 3", "Chapter cap is spelled out")
	assert_eq(CabinetSystems.max_tier_for_chapter(sim.run_state), 2, "Bedroom's cap is 2")

	sim.apply_run_location(sim.run_state, "moon_facility", false)
	CabinetSystems.set_tier(sim.run_state, "backplane", 4)
	var maxed: Dictionary = CabinetSystems.can_upgrade(sim.run_state, "backplane")
	assert_false(bool(maxed.get("ok", true)), "Tier 4 cannot go higher")
	assert_eq(str(maxed.get("reason", "")), "MAXED OUT", "Maxed is spelled out")
	assert_almost_eq(CabinetSystems.next_tier_cost(sim.run_state, "backplane"), -1.0, 0.001, "Maxed cost is -1")
	assert_eq(str(sim.upgrade_cabinet_system("backplane").get("reason", "")), "MAXED OUT", "Facade refuses a maxed system")

	var unknown: Dictionary = CabinetSystems.can_upgrade(sim.run_state, "flux_capacitor")
	assert_false(bool(unknown.get("ok", true)), "Unknown system cannot be bought")
	assert_false(bool(sim.upgrade_cabinet_system("flux_capacitor").get("ok", true)), "Facade refuses an unknown system")
	sim.free()


func _test_facade_row_is_presentable() -> void:
	var sim := _make_sim(907)
	sim.run_state.economy["cash"] = 5_000.0
	var row: Dictionary = sim.cabinet_system_next("cooling")
	assert_eq(str(row.get("name", "")), "Cooling Loop", "Row names the system")
	assert_eq(int(row.get("tier", 0)), 1, "Row shows the current tier")
	assert_eq(str(row.get("tier_name", "")), "Desk Fan", "Row names the current tier")
	assert_eq(int(row.get("next_tier", 0)), 2, "Row shows the next tier")
	assert_eq(str(row.get("next_tier_name", "")), "Radiator", "Row names the next tier")
	assert_almost_eq(float(row.get("cost", 0.0)), 2200.0, 0.001, "Row quotes the price")
	assert_eq(str(row.get("effect", "")), "16 → 97 COOLING · 100 → 140 HEAT CAP", "Row describes the effect")
	assert_true(bool(row.get("can_upgrade", false)), "Row's button is live")
	assert_eq(str(row.get("reason", "x")), "", "Live row has no refusal")
	assert_false(bool(row.get("maxed", true)), "Row is not maxed")
	CabinetSystems.set_tier(sim.run_state, "cooling", 4)
	var top: Dictionary = sim.cabinet_system_next("cooling")
	assert_true(bool(top.get("maxed", false)), "Tier 4 row is maxed")
	assert_eq(str(top.get("reason", "")), "MAXED OUT", "Maxed row says so")
	assert_eq(str(top.get("next_tier_name", "x")), "", "Maxed row has no next tier")
	sim.free()


func _test_market_closed_refuses() -> void:
	var sim := _make_sim(908)
	sim.run_state.economy["cash"] = 50_000.0
	sim.phase = sim.Phase.IN_ROUND
	var result: Dictionary = sim.upgrade_cabinet_system("backplane")
	assert_false(bool(result.get("ok", true)), "No cabinet upgrades mid-round")
	assert_eq(str(result.get("reason", "")), "MARKET CLOSED", "Closed Market says so")
	assert_eq(CabinetSystems.tier(sim.run_state, "backplane"), 1, "Tier untouched")
	var row: Dictionary = sim.cabinet_system_next("backplane")
	assert_false(bool(row.get("can_upgrade", true)), "Row's button is dead while closed")
	assert_eq(str(row.get("reason", "")), "MARKET CLOSED", "Row explains why")
	sim.free()


## A v22 save that was demonstrably using more than its room's row is raised
## until the tiers explain what it had, and the legacy bonus migration then
## attributes nothing extra to meta unlocks, so nothing is counted twice.
func _test_migration_never_reduces_capacity() -> void:
	var sim := _make_sim(909)
	var saved: Dictionary = sim.run_state.to_dict()
	sim.free()
	saved["save_version"] = 22
	var build: Dictionary = saved["build"]
	build.erase("cabinet_systems")
	build.erase("meta_workflow_bonus")
	var board: Dictionary = build["board"]
	board.erase("meta_slot_bonus")
	board["slot_count"] = 5
	build["board"] = board
	build["workflow_capacity"] = 2
	build["hardware"] = ["used_laptop", "used_laptop", "used_laptop"]
	saved["build"] = build

	var state := RunState.new()
	state.from_dict(saved)
	assert_eq(CabinetSystems.tier(state, "backplane"), 2, "Backplane raised to cover 5 bays")
	assert_eq(CabinetSystems.tier(state, "control"), 2, "Control raised to cover 2 workflows")
	assert_eq(CabinetSystems.tier(state, "power"), 2, "Power raised to cover 3 machines")
	assert_eq(CabinetSystems.tier(state, "compute"), 1, "Compute untouched: nothing demanded it")
	assert_eq(CabinetSystems.tier(state, "cooling"), 1, "Cooling untouched: nothing demanded it")
	assert_true(
		UpgradeSystem.hardware_slots_total(state, ContentDatabase) >= 3, "Three machines still fit"
	)
	_board.ensure_board(state, ContentDatabase)
	assert_eq(_board.derived_supported_capacity(state, ContentDatabase), 5, "Board is 5 bays, not 5 + a phantom meta bonus")
	assert_eq(int(Dictionary(state.build.get("board", {})).get("meta_slot_bonus", -1)), 0, "No meta slot bonus invented")
	assert_eq(_board.derived_workflow_capacity(state, ContentDatabase), 2, "Two workflows, not 2 + a phantom bonus")
	assert_eq(int(state.build.get("meta_workflow_bonus", -1)), 0, "No meta workflow bonus invented")


func _test_migration_clamps_stray_tiers() -> void:
	var sim := _make_sim(910)
	var saved: Dictionary = sim.run_state.to_dict()
	sim.free()
	saved["save_version"] = 22
	var build: Dictionary = saved["build"]
	build["cabinet_systems"] = {"compute": 9, "cooling": 0, "power": "2", "backplane": 2.0}
	saved["build"] = build
	var state := RunState.new()
	state.from_dict(saved)
	var tiers: Dictionary = CabinetSystems.tiers(state)
	assert_eq(int(tiers.get("compute", 0)), 4, "Tier 9 clamps to 4")
	assert_eq(int(tiers.get("cooling", 0)), 1, "Tier 0 clamps to 1")
	assert_eq(int(tiers.get("power", 0)), 2, "String tier is read as a number")
	assert_eq(int(tiers.get("backplane", 0)), 2, "Float tier is read as an int")
	assert_eq(int(tiers.get("control", 0)), 1, "Missing system is filled at tier 1")
	for value in Dictionary(state.build.get("cabinet_systems", {})).values():
		assert_true(value is int, "Stored tier is an int after migration")


func _test_round_trip_keeps_tiers() -> void:
	var sim := _make_sim(911, "warehouse")
	CabinetSystems.set_tier(sim.run_state, "control", 3)
	var saved: Dictionary = sim.run_state.to_dict()
	assert_true(Dictionary(saved.get("build", {})).has("cabinet_systems"), "to_dict writes cabinet_systems")
	var restored := RunState.new()
	restored.from_dict(saved)
	assert_eq(
		restored.build.get("cabinet_systems"), sim.run_state.build.get("cabinet_systems"),
		"Tiers survive to_dict/from_dict"
	)
	assert_false(restored.build.has("migration_debug"), "A current save does not pick up migration_debug")
	sim.free()
