extends PlaytestCase

## Job offers accept directly from their cards. The narrow contract-detail panel
## is gone, while the left Wire/Slate navigation remains available.


func play(harness: UiHarness) -> void:
	await harness.boot(89)
	await harness.goto_route("jobs")
	var venue: Node = harness.current_scene()
	var tile: VenueTile = _first_offer_tile(venue._board)
	assert_true(tile != null, "The Jobs board has an open offer")
	if tile == null:
		return
	var job_id: String = str(tile.meta)
	assert_true(
		tile._action.visible
		and tile._action.text == "ACCEPT"
		and not tile._action.disabled,
		"An open job carries its own enabled ACCEPT button"
	)
	var has_signage: bool = false
	var has_index: bool = false
	for entry in venue._entries:
		var region: String = str(entry.get("region", ""))
		if region == "signage":
			has_signage = true
		elif region == "index":
			has_index = true
	assert_false(has_signage, "Jobs no longer mounts the contract-detail panel")
	assert_true(has_index, "Jobs keeps the Wire/Slate navigation panel")
	assert_true(
		AssetCatalog.venue_art("jobs").resource_path.contains("no_signage"),
		"Jobs uses the room artwork with the contract display removed"
	)

	await harness.driver.press(tile._action)
	var queued_ids: Array[String] = []
	for job in Array(Simulation.run_state.business.get("job_queue", [])):
		queued_ids.append(str(Dictionary(job).get("id", "")))
	assert_true(job_id in queued_ids, "ACCEPT moves the selected offer onto the slate")


func _first_offer_tile(board: VenueBoard) -> VenueTile:
	for tile in board._tiles:
		if tile.visible and tile.meta != null and str(tile.meta) != "":
			return tile
	return null
