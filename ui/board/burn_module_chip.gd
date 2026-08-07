class_name BurnModuleChip
extends Button

## A module in the tray: tap it, then tap a slot in the pipeline editor.
##
## Drag-and-drop used to be an alternate way to place a module, but it stole
## the same gesture a scroll drag needs, so placement is tap-only now.

signal chip_pressed(operation_id: String)

var operation_id: String = ""
var on_board: bool = false


func _ready() -> void:
	# PASS lets a drag that starts on a chip still reach the tray's
	# ScrollContainer, instead of the chip swallowing the whole gesture.
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(operation: OperationDefinition, p_on_board: bool) -> void:
	operation_id = operation.id
	on_board = p_on_board
	text = operation.name
	icon = AssetCatalog.operation_icon(operation.category)
	custom_minimum_size = Vector2(0, UiThemeBuilder.TOUCH_TARGET)
	theme_type_variation = &"SecondaryButton" if on_board else &"PrimaryButton"
	# A module already in the pipeline reads dimmer: tapping it moves it.
	modulate = Color(0.72, 0.72, 0.78) if on_board else Color.WHITE
	var detail: String = ExpressionEvaluator.new().render_template(
		operation.description_template, operation.parameters
	)
	tooltip_text = detail if on_board else "%s\n\nOn the bench. Tap a slot to place it." % detail
	# Named pairings are the reason position matters, so they are advertised on
	# the bench rather than left to be discovered by accident.
	var pairings: PackedStringArray = []
	for combo in operation.combos:
		if combo is Dictionary:
			pairings.append(str(combo.get("name", "")))
	if not pairings.is_empty():
		tooltip_text += "\n\nCombos: %s" % ", ".join(pairings)
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)


func _on_pressed() -> void:
	chip_pressed.emit(operation_id)
