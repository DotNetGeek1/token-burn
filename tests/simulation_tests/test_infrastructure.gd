extends TestCase

## The Infrastructure Tier: machine scale bought in the Market. A purchase
## hands the run exactly the scale profile its tier row in
## `content/upgrades/infrastructure.json` states — base rate, cooling, cost
## scale, cabinet cap — for the price on the row and nothing else: the
## investor's target, the perks and the calendar are untouched, the rent
## follows the tier's facility cost, and the bus announces it.

const SCRATCH_PROFILE := "user://profile_test_infrastructure.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var restore_path: String = MetaProgress.profile_path
	var restore_enabled: bool = MetaProgress.enabled

	_test_a_purchase_gives_the_tier_s_authored_scale()
	_test_every_tier_matches_its_row()
	_test_a_purchase_needs_the_cash()
	_test_a_purchase_changes_nothing_else()
	_test_rent_follows_the_facility_cost()
	_test_a_purchase_is_announced()
	_test_the_top_tier_is_the_end_of_the_shelf()

	if FileAccess.file_exists(SCRATCH_PROFILE):
		DirAccess.remove_absolute(SCRATCH_PROFILE)
	MetaProgress.profile_path = restore_path
	MetaProgress.enabled = restore_enabled
	MetaProgress._loaded = false


func _fresh_profile() -> void:
	MetaProgress.enabled = true
	MetaProgress.use_scratch_profile(SCRATCH_PROFILE)


func _sim() -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	return sim


func _entry(tier: int) -> Dictionary:
	return InfrastructureSystem.entry(tier, ContentDatabase)


func _profile_of(tier: int) -> Dictionary:
	return Dictionary(_entry(tier).get("profile", {}))


## The scale-dependent figures a purchase is meant to move, read the way the
## game reads them rather than off the tier row.
func _live_scale(state: RunState) -> Dictionary:
	return {
		"base_token_rate": CabinetSystems.capacity(state, "compute", "base_token_rate"),
		"cooling_capacity": CabinetSystems.capacity(state, "cooling", "cooling_capacity"),
		"heat_capacity": CabinetSystems.capacity(state, "cooling", "heat_capacity"),
		"cost_scale": float(InfrastructureSystem.profile(state).get("cost_scale", 0.0)),
		"cabinet_max_tier": InfrastructureSystem.cabinet_max_tier(state),
		"work_tier": CabinetSystems.work_tier(state),
		"power_draw": CabinetSystems.power_draw(state),
	}


