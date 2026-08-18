extends PlaytestCase

## Market stock acts directly from its cards. The old right-hand detail display
## is gone, so buying and selling remain reachable at desktop and phone sizes.


func play(harness: UiHarness) -> void:
	await harness.boot(83)
	Simulation.run_state.economy["cash"] = 250000.0
	await harness.goto_route("market")
	var venue: Node = harness.current_scene()
	var choice: Dictionary = _buyable_hardware(venue)
	assert_true(not choice.is_empty(), "The Market has buyable hardware for the action test")
	if choice.is_empty():
		return

	var upgrade: UpgradeDefinition = choice["upgrade"]
	venue._on_counter_pressed(str(choice["group"]))
	var buy_tile: VenueTile = _visible_tile(venue._board, "buy:%s" % upgrade.id)
	assert_true(buy_tile != null, "The buyable hardware card is on its shelf")
	if buy_tile == null:
		return
	assert_true(
		buy_tile._action.visible
		and buy_tile._action.text == "BUY"
		and not buy_tile._action.disabled,
		"A purchasable Market card carries its own enabled BUY button"
	)
	var hardware_key: String = UpgradeSystem.installed_key(upgrade)
	var before: int = UpgradeSystem.installed_count(Simulation.run_state, hardware_key)
	await harness.driver.press(buy_tile._action)
	assert_eq(
		UpgradeSystem.installed_count(Simulation.run_state, hardware_key), before + 1,
		"BUY purchases directly from the card"
	)

	var installed: Control = harness.driver.command("INSTALLED")
	assert_true(installed != null, "Purchased hardware remains reachable from Installed")
	if installed != null:
		await harness.driver.press(installed)
	var sell_tile: VenueTile = _visible_tile(venue._board, "sell:%s" % hardware_key)
	assert_true(sell_tile != null, "The purchased hardware appears in Installed")
	if sell_tile != null:
		assert_true(
			sell_tile._action.visible
			and sell_tile._action.text == "SELL"
			and not sell_tile._action.disabled,
			"An installed sellable item carries its own enabled SELL button"
		)
		await harness.driver.press(sell_tile._action)
		assert_eq(
			UpgradeSystem.installed_count(Simulation.run_state, hardware_key), before,
			"SELL removes the purchased item directly from the card"
		)

	var has_signage: bool = false
	for entry in venue._entries:
		if str(entry.get("region", "")) == "signage":
			has_signage = true
	assert_false(has_signage, "Market no longer mounts the right-hand detail panel")
	assert_true(
		AssetCatalog.venue_art("market").resource_path.contains("no_signage"),
		"Market uses the room artwork with the right-hand display removed"
	)


func _buyable_hardware(venue: Node) -> Dictionary:
	for group_value in UpgradePresentation.GROUP_ORDER:
		var group: String = str(group_value)
		for upgrade in Array(venue._shelves().get(group, [])):
			if not (upgrade is UpgradeDefinition):
				continue
			if upgrade.category != "hardware":
				continue
			if UpgradeSystem.installed_key(upgrade) == "":
				continue
			if Simulation.can_buy_upgrade(upgrade.id):
				return {"group": group, "upgrade": upgrade}
	return {}


func _visible_tile(board: VenueBoard, meta: String) -> VenueTile:
	for tile in board._tiles:
		if tile.visible and str(tile.meta) == meta:
			return tile
	return null
