extends RefCounted

## Shared scale math for every console screen that is not drawn on the laptop
## glass.
##
## The game is authored on a 1280×720 canvas that Godot stretches over whatever
## screen the player has. Pixel counts say nothing about readability — a phone
## has more pixels than the design canvas but they are physically tiny — so the
## scale is computed from the physical size of a design pixel (via screen DPI)
## against a millimetre target for body text.

const DESIGN_HEIGHT := 720.0
const MIN_SCALE := 1.0
const MAX_SCALE := 3.0
const MOBILE_WIDTH := 900.0
## Fallback boost when the platform cannot report a usable DPI.
const MOBILE_SCALE_FLOOR := 1.6
## Physical height FONT_SMALL should reach on the player's screen. 2.6mm is in
## line with the ~16dp body text floor on handsets.
const TARGET_SMALL_MM := 2.6

const ROW_HEIGHT_REF := 26
const PAD_H_REF := 8
const ACTION_HEIGHT_REF := 26

## Of the window a piece of leant-in furniture claims. The rest is the room it
## is in, which is what stops a leant-in board reading as a screen change.
const FOCUS_FILL := 0.9
const MAX_FOCUS_ZOOM := 4.0


static func is_mobile() -> bool:
	return (
		OS.has_feature("mobile")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)


## Physical millimetres one design pixel covers on the player's screen, or 0.0
## when the platform cannot say (headless, bogus DPI).
static func design_px_mm() -> float:
	var window_size: Vector2i = DisplayServer.window_get_size()
	var dpi: int = DisplayServer.screen_get_dpi()
	if window_size.y <= 0 or dpi <= 0:
		return 0.0
	var design_height: float = DESIGN_HEIGHT
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var visible: Vector2 = tree.root.get_visible_rect().size
		if visible.y > 1.0:
			design_height = visible.y
	var physical_per_design: float = float(window_size.y) / design_height
	return physical_per_design / float(dpi) * 25.4


## How much console type must grow so FONT_SMALL lands on the millimetre
## target. 1.0 on a typical desktop monitor; ~2.2–2.6 on a handset.
static func stretch_compensation() -> float:
	var mm: float = design_px_mm()
	if mm <= 0.0:
		return MOBILE_SCALE_FLOOR if is_mobile() else 1.0
	var needed: float = TARGET_SMALL_MM / (float(ConsoleStyle.FONT_SMALL) * mm)
	return clampf(needed, 1.0, MAX_SCALE)


static func compute_scale(height: float, viewport_width: float = 0.0) -> float:
	var mm: float = design_px_mm()
	var scale: float
	if mm > 0.0:
		scale = TARGET_SMALL_MM / (float(ConsoleStyle.FONT_SMALL) * mm)
	elif is_mobile() or (viewport_width > 0.0 and viewport_width < MOBILE_WIDTH):
		scale = MOBILE_SCALE_FLOOR
	else:
		scale = 1.0
	return clampf(scale, MIN_SCALE, MAX_SCALE)


## Whether the room has to be leant into to be worked.
##
## The game is a picture of a room, and the things in that room are read at the
## size the picture draws them. On a monitor that is fine: the laptop glass is
## the better part of a hand span and the whiteboard is a paperback. On a
## handset the whole room is the size of a playing card, and nothing painted
## into it can be read or reliably hit.
##
## Where that is true the room becomes the view rather than the workspace: the
## player sees all of it, and taps whichever piece of furniture they want to
## use to pull it up to reading size.
static func needs_focus() -> bool:
	return stretch_compensation() > 1.2


## How far the room has to come forward for `rect` — a fraction of the window —
## to be worked at. Enough to fill the window bar a margin, so the thing being
## read is the thing on screen without its edges touching the frame.
static func focus_zoom(rect: Rect2) -> float:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return 1.0
	return clampf(
		minf(FOCUS_FILL / rect.size.x, FOCUS_FILL / rect.size.y), 1.0, MAX_FOCUS_ZOOM
	)


static func px(base: int, scale: float) -> int:
	return maxi(1, int(round(float(base) * scale)))


static func font_tiny(scale: float) -> int:
	return px(ConsoleStyle.FONT_TINY, scale)


static func font_small(scale: float) -> int:
	return px(ConsoleStyle.FONT_SMALL, scale)


static func font_body(scale: float) -> int:
	return px(ConsoleStyle.FONT_BODY, scale)


static func font_head(scale: float) -> int:
	return px(ConsoleStyle.FONT_HEAD, scale)


static func row_height(scale: float) -> int:
	return maxi(36, px(ROW_HEIGHT_REF, scale))


static func pad_h(scale: float) -> int:
	return px(PAD_H_REF, scale)


static func action_height(scale: float) -> int:
	return maxi(36, px(ACTION_HEIGHT_REF, scale))
