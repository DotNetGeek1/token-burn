class_name ConsoleDetail
extends PanelContainer

signal action_pressed
## The player is done reading and wants the board back.
signal closed

const PAD := 10

## The narrowest the pane can be and still read as a sheet about one thing rather
## than a column of broken words. A venue's signage panel is often painted a tenth
## of the picture wide, which is fine for a two-word sign and hopeless for a fee, a
## deadline and a BUY row, so the pane asks for this and the venue's layout finds
## it the room by shifting the panel rather than by shrinking the type.
const MIN_WIDTH := 230

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")


class ActionRow:
	extends Button

	var _label: Label = null
	var _margin: MarginContainer = null

	func _init() -> void:
		text = ""
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(0, 26)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_margin = MarginContainer.new()
		_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		_margin.add_theme_constant_override("margin_left", 8)
		_margin.add_theme_constant_override("margin_right", 8)
		_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_margin)
		_label = ConsoleStyle.label("", ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR)
		_margin.add_child(_label)

	func apply_metrics(scale: float) -> void:
		var pad: int = ConsoleMetrics.pad_h(scale)
		custom_minimum_size = Vector2(0, ConsoleMetrics.action_height(scale))
		_margin.add_theme_constant_override("margin_left", pad)
		_margin.add_theme_constant_override("margin_right", pad)
		_label.add_theme_font_size_override("font_size", ConsoleMetrics.font_small(scale))

	func set_action(label: String, enabled: bool) -> void:
		var lit: Color = ConsoleStyle.PHOSPHOR if enabled else ConsoleStyle.PHOSPHOR_DIM
		_label.text = label
		_label.add_theme_color_override("font_color", lit)
		disabled = not enabled
		focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var box_state: String = state if enabled else "normal"
			add_theme_stylebox_override(state, ConsoleStyle.row_box(box_state, lit))

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT, \
			NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT:
				if _label == null or disabled:
					return
				var inverted: bool = is_hovered() or has_focus()
				_label.add_theme_color_override(
					"font_color", ConsoleStyle.INK if inverted else ConsoleStyle.PHOSPHOR
				)


var _outer_margin: MarginContainer = null
var _box: VBoxContainer = null
var _headline_row: HBoxContainer = null
var _headline: Label = null
var _close: Button = null
var _scroll: ScrollContainer = null
var _lines: VBoxContainer = null
var _action: ActionRow = null
var _scale: float = 1.0


func _ready() -> void:
	if _box == null:
		_build()


func _build() -> void:
	add_theme_stylebox_override("panel", ConsoleStyle.frame_box(0.24, 0.03))
	_outer_margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		_outer_margin.add_theme_constant_override("margin_%s" % side, PAD)
	add_child(_outer_margin)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	_outer_margin.add_child(_box)
	_headline_row = HBoxContainer.new()
	_box.add_child(_headline_row)
	_headline = ConsoleStyle.label("", ConsoleStyle.FONT_BODY, ConsoleStyle.PHOSPHOR)
	_headline.clip_text = true
	_headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_headline_row.add_child(_headline)
	# The pane takes a third of a handset's screen, and the only other ways out
	# of it are pressing a different line on a board it is covering or leaving
	# the screen entirely.
	_close = Button.new()
	_close.text = "[X]"
	_close.flat = true
	_close.visible = false
	_close.focus_mode = Control.FOCUS_NONE
	_close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var font: Font = UiThemeBuilder.mono_font()
	if font != null:
		_close.add_theme_font_override("font", font)
	_close.add_theme_color_override("font_color", ConsoleStyle.PHOSPHOR_DIM)
	_close.add_theme_color_override("font_hover_color", ConsoleStyle.PHOSPHOR)
	_close.add_theme_color_override("font_pressed_color", ConsoleStyle.PHOSPHOR)
	_close.pressed.connect(func() -> void:
		UiSound.play("tap")
		closed.emit()
	)
	_headline_row.add_child(_close)
	# On a phone the scaled-up description would push the action row off the
	# bottom of the screen, leaving the player unable to press it, so the lines
	# scroll inside a capped window instead of claiming their full height.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(_scroll)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 2)
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_lines)
	_lines.resized.connect(func() -> void: call_deferred("_fit_lines"))
	_action = ActionRow.new()
	_action.pressed.connect(func() -> void:
		UiSound.play("tap")
		action_pressed.emit()
	)
	_box.add_child(_action)


