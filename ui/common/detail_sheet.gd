class_name DetailSheet
extends BottomSheet

## Where the long text lives. Cards on a list screen carry only what the player
## compares; everything else (full numbers, rule explanations, why an upgrade is
## locked) opens here on a tap.

signal action_confirmed
## Second way out of the same decision. A sheet that offers only one action makes
## the alternative invisible, which is wrong when the alternative is "walk away".
signal secondary_confirmed

@onready var _kicker_label: Label = $Margin/VBox/HeaderHBox/TitleBox/KickerLabel
@onready var _title_label: Label = $Margin/VBox/HeaderHBox/TitleBox/TitleLabel
@onready var _close_button: Button = $Margin/VBox/HeaderHBox/CloseButton
@onready var _chip_row: HBoxContainer = $Margin/VBox/ChipRow
@onready var _content: VBoxContainer = $Margin/VBox/Scroll/ContentVBox
@onready var _action_button: GameButton = $Margin/VBox/ActionButton
@onready var _secondary_button: GameButton = $Margin/VBox/SecondaryActionButton


func _ready() -> void:
	super._ready()
	_close_button.pressed.connect(hide_sheet)
	_action_button.pressed.connect(func():
		action_confirmed.emit()
		hide_sheet()
	)
	_secondary_button.pressed.connect(func():
		secondary_confirmed.emit()
		hide_sheet()
	)
	visible = false


## `rows` accepts dictionaries describing one of three shapes:
## - {"stat": "Tokens", "value": "8.5M"}      a label/value information strip
## - {"rule": "Creative Truth", "text": "…"}  a named rule with its consequence
## - {"text": "…"}                            a plain paragraph
func show_detail(
	title: String,
	kicker: String,
	rows: Array,
	chips: Array = [],
	action_text: String = "",
	accent: Color = Color.TRANSPARENT,
	secondary_text: String = ""
) -> void:
	_title_label.text = title
	_kicker_label.text = kicker.to_upper()
	_kicker_label.visible = kicker != ""
	if accent != Color.TRANSPARENT:
		_kicker_label.add_theme_color_override("font_color", accent)
	_fill(_chip_row, chips.map(_chip_from))
	_chip_row.visible = not chips.is_empty()
	_fill(_content, rows.map(_row_from))
	_action_button.set_lines(action_text.to_upper())
	_action_button.visible = action_text != ""
	_secondary_button.set_lines(secondary_text.to_upper())
	_secondary_button.visible = secondary_text != ""
	UiTransition.reveal_sheet(self)


func _fill(container: Node, controls: Array) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	for control in controls:
		container.add_child(control)


func _chip_from(spec: Variant) -> Control:
	if spec is Dictionary:
		if spec.has("accent"):
			return UiChip.create_colored(str(spec.get("text", "")), spec["accent"], spec.get("icon", null), true)
		return UiChip.create(str(spec.get("text", "")), str(spec.get("role", "neutral")), spec.get("icon", null), true)
	return UiChip.create(str(spec), "neutral")


func _row_from(spec: Variant) -> Control:
	if not (spec is Dictionary):
		return _paragraph(str(spec))
	if spec.has("stat"):
		return _stat_row(str(spec["stat"]), str(spec.get("value", "")), str(spec.get("role", "")))
	if spec.has("rule"):
		return _rule_block(str(spec["rule"]), str(spec.get("text", "")), str(spec.get("role", "warning")))
	return _paragraph(str(spec.get("text", "")))


func _stat_row(name_text: String, value_text: String, role: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiThemeBuilder.SPACE_MD)
	var name_label := Label.new()
	name_label.text = name_text.to_upper()
	name_label.theme_type_variation = &"SectionLabel"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	var value_label := Label.new()
	value_label.text = value_text
	value_label.add_theme_font_size_override("font_size", UiThemeBuilder.FONT_BODY + 4)
	if role != "":
		value_label.add_theme_color_override("font_color", UiThemeBuilder.semantic(role))
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return row


func _rule_block(rule_name: String, text: String, role: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiThemeBuilder.SPACE_XS)
	box.add_child(UiChip.create_warning(rule_name, role))
	if text != "":
		box.add_child(_paragraph(text))
	return box


func _paragraph(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"MutedLabel"
	label.add_theme_font_size_override("font_size", UiThemeBuilder.FONT_BODY)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
