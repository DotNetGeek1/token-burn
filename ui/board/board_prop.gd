class_name BoardProp
extends Button

## A readout painted onto something standing in the room.
##
## The desk artwork carries the housing — the thermometer's case, the meter box
## on the wall, the whiteboard, the phone — and this fills the window cut into
## it. That is the difference between a game with a HUD bolted on and a game
## whose HUD is furniture: nothing here floats, and every number is somewhere a
## person at that desk could actually read it.
##
## Props are placed by the shell from `board_scene.props` in the asset catalog,
## so where each one sits is a property of the picture rather than a constant in
## this script.

## Catalog key this prop was built for. Only used for debugging and tooltips.
var prop_key: String = ""

var _caption: Label = null
var _value: Label = null
var _checklist: VBoxContainer = null
var _glow: float = 0.0
var _ringing: bool = false


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	# Only the phone is worth pressing; the rest are readouts, and a readout that
	# eats a click on the desk behind it is a bug.
	mouse_filter = Control.MOUSE_FILTER_STOP if _is_interactive() else Control.MOUSE_FILTER_IGNORE
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, _face_style())
	var box := VBoxContainer.new()
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8.0
	box.offset_top = 5.0
	box.offset_right = -8.0
	box.offset_bottom = -5.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centred, because the window the artwork cut is the window the reading has
	# to land in; top-aligning it puts the number on the bezel.
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	add_child(box)
	_caption = _make_label(11, UiThemeBuilder.color("grey").lightened(0.35))
	_caption.add_theme_font_override("font", UiThemeBuilder.mono_font())
	box.add_child(_caption)
	_value = _make_label(16, UiThemeBuilder.color("white"))
	_value.add_theme_font_override("font", UiThemeBuilder.mono_font())
	box.add_child(_value)
	_checklist = VBoxContainer.new()
	_checklist.name = "Checklist"
	_checklist.visible = false
	_checklist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_checklist.add_theme_constant_override("separation", 0)
	box.add_child(_checklist)
	resized.connect(_fit_to_housing)
	_fit_to_housing()


## The housing is whatever the artwork drew, and the artwork drew a meter box the
## size of a meter box. Type is sized to the window rather than the window being
## sized to the type, and on the smallest faces the caption goes entirely — the
## thing it is bolted to already says what it measures.
func _fit_to_housing() -> void:
	if _caption == null:
		return
	var height: float = size.y
	var box: Control = get_node_or_null("Box")
	if box != null:
		var inset: float = 6.0 if height < 60.0 else 8.0
		box.offset_left = inset
		box.offset_right = -inset
		box.offset_top = 3.0
		box.offset_bottom = -3.0
	_caption.visible = height >= 46.0
	_caption.add_theme_font_size_override("font_size", clampi(int(height * 0.16), 9, 13))
	_value.add_theme_font_size_override(
		"font_size", clampi(int(height * (0.3 if _caption.visible else 0.5)), 10, 20)
	)
	var line_size: int = clampi(int(height / 8.5), 8, 13)
	for child in _checklist.get_children():
		(child as Label).add_theme_font_size_override("font_size", line_size)


func _is_interactive() -> bool:
	return prop_key == "phone"


## Recessed window: near-black glass with a lip around it, so the reading looks
## sunk into the housing the artwork drew rather than printed on top of it.
func _face_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var bay: Color = UiThemeBuilder.color("bay")
	style.bg_color = Color(bay.r, bay.g, bay.b, 0.78)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = UiThemeBuilder.color("stroke_dim")
	style.set_corner_radius_all(4)
	return style


func _make_label(font_size: int, font_color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	return label


## A single number on a device face: what it measures, and what it reads.
func set_readout(caption: String, value: String, value_color: Color) -> void:
	if _caption == null:
		return
	_checklist.visible = false
	_value.visible = true
	_caption.text = caption
	_value.text = value
	_value.add_theme_color_override("font_color", value_color)


## The plan on the wall. Each line is `[text, done]`; done lines are ticked and
## dimmed, so the board is a to-do list the run crosses off rather than a static
## piece of set dressing.
func set_checklist(caption: String, lines: Array) -> void:
	if _caption == null:
		return
	_caption.text = caption
	_value.visible = false
	_checklist.visible = true
	var grew: bool = _checklist.get_child_count() < lines.size()
	while _checklist.get_child_count() < lines.size():
		var line_label: Label = _make_label(11, UiThemeBuilder.color("white"))
		line_label.add_theme_font_override("font", UiThemeBuilder.mono_font())
		_checklist.add_child(line_label)
	if grew:
		_fit_to_housing()
	for index in range(_checklist.get_child_count()):
		var label: Label = _checklist.get_child(index)
		if index >= lines.size():
			label.visible = false
			continue
		var entry: Array = Array(lines[index])
		var done: bool = entry.size() > 1 and bool(entry[1])
		label.visible = true
		label.text = "%s %s" % ["[x]" if done else "[ ]", str(entry[0])]
		label.add_theme_color_override(
			"font_color",
			UiThemeBuilder.semantic("success") if done else UiThemeBuilder.color("grey").lightened(0.4)
		)


## The phone lights up when the investor has something to say. Drawn rather than
## tweened so it keeps time with the rest of the room even while a burn is
## animating and tweens are being killed and restarted.
func set_ringing(ringing: bool) -> void:
	if _ringing == ringing:
		return
	_ringing = ringing
	set_process(ringing)
	if not ringing:
		_glow = 0.0
		queue_redraw()


func _process(delta: float) -> void:
	_glow = fmod(_glow + delta * 2.4, TAU)
	queue_redraw()


func _draw() -> void:
	if not _ringing:
		return
	var pulse: float = 0.35 + 0.4 * (0.5 + 0.5 * sin(_glow))
	var accent: Color = UiThemeBuilder.semantic("danger")
	draw_rect(
		Rect2(Vector2.ZERO, size),
		Color(accent.r, accent.g, accent.b, pulse * 0.28),
		true
	)
	draw_rect(
		Rect2(Vector2.ZERO, size),
		Color(accent.r, accent.g, accent.b, pulse),
		false,
		2.0
	)
