class_name GameCard
extends PanelContainer

## Interactive card surface. The face carries only what the player compares on
## (kicker, name, headline value, a few chips); anything longer belongs in a
## detail sheet behind a tap.

signal pressed
## Tapping the card face rather than its action button. Screens that want a
## detail sheet connect this; screens that do not fall back to `pressed`, so a
## card with a single meaning stays tappable anywhere.
signal body_pressed

var _button_connected: bool = false
var _panel_connected: bool = false
var _disabled: bool = false
var _rail: Color = Color.TRANSPARENT
var _tap := TapGesture.new()


func setup(
	title: String,
	body: String,
	footer: String = "",
	action_text: String = "",
	icon: Texture2D = null,
	accent_key: String = ""
) -> void:
	var title_label: Label = $Margin/VBox/HeaderRow/TitleLabel
	var body_label: Label = $Margin/VBox/BodyLabel
	var footer_label: Label = $Margin/VBox/FooterLabel
	var action_button: GameButton = $Margin/VBox/ActionButton
	var icon_rect: TextureRect = $Margin/VBox/HeaderRow/Icon

	title_label.text = title
	body_label.text = body
	body_label.visible = body != ""
	footer_label.text = footer
	footer_label.visible = footer != ""
	if action_text != "":
		action_button.set_lines(action_text.to_upper())
		action_button.visible = true
	else:
		action_button.visible = false

	if icon != null:
		icon_rect.texture = icon
		icon_rect.visible = true
	else:
		icon_rect.visible = false

	add_theme_stylebox_override("panel", UiThemeBuilder.card_style(accent_key))
	if accent_key != "":
		var accent: Color = _accent_color(accent_key)
		footer_label.add_theme_color_override("font_color", accent)
		_light_rail(accent)

	if not _button_connected:
		action_button.pressed.connect(func(): if not _disabled: pressed.emit())
		_button_connected = true
	if not _panel_connected:
		gui_input.connect(_on_gui_input)
		_panel_connected = true


## Glyph and tint for the call to action, so BUY, ACCEPT and KEEP THIS read as
## different kinds of commitment rather than one generic confirm.
func set_action_style(
	icon_key: String, accent_key: String = "action", variation: String = ""
) -> void:
	var action_button: GameButton = $Margin/VBox/ActionButton
	action_button.icon_key = icon_key
	action_button.accent_key = accent_key
	if variation != "":
		action_button.theme_type_variation = StringName(variation)


## Colour identity for a data-driven category (job sector, upgrade group).
func set_accent(accent: Color) -> void:
	add_theme_stylebox_override("panel", UiThemeBuilder.card_style_accent(accent))
	($Margin/VBox/HeaderRow/Icon as TextureRect).modulate = accent.lightened(0.15)
	_light_rail(accent)


## The card's one lit edge. Painted rather than added as a child, because a
## `PanelContainer` stretches its children to its full rect, and it cannot come
## from the stylebox either: a stylebox has one border colour, so lighting the
## left border lights all four sides with it.
func _light_rail(accent: Color) -> void:
	_rail = accent
	queue_redraw()


func _draw() -> void:
	if _rail == Color.TRANSPARENT:
		return
	draw_rect(Rect2(0.0, 0.0, float(UiThemeBuilder.ACCENT_RAIL), size.y), _rail)


## Small uppercase line above the title: category and client.
func set_kicker(text: String, accent: Color = Color.TRANSPARENT) -> void:
	var label: Label = $Margin/VBox/KickerLabel
	label.text = text.to_upper()
	label.visible = text != ""
	if accent != Color.TRANSPARENT:
		label.add_theme_color_override("font_color", accent)


## The one number the decision turns on, shown large beside the title.
func set_headline(text: String, role: String = "money") -> void:
	var label: Label = $Margin/VBox/HeaderRow/HeadlineLabel
	label.text = text
	label.visible = text != ""
	label.add_theme_color_override("font_color", UiThemeBuilder.semantic(role))


