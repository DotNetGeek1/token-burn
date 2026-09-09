class_name PhoneStatement
extends VBoxContainer

## A statement printed on a handset screen.
##
## `ConsoleStatement` is the phosphor console's invoice: dotted leaders, a
## fixed-pitch figure column, ShareTechMono throughout. This is the same
## document — a heading, a note, a headline figure, then line items each with
## the sentence that explains its number — set in the phone's language so it
## can sit inside a `PhoneOverlay` next to the investor's call. The API matches
## `ConsoleStatement` so a screen can move between the two without rewording
## itself; `ConsoleStatement` remains for the run-end report.
##
## Items are `PhoneRows.stat_row`s (muted label left, monospace figure right)
## with a small muted explanation underneath. A bottom line (`emphasis`) gets a
## hairline above it and a heavier figure.

const COLUMN_SEPARATION := 8
const ITEM_SEPARATION := 10
const NOTE_SEPARATION := 2
## The headline figure is read from across the room, so it uses the display
## face rather than the body's.
const FIGURE_FONT_SIZE := 40
const EMPHASIS_FONT_SIZE := 20
const NOTE_FONT_SIZE := 12
const ASIDE_FONT_SIZE := 13


## One line of the statement: a labelled figure with its explanation under it.
class Line:
	extends VBoxContainer

	var _row: HBoxContainer = null
	var _value: Label = null
	var _note: Label = null
	var _emphasis: bool = false

	func _init(
		label_text: String, value_text: String, note_text: String, emphasis: bool, value_color: Color, scale: float
	) -> void:
		_emphasis = emphasis
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", NOTE_SEPARATION)
		_row = PhoneRows.stat_row(label_text, value_text)
		_value = _row.get_child(_row.get_child_count() - 1) as Label
		if _value != null:
			_value.add_theme_color_override("font_color", value_color)
		if emphasis:
			var key: Label = _row.get_child(0) as Label
			if key != null:
				key.add_theme_color_override("font_color", Color(UiThemeBuilder.TEXT_PRIMARY))
				var bold: Font = UiThemeBuilder.body_bold_font()
				if bold != null:
					key.add_theme_font_override("font", bold)
		add_child(_row)
		if note_text != "":
			_note = Label.new()
			_note.text = note_text
			_note.theme_type_variation = &"MutedLabel"
			_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			add_child(_note)
		apply_scale(scale)

	## The sizes this line sets itself, at `scale` of their authored value.
	func apply_scale(scale: float) -> void:
		if _value != null and _emphasis:
			_value.add_theme_font_size_override("font_size", PhoneStatement._scaled(EMPHASIS_FONT_SIZE, scale))
		if _note != null:
			_note.add_theme_font_size_override("font_size", PhoneStatement._scaled(NOTE_FONT_SIZE, scale))


static func _scaled(size: int, scale: float) -> int:
	return maxi(9, int(round(float(size) * scale)))


var _scale: float = 1.0
var _title: Label = null
var _note: Label = null
var _aside: Label = null
var _figure_box: VBoxContainer = null
var _figure: Label = null
var _figure_caption: Label = null
var _head_rule: ColorRect = null
var _items: VBoxContainer = null


func _ready() -> void:
	if _items == null:
		_build()


