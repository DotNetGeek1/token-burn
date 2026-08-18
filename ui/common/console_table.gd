class_name ConsoleTable
extends VBoxContainer

## A table as a line printer prints one: fixed-pitch columns across a carriage
## of whatever width the screen it is on happens to be.
##
## Which columns are printed is the table's own decision. A monitor takes the
## whole board; a handset's carriage is barely sixty characters wide once the
## type has been scaled up to be readable, and a board squeezed onto it would be
## nine columns of clipped words. So the columns that can be spared are dropped
## until the rest fit at their full width, and what they said is in the pane
## underneath as soon as a line is selected.

signal row_selected(meta: Variant)

const ROW_HEIGHT := 26
const PAD_H := 8
## Width of one character of the fixed-pitch face, as a fraction of its size.
const MONO_ADVANCE := 0.6
## The gap between columns, in characters.
const GAP_CHARS := 1.2

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")


class Row:
	extends Button

	var meta: Variant = null
	var _cells: Array = []
	var _labels: Array[Label] = []
	var _dots: Array = []
	var _accents: Array[Color] = []
	var _lit: Color = ConsoleStyle.PHOSPHOR
	var _selected: bool = false
	var _margin: MarginContainer = null
	var _row_box: HBoxContainer = null

	func _init(columns: Array, cells: Array, printed: Array, lit: Color, scale: float) -> void:
		_lit = lit
		_cells = cells
		text = ""
		mouse_filter = Control.MOUSE_FILTER_PASS
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(0, ConsoleMetrics.row_height(scale))
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_margin = MarginContainer.new()
		_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		_margin.add_theme_constant_override("margin_left", ConsoleMetrics.pad_h(scale))
		_margin.add_theme_constant_override("margin_right", ConsoleMetrics.pad_h(scale))
		_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_margin)
		_row_box = HBoxContainer.new()
		_row_box.add_theme_constant_override("separation", ConsoleMetrics.px(10, scale))
		_row_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_margin.add_child(_row_box)
		print_columns(columns, printed, scale)
		_apply_palette()

	## Re-prints the line over the columns the table has room for. The data a
	## dropped column carried is kept, so a window widened again reprints it.
	func print_columns(columns: Array, printed: Array, scale: float) -> void:
		for child in _row_box.get_children():
			_row_box.remove_child(child)
			child.queue_free()
		_labels.clear()
		_dots.clear()
		_accents.clear()
		for index in printed:
			var cell: Variant = _cells[index] if index < _cells.size() else ""
			_row_box.add_child(_cell(columns[index], cell, scale))
		_sync_ink()

	func _cell(column: Dictionary, cell: Variant, scale: float) -> Control:
		var alignment: int = int(column.get("align", HORIZONTAL_ALIGNMENT_LEFT))
		var weight: float = float(column.get("weight", 1.0))
		var reserved: float = ConsoleTable.column_width(column, scale)
		if cell is Dictionary and cell.has("dots"):
			var strip := ConsoleTable.DotStrip.new(scale)
			strip.filled = int(cell["dots"])
			strip.total = int(cell.get("max", 5))
			strip.color = Color(cell.get("color", ConsoleStyle.PHOSPHOR))
			strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			strip.size_flags_stretch_ratio = weight
			strip.custom_minimum_size.x = reserved
			_dots.append(strip)
			return strip
		var text_value: String = ""
		var color: Color = ConsoleStyle.PHOSPHOR
		if cell is Dictionary:
			text_value = str(cell.get("text", ""))
			color = Color(cell.get("color", ConsoleStyle.PHOSPHOR))
		else:
			text_value = str(cell)
		var label: Label = ConsoleStyle.label(text_value, ConsoleMetrics.font_small(scale), color)
		label.clip_text = true
		label.horizontal_alignment = alignment
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = weight
		label.custom_minimum_size.x = reserved
		_labels.append(label)
		_accents.append(color)
		return label

	func apply_metrics(columns: Array, printed: Array, scale: float) -> void:
		custom_minimum_size = Vector2(0, ConsoleMetrics.row_height(scale))
		_margin.add_theme_constant_override("margin_left", ConsoleMetrics.pad_h(scale))
		_margin.add_theme_constant_override("margin_right", ConsoleMetrics.pad_h(scale))
		_row_box.add_theme_constant_override("separation", ConsoleMetrics.px(10, scale))
		# Re-printed rather than re-fonted: a column reserves its width in
		# characters, so type of a different size is a different set of columns.
		print_columns(columns, printed, scale)

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

	func _sync_ink() -> void:
		var inverted: bool = _selected or is_hovered() or has_focus()
		for i in range(_labels.size()):
			_labels[i].add_theme_color_override(
				"font_color", ConsoleStyle.INK if inverted else _accents[i]
			)
		for strip in _dots:
			strip.inverted = inverted
			strip.queue_redraw()


