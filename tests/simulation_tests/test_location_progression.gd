extends TestCase

## The campaign spine: where a run happens is decided before it starts, comes
## from the profile rather than from the run, and only moves when a location is
## cleared. These tests are about the boundary between the two layers — a run
## must not be able to change its own location, and a profile must not forget
## one it has earned.

const SCRATCH_PROFILE := "user://profile_location_test.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_a_fresh_profile_only_has_the_bedroom()
	_test_a_locked_location_cannot_be_selected()
	_test_a_run_starts_in_the_selected_location()
	_test_unlocks_outlive_a_run()
	_test_clearing_a_location_opens_the_next()
	_test_an_old_profile_migrates_without_losing_anything()
	_test_an_old_save_reopens_the_rung_it_was_on()
	_test_a_new_run_after_a_win_starts_fresh_in_the_bedroom()
	_test_the_permanent_rig_arrives_on_every_fresh_run()
	_test_each_location_stakes_the_run_for_its_own_rent()


func _sim() -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	return sim


## Every test here needs the meta layer on and pointed somewhere disposable:
## with it off, a run is forced to the first rung on purpose.
func _with_scratch_profile() -> Dictionary:
	var restore: Dictionary = {
		"path": MetaProgress.profile_path,
		"enabled": MetaProgress.enabled,
	}
	MetaProgress.enabled = true
	MetaProgress.use_scratch_profile(SCRATCH_PROFILE)
	return restore


func _restore(restore: Dictionary) -> void:
	if FileAccess.file_exists(SCRATCH_PROFILE):
		DirAccess.remove_absolute(SCRATCH_PROFILE)
	MetaProgress.profile_path = str(restore["path"])
	MetaProgress.enabled = bool(restore["enabled"])
	MetaProgress._loaded = false


func _test_a_fresh_profile_only_has_the_bedroom() -> void:
	var restore: Dictionary = _with_scratch_profile()

	assert_eq(
		MetaProgress.unlocked_locations(),
		["bedroom"],
		"A profile that has beaten nothing has one place to play"
	)
	assert_eq(MetaProgress.selected_location(), "bedroom", "And that is where the next run goes")
	assert_eq(MetaProgress.completed_locations(), [], "Nothing has been cleared yet")
	assert_eq(
		MetaProgress.location_order().front(),
		"bedroom",
		"The bedroom is the bottom of the campaign"
	)
	assert_eq(
		MetaProgress.next_location_after("moon_facility"),
		"",
		"And the moon is the top of it"
	)

	_restore(restore)


func _test_a_locked_location_cannot_be_selected() -> void:
	var restore: Dictionary = _with_scratch_profile()

	assert_false(MetaProgress.select_location("warehouse"), "A warehouse has not been earned")
	assert_eq(MetaProgress.selected_location(), "bedroom", "So the choice does not move")
	assert_false(MetaProgress.select_location("not_a_place"), "Nor does an id that is not a location")

	assert_true(MetaProgress.unlock_location("garage"), "Opening the garage is a real change")
	assert_false(MetaProgress.unlock_location("garage"), "Opening it twice is not")
	assert_true(MetaProgress.select_location("garage"), "And now it can be chosen")
	assert_eq(MetaProgress.selected_location(), "garage", "The next run goes to the garage")

	_restore(restore)


## A room stakes a run that starts in it with a machine as well as a float, and
## machines carry cooling of their own.
func _starter_rig_cooling(stats: Dictionary) -> float:
	var total: float = 0.0
	for upgrade_id in Array(stats.get("starting_hardware", [])):
		var upgrade: UpgradeDefinition = ContentDatabase.get_upgrade(str(upgrade_id))
		if upgrade == null:
			continue
		for effect in upgrade.effects:
			if effect is EffectDefinition and effect.target == "compute.cooling":
				total += float(effect.value)
	return total


func _test_a_run_starts_in_the_selected_location() -> void:
	var restore: Dictionary = _with_scratch_profile()
	MetaProgress.unlock_location("garage")
	MetaProgress.select_location("garage")

	var sim: Node = _sim()
	sim.start_run(7101)
	var garage: Dictionary = ContentDatabase.balance.get("dwelling_costs", {}).get("garage", {})
	assert_eq(
		str(sim.run_state.build.get("dwelling", "")),
		"garage",
		"The run begins where the profile said it would"
	)
	assert_almost_eq(
		float(sim.run_state.economy.get("round_rent", 0.0)),
		float(garage.get("rent", 0.0)),
		0.01,
		"Paying the garage's rent from round one"
	)
	assert_almost_eq(
		float(sim.run_state.compute.get("cooling", 0.0)),
		float(garage.get("cooling_capacity", 0.0)) + _starter_rig_cooling(garage),
		0.01,
		"With the garage's cooling and the machine it comes with, and nothing stacked underneath"
	)
	assert_eq(
		UpgradeSystem.hardware_slots_total(sim.run_state, ContentDatabase),
		int(garage.get("hardware_slots", 0)),
		"And the garage's floor space"
	)
	sim.free()

	_restore(restore)


