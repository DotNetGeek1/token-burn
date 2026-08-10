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

# Type scale, in 1280x720 landscape design units. The scale was originally
# tuned for a 720-wide portrait column; landscape has nearly twice the width but
# little more than half the height, so every size is roughly three quarters of
# its portrait value. That keeps a line of body text about as tall relative to
# the screen as it used to be while letting far more of it fit across.
const FONT_SMALL := 16
## Secondary prose (subtitles, sub-lines, footers). It sits between SMALL and
## BODY because SMALL was tuned for uppercase kickers, and reusing it for whole
## sentences left the explanatory half of the UI harder to read than the numbers
## it was explaining.
const FONT_MUTED := 18
const FONT_BODY := 19
const FONT_TITLE := 27
const FONT_DISPLAY := 36
const FONT_STAT := 30

# Spacing scale
const SPACE_XS := 3
const SPACE_SM := 6
const SPACE_MD := 12
const SPACE_LG := 18

# Width of the right-hand panel that carries the job board, the market, the
# build and the menu. The desk fills everything to its left.
const SIDE_PANEL_WIDTH := 442.0
# Kept for screens that still want a readable measure for a column of prose.
const CONTENT_MAX_WIDTH := 720.0

## Narrowest a card tile can be and still read: below this a job title wraps to
## three lines and the stat chips stack.
const MIN_TILE_WIDTH := 300.0
## Beyond this a tile stops being a tile and starts being a banner.
const MAX_TILE_COLUMNS := 3

const CORNER_RADIUS := 6
# Cards and keys are cut from the machine's case, so they barely round at all.
const CARD_CORNER := 3
const KEY_CORNER := 3
# 64 design units on a 1280-wide landscape panel is ~48dp on a handset held
# sideways, which is the minimum comfortable thumb target.
const TOUCH_TARGET := 64
# Game buttons are the primary way the player acts, so they get more than the
# bare minimum thumb target.
const ACTION_TARGET := 76

# Bebas Neue is condensed and caps-only, so it needs more points than Inter to
# read at the same optical size.
const HEADER_FONT_PATH := "res://presentation/fonts/BebasNeue-Regular.ttf"
const BODY_FONT_PATH := "res://presentation/fonts/Inter-Variable.ttf"
const MONO_FONT_PATH := "res://presentation/fonts/ShareTechMono-Regular.ttf"
const HEADER_SCALE := 1.2

## Buttons are flat control modules cut from the case, not keycaps: a hairline
## border, an illuminated left rail, and a one-pixel press. The old six-pixel
## bottom bevel is kept at zero so scenes that still reserve room for it lay out
## unchanged.
const BUTTON_BEVEL := 0
## Vertical padding inside a control module.
const BUTTON_PAD_V := 12
## Horizontal padding inside a control module.
const BUTTON_PAD_H := 16
## Hairline edge. Colour, not weight, is what carries state.
const MODULE_BORDER := 1
## The one industrial motif: an illuminated rail down the left edge.
const ACCENT_RAIL := 3
## How far a module sinks under the thumb.
const PRESS_TRAVEL := 1

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
	"lab": "teal",
	"neutral": "grey",
}

## Bright variant used for hover, so an accent can power up without changing hue.
const BRIGHT_VARIANTS := {
	"blue": "blue_bright",
	"orange": "orange_bright",
	"red": "red_bright",
	"green": "green_bright",
}

## Surface tiers, straight from the button style guide.
const SURFACE := "#0d1013"
const SURFACE_HOVER := "#14181b"
const SURFACE_PRESSED := "#090b0d"
const SURFACE_DISABLED := "#0a0c0e"
const BORDER_IDLE := "#343a40"
const BORDER_HOVER := "#596168"
const BORDER_DISABLED := "#24282c"
const TEXT_PRIMARY := "#e1e1df"
const TEXT_SECONDARY := "#7e858a"
const TEXT_DISABLED := "#4e5459"


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
## How many card tiles fit across a container of this width. Every catalogue
## screen asks the same question, and every one of them used to answer it with
## "one", which is why a 1280-wide window showed two job offers.
static func tile_columns(available_width: float) -> int:
	return clampi(int(available_width / MIN_TILE_WIDTH), 1, MAX_TILE_COLUMNS)


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


