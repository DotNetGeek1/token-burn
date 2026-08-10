class_name TitleMenuTile
extends Button

## A title-menu control module: accent-lit icon on the left, headline and a
## secondary line stacked against it. Same flat module surface every other button
## in the game is cut from, so the menu reads as one bank of hardware controls.

@export var accent_key: String = "neutral":
	set(value):
		accent_key = value
		_apply_accent()

@export var headline: String = "TITLE":
	set(value):
		headline = value
		if _headline != null:
			_headline.text = value

@export var sub_text: String = "":
	set(value):
		sub_text = value
		_apply_sub()

@export var icon_key: String = "":
	set(value):
		icon_key = value
		_apply_icon()

var _rail: ColorRect = null
var _icon: TextureRect = null
var _headline: Label = null
var _sub: Label = null


func _ready() -> void:
	text = ""
	icon = null
	_build()
	_apply_icon()
	_apply_sub()
	_apply_accent()
	_style_bezel()
	pressed.connect(func(): UiSound.play("tap"))


func set_lines(new_headline: String, new_sub: String = "") -> void:
	headline = new_headline
	sub_text = new_sub


func _build() -> void:
	_rail = UiThemeBuilder.build_accent_rail(UiThemeBuilder.semantic(accent_key))
	add_child(_rail)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", UiThemeBuilder.BUTTON_PAD_H)
	margin.add_theme_constant_override("margin_right", UiThemeBuilder.SPACE_MD)
	margin.add_theme_constant_override("margin_top", UiThemeBuilder.BUTTON_PAD_V)
	margin.add_theme_constant_override("margin_bottom", UiThemeBuilder.BUTTON_PAD_V)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(26, 26)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)

	_headline = Label.new()
	_headline.clip_text = true
	_headline.theme_type_variation = &"SectionLabel"
	_headline.add_theme_font_size_override("font_size", UiThemeBuilder.FONT_SMALL)
	_headline.add_theme_color_override("font_color", Color(UiThemeBuilder.TEXT_PRIMARY))
	_headline.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_headline.add_theme_constant_override("outline_size", 2)
	_headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_headline)

	_sub = Label.new()
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.theme_type_variation = &"MutedLabel"
	_sub.add_theme_font_size_override("font_size", UiThemeBuilder.FONT_SMALL - 3)
	_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_sub.add_theme_constant_override("outline_size", 2)
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_sub)

	_headline.text = headline


func _apply_icon() -> void:
	if _icon == null:
		return
	var texture: Texture2D = null
	if icon_key != "":
		for lookup: Callable in [
			AssetCatalog.stat_icon,
			AssetCatalog.status_icon,
			AssetCatalog.category_icon,
			AssetCatalog.nav_icon,
			AssetCatalog.perk_icon,
		]:
			texture = lookup.call(icon_key)
			if texture != null:
				break
	_icon.texture = texture
	_icon.visible = texture != null


func _apply_sub() -> void:
	if _sub == null:
		return
	_sub.text = sub_text
	_sub.visible = sub_text.strip_edges() != ""


func _apply_accent() -> void:
	if _icon == null:
		return
	var accent: Color = UiThemeBuilder.semantic(accent_key)
	if _rail != null:
		_rail.color = accent
	_icon.modulate = accent.lightened(0.35)
	_sub.add_theme_color_override("font_color", Color(UiThemeBuilder.TEXT_SECONDARY))


func _style_bezel() -> void:
	var accent: Color = UiThemeBuilder.semantic(accent_key)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, UiThemeBuilder.module_style(accent, state, false))


func _draw() -> void:
	modulate = Color(0.62, 0.62, 0.62) if disabled else Color.WHITE
