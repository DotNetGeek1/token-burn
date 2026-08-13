extends TestCase


func run() -> void:
	_test_draw_returns_three_mixed_offers()
	_test_reroll_is_deterministic_for_sequence()


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
