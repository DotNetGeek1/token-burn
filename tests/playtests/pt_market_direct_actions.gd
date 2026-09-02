extends PlaytestCase

## Market stock acts directly from its cards. The old right-hand detail display
## is gone, so buying and selling remain reachable at desktop and phone sizes.
## Modules share the same board: BUY and REROLL are card actions.


func play(harness: UiHarness) -> void:
	await harness.boot(83)
	Simulation.run_state.economy["cash"] = 250000.0
	await harness.goto_route("market")
	var venue: Node = harness.current_scene()

	# Hardware first so the original buy/sell path is not competing with module
	# spend or a MODULES shelf still painted on the board.
	await _hardware_buy_sell(harness, venue)
	Simulation.run_state.economy["cash"] = 250000.0
	await _module_shelf(harness, venue)

	var has_signage: bool = false
	for entry in venue._entries:
		if str(entry.get("region", "")) == "signage":
			has_signage = true
	assert_false(has_signage, "Market no longer mounts the right-hand detail panel")
	assert_true(
		AssetCatalog.venue_art("market").resource_path.contains("no_signage"),
		"Market uses the room artwork with the right-hand display removed"
	)


func _module_shelf(harness: UiHarness, venue: Node) -> void:
	var modules_row: Control = harness.driver.command("MODULES")
	assert_true(modules_row != null, "MODULES counter is reachable")
	if modules_row != null:
		await harness.driver.press(modules_row)
	await harness.settle()
	var stock: Array = Simulation.module_market_stock()
	assert_true(stock.size() > 0, "Round 1 Market has module stock")
	var module_id: String = str(stock[0])
	var buy_tile: VenueTile = _visible_tile(venue._board, "buy_module:%s" % module_id)
	assert_true(buy_tile != null, "A stocked module card is on the MODULES shelf")
	if buy_tile == null:
		return
	assert_true(
		buy_tile._action.visible
		and buy_tile._action.text == "BUY"
		and not buy_tile._action.disabled,
		"A purchasable module card carries its own enabled BUY button"
	)
	assert_true(
		"\n" in buy_tile._spec.text,
		"Module card visibly prints its description below rarity and category"
	)
	await harness.set_viewport(UiHarness.VIEW_HANDSET)
	modules_row = harness.driver.command("MODULES")
	assert_true(modules_row != null, "MODULES counter remains reachable on a handset")
	if modules_row != null:
		await harness.driver.press(modules_row)
	buy_tile = _visible_tile(venue._board, "buy_module:%s" % module_id)
	assert_true(buy_tile != null, "Stocked module remains visible after handset reflow")
	if buy_tile == null:
		return
	venue._board.ensure_control_visible(buy_tile._action)
	await harness.settle()
	var owned_before: int = Array(Simulation.run_state.build.get("modules", [])).size()
	await harness.driver.press(buy_tile._action)
	assert_eq(
		Array(Simulation.run_state.build.get("modules", [])).size(),
		owned_before + 1,
		"BUY purchases a module directly from the card"
	)
	assert_false(module_id in Simulation.module_market_stock(), "Bought modules leave the shelf")

	var restock_tile: VenueTile = _visible_tile(venue._board, venue.RESTOCK_META)
	assert_true(restock_tile != null, "Restock row is visible on the module shelf")
	if restock_tile != null:
		assert_true(
			restock_tile._action.visible and restock_tile._action.text == "REROLL",
			"Restock exposes a REROLL action"
		)
		var capacity: int = MarketService.module_stock_size(Simulation)
		venue._board.ensure_control_visible(restock_tile._action)
		await harness.settle()
		await harness.driver.press(restock_tile._action)
		assert_eq(
			Simulation.module_market_stock().size(),
			capacity,
			"REROLL refills the module shelf"
		)


func _hardware_buy_sell(harness: UiHarness, venue: Node) -> void:
	var choice: Dictionary = _buyable_hardware(venue)
	assert_true(not choice.is_empty(), "The Market has buyable hardware for the action test")
	if choice.is_empty():
		return

	var upgrade: UpgradeDefinition = choice["upgrade"]
	venue._on_counter_pressed(str(choice["group"]))
	await harness.settle()
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
	await harness.settle()
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
