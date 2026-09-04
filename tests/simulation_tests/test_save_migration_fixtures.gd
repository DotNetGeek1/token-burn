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


## Seven v22 saves, one parked in each chapter's room, from before the cabinet
## systems existed. Each must come up at v23 with the tiers the migration table
## says the room is worth, and nothing the player had — bays, workflows, floor,
## cash, the contract, the kit on the board — may be smaller than it was.
func _test_dwelling_fixtures_migrate_to_cabinet_systems() -> void:
	var table: Dictionary = Dictionary(ContentDatabase.cabinet_systems.get("migration_from_dwelling", {}))
	var order: Array = Array(ContentDatabase.cabinet_systems.get("migration_value_order", []))
	var board_system := BoardSystem.new()
	for dwelling in DWELLING_FIXTURES:
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
		# exactly the table's row for the room.
		var tiers: Variant = state.build.get("cabinet_systems", null)
		assert_true(tiers is Dictionary, "%s migrates with a cabinet_systems block" % dwelling)
		var expected_row: Array = Array(table.get(dwelling, []))
		for i in range(order.size()):
			var system_id: String = str(order[i])
			var stored: Variant = Dictionary(tiers).get(system_id, null)
			assert_true(stored is int, "%s: %s tier is an int" % [dwelling, system_id])
			assert_true(
				int(stored) >= 1 and int(stored) <= 4, "%s: %s tier is inside 1..4" % [dwelling, system_id]
			)
			assert_eq(
				int(stored), int(expected_row[i]),
				"%s: %s tier matches the migration table" % [dwelling, system_id]
			)
		assert_eq(
			str(Dictionary(state.build.get("migration_debug", {})).get("dwelling", "")),
			dwelling,
			"%s: migration_debug records the dwelling it was derived from" % dwelling
		)

		# Capacities never shrink.
		var saved_slots: int = int(Dictionary(saved_build.get("board", {})).get("slot_count", 0))
		var saved_workflows: int = int(saved_build.get("workflow_capacity", 0))
		var saved_hardware: Array = Array(saved_build.get("hardware", []))
		var saved_heat_capacity: float = float(Dictionary(saved.get("compute", {})).get("heat_capacity", 0.0))
		assert_true(
			board_system.derived_supported_capacity(state, ContentDatabase) >= saved_slots,
			"%s: board capacity %d >= saved %d" % [
				dwelling, board_system.derived_supported_capacity(state, ContentDatabase), saved_slots,
			]
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
		var legacy_row: Dictionary = Dictionary(
			Dictionary(ContentDatabase.balance.get("dwelling_costs", {})).get(dwelling, {})
		)
		assert_true(
			UpgradeSystem.hardware_slots_total(state, ContentDatabase) >= int(legacy_row.get("hardware_slots", 0)),
			"%s: hardware slots >= the room's row" % dwelling
		)
		assert_true(
			UpgradeSystem.location_cooling(state, ContentDatabase) >= float(legacy_row.get("cooling_capacity", 0.0)),
			"%s: cooling >= the room's row" % dwelling
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
		assert_true(str(state.ascension.get("contract_id", "")) != "", "%s: fixture carries a contract" % dwelling)
		assert_eq(
			str(state.ascension.get("contract_id", "")),
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
			Array(state.build.get("hardware", [])).size(), saved_hardware.size(),
			"%s: hardware preserved" % dwelling
		)
		assert_eq(int(state.to_dict().get("save_version", 0)), RunState.SAVE_VERSION, "%s: saved back at v23" % dwelling)
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
