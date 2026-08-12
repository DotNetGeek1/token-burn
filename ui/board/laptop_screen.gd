class_name LaptopScreen
extends PanelContainer

## The laptop standing on the desk, printing the state of the operation.
##
## The room art paints an open laptop with a blank screen and the catalog says
## where that screen is, so this fills the glass rather than floating a card
## over the picture. Everything on it is drawn in the same phosphor language as
## the job board and the market, because in the fiction it is the same machine.
##
## Type is sized off however large the screen ended up being drawn: a garage
## laptop is a smaller piece of glass than a moon lab one, and the console has
## to stay readable on both without either scrolling or overflowing.

## Reference height the font sizes below were chosen against.
const REFERENCE_HEIGHT := 240.0
const MOBILE_VIEWPORT_WIDTH := 900.0
const MIN_SCALE_DESKTOP := 0.6
const MIN_SCALE_MOBILE := 0.85
## Below this the menu strip is no longer worth reading, so a laptop too narrow
## for its own menu at this size clips rather than shrinking further.
const NAV_MIN_FONT := 6

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

var _margin: MarginContainer = null
var _body: VBoxContainer = null
var _header: Label = null
var _status: Label = null
var _blurb: Label = null
var _scroll: ScrollContainer = null
var _stats: VBoxContainer = null
var _actions: GridContainer = null
var _nav: HBoxContainer = null
var _nav_rule: ColorRect = null
var _nav_rows: Dictionary = {}
var _nav_font: int = ConsoleStyle.FONT_SMALL
var _nav_pad: int = 4
var _rules: Array[ColorRect] = []
var _stat_rows: Dictionary = {}
var _screen_name: String = "DESK"
var _scale: float = 1.0


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
	_body.add_child(_status)

	_blurb = ConsoleStyle.paragraph("", ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR_DIM)
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

	# The main menu is part of the machine rather than a bar bolted under the
	# room, so it is always the last block on the glass. It is one line across
	# rather than five down: the commands above it are what the player came to
	# press, and a menu stacked underneath them was taking a third of the screen.
	_nav = HBoxContainer.new()
	_nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav.visible = false
	_nav_rule = _rule(0.2)
	_nav_rule.visible = false
	_body.add_child(_nav_rule)
	_body.add_child(_nav)

	add_child(ConsoleStyle.crt_overlay())
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


## One printed reading. Rows are addressed by key so the caller can rewrite a
## value every tick without rebuilding the screen under the player's pointer.
func set_stat(key: String, caption: String, value: String, color: Color = ConsoleStyle.PHOSPHOR) -> void:
	if _body == null:
		_build()
	var row: HBoxContainer = _stat_rows.get(key)
	if row == null:
		row = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var caption_label: Label = ConsoleStyle.label("", ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR_DIM)
		caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption_label.clip_text = true
		row.add_child(caption_label)
		var value_label: Label = ConsoleStyle.label("", ConsoleStyle.FONT_SMALL, color)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
		_stats.add_child(row)
		_stat_rows[key] = row
		_fit_to_glass()
	(row.get_child(0) as Label).text = caption.to_upper()
	var value_label: Label = row.get_child(1)
	value_label.text = value
	value_label.add_theme_color_override("font_color", color)


## Drops any printed reading whose key is not in `keep`. Lanes come and go with
## the machines on the floor, so a console that only ever adds rows would keep
## reporting a contract that has already been delivered.
func prune_stats(keep: Array) -> void:
	for key in _stat_rows.keys():
		if key in keep:
			continue
		var row: Control = _stat_rows[key]
		_stat_rows.erase(key)
		# Detached before freeing, so the next fit does not measure a reading
		# that is already gone.
		_stats.remove_child(row)
		row.queue_free()


## A readout the player can tap for the breakdown behind it. Handed back so the
## caller can wire its own gesture without this screen knowing what a breakdown
## sheet is.
func stat_row(key: String) -> Control:
	return _stat_rows.get(key)


## Console progress: a bar of blocks rather than a styled widget, because the
## machine is printing characters.
func set_meter(key: String, caption: String, ratio: float, note: String) -> void:
	var filled: int = clampi(int(round(clampf(ratio, 0.0, 1.0) * 16.0)), 0, 16)
	var bar: String = "%s%s" % ["#".repeat(filled), ".".repeat(16 - filled)]
	set_stat(key, "%s [%s]" % [caption.to_upper(), bar], note, ConsoleStyle.PHOSPHOR_DIM)


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


