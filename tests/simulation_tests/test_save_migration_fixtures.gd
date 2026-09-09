extends TestCase

## Historical save envelopes kept as fixtures so 1.0 does not rely on ad-hoc
## current-save tests. Each fixture must migrate without producing an impossible
## phase, negative job progress, or NaN cash.


const DWELLING_FIXTURES := [
	"bedroom", "garage", "office_unit", "warehouse",
	"datacentre_campus", "private_power_grid", "moon_facility",
]


func run() -> void:
	_test_v1_minimal_migrates()
	_test_corrupt_fixture_is_rejected()
	_test_current_save_round_trips()
	_test_dwelling_fixtures_migrate_to_cabinet_systems()
	_test_dwelling_fixtures_migrate_to_investor_levels()
	_test_v25_victory_fixture_has_completed_the_game()
	_test_v26_migration_is_idempotent()


## The v26 half of the room fixtures: rooms stop being progression. Each room
## reads back into the Infrastructure Tier it stood for (its index in the old
## campaign order), the contract it was playing for names the Investor Level,
## the campaign flags are gone, the module shelf is stamped for regeneration,
## and the cabinet's capacity is at least what the room's row promised.
func _test_dwelling_fixtures_migrate_to_investor_levels() -> void:
	var previous_bays: float = 0.0
	var previous_cooling: float = 0.0
	for index in range(DWELLING_FIXTURES.size()):
		var dwelling: String = str(DWELLING_FIXTURES[index])
		var payload: Dictionary = _read_fixture("dwelling_%s.json" % dwelling)
		var saved: Dictionary = Dictionary(payload.get("run_state", {}))
		var saved_flags: Dictionary = Dictionary(saved.get("flags", {}))
		assert_true(saved_flags.has("location_completed"), "%s fixture carries the old campaign flags" % dwelling)
		assert_false(saved_flags.has("game_completed"), "%s fixture predates game_completed" % dwelling)

		var state := RunState.new()
		state.from_dict(saved)

		assert_eq(
			int(state.build.get("infrastructure_tier", -1)), index,
			"%s: the room reads back as Infrastructure Tier %d" % [dwelling, index]
		)
		assert_eq(
			InfrastructureSystem.room_id(state, ContentDatabase), dwelling,
			"%s: and that tier shows the same room" % dwelling
		)
		assert_eq(
			int(state.investor.get("level", 0)), index + 1,
			"%s: the contract names Investor Level %d" % [dwelling, index + 1]
		)
		assert_eq(
			int(state.investor.get("targets_completed", -1)), index,
			"%s: with %d targets behind it" % [dwelling, index]
		)
		assert_eq(int(state.investor.get("activated_round", 0)), 1, "%s: activated_round is filled in" % dwelling)
		assert_eq(
			str(state.investor.get("contract_id", "")),
			str(Dictionary(saved.get("ascension", {})).get("contract_id", "")),
			"%s: the contract itself is preserved" % dwelling
		)
		for stale in ["location_completed", "next_location", "ascension_tier"]:
			assert_false(state.flags.has(stale), "%s: flags.%s is gone" % [dwelling, stale])
		assert_true(state.flags.has("game_completed"), "%s: game_completed exists" % dwelling)
		assert_false(bool(state.flags.get("game_completed", true)), "%s: a run mid-contract has not completed the game" % dwelling)
		assert_true(state.flags.has("target_complete"), "%s: target_complete exists" % dwelling)
		assert_false(bool(state.flags.get("target_complete", true)), "%s: nor met its target" % dwelling)
		var market: Dictionary = Dictionary(state.business.get("module_market", {}))
		assert_false(market.has("location"), "%s: the module shelf's old room-stamp key is gone" % dwelling)
		assert_eq(str(market.get("stamp", "x")), "", "%s: the module shelf's scale stamp is cleared" % dwelling)
		assert_eq(int(market.get("round", -1)), 0, "%s: and its round stamp, so the shelf regenerates" % dwelling)
		assert_false(state.build.has("dwelling"), "%s: the legacy room key is erased once its tier is derived" % dwelling)
		assert_eq(RoomProgression.room_for(state, ContentDatabase), dwelling, "%s: the room is drawn from the tier" % dwelling)

		# Capacity: the cabinet the migration derived must hold at least what
		# the room's old row granted — the tier the room reads back into is
		# what sizes the cabinet, so a wrong tier would show up here as a
		# warehouse loading with a bedroom's bays. The row is now the tier's
		# `floors` block in infrastructure.json.
		var bays: float = CabinetSystems.capacity(state, "backplane", "bays", ContentDatabase)
		var cooling: float = CabinetSystems.capacity(state, "cooling", "cooling_capacity", ContentDatabase)
		var legacy_row: Dictionary = Dictionary(InfrastructureSystem.entry(index, ContentDatabase).get("floors", {}))
		assert_true(
			cooling >= float(legacy_row.get("cooling_capacity", 0.0)),
			"%s: cooling %s >= the tier's floor %s" % [dwelling, str(cooling), str(legacy_row.get("cooling_capacity", 0.0))]
		)
		assert_true(
			bays >= previous_bays and cooling >= previous_cooling,
			"%s: bays %s / cooling %s never fall below the room before it (%s / %s)" % [
				dwelling, str(bays), str(cooling), str(previous_bays), str(previous_cooling),
			]
		)
		previous_bays = bays
		previous_cooling = cooling


