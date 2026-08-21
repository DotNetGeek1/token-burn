extends TestCase

## Photographed venue panels are quadrilaterals. Native builds can project a
## SubViewport exactly onto those four corners; Web cannot safely keep that GPU
## path alive across routed screens, so it uses a best-fit affine parallelogram.
## The old inscribed rectangle remains only as a degenerate-plane fallback.


func run() -> void:
	_test_workflow_keeps_compact_desktop_painted()
	_test_inscribed_rect_matches_the_photographed_rails()
	_test_workflow_web_safe_rect_is_inside_the_bounding_box()
	_test_inscribed_corners_stay_on_the_plane()
	_test_a_square_plane_is_unchanged()
	_test_projective_surface_rejects_a_degenerate_plane()
	_test_affine_fallback_follows_workflow_perspective()
	_test_build_index_uses_its_rectangular_flat_policy()


func _test_workflow_keeps_compact_desktop_painted() -> void:
	var generic_venue := VenueScene.new()
	var workflow_venue: Node = load("res://ui/venues/venue_workflows.gd").new()
	assert_false(
		generic_venue._painted_desktop_at_any_aspect(),
		"Other venues retain the shared desktop aspect fallback"
	)
	assert_true(
		workflow_venue._painted_desktop_at_any_aspect(),
		"The continuous workflow whiteboard stays painted in a compact desktop window"
	)
	workflow_venue.free()
	generic_venue.free()


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
	assert_true(inner.size.x > 0.0, "And a conservative fallback writing surface")
	assert_true(
		inner.position.y > bounds.position.y + 0.02,
		"The fallback rect does not use the bounding box top (the right-hand rail)"
	)
	assert_true(
		inner.end.y < bounds.end.y - 0.02,
		"The fallback rect does not use the bounding box bottom (the brick below the left rail)"
	)
	assert_true(
		bounds.grow(0.0001).encloses(inner),
		"The conservative fallback stays inside the authored bounding region"
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


func _test_projective_surface_rejects_a_degenerate_plane() -> void:
	var surface := VenueSurface.new()
	var panel := VenuePanel.new()
	surface.add_child(panel)
	var accepted: bool = surface.set_surface(
		panel,
		PackedVector2Array([
			Vector2(100.0, 100.0),
			Vector2(200.0, 100.0),
			Vector2(300.0, 100.0),
			Vector2(400.0, 100.0),
		]),
		Vector2(200.0, 100.0)
	)
	assert_false(accepted, "A degenerate projective plane reports placement failure")
	surface.free()


func _test_affine_fallback_follows_workflow_perspective() -> void:
	var plane: PackedVector2Array = AssetCatalog.venue_plane("workflows", "board")
	var placed: Dictionary = _place_affine(plane)
	assert_true(bool(placed.get("ok", false)), "Workflow plane accepts the Web affine mount")
	if not bool(placed.get("ok", false)):
		return
	var transform: Transform2D = placed["transform"]
	assert_true(
		absf(transform.x.y) > 0.001 or absf(transform.y.x) > 0.001,
		"Workflow Web fallback follows the photographed slant instead of staying axis-aligned"
	)
	_assert_affine_center_matches_plane(plane, placed, "Workflow")


func _test_build_index_uses_its_rectangular_flat_policy() -> void:
	var venue: Node = load("res://ui/venues/venue_build.gd").new()
	var surface := Node2D.new()
	var panel := VenuePanel.new()
	surface.add_child(panel)
	var placed: bool = venue._place_panel_affine(
		{"region": "index", "surface": surface},
		panel,
		AssetCatalog.venue_plane("build", "index"),
		Vector2(1000.0, 1000.0)
	)
	var expected: Rect2 = venue._region_rect("index", Vector2(1000.0, 1000.0))
	var transform: Transform2D = surface.transform
	var mounted_origin: Vector2 = transform * panel.position
	var mounted_size := Vector2(
		transform.x.length() * panel.size.x,
		transform.y.length() * panel.size.y
	)
	assert_true(placed, "Build index accepts its rectangular flat mount")
	assert_almost_eq(transform.x.y, 0.0, 0.0001, "Build index has no horizontal skew")
	assert_almost_eq(transform.y.x, 0.0, 0.0001, "Build index has no vertical skew")
	assert_almost_eq(mounted_origin.x, expected.position.x, 0.1, "Build index keeps its authored X")
	assert_almost_eq(mounted_origin.y, expected.position.y, 0.1, "Build index keeps its authored Y")
	assert_almost_eq(mounted_size.x, expected.size.x, 0.1, "Build index keeps its authored width")
	assert_almost_eq(mounted_size.y, expected.size.y, 0.1, "Build index keeps its authored height")
	panel.free()
	surface.free()
	venue.free()


func _place_affine(plane: PackedVector2Array) -> Dictionary:
	var venue := VenueScene.new()
	var surface := Node2D.new()
	var panel := VenuePanel.new()
	surface.add_child(panel)
	var ok: bool = venue._place_panel_affine(
		{"surface": surface}, panel, plane, Vector2(1000.0, 1000.0)
	)
	var result := {
		"ok": ok,
		"transform": surface.transform,
		"size": panel.size,
	}
	panel.free()
	surface.free()
	venue.free()
	return result


func _assert_affine_center_matches_plane(
	plane: PackedVector2Array,
	placed: Dictionary,
	label: String
) -> void:
	var transform: Transform2D = placed["transform"]
	var size: Vector2 = placed["size"]
	var mapped_center: Vector2 = transform * (size * 0.5)
	var expected := Vector2.ZERO
	for corner in plane:
		expected += corner * 1000.0
	expected *= 0.25
	assert_almost_eq(mapped_center.x, expected.x, 0.1, "%s affine mount keeps the plane centre X" % label)
	assert_almost_eq(mapped_center.y, expected.y, 0.1, "%s affine mount keeps the plane centre Y" % label)


func _convex_quad_contains(quad: PackedVector2Array, point: Vector2) -> bool:
	if quad.size() != 4:
		return false
	for index in range(4):
		var a: Vector2 = quad[index]
		var b: Vector2 = quad[(index + 1) % 4]
		if (b - a).cross(point - a) < -0.00001:
			return false
	return true
