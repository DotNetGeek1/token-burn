class_name EffectBreakdownSheet
extends BottomSheet

@onready var _base_label: Label = $Margin/VBox/BaseLabel
@onready var _final_label: Label = $Margin/VBox/FinalLabel
@onready var _steps_vbox: VBoxContainer = $Margin/VBox/Scroll/StepsVBox
@onready var _scroll: ScrollContainer = $Margin/VBox/Scroll
@onready var _empty_label: Label = $Margin/VBox/EmptyLabel

@onready var _close_button: Button = $Margin/VBox/HeaderHBox/CloseButton


func _ready() -> void:
	super._ready()
	_close_button.pressed.connect(hide_sheet)
	visible = false


func show_content(title: String, body: String) -> void:
	$Margin/VBox/HeaderHBox/TitleLabel.text = title
	$Margin/VBox/BodyLabel.text = body
	$Margin/VBox/BodyLabel.visible = true
	_set_breakdown_mode(false)
	visible = true


func show_breakdown(display_title: String, target_path: String, chain_id: String = "") -> void:
	$Margin/VBox/HeaderHBox/TitleLabel.text = display_title
	$Margin/VBox/BodyLabel.visible = false
	_set_breakdown_mode(true)

	var breakdown: Dictionary = Simulation.query_effect_breakdown(target_path, chain_id)
	var entries: Array = breakdown.get("entries", [])

	for child in _steps_vbox.get_children():
		child.queue_free()

	if entries.is_empty():
		_base_label.visible = false
		_final_label.visible = false
		_scroll.visible = false
		_empty_label.visible = true
		_empty_label.text = "No modifiers recorded yet"
	else:
		_empty_label.visible = false
		_scroll.visible = true
		_base_label.visible = true
		_final_label.visible = true
		_base_label.text = "Base: %s" % _format_value(target_path, breakdown.get("base_value"))
		_final_label.text = "Final: %s" % _format_value(target_path, breakdown.get("final_value"))
		for i in range(entries.size()):
			var entry: Dictionary = entries[i]
			if entry is Dictionary:
				_steps_vbox.add_child(_make_step_row(i + 1, entry, target_path))

	visible = true


func hide_sheet() -> void:
	super.hide_sheet()
	for child in _steps_vbox.get_children():
		child.queue_free()


func _set_breakdown_mode(enabled: bool) -> void:
	_scroll.visible = enabled
	_base_label.visible = enabled
	_final_label.visible = enabled
	_empty_label.visible = false
	if not enabled:
		for child in _steps_vbox.get_children():
			child.queue_free()


func _format_value(target_path: String, value: Variant) -> String:
	if value == null:
		return "—"
	match target_path:
		"compute.token_rate":
			return NumberFormat.format_token_rate(float(value))
		"job.reward":
			return NumberFormat.format_cash(float(value))
		_:
			return NumberFormat.format(float(value))


func _make_step_row(index: int, entry: Dictionary, target_path: String) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var header := Label.new()
	var source_id: String = str(entry.get("source_id", ""))
	if source_id == "":
		source_id = "unknown"
	var operation: String = str(entry.get("operation", ""))
	header.text = "%d. %s · %s" % [index, source_id, operation]
	header.add_theme_font_size_override("font_size", UiThemeBuilder.FONT_SMALL)
	header.add_theme_color_override("font_color", UiThemeBuilder.color("white"))
	row.add_child(header)

	var values := Label.new()
	var before_text: String = _format_value(target_path, entry.get("before"))
	var after_text: String = _format_value(target_path, entry.get("after"))
	values.text = "%s → %s" % [before_text, after_text]
	values.add_theme_font_size_override("font_size", UiThemeBuilder.FONT_SMALL)
	values.add_theme_color_override("font_color", UiThemeBuilder.color("blue"))
	row.add_child(values)

	var event_name: String = str(entry.get("event_name", ""))
	if event_name != "":
		var event_label := Label.new()
		event_label.text = event_name
		event_label.add_theme_font_size_override("font_size", UiThemeBuilder.FONT_SMALL - 2)
		event_label.add_theme_color_override("font_color", UiThemeBuilder.color("grey"))
		row.add_child(event_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	row.add_child(spacer)

	return row
