class_name ConsolePanel
extends PanelContainer

## A readout box down the right edge of the title terminal: a kicker, one large
## number and a caption, with an optional sparkline underneath.
##
## The numbers are real — lifetime counters from the profile, or live engine
## metrics. Only the trace is decoration, and it plots whatever samples it is
## actually given.

const SPARK_HEIGHT := 14
const SPARK_SAMPLES := 32


class Sparkline:
	extends Control

	var color: Color = ConsoleMenuRow.PHOSPHOR
	var samples: PackedFloat32Array = PackedFloat32Array()

	func _draw() -> void:
		if samples.size() < 2:
			return
		var low: float = samples[0]
		var high: float = samples[0]
		for value in samples:
			low = minf(low, value)
			high = maxf(high, value)
		var span: float = maxf(high - low, 0.0001)
		var points := PackedVector2Array()
		var step: float = size.x / float(samples.size() - 1)
		for i in range(samples.size()):
			var normalised: float = (samples[i] - low) / span
			points.append(Vector2(step * float(i), size.y - normalised * size.y))
		draw_polyline(points, Color(color.r, color.g, color.b, 0.85), 1.0, true)


var _margin: MarginContainer = null
var _box: VBoxContainer = null
var _kicker: Label = null
var _value: Label = null
var _caption: Label = null
var _spark: Sparkline = null


func _ready() -> void:
	_build()
	_style()


func setup(kicker: String, show_sparkline: bool = false) -> void:
	if _kicker == null:
		_build()
		_style()
	_kicker.text = kicker
	_spark.visible = show_sparkline


## Sized from the laptop screen it is printed on, like everything else on the
## glass. `scale_factor` is 1.0 at the reference screen height.
func set_metrics(scale_factor: float) -> void:
	if _margin == null:
		return
	_margin.add_theme_constant_override("margin_left", _px(8, scale_factor))
	_margin.add_theme_constant_override("margin_right", _px(8, scale_factor))
	_margin.add_theme_constant_override("margin_top", _px(5, scale_factor))
	_margin.add_theme_constant_override("margin_bottom", _px(5, scale_factor))
	_box.add_theme_constant_override("separation", _px(1, scale_factor))
	_kicker.add_theme_font_size_override("font_size", _px(9, scale_factor))
	_value.add_theme_font_size_override("font_size", _px(18, scale_factor))
	_caption.add_theme_font_size_override("font_size", _px(8, scale_factor))
	_spark.custom_minimum_size = Vector2(0, _px(SPARK_HEIGHT, scale_factor))


static func _px(reference_units: int, scale_factor: float) -> int:
	return maxi(1, int(round(float(reference_units) * scale_factor)))


func set_readout(value: String, caption: String = "") -> void:
	if _value == null:
		return
	_value.text = value
	_caption.text = caption
	_caption.visible = caption.strip_edges() != ""


## Pushes one live sample onto the trace, dropping the oldest once the window is
## full.
func push_sample(value: float) -> void:
	if _spark == null or not _spark.visible:
		return
	_spark.samples.append(value)
	while _spark.samples.size() > SPARK_SAMPLES:
		_spark.samples.remove_at(0)
	_spark.queue_redraw()


func _build() -> void:
	_margin = MarginContainer.new()
	_margin.add_theme_constant_override("margin_left", 8)
	_margin.add_theme_constant_override("margin_right", 8)
	_margin.add_theme_constant_override("margin_top", 5)
	_margin.add_theme_constant_override("margin_bottom", 5)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(box)
	_box = box

	_kicker = _line(9, ConsoleMenuRow.PHOSPHOR_DIM)
	box.add_child(_kicker)

	_value = _line(18, ConsoleMenuRow.PHOSPHOR)
	box.add_child(_value)

	_caption = _line(8, ConsoleMenuRow.PHOSPHOR_DIM)
	_caption.visible = false
	box.add_child(_caption)

	_spark = Sparkline.new()
	_spark.custom_minimum_size = Vector2(0, SPARK_HEIGHT)
	_spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spark.visible = false
	box.add_child(_spark)


func _line(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font: Font = UiThemeBuilder.mono_font()
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _style() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.42, 0.92, 0.60, 0.04)
	box.border_color = Color(0.42, 0.92, 0.60, 0.28)
	box.set_border_width_all(1)
	box.set_corner_radius_all(0)
	add_theme_stylebox_override("panel", box)
