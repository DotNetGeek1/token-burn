class_name BurnFeed
extends PanelContainer

## The small live screen top right: a scrolling log of the batch as it burns,
## the multiplier it is at, and whether anything is running at all. Glows like
## a furnace while a batch is on.

const MAX_LINES := 7

var _live: Label = null
var _lines: VBoxContainer = null
var _mult: Label = null
var _status: Label = null
var _glow: ColorRect = null
var _glow_tween: Tween = null
var _log: Array[Dictionary] = []


func _ready() -> void:
	add_theme_stylebox_override("panel", CabinetStyle.glass_box(0.9, Color(0.03, 0.03, 0.03, 0.97)))
	clip_contents = true

	_glow = ColorRect.new()
	_glow.color = Color(0.95, 0.40, 0.08, 0.0)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 1)
	add_child(column)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	var caption: Label = CabinetStyle.caption("BURN FEED")
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(caption)
	_live = CabinetStyle.mono("○ IDLE", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
	head.add_child(_live)

	_lines = VBoxContainer.new()
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_theme_constant_override("separation", 0)
	_lines.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lines.clip_contents = true
	column.add_child(_lines)

	_mult = CabinetStyle.mono("", CabinetStyle.FONT_HEAD, CabinetStyle.AMBER)
	_mult.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_mult)
	_status = CabinetStyle.mono("NO RUN ACTIVE", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)
	add_child(CabinetStyle.crt_overlay(0.22))
	resized.connect(_fit)
	_fit()


func _fit() -> void:
	_mult.add_theme_font_size_override("font_size", clampi(int(size.y * 0.16), 10, 22))
	_render()


func set_live(live: bool, status: String, multiplier: float = 0.0) -> void:
	_live.text = "● LIVE" if live else "○ IDLE"
	_live.add_theme_color_override("font_color", CabinetStyle.RED if live else CabinetStyle.PHOSPHOR_DIM)
	_status.text = status.to_upper()
	_status.add_theme_color_override("font_color", CabinetStyle.AMBER if live else CabinetStyle.PHOSPHOR_DIM)
	_mult.text = "×%.1f" % multiplier if multiplier > 0.0 else ""
	_set_glow(live)


func push(text: String, color: Color = CabinetStyle.PHOSPHOR) -> void:
	_log.append({"text": text, "color": color})
	while _log.size() > MAX_LINES:
		_log.pop_front()
	_render()


func clear() -> void:
	_log.clear()
	_render()


func _render() -> void:
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	var font: int = clampi(int(size.y * 0.075), 7, 11)
	var fit: int = maxi(1, int(_lines.size.y / (font + 3.0))) if _lines.size.y > 0.0 else MAX_LINES
	var start: int = maxi(0, _log.size() - fit)
	for index in range(start, _log.size()):
		var entry: Dictionary = _log[index]
		var age: float = float(_log.size() - 1 - index)
		var color: Color = Color(entry["color"])
		color.a = clampf(1.0 - age * 0.14, 0.35, 1.0)
		_lines.add_child(CabinetStyle.mono("> " + str(entry["text"]), font, color))


func _set_glow(on: bool) -> void:
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	if not on:
		_glow.color.a = 0.0
		return
	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_property(_glow, "color:a", 0.22, 0.55)
	_glow_tween.tween_property(_glow, "color:a", 0.08, 0.7)