class DotStrip:
	extends Control

	var filled: int = 0
	var total: int = 5
	var color: Color = ConsoleStyle.PHOSPHOR
	var inverted: bool = false
	var _dot: float = 6.0
	var _gap: float = 4.0

	func _init(scale: float = 1.0) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		apply_metrics(scale)

	func apply_metrics(scale: float) -> void:
		_dot = float(ConsoleMetrics.px(6, scale))
		_gap = float(ConsoleMetrics.px(4, scale))
		# Only the height is asked for here; the width a rating holds is the
		# width its column reserved, set where every other cell's is. A strip
		# that insisted on the size its dots would like to be drawn at would
		# take that out of the columns either side, and the heading above it
		# would no longer sit over its own column.
		custom_minimum_size.y = _dot
		queue_redraw()

	func _draw() -> void:
		var lit: Color = ConsoleStyle.INK if inverted else color
		var unlit: Color = Color(lit.r, lit.g, lit.b, 0.25)
		var pitch: float = _dot + _gap
		if size.x > 0.0 and float(total) * pitch > size.x:
			pitch = size.x / float(total)
		var dot: float = maxf(2.0, minf(_dot, pitch - _gap * 0.5))
		var top: float = (size.y - dot) * 0.5
		for i in range(total):
			var rect := Rect2(float(i) * pitch, top, dot, dot)
			draw_rect(rect, lit if i < filled else unlit, i < filled)


var _columns: Array = []
## Which of them the carriage has room for, in order.
var _printed: Array = []
var _header: HBoxContainer = null
var _header_margin: MarginContainer = null
var _rows_box: VBoxContainer = null
var _rows: Array[Row] = []
var _selected: Row = null
var _scale: float = 1.0


func _ready() -> void:
	add_theme_constant_override("separation", 2)
	if _rows_box == null:
		_build()
	resized.connect(_fit_columns)


func _build() -> void:
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 10)
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_margin = MarginContainer.new()
	_header_margin.add_theme_constant_override("margin_left", PAD_H)
	_header_margin.add_theme_constant_override("margin_right", PAD_H)
	_header_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_margin.add_child(_header)
	add_child(_header_margin)
	add_child(ConsoleStyle.rule(0.22))
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 0)
	add_child(_rows_box)


func set_metrics(scale: float) -> void:
	_scale = scale
	if _header_margin == null:
		return
	# Bigger type on the same carriage is a narrower board, so the columns are
	# re-chosen before anything is re-sized to fit them.
	_fit_columns()
	var pad: int = ConsoleMetrics.pad_h(scale)
	var font_tiny: int = ConsoleMetrics.font_tiny(scale)
	_header_margin.add_theme_constant_override("margin_left", pad)
	_header_margin.add_theme_constant_override("margin_right", pad)
	_header.add_theme_constant_override("separation", ConsoleMetrics.px(10, scale))
	for child in _header.get_children():
		if child is Label:
			child.add_theme_font_size_override("font_size", font_tiny)
	for row in _rows:
		row.apply_metrics(_columns, _printed, scale)
	for child in _rows_box.get_children():
		if child is Row:
			continue
		if child is MarginContainer:
			child.add_theme_constant_override("margin_left", pad)
			for note_child in child.get_children():
				if note_child is Label:
					note_child.add_theme_font_size_override("font_size", font_tiny)


## Declares the whole board. Each column is `{label, weight}`, and may also
## carry `min_chars` — the width below which printing it is pointless — and
## `optional`, the order in which it is given up when the carriage is too
## narrow, lowest first.
func set_columns(columns: Array) -> void:
	if _rows_box == null:
		_build()
	_columns = columns
	_printed = []
	_fit_columns()


