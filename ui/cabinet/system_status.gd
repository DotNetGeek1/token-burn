class_name SystemStatus
extends PanelContainer

## The narrow status panel on the right of the cabinet: the run's ledger and the
## live workflow's multipliers, one figure per line, so the numbers that used to
## be written on the whiteboard are always in the corner of the eye.

var _rows: VBoxContainer = null
var _caption: Label = null


func _ready() -> void:
	add_theme_stylebox_override("panel", CabinetStyle.glass_box())
	clip_contents = true
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 1)
	add_child(column)
	_caption = CabinetStyle.caption("SYSTEM STATUS")
	column.add_child(_caption)
	column.add_child(CabinetStyle.rule(CabinetStyle.AMBER, 0.35))
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("separation", 0)
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_rows)
	add_child(CabinetStyle.crt_overlay(0.12))


## `entries` is an array of `{"key": String, "value": String, "color": Color}`.
## An entry with only a `key` prints as a sub-caption.
func set_entries(entries: Array) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var font: int = clampi(int(size.y / maxf(1.0, entries.size() + 2) * 0.62), 7, 11)
	_caption.add_theme_font_size_override("font_size", font)
	for raw in entries:
		var entry: Dictionary = raw
		if not entry.has("value"):
			var sub: Label = CabinetStyle.caption(str(entry.get("key", "")), font, CabinetStyle.AMBER_DIM)
			_rows.add_child(sub)
			continue
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 4)
		var key: Label = CabinetStyle.mono(str(entry.get("key", "")).to_upper(), font, CabinetStyle.PHOSPHOR_DIM)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key)
		var value: Label = CabinetStyle.mono(str(entry.get("value", "")), font, Color(entry.get("color", CabinetStyle.PHOSPHOR)))
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_SHRINK_END
		# The figure keeps its width; the key is what gives way on a narrow panel.
		value.clip_text = false
		value.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		row.add_child(value)
		_rows.add_child(row)
