extends PlaytestCase

## Every venue uses the same panel-mount contract. This catches a panel that
## disappears, produces invalid geometry, or moves again after layout settles.

const ROUTES: Array[String] = [
	"market",
	"jobs",
	"build",
	"workflows",
	"menu",
	"legacy",
	"achievements",
	"terms",
]


func play(harness: UiHarness) -> void:
	await harness.boot(79)
	for viewport_size in [UiHarness.VIEW_DESKTOP, UiHarness.VIEW_HANDSET]:
		await harness.set_viewport(viewport_size)
		for route in ROUTES:
			await harness.go_desk()
			await harness.goto_route(route)
			var venue: Node = harness.current_scene()
			var label := "%s at %dx%d" % [route, viewport_size.x, viewport_size.y]
			assert_true(venue != null, "%s opens" % label)
			if venue == null:
				continue
			assert_false(venue.console_mode(), "%s keeps the photographed landscape" % label)
			_assert_mounts(venue, label)
			var before: Array[Dictionary] = _geometry(venue)
			venue._layout()
			await harness.settle()
			var after: Array[Dictionary] = _geometry(venue)
			_assert_stable(before, after, label)


func _assert_mounts(venue: Node, label: String) -> void:
	for entry_value in venue._entries:
		var entry: Dictionary = entry_value
		if bool(entry.get("painted_hide", false)):
			continue
		var region: String = str(entry.get("region", ""))
		var panel: VenuePanel = entry.get("panel")
		var surface: CanvasItem = entry.get("surface")
		var mount_label := "%s %s" % [label, region]
		assert_true(panel != null and panel.visible, "%s panel is visible" % mount_label)
		assert_true(surface != null and surface.visible, "%s mount is visible" % mount_label)
		if panel == null or surface == null:
			continue
		assert_true(
			panel.size.is_finite() and panel.size.x > 1.0 and panel.size.y > 1.0,
			"%s panel has finite positive size" % mount_label
		)
		var bounds: Rect2 = _mount_bounds(panel, surface)
		assert_true(
			bounds.position.is_finite()
			and bounds.size.is_finite()
			and bounds.size.x > 1.0
			and bounds.size.y > 1.0,
			"%s screen-space bounds are finite and positive" % mount_label
		)


func _geometry(venue: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry_value in venue._entries:
		var entry: Dictionary = entry_value
		if bool(entry.get("painted_hide", false)):
			continue
		var panel: VenuePanel = entry.get("panel")
		var surface: CanvasItem = entry.get("surface")
		result.append({
			"region": str(entry.get("region", "")),
			"bounds": _mount_bounds(panel, surface),
		})
	return result


func _mount_bounds(panel: VenuePanel, surface: CanvasItem) -> Rect2:
	if surface is VenueSurface:
		return surface._bounds
	if surface is Node2D:
		var transform: Transform2D = surface.transform
		var corners := PackedVector2Array([
			panel.position,
			panel.position + Vector2(panel.size.x, 0.0),
			panel.position + panel.size,
			panel.position + Vector2(0.0, panel.size.y),
		])
		var bounds := Rect2(transform * corners[0], Vector2.ZERO)
		for corner in corners:
			bounds = bounds.expand(transform * corner)
		return bounds
	return Rect2(panel.position, panel.size)


func _assert_stable(before: Array[Dictionary], after: Array[Dictionary], label: String) -> void:
	assert_eq(after.size(), before.size(), "%s keeps the same mount count" % label)
	if after.size() != before.size():
		return
	for index in range(before.size()):
		var first: Dictionary = before[index]
		var second: Dictionary = after[index]
		var mount_label := "%s %s" % [label, first.get("region", "")]
		var first_bounds: Rect2 = first["bounds"]
		var second_bounds: Rect2 = second["bounds"]
		assert_true(
			first_bounds.position.distance_to(second_bounds.position) <= 0.5
			and first_bounds.size.distance_to(second_bounds.size) <= 0.5,
			"%s screen-space bounds are stable after repeat layout (%s -> %s)"
			% [mount_label, first_bounds, second_bounds]
		)