func set_metrics(scale: float) -> void:
	_scale = scale
	if _outer_margin == null:
		return
	var pad: int = ConsoleMetrics.px(PAD, scale)
	for side in ["left", "right", "top", "bottom"]:
		_outer_margin.add_theme_constant_override("margin_%s" % side, pad)
	_box.add_theme_constant_override("separation", ConsoleMetrics.px(4, scale))
	_lines.add_theme_constant_override("separation", ConsoleMetrics.px(2, scale))
	_headline.add_theme_font_size_override("font_size", ConsoleMetrics.font_body(scale))
	_close.add_theme_font_size_override("font_size", ConsoleMetrics.font_body(scale))
	_action.apply_metrics(scale)
	# Never wider than the window, which is the one thing asking for width must
	# not be allowed to do: in the reflowed column the pane is already as wide as
	# the screen, and demanding more there would push the column sideways.
	var room: float = get_viewport_rect().size.x - float(pad) * 2.0
	custom_minimum_size.x = minf(float(ConsoleMetrics.px(MIN_WIDTH, scale)), room)
	_apply_line_fonts()
	call_deferred("_fit_lines")


func _apply_line_fonts() -> void:
	var font_small: int = ConsoleMetrics.font_small(_scale)
	for child in _lines.get_children():
		if child is Label:
			child.add_theme_font_size_override("font_size", font_small)
		elif child is HBoxContainer:
			for label in child.get_children():
				if label is Label:
					label.add_theme_font_size_override("font_size", font_small)


func show_detail(headline: String, lines: Array, action: String = "", action_enabled: bool = false) -> void:
	if _box == null:
		_build()
	visible = true
	_headline.text = "> %s" % headline
	_close.visible = true
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	for entry in lines:
		var line: Control = _line(entry)
		if line != null:
			_lines.add_child(line)
	_action.visible = action != ""
	if action != "":
		_action.set_action(action, action_enabled)
	_apply_line_fonts()
	call_deferred("_fit_lines")


func clear(placeholder: String = "SELECT A ROW") -> void:
	if _box == null:
		_build()
	_headline.text = "> %s" % placeholder
	_close.visible = false
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	_action.visible = false
	call_deferred("_fit_lines")


## Most of the screen the pane may take. The board it was opened from is still
## the screen the player is on, and a pane that grew to fit its own description
## would push every line of that board off the top.
const HEIGHT_SHARE := 0.5


## The description window: as tall as its lines want, up to the share of the
## screen it can take without squeezing out the table above or the action row
## below it.
func _fit_lines() -> void:
	if _scroll == null:
		return
	# Measured against the space the screen gave the pane rather than against
	# the window, because on a handset the pane's own type is twice the size and
	# the console around it is not.
	var host: float = get_viewport_rect().size.y
	var content: Control = get_parent() as Control
	if content != null and content.size.y > 1.0:
		host = content.size.y
	var pad: float = float(ConsoleMetrics.px(PAD, _scale)) * 2.0
	var chrome: float = _box.get_combined_minimum_size().y - _scroll.custom_minimum_size.y
	var floor_height: float = float(ConsoleMetrics.font_small(_scale)) * 3.0
	var cap: float = maxf(floor_height, host * HEIGHT_SHARE - chrome - pad)
	var wanted: float = _lines.get_combined_minimum_size().y
	_scroll.custom_minimum_size = Vector2(0.0, _whole_lines(minf(wanted, cap)))


## The window rounded down to a line boundary. A cap that lands mid-line leaves a
## row of type sliced in half along the bottom edge, which reads as a fault in the
## screen rather than as something to scroll.
func _whole_lines(height: float) -> float:
	var separation: float = float(_lines.get_theme_constant("separation"))
	var used: float = 0.0
	var last: float = 0.0
	for child in _lines.get_children():
		if child is not Control or not child.visible:
			continue
		var step: float = child.get_combined_minimum_size().y
		if used > 0.0:
			step += separation
		if used + step > height:
			break
		used += step
		last = used
	# A single line taller than the window still shows, partly: better a clipped
	# sentence than an empty pane.
	return last if last > 0.0 else height


func _line(entry: Variant) -> Control:
	return ConsoleStyle.detail_line(
		entry, ConsoleMetrics.font_small(_scale), ConsoleMetrics.px(8, _scale)
	)
