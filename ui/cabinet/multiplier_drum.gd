class_name MultiplierDrum
extends PanelContainer

## The multiplier window beside the screen: the next burn's output multiplier
## set large in amber, ticking up beat by beat while a batch runs.

var _value: Label = null
var _sub: Label = null
var _caption: Label = null
var _shown: float = 1.0
var _tween: Tween = null


func _ready() -> void:
	add_theme_stylebox_override("panel", CabinetStyle.glass_box())
	clip_contents = true
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	_caption = CabinetStyle.caption("MULTIPLIER")
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_caption)
	_value = CabinetStyle.mono("×1.00", CabinetStyle.FONT_DRUM, CabinetStyle.AMBER)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_value)
	_sub = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_sub)
	add_child(CabinetStyle.crt_overlay())
	resized.connect(_fit)
	_fit()


func _fit() -> void:
	var drum: int = clampi(int(size.y * 0.42), 14, 44)
	_value.add_theme_font_size_override("font_size", drum)
	var tiny: int = clampi(int(size.y * 0.10), 8, 13)
	_sub.add_theme_font_size_override("font_size", tiny)
	_caption.add_theme_font_size_override("font_size", tiny)


## The resting reading: what the next burn is projected to multiply output by,
## with the workflow's own three multipliers under it.
func set_projection(output_mult: float, quality_mult: float, thermal_mult: float, boosted: bool) -> void:
	_show(output_mult, false)
	var parts: PackedStringArray = ["Q ×%.2f" % quality_mult, "T ×%.2f" % thermal_mult]
	if boosted:
		parts.append("BOOST")
	_sub.text = " · ".join(parts)
	_sub.add_theme_color_override("font_color", CabinetStyle.AMBER if boosted else CabinetStyle.PHOSPHOR_DIM)


## A beat in the batch: the drum spins from what it showed to what the stage made.
func show_beat(multiplier_after: float, label: String) -> void:
	_show(multiplier_after, true)
	_sub.text = label.to_upper()
	_sub.add_theme_color_override("font_color", CabinetStyle.PHOSPHOR)


func _show(value: float, animate: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not animate or absf(value - _shown) < 0.005:
		_shown = value
		_value.text = _format(value)
		return
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void:
		_shown = v
		_value.text = _format(v), _shown, value, 0.22)


func _format(value: float) -> String:
	if value >= 100.0:
		return "×%d" % int(round(value))
	return "×%.2f" % value if value < 10.0 else "×%.1f" % value
