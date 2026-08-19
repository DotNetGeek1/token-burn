class_name WorkstationConsole
extends PanelContainer

## The live primary console mounted into the current workstation artwork.
##
## The workstation stage supplies a blank primary screen, so this fills its glass
## rather than floating a card over the room. Everything on it uses the same phosphor language as
## the job board and the market, because in the fiction it is the same machine.
##
## Type is sized off however large the screen ended up being drawn: a laptop
## panel is smaller glass than an ultrawide, and the console has
## to stay readable on both without either scrolling or overflowing.

## Reference height the font sizes below were chosen against.
const REFERENCE_HEIGHT := 240.0
const MOBILE_VIEWPORT_WIDTH := 900.0
const MIN_SCALE_DESKTOP := 0.6
const MIN_SCALE_MOBILE := 0.85
## Glass this size or smaller, measured on the player's actual screen, cannot
## print the desktop console at a readable size however the type is scaled. See
## `_compact`.
const COMPACT_GLASS_MM := 48.0

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

var _margin: MarginContainer = null
var _body: VBoxContainer = null
var _header: Label = null
var _status: Label = null
var _blurb: Label = null
var _scroll: ScrollContainer = null
var _stats: VBoxContainer = null
var _actions: GridContainer = null
## Swallows taps on a laptop too small to be operated, so the first press leans
## the room in on the glass instead of hitting a command by accident.
var _lean_in: Button = null
var _rules: Array[ColorRect] = []
var _stat_rows: Dictionary = {}
## What each reading says, kept rather than only printed. The same reading is
## worded differently on glass of different sizes, and the glass changes size
## under the console when the player leans in on it.
var _readings: Dictionary = {}
## Which wording is currently on the screen.
var _printed_compact: bool = false
var _screen_name: String = "DESK"
var _scale: float = 1.0
var _status_pressed: Callable = Callable()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	if _body == null:
		_build()
	resized.connect(_fit_to_glass)
	_fit_to_glass()
	set_process(true)


func _build() -> void:
	add_theme_stylebox_override("panel", ConsoleStyle.glass_box())

	# The glass is a fixed piece of the artwork, so the print-out is hung inside
	# a plain Control rather than added straight to the panel. A container would
	# pass its children's minimum size up and a busy console would stretch the
	# screen off the bottom of the laptop instead of fitting itself to it.
	var glass := Control.new()
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glass)

	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	glass.add_child(_margin)

	_body = VBoxContainer.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(_body)

	_header = ConsoleStyle.label("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_header.clip_text = true
	_body.add_child(_header)
	_body.add_child(_rule())

	_status = ConsoleStyle.label("", ConsoleStyle.FONT_HEAD, ConsoleStyle.PHOSPHOR)
	_status.clip_text = true
	_status.gui_input.connect(_on_status_gui_input)
	_body.add_child(_status)

	_blurb = ConsoleStyle.paragraph("", ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR_DIM)
	_blurb.gui_input.connect(_on_status_gui_input)
	_body.add_child(_blurb)

	_body.add_child(_rule(0.2))

	# The burn console prints more readings than the glass is tall, so the
	# readout block is the part that gives: the status above it and the commands
	# below it stay put while this scrolls.
	_scroll = ScrollContainer.new()
	# The readouts take the height they need and no more. Room left over on a
	# tall screen goes to the commands below, which is where the player's hand
	# is going; pooling it here just left a band of dead glass mid-screen.
	_scroll.size_flags_vertical = Control.SIZE_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_body.add_child(_scroll)

	_stats = VBoxContainer.new()
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_stats)

	_body.add_child(_rule(0.2))

	# A grid rather than a column: a busy console folds its commands two
	# across, which halves the height the list costs and buys every line a
	# taller, more pressable row.
	_actions = GridContainer.new()
	_actions.columns = 1
	_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_actions)

	add_child(ConsoleStyle.crt_overlay())

	_lean_in = Button.new()
	_lean_in.flat = true
	_lean_in.focus_mode = Control.FOCUS_NONE
	_lean_in.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lean_in.visible = false
	_lean_in.pressed.connect(_on_lean_in_pressed)
	add_child(_lean_in)

	_refresh_header()


