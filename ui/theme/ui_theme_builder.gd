class_name UiThemeBuilder
extends RefCounted

## Builds the Token Burn UI theme from the presentation asset palette.
##
## Design tokens (single source of truth for the UI):
## - Colors come from presentation/asset_catalog.json ("palette").
## - Type scale: FONT_SMALL / FONT_BODY / FONT_TITLE / FONT_DISPLAY.
## - Spacing scale: SPACE_XS / SPACE_SM / SPACE_MD / SPACE_LG.
## Screens should use these tokens (or theme type variations) instead of
## hardcoding colors, font sizes, or margins.
##
## Surfaces come in three tiers so the screen stops reading as one wall of
## identical rounded rectangles:
## - panel_style: large translucent game panels.
## - card_style: interactive cards, brighter edge and a clipped corner.
## - info_strip_style: flat compact strips with no container of their own.

# Type scale, in 720-wide design units. A handset maps those 720 units onto a
# ~411dp panel, so one design unit is about 0.57sp: multiply by 0.57 to sanity
# check a size against Android's 12sp readability floor. Keep them generous
# ("large numerical typography" per the UX doc).
const FONT_SMALL := 22
## Secondary prose (subtitles, sub-lines, footers). It sits between SMALL and
## BODY because SMALL was tuned for uppercase kickers, and reusing it for whole
## sentences left the explanatory half of the UI harder to read than the numbers
## it was explaining.
const FONT_MUTED := 25
const FONT_BODY := 26
const FONT_TITLE := 36
const FONT_DISPLAY := 48
const FONT_STAT := 40

# Spacing scale
const SPACE_XS := 4
const SPACE_SM := 8
const SPACE_MD := 16
const SPACE_LG := 24

# Maximum width of the main content column. Matches the 720-wide portrait
# design; on wider windows (desktop/landscape) the column is centered instead
# of stretching edge to edge.
const CONTENT_MAX_WIDTH := 720.0

const CORNER_RADIUS := 12
# 88 design units is ~50dp on a handset, just clear of the 48dp minimum.
const TOUCH_TARGET := 88
# Game buttons are the primary way the player acts, so they get more than the
# bare minimum thumb target.
const ACTION_TARGET := 104

# Bebas Neue is condensed and caps-only, so it needs more points than Inter to
# read at the same optical size.
const HEADER_FONT_PATH := "res://presentation/fonts/BebasNeue-Regular.ttf"
const BODY_FONT_PATH := "res://presentation/fonts/Inter-Variable.ttf"
const MONO_FONT_PATH := "res://presentation/fonts/ShareTechMono-Regular.ttf"
const HEADER_SCALE := 1.2

# Depth of the bottom bevel that makes buttons read as physical keycaps.
const BUTTON_BEVEL := 8

## Colour semantics. Every screen should ask for a role rather than a colour so
## green keeps meaning money and cyan keeps meaning "this is the thing to tap".
const SEMANTIC_ROLES := {
	"money": "green",
	"success": "green",
	"action": "blue",
	"compute": "blue",
	"heat": "orange",
	"warning": "orange",
	"danger": "red",
	"failure": "red",
	"perk": "purple",
	"energy": "yellow",
	"neutral": "grey",
}


static var _header_font: Font = null
static var _body_font: Font = null
static var _body_bold_font: Font = null
static var _mono_font: Font = null
static var _fonts_loaded: bool = false


static func apply(root: Control) -> void:
	root.theme = build()


static func color(color_name: String) -> Color:
	return AssetCatalog.palette_color(color_name)


## Condensed display face for headlines, stat numbers and button labels.
static func header_font() -> Font:
	_ensure_fonts()
	return _header_font


## Body face for prose, tooltips and dense readouts.
static func body_font() -> Font:
	_ensure_fonts()
	return _body_font


static func body_bold_font() -> Font:
	_ensure_fonts()
	return _body_bold_font


## Fixed pitch face for the rig terminal and any other readout that has to line
## its columns up.
static func mono_font() -> Font:
	_ensure_fonts()
	return _mono_font


## Header type sits at a different optical size to body type, so sizes asked
## for in the body scale get nudged up when rendered in the display face.
static func header_size(size: int) -> int:
	return int(round(float(size) * HEADER_SCALE))


static func _ensure_fonts() -> void:
	if _fonts_loaded:
		return
	_fonts_loaded = true
	_header_font = _load_font(HEADER_FONT_PATH)
	_body_font = _load_font(BODY_FONT_PATH)
	_mono_font = _load_font(MONO_FONT_PATH)
	if _body_font != null:
		# Inter ships as a variable font; Godot renders its default instance, so
		# emphasis comes from a synthetic weight rather than a second file.
		var bold := FontVariation.new()
		bold.base_font = _body_font
		bold.variation_embolden = 0.36
		_body_bold_font = bold