func _build() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", COLUMN_SEPARATION)

	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.visible = false
	add_child(_title)

	_note = PhoneRows.paragraph("")
	_note.theme_type_variation = &"MutedLabel"
	_note.visible = false
	add_child(_note)

	# His remark on the report: set apart from the note by its colour and a
	# lighter, slanted-looking face rather than a banner.
	_aside = PhoneRows.paragraph("")
	_aside.visible = false
	_aside.add_theme_font_size_override("font_size", _scaled(ASIDE_FONT_SIZE, _scale))
	add_child(_aside)

	_figure_box = VBoxContainer.new()
	_figure_box.visible = false
	_figure_box.add_theme_constant_override("separation", 0)
	_figure_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_figure_box)
	_figure = Label.new()
	_figure.theme_type_variation = &"DisplayLabel"
	_figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_figure.add_theme_font_size_override("font_size", _scaled(FIGURE_FONT_SIZE, _scale))
	var mono: Font = UiThemeBuilder.mono_font()
	if mono != null:
		_figure.add_theme_font_override("font", mono)
	_figure_box.add_child(_figure)
	_figure_caption = Label.new()
	_figure_caption.theme_type_variation = &"SectionLabel"
	_figure_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_figure_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_figure_box.add_child(_figure_caption)

	_head_rule = PhoneRows.rule()
	add_child(_head_rule)

	_items = VBoxContainer.new()
	_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_items.add_theme_constant_override("separation", ITEM_SEPARATION)
	add_child(_items)


## The document's heading. Reports that went well and reports that went badly
## are told apart by the colour of this line rather than by a banner.
func set_title(text: String, color: Color = Color(UiThemeBuilder.TEXT_PRIMARY)) -> void:
	if _items == null:
		_build()
	_title.text = text
	_title.visible = text != ""
	_title.add_theme_color_override("font_color", color)


## The standfirst under the heading: what the player is looking at, in a
## sentence. An empty note takes no room.
func set_note(text: String, color: Color = Color(UiThemeBuilder.TEXT_SECONDARY)) -> void:
	if _items == null:
		_build()
	_note.text = text
	_note.visible = text != ""
	_note.add_theme_color_override("font_color", color)


## A second line under the note, in its own colour: a remark passed on the
## report rather than a description of what it is.
func set_aside(text: String, color: Color = UiThemeBuilder.semantic("success")) -> void:
	if _items == null:
		_build()
	_aside.text = text
	_aside.visible = text != ""
	_aside.add_theme_color_override("font_color", color)


## The one number worth reading from across the room, printed above the items.
## Pass an empty caption and text to take it back off the page.
func set_figure(
	text: String, caption: String = "", color: Color = UiThemeBuilder.semantic("success")
) -> void:
	if _items == null:
		_build()
	_figure.text = text
	_figure.add_theme_color_override("font_color", color)
	_figure_caption.text = caption.to_upper()
	_figure_caption.visible = caption != ""
	_figure_box.visible = caption != "" or text != ""


## The headline figure's label, for callers that want to animate the number
## into place rather than print it outright.
func figure_label() -> Label:
	if _items == null:
		_build()
	return _figure


## One line item. `options` understands:
## - `"value_color"`  the figure's colour, for a charge that is bad news
## - `"emphasis"`     a bottom line: heavier type and a rule drawn above it
## - `"rule_above"`   a subtotal rule without the heavier type
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
		Color(options.get("value_color", Color(UiThemeBuilder.TEXT_PRIMARY))),
		_scale
	)
	_items.add_child(line)


## A hairline across the column, for a subtotal the following lines are
## measured against.
func add_rule() -> void:
	if _items == null:
		_build()
	_items.add_child(PhoneRows.rule())


func clear() -> void:
	if _items == null:
		_build()
	for child in _items.get_children():
		_items.remove_child(child)
		child.queue_free()


## The column of items, so a caller can stagger them in as they print.
func items() -> VBoxContainer:
	if _items == null:
		_build()
	return _items


## The sizes the statement sets itself — the headline figure, the bottom
## line, the notes — at `scale` of their authored value. The rest of its type
## comes from the theme, which the phone rescales on its own. Named to match
## `ConsoleStatement.set_metrics`.
func set_metrics(scale: float) -> void:
	if _items == null:
		_build()
	_scale = maxf(0.1, scale)
	_figure.add_theme_font_size_override("font_size", _scaled(FIGURE_FONT_SIZE, _scale))
	_aside.add_theme_font_size_override("font_size", _scaled(ASIDE_FONT_SIZE, _scale))
	for child in _items.get_children():
		if child is Line:
			(child as Line).apply_scale(_scale)