func _test_a_purchase_gives_the_tier_s_authored_scale() -> void:
	var sim: Node = _sim()
	sim.start_run(9201)
	var state: RunState = sim.run_state
	assert_eq(sim.infrastructure_tier(), 0, "A fresh run is on tier 0")
	var before: Dictionary = _live_scale(state)
	var row0: Dictionary = _profile_of(0)
	assert_almost_eq(float(before["base_token_rate"]), float(row0.get("base_token_rate", 0.0)), 0.5, "Tier 0's base rate is the row's")
	assert_almost_eq(float(before["cooling_capacity"]), float(row0.get("cooling_capacity", 0.0)), 0.5, "So is its cooling")

	var cost: float = InfrastructureSystem.cost_of_tier(1, ContentDatabase)
	assert_true(cost > 0.0, "Tier 1 has a price")
	state.economy["cash"] = cost + 1000.0
	var result: Dictionary = sim.purchase_infrastructure()
	assert_true(bool(result.get("ok", false)), "The purchase goes through (%s)" % str(result.get("reason", "")))
	assert_eq(int(result.get("tier", 0)), 1, "Reporting the tier reached")
	assert_eq(int(result.get("previous_tier", -1)), 0, "And the one left")
	assert_almost_eq(float(result.get("cost", 0.0)), cost, 0.01, "And the price paid")
	assert_almost_eq(float(state.economy.get("cash", 0.0)), 1000.0, 0.01, "Which came off the cash and nothing more")
	assert_eq(sim.infrastructure_tier(), 1, "The run is on tier 1")

	var after: Dictionary = _live_scale(state)
	var row1: Dictionary = _profile_of(1)
	assert_almost_eq(float(after["base_token_rate"]), float(row1.get("base_token_rate", 0.0)), 0.5, "The base rate is tier 1's row")
	assert_almost_eq(float(after["cooling_capacity"]), float(row1.get("cooling_capacity", 0.0)), 0.5, "The cooling is tier 1's row")
	assert_almost_eq(float(after["heat_capacity"]), float(row1.get("heat_capacity", 0.0)), 0.5, "The heat capacity is tier 1's row")
	assert_almost_eq(float(after["cost_scale"]), float(row1.get("cost_scale", 0.0)), 0.0001, "The cost scale is tier 1's row")
	assert_eq(int(after["work_tier"]), int(row1.get("work_tier", -1)), "The work tier is tier 1's row")
	assert_almost_eq(float(after["power_draw"]), float(row1.get("power_draw", 0.0)), 0.5, "The draw is tier 1's row")
	assert_eq(int(after["cabinet_max_tier"]), int(_entry(1).get("cabinet_max_tier", -1)), "The cabinet cap is tier 1's row")
	assert_true(float(after["base_token_rate"]) > float(before["base_token_rate"]), "Which is a bigger machine than before")
	assert_true(float(after["cooling_capacity"]) > float(before["cooling_capacity"]), "With more cooling")
	assert_true(float(after["cost_scale"]) > float(before["cost_scale"]), "And dearer cabinet tiers")
	assert_almost_eq(
		float(state.compute.get("heat_capacity", 0.0)), float(row1.get("heat_capacity", 0.0)), 0.5,
		"The live heat capacity was re-derived"
	)
	# The cabinet opened at the tier's entry tiers, never below them.
	var entry_tiers: Dictionary = InfrastructureSystem.cabinet_entry_tiers(state)
	for system_id in CabinetSystems.system_ids():
		assert_true(
			CabinetSystems.tier(state, str(system_id)) >= int(entry_tiers.get(system_id, 1)),
			"%s is at least the tier's entry tier" % str(system_id)
		)
	# And the cabinet's next-tier price scales by the row's cost_scale.
	var base_cost: float = CabinetSystems.cost_of_tier("control", CabinetSystems.tier(state, "control") + 1)
	if base_cost > 0.0:
		assert_almost_eq(
			CabinetSystems.next_tier_cost(state, "control"), base_cost * float(row1.get("cost_scale", 1.0)), 0.01,
			"A cabinet tier is priced through the tier's cost scale"
		)
	sim.free()


## Walking the whole ladder by purchase, every tier's live scale is its row.
func _test_every_tier_matches_its_row() -> void:
	var sim: Node = _sim()
	sim.start_run(9202)
	var state: RunState = sim.run_state
	for tier in range(1, InfrastructureSystem.max_tier(ContentDatabase) + 1):
		state.economy["cash"] = InfrastructureSystem.cost_of_tier(tier, ContentDatabase) + 1.0
		assert_true(bool(sim.purchase_infrastructure().get("ok", false)), "Tier %d is bought" % tier)
		assert_eq(sim.infrastructure_tier(), tier, "The run is on tier %d" % tier)
		var live: Dictionary = _live_scale(state)
		var row: Dictionary = _profile_of(tier)
		assert_almost_eq(float(live["base_token_rate"]), float(row.get("base_token_rate", 0.0)), 0.5, "Tier %d base rate" % tier)
		assert_almost_eq(float(live["cooling_capacity"]), float(row.get("cooling_capacity", 0.0)), 0.5, "Tier %d cooling" % tier)
		assert_almost_eq(float(live["heat_capacity"]), float(row.get("heat_capacity", 0.0)), 0.5, "Tier %d heat capacity" % tier)
		assert_almost_eq(float(live["cost_scale"]), float(row.get("cost_scale", 0.0)), 0.0001, "Tier %d cost scale" % tier)
		assert_eq(int(live["cabinet_max_tier"]), int(_entry(tier).get("cabinet_max_tier", -1)), "Tier %d cabinet cap" % tier)
		assert_almost_eq(
			InfrastructureSystem.overflow_allowance(state), float(_entry(tier).get("overflow_allowance", -1)), 0.01,
			"Tier %d overflow allowance" % tier
		)
		assert_eq(RoomProgression.room_for(state), str(_entry(tier).get("room", "")), "Tier %d is drawn in its room" % tier)
	sim.free()