## A v25 save that beat the Moon and carried on: it has completed the game, so
## it comes back at the final level with Deep Burn open to it and nothing left
## of the campaign flags.
func _test_v25_victory_fixture_has_completed_the_game() -> void:
	var payload: Dictionary = _read_fixture("v25_victory.json")
	assert_true(not payload.is_empty(), "v25 victory fixture parses")
	var saved: Dictionary = Dictionary(payload.get("run_state", {}))
	assert_eq(int(saved.get("save_version", 0)), 25, "The fixture is a v25 save")
	assert_true(bool(Dictionary(saved.get("flags", {})).get("post_victory", false)), "The fixture is post-victory")
	var state := RunState.new()
	state.from_dict(saved)
	assert_true(bool(state.flags.get("game_completed", false)), "A post-victory Moon save has completed the game")
	assert_false(bool(state.flags.get("target_complete", false)), "It is not waiting on a next target")
	assert_true(bool(state.flags.get("post_victory", false)), "post_victory is kept")
	assert_eq(
		int(state.investor.get("level", 0)), InvestorProgression.final_level(ContentDatabase),
		"The Final Prompt is the final level"
	)
	assert_eq(int(state.build.get("infrastructure_tier", -1)), 6, "The Moon is the top Infrastructure Tier")
	assert_true(DepthSystem.new().can_begin(state), "Deep Burn is open to it")
	for stale in ["location_completed", "next_location", "ascension_tier"]:
		assert_false(state.flags.has(stale), "flags.%s is gone" % stale)
	assert_eq(int(state.to_dict().get("save_version", 0)), RunState.SAVE_VERSION, "Saved back at the current version")


## Running a migrated save back through from_dict changes nothing: the level
## read out of the contract is now carried by the save itself.
func _test_v26_migration_is_idempotent() -> void:
	var payload: Dictionary = _read_fixture("dwelling_warehouse.json")
	var first := RunState.new()
	first.from_dict(Dictionary(payload.get("run_state", {})))
	var again := RunState.new()
	again.from_dict(first.to_dict())
	assert_eq(again.investor, first.investor, "The investor block round-trips unchanged")
	assert_eq(again.flags, first.flags, "So do the flags")
	assert_eq(
		int(again.build.get("infrastructure_tier", -1)), int(first.build.get("infrastructure_tier", -2)),
		"And the Infrastructure Tier"
	)


