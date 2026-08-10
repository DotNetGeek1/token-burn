class_name ConsoleFrame
extends PanelContainer

## The chrome every console screen wears: dark glass, a status line across the
## top naming the program and the screen, a hairline under it, the screen's own
## output below, and the CRT tube over the lot.
##
## The overlay is the same shader the burn rig and the title screen use, so the
## panel the player buys hardware on is visibly the same machine they work on.

const CONTENT_PAD := 10

var _body: VBoxContainer = null
var _title: Label = null
var _context: Label = null
var _content: VBoxContainer = null
var _screen_name: String = "CONSOLE"


func _ready() -> void:
	if _body == null:
		_build()
	set_process(true)


func _build() -> void:
	add_theme_stylebox_override("panel", ConsoleStyle.glass_box())

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, CONTENT_PAD)
	add_child(margin)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	margin.add_child(_body)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(header)

	_title = ConsoleStyle.label("", ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	header.add_child(_title)

	_context = ConsoleStyle.label("", ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR_DIM)
	_context.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_context)

	_body.add_child(ConsoleStyle.rule())

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_content)

	add_child(ConsoleStyle.crt_overlay())
	_refresh_title()


func setup(screen_name: String) -> void:
	if _body == null:
		_build()
	_screen_name = screen_name.to_upper()
	_refresh_title()


## The right-hand readout: whatever number the screen is spent against, usually
## the wallet.
func set_context(text: String, color: Color = ConsoleStyle.PHOSPHOR_DIM) -> void:
	if _body == null:
		_build()
	_context.text = text
	_context.add_theme_color_override("font_color", color)


## Where a screen prints itself.
func content() -> VBoxContainer:
	if _body == null:
		_build()
	return _content


func _process(_delta: float) -> void:
	_refresh_title()


func _refresh_title() -> void:
	if _title == null:
		return
	var clock: Dictionary = Time.get_time_dict_from_system()
	_title.text = "TOKEN_BURN %s · [ %s ] · %02d:%02d" % [
		_version(), _screen_name, int(clock["hour"]), int(clock["minute"]),
	]


func _version() -> String:
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	return "v%s" % (version if version != "" else "0.1.0")
