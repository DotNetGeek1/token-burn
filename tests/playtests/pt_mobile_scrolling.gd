extends PlaytestCase

## Real touch drags must climb through interactive menu items to their shared
## ScrollContainer. The original regression highlighted the pressed item but
## left the visible scrollbar at zero because the button stopped the drag.


func play(harness: UiHarness) -> void:
	await harness.boot(23)
	await _menu_rows_scroll(harness)
	await _venue_tiles_scroll(harness)
	await _real_venue_scrolls_through_nested_panels(harness)
	await _build_workflow_door_stays_reachable(harness)


func _menu_rows_scroll(harness: UiHarness) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "MobileMenuScrollProbe"
	scroll.position = Vector2(120, 100)
	scroll.size = Vector2(360, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.z_index = 100
	harness.current_scene().add_child(scroll)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var pressed: int = 0
	var rows: Array[ConsoleMenuRow] = []
	for index in range(18):
		var row := ConsoleMenuRow.new()
		row.index_label = str(index + 1)
		row.headline = "MENU ITEM %02d" % (index + 1)
		row.custom_minimum_size.y = 44.0
		row.pressed.connect(func() -> void: pressed += 1)
		column.add_child(row)
		rows.append(row)
	await harness.settle()
	assert_true(
		scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page,
		"The mobile menu probe has overflow to scroll"
	)
	await harness.driver.swipe(rows[1], Vector2(0, -170))
	assert_true(scroll.scroll_vertical > 0, "A swipe beginning on a menu row scrolls its list")
	assert_eq(pressed, 0, "A menu-row swipe does not activate the highlighted item")
	scroll.queue_free()
	await harness.settle()


func _venue_tiles_scroll(harness: UiHarness) -> void:
	var board := VenueBoard.new()
	board.name = "MobileVenueBoardProbe"
	board.position = Vector2(540, 100)
	board.size = Vector2(360, 240)
	board.z_index = 100
	harness.current_scene().add_child(board)
	var entries: Array = []
	for index in range(18):
		entries.append({
			"meta": index,
			"name": "VENUE ITEM %02d" % (index + 1),
			"figure": "$%d" % ((index + 1) * 100),
			"unit": "installed",
			"spec": "A scrollable venue tile.",
			"status": "OPEN",
		})
	board.set_metrics(1.0, board.size.x)
	board.set_entries(entries)
	await harness.settle()
	assert_true(
		board.get_v_scroll_bar().max_value > board.get_v_scroll_bar().page,
		"The venue board probe has overflow to scroll"
	)
	var first_tile: VenueTile = board._tiles[1]
	await harness.driver.swipe(first_tile, Vector2(0, -170))
	assert_true(board.scroll_vertical > 0, "A swipe beginning on a venue tile scrolls its board")
	assert_eq(board.selected(), null, "A venue-tile swipe does not select the highlighted tile")
	board.queue_free()
	await harness.settle()


func _real_venue_scrolls_through_nested_panels(harness: UiHarness) -> void:
	# Portrait forces the actual venue into its reflowed console column. A tile's
	# drag then has to cross VenueBoard (inline), VenuePanel (inner scroll
	# disabled), and two layout containers before it reaches the outer scroll.
	await harness.set_viewport(Vector2i(480, 854))
	await harness.goto_route("achievements")
	var scene: Node = harness.current_scene()
	var scroll: ScrollContainer = scene.find_child("Console", true, false)
	var tile: Control = harness.driver.first_tile()
	assert_true(scroll != null and scroll.visible, "The portrait venue uses its console scroll")
	assert_true(tile != null, "The real achievements venue has a tile to swipe")
	if scroll == null or tile == null:
		return
	assert_true(
		scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page,
		"The real portrait venue overflows its console"
	)
	await harness.driver.swipe(tile, Vector2(0, -220))
	assert_true(
		scroll.scroll_vertical > 0,
		"A tile swipe crosses nested panels and scrolls the real venue menu"
	)


func _build_workflow_door_stays_reachable(harness: UiHarness) -> void:
	# Landscape phones keep the photographed room. The narrow index reaches the
	# maximum camera zoom, so its local controls compensate for that zoom rather
	# than replacing the room with the console fallback.
	await harness.set_viewport(UiHarness.VIEW_HANDSET)
	await harness.goto_route("build")
	var venue: Node = harness.current_scene()
	assert_true(
		venue._use_room_mode(true, true),
		"A landscape phone keeps the photographed Build room"
	)
	var build_saved_scale: float = venue._scale
	var build_saved_zoom: float = venue._lean_zoom
	venue._scale = 2.6
	venue._lean_zoom = 4.0
	assert_eq(venue._lean_scale(), 1.0, "The narrow Build index scales back at maximum zoom")
	venue._scale = build_saved_scale
	venue._lean_zoom = build_saved_zoom

	# ROOM is a camera step, not venue history: it must reveal Build again without
	# leaving for the desk or returning to another menu.
	venue._room_mode = true
	venue._leaning_on = "index"
	venue._zoom = 4.0
	venue._lean_zoom = 4.0
	venue._sync_lean_chrome()
	assert_true(venue._step_back.visible and "ROOM" in venue._step_back.text,
		"A Build panel close-up exposes its Room control")
	await harness.driver.press(venue._step_back)
	assert_eq(SceneRouter.current, "build", "Room returns to the photographed Build venue")
	assert_eq(venue._leaning_on, "", "Room leaves the Build panel close-up")

	# The route does not depend on reaching the bottom of that narrow panel. Room
	# chrome exposes the touch equivalent of the desktop W shortcut.
	venue._room_mode = true
	venue._layout_workflow_chrome()
	assert_true(
		venue._workflow_chrome.visible and "WORKFLOWS" in venue._workflow_chrome.text,
		"The mobile Build room exposes an always-visible Workflows control"
	)
	await harness.driver.press(venue._workflow_chrome)
	assert_eq(SceneRouter.current, "workflows", "Build room chrome opens Workflows")
	await harness.goto_route("build")
	venue = harness.current_scene()

	# Portrait is too far from the artwork's shape and still uses the compact
	# fallback. Its Workflow route remains usable independently of room mode.
	await harness.set_viewport(Vector2i(480, 854))
	var scroll: ScrollContainer = venue.find_child("Console", true, false)
	var workflow: ConsoleMenuRow = venue._workflow_row
	assert_true(scroll != null and scroll.visible, "Mobile Build uses its console scroll")
	assert_true(workflow != null and workflow.visible, "Mobile Build prints the Workflows door")
	if scroll == null or workflow == null:
		return
	scroll.ensure_control_visible(workflow)
	await harness.settle()
	await harness.driver.press(workflow)
	assert_eq(SceneRouter.current, "workflows", "Mobile Build can open Workflows")
	var workflow_venue: Node = harness.current_scene()
	assert_true(
		workflow_venue._use_room_mode(true, true),
		"A landscape phone keeps the photographed Workflow whiteboard"
	)
	var saved_scale: float = workflow_venue._scale
	var saved_zoom: float = workflow_venue._lean_zoom
	workflow_venue._scale = 2.6
	workflow_venue._lean_zoom = 1.44
	var leaned_scale: float = workflow_venue._lean_scale()
	assert_true(
		leaned_scale < workflow_venue._scale
		and is_equal_approx(leaned_scale, 2.6 / 1.44),
		"The zoomed whiteboard scales its controls and post-its back down"
	)
	workflow_venue._scale = saved_scale
	workflow_venue._lean_zoom = saved_zoom
	# Recreate the connected 2340x1080 phone's zoomed board in design units. The
	# regression screenshot had the OptionButton crossing the photographed rail
	# into the first stage; the compensated scale must make the authored split
	# physically achievable, not merely return a smaller number.
	workflow_venue._console_mode = false
	workflow_venue._room_mode = true
	workflow_venue._leaning_on = "board"
	workflow_venue._scale = 2.6
	workflow_venue._lean_zoom = 1.44
	workflow_venue._body.custom_minimum_size = Vector2.ZERO
	workflow_venue._body.size = Vector2(1360, 600)
	workflow_venue._on_venue_layout()
	assert_true(
		workflow_venue._left.position.x + workflow_venue._left.size.x
		<= workflow_venue._right.position.x + 1.0,
		"The zoomed phone module menu does not overlap the workflow"
	)
