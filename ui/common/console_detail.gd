class_name ConsoleDetail
extends PanelContainer

## The pane under a `ConsoleTable` that expands the selected row.
##
## It reads as the machine answering a query: a prompt line naming the record,
## the facts printed underneath it as `KEY .... VALUE`, any warnings in red, and
## a single bracketed action at the bottom. Screens that use it never open a
## sheet over the top of themselves — the answer arrives in place.

signal action_pressed

const PAD := 10


## The bracketed action line. Disabled it still prints, so a blocked action says
## what it is rather than vanishing.
class ActionRow:
	extends Button

	var _label: Label = null

	func _init() -> void:
		text = ""
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(0, 26)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var margin := MarginContainer.new()
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_right", 8)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(margin)
		_label = ConsoleStyle.label("", ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR)
		margin.add_child(_label)

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


var _box: VBoxContainer = null
var _headline: Label = null
var _lines: VBoxContainer = null
var _action: ActionRow = null


func _ready() -> void:
	if _box == null:
		_build()


func _build() -> void:
	add_theme_stylebox_override("panel", ConsoleStyle.frame_box(0.24, 0.03))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, PAD)
	add_child(margin)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	margin.add_child(_box)

	_headline = ConsoleStyle.label("", ConsoleStyle.FONT_BODY, ConsoleStyle.PHOSPHOR)
	_headline.clip_text = true
	_box.add_child(_headline)

	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 2)
	_box.add_child(_lines)

	_action = ActionRow.new()
	_action.pressed.connect(func() -> void:
		UiSound.play("tap")
		action_pressed.emit()
	)
	_box.add_child(_action)


## `lines` entries are `{text}` for prose, `{stat, value, role}` for a keyed
## readout, and `{warn}` for a red line.
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


func clear(placeholder: String = "SELECT A ROW") -> void:
	if _box == null:
		_build()
	_headline.text = "> %s" % placeholder
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	_action.visible = false


func _line(entry: Variant) -> Control:
	if not entry is Dictionary:
		return ConsoleStyle.paragraph(str(entry))
	if entry.has("warn"):
		return ConsoleStyle.paragraph(
			"! %s" % str(entry["warn"]), ConsoleStyle.FONT_SMALL, ConsoleStyle.DANGER
		)
	if entry.has("stat"):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var key: Label = ConsoleStyle.label(
			str(entry["stat"]).to_upper(), ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR_DIM
		)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key)
		var value: Label = ConsoleStyle.label(
			str(entry.get("value", "")),
			ConsoleStyle.FONT_SMALL,
			Color(entry.get("color", ConsoleStyle.PHOSPHOR))
		)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		return row
	var text: String = str(entry.get("text", ""))
	if entry.has("rule"):
		text = "%s — %s" % [str(entry["rule"]), text] if text != "" else str(entry["rule"])
	if text.strip_edges() == "":
		return null
	return ConsoleStyle.paragraph(text)
