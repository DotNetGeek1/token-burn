class_name ScreenHeader
extends VBoxContainer

## Shared tab-screen header: uppercase title on the left, contextual stat on
## the right, plus an optional secondary row with its own action button.
##
## The title and the sub-line both wrap. A Label that does not wrap reports its
## whole single line as a minimum width, and the sub-line carries a sentence of
## run state ("Ad Spend: $0/day · Reputation 10 ..."), which was wider than the
## content column: the screen then grew past the viewport in both directions and
## every tab using this header was clipped at both edges.

signal action_pressed

@onready var title_label: Label = $TitleRow/TitleLabel
@onready var context_label: Label = $TitleRow/ContextLabel
@onready var sub_row: HBoxContainer = $SubRow
@onready var sub_label: Label = $SubRow/SubLabel
@onready var action_button: GameButton = $SubRow/ActionButton


func _ready() -> void:
	sub_row.visible = false
	action_button.pressed.connect(func(): action_pressed.emit())


func setup(title: String, context: String = "") -> void:
	title_label.text = title.to_upper()
	context_label.text = context
	context_label.visible = context != ""


func set_context(context: String, role: String = "") -> void:
	context_label.text = context
	context_label.visible = context != ""
	if role != "":
		context_label.add_theme_color_override("font_color", UiThemeBuilder.semantic(role))


func set_sub_line(text: String, action_text: String = "") -> void:
	sub_row.visible = text != "" or action_text != ""
	sub_label.text = text
	action_button.visible = action_text != ""
	action_button.set_lines(action_text.to_upper())
