class_name DeckSwitch
extends Control

## One of the two small plates beside the BURN button. The plate paints a toggle
## in the middle; this prints the caption above it and a reading either side, and
## takes the press. OVERRIDE (safe/risky) is the boost; COOLDOWN is cooling.

signal pressed

var _caption: Label = null
var _left: Label = null
var _right: Label = null
var _tap := TapGesture.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_caption = CabinetStyle.caption("", CabinetStyle.FONT_TINY, CabinetStyle.AMBER)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_caption)
	_left = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
	_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_left)
	_right = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
	_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_right)
	gui_input.connect(_on_input)
	resized.connect(_layout)


func _layout() -> void:
	var font: int = clampi(int(size.y * 0.19), 7, 11)
	for label in [_caption, _left, _right]:
		label.add_theme_font_size_override("font_size", font)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The control is cut to the plate's octagon: the caption fills the band
	# above the painted toggle, the readings flank the toggle at its height.
	_caption.position = Vector2(size.x * 0.08, size.y * 0.04)
	_caption.size = Vector2(size.x * 0.84, size.y * 0.27)
	var knob: float = size.x * 0.48
	var reach: float = size.x * 0.12
	_left.position = Vector2(size.x * 0.06, size.y * 0.30)
	_left.size = Vector2(knob - reach - size.x * 0.06, size.y * 0.42)
	_right.position = Vector2(knob + reach, size.y * 0.30)
	_right.size = Vector2(size.x * 0.94 - knob - reach, size.y * 0.42)


## `lit` is which side is live: -1 neither, 0 left, 1 right.
func set_readings(caption: String, left: String, right: String, lit: int, enabled: bool = true) -> void:
	_caption.text = caption.to_upper()
	_left.text = left.to_upper()
	_right.text = right.to_upper()
	_left.add_theme_color_override("font_color", CabinetStyle.PHOSPHOR if lit == 0 else CabinetStyle.PHOSPHOR_DIM)
	_right.add_theme_color_override("font_color", (CabinetStyle.RED if caption.to_upper() == "OVERRIDE" else CabinetStyle.PHOSPHOR) if lit == 1 else CabinetStyle.PHOSPHOR_DIM)
	modulate.a = 1.0 if enabled else 0.55
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW


func _on_input(event: InputEvent) -> void:
	if _tap.feed(event):
		pressed.emit()
		accept_event()
