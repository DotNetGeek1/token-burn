class_name WorkflowCard
extends PanelContainer

## A magnetic card on the workflow whiteboard. Cards in the tray carry modules;
## cards on the diagram carry slots. Both are genuine drag sources, while slot
## cards are also drop targets. The ordinary tap signal remains so the editor is
## fully usable on touch screens where a precise drag is less comfortable.

signal tapped(meta: Variant)
signal data_dropped(target_meta: Variant, data: Dictionary)

const ROLE_MODULE := "module"
const ROLE_SLOT := "slot"
const PAD := 8
const GAP := 2
## Width over height of a stuck-down note. Tray cards and diagram stages share
## this so a module looks like the same piece of paper on either side of the rail.
const PAPER_ASPECT := 0.84
const MIN_HEIGHT := 96.0

const PAPER_MODULE := Color("e7d98f")
const PAPER_STAGE := Color("dfe2d2")
const PAPER_EMPTY := Color("eef0e8")
const PAPER_BLOCKED := Color("dfb2aa")
const PAPER_OVERFLOW := Color("e4c48a")
const PAPER_SELECTED := Color("b9dcd2")
const PAPER_HOVER := Color("f1e7b8")
const INK := Color("17251f")
const INK_DIM := Color("46534d")
const INK_DANGER := Color("6f2529")

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

var meta: Variant = null
var role: String = ROLE_MODULE
var module_id: String = ""
var slot_index: int = -1
var blocked: bool = false
var overflow: bool = false

var _margin: MarginContainer = null
var _body: VBoxContainer = null
var _top: HBoxContainer = null
var _step: Label = null
var _name: Label = null
var _badge: Label = null
var _description: Label = null
var _filler: Control = null
var _status: Label = null
var _selected: bool = false
var _scale: float = 1.0
var _hovered: bool = false
var _pressed: bool = false
var _dragged: bool = false
var _press_origin: Vector2 = Vector2.ZERO


func _init() -> void:
	_build()


