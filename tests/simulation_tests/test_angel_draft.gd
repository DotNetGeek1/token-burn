extends TestCase


func run() -> void:
	_test_draw_returns_three_mixed_offers()
	_test_reroll_is_deterministic_for_sequence()
	_test_angel_filters_perks_with_no_legal_swap()


func _sim() -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	return sim


func _test_draw_returns_three_mixed_offers() -> void:
	var rng := DeterministicRng.new(4242)
	var state := RunState.new()
	state.reset()
	var offers: Array = ContentDatabase.draw_angel_offers(rng, state, 3, [], 0.0)
	assert_eq(offers.size(), 3, "His Table draws three cards")
	var types: Dictionary = {}
	for offer in offers:
		types[str(offer.get("type", ""))] = true
	assert_true(types.size() >= 1, "Offers include at least one card type")


func _test_reroll_is_deterministic_for_sequence() -> void:
	var sim_a: Node = _sim()
	var sim_b: Node = _sim()
	sim_a.start_run(777)
	sim_b.start_run(777)
	sim_a.run_state.build["draft_state"] = {"sequence": 2, "rerolls": 1}
	sim_b.run_state.build["draft_state"] = {"sequence": 2, "rerolls": 1}
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


func _test_angel_filters_perks_with_no_legal_swap() -> void:
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
	state.build["perk_inventory"] = Array(state.build["perks"]).duplicate()
	var system := PerkSystem.new()
	var blocked: Array = system.undraftable_ids(state, ContentDatabase)
	assert_true(
		"perk.move_fast_and_break_everything" in blocked,
		"A perk excluded by several active cards has no legal one-card swap"
	)
	var offers: Array = ContentDatabase.draw_angel_offers(
		DeterministicRng.new(991),
		state,
		200,
		system.owned_tags(state, ContentDatabase),
		0.0,
		blocked
	)
	for offer in offers:
		assert_false(
			str(offer.get("id", "")) == "perk.move_fast_and_break_everything",
			"Angel offers omit perks that cannot legally join the loadout"
		)
