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

const PAD := 10
const HEADING_GAP := 6

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

var _margin: MarginContainer = null
var _body: VBoxContainer = null
var _heading: Label = null
var _rule: ColorRect = null
var _content: VBoxContainer = null


func _init() -> void:
	_build()


func _build() -> void:
	if _body != null:
		return
	add_theme_stylebox_override("panel", ConsoleStyle.glass_box())
	clip_contents = true

	_margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_%s" % side, PAD)
	add_child(_margin)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", HEADING_GAP)
	_margin.add_child(_body)

	_heading = ConsoleStyle.label("", ConsoleStyle.FONT_BODY, ConsoleStyle.PHOSPHOR)
	_heading.visible = false
	_body.add_child(_heading)

	_rule = ConsoleStyle.rule(0.3)
	_rule.visible = false
	_body.add_child(_rule)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", HEADING_GAP)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_content)

	# Every piece of glass in the game is the same tube, so a wall board gets the
	# same scanlines as the laptop it is being read from.
	add_child(ConsoleStyle.crt_overlay())


## The name of what is on the panel. Blank leaves it off entirely.
func set_heading(text: String) -> void:
	_build()
	_heading.text = text.to_upper()
	_heading.visible = text != ""
	_rule.visible = _heading.visible


func content() -> VBoxContainer:
	_build()
	return _content


func set_metrics(scale: float) -> void:
	_build()
	var pad: int = ConsoleMetrics.px(PAD, scale)
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_%s" % side, pad)
	var gap: int = ConsoleMetrics.px(HEADING_GAP, scale)
	_body.add_theme_constant_override("separation", gap)
	_content.add_theme_constant_override("separation", gap)
	_heading.add_theme_font_size_override("font_size", ConsoleMetrics.font_body(scale))
