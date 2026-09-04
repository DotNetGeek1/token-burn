class_name CabinetStyle
extends RefCounted

## The language everything on the Burn Cabinet is printed in.
##
## The cabinet is one piece of painted hardware with dark glass wells, so the
## live UI is phosphor readouts on that glass, amber engraved captions, red for
## anything that burns. It borrows the console's fixed-pitch face and phosphor
## and adds the amber the plate's own brasswork is lit in.

const AMBER := Color(0.93, 0.68, 0.24)
const AMBER_DIM := Color(0.60, 0.44, 0.17)
const PHOSPHOR := ConsoleStyle.PHOSPHOR
const PHOSPHOR_DIM := ConsoleStyle.PHOSPHOR_DIM
const RED := Color(0.92, 0.28, 0.22)
const RED_DIM := Color(0.55, 0.16, 0.13)
const WHITE := Color(0.88, 0.88, 0.85)
const GREY := Color(0.45, 0.48, 0.50)
## The unlit glass behind a live well.
const GLASS := Color(0.020, 0.045, 0.040, 0.97)
const GLASS_EDGE := Color(0.0, 0.0, 0.0, 0.85)
## Ink on the paper job tag.
const INK := Color(0.11, 0.08, 0.05)
const INK_DIM := Color(0.30, 0.23, 0.15)
const INK_GREEN := Color(0.12, 0.36, 0.16)
const INK_RED := Color(0.56, 0.13, 0.10)

## Type sizes at the 1280x720 baseline. Body copy targets 16 px there and is
## never set below 12 (spec 03); captions are engraved labels, not copy, and
## may sit a little under that.
const FONT_TINY := 10
const FONT_SMALL := 12
const FONT_BODY := 16
const FONT_HEAD := 20
const FONT_DRUM := 30
## The floor for anything that is body copy.
const FONT_MIN_BODY := 12


## A line of readout. Fixed pitch, one colour, no wrap.
static func mono(text: String, font_size: int = FONT_BODY, color: Color = PHOSPHOR) -> Label:
	var line: Label = ConsoleStyle.label(text, font_size, color)
	line.clip_text = true
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return line


## Wrapping copy, for briefs and descriptions.
static func prose(text: String, font_size: int = FONT_SMALL, color: Color = PHOSPHOR_DIM) -> Label:
	var line: Label = ConsoleStyle.paragraph(text, font_size, color)
	return line


## An engraved section caption: amber, tiny, upper case.
static func caption(text: String, font_size: int = FONT_TINY, color: Color = AMBER) -> Label:
	var line: Label = mono(text.to_upper(), font_size, color)
	return line


## The dark glass of a well: near-black with a hairline shadow edge so the live
## panel sits *in* the painted bezel rather than floating on it.
static func glass_box(edge_alpha: float = 0.85, fill: Color = GLASS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = Color(0.0, 0.0, 0.0, edge_alpha)
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box


## A small engraved legend plate screwed to the chassis, like the plate's own
## painted "PULL TO ABORT" label: dark metal, brass hairline, a shadow under it
## so it sits on the panel rather than floating over it.
static func legend_plate() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.085, 0.072, 0.058, 0.97)
	box.border_color = Color(AMBER_DIM.r, AMBER_DIM.g, AMBER_DIM.b, 0.6)
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	box.shadow_size = 2
	box.shadow_offset = Vector2(0, 1)
	box.content_margin_left = 3
	box.content_margin_right = 3
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	return box


## Hairline frame in a colour, for selected tiles and grouped readouts.
static func frame(color: Color, alpha: float = 0.5, fill_alpha: float = 0.04, width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color.r, color.g, color.b, fill_alpha)
	box.border_color = Color(color.r, color.g, color.b, alpha)
	box.set_border_width_all(width)
	box.set_corner_radius_all(1)
	box.content_margin_left = 5
	box.content_margin_right = 5
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box


## The screen inside a module cartridge: near-black glass with a faint targeting
## grid and crosshair, and a hairline of the category colour glowing just
## inside the frame. `tint` is that colour; `lit` false leaves the glass dead.
class ModuleScreen extends Control:
	var tint: Color = GREY
	var lit: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_look(color: Color, is_lit: bool) -> void:
		tint = color
		lit = is_lit
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var glass := Color(0.012, 0.025, 0.022, 1.0)
		if lit:
			glass = glass.lerp(tint, 0.10)
		draw_rect(rect, glass)
		var line := Color(tint.r, tint.g, tint.b, 0.10 if lit else 0.045)
		var pitch: float = maxf(6.0, size.y / 5.0)
		var x: float = pitch
		while x < size.x:
			draw_line(Vector2(x, 0.0), Vector2(x, size.y), line, 1.0)
			x += pitch
		var y: float = pitch
		while y < size.y:
			draw_line(Vector2(0.0, y), Vector2(size.x, y), line, 1.0)
			y += pitch
		var centre: Vector2 = size * 0.5
		var cross := Color(tint.r, tint.g, tint.b, 0.16 if lit else 0.06)
		draw_line(Vector2(centre.x, 0.0), Vector2(centre.x, size.y), cross, 1.0)
		draw_line(Vector2(0.0, centre.y), Vector2(size.x, centre.y), cross, 1.0)
		if lit:
			# The glow line just inside the frame, with a soft bloom behind it.
			var inset: float = 1.5
			var glow_rect: Rect2 = rect.grow(-inset)
			draw_rect(glow_rect.grow(1.0), Color(tint.r, tint.g, tint.b, 0.18), false, 3.0)
			draw_rect(glow_rect, Color(tint.r, tint.g, tint.b, 0.85), false, 1.0)


