class_name NumberLabel
extends Label

## A figure that climbs to its new value rather than snapping, and brightens
## for a moment when the value went up. Token rates print through
## `NumberFormat.format_token_rate`, so they carry "/min" and go to scientific
## notation (`1.00e+10/min`) once they pass a billion.

## The value has settled on its target after an animated change.
signal settled(value: float)

@export var prefix: String = ""
@export var suffix: String = ""
@export var use_cash_format: bool = false
@export var use_token_format: bool = false
## How long a climb takes, in seconds. The same for a small nudge and a
## doubling, so a readout never lags behind a chain of upgrades.
@export var climb_seconds: float = 0.6
## Brightens to this colour while an increase is climbing, then settles back
## to the label's own font colour. Alpha 0 turns the flash off.
@export var increase_color: Color = Color(1.0, 0.96, 0.8, 1.0)

var _target_value: float = 0.0
var _display_value: float = 0.0
var _start_value: float = 0.0
var _elapsed: float = 0.0
var _animating: bool = false
var _literal: String = ""
var _rest_color: Color = Color.WHITE
var _has_rest_color: bool = false


func _ready() -> void:
	set_process(false)
	_refresh_text()


func set_value(value: float, animate: bool = true) -> void:
	_literal = ""
	_target_value = value
	if not animate or not is_inside_tree():
		_display_value = value
		_finish()
		return
	if is_equal_approx(_display_value, value):
		_finish()
		return
	if value > _display_value:
		_flash()
	_start_value = _display_value
	_elapsed = 0.0
	_animating = true
	set_process(true)


## For readouts that are not a single number ("1/12"). The label then keeps the
## text it was given instead of reformatting a value.
func set_literal(literal_text: String) -> void:
	_literal = literal_text
	_animating = false
	set_process(false)
	text = literal_text


func skip_animation() -> void:
	_display_value = _target_value
	_finish()


func value() -> float:
	return _target_value


func is_animating() -> bool:
	return _animating


func _process(delta: float) -> void:
	if not _animating:
		set_process(false)
		return
	_elapsed += delta
	var t: float = 1.0 if climb_seconds <= 0.0 else clampf(_elapsed / climb_seconds, 0.0, 1.0)
	# Ease out: the figure leaps at first and settles on the last digits, which
	# reads as "it went up" rather than "it is still counting".
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	_display_value = lerpf(_start_value, _target_value, eased)
	if t >= 1.0:
		_display_value = _target_value
		_finish()
		return
	_refresh_text()


func _finish() -> void:
	_animating = false
	set_process(false)
	_refresh_text()
	_restore_color()
	settled.emit(_target_value)


func _flash() -> void:
	if increase_color.a <= 0.0:
		return
	if not _has_rest_color:
		_rest_color = get_theme_color("font_color")
		_has_rest_color = true
	add_theme_color_override("font_color", increase_color)


func _restore_color() -> void:
	if _has_rest_color:
		add_theme_color_override("font_color", _rest_color)
		_has_rest_color = false


func _refresh_text() -> void:
	if _literal != "":
		text = _literal
		return
	var formatted: String
	if use_cash_format:
		formatted = NumberFormat.format_cash(_display_value)
	elif use_token_format:
		formatted = NumberFormat.format_token_rate(_display_value)
	else:
		formatted = NumberFormat.format(_display_value)
	text = "%s%s%s" % [prefix, formatted, suffix]
