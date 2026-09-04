class_name DeckSwitch
extends Control

## One of the two small plates beside the BURN button: a caption above a rocker
## toggle with a reading either side, and it takes the press. OVERRIDE
## (safe/risky) is the boost; COOLDOWN is cooling. The rocker is drawn here.

signal pressed

var _caption: Label = null
var _left: Label = null
var _right: Label = null
var _lit: int = -1
var _hot: bool = false
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
	var font: int = clampi(int(size.y * 0.19), 8, 14)
	for label in [_caption, _left, _right]:
		label.add_theme_font_size_override("font_size", font)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The caption fills the band above the toggle; the readings flank the
	# toggle at its height.
	_caption.position = Vector2(size.x * 0.08, size.y * 0.04)
	_caption.size = Vector2(size.x * 0.84, size.y * 0.27)
	var knob: float = size.x * 0.48
	var reach: float = size.x * 0.12
	_left.position = Vector2(size.x * 0.06, size.y * 0.30)
	_left.size = Vector2(knob - reach - size.x * 0.06, size.y * 0.42)
	_right.position = Vector2(knob + reach, size.y * 0.30)
	_right.size = Vector2(size.x * 0.94 - knob - reach, size.y * 0.42)
	queue_redraw()


## The rocker between the readings: a dark slot with the knob thrown to the
## live side (centred when neither side is), lit in the live side's colour.
func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var reach: float = size.x * 0.12
	var slot_h: float = clampf(size.y * 0.30, 10.0, 26.0)
	var slot := Rect2(Vector2(size.x * 0.48 - reach, size.y * 0.51 - slot_h * 0.5), Vector2(reach * 2.0, slot_h))
	var slot_box := StyleBoxFlat.new()
	slot_box.bg_color = Color(0.05, 0.06, 0.06, 0.95)
	slot_box.set_corner_radius_all(int(slot_h * 0.5))
	slot_box.set_border_width_all(1)
	slot_box.border_color = Color(0.36, 0.33, 0.27, 0.8)
	draw_style_box(slot_box, slot)
	var knob_d: float = slot_h - 4.0
	var knob_x: float = slot.position.x + slot.size.x * 0.5 - knob_d * 0.5
	if _lit == 0:
		knob_x = slot.position.x + 2.0
	elif _lit == 1:
		knob_x = slot.end.x - 2.0 - knob_d
	var knob := Rect2(Vector2(knob_x, slot.position.y + 2.0), Vector2(knob_d, knob_d))
	var knob_box := StyleBoxFlat.new()
	var lit_color: Color = CabinetStyle.RED if _hot else CabinetStyle.PHOSPHOR
	knob_box.bg_color = lit_color if _lit >= 0 else Color(0.55, 0.52, 0.45)
	knob_box.set_corner_radius_all(int(knob_d * 0.5))
	draw_style_box(knob_box, knob)


## `lit` is which side is live: -1 neither, 0 left, 1 right.
func set_readings(caption: String, left: String, right: String, lit: int, enabled: bool = true) -> void:
	_lit = lit
	_hot = lit == 1 and caption.to_upper() == "OVERRIDE"
	queue_redraw()
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
