extends TestCase

## The workflow whiteboard is a photographed trapezoid. Native builds warp a
## live panel onto that plane; the Web fallback has to sit in the largest
## axis-aligned rectangle still on the writing surface. These numbers are the
## contract that layout and playtests share, so a bounding-box mount cannot
## silently become "correct".


func run() -> void:
	_test_inscribed_rect_matches_the_photographed_rails()
	_test_workflow_web_safe_rect_is_inside_the_bounding_box()
	_test_inscribed_corners_stay_on_the_plane()
	_test_a_square_plane_is_unchanged()


func _test_inscribed_rect_matches_the_photographed_rails() -> void:
	var plane: PackedVector2Array = AssetCatalog.venue_plane("workflows", "board")
	assert_eq(plane.size(), 4, "The workflow board has four photographed corners")
	if plane.size() != 4:
		return
	assert_almost_eq(plane[0].y, 0.160, 0.001, "Left top of the board plane")
	assert_almost_eq(plane[1].y, 0.096, 0.001, "Right top of the board plane")
	assert_almost_eq(plane[2].y, 0.704, 0.001, "Right bottom of the board plane")
	assert_almost_eq(plane[3].y, 0.660, 0.001, "Left bottom of the board plane")
	var inner: Rect2 = AssetCatalog.inscribed_rect(plane)
	assert_almost_eq(inner.position.y, 0.160, 0.001, "Safe top is the left rail, not the bounding top")
	assert_almost_eq(inner.end.y, 0.660, 0.001, "Safe bottom is the left rail, not the bounding bottom")
	assert_almost_eq(inner.position.x, 0.265, 0.001, "Safe left is the photographed left rail")
	assert_almost_eq(inner.end.x, 0.889, 0.001, "Safe right is the inner of the two right corners")


func _test_workflow_web_safe_rect_is_inside_the_bounding_box() -> void:
	var bounds: Rect2 = AssetCatalog.venue_region("workflows", "board")
	var inner: Rect2 = AssetCatalog.venue_axis_aligned_region("workflows", "board")
	assert_true(bounds.size.x > 0.0, "The workflow board has an authored region")
	assert_true(inner.size.x > 0.0, "And a Web-safe writing surface")
	assert_true(
		inner.position.y > bounds.position.y + 0.02,
		"The safe rect does not use the bounding box top (the right-hand rail)"
	)
	assert_true(
		inner.end.y < bounds.end.y - 0.02,
		"The safe rect does not use the bounding box bottom (the brick below the left rail)"
	)
	assert_true(
		bounds.grow(0.0001).encloses(inner),
		"The Web-safe rect stays inside the authored bounding region"
	)


func _test_inscribed_corners_stay_on_the_plane() -> void:
	var plane: PackedVector2Array = AssetCatalog.venue_plane("workflows", "board")
	var inner: Rect2 = AssetCatalog.inscribed_rect(plane)
	var corners := PackedVector2Array([
		inner.position,
		Vector2(inner.end.x, inner.position.y),
		inner.end,
		Vector2(inner.position.x, inner.end.y),
	])
	for corner in corners:
		assert_true(
			_convex_quad_contains(plane, corner),
			"An inscribed corner stays on the photographed board"
		)


func _test_a_square_plane_is_unchanged() -> void:
	var square := PackedVector2Array([
		Vector2(0.2, 0.1), Vector2(0.8, 0.1), Vector2(0.8, 0.7), Vector2(0.2, 0.7),
	])
	var inner: Rect2 = AssetCatalog.inscribed_rect(square)
	assert_almost_eq(inner.position.x, 0.2, 0.0001, "A square plane keeps its left")
	assert_almost_eq(inner.position.y, 0.1, 0.0001, "A square plane keeps its top")
	assert_almost_eq(inner.size.x, 0.6, 0.0001, "A square plane keeps its width")
	assert_almost_eq(inner.size.y, 0.6, 0.0001, "A square plane keeps its height")


func _convex_quad_contains(quad: PackedVector2Array, point: Vector2) -> bool:
	if quad.size() != 4:
		return false
	for index in range(4):
		var a: Vector2 = quad[index]
		var b: Vector2 = quad[(index + 1) % 4]
		if (b - a).cross(point - a) < -0.00001:
			return false
	return true
