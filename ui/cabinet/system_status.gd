class_name SystemStatus
extends PanelContainer

## The narrow status panel on the right of the cabinet: the run's ledger and the
## live workflow's multipliers, one figure per line, so the numbers that used to
## be written on the whiteboard are always in the corner of the eye.

## A panel wider than this many times its height (the tablet profile's
## telemetry strip) prints its ledger in more than one column: one column per
## multiple of the aspect, up to MAX_COLUMNS, so a strip eight times wider than
## it is tall gets four short columns of legible type rather than two long
## columns of 8 px.
const FOLD_ASPECT := 2.2
const MAX_COLUMNS := 4

var _rows: HBoxContainer = null
var _caption: Label = null
var _entries: Array = []
var _columns: int = 1
var _font: int = 0


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
	_rows = HBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("separation", 12)
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_rows)
	add_child(CabinetStyle.crt_overlay(0.12))
	resized.connect(_on_resized)


func _on_resized() -> void:
	var area: Vector2 = _allotted()
	if area.x <= 0.0 or area.y <= 0.0:
		return
	if _columns_for(_entries) != _columns or _fit_font(_entries, _columns) != _font:
		set_entries(_entries)


## The room the panel has been given: its slot on the telemetry rail, not its
## own size. A PanelContainer cannot be smaller than the rows it holds, so
## reading `size` back would let one generous layout pass lock in a type size
## the next, tighter pass can never undo.
func _allotted() -> Vector2:
	var parent: Node = get_parent()
	if parent is Control and (parent as Control).size.x > 0.0 and (parent as Control).size.y > 0.0:
		return (parent as Control).size
	return size


## How many columns the ledger folds into at the panel's current shape.
func _columns_for(entries: Array) -> int:
	var area: Vector2 = _allotted()
	if area.y <= 0.0 or entries.size() <= 3:
		return 1
	return clampi(int(area.x / (area.y * FOLD_ASPECT)) + 1, 1, MAX_COLUMNS)


## The largest type, 8–14 px, at which the caption, its rule and a column's
## rows stack inside the panel's content height, and the widest `KEY value`
## row fits a column's width, measured on the real face.
func _fit_font(entries: Array, columns: int) -> int:
	var per_column: int = ceili(float(entries.size()) / float(maxi(1, columns)))
	var area: Vector2 = _allotted()
	var box: StyleBox = get_theme_stylebox("panel")
	var margins: Vector2 = box.get_minimum_size() if box != null else Vector2.ZERO
	var inner_h: float = area.y - margins.y
	var column_w: float = (area.x - margins.x - 12.0 * float(columns - 1)) / float(maxi(1, columns))
	var font: Font = _caption.get_theme_font("font") if _caption != null else null
	if font == null or inner_h <= 0.0:
		return clampi(int(area.y / maxf(1.0, per_column + 2) * 0.62), 8, 14)
	# One line per row plus the caption; the rule is a pixel and each of the
	# column's separations one more.
	var fixed: float = 1.0 + 2.0
	for px in range(14, 8, -1):
		if font.get_height(px) * float(per_column + 1) + fixed > inner_h:
			continue
		if columns > 1 and _widest_row(font, px, entries) > column_w:
			continue
		return px
	return 8


## The widest `KEY value` line in `entries` at `px`, with the row's gap.
func _widest_row(font: Font, px: int, entries: Array) -> float:
	var widest: float = 0.0
	for raw in entries:
		var entry: Dictionary = raw
		var line: float = font.get_string_size(str(entry.get("key", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
		if entry.has("value"):
			line += 4.0 + font.get_string_size(str(entry.get("value", "")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
		widest = maxf(widest, line)
	return widest


## `entries` is an array of `{"key": String, "value": String, "color": Color}`.
## An entry with only a `key` prints as a sub-caption.
func set_entries(entries: Array) -> void:
	_entries = entries.duplicate()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_columns = _columns_for(entries)
	var per_column: int = ceili(float(entries.size()) / float(_columns))
	var font: int = _fit_font(entries, _columns)
	_font = font
	_caption.add_theme_font_size_override("font_size", font)
	var columns: Array[VBoxContainer] = []
	for _i in range(_columns):
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 0)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rows.add_child(column)
		columns.append(column)
	var index: int = 0
	for raw in entries:
		var entry: Dictionary = raw
		var target: VBoxContainer = columns[mini(_columns - 1, index / maxi(1, per_column))]
		index += 1
		if not entry.has("value"):
			var sub: Label = CabinetStyle.caption(str(entry.get("key", "")), font, CabinetStyle.AMBER_DIM)
			target.add_child(sub)
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
		target.add_child(row)
