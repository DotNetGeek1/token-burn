extends TestCase

## Cooling is derived, not accumulated. The bug this replaces: moving premises
## added the new location's cooling on top of whatever was already there, so a
## warehouse run was quietly carrying the bedroom, the garage and the office as
## well. Anything that recomputes the rig — buying, selling, saving, loading,
## simply recalculating — has to arrive at the same number every time.

const SCRATCH_PROFILE := "user://profile_cooling_test.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_a_location_contributes_its_cooling_exactly_once()
	_test_buying_cooling_adds_exactly_what_the_card_promises()
	_test_selling_cooling_takes_exactly_that_back()
	_test_recalculating_never_changes_the_answer()
	_test_save_and_load_does_not_duplicate_cooling()
	_test_an_old_save_sheds_its_accumulated_cooling()
	_test_a_permanent_unlock_survives_recalculation()


func _sim(seed_value: int, location: String = "bedroom") -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(seed_value)
	# The subject is the room's own cooling budget, so the machine the room comes
	# with — which carries cooling of its own — is left out of the sum.
	sim.apply_run_location(sim.run_state, location, false)
	sim.run_state.economy["cash"] = 1.0e12
	sim._compute_system.recalculate(
		sim.run_state, sim.effect_resolver, sim._collect_subscriptions(), sim.rng
	)
	return sim


func _cooling(sim: Node) -> float:
	return float(sim.run_state.compute.get("cooling", 0.0))


func _location_cooling(location: String) -> float:
	return float(
		ContentDatabase.balance.get("dwelling_costs", {}).get(location, {}).get("cooling_capacity", 0.0)
	)


## The headline acceptance criterion: a warehouse run has warehouse cooling, not
## bedroom plus garage plus office plus warehouse.
func _test_a_location_contributes_its_cooling_exactly_once() -> void:
	for location in ["bedroom", "garage", "office_unit", "warehouse", "datacentre_campus"]:
		var sim: Node = _sim(8100, location)
		# The starter laptop is not cooling kit, so the run's whole cooling
		# budget at this point is the room it is standing in.
		assert_almost_eq(
			_cooling(sim),
			_location_cooling(location),
			0.01,
			"A %s run is cooled by the %s and nothing underneath it" % [location, location]
		)
		sim.free()

	var chain: float = 0.0
	for location in ["bedroom", "garage", "office_unit", "warehouse"]:
		chain += _location_cooling(location)
	var warehouse: Node = _sim(8101, "warehouse")
	assert_true(
		_cooling(warehouse) < chain,
		"And is not carrying every chapter below it (%d, not %d)" % [
			int(_cooling(warehouse)), int(chain),
		]
	)
	warehouse.free()


func _test_buying_cooling_adds_exactly_what_the_card_promises() -> void:
	var sim: Node = _sim(8102, "garage")
	var before: float = _cooling(sim)
	var rig: UpgradeDefinition = ContentDatabase.get_upgrade("upgrade.immersion_cooling")
	assert_true(sim.buy_upgrade("upgrade.immersion_cooling"), "The immersion rig is bought")
	assert_almost_eq(
		_cooling(sim),
		before + UpgradeSystem.cooling_from(rig),
		0.01,
		"Cooling goes up by exactly what the card advertises"
	)

	assert_true(sim.buy_upgrade("upgrade.immersion_cooling"), "And a second one")
	assert_almost_eq(
		_cooling(sim),
		before + UpgradeSystem.cooling_from(rig) * 2.0,
		0.01,
		"Two of them are worth twice one of them"
	)
	sim.free()


func _test_selling_cooling_takes_exactly_that_back() -> void:
	var sim: Node = _sim(8103, "garage")
	var before: float = _cooling(sim)
	assert_true(sim.buy_upgrade("upgrade.immersion_cooling"), "Buy a cooler")
	assert_true(_cooling(sim) > before, "Which raises cooling")
	assert_true(sim.sell_hardware("immersion_cooling"), "Then sell it again")
	assert_almost_eq(
		_cooling(sim),
		before,
		0.01,
		"And cooling comes back to exactly where it started"
	)
	sim.free()


