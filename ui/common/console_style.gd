class_name ConsoleStyle
extends RefCounted

## The phosphor language every console screen is drawn in.
##
## These screens are diegetic — they are what the machine in the fiction is
## printing — so they deliberately ignore the app palette in `UiThemeBuilder`
## and share this one instead. Anything that wants to look like terminal output
## takes its colours, its fixed-pitch face and its hairlines from here.

const PHOSPHOR := Color(0.42, 0.92, 0.60)
const PHOSPHOR_DIM := Color(0.30, 0.62, 0.44)
## Text drawn on top of an inverted (lit) row.
const INK := Color(0.03, 0.07, 0.06)
## Warnings and destructive lines burn red rather than green.
const DANGER := Color(0.86, 0.34, 0.40)
const WARNING := Color(0.92, 0.74, 0.36)
## The unlit glass behind everything.
const GLASS := Color(0.02, 0.05, 0.04, 0.92)

const FONT_TINY := 10
const FONT_SMALL := 12
const FONT_BODY := 14
const FONT_HEAD := 18


## A line of terminal output. Everything on a console screen is one of these.
static func label(text: String, font_size: int = FONT_BODY, color: Color = PHOSPHOR) -> Label:
	var line := Label.new()
	line.text = text
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font: Font = UiThemeBuilder.mono_font()
	if font != null:
		line.add_theme_font_override("font", font)
	line.add_theme_font_size_override("font_size", font_size)
	line.add_theme_color_override("font_color", color)
	return line


## Wrapping body copy, for descriptions rather than for table cells.
static func paragraph(text: String, font_size: int = FONT_SMALL, color: Color = PHOSPHOR_DIM) -> Label:
	var line: Label = label(text, font_size, color)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return line


## The one-pixel divider that separates a console header from its body.
static func rule(alpha: float = 0.35) -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, alpha)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Hairline box with a barely-there fill: the frame drawn around a panel or a
## table on the glass.
static func frame_box(border_alpha: float = 0.28, fill_alpha: float = 0.04) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, fill_alpha)
	box.border_color = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, border_alpha)
	box.set_border_width_all(1)
	box.set_corner_radius_all(0)
	return box


## The solid backdrop of a full console screen.
static func glass_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = GLASS
	box.set_corner_radius_all(0)
	return box


## Inverse video: an idle row is bare text with no container, and a hovered,
## focused or pressed row becomes a solid bar the text is knocked out of.
static func row_box(state: String, lit: Color = PHOSPHOR) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(0)
	match state:
		"hover", "focus":
			box.bg_color = Color(lit.r, lit.g, lit.b, 0.82)
		"pressed":
			box.bg_color = lit
		_:
			box.bg_color = Color(lit.r, lit.g, lit.b, 0.0)
	return box


## The CRT overlay the title, the burn rig and the console screens all wear, so
## every piece of glass in the game is the same tube.
static func crt_overlay() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = load("res://ui/board/crt_screen.gdshader")
	material.set_shader_parameter("phosphor", PHOSPHOR)
	overlay.material = material
	return overlay