## Characters a column asked for, or as many as its own heading takes.
static func column_chars(column: Dictionary) -> float:
	return float(column.get("min_chars", str(column.get("label", "")).length() + 2))


## The width a column holds on to however the rest of the board is laid out.
## The header and the lines under it are measured the same way, which is what
## keeps a heading over its own column instead of drifting off it.
static func column_width(column: Dictionary, scale: float) -> float:
	return column_chars(column) * float(ConsoleMetrics.font_small(scale)) * MONO_ADVANCE


## Chooses the widest board this carriage can print at full width.
func _fit_columns() -> void:
	if _columns.is_empty() or _header == null:
		return
	var keep: Array = []
	for index in range(_columns.size()):
		keep.append(index)
	var carriage: float = _carriage_chars()
	if carriage > 0.0:
		while _needed_chars(keep) > carriage:
			var victim: int = _next_drop(keep)
			if victim < 0:
				break
			keep.erase(victim)
	if keep == _printed:
		return
	_printed = keep
	_print_header()
	for row in _rows:
		row.print_columns(_columns, _printed, _scale)


## How many characters of the fixed-pitch face fit across the table.
func _carriage_chars() -> float:
	var advance: float = float(ConsoleMetrics.font_small(_scale)) * MONO_ADVANCE
	if size.x <= 1.0 or advance <= 0.0:
		return 0.0
	return (size.x - float(ConsoleMetrics.pad_h(_scale)) * 2.0) / advance


## What the board would take to print without clipping a word.
func _needed_chars(keep: Array) -> float:
	var total: float = 0.0
	for index in keep:
		total += column_chars(_columns[index])
	return total + GAP_CHARS * float(maxi(0, keep.size() - 1))


## The next column to give up: the one its screen said it could most afford to.
func _next_drop(keep: Array) -> int:
	var victim: int = -1
	var priority: int = 0
	for index in keep:
		var optional: int = int(_columns[index].get("optional", 0))
		if optional <= 0:
			continue
		if victim < 0 or optional < priority:
			victim = index
			priority = optional
	return victim


func _print_header() -> void:
	for child in _header.get_children():
		_header.remove_child(child)
		child.queue_free()
	for index in _printed:
		var column: Dictionary = _columns[index]
		var label: Label = ConsoleStyle.label(
			str(column.get("label", "")).to_upper(),
			ConsoleMetrics.font_tiny(_scale),
			ConsoleStyle.PHOSPHOR_DIM
		)
		label.clip_text = true
		label.horizontal_alignment = int(column.get("align", HORIZONTAL_ALIGNMENT_LEFT))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = float(column.get("weight", 1.0))
		label.custom_minimum_size.x = column_width(column, _scale)
		_header.add_child(label)


## One line of the board. `cells` covers every declared column, printed or not.
func add_row(cells: Array, meta: Variant = null, lit: Color = ConsoleStyle.PHOSPHOR) -> Row:
	if _rows_box == null:
		_build()
	var row := Row.new(_columns, cells, _printed, lit, _scale)
	row.meta = meta
	row.pressed.connect(_on_row_pressed.bind(row))
	row.mouse_entered.connect(func() -> void: UiSound.play("key"))
	_rows_box.add_child(row)
	_rows.append(row)
	return row


func add_note(text: String, color: Color = ConsoleStyle.PHOSPHOR_DIM) -> void:
	if _rows_box == null:
		_build()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", ConsoleMetrics.pad_h(_scale))
	margin.add_theme_constant_override("margin_top", ConsoleMetrics.px(4, _scale))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(ConsoleStyle.label(text, ConsoleMetrics.font_tiny(_scale), color))
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


## Puts the board back to nothing selected, for a screen whose detail pane has
## been closed: a lit row with no pane under it reads as a lost press.
func clear_selection() -> void:
	if _selected != null and is_instance_valid(_selected):
		# Given up along with the selection: a line pressed by finger keeps the
		# focus afterwards, and a focused line prints itself in inverse video —
		# which on a board with nothing selected is a line of dark text on a
		# background that is no longer lit behind it.
		_selected.release_focus()
		_selected.set_selected(false)
	_selected = null


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