## Powered-up version of a semantic role, for hover and focus.
static func semantic_bright(role: String) -> Color:
	var hue: String = str(SEMANTIC_ROLES.get(role, role))
	if BRIGHT_VARIANTS.has(hue):
		return color(str(BRIGHT_VARIANTS[hue]))
	return color(hue).lightened(0.2)


static func brighten(accent: Color) -> Color:
	return accent.lightened(0.22)


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
	theme.set_stylebox("disabled", "Button", disabled_button_style())
	theme.set_stylebox("focus", "Button", module_style(blue, "focus", false))
	theme.set_color("font_disabled_color", "Button", Color(TEXT_DISABLED))
	theme.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.6))
	theme.set_constant("outline_size", "Button", 2)

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
	# Kickers and figures are machine output, so they take the terminal face the
	# rig's own readouts use rather than the poster face used for titles.
	_add_mono_label_variation(theme, "SectionLabel", Color(TEXT_SECONDARY), FONT_SMALL)
	_add_label_variation(theme, "MutedLabel", Color(TEXT_SECONDARY), FONT_MUTED)
	_add_label_variation(theme, "AccentLabel", blue, FONT_BODY)
	_add_mono_label_variation(theme, "MoneyLabel", green, FONT_BODY)
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


## A label role that reads as something the machine printed. Sized off the base
## scale rather than through `header_size`, which exists to compensate for the
## condensed poster face and would oversize a monospace.
static func _add_mono_label_variation(
	theme: Theme, variation: String, font_color: Color, font_size: int
) -> void:
	theme.set_type_variation(variation, "Label")
	theme.set_color("font_color", variation, font_color)
	theme.set_font_size("font_size", variation, font_size)
	_ensure_fonts()
	if _mono_font != null:
		theme.set_font("font", variation, _mono_font)


static func _add_button_variation(theme: Theme, variation: String, accent: Color, filled: bool = true) -> void:
	theme.set_type_variation(variation, "Button")
	theme.set_stylebox("normal", variation, action_button_style(accent, false, filled))
	theme.set_stylebox("hover", variation, action_button_style(accent, true, filled))
	theme.set_stylebox("pressed", variation, pressed_button_style(accent, filled))
	theme.set_stylebox("disabled", variation, disabled_button_style())
	theme.set_stylebox("focus", variation, action_button_style(accent, false, filled))
	theme.set_color("font_color", variation, Color(TEXT_PRIMARY))
	theme.set_color("font_hover_color", variation, Color(TEXT_PRIMARY))
	theme.set_color("font_pressed_color", variation, Color(TEXT_PRIMARY))
	theme.set_color("font_disabled_color", variation, Color(TEXT_DISABLED))
	theme.set_color("font_outline_color", variation, Color(0, 0, 0, 0.6))
	theme.set_constant("outline_size", variation, 2)
	theme.set_constant("h_separation", variation, SPACE_MD)
	theme.set_constant("icon_max_width", variation, 40)
	# The icon is where a secondary control shows its semantic colour, since the
	# surface itself stays hardware dark.
	theme.set_color("icon_normal_color", variation, accent.lightened(0.15))
	theme.set_color("icon_hover_color", variation, brighten(accent))
	theme.set_color("icon_disabled_color", variation, Color(TEXT_DISABLED))


