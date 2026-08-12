class_name ConsoleStatement
extends VBoxContainer

## The console's printed statement: a titled column of line items with their
## figures ruled up in a right-hand column.
##
## The two end-of-round reports — what the round earned and what it cost — are
## the same document with different line items, so they share this instead of
## each growing its own stack of hand-built rows. A statement is a heading, an
## optional headline figure, and then the items themselves, each of which may
## carry the plain-language note that explains where its number came from.
##
## Figures are separated from their labels by a dotted leader and drawn in a
## fixed-pitch column, because a bill the player is meant to add up in their
## head has to line up down the page.

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

## The headline figure is the one thing on the page read from across the room,
## so it is sized well past the console's largest body face.
const FIGURE_SIZE := 34
## Width reserved for the figure column, in characters of the current face.
const FIGURE_COLUMN_CHARS := 10
## Clearance kept on the right so the figures never run into the scrollbar of
## whatever window the statement is being read in.
const GUTTER := 12


## The run of dots between a line item and its figure. Drawn rather than typed
## so it fills whatever width the label leaves behind at any scale.
class Leader:
	extends Control

	var _step: float = 5.0
	var _dot: float = 1.0

	func _init(scale: float = 1.0) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		apply_metrics(scale)

	func apply_metrics(scale: float) -> void:
		_step = float(ConsoleMetrics.px(5, scale))
		_dot = float(ConsoleMetrics.px(1, scale))
		custom_minimum_size = Vector2(_step * 3.0, _dot)
		queue_redraw()

	func _draw() -> void:
		var color := Color(
			ConsoleStyle.PHOSPHOR.r, ConsoleStyle.PHOSPHOR.g, ConsoleStyle.PHOSPHOR.b, 0.22
		)
		var y: float = floorf(size.y * 0.5)
		var x: float = _step
		while x < size.x - _step:
			draw_rect(Rect2(x, y, _dot, _dot), color, true)
			x += _step


## One line of the statement: a label, its figure, and the note underneath that
## says what the figure means.
class Line:
	extends VBoxContainer

	var _label: Label = null
	var _value: Label = null
	var _leader: Leader = null
	var _note: Label = null
	var _emphasis: bool = false

	func _init(
		label_text: String, value_text: String, note_text: String, emphasis: bool, value_color: Color
	) -> void:
		_emphasis = emphasis
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_theme_constant_override("separation", 2)
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(head)
		_label = ConsoleStyle.label(
			label_text.to_upper(),
			ConsoleStyle.FONT_SMALL,
			ConsoleStyle.PHOSPHOR if emphasis else ConsoleStyle.PHOSPHOR_DIM
		)
		head.add_child(_label)
		_leader = Leader.new()
		head.add_child(_leader)
		_value = ConsoleStyle.label(value_text, ConsoleStyle.FONT_SMALL, value_color)
		_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(_value)
		if note_text != "":
			_note = ConsoleStyle.paragraph(note_text, ConsoleStyle.FONT_TINY)
			add_child(_note)

	func apply_metrics(scale: float) -> void:
		var font: int = (
			ConsoleMetrics.font_body(scale) if _emphasis else ConsoleMetrics.font_small(scale)
		)
		add_theme_constant_override("separation", ConsoleMetrics.px(2, scale))
		_label.add_theme_font_size_override("font_size", font)
		_value.add_theme_font_size_override("font_size", font)
		# The figure column is reserved rather than measured, so every line's
		# number ends on the same edge however short its own figure is.
		_value.custom_minimum_size = Vector2(float(font) * 0.62 * float(FIGURE_COLUMN_CHARS), 0)
		_leader.apply_metrics(scale)
		if _note != null:
			_note.add_theme_font_size_override("font_size", ConsoleMetrics.font_tiny(scale))


var _gutter: MarginContainer = null
var _column: VBoxContainer = null
var _title: Label = null
var _note: Label = null
var _aside: Label = null
var _figure_box: VBoxContainer = null
var _figure: Label = null
var _figure_caption: Label = null
var _head_rule: ColorRect = null
var _items: VBoxContainer = null
var _lines: Array[Line] = []
var _rules: Array[ColorRect] = []
var _scale: float = 1.0


func _ready() -> void:
	if _items == null:
		_build()


