class_name ConsoleDetail
extends PanelContainer

signal action_pressed

const PAD := 10
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
var _headline: Label = null
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
	_headline = ConsoleStyle.label("", ConsoleStyle.FONT_BODY, ConsoleStyle.PHOSPHOR)
	_headline.clip_text = true
	_box.add_child(_headline)
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
	_action.apply_metrics(scale)
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
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	_action.visible = false
	call_deferred("_fit_lines")


## The description window: as tall as its lines want, up to the share of the
## screen it can take without squeezing out the table above or the action row
## below it.
func _fit_lines() -> void:
	if _scroll == null:
		return
	var cap: float = 240.0
	var viewport: Vector2 = get_viewport_rect().size
	if viewport.y > 1.0:
		cap = viewport.y * 0.38
	var wanted: float = _lines.get_combined_minimum_size().y
	_scroll.custom_minimum_size = Vector2(0.0, minf(wanted, cap))


func _line(entry: Variant) -> Control:
	return ConsoleStyle.detail_line(
		entry, ConsoleMetrics.font_small(_scale), ConsoleMetrics.px(8, _scale)
	)