func _test_unlocks_outlive_a_run() -> void:
	var restore: Dictionary = _with_scratch_profile()
	MetaProgress.unlock_location("garage")
	MetaProgress.select_location("garage")

	var sim: Node = _sim()
	sim.start_run(7102)
	sim.start_run(7103)
	assert_eq(
		str(sim.run_state.build.get("dwelling", "")),
		"garage",
		"Restarting keeps the location the profile owns"
	)
	assert_true(
		"garage" in MetaProgress.unlocked_locations(),
		"Losing and restarting never costs an unlock"
	)
	sim.free()

	_restore(restore)


func _test_clearing_a_location_opens_the_next() -> void:
	var restore: Dictionary = _with_scratch_profile()

	MetaProgress.complete_location("bedroom")
	assert_true("bedroom" in MetaProgress.completed_locations(), "The bedroom is recorded as beaten")
	assert_true("garage" in MetaProgress.unlocked_locations(), "Which is what opens the garage")
	assert_false(
		"office_unit" in MetaProgress.unlocked_locations(),
		"But only the next one, not the whole ladder"
	)

	MetaProgress.complete_location("bedroom")
	assert_eq(
		MetaProgress.completed_locations().size(),
		1,
		"Replaying a cleared location does not record it twice"
	)

	MetaProgress.complete_location("moon_facility")
	assert_true(
		"moon_facility" in MetaProgress.completed_locations(),
		"The last location can still be cleared"
	)

	_restore(restore)


