class_name UiChip
extends PanelContainer

## Compact high-contrast chip: optional icon plus short uppercase text.
##
## Replaces sentence-long warnings and stat lines with something scannable
## ("COOLING 15/30", "LOW RISK", "INSUFFICIENT CASH"). Built in code so any
## screen can drop one into a row without another scene file.

## Widest a chip may ask to be. Chips are laid out by `HFlowContainer`, which hands
## each child its minimum size, and a Label that does not wrap makes that minimum
## the full length of its text. A caller that passes a whole sentence therefore
## used to stretch the card, the screen and the viewport with it, so past this
## width the text wraps instead of demanding more room. The content column is 720
## design units and a chip sits inside a card inside a screen margin, so this has
## to stay clear of that with the nesting allowed for.
const MAX_TEXT_WIDTH := 500.0


static func create(text: String, role: String = "neutral", icon: Texture2D = null, filled: bool = false) -> UiChip:
	var chip := UiChip.new()
	chip._build(text, UiThemeBuilder.semantic(role), icon, filled)
	return chip


static func create_colored(text: String, accent: Color, icon: Texture2D = null, filled: bool = false) -> UiChip:
	var chip := UiChip.new()
	chip._build(text, accent, icon, filled)
	return chip


## Warning chip with the kit's warning glyph, for risks the player must notice.
static func create_warning(text: String, role: String = "warning") -> UiChip:
	return create(text, role, AssetCatalog.status_icon("warning"), true)


func _build(text: String, accent: Color, icon: Texture2D, filled: bool) -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiThemeBuilder.chip_style(accent, filled))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiThemeBuilder.SPACE_XS + 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	if icon != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon
		icon_rect.custom_minimum_size = Vector2(24, 24)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.modulate = accent
		row.add_child(icon_rect)
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", UiThemeBuilder.FONT_SMALL)
	label.add_theme_color_override("font_color", accent.lightened(0.4))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Only long chips wrap: a short one keeps sizing to its text exactly, which is
	# what makes a row of them read as tags rather than as boxes on a grid.
	if _text_width(label.text) > MAX_TEXT_WIDTH:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = MAX_TEXT_WIDTH
	row.add_child(label)


static func _text_width(text: String) -> float:
	var font: Font = UiThemeBuilder.body_font()
	if font == null:
		font = ThemeDB.fallback_font
	return font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiThemeBuilder.FONT_SMALL
	).x