## The one control surface every button in the game is cut from: a dark module
## with a hairline edge and a 3px illuminated rail down its left side. State is
## carried by how brightly the rail and the edge are lit, never by flooding the
## whole control with its accent — 90% dark hardware, 10% illumination.
##
## `state` is one of "normal", "hover", "pressed", "focus" or "disabled".
## `filled` marks the controls high enough in the hierarchy to earn a faint
## accent wash and a trace of glow behind them.
static func module_style(
	accent: Color, state: String = "normal", filled: bool = true
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var surface: Color = Color(SURFACE)
	# A stylebox carries one border colour for all four edges, so the rail and the
	# hairline are the same hue and the rail reads only through its extra width.
	# Filled modules light that hue; unfilled ones let it fall back to hardware
	# grey until the pointer arrives.
	var edge: Color = accent.darkened(0.32) if filled else Color(BORDER_IDLE)
	# A filled module tints its surface toward the accent just enough to read as
	# powered from across the screen.
	var wash: float = 0.07 if filled else 0.0
	match state:
		"hover":
			surface = Color(SURFACE_HOVER)
			edge = brighten(accent)
			wash += 0.05
		"pressed":
			surface = Color(SURFACE_PRESSED)
			edge = accent.darkened(0.35)
		"focus":
			edge = accent
		"disabled":
			surface = Color(SURFACE_DISABLED)
			edge = Color(BORDER_DISABLED)
			wash = 0.0
	style.bg_color = surface.lerp(accent, wash)
	style.border_width_top = MODULE_BORDER
	style.border_width_right = MODULE_BORDER
	style.border_width_bottom = MODULE_BORDER
	style.border_width_left = ACCENT_RAIL
	style.border_color = edge
	style.set_corner_radius_all(KEY_CORNER)
	style.content_margin_left = BUTTON_PAD_H
	style.content_margin_right = BUTTON_PAD_H
	style.content_margin_top = BUTTON_PAD_V
	style.content_margin_bottom = BUTTON_PAD_V
	if state == "pressed":
		style.content_margin_top = BUTTON_PAD_V + PRESS_TRAVEL
		style.content_margin_bottom = BUTTON_PAD_V - PRESS_TRAVEL
	# Restrained spill, 5-12% opacity, only on the controls that matter.
	if filled and state != "disabled" and state != "pressed":
		style.shadow_color = Color(
			accent.r, accent.g, accent.b, 0.12 if state == "hover" else 0.07
		)
		style.shadow_size = 4
		style.shadow_offset = Vector2.ZERO
	return style


## Named after the rail colour rather than the border, for controls that want the
## rail lit while the surrounding edge stays neutral hardware grey.
static func rail_style(accent: Color, state: String = "normal") -> StyleBoxFlat:
	return module_style(accent, state, false)


## App-wide action button. Kept as a thin wrapper so the many call sites that
## already ask for it need no change.
static func action_button_style(accent: Color, bright: bool, filled: bool = true) -> StyleBoxFlat:
	return module_style(accent, "hover" if bright else "normal", filled)


## Burn-board keys are the same control module as every other button; only their
## padding is tighter, because a deck packs a lot of them into one plate.
static func deck_key_style(
	accent: Color, filled: bool = true, state: String = "normal"
) -> StyleBoxFlat:
	var style: StyleBoxFlat = module_style(accent, state, filled)
	style.content_margin_left = SPACE_MD
	style.content_margin_right = SPACE_SM
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	if state == "pressed":
		style.content_margin_top = 8 + PRESS_TRAVEL
		style.content_margin_bottom = 8 - PRESS_TRAVEL
	return style


static func pressed_button_style(accent: Color, filled: bool = true) -> StyleBoxFlat:
	return module_style(accent, "pressed", filled)


static func disabled_button_style() -> StyleBoxFlat:
	return module_style(Color(BORDER_DISABLED), "disabled", false)


static func flat_button(_bg: Color, border: Color, bright: bool, alpha: float = 1.0) -> StyleBoxFlat:
	var style: StyleBoxFlat = module_style(border, "hover" if bright else "normal", false)
	if alpha < 1.0:
		style.bg_color = Color(style.bg_color.r, style.bg_color.g, style.bg_color.b, alpha)
	return style


static func flat_button_pressed(_bg: Color, border: Color) -> StyleBoxFlat:
	return module_style(border, "pressed", false)


## Tier 1 surface: large translucent game panel floating over the diorama.
static func panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(bg.r, bg.g, bg.b, 0.94)
	style.border_width_left = MODULE_BORDER
	style.border_width_top = MODULE_BORDER
	style.border_width_right = MODULE_BORDER
	style.border_width_bottom = MODULE_BORDER
	style.border_color = border
	style.set_corner_radius_all(CARD_CORNER)
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


## Tier 2 surface: interactive card. A pane of bay glass set in the case, not a
## floating app card — square corners, a hard bezel edge with the light on the
## top rim, and an accent stripe down the left for category identity. The old
## 20px rounding and coloured lift read as a phone app pasted over the art.
static func card_style(accent_key: String = "") -> StyleBox:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(SURFACE)
	style.border_width_left = MODULE_BORDER
	style.border_width_top = MODULE_BORDER
	style.border_width_right = MODULE_BORDER
	style.border_width_bottom = MODULE_BORDER
	style.border_color = Color(BORDER_IDLE)
	style.set_corner_radius_all(CARD_CORNER)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	if accent_key != "":
		var accent: Color = AssetCatalog.rarity_color(accent_key) if _is_rarity(accent_key) else color(accent_key)
		return _apply_card_rail(style, accent)
	return style


## Same card surface but given an explicit colour, for job sectors and other
## data-driven accents that are not palette keys.
static func card_style_accent(accent: Color) -> StyleBoxFlat:
	return _apply_card_rail(card_style() as StyleBoxFlat, accent)


## A card's outline stays neutral hardware grey; its category colour arrives as a
## rail down the left edge, drawn by `GameCard` as its own node because a
## stylebox carries only one border colour and lighting all four sides turned a
## grid of cards into a paint chart.
static func _apply_card_rail(style: StyleBoxFlat, accent: Color) -> StyleBoxFlat:
	style.border_width_left = ACCENT_RAIL
	style.border_color = Color(BORDER_IDLE)
	style.bg_color = Color(SURFACE).lerp(accent, 0.03)
	return style


## The illuminated left rail, as a node, for surfaces that want it lit brighter
## than their own border.
static func build_accent_rail(accent: Color) -> ColorRect:
	var rail := ColorRect.new()
	rail.name = "AccentRail"
	rail.color = accent
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	rail.offset_right = float(ACCENT_RAIL)
	return rail


static func _is_rarity(key: String) -> bool:
	return key in ["common", "rare", "epic", "legendary"]


## Compact high-contrast chip used for tags, difficulty and warnings.
static func chip_style(accent: Color, filled: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var base: Color = Color(SURFACE_PRESSED)
	style.bg_color = base.lerp(accent, 0.11 if filled else 0.05)
	style.border_width_left = MODULE_BORDER
	style.border_width_top = MODULE_BORDER
	style.border_width_right = MODULE_BORDER
	style.border_width_bottom = MODULE_BORDER
	# Only a chip that is calling for attention outlines itself in its colour; the
	# rest sit in hardware grey and let the text carry the meaning, so a card with
	# six facts on it does not read as six warnings.
	style.border_color = accent.darkened(0.45) if filled else Color(BORDER_IDLE)
	style.set_corner_radius_all(2)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


static func sheet_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var base: Color = color("bg_panel")
	style.bg_color = Color(base.r, base.g, base.b, 0.98)
	style.border_width_top = MODULE_BORDER
	style.border_color = color("stroke_dim")
	style.corner_radius_top_left = CARD_CORNER
	style.corner_radius_top_right = CARD_CORNER
	return style


## A printed docket lying on the desk, for the round-end surfaces. Warm off-white
## rather than the panel greys, square corners and a drop shadow, so the bills and
## the debrief read as paper the run put in front of you instead of another app
## window floating over the room.
static func docket_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.91, 0.86)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.62, 0.59, 0.53)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 8)
	return style


