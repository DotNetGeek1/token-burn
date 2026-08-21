extends PlaytestCase

## Keeps the full-board workflow editor registered to the photographed plane
## while a desktop window moves through the supported debug sizes.

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")


func play(harness: UiHarness) -> void:
	await harness.boot(73)
	await harness.goto_route("workflows")
	var venue: Node = harness.current_scene()
	assert_true(venue != null, "Workflow venue opens for the resize audit")
	if venue == null:
		return

	var surface: VenueSurface = null
	for entry_value in venue._entries:
		var entry: Dictionary = entry_value
		if str(entry.get("region", "")) == "board" and entry.get("surface") is VenueSurface:
			surface = entry["surface"]
			break
	assert_true(surface != null, "Desktop workflows use the measured whiteboard surface")
	if surface == null:
		return

	var plane: PackedVector2Array = AssetCatalog.venue_plane("workflows", "board")
	for viewport_size in [
		Vector2i(1280, 720),
		Vector2i(1668, 750),
		Vector2i(1212, 768),
		Vector2i(874, 768),
	]:
		await harness.set_viewport(viewport_size)
		var label := "%dx%d" % [viewport_size.x, viewport_size.y]
		assert_false(venue.console_mode(), "%s desktop workflows stay out of console mode" % label)
		assert_true(venue._stage.visible, "%s keeps the photographed stage visible" % label)
		assert_true(surface.visible, "%s keeps the whiteboard surface visible" % label)
		assert_true(
			venue._board_panel.get_parent() == surface._viewport,
			"%s keeps the board mounted in its projective viewport" % label
		)
		var expected_bounds := Rect2(plane[0] * Vector2(viewport_size), Vector2.ZERO)
		for corner in plane:
			expected_bounds = expected_bounds.expand(corner * Vector2(viewport_size))
		assert_true(
			surface._bounds.position.distance_to(expected_bounds.position) <= 2.0
			and surface._bounds.size.distance_to(expected_bounds.size) <= 2.0,
			"%s recalculates the photographed board bounds" % label
		)
		var divider_x: float = venue._body.size.x * venue.LEFT_SHARE
		assert_true(
			venue._left.position.x + venue._left.size.x <= divider_x + 1.0,
			(
				"%s keeps the module tray left of the metal divider "
				+ "(edge %.1f, divider %.1f, minimum %.1f)"
			) % [
				label,
				venue._left.position.x + venue._left.size.x,
				divider_x,
				venue._left.get_combined_minimum_size().x,
			]
		)
		assert_true(
			venue._right.position.x >= divider_x - 1.0,
			"%s keeps the workflow on the right of the metal divider" % label
		)
		assert_true(
			venue._writing_face.size.x
			<= venue._body.size.x - ConsoleMetrics.px(venue.RIGHT_INSET, venue.console_scale()) + 1.0
			and venue._writing_face.clip_contents,
			"%s clips the workflow inside the right whiteboard bevel" % label
		)
		assert_true(
			venue._left.position.x
			>= ConsoleMetrics.px(venue.LEFT_INSET, venue.console_scale()) - 1.0,
			"%s keeps the module tray inside the left whiteboard bevel" % label
		)
		assert_true(
			venue._writing_face.size.y
			<= venue._body.size.y - ConsoleMetrics.px(venue.BOTTOM_INSET, venue.console_scale()) + 1.0,
			"%s clips both columns above the bottom whiteboard bevel" % label
		)
		var diagram_bar: VScrollBar = venue._diagram_scroll.get_v_scroll_bar()
		if viewport_size == Vector2i(874, 768):
			assert_true(
				venue._diagram.custom_minimum_size.y > venue._diagram_scroll.size.y + 1.0
				and diagram_bar.max_value > diagram_bar.page,
				"%s preserves readable stage heights and scrolls overflow rows" % label
			)
			venue._diagram_scroll.scroll_vertical = int(diagram_bar.max_value)
			await harness.settle()
			assert_true(
				venue._diagram_scroll.scroll_vertical > 0,
				"%s can scroll down to later workflow rows" % label
			)

	await harness.set_viewport(UiHarness.VIEW_DESKTOP)