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
var _tap: TapGesture = TapGesture.new()

# Resolved by `@onready`, but every caller in the project configures a card
# (`setup`, `set_chips`, ...) before `add_child`, so `_ensure_nodes()` resolves
# them on first use when the card is not yet in the tree.
@onready var _box: VBoxContainer = $Margin/VBox
@onready var _title_label: Label = $Margin/VBox/HeaderRow/TitleLabel
@onready var _headline_label: Label = $Margin/VBox/HeaderRow/HeadlineLabel
@onready var _icon_rect: TextureRect = $Margin/VBox/HeaderRow/Icon
@onready var _kicker_label: Label = $Margin/VBox/KickerLabel
@onready var _body_label: Label = $Margin/VBox/BodyLabel
@onready var _footer_label: Label = $Margin/VBox/FooterLabel
@onready var _action_button: GameButton = $Margin/VBox/ActionButton
@onready var _chip_row: HFlowContainer = $Margin/VBox/ChipRow
@onready var _ratings_box: VBoxContainer = $Margin/VBox/RatingsBox
@onready var _badge_row: HFlowContainer = $Margin/VBox/BadgeRow
@onready var _warnings_box: HFlowContainer = $Margin/VBox/WarningsBox


func setup(
	title: String,
	body: String,
	footer: String = "",
	action_text: String = "",
	icon: Texture2D = null,
	accent_key: String = ""
) -> void:
	_ensure_nodes()
	_title_label.text = title
	_body_label.text = body
	_body_label.visible = body != ""
	_footer_label.text = footer
	_footer_label.visible = footer != ""
	if action_text != "":
		_action_button.set_lines(action_text.to_upper())
		_action_button.visible = true
	else:
		_action_button.visible = false

	if icon != null:
		_icon_rect.texture = icon
		_icon_rect.visible = true
	else:
		_icon_rect.visible = false

	add_theme_stylebox_override("panel", UiThemeBuilder.card_style(accent_key))
	if accent_key != "":
		var accent: Color = _accent_color(accent_key)
		_footer_label.add_theme_color_override("font_color", accent)
		_light_rail(accent)

	if not _button_connected:
		_action_button.pressed.connect(func() -> void: if not _disabled: pressed.emit())
		_button_connected = true
	if not _panel_connected:
		gui_input.connect(_on_gui_input)
		_panel_connected = true


## Glyph and tint for the call to action, so BUY, ACCEPT and KEEP THIS read as
## different kinds of commitment rather than one generic confirm.
func set_action_style(
	icon_key: String, accent_key: String = "action", variation: String = ""
) -> void:
	_ensure_nodes()
	_action_button.icon_key = icon_key
	_action_button.accent_key = accent_key
	if variation != "":
		_action_button.theme_type_variation = StringName(variation)


## Keeps calls to action on a shared baseline when cards in the same row have
## different amounts of copy. This is opt-in because most cards should remain
## only as tall as their content.
func set_action_pinned(pinned: bool = true) -> void:
	_ensure_nodes()
	var spacer: Control = _box.get_node_or_null("ActionSpacer") as Control
	if pinned and spacer == null:
		spacer = Control.new()
		spacer.name = "ActionSpacer"
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_box.add_child(spacer)
		_box.move_child(spacer, _action_button.get_index())
	elif not pinned and spacer != null:
		spacer.queue_free()


## Card faces are summaries; the screen can cap prose when a detail sheet is
## available behind a tap.
func set_body_max_lines(max_lines: int) -> void:
	_ensure_nodes()
	_body_label.max_lines_visible = maxi(0, max_lines)
	_body_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


## Colour identity for a data-driven category (job sector, upgrade group).
func set_accent(accent: Color) -> void:
	_ensure_nodes()
	add_theme_stylebox_override("panel", UiThemeBuilder.card_style_accent(accent))
	_icon_rect.modulate = accent.lightened(0.15)
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
	_ensure_nodes()
	_kicker_label.text = text.to_upper()
	_kicker_label.visible = text != ""
	if accent != Color.TRANSPARENT:
		_kicker_label.add_theme_color_override("font_color", accent)


## The one number the decision turns on, shown large beside the title.
func set_headline(text: String, role: String = "money") -> void:
	_ensure_nodes()
	_headline_label.text = text
	_headline_label.visible = text != ""
	_headline_label.add_theme_color_override("font_color", UiThemeBuilder.semantic(role))


## Compact facts row (deadline, quality target, tags).
func set_chips(chips: Array) -> void:
	_ensure_nodes()
	_clear(_chip_row)
	_chip_row.visible = not chips.is_empty()
	for chip in chips:
		_chip_row.add_child(_build_chip(chip))


## PAY / RISK / TOKENS dot strips for fast comparison between offers.
func set_ratings(ratings: Array) -> void:
	_ensure_nodes()
	_clear(_ratings_box)
	_ratings_box.visible = not ratings.is_empty()
	for rating in ratings:
		_ratings_box.add_child(RatingStrip.create(
			str(rating.get("label", "")),
			int(rating.get("filled", 0)),
			str(rating.get("role", "neutral"))
		))


## Small colored tags above the title (e.g. URGENT, sector name).
func set_badges(badges: Array) -> void:
	_ensure_nodes()
	_clear(_badge_row)
	_badge_row.visible = not badges.is_empty()
	for badge in badges:
		_badge_row.add_child(_build_chip(badge))


## Risks and blockers as high-contrast chips rather than paragraphs.
func set_warnings(warnings: Array) -> void:
	_ensure_nodes()
	_clear(_warnings_box)
	_warnings_box.visible = not warnings.is_empty()
	for warning in warnings:
		var text: String = str(warning.get("text", "")) if warning is Dictionary else str(warning)
		var role: String = str(warning.get("role", "warning")) if warning is Dictionary else "warning"
		_warnings_box.add_child(UiChip.create_warning(text, role))


func set_disabled(disabled: bool) -> void:
	_ensure_nodes()
	_disabled = disabled
	# Unpowered rather than washed out: the card keeps its contrast, it just stops
	# being lit.
	modulate = Color(0.66, 0.66, 0.66, 1.0) if disabled else Color.WHITE
	_action_button.disabled = disabled


## Press feedback: the card compresses under the finger before the screen moves.
func play_press_feedback() -> void:
	pivot_offset = size / 2.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2(0.99, 0.985), 0.07).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.09).set_ease(Tween.EASE_IN)


## `@onready` only fires once the card enters the tree, but callers configure
## cards before `add_child`, so resolve the scene nodes on demand until then.
func _ensure_nodes() -> void:
	if _box != null:
		return
	_box = $Margin/VBox
	_title_label = $Margin/VBox/HeaderRow/TitleLabel
	_headline_label = $Margin/VBox/HeaderRow/HeadlineLabel
	_icon_rect = $Margin/VBox/HeaderRow/Icon
	_kicker_label = $Margin/VBox/KickerLabel
	_body_label = $Margin/VBox/BodyLabel
	_footer_label = $Margin/VBox/FooterLabel
	_action_button = $Margin/VBox/ActionButton
	_chip_row = $Margin/VBox/ChipRow
	_ratings_box = $Margin/VBox/RatingsBox
	_badge_row = $Margin/VBox/BadgeRow
	_warnings_box = $Margin/VBox/WarningsBox


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
	_ensure_nodes()
	if not _action_button.visible:
		return false
	var local_position: Vector2
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		local_position = event.position
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		local_position = event.position
	else:
		return false
	var global_point: Vector2 = global_position + local_position
	return _action_button.get_global_rect().has_point(global_point)