func _rule(alpha: float = 0.35) -> ColorRect:
	var line: ColorRect = ConsoleStyle.rule(alpha)
	_rules.append(line)
	return line


func setup(screen_name: String) -> void:
	if _body == null:
		_build()
	_screen_name = screen_name.to_upper()
	_refresh_header()


# --- Content -----------------------------------------------------------------

## The headline the machine is currently reporting, and the sentence under it
## explaining what the player is expected to do about it.
func set_status(headline: String, blurb: String) -> void:
	if _body == null:
		_build()
	_status.text = headline.to_upper()
	_blurb.text = blurb
	_fit_to_glass()


## Makes the headline and the line under it a tap target. Used mid-burn so
## tapping the glass skips the rest of the spectacle without killing the batch.
func set_status_pressed(handler: Callable) -> void:
	_status_pressed = handler
	var filter: Control.MouseFilter = (
		Control.MOUSE_FILTER_STOP if handler.is_valid() else Control.MOUSE_FILTER_IGNORE
	)
	if _status != null:
		_status.mouse_filter = filter
	if _blurb != null:
		_blurb.mouse_filter = filter


func _on_status_gui_input(event: InputEvent) -> void:
	if not _status_pressed.is_valid():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_status_pressed.call()
		accept_event()


## Whether the glass this console is being drawn on is too small, on the
## player's actual screen, to print the desktop version of itself.
##
## This is a physical measurement rather than a platform check. The same
## handset shows this laptop twice: once as a few centimetres of a room, where
## the console can only sketch itself, and again with the room leant in on the
## glass, where there is room for the lot. Which of those is being drawn is a
## question about millimetres, not about Android.
func _compact() -> bool:
	var mm: float = ConsoleMetrics.design_px_mm()
	if mm <= 0.0:
		return ConsoleMetrics.is_mobile() or _viewport_width() < MOBILE_VIEWPORT_WIDTH
	return size.y * mm < COMPACT_GLASS_MM


## Puts a tap-catcher over the whole screen while the room is pulled back far
## enough that the commands on it are smaller than a fingertip. Pressing the
## machine then means "let me read this", which is the only thing a player can
## honestly intend at that size.
func _refresh_lean_in() -> void:
	if _lean_in == null:
		return
	_lean_in.visible = _should_lean_in(ConsoleMetrics.needs_focus(), _compact())


func _should_lean_in(needs_focus: bool, compact: bool) -> bool:
	return needs_focus and compact and not _room_focused()


func _on_lean_in_pressed() -> void:
	UiSound.play("tap")
	# Aim the camera at the primary glass, not the workstation bay around it.
	# The bay became the target when multi-stage rig art was introduced, but it
	# is far larger than a phone screen and left this catcher permanently over
	# commands such as OPEN BOARD after the shallow zoom completed.
	var handled: bool = false
	for node in get_tree().get_nodes_in_group("main_ui"):
		if node.has_method("focus_control"):
			node.call("focus_control", "workstation", self)
			handled = true
	if not handled:
		get_tree().call_group("main_ui", "focus_room", "workstation")
	_refresh_lean_in()


func _room_focused() -> bool:
	for node in get_tree().get_nodes_in_group("main_ui"):
		if (
			node.has_method("room_focused_on")
			and bool(node.call("room_focused_on", "workstation"))
		):
			return true
	return false


## One printed reading. Rows are addressed by key so the caller can rewrite a
## value every tick without rebuilding the screen under the player's pointer.
## `short_caption` is what the reading is called on glass too small for the full
## wording, which would otherwise set the width of the whole print-out.
func set_stat(
	key: String,
	caption: String,
	value: String,
	color: Color = ConsoleStyle.PHOSPHOR,
	short_caption: String = ""
) -> void:
	_readings[key] = {
		"caption": caption, "short": short_caption, "value": value, "color": color,
	}
	_print_reading(key)