func _test_a_purchase_needs_the_cash() -> void:
	var sim: Node = _sim()
	sim.start_run(9203)
	var state: RunState = sim.run_state
	var cost: float = InfrastructureSystem.cost_of_tier(1, ContentDatabase)
	state.economy["cash"] = cost - 1.0
	var verdict: Dictionary = InfrastructureSystem.can_upgrade(state)
	assert_false(bool(verdict.get("ok", true)), "A dollar short cannot buy")
	assert_true(str(verdict.get("reason", "")).begins_with("NEED "), "In the Market's words: %s" % str(verdict.get("reason", "")))
	assert_eq(str(verdict.get("reason", "")), "NEED %s MORE" % NumberFormat.format_cash(1.0), "Naming the shortfall")
	var result: Dictionary = sim.purchase_infrastructure()
	assert_false(bool(result.get("ok", true)), "The purchase is refused")
	assert_eq(str(result.get("reason", "")), str(verdict.get("reason", "")), "For the same reason")
	assert_eq(sim.infrastructure_tier(), 0, "The tier has not moved")
	assert_almost_eq(float(state.economy.get("cash", 0.0)), cost - 1.0, 0.01, "And nothing was charged")
	var row: Dictionary = sim.infrastructure_next()
	assert_false(bool(row.get("can_upgrade", true)), "The Market row is blocked")
	assert_eq(str(row.get("reason", "")), str(verdict.get("reason", "")), "With the same blocker")

	state.economy["cash"] = cost
	assert_true(bool(InfrastructureSystem.can_upgrade(state).get("ok", false)), "Exactly the price is enough")
	assert_true(bool(sim.purchase_infrastructure().get("ok", false)), "And the purchase goes through")
	assert_almost_eq(float(state.economy.get("cash", 0.0)), 0.0, 0.01, "Leaving nothing")

	# The Market's hours apply: a purchase mid-round is refused too.
	state.economy["cash"] = 1e12
	sim.phase = sim.Phase.IN_ROUND
	var closed: Dictionary = sim.purchase_infrastructure()
	assert_false(bool(closed.get("ok", true)), "The counter is closed mid-round")
	assert_eq(str(closed.get("reason", "")), "MARKET CLOSED", "And says so")
	assert_eq(sim.infrastructure_tier(), 1, "Without moving the tier")
	sim.free()


## The purchase is scale and nothing else: the investor's target, the perks
## and the calendar are exactly as they were.
func _test_a_purchase_changes_nothing_else() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9204)
	var state: RunState = sim.run_state
	state.build["perks"] = ["perk.test_marker_a", "perk.test_marker_b"]
	state.calendar["round"] = 4
	state.calendar["prompt"] = 3
	state.investor["tokens_burned"] = 12345.0
	state.investor["quality_sum"] = 80.0
	state.investor["quality_count"] = 2
	var investor_before: Dictionary = state.investor.duplicate(true)
	var perks_before: Array = Array(state.build.get("perks", [])).duplicate(true)
	var calendar_before: Dictionary = state.calendar.duplicate(true)
	var level_before: int = sim.investor_level()
	var target_before: Dictionary = sim.investor_target()
	var reputation_before: float = float(state.business.get("reputation", 0.0))
	var cost: float = InfrastructureSystem.cost_of_tier(1, ContentDatabase)
	state.economy["cash"] = cost + 500.0

	assert_true(bool(sim.purchase_infrastructure().get("ok", false)), "The purchase goes through")

	assert_eq(state.investor, investor_before, "run_state.investor is byte-identical")
	assert_eq(sim.investor_level(), level_before, "The Investor Level did not move")
	assert_eq(sim.investor_target(), target_before, "Nor the target")
	assert_eq(Array(state.build.get("perks", [])), perks_before, "build.perks is untouched")
	assert_eq(state.calendar, calendar_before, "The calendar is untouched")
	assert_almost_eq(float(state.business.get("reputation", 0.0)), reputation_before, 0.001, "So is reputation")
	assert_almost_eq(float(state.economy.get("cash", 0.0)), 500.0, 0.01, "Only the price left the account")
	assert_eq(sim.phase, sim.Phase.ROUND_PREP, "The run is still at round prep")
	assert_false(bool(state.flags.get("victory", false)), "No victory was declared")
	assert_false(bool(state.flags.get("target_complete", false)), "No target was met")
	assert_false(sim.investor_draft_pending(), "And no draft was dealt")
	sim.free()


