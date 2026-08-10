class_name ConsoleMenuRow
extends Button

## One line of the title terminal's menu: `[n] LABEL` on the left, the current
## value or hint on the right, all in the fixed-pitch face so the numbers line up
## down the column.
##
## The row is a plain text line until the pointer reaches it, at which point it
## inverts to a solid phosphor bar with black text — the way a selected line looks
## on a real console, and the only affordance the screen needs.

## Phosphor green the whole terminal is drawn in. Kept here rather than in the
## theme because this screen is diegetic and deliberately ignores the app palette.
const PHOSPHOR := Color(0.42, 0.92, 0.60)
const PHOSPHOR_DIM := Color(0.30, 0.62, 0.44)
const INK := Color(0.03, 0.07, 0.06)

const ROW_HEIGHT := 24
const PAD_H := 8

@export var index_label: String = "1":
	set(value):
		index_label = value
		_apply_text()

@export var headline: String = "":
	set(value):
		headline = value
		_apply_text()

@export var value_text: String = "":
	set(value):
		value_text = value
		_apply_text()

## Destructive lines burn red instead of green, both idle and inverted.
@export var destructive: bool = false:
	set(value):
		destructive = value
		_apply_palette()

var _margin: MarginContainer = null
var _row: HBoxContainer = null
var _index: Label = null
var _headline: Label = null
var _value: Label = null
var _revealed: int = -1
var _font_size: int = UiThemeBuilder.FONT_SMALL


func _ready() -> void:
	text = ""
	icon = null
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(0, ROW_HEIGHT)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_build()
	_apply_palette()
	_apply_text()
	pressed.connect(func() -> void: UiSound.play("tap"))
	mouse_entered.connect(func() -> void: UiSound.play("key"))


func accent() -> Color:
	return Color(0.86, 0.34, 0.40) if destructive else PHOSPHOR


func _build() -> void:
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.add_theme_constant_override("margin_left", PAD_H)
	_margin.add_theme_constant_override("margin_right", PAD_H)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(row)
	_row = row

	_index = _line()
	row.add_child(_index)

	_headline = _line()
	_headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_headline)

	_value = _line()
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Left unclipped so it keeps its natural minimum width. A clipped label
	# reports zero, and the expanding headline beside it then takes the row.
	_value.clip_text = false
	row.add_child(_value)


func _line() -> Label:
	var label := Label.new()
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font: Font = UiThemeBuilder.mono_font()
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", _font_size)
	return label


## The row lives on a laptop screen inside the scene, so its type and its height
## are handed down from however large that screen ended up being drawn.
func set_metrics(font_size: int, height: int, pad_h: int) -> void:
	_font_size = font_size
	if _margin == null:
		return
	custom_minimum_size = Vector2(0, height)
	_margin.add_theme_constant_override("margin_left", pad_h)
	_margin.add_theme_constant_override("margin_right", pad_h)
	_row.add_theme_constant_override("separation", maxi(2, int(font_size * 0.6)))
	# Widest bracket is "[9]", so reserving it keeps every label at one column.
	_index.custom_minimum_size = Vector2(font_size * 2.2, 0)
	for label: Label in [_index, _headline, _value]:
		label.add_theme_font_size_override("font_size", font_size)


func _apply_text() -> void:
	if _index == null:
		return
	_index.text = "[%s]" % index_label
	_headline.text = headline
	_value.text = value_text
	set_reveal(_revealed)


func _apply_palette() -> void:
	if _index == null:
		return
	var lit: Color = accent()
	_index.add_theme_color_override("font_color", PHOSPHOR_DIM)
	_headline.add_theme_color_override("font_color", lit)
	_value.add_theme_color_override("font_color", PHOSPHOR_DIM)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, _surface(state, lit))


## Inverse video for hover, press and focus; the idle line is bare text with no
## container at all, so the menu reads as printed output rather than as widgets.
func _surface(state: String, lit: Color) -> StyleBox:
	var box := StyleBoxFlat.new()
	box.corner_radius_top_left = 0
	box.corner_radius_top_right = 0
	box.corner_radius_bottom_left = 0
	box.corner_radius_bottom_right = 0
	match state:
		"hover", "focus":
			box.bg_color = Color(lit.r, lit.g, lit.b, 0.82)
		"pressed":
			box.bg_color = lit
		_:
			box.bg_color = Color(lit.r, lit.g, lit.b, 0.0)
	return box


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		_sync_ink()
	elif what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		_sync_ink()


## While the row is inverted the text has to flip to the dark ink or it vanishes
## into its own highlight.
func _sync_ink() -> void:
	if _index == null:
		return
	var inverted: bool = is_hovered() or has_focus()
	var lit: Color = accent()
	_index.add_theme_color_override("font_color", INK if inverted else PHOSPHOR_DIM)
	_headline.add_theme_color_override("font_color", INK if inverted else lit)
	_value.add_theme_color_override(
		"font_color", Color(INK.r, INK.g, INK.b, 0.75) if inverted else PHOSPHOR_DIM
	)


## Total characters in the line, for the boot printer's budget.
func reveal_length() -> int:
	return _index.text.length() + _headline.text.length() + _value.text.length()


## Prints the line left to right. -1 shows the whole row.
func set_reveal(characters: int) -> void:
	_revealed = characters
	if _index == null:
		return
	if characters < 0:
		for label: Label in [_index, _headline, _value]:
			label.visible_characters = -1
		return
	var budget: int = characters
	for label: Label in [_index, _headline, _value]:
		label.visible_characters = clampi(budget, 0, label.text.length())
		budget -= label.text.length()