static func _load_font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		push_warning("UiThemeBuilder: missing font %s" % path)
		return null
	var loaded: Variant = load(path)
	return loaded if loaded is Font else null


## Colour for a meaning ("money", "action", "heat"...) instead of a hue name.
static func semantic(role: String) -> Color:
	return color(str(SEMANTIC_ROLES.get(role, role)))


static func build() -> Theme:
	var theme: Theme = Theme.new()
	var panel: Color = color("bg_panel")
	var stroke: Color = color("stroke_dim")
	var green: Color = color("green")
	var blue: Color = color("blue")
	var white: Color = color("white")
	var grey: Color = color("grey")
	var red: Color = color("red")
	var orange: Color = color("orange")

	theme.set_color("font_color", "Label", white)
	theme.set_color("font_color", "Button", white)
	theme.set_font_size("font_size", "Label", FONT_BODY)
	theme.set_font_size("font_size", "Button", header_size(FONT_BODY))

	_ensure_fonts()
	if _body_font != null:
		theme.set_font("font", "Label", _body_font)
		theme.set_font("font", "RichTextLabel", _body_font)
		theme.set_font("normal_font", "RichTextLabel", _body_font)
		theme.set_font("font", "LineEdit", _body_font)
	if _body_bold_font != null:
		theme.set_font("bold_font", "RichTextLabel", _body_bold_font)
	if _header_font != null:
		# Buttons shout, so they take the display face everywhere.
		theme.set_font("font", "Button", _header_font)

	theme.set_stylebox("normal", "Button", flat_button(panel, blue, false))
	theme.set_stylebox("hover", "Button", flat_button(panel, blue, true))
	theme.set_stylebox("pressed", "Button", flat_button_pressed(panel, blue))
	theme.set_stylebox("disabled", "Button", flat_button(panel, grey, false, 0.45))
	theme.set_stylebox("focus", "Button", flat_button(panel, blue, false))
	theme.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.7))
	theme.set_constant("outline_size", "Button", 4)

	theme.set_stylebox("panel", "PanelContainer", panel_style(panel, stroke))
	theme.set_stylebox("background", "ProgressBar", progress_bg())
	theme.set_stylebox("fill", "ProgressBar", progress_fill(blue))

	# Cyan is the "tap this" colour; green is reserved for cash and success.
	_add_button_variation(theme, "PrimaryButton", blue)
	_add_button_variation(theme, "MoneyButton", green)
	_add_button_variation(theme, "SecondaryButton", grey, false)
	_add_button_variation(theme, "DangerButton", red)
	_add_button_variation(theme, "BoostButton", orange)

	# Headline and number roles take the display face; prose roles stay on Inter
	# so long descriptions remain readable.
	_add_label_variation(theme, "TitleLabel", white, header_size(FONT_TITLE), true)
	_add_label_variation(theme, "DisplayLabel", white, header_size(FONT_DISPLAY), true)
	_add_label_variation(theme, "StatLabel", white, header_size(FONT_STAT), true)
	# Both grey roles are lifted well clear of the panel behind them: at the
	# catalogue grey these read as disabled rather than secondary.
	_add_label_variation(theme, "SectionLabel", grey.lightened(0.3), header_size(FONT_SMALL), true)
	_add_label_variation(theme, "MutedLabel", grey.lightened(0.45), FONT_MUTED)
	_add_label_variation(theme, "AccentLabel", blue, FONT_BODY)
	_add_label_variation(theme, "MoneyLabel", green, header_size(FONT_BODY), true)
	_add_label_variation(theme, "WarningLabel", orange, FONT_MUTED)
	_add_label_variation(theme, "ErrorLabel", red, FONT_BODY)
	if _header_font != null:
		theme.set_constant("extra_spacing_glyph", "SectionLabel", 2)

	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel", card_style())

	# Flat information strips: content sits on the background with no border.
	theme.set_type_variation("InfoStrip", "PanelContainer")
	theme.set_stylebox("panel", "InfoStrip", info_strip_style())

	# Thin technical rail rather than a chunky bar sitting on the card edges.
	for bar in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", bar, _scroll_track())
		theme.set_stylebox("grabber", bar, _scroll_grabber(0.5))
		theme.set_stylebox("grabber_highlight", bar, _scroll_grabber(0.8))
		theme.set_stylebox("grabber_pressed", bar, _scroll_grabber(0.9))

	return theme


static func _scroll_track() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


