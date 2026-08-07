class_name BurnSlot
extends PanelContainer

## One pipeline slot.
##
## Tap-to-select then tap-to-place/swap is the only interaction; drag-and-drop
## used to be offered too, but it stole the same gesture a scroll drag needs,
## so placement now lives entirely in the dedicated pipeline editor. This slot
## can also be shown non-interactive (`set_interactive(false)`), which is how
## the work screen displays a read-only strip during a burn animation.

signal slot_pressed(index: int)

var index: int = 0
var operation_id: String = ""
var blocked: bool = false
var interactive: bool = true

var _name_label: Label
var _badge_label: Label
var _detail_label: Label
var _combo_label: Label
var _icon: TextureRect
var _selected: bool = false
var _packet: ColorRect
var _tap := TapGesture.new()


func _ready() -> void:
	# Passes events on so a drag down the pipeline scrolls the list instead of
	# being swallowed by whichever slot the finger happened to land on.
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size.y = 120
	_build()


## Non-interactive slots (the work screen's read-only strip) still animate
## during a burn but never claim tap input, so the pipeline editor stays the
## only place a slot can be selected.
func set_interactive(value: bool) -> void:
	interactive = value
	mouse_filter = Control.MOUSE_FILTER_PASS if interactive else Control.MOUSE_FILTER_IGNORE


func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UiThemeBuilder.SPACE_MD)
	margin.add_theme_constant_override("margin_right", UiThemeBuilder.SPACE_MD)
	margin.add_theme_constant_override("margin_top", UiThemeBuilder.SPACE_SM)
	margin.add_theme_constant_override("margin_bottom", UiThemeBuilder.SPACE_SM)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiThemeBuilder.SPACE_MD)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(56, 56)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 2)
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_column)

	_name_label = Label.new()
	_name_label.theme_type_variation = &"TitleLabel"
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(_name_label)

	_detail_label = Label.new()
	_detail_label.theme_type_variation = &"MutedLabel"
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(_detail_label)

	# A combo only exists because of what is in the slot above or below, so it
	# is reported on the slot rather than on the module.
	_combo_label = Label.new()
	_combo_label.theme_type_variation = &"AccentLabel"
	_combo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_combo_label.visible = false
	_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_label.add_theme_color_override("font_color", UiThemeBuilder.semantic("perk"))
	text_column.add_child(_combo_label)

	_badge_label = Label.new()
	_badge_label.theme_type_variation = &"AccentLabel"
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_badge_label.custom_minimum_size = Vector2(130, 0)
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_badge_label)

	# Added last so the batch packet draws over the module it is passing through.
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	_packet = ColorRect.new()
	_packet.visible = false
	_packet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_packet)


func setup(p_index: int, p_operation_id: String, p_blocked: bool, blocked_label: String) -> void:
	index = p_index
	operation_id = p_operation_id
	blocked = p_blocked
	if _name_label == null:
		_build()

	set_combos([])
	if blocked:
		_name_label.text = "SLOT %d — OCCUPIED" % (index + 1)
		_detail_label.text = blocked_label
		_badge_label.text = "×"
		_icon.texture = AssetCatalog.status_icon("warning")
		_apply_style(UiThemeBuilder.color("red"), 0.35)
		tooltip_text = blocked_label
		return

	var operation: OperationDefinition = ContentDatabase.get_operation(operation_id)
	if operation == null:
		_name_label.text = "SLOT %d" % (index + 1)
		_detail_label.text = "Empty. Drop a module here."
		_badge_label.text = ""
		_icon.texture = null
		_apply_style(UiThemeBuilder.color("stroke_dim"), 1.0)
		tooltip_text = ""
		return

	_name_label.text = operation.name.to_upper()
	_detail_label.text = ExpressionEvaluator.new().render_template(
		operation.description_template, operation.parameters
	)
	_badge_label.text = ExpressionEvaluator.new().render_template(operation.badge, operation.parameters)
	_icon.texture = AssetCatalog.operation_icon(operation.category)
	_apply_style(AssetCatalog.rarity_color(operation.rarity), 1.0)
	tooltip_text = _detail_label.text


## Named pairings this module has live with its current neighbours, rendered
## with the module's own numbers so the payoff is a figure rather than a hint.
func set_combos(combos: Array, parameters: Dictionary = {}) -> void:
	if _combo_label == null:
		return
	var lines: PackedStringArray = []
	var evaluator := ExpressionEvaluator.new()
	for combo in combos:
		if not combo is Dictionary:
			continue
		lines.append("◆ %s — %s" % [
			str(combo.get("name", "Combo")),
			evaluator.render_template(str(combo.get("description", "")), parameters),
		])
	_combo_label.text = "\n".join(lines)
	_combo_label.visible = not lines.is_empty()


func set_selected(value: bool) -> void:
	_selected = value
	if _selected:
		_apply_style(UiThemeBuilder.semantic("action"), 1.0, 4)


## Marks the stage the batch is currently passing through.
func set_active(value: bool) -> void:
	modulate = Color(1.35, 1.35, 1.2) if value else Color.WHITE


## Sends a packet of tokens across the slot. `intensity` is the batch size
## relative to a full contract, so a big burn reads as a fatter pulse; `bugs`
## fragments it red when the stage wrote defects.
func pulse(bugs: int, intensity: float, duration: float) -> void:
	if _packet == null:
		return
	var width: float = 14.0 + 42.0 * clampf(intensity, 0.0, 1.0)
	_packet.color = UiThemeBuilder.semantic("danger") if bugs > 0 else UiThemeBuilder.semantic("compute")
	_packet.size = Vector2(width, 6.0)
	_packet.position = Vector2(0.0, size.y - 8.0)
	_packet.visible = true
	var tween: Tween = create_tween()
	tween.tween_property(_packet, "position:x", maxf(0.0, size.x - width), maxf(0.05, duration))
	tween.tween_callback(func() -> void: _packet.visible = false)


func _apply_style(border: Color, alpha: float, border_width: int = 2) -> void:
	var style := StyleBoxFlat.new()
	var base: Color = UiThemeBuilder.color("bg_panel")
	style.bg_color = Color(base.r, base.g, base.b, 0.9 * alpha)
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = border
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 18
	style.corner_radius_bottom_left = 4
	add_theme_stylebox_override("panel", style)


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if _tap.feed(event):
		slot_pressed.emit(index)
		accept_event()