func _build() -> void:
	if _body != null:
		return
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	_margin = MarginContainer.new()
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_%s" % side, PAD)
	add_child(_margin)

	_body = VBoxContainer.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_constant_override("separation", GAP)
	_margin.add_child(_body)

	_top = HBoxContainer.new()
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_theme_constant_override("separation", GAP * 2)
	_body.add_child(_top)

	_step = ConsoleStyle.label("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_step.add_theme_font_override("font", UiThemeBuilder.header_font())
	_step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top.add_child(_step)

	_name = ConsoleStyle.label("", ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR)
	_name.add_theme_font_override("font", UiThemeBuilder.body_bold_font())
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.max_lines_visible = 1
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_name)

	_badge = ConsoleStyle.label("", ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR)
	_badge.add_theme_font_override("font", UiThemeBuilder.header_font())
	_badge.clip_text = true
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_top.add_child(_badge)

	_description = ConsoleStyle.label("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_description.add_theme_font_override("font", UiThemeBuilder.body_font())
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.max_lines_visible = 2
	_description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_body.add_child(_description)

	_filler = Control.new()
	_filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_filler)

	_status = ConsoleStyle.label("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_status.add_theme_font_override("font", UiThemeBuilder.header_font())
	_status.clip_text = true
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_body.add_child(_status)

	_apply_palette()


## Height of a note that is `width` wide, never shorter than the readable floor.
static func paper_height(width: float, scale: float = 1.0) -> float:
	return maxf(MIN_HEIGHT * scale, width / PAPER_ASPECT)


func set_card(entry: Dictionary) -> void:
	_build()
	meta = entry.get("meta", null)
	role = str(entry.get("role", ROLE_MODULE))
	module_id = str(entry.get("module_id", ""))
	slot_index = int(entry.get("slot_index", -1))
	blocked = bool(entry.get("blocked", false))
	overflow = bool(entry.get("overflow", false))
	_step.text = str(entry.get("step", "")).to_upper()
	_step.visible = _step.text != ""
	_name.text = str(entry.get("name", "")).to_upper()
	_badge.text = str(entry.get("badge", ""))
	_badge.visible = _badge.text != ""
	_top.visible = _step.visible or _badge.visible
	_description.text = str(entry.get("description", ""))
	_description.visible = _description.text != ""
	_status.text = str(entry.get("status", "")).to_upper()
	_status.visible = _status.text != ""
	mouse_default_cursor_shape = (
		Control.CURSOR_FORBIDDEN if blocked else Control.CURSOR_DRAG
	)
	_apply_palette()


func set_selected(selected: bool) -> void:
	_selected = selected
	_apply_palette()


func set_metrics(scale: float) -> void:
	_scale = scale
	var pad: int = ConsoleMetrics.px(PAD, scale)
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_%s" % side, pad)
	var gap: int = ConsoleMetrics.px(GAP, scale)
	_body.add_theme_constant_override("separation", gap)
	_top.add_theme_constant_override("separation", gap * 2)
	_step.add_theme_font_size_override("font_size", ConsoleMetrics.font_tiny(scale))
	_name.add_theme_font_size_override("font_size", ConsoleMetrics.font_small(scale))
	_badge.add_theme_font_size_override("font_size", ConsoleMetrics.font_small(scale))
	_description.add_theme_font_size_override("font_size", ConsoleMetrics.font_tiny(scale))
	_status.add_theme_font_size_override("font_size", ConsoleMetrics.font_tiny(scale))


func _gui_input(event: InputEvent) -> void:
	if blocked:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_pressed = true
			_dragged = false
			_press_origin = event.position
			grab_focus()
		elif _pressed and not _dragged:
			_pressed = false
			UiSound.play("tap")
			tapped.emit(meta)
		else:
			_pressed = false
	elif event is InputEventScreenDrag and _pressed:
		if event.position.distance_to(_press_origin) > 6.0 * _scale:
			_dragged = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_dragged = false
			_press_origin = event.position
			grab_focus()
		elif _pressed and not _dragged:
			_pressed = false
			UiSound.play("tap")
			tapped.emit(meta)
		else:
			_pressed = false
	elif event is InputEventMouseMotion and _pressed:
		if event.position.distance_to(_press_origin) > 6.0 * _scale:
			_dragged = true
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_SPACE]:
			UiSound.play("tap")
			tapped.emit(meta)
			accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if blocked:
		return null
	var data: Dictionary = {}
	if role == ROLE_MODULE and module_id != "":
		data = {"kind": ROLE_MODULE, "module_id": module_id}
	elif role == ROLE_SLOT and slot_index >= 0 and module_id != "":
		data = {"kind": ROLE_SLOT, "slot_index": slot_index}
	if data.is_empty():
		return null
	_dragged = true

	var preview := Label.new()
	preview.text = "  %s  " % _name.text
	preview.add_theme_font_override("font", UiThemeBuilder.body_bold_font())
	preview.add_theme_font_size_override("font_size", ConsoleMetrics.font_small(_scale))
	preview.add_theme_color_override("font_color", INK)
	preview.add_theme_stylebox_override("normal", _card_box(PAPER_HOVER, INK, 0.8))
	set_drag_preview(preview)
	return data


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if role != ROLE_SLOT or blocked or not data is Dictionary:
		return false
	var kind: String = str(Dictionary(data).get("kind", ""))
	if kind == ROLE_MODULE:
		return str(Dictionary(data).get("module_id", "")) != ""
	if kind == ROLE_SLOT:
		return int(Dictionary(data).get("slot_index", -1)) != slot_index
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _can_drop_data(Vector2.ZERO, data):
		UiSound.play("tap")
		data_dropped.emit(meta, Dictionary(data))


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovered = true
		_apply_palette()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovered = false
		_apply_palette()
	elif what in [NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT]:
		_apply_palette()


func _apply_palette() -> void:
	if _body == null:
		return
	var paper: Color = PAPER_MODULE if role == ROLE_MODULE else PAPER_STAGE
	var ink: Color = INK
	var border: float = 0.44
	if role == ROLE_SLOT and module_id == "":
		paper = PAPER_EMPTY
		border = 0.30
	if overflow and not blocked:
		paper = PAPER_OVERFLOW
		ink = INK_DANGER
		border = 0.55
	if blocked:
		paper = PAPER_BLOCKED
		ink = INK_DANGER
		border = 0.36
	if _selected:
		paper = PAPER_SELECTED
		border = 0.95
	if _hovered or has_focus():
		paper = PAPER_HOVER if not blocked else PAPER_BLOCKED.lightened(0.08)
		border = 0.82
	add_theme_stylebox_override("panel", _card_box(paper, ink, border))
	_step.add_theme_color_override("font_color", INK_DIM if not blocked else ink)
	_name.add_theme_color_override("font_color", ink)
	_badge.add_theme_color_override("font_color", ink)
	_description.add_theme_color_override("font_color", INK_DIM if not blocked else ink)
	_status.add_theme_color_override("font_color", INK_DIM if not blocked else ink)


func _card_box(paper: Color, ink: Color, border_alpha: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = paper
	box.border_color = Color(ink.r, ink.g, ink.b, border_alpha)
	box.set_border_width_all(1)
	box.set_corner_radius_all(1)
	box.shadow_color = Color(0.02, 0.03, 0.025, 0.30)
	box.shadow_size = 3
	box.shadow_offset = Vector2(2, 3)
	return box
