extends TestCase

const PerkSystemScript := preload("res://systems/perk_system.gd")


func run() -> void:
	_test_org_chart_raises_capacity()
	_test_bench_capacity_perk_blocked_when_full()
	_test_swap_works_at_a_full_loadout()
	_test_swap_clears_a_conflict()
	_test_a_refused_swap_leaves_the_loadout_alone()


func _perk_system() -> PerkSystem:
	return PerkSystemScript.new()


func _fresh_run() -> RunState:
	var state := RunState.new()
	state.reset()
	return state


func _fill_active(system: PerkSystem, state: RunState, count: int) -> void:
	var filled: int = 0
	for perk in ContentDatabase.perks:
		if filled >= count:
			break
		if system.can_collect(state, perk.id, ContentDatabase):
			system.collect_perk(state, perk.id, ContentDatabase)
			if system.can_equip(state, perk.id, ContentDatabase):
				system.equip_perk(state, perk.id, ContentDatabase)
				filled += 1


func _test_org_chart_raises_capacity() -> void:
	var system := _perk_system()
	var state := _fresh_run()
	var base: int = system.perk_capacity(state, ContentDatabase)
	assert_true(system.collect_perk(state, "perk.org_chart", ContentDatabase), "Org Chart can be collected")
	assert_true(system.equip_perk(state, "perk.org_chart", ContentDatabase), "Org Chart can be equipped")
	assert_eq(
		system.perk_capacity(state, ContentDatabase),
		base + 2,
		"Org Chart grants two active perk slots"
	)


func _test_bench_capacity_perk_blocked_when_full() -> void:
	var system := _perk_system()
	var state := _fresh_run()
	assert_true(system.collect_perk(state, "perk.org_chart", ContentDatabase), "Collect capacity perk")
	assert_true(system.equip_perk(state, "perk.org_chart", ContentDatabase), "Equip capacity perk")
	var cap: int = system.perk_capacity(state, ContentDatabase)
	_fill_active(system, state, cap - 1)
	var reason: String = system.bench_block_reason(state, "perk.org_chart", ContentDatabase)
	assert_false(reason == "", "Benching a capacity perk is blocked while the loadout is full")


## A swap is the only way into a full loadout, so it has to judge the incoming
## perk against the loadout it leaves behind rather than the one it replaces.
func _test_swap_works_at_a_full_loadout() -> void:
	var system := _perk_system()
	var state := _fresh_run()
	var cap: int = system.perk_capacity(state, ContentDatabase)
	_fill_active(system, state, cap)
	assert_eq(state.build["perks"].size(), cap, "The loadout is full")
	var incoming: String = ""
	for perk in ContentDatabase.perks:
		if perk.id in state.build["perk_inventory"]:
			continue
		if system.collect_perk(state, perk.id, ContentDatabase):
			incoming = perk.id
			break
	assert_false(incoming == "", "There is a benched perk to bring in")
	assert_false(
		system.can_equip(state, incoming, ContentDatabase),
		"It cannot simply be equipped, because there is no room"
	)
	var outgoing: String = str(state.build["perks"][0])
	assert_true(
		system.can_swap(state, outgoing, incoming, ContentDatabase),
		"But it can take an active perk's place"
	)
	assert_true(system.swap_perk(state, outgoing, incoming, ContentDatabase), "The swap goes through")
	assert_true(incoming in state.build["perks"], "The incoming perk is now active")
	assert_false(outgoing in state.build["perks"], "And the outgoing one is on the bench")
	assert_true(outgoing in state.build["perk_inventory"], "Benched, not lost")
	assert_eq(state.build["perks"].size(), cap, "The loadout is still exactly full")


## Swapping out the perk that conflicts is how a build changes direction, so the
## conflict must be judged after the outgoing perk has left.
func _test_swap_clears_a_conflict() -> void:
	var system := _perk_system()
	var state := _fresh_run()
	assert_true(system.collect_perk(state, "perk.thermal_paste", ContentDatabase), "Collect the paste")
	assert_true(system.collect_perk(state, "perk.hot_streak", ContentDatabase), "Collect the runaway")
	assert_true(system.equip_perk(state, "perk.thermal_paste", ContentDatabase), "Equip the paste")
	assert_false(
		system.can_equip(state, "perk.hot_streak", ContentDatabase),
		"The two cannot both be active"
	)
	assert_true(
		system.can_swap(state, "perk.thermal_paste", "perk.hot_streak", ContentDatabase),
		"But one can replace the other"
	)
	assert_true(
		system.swap_perk(state, "perk.thermal_paste", "perk.hot_streak", ContentDatabase),
		"And the swap goes through"
	)
	assert_true("perk.hot_streak" in state.build["perks"], "Thermal Runaway took the slot")
	assert_false("perk.thermal_paste" in state.build["perks"], "The paste stood down")


func _test_a_refused_swap_leaves_the_loadout_alone() -> void:
	var system := _perk_system()
	var state := _fresh_run()
	assert_true(system.collect_perk(state, "perk.org_chart", ContentDatabase), "Collect Org Chart")
	assert_true(system.equip_perk(state, "perk.org_chart", ContentDatabase), "Equip Org Chart")
	var before: Array = state.build["perks"].duplicate()
	assert_false(
		system.swap_perk(state, "perk.org_chart", "perk.not_a_real_perk", ContentDatabase),
		"A swap for a perk that does not exist is refused"
	)
	assert_eq(state.build["perks"], before, "And the loadout is untouched")
