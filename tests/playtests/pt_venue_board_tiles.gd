extends PlaytestCase

## A long perk spec used to stretch one GridContainer column past its neighbours.
## The board now assigns every visible tile the same cell width.


func play(harness: UiHarness) -> void:
	await harness.boot(41)
	var board := VenueBoard.new()
	board.name = "EqualTileBoardProbe"
	board.position = Vector2(80, 80)
	board.size = Vector2(800, 700)
	board.z_index = 100
	harness.current_scene().add_child(board)
	var entries: Array = [
		{
			"meta": "short",
			"name": "Vibe Check",
			"figure": "COMMON",
			"spec": "Short.",
			"price": "speed",
			"status": "FITTED",
		},
		{
			"meta": "long",
			"name": "Rubber Duck",
			"figure": "UNCOMMON",
			"spec": (
				"A colleague who never judges. Slightly higher quality, slightly "
				+ "lower speed. You talk to it more than you should, and the copy "
				+ "keeps going so this column would have been the wide one."
			),
			"price": "speed, quality, reliability",
			"status": "FITTED",
		},
		{
			"meta": "medium",
			"name": "Founder Discount",
			"figure": "COMMON",
			"spec": "Hardware costs a little less this run.",
			"price": "board, economy",
			"status": "FITTED",
		},
		{
			"meta": "rare",
			"name": "Bug Alchemy",
			"figure": "RARE",
			"spec": "Failed stages still count.",
			"price": "quality",
			"status": "NO ROOM — SWAP WITH RUBBER DUCK TO FIT THIS",
		},
		{
			"meta": "paste",
			"name": "Generous Thermal Paste",
			"figure": "COMMON",
			"spec": "Heat moves. Hardware lasts longer between replacements.",
			"price": "board, heat, thermal_safety",
			"status": "FITTED",
		},
		{
			"meta": "bus",
			"name": "Wide Bus",
			"figure": "RARE",
			"spec": "More tokens per pass.",
			"price": "speed",
			"status": "FITTED",
		},
	]
	board.set_metrics(1.0, board.size.x)
	board.set_entries(entries)
	await harness.settle()

	var visible: Array[VenueTile] = []
	for tile in board._tiles:
		if tile.visible:
			visible.append(tile)
	assert_eq(visible.size(), 6, "The probe prints every mixed-length tile")
	assert_eq(board._grid.columns, 4, "An 800-wide board keeps four columns")
	if visible.is_empty():
		board.queue_free()
		return

	var expected: float = (800.0 - 8.0 * 3.0) / 4.0
	var first_width: float = visible[0].size.x
	assert_almost_eq(
		first_width, expected, 1.0,
		"Tiles fill an equal share of the board width"
	)
	for tile in visible:
		assert_almost_eq(
			tile.size.x, first_width, 1.0,
			"Tile %s matches the shared cell width" % str(tile.meta)
		)
	board.queue_free()
	await harness.settle()