## Seven v22 saves, one parked in each of the old rooms, from before the cabinet
## systems existed. Each must come up at v23 with the entry tiers of the
## Infrastructure Tier the room now stands for (`cabinet_entry_tiers` in
## infrastructure.json), and nothing the player had — bays, workflows, floor,
## cash, the contract, the kit on the board — may be smaller than it was.
func _test_dwelling_fixtures_migrate_to_cabinet_systems() -> void:
	var order: Array = Array(ContentDatabase.cabinet_systems.get("migration_value_order", []))
	var board_system := BoardSystem.new()
	for dwelling in DWELLING_FIXTURES:
		var tier: int = InfrastructureSystem.tier_for_room(dwelling, ContentDatabase)
		var payload: Dictionary = _read_fixture("dwelling_%s.json" % dwelling)
		assert_true(not payload.is_empty(), "%s fixture parses" % dwelling)
		var saved: Dictionary = Dictionary(payload.get("run_state", {}))
		assert_eq(int(saved.get("save_version", 0)), 22, "%s fixture is a v22 save" % dwelling)
		var saved_build: Dictionary = Dictionary(saved.get("build", {}))
		assert_true(
			not saved_build.has("cabinet_systems"), "%s fixture predates cabinet systems" % dwelling
		)
		assert_eq(str(saved_build.get("dwelling", "")), dwelling, "%s fixture is parked in its room" % dwelling)

		var state := RunState.new()
		state.from_dict(saved)

		# Tiers: present for every system, whole numbers inside the range, and
		# exactly the entry tiers of the room's Infrastructure Tier.
		var tiers: Variant = state.build.get("cabinet_systems", null)
		assert_true(tiers is Dictionary, "%s migrates with a cabinet_systems block" % dwelling)
		var expected_row: Dictionary = InfrastructureSystem.cabinet_entry_tiers_at(tier, ContentDatabase)
		for i in range(order.size()):
			var system_id: String = str(order[i])
			var stored: Variant = Dictionary(tiers).get(system_id, null)
			assert_true(stored is int, "%s: %s tier is an int" % [dwelling, system_id])
			assert_true(
				int(stored) >= 1 and int(stored) <= 4, "%s: %s tier is inside 1..4" % [dwelling, system_id]
			)
			assert_eq(
				int(stored), int(expected_row.get(system_id, 0)),
				"%s: %s tier matches the tier's entry tiers" % [dwelling, system_id]
			)
		assert_eq(
			int(state.build.get("infrastructure_tier", -1)), tier,
			"%s: the room it was derived from is Infrastructure Tier %d" % [dwelling, tier]
		)
		assert_false(state.build.has("dwelling"), "%s: the legacy room key does not survive" % dwelling)

		# Capacities never shrink.
		var saved_slots: int = int(Dictionary(saved_build.get("board", {})).get("slot_count", 0))
		var saved_workflows: int = int(saved_build.get("workflow_capacity", 0))
		var saved_hardware: Array = Array(saved_build.get("hardware", []))
		var saved_heat_capacity: float = float(Dictionary(saved.get("compute", {})).get("heat_capacity", 0.0))
		# Safe capacity is the room's backplane tier and nothing more. A save
		# that was running a wider pipeline keeps every stage of it: the ones
		# past the rail are overflow now, not a tier it never bought and not a
		# phantom unlock.
		var backplane_tier: int = int(Dictionary(tiers).get("backplane", 0))
		var expected_safe: int = int(CabinetSystems.tier_value("backplane", "bays", backplane_tier))
		var saved_layout: Array = Array(
			Dictionary(Array(saved_build.get("workflows", []))[0]).get("slots", [])
		)
		board_system.ensure_board(state, ContentDatabase)
		assert_eq(
			board_system.derived_supported_capacity(state, ContentDatabase), expected_safe,
			"%s: safe capacity %d is the tier-%d backplane's bays" % [dwelling, expected_safe, backplane_tier]
		)
		assert_eq(
			board_system.slots(state).size(), maxi(expected_safe, saved_layout.size()),
			"%s: the %d-stage pipeline is kept (%d safe + %d overflow)" % [
				dwelling, saved_layout.size(), expected_safe, maxi(0, saved_layout.size() - expected_safe),
			]
		)
		assert_true(
			board_system.slots(state).size() >= saved_slots,
			"%s: pipeline %d >= saved slot_count %d" % [dwelling, board_system.slots(state).size(), saved_slots]
		)
		for index in range(saved_layout.size()):
			assert_eq(
				str(board_system.slots(state)[index]), str(saved_layout[index]),
				"%s: stage %d keeps its module" % [dwelling, index + 1]
			)
		var migrated_board: Dictionary = Dictionary(state.build.get("board", {}))
		assert_false(migrated_board.has("meta_slot_bonus"), "%s: meta_slot_bonus is renamed" % dwelling)
		assert_eq(
			int(migrated_board.get("meta_overflow_bonus", -1)), 0,
			"%s: no overflow bonus is invented to explain the wider pipeline" % dwelling
		)
		assert_true(
			board_system.derived_workflow_capacity(state, ContentDatabase) >= saved_workflows,
			"%s: workflow capacity %d >= saved %d" % [
				dwelling, board_system.derived_workflow_capacity(state, ContentDatabase), saved_workflows,
			]
		)
		assert_true(
			UpgradeSystem.hardware_slots_total(state, ContentDatabase)
				>= UpgradeSystem.hardware_slots_used(state, ContentDatabase),
			"%s: floor space still holds the kit that was racked" % dwelling
		)
		var legacy_row: Dictionary = Dictionary(InfrastructureSystem.entry(tier, ContentDatabase).get("floors", {}))
		assert_true(
			UpgradeSystem.hardware_slots_total(state, ContentDatabase) >= int(legacy_row.get("hardware_slots", 0)),
			"%s: hardware slots >= the tier's floor" % dwelling
		)
		assert_true(
			UpgradeSystem.infrastructure_cooling(state, ContentDatabase) >= float(legacy_row.get("cooling_capacity", 0.0)),
			"%s: cooling >= the tier's floor" % dwelling
		)
		assert_true(
			float(state.compute.get("heat_capacity", 0.0)) >= saved_heat_capacity,
			"%s: heat capacity %s >= saved %s" % [
				dwelling, str(state.compute.get("heat_capacity", 0.0)), str(saved_heat_capacity),
			]
		)

		# Everything the player had is still there.
		assert_eq(
			float(state.economy.get("cash", -1.0)),
			float(Dictionary(saved.get("economy", {})).get("cash", 0.0)),
			"%s: cash preserved" % dwelling
		)
		assert_eq(
			int(state.calendar.get("round", 0)),
			int(Dictionary(saved.get("calendar", {})).get("round", 0)),
			"%s: round preserved" % dwelling
		)
		assert_true(str(state.investor.get("contract_id", "")) != "", "%s: fixture carries a contract" % dwelling)
		assert_eq(
			str(state.investor.get("contract_id", "")),
			str(Dictionary(saved.get("ascension", {})).get("contract_id", "")),
			"%s: contract preserved" % dwelling
		)
		assert_eq(
			Array(state.build.get("modules", [])).size(),
			Array(saved_build.get("modules", [])).size(),
			"%s: modules preserved" % dwelling
		)
		assert_eq(
			Array(state.build.get("perks", [])).size(),
			Array(saved_build.get("perks", [])).size(),
			"%s: perks preserved" % dwelling
		)
		assert_eq(
			Array(state.build.get("workflows", [])).size(),
			Array(saved_build.get("workflows", [])).size(),
			"%s: workflows preserved" % dwelling
		)
		assert_eq(
			Array(state.build.get("hardware", [])).size(), 0,
			"%s: hardware converted to cabinet capacity" % dwelling
		)
		assert_eq(int(state.to_dict().get("save_version", 0)), RunState.SAVE_VERSION, "%s: saved back at the current version" % dwelling)
		var round_trip := RunState.new()
		round_trip.from_dict(state.to_dict())
		assert_eq(
			round_trip.build.get("cabinet_systems", {}), state.build.get("cabinet_systems", {}),
			"%s: cabinet_systems round-trips through to_dict/from_dict" % dwelling
		)