## Recalculation happens every round, after every purchase and on every load.
## A cooling figure that moved when nothing else did was the original bug.
func _test_recalculating_never_changes_the_answer() -> void:
	var sim: Node = _sim(8104, "office_unit")
	assert_true(sim.buy_upgrade("upgrade.industrial_chiller"), "A chiller for the office")
	var settled: float = _cooling(sim)
	for _i in range(5):
		sim._compute_system.recalculate(
			sim.run_state, sim.effect_resolver, sim._collect_subscriptions(), sim.rng
		)
	assert_almost_eq(
		_cooling(sim), settled, 0.01, "Recalculating five more times changes nothing"
	)
	sim.free()


func _test_save_and_load_does_not_duplicate_cooling() -> void:
	var sim: Node = _sim(8105, "warehouse")
	assert_true(sim.buy_upgrade("upgrade.chilled_water_plant"), "A cooling plant for the warehouse")
	var before: float = _cooling(sim)
	SaveManager.save_run(sim.run_state, "ROUND_PREP", sim.run_seed, sim.pending_choices, false)
	sim.free()

	var reloaded: Node = load("res://core/simulation.gd").new()
	reloaded.autosave_enabled = false
	assert_true(reloaded.load_saved_run(), "The run loads")
	assert_almost_eq(
		_cooling(reloaded), before, 0.01, "With the cooling it went to bed with, counted once"
	)
	reloaded.free()
	SaveManager.delete_save()


## A save written under the old rules is carrying the whole property ladder's
## cooling. Loading it has to arrive at the same figure a fresh run in that
## location would have, not keep the inflated one.
func _test_an_old_save_sheds_its_accumulated_cooling() -> void:
	var legacy: Dictionary = {
		"save_version": 9,
		"build": {"dwelling": "warehouse", "hardware": ["used_laptop"]},
		"compute": {"cooling": 2616.0},
	}
	var migrated := RunState.new()
	migrated.from_dict(legacy)
	assert_eq(
		str(migrated.build.get("dwelling", "")),
		"warehouse",
		"The run is still in the warehouse it was saved in"
	)
	assert_almost_eq(
		ComputeSystem.derive_cooling(migrated),
		_location_cooling("warehouse"),
		0.01,
		"But its cooling is the warehouse's, not the ladder it climbed to get there"
	)


## The one contribution that cannot be read back off the run, so it is kept in
## its own field rather than folded into a total that gets recomputed.
func _test_a_permanent_unlock_survives_recalculation() -> void:
	var restore_path: String = MetaProgress.profile_path
	var restore_enabled: bool = MetaProgress.enabled
	MetaProgress.enabled = true
	MetaProgress.use_scratch_profile(SCRATCH_PROFILE)
	MetaProgress.bank_victory()
	assert_true(MetaProgress.spend_pick("unlock.cooling"), "The cooling unlock is kept")
	var bonus: float = MetaProgress.cooling_bonus()
	assert_true(bonus > 0.0, "And it is worth something")

	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(8106)
	assert_almost_eq(
		_cooling(sim),
		_location_cooling("bedroom") + bonus,
		0.01,
		"A fresh run starts with the room's cooling plus what was unlocked"
	)
	sim._compute_system.recalculate(
		sim.run_state, sim.effect_resolver, sim._collect_subscriptions(), sim.rng
	)
	assert_almost_eq(
		_cooling(sim),
		_location_cooling("bedroom") + bonus,
		0.01,
		"And recalculating does not lose it"
	)
	sim.free()

	if FileAccess.file_exists(SCRATCH_PROFILE):
		DirAccess.remove_absolute(SCRATCH_PROFILE)
	MetaProgress.profile_path = restore_path
	MetaProgress.enabled = restore_enabled
	MetaProgress._loaded = false