## Drops any printed reading whose key is not in `keep`. Lanes come and go with
## the machines on the floor, so a console that only ever adds rows would keep
## reporting a contract that has already been delivered.
func prune_stats(keep: Array) -> void:
	for key in _stat_rows.keys():
		if key in keep:
			continue
		var row: Control = _stat_rows[key]
		_stat_rows.erase(key)
		_readings.erase(key)
		# Detached before freeing, so the next fit does not measure a reading
		# that is already gone.
		_stats.remove_child(row)
		row.queue_free()


## Writes one held reading onto the glass at the wording the glass has room for.
func _print_reading(key: String) -> void:
	if _body == null:
		_build()
	var reading: Dictionary = _readings.get(key, {})
	if reading.is_empty():
		return
	var row: HBoxContainer = _stat_rows.get(key)
	if row == null:
		row = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var caption_label: Label = ConsoleStyle.label(
			"", ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR_DIM
		)
		caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption_label.clip_text = true
		row.add_child(caption_label)
		var new_value: Label = ConsoleStyle.label("", ConsoleStyle.FONT_SMALL)
		new_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(new_value)
		_stats.add_child(row)
		_stat_rows[key] = row
		_fit_to_glass()
	var short: String = str(reading.get("short", ""))
	var caption: String = str(reading.get("caption", ""))
	if _printed_compact and short != "":
		caption = short
	if reading.has("ratio"):
		# The bar is the longest thing the console prints, so glass that cannot
		# take the full-width version gets the same reading at half the
		# resolution rather than a bar written off the edge of the screen.
		var blocks: int = 8 if _printed_compact else 16
		var filled: int = clampi(
			int(round(clampf(float(reading["ratio"]), 0.0, 1.0) * float(blocks))), 0, blocks
		)
		caption = "%s [%s%s]" % [caption, "#".repeat(filled), ".".repeat(blocks - filled)]
	(row.get_child(0) as Label).text = caption.to_upper()
	var value_label: Label = row.get_child(1)
	value_label.text = str(reading.get("value", ""))
	var ink: Color = reading.get("color", ConsoleStyle.PHOSPHOR)
	value_label.add_theme_color_override("font_color", ink)


## A readout the player can tap for the breakdown behind it. Handed back so the
## caller can wire its own gesture without this screen knowing what a breakdown
## sheet is.
func stat_row(key: String) -> Control:
	return _stat_rows.get(key)


## Console progress: a bar of blocks rather than a styled widget, because the
## machine is printing characters.
func set_meter(
	key: String, caption: String, ratio: float, note: String, short_caption: String = ""
) -> void:
	_readings[key] = {
		"caption": caption,
		"short": short_caption,
		"value": note,
		"color": ConsoleStyle.PHOSPHOR_DIM,
		"ratio": ratio,
	}
	_print_reading(key)


## The commands available on this screen. Rebuilt whenever the list changes,
## which is rare enough that reusing rows would cost more than it saves.
func set_actions(entries: Array) -> void:
	if _body == null:
		_build()
	# Detached before freeing: queue_free only takes effect at the end of the
	# frame, and the fit below has to measure the new rows, not both sets.
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	var index: int = 1
	for raw in entries:
		var entry: Dictionary = raw
		var row := ConsoleMenuRow.new()
		row.index_label = str(index)
		row.headline = str(entry.get("headline", ""))
		row.value_text = str(entry.get("value", ""))
		row.destructive = bool(entry.get("destructive", false))
		row.warning = bool(entry.get("warning", false))
		var handler: Variant = entry.get("pressed")
		if handler is Callable:
			row.pressed.connect(handler)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_actions.add_child(row)
		index += 1
	# Short lists stay one under the other, which reads as a menu; from four
	# commands up the list folds into two columns so the rows stay large.
	_actions.columns = 2 if entries.size() >= 4 else 1
	_fit_to_glass()


# --- Fitting -----------------------------------------------------------------

## How far the command rows may be squeezed before the console gives up and lets
## the readouts scroll instead. Below this the type stops being pressable.
const MIN_ROW_SCALE := 0.75

## Most the readouts may claim of the glass. The commands are what the player
## came to press, so they are never the part that gets pushed off.
const MAX_READOUT_SHARE := 0.34


