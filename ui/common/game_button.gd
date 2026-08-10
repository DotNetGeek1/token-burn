class_name GameButton
extends Button

## A chunky action button: icon, shouted headline, and an optional consequence
## line underneath.
##
## The board used to pack costs into the button label with an embedded newline,
## which gave the heat and cash figures the same weight as the verb. Here the
## headline stays in the display face while the consequence line sits smaller
## and dimmer, so "BURN 4.2 BT" reads first and "Heat +18 · Cost $340" second.
##
## Content lives in child controls rather than the built-in text so the two
## lines can be styled independently. That means the stylebox content margins no
## longer move the label on press, so the press dip is applied here instead.

const PRESS_DIP := 1.0
const ICON_SIZE := 24.0
## Function-row proportions: enough to read a legend, small enough that the keys
## which matter keep their rank on the deck. The height still bottoms out at the
## ordinary thumb target — ranking keys by size must not produce a key that is
## awkward to hit.
const COMPACT_ICON_SIZE := 22.0
## Widest a button may demand from its row on the strength of its own text. The
## side panel is narrower than any label is long, so beyond this the text yields.
## Title-screen keys opt out via `allow_wide`.
const MAX_AUTO_WIDTH := 176.0

## Title and other full-width menus skip the side-panel width cap.
@export var allow_wide: bool = false

## Palette or semantic key used to tint the icon and the consequence line.
@export var accent_key: String = "action":
	set(value):
		accent_key = value
		_apply_accent()

@export var headline: String = "BUTTON":
	set(value):
		headline = value
		if _headline_label != null:
			_headline_label.text = value
			_sync_minimum_size()

@export_multiline var sub_text: String = "":
	set(value):
		sub_text = value
		_apply_sub_text()

@export var button_icon: Texture2D = null:
	set(value):
		button_icon = value
		_apply_icon()

## Art-kit key resolved through AssetCatalog, so scenes can name a glyph
## ("heat", "cash", "warning") instead of carrying an ext_resource for it.
@export var icon_key: String = "":
	set(value):
		icon_key = value
		if value != "":
			button_icon = _resolve_icon(value)

## Cue played on press. Blank for buttons that play their own, louder cue.
@export var sound_cue: String = "tap"

## Function-row key: a smaller legend, a smaller glyph and tighter padding, so a
## deck can rank its keys by size. A button's accent is baked into its stylebox,
## so ranking by size through the theme would mean a second variation for every
## accent; one flag on the button is cheaper and keeps the palette intact.
@export var compact: bool = false:
	set(value):
		compact = value
		_apply_compact()

var _rail: ColorRect = null
var _content: MarginContainer = null
var _row: HBoxContainer = null
var _icon_rect: TextureRect = null
var _headline_label: Label = null
var _sub_label: Label = null
## Height the scene asked for, kept so growing content can raise the button
## without a later shrink pinning it to whatever it grew to.
var _authored_min_height: float = 0.0
var _authored_min_width: float = 0.0


func _ready() -> void:
	# The built-in label and icon would draw underneath the child controls.
	text = ""
	icon = null
	# A scene that named its own height meant it; only unspecified buttons get
	# pushed up to the full action target, so card CTAs stay list-sized.
	var default_height: int = (
		UiThemeBuilder.TOUCH_TARGET if compact else UiThemeBuilder.ACTION_TARGET
	)
	_authored_min_height = (
		custom_minimum_size.y if custom_minimum_size.y > 0.0 else float(default_height)
	)
	_authored_min_width = custom_minimum_size.x
	_build()
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	pressed.connect(_on_pressed)


func _build() -> void:
	if _content != null:
		return
	# The one industrial motif: an illuminated rail down the left edge. It is a
	# node rather than part of the stylebox because a stylebox has a single border
	# colour, so a lit left border would light all four sides with it.
	_rail = UiThemeBuilder.build_accent_rail(UiThemeBuilder.semantic(accent_key))
	add_child(_rail, false, Node.INTERNAL_MODE_FRONT)

	_content = MarginContainer.new()
	_content.name = "Content"
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content, false, Node.INTERNAL_MODE_FRONT)

	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_row)

	_icon_rect = TextureRect.new()
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon_rect.visible = false
	_row.add_child(_icon_rect)

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The legends clip rather than claim width, so the stack has to take whatever
	# the keycap has left over after the icon or they would collapse to nothing.
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 0)
	_row.add_child(stack)

	_headline_label = Label.new()
	_headline_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A keycap is sized by the layout, not by its legend. Without this the label
	# reports its full single-line width as a minimum, a row of keys sums those
	# minimums past the viewport, and the whole screen is clipped at both edges.
	# Wrapping is not the answer either: in a row that is already at its minimum
	# it collapses the legend to one letter per line.
	_headline_label.clip_text = true
	_headline_label.text = headline
	_headline_label.add_theme_color_override("font_color", Color(UiThemeBuilder.TEXT_PRIMARY))
	_headline_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_headline_label.add_theme_constant_override("outline_size", 2)
	var header: Font = UiThemeBuilder.header_font()
	if header != null:
		_headline_label.add_theme_font_override("font", header)
	stack.add_child(_headline_label)

	_sub_label = Label.new()
	_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_sub_label.clip_text = true
	_sub_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_sub_label.add_theme_constant_override("outline_size", 2)
	_sub_label.visible = false
	stack.add_child(_sub_label)

	_apply_compact()
	_apply_icon()
	_apply_sub_text()
	_apply_accent()
	_sync_minimum_size()


