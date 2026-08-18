extends PlaytestCase

## Perk loadout changes live on the cards themselves. The old right-hand detail
## panel is gone, so a fitted card unequips directly and a bench card equips into
## the slot it frees.


func play(harness: UiHarness) -> void:
	await harness.boot(79)
	var pair: Dictionary = _prepare_full_loadout()
	assert_true(not pair.is_empty(), "A full test loadout has a legal perk swap")
	if pair.is_empty():
		return

	await harness.goto_route("build")
	var venue: Node = harness.current_scene()
	var outgoing: String = str(pair.get("out", ""))
	var incoming: String = str(pair.get("in", ""))
	var outgoing_tile: VenueTile = _visible_tile(venue._board, outgoing)
	assert_true(outgoing_tile != null, "The fitted outgoing perk is selectable")
	if outgoing_tile == null:
		return
	assert_true(
		outgoing_tile._action.visible
		and outgoing_tile._action.text == "UNEQUIP"
		and not outgoing_tile._action.disabled,
		"A fitted perk carries its own enabled UNEQUIP button"
	)
	await harness.driver.press(outgoing_tile._action)
	assert_false(
		outgoing in Array(Simulation.run_state.build.get("perks", [])),
		"UNEQUIP moves the fitted perk to the bench immediately"
	)

	var bench: Control = harness.driver.command("ON THE BENCH")
	assert_true(bench != null, "The bench rack remains reachable")
	if bench == null:
		return
	await harness.driver.press(bench)

	var incoming_tile: VenueTile = _visible_tile(venue._board, incoming)
	assert_true(incoming_tile != null, "The incoming benched perk is selectable")
	if incoming_tile == null:
		return
	assert_true(
		incoming_tile._action.visible
		and incoming_tile._action.text == "EQUIP"
		and not incoming_tile._action.disabled,
		"A benched perk carries its own enabled EQUIP button"
	)
	await harness.driver.press(incoming_tile._action)
	var active: Array = Array(Simulation.run_state.build.get("perks", []))
	assert_true(incoming in active, "The incoming perk is fitted")
	assert_false(outgoing in active, "The outgoing perk moves to the bench")
	var has_signage: bool = false
	for entry in venue._entries:
		if str(entry.get("region", "")) == "signage":
			has_signage = true
	assert_false(has_signage, "Build no longer mounts the right-hand detail panel")
	assert_true(
		AssetCatalog.venue_art("build").resource_path.contains("no_signage"),
		"Build uses the room artwork with the right-hand display removed"
	)


func _prepare_full_loadout() -> Dictionary:
	# Collect broadly enough to find a legal pair, while equipping until the
	# current (possibly perk-expanded) capacity is full.
	for perk in ContentDatabase.perks:
		var perk_id: String = str(perk.id)
		if not (perk_id in Array(Simulation.run_state.build.get("perk_inventory", []))):
			Simulation.collect_perk(perk_id)
		if Simulation.can_equip_perk(perk_id):
			Simulation.equip_perk(perk_id)
	for incoming_value in Array(Simulation.run_state.build.get("perk_inventory", [])):
		var incoming: String = str(incoming_value)
		if incoming in Array(Simulation.run_state.build.get("perks", [])):
			continue
		var candidates: Array[String] = []
		for outgoing_value in Array(Simulation.run_state.build.get("perks", [])):
			var outgoing: String = str(outgoing_value)
			if (
				Simulation.can_bench_perk(outgoing)
				and Simulation.can_swap_perk(outgoing, incoming)
			):
				candidates.append(outgoing)
		if candidates.size() > 1:
			return {"out": candidates[0], "in": incoming}
	return {}


func _visible_tile(board: VenueBoard, meta: String) -> VenueTile:
	for tile in board._tiles:
		if tile.visible and str(tile.meta) == meta:
			return tile
	return null