static func _scroll_grabber(alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var grey: Color = color("grey")
	style.bg_color = Color(grey.r, grey.g, grey.b, alpha)
	style.set_corner_radius_all(3)
	return style


static func _add_label_variation(
	theme: Theme, variation: String, font_color: Color, font_size: int, display: bool = false
) -> void:
	theme.set_type_variation(variation, "Label")
	theme.set_color("font_color", variation, font_color)
	theme.set_font_size("font_size", variation, font_size)
	if display:
		_ensure_fonts()
		if _header_font != null:
			theme.set_font("font", variation, _header_font)


static func _add_button_variation(theme: Theme, variation: String, accent: Color, filled: bool = true) -> void:
	theme.set_type_variation(variation, "Button")
	theme.set_stylebox("normal", variation, action_button_style(accent, false, filled))
	theme.set_stylebox("hover", variation, action_button_style(accent, true, filled))
	theme.set_stylebox("pressed", variation, pressed_button_style(accent, filled))
	theme.set_stylebox("disabled", variation, disabled_button_style())
	theme.set_stylebox("focus", variation, action_button_style(accent, false, filled))
	theme.set_color("font_color", variation, color("white"))
	theme.set_color("font_hover_color", variation, accent.lightened(0.45))
	theme.set_color("font_pressed_color", variation, color("white"))
	theme.set_color("font_disabled_color", variation, color("grey"))
	theme.set_color("font_outline_color", variation, Color(0, 0, 0, 0.75))
	theme.set_constant("outline_size", variation, 4)
	theme.set_constant("h_separation", variation, SPACE_MD)
	theme.set_constant("icon_max_width", variation, 52)
	theme.set_color("icon_normal_color", variation, Color.WHITE)
	theme.set_color("icon_disabled_color", variation, Color(1, 1, 1, 0.35))


## Heavy game action button: accent-tinted fill, thick edge, clipped corner and a
## deep bottom bevel so it reads as a physical key rather than a settings row.
static func action_button_style(accent: Color, bright: bool, filled: bool = true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var base: Color = color("bg_panel")
	var mix: float = 0.34 if filled else 0.14
	if bright:
		mix += 0.18
	style.bg_color = base.lerp(accent, mix)
	# Vertical sheen: lighter at the top edge, so the cap looks lit from above.
	style.bg_color = style.bg_color.lightened(0.04 if bright else 0.0)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = BUTTON_BEVEL
	style.border_color = accent if bright else accent.darkened(0.12)
	_clip_corners(style, 18, 4)
	style.content_margin_left = SPACE_LG
	style.content_margin_right = SPACE_LG
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.shadow_color = Color(accent.r, accent.g, accent.b, 0.34 if bright else 0.18)
	style.shadow_size = 14 if filled else 8
	style.shadow_offset = Vector2(0, 4)
	return style


## Keycap on the burn board. The app-wide action style carries an accent glow and a
## big clipped corner, which reads as a floating call to action; a key on a machine
## is a small-radius cap cut from the case, lit only by its own legend. Same bottom
## bevel, so the press travel is unchanged.
##
## `state` is one of "normal", "hover", "pressed" or "disabled".
static func deck_key_style(
	accent: Color, filled: bool = true, state: String = "normal"
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	# Mixed from the deck plate rather than from the panel colour, so a cap looks
	# cut from the same case as the board it is mounted in.
	var base: Color = color("bay").lightened(0.14)
	var mix: float = 0.32 if filled else 0.12
	var edge: Color = accent.darkened(0.15)
	match state:
		"hover":
			mix += 0.14
			edge = accent
		"pressed":
			mix += 0.2
			edge = accent.darkened(0.3)
		"disabled":
			mix = 0.02
			edge = color("stroke_dim")
	style.bg_color = base.lerp(accent, mix)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = BUTTON_BEVEL
	style.border_color = edge
	style.set_corner_radius_all(8)
	style.content_margin_left = SPACE_SM
	style.content_margin_right = SPACE_SM
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	if state == "pressed":
		# The cap is driven into the tray: the bevel moves to the top edge and the
		# content goes down with it.
		style.border_width_top = BUTTON_BEVEL
		style.border_width_bottom = 2
		style.content_margin_top = 10 + BUTTON_BEVEL - 2
		style.content_margin_bottom = 10 - (BUTTON_BEVEL - 2)
	return style


## Pressed state loses the bevel and pushes its content down, so the cap looks
## driven into the board under the thumb.
static func pressed_button_style(accent: Color, filled: bool = true) -> StyleBoxFlat:
	var style: StyleBoxFlat = action_button_style(accent, true, filled)
	style.border_width_bottom = 3
	style.border_width_top = BUTTON_BEVEL
	style.border_color = accent.darkened(0.25)
	style.bg_color = style.bg_color.darkened(0.12)
	style.content_margin_top = 14 + BUTTON_BEVEL - 3
	style.content_margin_bottom = 14 - (BUTTON_BEVEL - 3)
	style.shadow_size = 0
	return style


static func disabled_button_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var base: Color = color("bg")
	style.bg_color = Color(base.r, base.g, base.b, 0.55)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 4
	style.border_color = color("stroke_dim")
	_clip_corners(style, 18, 4)
	style.content_margin_left = SPACE_LG
	style.content_margin_right = SPACE_LG
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style


## Asymmetric radii read as a clipped technical corner rather than app-style
## uniform rounding.
static func _clip_corners(style: StyleBoxFlat, large: int, small: int) -> void:
	style.corner_radius_top_left = large
	style.corner_radius_top_right = small
	style.corner_radius_bottom_right = large
	style.corner_radius_bottom_left = small


static func flat_button(bg: Color, border: Color, bright: bool, alpha: float = 1.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(bg.r, bg.g, bg.b, alpha)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 6
	style.border_color = border if bright else border.darkened(0.35)
	_clip_corners(style, 14, 4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


static func flat_button_pressed(bg: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = flat_button(bg, border, true)
	style.border_width_bottom = 2
	style.border_width_top = 6
	style.content_margin_top = 14
	style.content_margin_bottom = 6
	return style


## Tier 1 surface: large translucent game panel floating over the diorama.
static func panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(bg.r, bg.g, bg.b, 0.9)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = border
	style.set_corner_radius_all(CORNER_RADIUS)
	return style


## Tier 3 surface: no container at all, just padding, so secondary readouts can
## breathe directly over the background.
static func info_strip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.content_margin_left = SPACE_SM
	style.content_margin_right = SPACE_SM
	style.content_margin_top = SPACE_XS
	style.content_margin_bottom = SPACE_XS
	return style


## Tier 2 surface: interactive card. Brighter edge, subtle lift, clipped corner,
## and an optional accent stripe down the left for category identity.
static func card_style(accent_key: String = "") -> StyleBox:
	var style := StyleBoxFlat.new()
	var base: Color = color("bg_panel")
	style.bg_color = Color(base.r, base.g, base.b, 0.94)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = color("stroke_dim").lightened(0.22)
	_clip_corners(style, 20, 4)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	if accent_key != "":
		var accent: Color = AssetCatalog.rarity_color(accent_key) if _is_rarity(accent_key) else color(accent_key)
		style.border_width_left = 8
		style.border_color = accent.darkened(0.1)
		style.bg_color = base.lerp(accent, 0.06)
	return style


## Same card surface but given an explicit colour, for job sectors and other
## data-driven accents that are not palette keys.
static func card_style_accent(accent: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = card_style() as StyleBoxFlat
	var base: Color = color("bg_panel")
	style.border_width_left = 8
	style.border_color = accent.darkened(0.1)
	style.bg_color = base.lerp(accent, 0.06)
	return style


static func _is_rarity(key: String) -> bool:
	return key in ["common", "rare", "epic", "legendary"]


## Compact high-contrast chip used for tags, difficulty and warnings.
static func chip_style(accent: Color, filled: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var base: Color = color("bg")
	style.bg_color = base.lerp(accent, 0.3 if filled else 0.14)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = accent.darkened(0.05)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 3
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


static func sheet_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var base: Color = color("bg_panel")
	style.bg_color = Color(base.r, base.g, base.b, 0.98)
	style.border_width_top = 2
	style.border_color = color("stroke_dim").lightened(0.1)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	return style


static func nav_bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var base: Color = color("bg").darkened(0.2)
	style.bg_color = Color(base.r, base.g, base.b, 0.92)
	style.border_width_top = 2
	style.border_color = color("stroke_dim").lightened(0.15)
	return style


## Bottom navigation tab: flat, with an accent bar along the top edge and a
## faint wash behind the active tab.
static func nav_tab_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var accent: Color = semantic("action")
	if active:
		var base: Color = color("bg_panel")
		style.bg_color = base.lerp(accent, 0.22)
		style.border_width_top = 5
		style.border_color = accent
	else:
		style.bg_color = Color(0, 0, 0, 0)
	style.content_margin_left = SPACE_SM
	style.content_margin_right = SPACE_SM
	style.content_margin_top = 12
	style.content_margin_bottom = 10
	return style


static func progress_bg() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color("bg")
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = color("stroke_dim")
	style.set_corner_radius_all(8)
	return style


static func progress_fill(fill_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.set_corner_radius_all(7)
	return style


static func progress_fill_for(stat_key: String) -> StyleBoxFlat:
	var color_key: String = "blue"
	match stat_key:
		"tokens":
			color_key = "blue"
		"quality":
			color_key = "yellow"
		"deadline":
			color_key = "green"
		"heat":
			color_key = "orange"
	return progress_fill(color(color_key))