func _test_v1_minimal_migrates() -> void:
	var payload: Dictionary = _read_fixture("v1_minimal.json")
	assert_true(not payload.is_empty(), "v1 fixture parses")
	var state := RunState.new()
	state.from_dict(Dictionary(payload.get("run_state", {})))
	assert_true(state.compute.has("token_rate"), "v1 fixture fills compute")
	assert_eq(float(state.economy.get("cash", 0.0)), 250.0, "v1 cash survives")
	assert_true(float(state.economy.get("cash", 0.0)) >= 0.0, "cash is not negative")
	assert_true(int(state.calendar.get("round", 0)) >= 1, "round is valid")
	for job in Array(state.business.get("active_jobs", [])):
		if job is Dictionary:
			assert_true(float(job.get("tokens_remaining", 0.0)) >= 0.0, "job progress not negative")


func _test_corrupt_fixture_is_rejected() -> void:
	var path := "res://tests/fixtures/saves/corrupt.json"
	var parser := JSON.new()
	var text: String = FileAccess.get_file_as_string(path)
	assert_true(parser.parse(text) != OK, "Corrupt fixture is not valid JSON")


func _test_current_save_round_trips() -> void:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(404)
	var envelope := {
		"version": SaveManager.CURRENT_SAVE_VERSION,
		"phase": "ROUND_PREP",
		"seed": sim.run_seed,
		"run_state": sim.run_state.to_dict(),
		"pending_choices": [],
		"round_end_pending": false,
	}
	var restored := RunState.new()
	restored.from_dict(Dictionary(envelope.get("run_state", {})))
	assert_eq(
		float(restored.economy.get("cash", -1.0)),
		float(sim.run_state.economy.get("cash", 0.0)),
		"Current save cash round-trips"
	)
	assert_eq(int(restored.to_dict().get("save_version", 0)), RunState.SAVE_VERSION, "Current save is at SAVE_VERSION")
	sim.free()


func _read_fixture(name: String) -> Dictionary:
	var path := "res://tests/fixtures/saves/%s" % name
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
