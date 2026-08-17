class_name VenueSurface
extends Control

## A live venue panel rendered onto a photographed four-corner surface.
##
## CanvasItem transforms are affine, so they can only turn a rectangle into a
## parallelogram. The venue screens are trapezoids: their top and bottom rails
## have different slopes. This mount renders the real Control into a SubViewport
## and projectively maps that texture onto the measured quadrilateral. Pointer
## coordinates are mapped back through the same homography before being sent to
## the SubViewport, keeping tiles and action rows clickable where they are drawn.

var _viewport: SubViewport = null
var _polygon: Polygon2D = null
var _material: ShaderMaterial = null
var _input: Control = null
var _quad: PackedVector2Array = PackedVector2Array()
var _bounds := Rect2()
var _source_size := Vector2.ONE
var _inverse_row_0 := Vector3(1.0, 0.0, 0.0)
var _inverse_row_1 := Vector3(0.0, 1.0, 0.0)
var _inverse_row_2 := Vector3(0.0, 0.0, 1.0)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_viewport = SubViewport.new()
	_viewport.name = "PanelViewport"
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_polygon = Polygon2D.new()
	_polygon.name = "WarpedPanel"
	_polygon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_material = ShaderMaterial.new()
	_material.shader = load("res://ui/venues/venue_surface.gdshader")
	_polygon.material = _material
	add_child(_polygon)

	_input = Control.new()
	_input.name = "InputSurface"
	_input.mouse_filter = Control.MOUSE_FILTER_STOP
	_input.focus_mode = Control.FOCUS_NONE
	_input.gui_input.connect(_on_surface_input)
	add_child(_input)


func mount_panel(panel: Control) -> void:
	if panel.get_parent() != _viewport:
		panel.reparent(_viewport)


func set_surface(panel: Control, corners: PackedVector2Array, local_size: Vector2) -> void:
	if corners.size() != 4:
		visible = false
		return
	visible = true
	mount_panel(panel)
	var pixels := Vector2i(
		maxi(1, int(ceil(local_size.x))),
		maxi(1, int(ceil(local_size.y)))
	)
	if _viewport.size != pixels:
		_viewport.size = pixels
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	panel.position = Vector2.ZERO
	panel.size = Vector2(pixels)

	_quad = corners
	_source_size = Vector2(pixels)
	_bounds = Rect2(_quad[0], Vector2.ZERO)
	for corner in _quad:
		_bounds = _bounds.expand(corner)
	if _bounds.size.x < 1.0 or _bounds.size.y < 1.0:
		visible = false
		return
	var normalized := PackedVector2Array()
	for corner in _quad:
		normalized.append((corner - _bounds.position) / _bounds.size)
	if not _set_inverse_homography(normalized):
		visible = false
		return

	_polygon.polygon = PackedVector2Array([
		_bounds.position,
		Vector2(_bounds.end.x, _bounds.position.y),
		_bounds.end,
		Vector2(_bounds.position.x, _bounds.end.y),
	])
	_polygon.uv = PackedVector2Array([
		Vector2.ZERO,
		Vector2(float(pixels.x), 0.0),
		Vector2(pixels),
		Vector2(0.0, float(pixels.y)),
	])
	_polygon.texture = _viewport.get_texture()
	_material.set_shader_parameter("inverse_row_0", _inverse_row_0)
	_material.set_shader_parameter("inverse_row_1", _inverse_row_1)
	_material.set_shader_parameter("inverse_row_2", _inverse_row_2)

	_input.position = _bounds.position
	_input.size = _bounds.size


func _on_surface_input(event: InputEvent) -> void:
	var point := Vector2.INF
	if event is InputEventMouse:
		point = _input.position + event.position
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		point = _input.position + event.position
	if not point.is_finite():
		return
	var mapped: Vector2 = _map_to_panel(point)
	if not mapped.is_finite():
		return
	var forwarded: InputEvent = event.duplicate()
	if forwarded is InputEventMouse:
		forwarded.position = mapped
		forwarded.global_position = mapped
	elif forwarded is InputEventScreenTouch or forwarded is InputEventScreenDrag:
		forwarded.position = mapped
	_viewport.push_input(forwarded, true)
	_input.accept_event()


func _map_to_panel(point: Vector2) -> Vector2:
	if _quad.size() != 4 or _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		return Vector2.INF
	var destination := Vector3(
		(point.x - _bounds.position.x) / _bounds.size.x,
		(point.y - _bounds.position.y) / _bounds.size.y,
		1.0
	)
	var divisor: float = _inverse_row_2.dot(destination)
	if absf(divisor) < 0.00001:
		return Vector2.INF
	var panel_uv := Vector2(
		_inverse_row_0.dot(destination) / divisor,
		_inverse_row_1.dot(destination) / divisor
	)
	if (
		panel_uv.x < -0.001 or panel_uv.x > 1.001
		or panel_uv.y < -0.001 or panel_uv.y > 1.001
	):
		return Vector2.INF
	return panel_uv * _source_size


## Builds the projective map from a unit panel into `corners`, then stores its
## inverse. Rows are kept explicitly so the CPU input mapping and GPU image
## mapping use exactly the same arithmetic.
func _set_inverse_homography(corners: PackedVector2Array) -> bool:
	if corners.size() != 4:
		return false
	var p0: Vector2 = corners[0]
	var p1: Vector2 = corners[1]
	var p2: Vector2 = corners[2]
	var p3: Vector2 = corners[3]
	var dx1: float = p1.x - p2.x
	var dx2: float = p3.x - p2.x
	var dx3: float = p0.x - p1.x + p2.x - p3.x
	var dy1: float = p1.y - p2.y
	var dy2: float = p3.y - p2.y
	var dy3: float = p0.y - p1.y + p2.y - p3.y
	var denominator: float = dx1 * dy2 - dx2 * dy1
	if absf(denominator) < 0.00001:
		return false
	var g: float = (dx3 * dy2 - dx2 * dy3) / denominator
	var h: float = (dx1 * dy3 - dx3 * dy1) / denominator
	var a: float = p1.x - p0.x + g * p1.x
	var b: float = p3.x - p0.x + h * p3.x
	var c: float = p0.x
	var d: float = p1.y - p0.y + g * p1.y
	var e: float = p3.y - p0.y + h * p3.y
	var f: float = p0.y
	var determinant: float = (
		a * (e - f * h) - b * (d - f * g) + c * (d * h - e * g)
	)
	if absf(determinant) < 0.00001:
		return false
	_inverse_row_0 = Vector3(e - f * h, c * h - b, b * f - c * e) / determinant
	_inverse_row_1 = Vector3(f * g - d, a - c * g, c * d - a * f) / determinant
	_inverse_row_2 = Vector3(d * h - e * g, b * g - a * h, a * e - b * d) / determinant
	return true
