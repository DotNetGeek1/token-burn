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

const PRESS_DIP := 5.0
const ICON_SIZE := 56.0
## Function-row proportions: enough to read a legend, small enough that the keys
## which matter keep their rank on the deck. The height still bottoms out at the
## ordinary thumb target — ranking keys by size must not produce a key that is
## awkward to hit, and the design viewport is 1080 wide, so these numbers land at
## roughly half their value on a phone.
const COMPACT_ICON_SIZE := 38.0

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

var _content: MarginContainer = null
var _row: HBoxContainer = null
var _icon_rect: TextureRect = null
var _headline_label: Label = null
var _sub_label: Label = null
## Height the scene asked for, kept so growing content can raise the button
## without a later shrink pinning it to whatever it grew to.
var _authored_min_height: float = 0.0


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
	_build()
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	pressed.connect(_on_pressed)


func _build() -> void:
	if _content != null:
		return
	_content = MarginContainer.new()
	_content.name = "Content"
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content, false, Node.INTERNAL_MODE_FRONT)

	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
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
	_headline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# A keycap is sized by the layout, not by its legend. Without this the label
	# reports its full single-line width as a minimum, a row of keys sums those
	# minimums past the viewport, and the whole screen is clipped at both edges.
	# Wrapping is not the answer either: in a row that is already at its minimum
	# it collapses the legend to one letter per line.
	_headline_label.clip_text = true
	_headline_label.text = headline
	_headline_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_headline_label.add_theme_constant_override("outline_size", 6)
	var header: Font = UiThemeBuilder.header_font()
	if header != null:
		_headline_label.add_theme_font_override("font", header)
	stack.add_child(_headline_label)

	_sub_label = Label.new()
	_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_sub_label.clip_text = true
	_sub_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_sub_label.add_theme_constant_override("outline_size", 5)
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
	var side: int = UiThemeBuilder.SPACE_SM if compact else UiThemeBuilder.SPACE_MD
	var top: int = 4 if compact else 10
	_content.add_theme_constant_override("margin_left", side)
	_content.add_theme_constant_override("margin_right", side)
	_content.add_theme_constant_override("margin_top", top)
	_content.add_theme_constant_override("margin_bottom", top + UiThemeBuilder.BUTTON_BEVEL)
	_row.add_theme_constant_override(
		"separation", UiThemeBuilder.SPACE_SM if compact else UiThemeBuilder.SPACE_MD
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
	_icon_rect.modulate = accent.lightened(0.25)
	_sub_label.add_theme_color_override("font_color", accent.lightened(0.4))


## `Button` computes its minimum size in C++ from its own text and icon, both of
## which are empty here, and never consults the script's `_get_minimum_size`. So
## the size the child content needs is pushed into `custom_minimum_size` instead.
func _sync_minimum_size() -> void:
	if _content == null:
		return
	var content: Vector2 = _content.get_combined_minimum_size()
	custom_minimum_size = Vector2(
		maxf(custom_minimum_size.x, content.x),
		maxf(_authored_min_height, content.y)
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _content != null:
		_sync_minimum_size()


func _on_button_down() -> void:
	if _content != null:
		_content.position.y = PRESS_DIP


func _on_button_up() -> void:
	if _content == null:
		return
	# Springs back rather than snapping, which is what makes the cap feel like it
	# has travel.
	_content.position.y = PRESS_DIP
	var tween: Tween = create_tween()
	tween.tween_property(_content, "position:y", 0.0, 0.12).set_ease(Tween.EASE_OUT)


func _on_pressed() -> void:
	if sound_cue != "":
		UiSound.play(sound_cue)
	# A short overshoot on the whole cap, so a tap registers even when the
	# consequence of it lands a frame later.
	pivot_offset = size * 0.5
	scale = Vector2(0.97, 0.97)
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)


## Godot dims the built-in label for a disabled button, but our content lives in
## child controls. Redraw is the one hook that fires when `disabled` flips.
func _draw() -> void:
	if _content == null:
		return
	_content.modulate.a = 0.4 if disabled else 1.0
