extends TestCase

## The room is presentation. It follows the Infrastructure Tier the player has
## bought, the investor keys his "new premises" call off it, and nothing in the
## game reads a number back out of it: forcing a different room key changes
## nothing in `economy`, `compute`, `build`, `business` or `investor`, and no
## gameplay answer — the tier, the cabinet's capacities, what perks are open.

const SCRATCH_PROFILE := "user://profile_test_room_presentation.json"

## The sections a room swap must not touch, and the one build key that is
## only the derived room cache.
const GAMEPLAY_SECTIONS := ["economy", "compute", "build", "business", "investor"]
const ROOM_CACHE_KEY := "dwelling"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_room_follows_infrastructure_tier()
	_test_room_name_is_the_id_in_words()
	_test_investor_has_a_line_for_every_room()
	_test_forcing_a_room_key_changes_no_gameplay()
	_test_a_room_swap_leaves_perk_gates_alone()
	_test_asset_catalog_reads_the_room_off_the_tier()


func _sim() -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	return sim


func _fresh_profile() -> void:
	MetaProgress.enabled = true
	MetaProgress.use_scratch_profile(SCRATCH_PROFILE)


func _cleanup_profile() -> void:
	if FileAccess.file_exists(SCRATCH_PROFILE):
		DirAccess.remove_absolute(SCRATCH_PROFILE)
	MetaProgress._loaded = false


## Deep copies of every gameplay section, with the derived room cache stripped
## out of `build` so the comparison is about the numbers.
func _gameplay_snapshot(state: RunState) -> Dictionary:
	var snapshot: Dictionary = {}
	for section in GAMEPLAY_SECTIONS:
		var copy: Dictionary = Dictionary(state.get(section)).duplicate(true)
		if section == "build":
			copy.erase(ROOM_CACHE_KEY)
		snapshot[section] = copy
	return snapshot


func _capacities(state: RunState) -> Dictionary:
	var result: Dictionary = {}
	for system_id in CabinetSystems.system_ids():
		result[system_id] = CabinetSystems.tier(state, str(system_id))
	result["cooling_capacity"] = CabinetSystems.capacity(state, "cooling", "cooling_capacity")
	result["heat_capacity"] = CabinetSystems.capacity(state, "cooling", "heat_capacity")
	result["cabinet_max_tier"] = InfrastructureSystem.cabinet_max_tier(state)
	result["overflow"] = InfrastructureSystem.overflow_allowance(state)
	result["facility_cost"] = InfrastructureSystem.facility_cost(state)
	return result


func _test_room_follows_infrastructure_tier() -> void:
	var sim: Node = _sim()
	sim.start_run(7301)
	assert_eq(RoomProgression.room_for(sim.run_state), "bedroom", "A fresh run is drawn in the bedroom")
	for tier in range(InfrastructureSystem.max_tier() + 1):
		sim.apply_infrastructure_tier(sim.run_state, tier)
		var expected: String = str(InfrastructureSystem.entry(tier).get("room", ""))
		assert_eq(
			RoomProgression.room_for(sim.run_state), expected,
			"Infrastructure tier %d is drawn in its authored room" % tier
		)
		assert_eq(
			RoomProgression.room_at(tier), expected,
			"The tier alone names the same room"
		)
		assert_eq(
			InfrastructureSystem.tier_for_room(expected), tier,
			"And the room reads back to the tier"
		)
	sim.free()


func _test_room_name_is_the_id_in_words() -> void:
	assert_eq(RoomProgression.room_name("bedroom"), "Bedroom", "A one-word id is capitalised")
	assert_eq(RoomProgression.room_name("office_unit"), "Office Unit", "Underscores become spaces")
	assert_eq(RoomProgression.room_name("moon_facility"), "Moon Facility", "Every word is capitalised")


func _test_investor_has_a_line_for_every_room() -> void:
	var sim: Node = _sim()
	sim.start_run(7302)
	for tier in range(InfrastructureSystem.max_tier() + 1):
		sim.apply_infrastructure_tier(sim.run_state, tier)
		var room: String = RoomProgression.room_for(sim.run_state)
		assert_eq(
			RoomProgression.investor_variant(sim.run_state), room,
			"Tier %d's investor line is keyed by its room" % tier
		)
		assert_true(
			InvestorVoice.has_call(RoomProgression.ROOM_CHANGED_TRIGGER, room),
			"Vince has something to say about arriving in the %s" % room
		)
		var call: Dictionary = InvestorVoice.call_for(RoomProgression.ROOM_CHANGED_TRIGGER, room, tier)
		assert_true(not Array(call.get("lines", [])).is_empty(), "And it has lines")
	assert_true(
		InvestorVoice.has_call(RoomProgression.ROOM_CHANGED_TRIGGER, "default"),
		"With a default for a room he has no script for"
	)
	sim.free()