func _build() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gutter = MarginContainer.new()
	_gutter.add_theme_constant_override("margin_right", GUTTER)
	_gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gutter)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 6)
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gutter.add_child(_column)
	_title = ConsoleStyle.label("", ConsoleStyle.FONT_HEAD, ConsoleStyle.PHOSPHOR)
	_column.add_child(_title)
	_note = ConsoleStyle.paragraph("", ConsoleStyle.FONT_SMALL)
	_column.add_child(_note)
	_aside = ConsoleStyle.paragraph("", ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR)
	_aside.visible = false
	_column.add_child(_aside)
	_figure_box = VBoxContainer.new()
	_figure_box.visible = false
	_figure_box.add_theme_constant_override("separation", 0)
	_figure_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_figure_box)
	_figure = ConsoleStyle.label("", FIGURE_SIZE, ConsoleStyle.PHOSPHOR)
	_figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_figure_box.add_child(_figure)
	_figure_caption = ConsoleStyle.label("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_figure_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_figure_box.add_child(_figure_caption)
	_head_rule = ConsoleStyle.rule(0.28)
	_column.add_child(_head_rule)
	_items = VBoxContainer.new()
	_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items.add_theme_constant_override("separation", 8)
	_column.add_child(_items)


## The document's heading. Reports that went well and reports that went badly
## are told apart by the colour of this line rather than by a banner.
func set_title(text: String, color: Color = ConsoleStyle.PHOSPHOR) -> void:
	if _items == null:
		_build()
	_title.text = text
	_title.add_theme_color_override("font_color", color)


## The standfirst under the heading: what the player is looking at, in a
## sentence. An empty note takes no room.
func set_note(text: String, color: Color = ConsoleStyle.PHOSPHOR_DIM) -> void:
	if _items == null:
		_build()
	_note.text = text
	_note.visible = text != ""
	_note.add_theme_color_override("font_color", color)


## A second line under the note, in its own colour: a remark passed on the
## report rather than a description of what it is.
func set_aside(text: String, color: Color = ConsoleStyle.PHOSPHOR) -> void:
	if _items == null:
		_build()
	_aside.text = text
	_aside.visible = text != ""
	_aside.add_theme_color_override("font_color", color)


## The one number worth reading from across the room, printed above the items.
## Pass an empty caption to take it back off the page.
func set_figure(text: String, caption: String = "", color: Color = ConsoleStyle.PHOSPHOR) -> void:
	if _items == null:
		_build()
	_figure.text = text
	_figure.add_theme_color_override("font_color", color)
	_figure_caption.text = caption.to_upper()
	_figure_box.visible = caption != "" or text != ""


## The headline figure's label, for callers that want to animate the number
## into place rather than print it outright.
func figure_label() -> Label:
	if _items == null:
		_build()
	return _figure


## One line item. `options` understands:
## - `"value_color"`  the figure's colour, for a charge that is bad news
## - `"emphasis"`     a bottom line: larger type and a rule drawn above it
## - `"rule_above"`   a subtotal rule without the larger type
func add_item(
	label_text: String, value_text: String, note_text: String = "", options: Dictionary = {}
) -> void:
	if _items == null:
		_build()
	var emphasis: bool = bool(options.get("emphasis", false))
	if emphasis or bool(options.get("rule_above", false)):
		add_rule()
	var line := Line.new(
		label_text,
		value_text,
		note_text,
		emphasis,
		Color(options.get("value_color", ConsoleStyle.PHOSPHOR))
	)
	_items.add_child(line)
	_lines.append(line)
	line.apply_metrics(_scale)


## A hairline across the figure column, for a subtotal the following lines are
## measured against.
func add_rule() -> void:
	if _items == null:
		_build()
	var rule: ColorRect = ConsoleStyle.rule(0.22)
	_items.add_child(rule)
	_rules.append(rule)


func clear() -> void:
	if _items == null:
		_build()
	for child in _items.get_children():
		_items.remove_child(child)
		child.queue_free()
	_lines.clear()
	_rules.clear()


## The column of items, so a caller can stagger them in as they print.
func items() -> VBoxContainer:
	if _items == null:
		_build()
	return _items


func set_metrics(scale: float) -> void:
	_scale = scale
	if _items == null:
		return
	_gutter.add_theme_constant_override("margin_right", ConsoleMetrics.px(GUTTER, scale))
	_column.add_theme_constant_override("separation", ConsoleMetrics.px(6, scale))
	_items.add_theme_constant_override("separation", ConsoleMetrics.px(8, scale))
	_title.add_theme_font_size_override("font_size", ConsoleMetrics.font_head(scale))
	_note.add_theme_font_size_override("font_size", ConsoleMetrics.font_small(scale))
	_aside.add_theme_font_size_override("font_size", ConsoleMetrics.font_small(scale))
	_figure.add_theme_font_size_override("font_size", ConsoleMetrics.px(FIGURE_SIZE, scale))
	_figure_caption.add_theme_font_size_override("font_size", ConsoleMetrics.font_tiny(scale))
	for line in _lines:
		line.apply_metrics(scale)