func _test_an_old_profile_migrates_without_losing_anything() -> void:
	var restore: Dictionary = _with_scratch_profile()

	var legacy: Dictionary = {
		"version": 2,
		"victories": 3,
		"unlocks": {"unlock.cloud_account": 1},
		"pending_picks": 2,
		"achievements": {"ach.first_burn": 1700000000},
		"lifetime_stats": {"runs": 9.0},
		"difficulty": "hard",
	}
	var file := FileAccess.open(SCRATCH_PROFILE, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	MetaProgress._loaded = false
	MetaProgress._ensure_loaded()

	assert_eq(MetaProgress.unlocked_locations(), ["bedroom"], "A pre-campaign profile starts at the bottom")
	assert_eq(MetaProgress.selected_location(), "bedroom", "And has somewhere valid to play")
	assert_eq(MetaProgress.unlock_count("unlock.cloud_account"), 1, "Its unlocks survive the migration")
	assert_eq(MetaProgress.pending_picks(), 2, "So do its banked picks")
	assert_true(MetaProgress.has_achievement("ach.first_burn"), "And its achievements")
	assert_eq(MetaProgress.difficulty(), "hard", "And the difficulty it was set to")

	_restore(restore)


## A save from before the campaign existed can be mid-warehouse, having bought
## its way up. The profile has to catch up rather than leave the run somewhere
## it is no longer allowed to be.
func _test_an_old_save_reopens_the_rung_it_was_on() -> void:
	var restore: Dictionary = _with_scratch_profile()

	var sim: Node = _sim()
	sim.start_run(7104)
	sim.run_state.build["dwelling"] = "warehouse"
	sim.phase = sim.Phase.ROUND_PREP
	SaveManager.save_run(sim.run_state, "ROUND_PREP", sim.run_seed, sim.pending_choices, false)
	sim.free()

	var reloaded: Node = _sim()
	assert_true(reloaded.load_saved_run(), "The old save loads")
	assert_eq(
		str(reloaded.run_state.build.get("dwelling", "")),
		"warehouse",
		"And the run stays in the premises it had reached"
	)
	for location in ["bedroom", "garage", "office_unit", "warehouse"]:
		assert_true(
			location in MetaProgress.unlocked_locations(),
			"Everything up to that rung counts as earned (%s)" % location
		)
	assert_false(
		"datacentre_campus" in MetaProgress.unlocked_locations(),
		"But nothing above it is handed over"
	)
	reloaded.free()
	SaveManager.delete_save()

	_restore(restore)


## A "New Run" is a fresh game from the start. A chapter win continues in place
## through `advance_to_next_chapter`; nothing a finished run bought — kit, cash,
## modules — follows into a run started fresh, and the campaign selection stays
## at the bottom rather than moving to the location the win opened.
func _test_a_new_run_after_a_win_starts_fresh_in_the_bedroom() -> void:
	var restore: Dictionary = _with_scratch_profile()

	var sim: Node = _sim()
	sim.start_run(7110)
	sim.run_state.economy["cash"] = 5000000.0
	assert_true(sim.buy_upgrade("upgrade.custom_desktop"), "The bedroom run buys a desktop")
	# Winning the chapter opens the garage for the run that won it.
	sim.run_state.statistics["lifetime_tokens"] = 1e18
	sim.run_state.ascension["quality_sum"] = 100.0
	sim.run_state.ascension["quality_count"] = 1
	sim._finish_prompt({"ok": true, "messages": []})
	assert_true("garage" in MetaProgress.unlocked_locations(), "The win records the garage as earned")
	assert_eq(
		MetaProgress.selected_location(), "bedroom",
		"But a fresh run still starts at the bottom of the campaign"
	)
	assert_eq(MetaProgress.pending_picks(), 0, "And a chapter win banks nothing permanent")
	sim.free()

	var next_run: Node = _sim()
	next_run.start_run(7111)
	assert_eq(
		str(next_run.run_state.build.get("dwelling", "")), "bedroom",
		"A new run is a new game, from the bedroom"
	)
	assert_false(
		"custom_desktop" in Array(next_run.run_state.build.get("hardware", [])),
		"Nothing the old run bought comes along"
	)
	assert_true(
		float(next_run.run_state.economy.get("cash", 0.0)) < 5000000.0,
		"And neither does its bank balance"
	)
	next_run.free()

	_restore(restore)


## The one way hardware crosses runs: the permanent starting-rig ladder, bought
## with picks earned by beating the whole campaign. Each pick racks the next
## rung on every fresh run — as far as the room's floor allows — and a rung the
## bedroom had no space for arrives with the first bigger room.
func _test_the_permanent_rig_arrives_on_every_fresh_run() -> void:
	var restore: Dictionary = _with_scratch_profile()

	MetaProgress.bank_victory(2)
	assert_true(MetaProgress.spend_pick("unlock.starting_rig"), "The first pick buys the desktop")
	assert_true(MetaProgress.spend_pick("unlock.starting_rig"), "The second buys the GPU rack")

	var sim: Node = _sim()
	sim.start_run(7112)
	var hardware: Array = Array(sim.run_state.build.get("hardware", []))
	assert_true("custom_desktop" in hardware, "The desktop is racked from round one")
	assert_false(
		"gpu_rack" in hardware,
		"The bedroom's floor is full, so the rack waits for a bigger room"
	)

	# Winning the chapter and moving up racks the rung that did not fit.
	sim.run_state.economy["cash"] = 5000000.0
	sim.run_state.statistics["lifetime_tokens"] = 1e18
	sim.run_state.ascension["quality_sum"] = 100.0
	sim.run_state.ascension["quality_count"] = 1
	sim._finish_prompt({"ok": true, "messages": []})
	assert_true(sim.advance_to_next_chapter(), "The win moves the company into the garage")
	assert_true(
		"gpu_rack" in Array(sim.run_state.build.get("hardware", [])),
		"Where the earned GPU rack is finally racked"
	)
	sim.free()

	# The ladder has a top: once every rung is owned it stops being offered.
	MetaProgress.bank_victory(3)
	assert_true(MetaProgress.spend_pick("unlock.starting_rig"), "The third pick buys the cluster")
	assert_true(MetaProgress.spend_pick("unlock.starting_rig"), "The fourth buys the garage datacentre")
	assert_true(MetaProgress.spend_pick("unlock.starting_rig"), "The fifth buys the compute warehouse")
	assert_false(
		MetaProgress.is_available("unlock.starting_rig"),
		"And there is no sixth rung to sell"
	)

	_restore(restore)


## A chapter whose rent is three times the last one's cannot be started on the
## last one's float, so each location stakes the run for its own bills.
func _test_each_location_stakes_the_run_for_its_own_rent() -> void:
	var restore: Dictionary = _with_scratch_profile()

	var sim: Node = _sim()
	sim.start_run(7113)
	for location in ["bedroom", "garage", "office_unit", "warehouse"]:
		Simulation.apply_run_location(sim.run_state, location)
		assert_true(
			float(sim.run_state.economy.get("cash", 0.0))
				> float(sim.run_state.economy.get("round_rent", 0.0)),
			"%s starts with more than one round's rent in hand" % location
		)
	sim.free()

	_restore(restore)
