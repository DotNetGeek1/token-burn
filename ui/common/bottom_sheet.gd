class_name BottomSheet
extends PanelContainer

## Modal bottom sheet with a built-in dim backdrop and close affordance.
## The backdrop is created as a sibling directly below the sheet so it dims
## everything behind the sheet; tapping it (or Close) hides the sheet.

var _backdrop: ColorRect = null
var _backdrop_tap := TapGesture.new()


func _ready() -> void:
	add_theme_stylebox_override("panel", UiThemeBuilder.sheet_style())
	visibility_changed.connect(_sync_backdrop)
	_ensure_close_button()
	_sync_backdrop()


func show_content(title: String, body: String) -> void:
	$Margin/VBox/TitleLabel.text = title
	$Margin/VBox/BodyLabel.text = body
	$Margin/VBox/BodyLabel.visible = true
	_hide_breakdown_extras()
	UiTransition.reveal_sheet(self)


func hide_sheet() -> void:
	visible = false


func _sync_backdrop() -> void:
	if not is_inside_tree():
		return
	if _backdrop == null:
		_backdrop = ColorRect.new()
		_backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
		_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		_backdrop.gui_input.connect(_on_backdrop_input)
		var parent := get_parent()
		parent.add_child.call_deferred(_backdrop)
		_backdrop.ready.connect(func():
			_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
			_position_backdrop()
			_backdrop.visible = visible
		)
		return
	_position_backdrop()
	_backdrop.visible = visible


func _position_backdrop() -> void:
	var parent := get_parent()
	if _backdrop.get_parent() == parent:
		parent.move_child(_backdrop, maxi(get_index() - 1, 0))


func _on_backdrop_input(event: InputEvent) -> void:
	if _backdrop_tap.feed(event):
		hide_sheet()


func _ensure_close_button() -> void:
	if has_node("Margin/VBox/HeaderHBox/CloseButton"):
		return
	if not has_node("Margin/VBox"):
		return
	var close_button := GameButton.new()
	close_button.name = "SheetCloseButton"
	close_button.theme_type_variation = &"SecondaryButton"
	close_button.accent_key = "neutral"
	close_button.custom_minimum_size = Vector2(0, UiThemeBuilder.TOUCH_TARGET)
	close_button.pressed.connect(hide_sheet)
	$Margin/VBox.add_child(close_button)
	close_button.set_lines("CLOSE")


func _hide_breakdown_extras() -> void:
	if has_node("Margin/VBox/Scroll"):
		$Margin/VBox/Scroll.visible = false
	if has_node("Margin/VBox/BaseLabel"):
		$Margin/VBox/BaseLabel.visible = false
	if has_node("Margin/VBox/FinalLabel"):
		$Margin/VBox/FinalLabel.visible = false
	if has_node("Margin/VBox/EmptyLabel"):
		$Margin/VBox/EmptyLabel.visible = false
