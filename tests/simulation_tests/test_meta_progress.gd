extends TestCase

## Meta-progression is the only state that outlives a run, so these cover what a
## player is promised across runs: a win banks exactly one pick, spending it
## changes the next run, the slot cap holds, and the profile survives a restart.
##
## Every test here runs against a scratch profile. The suite must never touch the
## profile the developer is playing.

const SCRATCH_PROFILE := "user://profile_test.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var restore_path: String = MetaProgress.profile_path
	var restore_enabled: bool = MetaProgress.enabled
	MetaProgress.enabled = true

	_test_a_victory_banks_one_pick()
	_test_a_loss_banks_nothing()
	_test_an_extra_slot_widens_the_next_run()
	_test_the_slot_cap_holds()
	_test_a_starting_module_arrives_owned()
	_test_the_profile_survives_a_restart()
	_test_a_disabled_meta_layer_leaves_a_run_alone()
	_test_difficulty_choice_carries_into_a_new_run()
	_test_endless_stays_locked_without_a_tier_3_ascension()
	_test_endless_keeps_the_run_going_past_round_twelve()

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


func _test_a_victory_banks_one_pick() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9001)
	sim._end_run(true)
	assert_eq(MetaProgress.victories(), 1, "Surviving the year counts as a victory")
	assert_eq(MetaProgress.pending_picks(), 1, "A victory banks exactly one pick")

	var choices: Array = sim.debrief_choices()
	assert_eq(choices.size(), 3, "The debrief offers three unlocks")
	var repeated: Array = sim.debrief_choices()
	assert_eq(
		str(choices[0].get("id", "")),
		str(repeated[0].get("id", "")),
		"Reopening the debrief shows the same three, not a reroll"
	)

	assert_true(sim.spend_debrief_pick(str(choices[0].get("id", ""))), "The pick can be spent")
	assert_eq(MetaProgress.pending_picks(), 0, "And it is spent only once")
	assert_false(
		sim.spend_debrief_pick(str(choices[1].get("id", ""))),
		"A second unlock cannot be taken on one victory"
	)
	sim.free()


func _test_a_loss_banks_nothing() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9002)
	sim._end_run(false)
	assert_eq(MetaProgress.victories(), 0, "Collapsing is not a victory")
	assert_eq(MetaProgress.pending_picks(), 0, "And it pays nothing into the profile")
	assert_true(sim.debrief_choices().is_empty(), "So there is no debrief to sit through")
	sim.free()


func _test_an_extra_slot_widens_the_next_run() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9003)
	var slots_before: int = sim.board_slots().size()

	MetaProgress.bank_victory()
	assert_true(MetaProgress.spend_pick("unlock.extra_slot"), "An extra slot can be kept")

	sim.start_run(9003)
	assert_eq(sim.board_slots().size(), slots_before + 1, "The next run starts one slot wider")
	assert_true(
		sim.filled_slot_count() >= slots_before,
		"And the pipeline it opens with is at least as long as before"
	)
	sim.free()


func _test_the_slot_cap_holds() -> void:
	_fresh_profile()
	var wanted: int = BoardSystem.MAX_SLOT_COUNT - BoardSystem.DEFAULT_SLOT_COUNT
	for _i in range(wanted):
		MetaProgress.bank_victory()
		assert_true(MetaProgress.spend_pick("unlock.extra_slot"), "Slots stack up to the cap")
	assert_false(
		MetaProgress.is_available("unlock.extra_slot"),
		"At the cap the board can take no more, so it stops being offered"
	)
	MetaProgress.bank_victory()
	assert_false(MetaProgress.spend_pick("unlock.extra_slot"), "And it cannot be bought anyway")

	var sim: Node = _sim()
	sim.start_run(9004)
	assert_eq(sim.board_slots().size(), BoardSystem.MAX_SLOT_COUNT, "The widest board is the cap")
	sim.free()


func _test_a_starting_module_arrives_owned() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9005)
	assert_false("op.linter" in sim.owned_operations(), "The linter is not a starter by default")

	MetaProgress.bank_victory()
	assert_true(MetaProgress.spend_pick("unlock.starting_module_linter"), "It can be kept")
	sim.start_run(9005)
	assert_true("op.linter" in sim.owned_operations(), "And the next run starts owning it")
	assert_false(
		MetaProgress.is_available("unlock.starting_module_linter"),
		"Keeping the same module twice would do nothing, so it is not offered again"
	)
	sim.free()


