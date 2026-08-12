class_name ConsoleTable
extends VBoxContainer

signal row_selected(meta: Variant)

const ROW_HEIGHT := 26
const PAD_H := 8

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")


class Row:
	extends Button

	var meta: Variant = null
	var _labels: Array[Label] = []
	var _dots: Array = []
	var _accents: Array[Color] = []
	var _lit: Color = ConsoleStyle.PHOSPHOR
	var _selected: bool = false
	var _margin: MarginContainer = null
	var _row_box: HBoxContainer = null

	func _init(columns: Array, cells: Array, lit: Color, scale: float = 1.0) -> void:
		_lit = lit
		text = ""
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
		for i in range(columns.size()):
			var column: Dictionary = columns[i]
			var cell: Variant = cells[i] if i < cells.size() else ""
			_row_box.add_child(_cell(column, cell, scale))
		_apply_palette()

	func _cell(column: Dictionary, cell: Variant, scale: float) -> Control:
		var alignment: int = int(column.get("align", HORIZONTAL_ALIGNMENT_LEFT))
		var weight: float = float(column.get("weight", 1.0))
		if cell is Dictionary and cell.has("dots"):
			var strip := ConsoleTable.DotStrip.new(scale)
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
		var label: Label = ConsoleStyle.label(text_value, ConsoleMetrics.font_small(scale), color)
		label.clip_text = true
		label.horizontal_alignment = alignment
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = weight
		_labels.append(label)
		_accents.append(color)
		return label

	func apply_metrics(scale: float) -> void:
		custom_minimum_size = Vector2(0, ConsoleMetrics.row_height(scale))
		_margin.add_theme_constant_override("margin_left", ConsoleMetrics.pad_h(scale))
		_margin.add_theme_constant_override("margin_right", ConsoleMetrics.pad_h(scale))
		_row_box.add_theme_constant_override("separation", ConsoleMetrics.px(10, scale))
		var font_small: int = ConsoleMetrics.font_small(scale)
		for label in _labels:
			label.add_theme_font_size_override("font_size", font_small)
		for strip in _dots:
			(strip as ConsoleTable.DotStrip).apply_metrics(scale)

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
		custom_minimum_size = Vector2(float(total) * (_dot + _gap), _dot)
		queue_redraw()

	func _draw() -> void:
		var lit: Color = ConsoleStyle.INK if inverted else color
		var unlit: Color = Color(lit.r, lit.g, lit.b, 0.25)
		var top: float = (size.y - _dot) * 0.5
		for i in range(total):
			var rect := Rect2(float(i) * (_dot + _gap), top, _dot, _dot)
			draw_rect(rect, lit if i < filled else unlit, i < filled)


var _columns: Array = []
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
	var pad: int = ConsoleMetrics.pad_h(scale)
	var font_tiny: int = ConsoleMetrics.font_tiny(scale)
	_header_margin.add_theme_constant_override("margin_left", pad)
	_header_margin.add_theme_constant_override("margin_right", pad)
	_header.add_theme_constant_override("separation", ConsoleMetrics.px(10, scale))
	for child in _header.get_children():
		if child is Label:
			child.add_theme_font_size_override("font_size", font_tiny)
	for row in _rows:
		row.apply_metrics(scale)
	for child in _rows_box.get_children():
		if child is Row:
			continue
		if child is MarginContainer:
			child.add_theme_constant_override("margin_left", pad)
			for note_child in child.get_children():
				if note_child is Label:
					note_child.add_theme_font_size_override("font_size", font_tiny)


func set_columns(columns: Array) -> void:
	if _rows_box == null:
		_build()
	_columns = columns
	for child in _header.get_children():
		child.queue_free()
	for column in columns:
		var label: Label = ConsoleStyle.label(
			str(column.get("label", "")).to_upper(),
			ConsoleMetrics.font_tiny(_scale),
			ConsoleStyle.PHOSPHOR_DIM
		)
		label.clip_text = true
		label.horizontal_alignment = int(column.get("align", HORIZONTAL_ALIGNMENT_LEFT))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = float(column.get("weight", 1.0))
		_header.add_child(label)


func add_row(cells: Array, meta: Variant = null, lit: Color = ConsoleStyle.PHOSPHOR) -> Row:
	if _rows_box == null:
		_build()
	var row := Row.new(_columns, cells, lit, _scale)
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