## The heart of it: write a different room key straight into the build and
## nothing that matters notices.
func _test_forcing_a_room_key_changes_no_gameplay() -> void:
	var sim: Node = _sim()
	sim.start_run(7303)
	sim.apply_infrastructure_tier(sim.run_state, 2)
	sim.run_state.economy["cash"] = 12345.0
	var state: RunState = sim.run_state
	# Stock the shelf first: its first read stamps the market state, and the
	# snapshot has to be of a settled run.
	var stock_before: Array = sim.module_market_stock()
	var before: Dictionary = _gameplay_snapshot(state)
	var tier_before: int = InfrastructureSystem.tier(state)
	var capacities_before: Dictionary = _capacities(state)
	var level_before: int = sim.investor_level()

	state.build[ROOM_CACHE_KEY] = "moon_facility"

	assert_eq(_gameplay_snapshot(state), before, "Every gameplay section is unchanged by the room key")
	assert_eq(InfrastructureSystem.tier(state), tier_before, "The infrastructure tier does not follow the key")
	assert_eq(_capacities(state), capacities_before, "The cabinet's capacities do not follow the key")
	assert_eq(sim.investor_level(), level_before, "Nor does the Investor Level")
	assert_eq(sim.module_market_stock(), stock_before, "Nor the Market shelf")
	assert_eq(
		RoomProgression.room_for(state), RoomProgression.room_at(tier_before),
		"The room drawn is still the tier's room, not the forced key"
	)
	assert_eq(
		AssetCatalog.dwelling_for_build(state.build), RoomProgression.room_at(tier_before),
		"The art catalog draws the tier's room too"
	)
	sim.free()


func _test_a_room_swap_leaves_perk_gates_alone() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(7304)
	var state: RunState = sim.run_state
	var gated: PerkDefinition = null
	for perk in ContentDatabase.perks:
		if perk.min_investor_level > 1 and perk.unlock_achievement == "" \
			and perk.requires_tags.is_empty() and not perk.difficulty.is_empty():
			gated = perk
			break
	assert_true(gated != null, "Some perk is gated on an Investor Level above the first")
	if gated == null:
		sim.free()
		_cleanup_profile()
		return
	# Only the level gate is under test: play on a difficulty the perk allows.
	state.flags["difficulty"] = str(gated.difficulty[0])
	assert_eq(
		sim.perk_acquire_block_reason(gated.id), "Investor Target %d" % gated.min_investor_level,
		"At level 1 the gate is refused in the investor's words"
	)
	state.build[ROOM_CACHE_KEY] = "moon_facility"
	assert_eq(
		sim.perk_acquire_block_reason(gated.id), "Investor Target %d" % gated.min_investor_level,
		"Forcing the top room opens nothing: rooms are not levels"
	)
	sim.apply_infrastructure_tier(state, InfrastructureSystem.max_tier())
	assert_eq(
		sim.perk_acquire_block_reason(gated.id), "Investor Target %d" % gated.min_investor_level,
		"Buying the top infrastructure opens nothing either"
	)
	state.investor["level"] = gated.min_investor_level
	assert_true(
		sim.perk_acquire_block_reason(gated.id) != "Investor Target %d" % gated.min_investor_level,
		"Reaching the Investor Level is what opens it"
	)
	sim.free()
	_cleanup_profile()


func _test_asset_catalog_reads_the_room_off_the_tier() -> void:
	var build: Dictionary = {InfrastructureSystem.STATE_KEY: 1, ROOM_CACHE_KEY: "moon_facility"}
	assert_eq(
		AssetCatalog.dwelling_for_build(build), RoomProgression.room_at(1),
		"A stale room cache loses to the tier"
	)
	assert_eq(
		AssetCatalog.dwelling_for_build({}), RoomProgression.DEFAULT_ROOM,
		"No tier at all draws as the starting room"
	)
