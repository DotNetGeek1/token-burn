class_name HeatMeter
extends PanelContainer

## The heat window: a bar of lit segments running green through amber into red,
## with the throttle line marked, and the rig's heat state named under it.

const SEGMENTS := 24

var _percent: Label = null
var _state: Label = null
var _bar: Control = null
var _ratio: float = 0.0
var _throttle: float = 0.8
var _projected: float = -1.0


func _ready() -> void:
	add_theme_stylebox_override("panel", CabinetStyle.glass_box())
	clip_contents = true
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	var caption: Label = CabinetStyle.caption("HEAT")
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(caption)
	_percent = CabinetStyle.mono("0%", CabinetStyle.FONT_SMALL, CabinetStyle.PHOSPHOR)
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_percent)
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bar.custom_minimum_size = Vector2(0, 10)
	_bar.draw.connect(_draw_bar)
	column.add_child(_bar)
	_state = CabinetStyle.mono("NOMINAL", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
	_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_state)
	add_child(CabinetStyle.crt_overlay(0.12))


## `projected` is where the next burn would leave the rig, drawn as a dim
## extension past the live reading so the player sees what BURN costs.
func set_heat(ratio: float, throttle_ratio: float, state_label: String, projected: float = -1.0) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	_throttle = clampf(throttle_ratio, 0.0, 1.0)
	_projected = clampf(projected, 0.0, 1.0) if projected >= 0.0 else -1.0
	_percent.text = "%d%%" % int(round(_ratio * 100.0))
	var color: Color = _color_for(_ratio)
	_percent.add_theme_color_override("font_color", color)
	var text: String = state_label.to_upper() if state_label != "" else ("DANGER ZONE" if _ratio >= _throttle else "NOMINAL")
	_state.text = text
	_state.add_theme_color_override("font_color", color if _ratio >= _throttle else CabinetStyle.PHOSPHOR_DIM)
	_bar.queue_redraw()


func _color_for(ratio: float) -> Color:
	if ratio >= 0.9:
		return CabinetStyle.RED
	if ratio >= _throttle:
		return CabinetStyle.AMBER
	return CabinetStyle.PHOSPHOR


func _draw_bar() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, _bar.size)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var gap: float = 2.0
	var width: float = (rect.size.x - gap * (SEGMENTS - 1)) / SEGMENTS
	var lit: int = int(round(_ratio * SEGMENTS))
	var projected: int = int(round(_projected * SEGMENTS)) if _projected >= 0.0 else -1
	for index in range(SEGMENTS):
		var x: float = index * (width + gap)
		var segment := Rect2(x, 0.0, width, rect.size.y)
		var position: float = float(index + 1) / SEGMENTS
		var color: Color = _color_for(position)
		if index < lit:
			_bar.draw_rect(segment, color)
		elif index < projected:
			_bar.draw_rect(segment, Color(color.r, color.g, color.b, 0.35))
		else:
			_bar.draw_rect(segment, Color(color.r, color.g, color.b, 0.10))
	var throttle_x: float = _throttle * rect.size.x
	_bar.draw_line(Vector2(throttle_x, -1.0), Vector2(throttle_x, rect.size.y + 1.0), Color(1, 1, 1, 0.5), 1.0)