## The glass is whatever size the artwork drew it, so the type is sized to the
## glass. Below a certain height the explanatory sentence goes: the headline and
## the command are what the player has to be able to read.
func _fit_to_glass() -> void:
	if _body == null:
		return
	var height: float = size.y
	if height <= 1.0:
		return
	_refresh_lean_in()
	var mobile: bool = ConsoleMetrics.is_mobile() or _viewport_width() < MOBILE_VIEWPORT_WIDTH
	var compact: bool = _compact()
	if compact != _printed_compact:
		_printed_compact = compact
		for key in _readings:
			_print_reading(key)
	# The mobile floor is there to stop a readable screen being shrunk below
	# what a thumb can work. A screen that is not readable at any size is not
	# being worked, so it may go as small as it likes: this is the laptop seen
	# across the room, and it should look like a machine with a screenful on it
	# rather than like a clipped one.
	var min_scale: float = MIN_SCALE_DESKTOP
	if mobile and not compact:
		min_scale = MIN_SCALE_MOBILE
	_scale = clampf(height / REFERENCE_HEIGHT, min_scale, 2.6)
	if mobile:
		_scale = clampf(_scale * ConsoleMetrics.stretch_compensation(), min_scale, 2.6)

	# Readability pulls the type up; the glass pulls it back down. Type that
	# prints the commands off the bottom of the laptop is worse than type a step
	# smaller, so the target is walked back until the whole print-out fits:
	# first the explanatory sentence goes, then the scale.
	#
	# On glass too small to print it the sentence never gets written. It
	# explains what the screen is for, which is worth a couple of lines on a
	# monitor and is worth more as legible readings on a phone.
	var show_blurb: bool = height >= 150.0 and not compact
	while true:
		var available: float = _apply_glass_chrome(height, show_blurb)
		if _try_row_scale(MIN_ROW_SCALE, height, available):
			var best: float = MIN_ROW_SCALE
			var row_scale: float = MIN_ROW_SCALE + 0.05
			while row_scale <= 1.0:
				if not _try_row_scale(row_scale, height, available):
					break
				best = row_scale
				row_scale += 0.05
			_try_row_scale(best, height, available)
			_spread_commands(best, available)
			return
		if show_blurb:
			show_blurb = false
			continue
		if _scale <= min_scale + 0.01:
			_try_row_scale(MIN_ROW_SCALE, height, available)
			_spread_commands(MIN_ROW_SCALE, available)
			return
		_scale = maxf(min_scale, _scale - 0.15)


## Pads, gaps and the fixed type (header, headline, blurb) at the current
## scale. Returns the glass height left for the readouts and commands.
func _apply_glass_chrome(height: float, show_blurb: bool) -> float:
	var pad: int = maxi(6, int(10.0 * _scale))
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_%s" % side, pad)
	var gap: int = maxi(2, int(5.0 * _scale))
	_body.add_theme_constant_override("separation", gap)
	_stats.add_theme_constant_override("separation", maxi(1, int(3.0 * _scale)))
	_actions.add_theme_constant_override("v_separation", maxi(1, int(3.0 * _scale)))
	_actions.add_theme_constant_override("h_separation", maxi(4, int(10.0 * _scale)))

	_apply_font(_header, ConsoleStyle.FONT_TINY)
	_blurb.visible = show_blurb
	_blurb.max_lines_visible = 3 if height >= 220.0 else 2
	_fit_headline()
	return height - float(pad) * 2.0


## Opens the commands out into whatever height is left over, up to half a line
## each. A console with two things to press should not print them tight at the
## top of an empty screen, but nor should a single command become a bar half the
## height of the glass.
func _spread_commands(row_scale: float, available: float) -> void:
	var rows: int = 0
	for child in _actions.get_children():
		if child is ConsoleMenuRow:
			rows += 1
	if rows == 0:
		return
	var leftover: float = available - _body.get_combined_minimum_size().y
	if leftover <= 0.0:
		return
	# Folded two across, the list is only as tall as its longest column, so the
	# leftover is shared between grid lines rather than between commands.
	var lines: int = ceili(float(rows) / float(maxi(1, _actions.columns)))
	_apply_row_metrics(row_scale, minf(leftover / float(lines), _command_height(row_scale) * 0.5))


