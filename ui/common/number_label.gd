class_name NumberLabel
extends Label

@export var prefix: String = ""
@export var suffix: String = ""
@export var use_cash_format: bool = false
@export var use_token_format: bool = false

var _target_value: float = 0.0
var _display_value: float = 0.0
var _animating: bool = false
var _literal: String = ""


func set_value(value: float, animate: bool = true) -> void:
	_literal = ""
	_target_value = value
	if not animate:
		_display_value = value
		_refresh_text()
		return
	_animating = true


## For readouts that are not a single number ("1/12"). The label then keeps the
## text it was given instead of reformatting a value.
func set_literal(literal_text: String) -> void:
	_literal = literal_text
	_animating = false
	text = literal_text


func skip_animation() -> void:
	_display_value = _target_value
	_animating = false
	_refresh_text()


func _process(delta: float) -> void:
	if not _animating:
		return
	_display_value = lerpf(_display_value, _target_value, minf(1.0, delta * 8.0))
	if absf(_display_value - _target_value) < 0.5:
		_display_value = _target_value
		_animating = false
	_refresh_text()


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