## Everything that differs between a full keycap and a function-row one, in one
## place so the two sizes cannot drift apart.
func _apply_compact() -> void:
	if _content == null:
		return
	var glyph: float = COMPACT_ICON_SIZE if compact else ICON_SIZE
	_icon_rect.custom_minimum_size = Vector2(glyph, glyph)
	_headline_label.add_theme_font_size_override(
		"font_size",
		UiThemeBuilder.header_size(
			UiThemeBuilder.FONT_SMALL if compact else UiThemeBuilder.FONT_BODY
		)
	)
	_sub_label.add_theme_font_size_override(
		"font_size", UiThemeBuilder.FONT_SMALL - (4 if compact else 2)
	)
	# A function-row key is too small to hang a left-aligned legend off, so it
	# keeps its centred label; everything at menu size reads as a control module
	# with the content stacked against the accent rail.
	var align: int = (
		HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
	)
	_headline_label.horizontal_alignment = align
	_sub_label.horizontal_alignment = align
	_row.alignment = (
		BoxContainer.ALIGNMENT_CENTER if compact else BoxContainer.ALIGNMENT_BEGIN
	)
	var side: int = (
		UiThemeBuilder.SPACE_SM if compact else UiThemeBuilder.BUTTON_PAD_H
	)
	var top: int = 4 if compact else UiThemeBuilder.BUTTON_PAD_V
	_content.add_theme_constant_override("margin_left", side)
	_content.add_theme_constant_override("margin_right", side)
	_content.add_theme_constant_override("margin_top", top)
	_content.add_theme_constant_override("margin_bottom", top)
	_row.add_theme_constant_override(
		"separation", UiThemeBuilder.SPACE_SM if compact else 10
	)
	_sync_minimum_size()


## Sets both lines at once, which is how callers usually refresh a button.
func set_lines(new_headline: String, new_sub_text: String = "") -> void:
	headline = new_headline
	sub_text = new_sub_text


static func _resolve_icon(key: String) -> Texture2D:
	for lookup: Callable in [
		AssetCatalog.stat_icon,
		AssetCatalog.status_icon,
		AssetCatalog.category_icon,
		AssetCatalog.nav_icon,
		AssetCatalog.perk_icon,
	]:
		var texture: Texture2D = lookup.call(key)
		if texture != null:
			return texture
	return null


func _apply_icon() -> void:
	if _icon_rect == null:
		return
	_icon_rect.texture = button_icon
	_icon_rect.visible = button_icon != null


func _apply_sub_text() -> void:
	if _sub_label == null:
		return
	_sub_label.text = sub_text
	_sub_label.visible = sub_text.strip_edges() != ""
	_sync_minimum_size()


func _apply_accent() -> void:
	if _icon_rect == null:
		return
	var accent: Color = UiThemeBuilder.semantic(accent_key)
	if _rail != null:
		_rail.color = accent
	_icon_rect.modulate = accent.lightened(0.35)
	# The icon and the rail carry the accent; the consequence line stays
	# secondary text so a screen of buttons does not read as a paint chart.
	_sub_label.add_theme_color_override(
		"font_color", Color(UiThemeBuilder.TEXT_SECONDARY)
	)


## `Button` computes its minimum size in C++ from its own text and icon, both of
## which are empty here, and never consults the script's `_get_minimum_size`. So
## the size the child content needs is pushed into `custom_minimum_size` instead.
func _sync_minimum_size() -> void:
	if _content == null:
		return
	var content: Vector2 = _content.get_combined_minimum_size()
	# Capped so a long headline asks for room it cannot have in the side panel;
	# the labels clip instead of dragging the whole row past the panel edge.
	var width: float = maxf(_authored_min_width, content.x)
	if not allow_wide:
		width = minf(width, MAX_AUTO_WIDTH)
	custom_minimum_size = Vector2(width, maxf(_authored_min_height, content.y))


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _content != null:
		_sync_minimum_size()


func _on_button_down() -> void:
	if _content != null:
		_content.position.y = PRESS_DIP


func _on_button_up() -> void:
	if _content == null:
		return
	# Snaps back inside the 90ms release window the style guide asks for; the
	# longer spring read as a floaty app animation rather than a switch.
	_content.position.y = PRESS_DIP
	var tween: Tween = create_tween()
	tween.tween_property(_content, "position:y", 0.0, 0.09).set_ease(Tween.EASE_OUT)


func _on_pressed() -> void:
	if sound_cue != "":
		UiSound.play(sound_cue)


## Godot dims the built-in label for a disabled button, but our content lives in
## child controls. Redraw is the one hook that fires when `disabled` flips.
func _draw() -> void:
	if _content == null:
		return
	# Unpowered rather than transparent: dropping the alpha far enough to read as
	# disabled also dropped the legend below the contrast the text needs.
	_content.modulate = Color(0.62, 0.62, 0.62) if disabled else Color.WHITE
