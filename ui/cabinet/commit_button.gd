class_name BurnButton
extends Button

## The big red button. The plate paints the button itself; this is the lettering
## on its face and the press. What it says depends on which screen the cabinet
## is showing: BURN on the run, ACCEPT on the contracts, BUY in the market.
##
## A real Button underneath — the word is drawn by a Label on its face, but the
## press, the disabled state and the focus all belong to the button, so the
## playtest driver, a keyboard and a controller find it the same way a finger
## does. Nothing is painted over the plate's red glass but the letters: a
## rectangle of shade would sit on top of an octagonal button.

var _label: Label = null
var _sub: Label = null
var _tween: Tween = null


func _ready() -> void:
	text = ""
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var clear := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		add_theme_stylebox_override(state, clear)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font: Font = UiThemeBuilder.header_font()
	if font != null:
		_label.add_theme_font_override("font", font)
	# Printed on the glass: pale lettering with the shadow it casts into the red,
	# rather than a glow floating above it.
	_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.80))
	_label.add_theme_color_override("font_shadow_color", Color(0.18, 0.0, 0.0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.add_theme_constant_override("shadow_outline_size", 1)
	_label.add_theme_constant_override("outline_size", 0)
	add_child(_label)
	_sub = CabinetStyle.mono("", CabinetStyle.FONT_TINY, Color(1.0, 0.82, 0.72, 0.85))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub.add_theme_color_override("font_shadow_color", Color(0.15, 0.0, 0.0, 0.8))
	_sub.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_sub)
	button_down.connect(_press_down)
	button_up.connect(_release)
	resized.connect(_layout)


func _layout() -> void:
	_label.position = Vector2(0.0, size.y * 0.06)
	_label.size = Vector2(size.x, size.y * 0.62)
	_label.add_theme_font_size_override("font_size", clampi(int(size.y * 0.58), 14, 52))
	_label.pivot_offset = _label.size * 0.5
	_sub.position = Vector2(size.x * 0.05, size.y * 0.66)
	_sub.size = Vector2(size.x * 0.9, size.y * 0.26)
	_sub.add_theme_font_size_override("font_size", clampi(int(size.y * 0.14), 7, 11))


## `sub` is the small line under the word: the cost of the press, the reason it
## is not available.
func set_action(label_text: String, enabled: bool, sub: String = "") -> void:
	_label.text = label_text.to_upper()
	_sub.text = sub
	disabled = not enabled
	_label.modulate.a = 1.0 if enabled else 0.4
	_sub.modulate.a = 1.0 if enabled else 0.5
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW


func is_enabled() -> bool:
	return not disabled


## The letters sink into the glass while the button is held.
func _press_down() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_label.scale = Vector2(0.96, 0.96)
	_label.modulate = Color(0.85, 0.75, 0.68, _label.modulate.a)


func _release() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_label, "scale", Vector2.ONE, 0.18)
	_tween.tween_property(_label, "modulate", Color(1, 1, 1, 1.0 if not disabled else 0.4), 0.18)


## Lights the lettering for a beat, for anything the cabinet wants to shout about.
func flash() -> void:
	_label.modulate = Color(1.6, 1.4, 1.2, 1.0)
	var tween: Tween = create_tween()
	tween.tween_property(_label, "modulate", Color(1, 1, 1, 1.0 if not disabled else 0.4), 0.35)