func _test_the_profile_survives_a_restart() -> void:
	_fresh_profile()
	MetaProgress.bank_victory()
	MetaProgress.spend_pick("unlock.starting_cash")
	MetaProgress.bank_victory()
	MetaProgress.spend_pick("unlock.starting_cash")

	# Same file, read from scratch: what a player gets when they reopen the game.
	MetaProgress._loaded = false
	MetaProgress._ensure_loaded()
	assert_eq(MetaProgress.victories(), 2, "Victories round-trip through JSON")
	assert_eq(MetaProgress.unlock_count("unlock.starting_cash"), 2, "So do repeated unlocks")
	assert_eq(MetaProgress.pending_picks(), 0, "And so does an empty bank")

	var unlock: Dictionary = MetaProgress.get_unlock("unlock.starting_cash")
	var sim: Node = _sim()
	sim.start_run(9006)
	assert_almost_eq(
		float(sim.run_state.economy.get("cash", 0.0)),
		500.0 + 2.0 * float(unlock.get("amount", 0.0)),
		0.01,
		"Both stacks of the cash unlock are in the next run's balance"
	)
	sim.free()


func _test_difficulty_choice_carries_into_a_new_run() -> void:
	_fresh_profile()
	MetaProgress.set_difficulty("hard")
	assert_eq(MetaProgress.difficulty(), "hard", "The choice is remembered")
	var sim: Node = _sim()
	sim.start_run(9101)
	var hard_cash: float = float(sim.run_state.economy.get("cash", 0.0))
	sim.free()

	MetaProgress.set_difficulty("normal")
	var sim_normal: Node = _sim()
	sim_normal.start_run(9101)
	var normal_cash: float = float(sim_normal.run_state.economy.get("cash", 0.0))
	sim_normal.free()

	assert_true(hard_cash < normal_cash, "Hard starts with less cash than normal, per the difficulty profile")


func _test_endless_stays_locked_without_a_tier_3_ascension() -> void:
	_fresh_profile()
	assert_false(MetaProgress.endless_unlocked(), "A fresh profile has not proven it can reach a real ending")
	MetaProgress.set_endless_enabled(true)
	assert_false(MetaProgress.endless_enabled(), "Toggling it on does nothing until it is actually unlocked")

	MetaProgress.record_ascension("ascension.the_monopoly")
	assert_true(MetaProgress.endless_unlocked(), "Completing a Tier 3 contract unlocks it")
	assert_true(MetaProgress.endless_enabled(), "The earlier toggle now takes effect")


func _test_endless_keeps_the_run_going_past_round_twelve() -> void:
	_fresh_profile()
	MetaProgress.record_ascension("ascension.the_monopoly")
	MetaProgress.set_endless_enabled(true)

	var sim: Node = _sim()
	sim.start_run(9102)
	sim.run_state.calendar["round"] = 12
	var rent_before: float = float(sim.run_state.economy.get("round_rent", 400.0))
	sim._end_round()
	assert_true(sim.phase != sim.Phase.RUN_END, "The run keeps going instead of ending at round 12")
	assert_eq(int(sim.run_state.calendar["round"]), 13, "The calendar rolls past twelve")
	assert_true(
		float(sim.run_state.economy.get("round_rent", 0.0)) > rent_before,
		"Endless rounds escalate costs so it stays a real challenge"
	)
	sim.free()


func _test_a_disabled_meta_layer_leaves_a_run_alone() -> void:
	_fresh_profile()
	MetaProgress.bank_victory()
	MetaProgress.spend_pick("unlock.extra_slot")

	MetaProgress.enabled = false
	var sim: Node = _sim()
	sim.start_run(9007)
	assert_eq(
		sim.board_slots().size(),
		BoardSystem.DEFAULT_SLOT_COUNT,
		"With the meta layer off a run starts from nothing, whatever is in the profile"
	)
	sim._end_run(true)
	assert_eq(MetaProgress.pending_picks(), 0, "And a victory banks nothing it could spend")
	sim.free()
	MetaProgress.enabled = true
