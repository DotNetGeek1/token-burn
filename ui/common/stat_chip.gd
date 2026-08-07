class_name StatChip
extends HBoxContainer

## Compact icon + value readout. The caption is hidden unless a title is
## passed, so the persistent HUD stays a single tight row and only the home
## screen / onboarding spends space on labels.

var _tap_connected: bool = false


func setup(stat_key: String, text: String, title: String = "") -> void:
	_set_icon(stat_key)
	_set_title(title)
	($Text/Value as NumberLabel).set_literal(text)


## Animated variant: value counts toward the target and can be skipped by
## tapping the chip (mobile UX rule: let players skip number animations).
func setup_value(stat_key: String, value: float, format: String = "plain", prefix: String = "", title: String = "", animate: bool = true) -> void:
	_set_icon(stat_key)
	_set_title(title)
	var number: NumberLabel = $Text/Value
	number.prefix = prefix
	number.use_cash_format = format == "cash"
	number.use_token_format = format == "tokens"
	number.set_value(value, animate)
	if not _tap_connected:
		_tap_connected = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		gui_input.connect(_on_gui_input)


## The HUD row is a fixed width and the numbers in it are not, so the shell can
## ask the chips to read a size smaller rather than let a late-game figure push
## the whole layout off the edges of the screen.
func set_value_font_size(font_size: int) -> void:
	($Text/Value as Label).add_theme_font_size_override("font_size", font_size)


## How wide this chip would be with its value set at `font_size`, measured from
## the font rather than from the current layout. The shell needs the answer
## before it commits to a size, and a container's minimum size only catches up
## a frame after the text changes — long enough to oscillate.
func width_at_font_size(font_size: int) -> float:
	var value: Label = $Text/Value
	var font: Font = value.get_theme_font("font")
	var text_width: float = 0.0
	if font != null:
		text_width = font.get_string_size(value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var icon: TextureRect = $Icon
	var icon_width: float = icon.custom_minimum_size.x + get_theme_constant("separation") if icon.visible else 0.0
	return icon_width + text_width


## Lets money read green while compute and reputation stay neutral.
func set_value_color(value_color: Color) -> void:
	($Text/Value as Label).add_theme_color_override("font_color", value_color)


## Brief flash used when a value changes because of a player action.
func pulse(flash_color: Color) -> void:
	var value: Label = $Text/Value
	value.pivot_offset = value.size / 2.0
	var tween: Tween = create_tween()
	tween.tween_property(value, "scale", Vector2(1.18, 1.18), 0.08)
	tween.tween_property(value, "scale", Vector2.ONE, 0.18).set_ease(Tween.EASE_OUT)
	var icon: TextureRect = $Icon
	if icon.visible:
		icon.modulate = flash_color
		tween.parallel().tween_property(icon, "modulate", Color.WHITE, 0.35)


func _on_gui_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if tapped:
		($Text/Value as NumberLabel).skip_animation()


func _set_title(title: String) -> void:
	var label: Label = $Text/Title
	label.text = title.to_upper()
	label.visible = title != ""


func _set_icon(stat_key: String) -> void:
	var icon: TextureRect = $Icon
	var tex: Texture2D = AssetCatalog.stat_icon(stat_key)
	icon.texture = tex
	icon.visible = tex != null
