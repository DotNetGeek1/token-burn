extends TestCase


func run() -> void:
	_test_draw_returns_three_perk_offers()
	_test_redraw_is_deterministic_for_sequence()
	_test_table_filters_perks_that_cannot_be_acquired()
	_test_rolodex_widens_the_table()


const SCRATCH_PROFILE := "user://profile_test_angel_draft.json"


func _sim() -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	return sim


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


## Rolodex no longer adds perk slots — there are none to add. Each rank lays
## one more card on the investor's table: four, then five, and no further.
func _test_rolodex_widens_the_table() -> void:
	var restore: Dictionary = _with_scratch_profile()
	var rolodex: Dictionary = MetaProgress.get_unlock("unlock.rolodex")
	assert_eq(str(rolodex.get("kind", "")), "draft_options", "Rolodex is a draft-size unlock")
	assert_eq(MetaProgress.draft_option_bonus(), 0, "A fresh profile adds no cards")
	assert_eq(MetaProgress.draft_option_count(), MetaProgress.BASE_DRAFT_OPTIONS, "Three cards to start")

	MetaProgress.bank_victory(1)
	assert_true(MetaProgress.spend_pick("unlock.rolodex"), "The first pick buys Rolodex rank 1")
	assert_eq(MetaProgress.draft_option_bonus(), 1, "Rank 1 adds one card")
	assert_eq(MetaProgress.draft_option_count(), 4, "Four on the table")

	var sim: Node = _sim()
	sim.start_run(4401)
	sim._redraw_angel_offers()
	assert_eq(sim.pending_choices.size(), 4, "The redraw deals 3 + the Rolodex bonus")
	sim.free()

	MetaProgress.bank_victory(1, "hard")
	assert_true(MetaProgress.spend_pick("unlock.rolodex"), "A Hard win buys rank 2")
	assert_eq(MetaProgress.draft_option_count(), MetaProgress.MAX_DRAFT_OPTIONS, "Five on the table")
	assert_eq(MetaProgress.MAX_DRAFT_OPTIONS, 5, "And five is the ceiling")
	assert_false(MetaProgress.is_available("unlock.rolodex"), "There is no third rank to sell")

	var wide: Node = _sim()
	wide.start_run(4402)
	wide._redraw_angel_offers()
	assert_eq(wide.pending_choices.size(), 5, "The redraw deals five")
	wide.free()
	_restore(restore)


func _test_draw_returns_three_perk_offers() -> void:
	var rng := DeterministicRng.new(4242)
	var state := RunState.new()
	state.reset()
	var offers: Array = ContentDatabase.draw_angel_perks(rng, state, 3, [], [])
	assert_eq(offers.size(), 3, "His Table draws three cards")
	for offer in offers:
		assert_eq(str(offer.get("type", "")), "perk", "Every offer is a perk")


func _test_redraw_is_deterministic_for_sequence() -> void:
	var sim_a: Node = _sim()
	var sim_b: Node = _sim()
	sim_a.start_run(777)
	sim_b.start_run(777)
	sim_a.run_state.build["draft_state"] = {"sequence": 2, "rerolls": 0}
	sim_b.run_state.build["draft_state"] = {"sequence": 2, "rerolls": 0}
	sim_a._redraw_angel_offers()
	sim_b._redraw_angel_offers()
	assert_eq(sim_a.pending_choices.size(), 3, "Redraw fills three offers")
	var ids_a: Array = []
	var ids_b: Array = []
	for choice in sim_a.pending_choices:
		ids_a.append("%s:%s" % [choice.get("type", ""), choice.get("id", "")])
	for choice in sim_b.pending_choices:
		ids_b.append("%s:%s" % [choice.get("type", ""), choice.get("id", "")])
	assert_eq(ids_a, ids_b, "Sequence-keyed angel RNG reproduces the same table")
	sim_a.free()
	sim_b.free()


func _test_table_filters_perks_that_cannot_be_acquired() -> void:
	var state := RunState.new()
	state.reset()
	state.build["modules"] = ["op.unit_tests"]
	state.build["perks"] = [
		"perk.thermal_paste",
		"perk.clean_compile",
		"perk.cool_operator",
		"perk.sustainable_engineering",
		"perk.audit_trail",
		"perk.enterprise_grade",
	]
	var system := PerkSystem.new()
	var blocked: Array = system.undraftable_ids(state, ContentDatabase)
	assert_true(
		"perk.move_fast_and_break_everything" in blocked,
		"A perk excluded by the build's permanent cards cannot be acquired"
	)
	assert_false(
		system.can_acquire(state, "perk.move_fast_and_break_everything", ContentDatabase),
		"undraftable is exactly the complement of can_acquire"
	)
	var offers: Array = ContentDatabase.draw_angel_perks(
		DeterministicRng.new(991),
		state,
		200,
		system.owned_tags(state, ContentDatabase),
		blocked
	)
	for offer in offers:
		assert_eq(str(offer.get("type", "")), "perk", "Angel offers are perk-only")
		assert_false(
			str(offer.get("id", "")) == "perk.move_fast_and_break_everything",
			"The table omits perks that cannot legally join the build"
		)
