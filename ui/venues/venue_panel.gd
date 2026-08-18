class_name VenuePanel
extends PanelContainer

## One lit panel in a venue.
##
## The venues are photographs of places with blank display panels hanging in
## them, and this is what gets printed into one. It is `ConsoleFrame` without the
## header ticker: the frame is the machine's own chrome and belongs on the
## laptop, whereas a board bolted to the wall of a shop carries the name of what
## is on it and nothing else.
##
## The heading is optional, because some of these panels are signage rather than
## readouts and a sign with a title bar is a window.

signal pressed

const PAD := 10
const HEADING_GAP := 6

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

var _margin: MarginContainer = null
var _body: VBoxContainer = null
var _heading: Label = null
var _rule: ColorRect = null
var _scroll: ScrollContainer = null
var _content: VBoxContainer = null
var _crt: Control = null
## Takes the press while the panel is across the room. See `set_far_off`.
var _surface: Button = null


func _init() -> void:
	_build()


func _build() -> void:
	if _body != null:
		return
	# A panel may itself be inside the venue's reflowed ScrollContainer. Keep the
	# whole structural chain transparent to drags once the far-off tap surface is
	# hidden.
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_stylebox_override("panel", ConsoleStyle.glass_box())
	clip_contents = true

	_margin = MarginContainer.new()
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_%s" % side, PAD)
	add_child(_margin)

	_body = VBoxContainer.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_constant_override("separation", HEADING_GAP)
	_margin.add_child(_body)

	_heading = ConsoleStyle.label("", ConsoleStyle.FONT_BODY, ConsoleStyle.PHOSPHOR)
	_heading.visible = false
	_body.add_child(_heading)

	_rule = ConsoleStyle.rule(0.3)
	_rule.visible = false
	_body.add_child(_rule)

	# The content sits in a scroll that does not scroll. With both axes disabled a
	# ScrollContainer passes its child's minimum size straight up, so the panel
	# still reports what is mounted in it and still grows to fit — which is what
	# keeps an action row from being placed off the window. Turned on only for a
	# panel being read at close range, where the alternative to scrolling is
	# clipping. See `set_scrollable`.
	_scroll = ScrollContainer.new()
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override("separation", HEADING_GAP)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)

	# Every piece of glass in the game is the same tube, so a wall board gets the
	# same scanlines as the laptop it is being read from.
	_crt = ConsoleStyle.crt_overlay()
	add_child(_crt)

	# Added last so it lies over the lines. Carries no look of its own and is only
	# live while the panel is a sign rather than a screen.
	_surface = Button.new()
	_surface.flat = true
	_surface.focus_mode = Control.FOCUS_NONE
	_surface.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_surface.visible = false
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		_surface.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_surface.pressed.connect(func() -> void:
		UiSound.play("tap")
		pressed.emit()
	)
	add_child(_surface)


## The name of what is on the panel. Blank leaves it off entirely.
func set_heading(text: String) -> void:
	_build()
	_heading.text = text.to_upper()
	_heading.visible = text != ""
	_rule.visible = _heading.visible


func content() -> VBoxContainer:
	_build()
	return _content


## Whiteboards use the room artwork as their surface instead of laying another
## sheet of CRT glass over it. Their live cards still carry the console palette,
## but the blank board and its physical divider remain visible between them.
func set_whiteboard(enabled: bool) -> void:
	_build()
	add_theme_stylebox_override(
		"panel", StyleBoxEmpty.new() if enabled else ConsoleStyle.glass_box()
	)
	if _crt != null:
		_crt.visible = not enabled


## Puts a tap-catcher over the whole panel while it is being seen from across the
## room, where the type on it is smaller than a fingertip.
##
## The panel still prints its whole screenful — a board with a screenful on it read
## from the far side of a shop is what a board looks like, and blanking it to a
## title would make the place a set of doors rather than somewhere with screens in
## it. But nothing on it can honestly be aimed at from there, so a press means
## "let me read this" and the room brings the player up to it.
func set_far_off(far_off: bool) -> void:
	_build()
	_surface.visible = far_off


func far_off() -> bool:
	_build()
	return _surface.visible


## Whether the panel may scroll rather than grow.
##
## A panel normally reports everything mounted in it and is given room for the lot.
## A panel being read at close range cannot be: it is one surface in a room and the
## room decides how much of the window it gets, so a long shelf has to scroll
## inside it. The panel stops asking for the height instead.
func set_scrollable(scrollable: bool) -> void:
	_build()
	var mode: int = (
		ScrollContainer.SCROLL_MODE_AUTO if scrollable
		else ScrollContainer.SCROLL_MODE_DISABLED
	)
	if _scroll.vertical_scroll_mode != mode:
		_scroll.vertical_scroll_mode = mode


func set_metrics(scale: float) -> void:
	_build()
	var pad: int = ConsoleMetrics.px(PAD, scale)
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_%s" % side, pad)
	var gap: int = ConsoleMetrics.px(HEADING_GAP, scale)
	_body.add_theme_constant_override("separation", gap)
	_content.add_theme_constant_override("separation", gap)
	_heading.add_theme_font_size_override("font_size", ConsoleMetrics.font_body(scale))