## A glass well: a panel wearing the glass and a CRT overlay, with a body the
## caller fills. The overlay is added last so it draws over the content.
static func glass_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", glass_box())
	panel.clip_contents = true
	return panel


static func crt_overlay(strength: float = 0.18) -> ColorRect:
	var overlay: ColorRect = ConsoleStyle.crt_overlay()
	var material: ShaderMaterial = overlay.material
	material.set_shader_parameter("scanline_strength", strength)
	material.set_shader_parameter("edge_darkness", 0.55)
	material.set_shader_parameter("band_strength", 0.05)
	return overlay


## A hardware key: the game's dark control module with a lit rail, in the
## cabinet's fixed-pitch face. `accent` is the rail colour.
static func key(text: String, accent: Color = PHOSPHOR, font_size: int = FONT_SMALL) -> Button:
	var button := Button.new()
	button.text = text.to_upper()
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var font: Font = UiThemeBuilder.mono_font()
	if font != null:
		button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", WHITE)
	button.add_theme_color_override("font_hover_color", WHITE)
	button.add_theme_color_override("font_pressed_color", WHITE)
	button.add_theme_color_override("font_disabled_color", GREY)
	button.add_theme_constant_override("outline_size", 0)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box: StyleBoxFlat = UiThemeBuilder.deck_key_style(accent, true, state)
		box.content_margin_left = 8
		box.content_margin_right = 8
		box.content_margin_top = 4
		box.content_margin_bottom = 4
		box.shadow_size = 0
		button.add_theme_stylebox_override(state, box)
	var disabled: StyleBoxFlat = UiThemeBuilder.deck_key_style(accent, false, "disabled")
	disabled.content_margin_left = 8
	disabled.content_margin_right = 8
	disabled.content_margin_top = 4
	disabled.content_margin_bottom = 4
	disabled.shadow_size = 0
	button.add_theme_stylebox_override("disabled", disabled)
	return button


## A row tab printed on the glass: bare text, underlined in amber when active.
static func tab(text: String) -> Button:
	var button := Button.new()
	button.text = text.to_upper()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var font: Font = UiThemeBuilder.mono_font()
	if font != null:
		button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", FONT_SMALL)
	button.add_theme_constant_override("outline_size", 0)
	set_tab_active(button, false)
	return button


static func set_tab_active(button: Button, active: bool) -> void:
	var color: Color = AMBER if active else PHOSPHOR_DIM
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", AMBER)
	button.add_theme_color_override("font_pressed_color", AMBER)
	button.add_theme_color_override("font_focus_color", color)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.10 if active else (0.05 if state == "hover" else 0.0))
		box.border_color = AMBER if active else Color(AMBER.r, AMBER.g, AMBER.b, 0.0)
		box.border_width_bottom = 2 if active else 0
		box.set_corner_radius_all(0)
		box.content_margin_left = 8
		box.content_margin_right = 8
		box.content_margin_top = 3
		box.content_margin_bottom = 3
		button.add_theme_stylebox_override(state, box)


## Risk without skulls: a row of five pips, `filled` of them lit.
static func pips(filled: int, color: Color, total: int = 5, size: float = 7.0, off: Color = Color(0, 0, 0, 0.35)) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in range(total):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(size, size)
		pip.color = color if index < filled else off
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pip)
	return row


## A small tinted glyph.
static func glyph(texture: Texture2D, size: float, tint: Color = PHOSPHOR) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(size, size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = tint
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


## A hairline rule.
static func rule(color: Color = PHOSPHOR, alpha: float = 0.25) -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(color.r, color.g, color.b, alpha)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Which colour a module category glows: the cartridge tints in the mockup.
static func category_color(category: String) -> Color:
	match category.to_lower():
		"model":
			return Color(0.30, 0.72, 0.95)
		"prompt":
			return Color(0.36, 0.86, 0.60)
		"context":
			return Color(0.55, 0.85, 0.45)
		"agent":
			return Color(0.95, 0.55, 0.25)
		"test":
			return Color(0.92, 0.36, 0.32)
		"cache":
			return Color(0.65, 0.55, 0.95)
		"hardware":
			return Color(0.92, 0.78, 0.30)
		"deploy":
			return Color(0.95, 0.45, 0.55)
		_:
			return PHOSPHOR


static func risk_color(risk: String) -> Color:
	match risk:
		"INSANE", "HIGH":
			return RED
		"ELEVATED":
			return AMBER
		_:
			return PHOSPHOR


static func risk_level(risk: String) -> int:
	match risk:
		"INSANE":
			return 5
		"HIGH":
			return 4
		"ELEVATED":
			return 3
		"LOW":
			return 1
		_:
			return 2


## Fits a control to a fractional rect of `plate`, in pixels.
static func fit(control: Control, plate: Rect2, fraction: Rect2) -> void:
	control.position = plate.position + fraction.position * plate.size
	control.size = fraction.size * plate.size