func _command_height(row_scale: float) -> float:
	return float(maxi(8, int(round(float(_font_size(ConsoleStyle.FONT_BODY)) * row_scale)))) * 1.6


## Sizes the print-out at `row_scale` and reports whether it still fits. The
## readouts claim exactly the height they need — no more, so there is never a
## band of dead glass above the commands, and no less, so they are not silently
## scrolled out of sight.
func _try_row_scale(row_scale: float, height: float, available: float) -> bool:
	_apply_row_metrics(row_scale)
	var wanted: float = _stats.get_combined_minimum_size().y
	# Glass being read across the room is not being scrolled, so it prints the
	# whole screenful small rather than a third of one at size: a laptop with a
	# reading sawn in half by the edge of a scroll box reads as a broken screen
	# rather than as a machine seen from four feet away.
	if not _printed_compact:
		wanted = minf(wanted, height * MAX_READOUT_SHARE)
	_scroll.custom_minimum_size = Vector2(0.0, wanted)
	return _body.get_combined_minimum_size().y <= available


## Everything below the headline is sized together, so a crowded console reads
## as one smaller print-out rather than as large readings above squinting
## commands.
func _apply_row_metrics(row_scale: float, command_slack: float = 0.0) -> void:
	var pad_h: int = maxi(4, int(8.0 * _scale))
	var body_font: int = maxi(8, int(round(float(_font_size(ConsoleStyle.FONT_SMALL)) * row_scale)))
	_blurb.add_theme_font_size_override("font_size", body_font)
	for key in _stat_rows:
		var stat_row: HBoxContainer = _stat_rows[key]
		for child in stat_row.get_children():
			child.add_theme_font_size_override("font_size", body_font)
	var row_font: int = maxi(8, int(round(float(_font_size(ConsoleStyle.FONT_BODY)) * row_scale)))
	var row_height: int = int(_command_height(row_scale) + command_slack)
	for child in _actions.get_children():
		if child is ConsoleMenuRow:
			child.set_metrics(row_font, row_height, pad_h)


## Contract names are written by content and some of them are long, so the
## headline reads a size down rather than losing its last few words off the edge
## of the screen.
func _fit_headline() -> void:
	var font: Font = _status.get_theme_font("font")
	var width: float = size.x - float(maxi(6, int(10.0 * _scale))) * 2.0
	var font_size: int = _font_size(ConsoleStyle.FONT_HEAD)
	if font != null and width > 1.0 and not _status.text.is_empty():
		while font_size > _font_size(ConsoleStyle.FONT_SMALL):
			var measured: float = font.get_string_size(
				_status.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
			).x
			if measured <= width:
				break
			font_size -= 1
	_status.add_theme_font_size_override("font_size", font_size)


func _apply_font(label: Label, base_size: int) -> void:
	label.add_theme_font_size_override("font_size", _font_size(base_size))


func _font_size(base_size: int) -> int:
	var min_size: int = 8
	if base_size >= ConsoleStyle.FONT_SMALL:
		min_size = 12
	elif base_size >= ConsoleStyle.FONT_TINY:
		min_size = 10
	return clampi(int(round(float(base_size) * _scale)), min_size, 40)


func _viewport_width() -> float:
	return get_viewport_rect().size.x


func _process(_delta: float) -> void:
	_refresh_header()


func _refresh_header() -> void:
	if _header == null:
		return
	var clock: Dictionary = Time.get_time_dict_from_system()
	if _compact():
		# The machine does not need to tell a phone what it is called every
		# frame; which screen is open and what time it is are the useful half.
		_header.text = "[ %s ] · %02d:%02d" % [
			_screen_name, int(clock["hour"]), int(clock["minute"]),
		]
		return
	var version: String = str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	_header.text = "TOKEN_BURN v%s · [ %s ] · %02d:%02d" % [
		version, _screen_name, int(clock["hour"]), int(clock["minute"]),
	]