func _test_rent_follows_the_facility_cost() -> void:
	var sim: Node = _sim()
	sim.start_run(9205)
	var state: RunState = sim.run_state
	assert_almost_eq(
		float(state.economy.get("round_rent", 0.0)),
		float(_entry(0).get("facility_cost", 0.0)) * float(state.economy.get("rent_multiplier", 1.0)),
		0.01, "A fresh run pays tier 0's facility cost"
	)
	state.economy["rent_multiplier"] = 1.5
	for tier in range(1, 4):
		state.economy["cash"] = InfrastructureSystem.cost_of_tier(tier, ContentDatabase) + 1.0
		assert_true(bool(sim.purchase_infrastructure().get("ok", false)), "Tier %d is bought" % tier)
		assert_almost_eq(
			float(state.economy.get("round_rent", 0.0)),
			float(_entry(tier).get("facility_cost", 0.0)) * 1.5,
			0.01, "Tier %d's rent is its facility cost times the run's rent multiplier" % tier
		)
		assert_almost_eq(
			InfrastructureSystem.facility_cost(state), float(_entry(tier).get("facility_cost", 0.0)), 0.01,
			"Which the system reads off the row"
		)
	assert_true(
		float(state.economy.get("round_rent", 0.0)) > float(_entry(0).get("facility_cost", 0.0)) * 1.5,
		"So a bigger machine costs more a round"
	)
	sim.free()


func _test_a_purchase_is_announced() -> void:
	var sim: Node = _sim()
	sim.start_run(9206)
	var state: RunState = sim.run_state
	var announced: Array = []
	var on_upgraded := func(tier: int) -> void: announced.append(tier)
	EventBus.infrastructure_upgraded.connect(on_upgraded)

	state.economy["cash"] = 0.0
	sim.purchase_infrastructure()
	assert_true(announced.is_empty(), "A refused purchase announces nothing")

	state.economy["cash"] = InfrastructureSystem.cost_of_tier(1, ContentDatabase) + 1.0
	assert_true(bool(sim.purchase_infrastructure().get("ok", false)), "Tier 1 is bought")
	assert_eq(announced, [1], "infrastructure.upgraded fires once, with the tier reached")
	state.economy["cash"] = InfrastructureSystem.cost_of_tier(2, ContentDatabase) + 1.0
	assert_true(bool(sim.purchase_infrastructure().get("ok", false)), "Tier 2 is bought")
	assert_eq(announced, [1, 2], "And again for the next")
	assert_eq(
		int(state.statistics.get("infrastructure_purchases", 0)), 2,
		"The run counts its purchases"
	)
	EventBus.infrastructure_upgraded.disconnect(on_upgraded)
	sim.free()


func _test_the_top_tier_is_the_end_of_the_shelf() -> void:
	var sim: Node = _sim()
	sim.start_run(9207)
	var state: RunState = sim.run_state
	var top: int = InfrastructureSystem.max_tier(ContentDatabase)
	sim.apply_infrastructure_tier(state, top)
	state.economy["cash"] = 1e15
	var verdict: Dictionary = InfrastructureSystem.can_upgrade(state)
	assert_false(bool(verdict.get("ok", true)), "Nothing is for sale above the top tier")
	assert_eq(str(verdict.get("reason", "")), InfrastructureSystem.REASON_MAXED, "The row says MAXED OUT")
	assert_almost_eq(InfrastructureSystem.next_tier_cost(state), -1.0, 0.001, "And quotes no price")
	var row: Dictionary = sim.infrastructure_next()
	assert_true(bool(row.get("maxed", false)), "The Market row is maxed")
	assert_eq(str(row.get("effect", "x")), "", "With no effect to promise")
	assert_false(bool(sim.purchase_infrastructure().get("ok", true)), "And a purchase is refused")
	assert_eq(sim.infrastructure_tier(), top, "Leaving the run at the top")
	sim.free()