## Ink on the docket, in the three weights the printed surfaces use.
static func docket_ink(weight: String = "body") -> Color:
	match weight:
		"title":
			return Color(0.09, 0.08, 0.07)
		"muted":
			return Color(0.36, 0.34, 0.30)
		_:
			return Color(0.16, 0.15, 0.13)


static func nav_bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var base: Color = Color(SURFACE_PRESSED)
	style.bg_color = Color(base.r, base.g, base.b, 0.94)
	style.border_width_top = MODULE_BORDER
	style.border_color = color("stroke_dim")
	return style


## Bottom navigation tab: flat, with an accent bar along the top edge and a
## faint wash behind the active tab.
static func nav_tab_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var accent: Color = semantic("action")
	if active:
		var base: Color = Color(SURFACE_HOVER)
		style.bg_color = base.lerp(accent, 0.08)
		style.border_width_top = 2
		style.border_color = accent
	else:
		style.bg_color = Color(0, 0, 0, 0)
	style.content_margin_left = SPACE_SM
	style.content_margin_right = SPACE_SM
	style.content_margin_top = 7
	style.content_margin_bottom = 6
	return style


static func progress_bg() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color("bg")
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = color("stroke_dim")
	style.set_corner_radius_all(2)
	return style


static func progress_fill(fill_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.set_corner_radius_all(1)
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