## Compact facts row (deadline, quality target, tags).
func set_chips(chips: Array) -> void:
	var row: HFlowContainer = $Margin/VBox/ChipRow
	_clear(row)
	row.visible = not chips.is_empty()
	for chip in chips:
		row.add_child(_build_chip(chip))


## PAY / RISK / TOKENS dot strips for fast comparison between offers.
func set_ratings(ratings: Array) -> void:
	var box: VBoxContainer = $Margin/VBox/RatingsBox
	_clear(box)
	box.visible = not ratings.is_empty()
	for rating in ratings:
		box.add_child(RatingStrip.create(
			str(rating.get("label", "")),
			int(rating.get("filled", 0)),
			str(rating.get("role", "neutral"))
		))


## Small colored tags above the title (e.g. URGENT, sector name).
func set_badges(badges: Array) -> void:
	var badge_row: HFlowContainer = $Margin/VBox/BadgeRow
	_clear(badge_row)
	badge_row.visible = not badges.is_empty()
	for badge in badges:
		badge_row.add_child(_build_chip(badge))


## Risks and blockers as high-contrast chips rather than paragraphs.
func set_warnings(warnings: Array) -> void:
	var warnings_box: HFlowContainer = $Margin/VBox/WarningsBox
	_clear(warnings_box)
	warnings_box.visible = not warnings.is_empty()
	for warning in warnings:
		var text: String = str(warning.get("text", "")) if warning is Dictionary else str(warning)
		var role: String = str(warning.get("role", "warning")) if warning is Dictionary else "warning"
		warnings_box.add_child(UiChip.create_warning(text, role))


func set_disabled(disabled: bool) -> void:
	_disabled = disabled
	# Unpowered rather than washed out: the card keeps its contrast, it just stops
	# being lit.
	modulate = Color(0.66, 0.66, 0.66, 1.0) if disabled else Color.WHITE
	var action_button: GameButton = $Margin/VBox/ActionButton
	action_button.disabled = disabled


## Press feedback: the card compresses under the finger before the screen moves.
func play_press_feedback() -> void:
	pivot_offset = size / 2.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2(0.99, 0.985), 0.07).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.09).set_ease(Tween.EASE_IN)


func _build_chip(spec: Variant) -> Control:
	if spec is Dictionary:
		var text: String = str(spec.get("text", ""))
		var icon: Texture2D = spec.get("icon", null)
		var filled: bool = bool(spec.get("filled", false))
		if spec.has("accent"):
			return UiChip.create_colored(text, spec["accent"], icon, filled)
		return UiChip.create(text, str(spec.get("role", "neutral")), icon, filled)
	return UiChip.create(str(spec), "neutral")


func _accent_color(accent_key: String) -> Color:
	if accent_key in ["common", "rare", "epic", "legendary"]:
		return AssetCatalog.rarity_color(accent_key)
	return UiThemeBuilder.color(accent_key)


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


## Acts on release rather than on touch-down, so dragging the list past a card
## scrolls instead of opening it.
func _on_gui_input(event: InputEvent) -> void:
	if _disabled or _is_over_action_button(event):
		_tap.cancel()
		return
	if not _tap.feed(event):
		return
	if body_pressed.get_connections().is_empty():
		pressed.emit()
	else:
		body_pressed.emit()


## The action button is set to MOUSE_FILTER_PASS so a drag started on it can
## still scroll the list behind it; that means its taps also reach this
## handler and would otherwise double-fire as a card-body tap too.
func _is_over_action_button(event: InputEvent) -> bool:
	var action_button: Button = $Margin/VBox/ActionButton
	if not action_button.visible:
		return false
	var local_position: Vector2
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		local_position = event.position
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		local_position = event.position
	else:
		return false
	var global_point: Vector2 = global_position + local_position
	return action_button.get_global_rect().has_point(global_point)
