class_name ConsoleTable
extends VBoxContainer

## A column of terminal output that happens to be a list: a dim header row of
## column names, then one touchable line per record.
##
## Rows are printed text until the pointer reaches them, at which point they
## invert to a solid phosphor bar — the same affordance `ConsoleMenuRow` uses on
## the title screen, applied to tabular data. The selected row stays lit so the
## detail pane underneath always has a visible owner.

signal row_selected(meta: Variant)

const ROW_HEIGHT := 26
const PAD_H := 8


## One record. Cells are laid out on the same weights as the header, so the
## columns line up down the table without a grid container in the way.
class Row:
	extends Button

	var meta: Variant = null

	var _labels: Array[Label] = []
	var _dots: Array = []
	var _accents: Array[Color] = []
	var _lit: Color = ConsoleStyle.PHOSPHOR
	var _selected: bool = false

	func _init(columns: Array, cells: Array, lit: Color) -> void:
		_lit = lit
		text = ""
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(0, ConsoleTable.ROW_HEIGHT)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var margin := MarginContainer.new()
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", ConsoleTable.PAD_H)
		margin.add_theme_constant_override("margin_right", ConsoleTable.PAD_H)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(margin)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(row)

		for i in range(columns.size()):
			var column: Dictionary = columns[i]
			var cell: Variant = cells[i] if i < cells.size() else ""
			row.add_child(_cell(column, cell))
		_apply_palette()

	func _cell(column: Dictionary, cell: Variant) -> Control:
		var alignment: int = int(column.get("align", HORIZONTAL_ALIGNMENT_LEFT))
		var weight: float = float(column.get("weight", 1.0))
		if cell is Dictionary and cell.has("dots"):
			var strip := ConsoleTable.DotStrip.new()
			strip.filled = int(cell["dots"])
			strip.total = int(cell.get("max", 5))
			strip.color = Color(cell.get("color", ConsoleStyle.PHOSPHOR))
			strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			strip.size_flags_stretch_ratio = weight
			_dots.append(strip)
			return strip
		var text_value: String = ""
		var color: Color = ConsoleStyle.PHOSPHOR
		if cell is Dictionary:
			text_value = str(cell.get("text", ""))
			color = Color(cell.get("color", ConsoleStyle.PHOSPHOR))
		else:
			text_value = str(cell)
		var label: Label = ConsoleStyle.label(text_value, ConsoleStyle.FONT_SMALL, color)
		label.clip_text = true
		label.horizontal_alignment = alignment
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = weight
		_labels.append(label)
		_accents.append(color)
		return label

	func set_selected(selected: bool) -> void:
		_selected = selected
		_apply_palette()
		_sync_ink()

	func _apply_palette() -> void:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var box_state: String = state
			if _selected and state == "normal":
				box_state = "hover"
			add_theme_stylebox_override(state, ConsoleStyle.row_box(box_state, _lit))

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT:
				_sync_ink()
			NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT:
				_sync_ink()

	## Text on a lit bar has to flip to ink or it disappears into its own
	## highlight.
	func _sync_ink() -> void:
		var inverted: bool = _selected or is_hovered() or has_focus()
		for i in range(_labels.size()):
			_labels[i].add_theme_color_override(
				"font_color", ConsoleStyle.INK if inverted else _accents[i]
			)
		for strip in _dots:
			strip.inverted = inverted
			strip.queue_redraw()


## The red/blue pips that stand in for a rating bar on a terminal.
class DotStrip:
	extends Control

	var filled: int = 0
	var total: int = 5
	var color: Color = ConsoleStyle.PHOSPHOR
	var inverted: bool = false

	const DOT := 6.0
	const GAP := 4.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(float(total) * (DOT + GAP), DOT)

	func _draw() -> void:
		var lit: Color = ConsoleStyle.INK if inverted else color
		var unlit: Color = Color(lit.r, lit.g, lit.b, 0.25)
		var top: float = (size.y - DOT) * 0.5
		for i in range(total):
			var rect := Rect2(float(i) * (DOT + GAP), top, DOT, DOT)
			draw_rect(rect, lit if i < filled else unlit, i < filled)


var _columns: Array = []
var _header: HBoxContainer = null
var _rows_box: VBoxContainer = null
var _rows: Array[Row] = []
var _selected: Row = null


func _ready() -> void:
	add_theme_constant_override("separation", 2)
	if _rows_box == null:
		_build()


func _build() -> void:
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 10)
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PAD_H)
	margin.add_theme_constant_override("margin_right", PAD_H)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_header)
	add_child(margin)
	add_child(ConsoleStyle.rule(0.22))
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 0)
	add_child(_rows_box)


## `columns` is a list of `{label, weight, align}`. Weights are stretch ratios,
## so a table only has to say which column is the wide one.
func set_columns(columns: Array) -> void:
	if _rows_box == null:
		_build()
	_columns = columns
	for child in _header.get_children():
		child.queue_free()
	for column in columns:
		var label: Label = ConsoleStyle.label(
			str(column.get("label", "")).to_upper(),
			ConsoleStyle.FONT_TINY,
			ConsoleStyle.PHOSPHOR_DIM
		)
		label.clip_text = true
		label.horizontal_alignment = int(column.get("align", HORIZONTAL_ALIGNMENT_LEFT))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = float(column.get("weight", 1.0))
		_header.add_child(label)


## Cells are strings, `{text, color}` or `{dots, max, color}`, one per column.
func add_row(cells: Array, meta: Variant = null, lit: Color = ConsoleStyle.PHOSPHOR) -> Row:
	if _rows_box == null:
		_build()
	var row := Row.new(_columns, cells, lit)
	row.meta = meta
	row.pressed.connect(_on_row_pressed.bind(row))
	row.mouse_entered.connect(func() -> void: UiSound.play("key"))
	_rows_box.add_child(row)
	_rows.append(row)
	return row


## A line of output inside the table that is not a record — a section heading, or
## "no contracts on the wire".
func add_note(text: String, color: Color = ConsoleStyle.PHOSPHOR_DIM) -> void:
	if _rows_box == null:
		_build()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PAD_H)
	margin.add_theme_constant_override("margin_top", 4)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(ConsoleStyle.label(text, ConsoleStyle.FONT_TINY, color))
	_rows_box.add_child(margin)


func clear() -> void:
	if _rows_box == null:
		_build()
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_rows.clear()
	_selected = null


func rows() -> Array[Row]:
	return _rows


## Lights the row holding `meta` and reports it, so a screen can restore the
## selection it had before a refresh redrew the table.
func select_meta(meta: Variant, emit: bool = true) -> bool:
	for row in _rows:
		if row.meta == meta:
			_light(row)
			if emit:
				row_selected.emit(row.meta)
			return true
	return false


func _on_row_pressed(row: Row) -> void:
	UiSound.play("tap")
	_light(row)
	row_selected.emit(row.meta)


func _light(row: Row) -> void:
	if _selected != null and is_instance_valid(_selected):
		_selected.set_selected(false)
	_selected = row
	row.set_selected(true)