## The main menu, printed on the machine. Unlike the context actions this is the
## same list on every console screen, so it is built once and then only its
## flags are rewritten.
func set_nav(entries: Array) -> void:
	if _body == null:
		_build()
	# Detached before freeing, so the fit below measures only the new menu.
	for child in _nav.get_children():
		_nav.remove_child(child)
		child.queue_free()
	_nav_rows.clear()
	for raw in entries:
		var entry: Dictionary = raw
		var row := ConsoleMenuRow.new()
		row.index_label = str(entry.get("index", entry.get("key", "?"))).substr(0, 1).to_upper()
		row.headline = str(entry.get("headline", ""))
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var handler: Variant = entry.get("pressed")
		if handler is Callable:
			row.pressed.connect(handler)
		_nav.add_child(row)
		_nav_rows[str(entry.get("key", ""))] = row
	_nav.visible = not _nav_rows.is_empty()
	_nav_rule.visible = _nav.visible
	_fit_to_glass()


## Flags a menu line as having something worth looking at — stock the player can
## now afford, say. On one line across there is no room for a hint, so the
## marker is an asterisk against the label.
func set_nav_flag(key: String, flagged: bool) -> void:
	var row: ConsoleMenuRow = _nav_rows.get(key)
	if row == null:
		return
	var label: String = row.headline.trim_suffix("*")
	row.headline = "%s*" % label if flagged else label


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
	var mobile: bool = ConsoleMetrics.is_mobile() or _viewport_width() < MOBILE_VIEWPORT_WIDTH
	var min_scale: float = MIN_SCALE_MOBILE if mobile else MIN_SCALE_DESKTOP
	_scale = clampf(height / REFERENCE_HEIGHT, min_scale, 2.6)
	if mobile:
		_scale = clampf(_scale * ConsoleMetrics.stretch_compensation(), min_scale, 2.6)

	# Readability pulls the type up; the glass pulls it back down. Type that
	# prints the nav off the bottom of the laptop is worse than type a step
	# smaller, so the target is walked back until the whole print-out fits:
	# first the explanatory sentence goes, then the scale.
	var show_blurb: bool = height >= 150.0
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
			_fit_nav()
			return
		if show_blurb:
			show_blurb = false
			continue
		if _scale <= min_scale + 0.01:
			_try_row_scale(MIN_ROW_SCALE, height, available)
			_spread_commands(MIN_ROW_SCALE, available)
			_fit_nav()
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
	_nav.add_theme_constant_override("separation", 0)

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
	_scroll.custom_minimum_size = Vector2(
		0.0, minf(_stats.get_combined_minimum_size().y, height * MAX_READOUT_SHARE)
	)
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
	# The menu is reference rather than the thing the player came to press, so it
	# sits a size below the context commands.
	_nav_font = maxi(7, int(round(float(_font_size(ConsoleStyle.FONT_SMALL)) * row_scale)))
	_nav_pad = maxi(2, pad_h / 2)
	_apply_nav_metrics(_nav_font)


func _apply_nav_metrics(font_size: int) -> void:
	for child in _nav.get_children():
		if child is ConsoleMenuRow:
			var row: ConsoleMenuRow = child
			row.set_metrics(font_size, int(font_size * 1.7), _nav_pad)
			# Claimed outright rather than left to the container's share-out:
			# every cell in the row clips itself, so a row given less than it
			# needs loses the end of its word without anything reporting that
			# the strip did not fit.
			var needed: float = row.natural_width(font_size, _nav_pad)
			row.custom_minimum_size.x = needed
			row.size_flags_stretch_ratio = needed


## The menu is the one row that has to fit across rather than down, and five
## commands on a line run out of width long before the print-out runs out of
## height. It is fitted last and on its own, so a narrow laptop loses a size off
## its menu rather than losing the ends of the words in it.
func _fit_nav() -> void:
	if _nav == null or not _nav.visible:
		return
	var pad: int = maxi(6, int(10.0 * _scale))
	var width: float = size.x - float(pad) * 2.0
	if width <= 1.0:
		return
	# A pixel of slack per row, because each cell is clipped to its share and a
	# strip that fits exactly still loses the last column of the last glyph.
	var slack: float = float(_nav.get_child_count())
	var font: int = _nav_font
	while font > NAV_MIN_FONT and _nav_width(font) + slack > width:
		font -= 1
	_apply_nav_metrics(font)


## What the strip needs at `font_size`. Measured off the rows' own claims, which
## they have already staked as minimum widths, so this is the width the container
## would actually be forced to.
func _nav_width(font_size: int) -> float:
	_apply_nav_metrics(font_size)
	return _nav.get_combined_minimum_size().x


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
	var version: String = str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	_header.text = "TOKEN_BURN v%s · [ %s ] · %02d:%02d" % [
		version, _screen_name, int(clock["hour"]), int(clock["minute"]),
	]
