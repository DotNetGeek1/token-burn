class_name InvestorTargetPanel
extends PanelContainer

## Run-level investor target: delivered tokens, a pace notch, and ahead/behind.

const DELIVERY_CLIMB_SECONDS := 0.55
const PACE_EPSILON := 0.02

var _header: Label = null
var _target_name: Label = null
var _figures: Label = null
var _pace: Label = null
var _rounds_left: Label = null
var _bar: Control = null

var _shown_ratio: float = 0.0
var _target_ratio: float = 0.0
var _pace_ratio: float = 0.0
## Where the running climb is heading; differs from _target_ratio only while
## a fresh reading has not yet been retargeted.
var _climb_target: float = 0.0
var _climb_tween: Tween = null


func _ready() -> void:
	add_theme_stylebox_override("panel", CabinetStyle.glass_box())
	clip_contents = true
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 1)
	add_child(column)
	_header = CabinetStyle.caption("", CabinetStyle.FONT_TINY, CabinetStyle.AMBER)
	column.add_child(_header)
	_target_name = CabinetStyle.caption("", CabinetStyle.FONT_TINY, CabinetStyle.AMBER_DIM)
	column.add_child(_target_name)
	column.add_child(CabinetStyle.rule(CabinetStyle.AMBER, 0.35))
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.draw.connect(_draw_bar)
	column.add_child(_bar)
	_figures = CabinetStyle.mono("0 / 0", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR)
	_figures.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_figures)
	_pace = CabinetStyle.mono("ON PACE", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR)
	_pace.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_pace)
	_rounds_left = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
	_rounds_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_rounds_left)
	add_child(CabinetStyle.crt_overlay(0.12))
	resized.connect(_on_resized)


func set_view(data: Dictionary, snap: bool = false) -> void:
	if data.is_empty():
		visible = false
		return
	visible = true
	var level: int = int(data.get("level", 1))
	_header.text = "INVESTOR // LVL %d" % level
	_target_name.text = str(data.get("target_name", "")).to_upper()
	var total: float = maxf(1.0, float(data.get("total_burn", 1.0)))
	var delivered: float = float(data.get("delivered", 0.0))
	_target_ratio = clampf(delivered / total, 0.0, 1.0)
	_pace_ratio = clampf(float(data.get("pace_ratio", 0.0)), 0.0, 1.0)
	_figures.text = "%s / %s  %d%%" % [
		NumberFormat.format(delivered),
		NumberFormat.format(total),
		int(round(_target_ratio * 100.0)),
	]
	_pace.text = _pace_line(data)
	_pace.add_theme_color_override("font_color", _pace_color(str(data.get("pace_label", "on_pace"))))
	var remaining: int = int(data.get("rounds_remaining", 0))
	_rounds_left.text = "%d ROUNDS LEFT" % remaining if remaining > 0 else "DEADLINE ROUND"
	if snap:
		_kill_climb()
		_shown_ratio = _target_ratio
		_bar.queue_redraw()
		return
	_retarget_ratio(_target_ratio)


## The panel is short on the compact and handset rails: drop the target name
## first, then the rounds-left line, before the bar or the pace line give way.
func _on_resized() -> void:
	var font: Font = _header.get_theme_font("font")
	if font == null:
		return
	var line_h: float = font.get_height(CabinetStyle.FONT_TINY) + 1.0
	var box: StyleBox = get_theme_stylebox("panel")
	var inner_h: float = size.y - (box.get_minimum_size().y if box != null else 0.0)
	# Header, rule, bar minimum, figures, pace: the rows that always print.
	var fixed_h: float = line_h * 3.0 + 2.0 + _bar.custom_minimum_size.y
	var spare: float = inner_h - fixed_h
	_target_name.visible = spare >= line_h * 2.0
	_rounds_left.visible = spare >= line_h


func _pace_line(data: Dictionary) -> String:
	var label: String = str(data.get("pace_label", "on_pace"))
	var rounds: float = absf(float(data.get("pace_rounds_delta", 0.0)))
	var figure: String = "%.1f" % rounds
	match label:
		"ahead":
			return "▲ AHEAD %s ROUNDS" % figure
		"behind":
			return "▼ BEHIND %s ROUNDS" % figure
	return "ON PACE"


func _pace_color(label: String) -> Color:
	match label:
		"ahead":
			return CabinetStyle.PHOSPHOR
		"behind":
			return CabinetStyle.RED
	return CabinetStyle.AMBER


func _fill_color() -> Color:
	if _shown_ratio > _pace_ratio + PACE_EPSILON:
		return CabinetStyle.PHOSPHOR
	if _shown_ratio < _pace_ratio - PACE_EPSILON:
		return CabinetStyle.RED
	return CabinetStyle.AMBER


func _kill_climb() -> void:
	if _climb_tween != null and _climb_tween.is_valid():
		_climb_tween.kill()
	_climb_tween = null


## A rise climbs over DELIVERY_CLIMB_SECONDS; a fall (a new level's fresh
## target) snaps. A refresh landing on the figure already being climbed to
## leaves the climb running rather than restarting it.
func _retarget_ratio(target: float) -> void:
	target = clampf(target, 0.0, 1.0)
	var climbing: bool = _climb_tween != null and _climb_tween.is_valid() and _climb_tween.is_running()
	if climbing and is_equal_approx(target, _climb_target):
		_bar.queue_redraw()
		return
	_kill_climb()
	_climb_target = target
	var can_animate: bool = (
		is_inside_tree() and target > _shown_ratio and not is_equal_approx(target, _shown_ratio)
	)
	if not can_animate:
		_shown_ratio = target
		_bar.queue_redraw()
		return
	_climb_tween = create_tween()
	_climb_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_climb_tween.tween_method(_show_ratio, _shown_ratio, target, DELIVERY_CLIMB_SECONDS)
	_climb_tween.finished.connect(_on_ratio_settled)


func _show_ratio(value: float) -> void:
	_shown_ratio = clampf(value, 0.0, 1.0)
	_bar.queue_redraw()


func _on_ratio_settled() -> void:
	_shown_ratio = _climb_target
	_climb_tween = null
	_bar.queue_redraw()


func _draw_bar() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, _bar.size)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	_bar.draw_rect(rect, Color(CabinetStyle.PHOSPHOR.r, CabinetStyle.PHOSPHOR.g, CabinetStyle.PHOSPHOR.b, 0.12))
	var fill_w: float = _shown_ratio * rect.size.x
	if fill_w > 0.0:
		_bar.draw_rect(Rect2(0.0, 0.0, fill_w, rect.size.y), _fill_color())
	var notch_x: float = _pace_ratio * rect.size.x
	_bar.draw_line(
		Vector2(notch_x, -1.0),
		Vector2(notch_x, rect.size.y + 1.0),
		Color(1.0, 1.0, 1.0, 0.55),
		1.0
	)
