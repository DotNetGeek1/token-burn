extends Node

## Makes a design pixel a readable size on whatever screen the game is on.
##
## The game is authored on a 1280×720 canvas that Godot stretches over the
## window. On a monitor a design pixel is roughly a real pixel and 12 px type is
## legible. On a handset the same canvas is squeezed into fifteen centimetres,
## a design pixel is a tenth of a millimetre and 12 px type is a millimetre
## tall. Pixel counts say nothing about that; the physical size of a design
## pixel (window pixels × screen DPI) does.
##
## So this node measures that size and raises the window's
## `content_scale_factor` until `ConsoleStyle.FONT_SMALL` reaches its
## millimetre target. Everything on the canvas — type, padding, textures, touch
## targets — grows by the same amount, and the canvas gets smaller in design
## pixels: a 6.8" phone ends up around 650×300. The cabinet's layout profiles
## read that canvas and pick the handset profile for it; the console overlays
## measure the canvas they are given and find nothing left to compensate.
##
## A monitor comes out at 1.0 and nothing changes. Tests set the factor by
## hand with `override_factor`.

signal factor_changed(factor: float)

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

## Above this the room has to be laid out for a handset, not a monitor.
const HANDSET_THRESHOLD := 1.2
## The canvas is never squeezed shorter than this many design pixels: below it
## nothing lays out, so on a very small screen type falls a little under its
## millimetre target instead.
const MIN_CANVAS_HEIGHT := 300.0
## The hard ceiling on the factor whatever the canvas has room for.
const MAX_FACTOR := 3.0

var _factor: float = 1.0
var _override: float = -1.0


func _ready() -> void:
	get_viewport().size_changed.connect(_apply)
	_apply()


## The factor the canvas is drawn at: 1.0 on a monitor, ~2.4 on a handset.
func factor() -> float:
	return _factor


## Whether the screen is small enough that the room has to be laid out for a
## handset. The layout profiles pick by canvas size; this is the same fact for
## code that wants it in one word.
func is_handset() -> bool:
	return _factor > HANDSET_THRESHOLD


## Forces the factor (tests, the screenshot tool). A negative value clears the
## override and goes back to measuring the screen.
func override_factor(value: float) -> void:
	_override = value
	_apply()


## What the screen needs: how far a design pixel of the *base* canvas (the
## project's 1280×720 stretched to the window, before any factor) falls short
## of the millimetre target for small type, capped so the canvas keeps its
## floor height. 1.0 when the platform cannot report a usable DPI and is not a
## handset.
func measured_factor() -> float:
	var window_size: Vector2i = DisplayServer.window_get_size()
	if window_size.y <= 0:
		return 1.0
	var base_height: float = _base_canvas_height(window_size)
	var ceiling: float = maxf(1.0, minf(MAX_FACTOR, base_height / MIN_CANVAS_HEIGHT))
	var dpi: int = DisplayServer.screen_get_dpi()
	if dpi <= 0:
		return clampf(ConsoleMetrics.MOBILE_SCALE_FLOOR, 1.0, ceiling) if ConsoleMetrics.is_mobile() else 1.0
	var physical_per_design: float = float(window_size.y) / base_height
	var mm_per_design_px: float = physical_per_design / float(dpi) * 25.4
	var needed: float = ConsoleMetrics.TARGET_SMALL_MM / (float(ConsoleStyle.FONT_SMALL) * mm_per_design_px)
	return clampf(needed, 1.0, ceiling)


## The height of the base canvas in design pixels: the project's content scale
## size, expanded to the window's aspect the way `aspect = expand` does it.
func _base_canvas_height(window_size: Vector2i) -> float:
	var base: Vector2 = Vector2(get_window().content_scale_size)
	if base.x <= 0.0 or base.y <= 0.0:
		base = Vector2(
			float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
			float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
		)
	if window_size.x <= 0:
		return base.y
	var window_aspect: float = float(window_size.x) / float(window_size.y)
	var base_aspect: float = base.x / base.y
	# Expand keeps the base canvas and grows the short side's opposite: a
	# wider window keeps the height, a taller one keeps the width.
	if window_aspect >= base_aspect:
		return base.y
	return base.x / window_aspect


func _apply() -> void:
	var wanted: float = _override if _override > 0.0 else measured_factor()
	wanted = clampf(wanted, 1.0, MAX_FACTOR)
	var window: Window = get_window()
	if window == null:
		return
	var changed: bool = not is_equal_approx(wanted, _factor) or not is_equal_approx(window.content_scale_factor, wanted)
	_factor = wanted
	if not is_equal_approx(window.content_scale_factor, wanted):
		window.content_scale_factor = wanted
	if changed:
		factor_changed.emit(_factor)
