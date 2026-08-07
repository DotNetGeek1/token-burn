class_name HeatGauge
extends Control

## Analog heat meter for the rig.
##
## Heat used to be one more horizontal bar in a stack of four, which made the
## number that can end a run look exactly like the number that measures polish.
## A needle over a green/amber/red dial reads at a glance, and once it is in the
## red it shakes, which a bar cannot do.

const ARC_START := 0.75 * PI
const ARC_SWEEP := 1.5 * PI
const WARNING_RATIO := 0.62
const DANGER_RATIO := 0.85
const JITTER_DEGREES := 3.5
## Dial size when a scene does not ask for one. The office panel authors a
## smaller gauge, so this is a default rather than a floor.
const DEFAULT_SIZE := Vector2(200, 178)

## How much of the housing's recessed face the dial track fills, and how thick that
## track is as a share of the face. Kept clear of the bezel so the machined rim of
## the artwork stays visible around the reading.
const FACE_FILL := 0.78
const FACE_TRACK := 0.22

var _ratio: float = 0.0
var _shown_ratio: float = 0.0
var _jitter: float = 0.0
var _needle_tween: Tween = null
## Housing art and the sub-rects to draw into, when the gauge is mounted on the
## rig. Empty elsewhere: the office panel wants a bare dial in a row of bars.
var _housing: Dictionary = {}


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = DEFAULT_SIZE
	set_process(false)


## Mounts the dial in a photographed instrument housing. The needle and the zones
## are then painted into the housing's empty face and its readout window, so the
## gauge reads as part of the machine instead of a widget lying on top of it.
func set_housing(housing: Dictionary) -> void:
	_housing = housing
	queue_redraw()


func setup(heat: float, capacity: float) -> void:
	var target: float = clampf(heat / maxf(1.0, capacity), 0.0, 1.15)
	if is_equal_approx(target, _ratio):
		return
	_ratio = target
	if _needle_tween != null and _needle_tween.is_valid():
		_needle_tween.kill()
	# Needles have mass: it swings to the new reading rather than teleporting.
	_needle_tween = create_tween()
	_needle_tween.tween_property(self, "_shown_ratio", _ratio, 0.45).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	_needle_tween.tween_callback(queue_redraw)
	set_process(true)


func ratio() -> float:
	return _ratio


func is_critical() -> bool:
	return _ratio >= DANGER_RATIO


func _process(_delta: float) -> void:
	_jitter = randf_range(-JITTER_DEGREES, JITTER_DEGREES) if is_critical() else 0.0
	queue_redraw()
	# Only a hot rig needs to keep repainting; a settled needle can stop.
	var swinging: bool = _needle_tween != null and _needle_tween.is_valid() and _needle_tween.is_running()
	if not is_critical() and not swinging:
		set_process(false)


func _draw() -> void:
	# A 270-degree dial reaches below its centre, and the readout sits below the
	# dial, so the radius leaves room for the track, the ticks and that line.
	var centre := Vector2(size.x * 0.5, size.y * 0.46)
	var radius: float = minf(size.x * 0.38, size.y * 0.37)
	var track_width: float = maxf(7.0, radius * 0.18)
	var mounted: bool = not _housing.is_empty()
	if mounted:
		draw_texture_rect(_housing["texture"], Rect2(Vector2.ZERO, size), false)
		var face_centre: Vector2 = _housing.get("face_centre", Vector2(0.5, 0.46))
		var face: float = float(_housing.get("face_radius", 0.3)) * minf(size.x, size.y)
		centre = face_centre * size
		radius = face * FACE_FILL
		track_width = maxf(6.0, face * FACE_TRACK)
	else:
		# Stands in for the housing's recessed face when the gauge is drawn bare.
		draw_circle(centre, radius + track_width * 0.9, Color(0, 0, 0, 0.55))
	draw_arc(
		centre, radius, ARC_START, ARC_START + ARC_SWEEP, 64,
		UiThemeBuilder.color("stroke_dim"), track_width, true
	)
	_draw_zone(centre, radius, track_width, 0.0, WARNING_RATIO, "green")
	_draw_zone(centre, radius, track_width, WARNING_RATIO, DANGER_RATIO, "orange")
	_draw_zone(centre, radius, track_width, DANGER_RATIO, 1.0, "red")

	# Ticks every 10%, longer every 25%, so the dial has something to read
	# against rather than just a coloured band.
	for step in range(11):
		var t: float = float(step) / 10.0
		var angle: float = ARC_START + ARC_SWEEP * t
		var direction := Vector2(cos(angle), sin(angle))
		var long_tick: bool = step % 5 == 0 or step == 10
		var inner: float = radius - track_width * (1.15 if long_tick else 0.85)
		draw_line(
			centre + direction * inner,
			centre + direction * (radius - track_width * 0.55),
			Color(1, 1, 1, 0.4 if long_tick else 0.2),
			2.0 if long_tick else 1.0
		)

	_draw_needle(centre, radius, track_width)
	_draw_readout(centre, radius)


func _draw_zone(
	centre: Vector2, radius: float, width: float, from: float, to: float, color_key: String
) -> void:
	var accent: Color = UiThemeBuilder.color(color_key)
	# The zone lights up only once the needle is in it, so a cool rig is not a
	# wall of colour competing with everything else on the board.
	var live: bool = _ratio >= from
	var alpha: float = 0.95 if live else 0.28
	draw_arc(
		centre, radius,
		ARC_START + ARC_SWEEP * from, ARC_START + ARC_SWEEP * to,
		32, Color(accent.r, accent.g, accent.b, alpha), width, true
	)


func _draw_needle(centre: Vector2, radius: float, width: float) -> void:
	var clamped: float = clampf(_shown_ratio, 0.0, 1.0)
	var angle: float = ARC_START + ARC_SWEEP * clamped + deg_to_rad(_jitter)
	var direction := Vector2(cos(angle), sin(angle))
	var accent: Color = _needle_color()
	var tip: Vector2 = centre + direction * (radius - width * 0.4)
	var tail: Vector2 = centre - direction * (radius * 0.18)
	draw_line(tail, tip, Color(0, 0, 0, 0.7), 8.0)
	draw_line(tail, tip, accent, 4.5)
	draw_circle(centre, width * 0.62, UiThemeBuilder.color("bg_panel"))
	draw_circle(centre, width * 0.42, accent)


func _needle_color() -> Color:
	if _ratio >= DANGER_RATIO:
		return UiThemeBuilder.color("red")
	if _ratio >= WARNING_RATIO:
		return UiThemeBuilder.color("orange")
	return UiThemeBuilder.color("white")


func _draw_readout(centre: Vector2, radius: float) -> void:
	var header: Font = UiThemeBuilder.header_font()
	if header == null:
		header = ThemeDB.fallback_font
	# The readout sits clear of the dial, below where the needle can reach.
	var value: String = "%d%%" % int(round(_ratio * 100.0))
	# Type tracks the dial so a compact gauge is not overrun by its own readout.
	var value_size: int = int(clampf(radius * 0.52, 20.0, 34.0))
	var baseline: float = size.y - 6.0
	var value_centre: float = centre.x
	var window: Rect2 = _housing.get("readout", Rect2())
	if window.size.y > 0.0:
		# Into the housing's readout window rather than onto the plate below it.
		var pixels := Rect2(window.position * size, window.size * size)
		value_size = int(clampf(pixels.size.y * 0.78, 11.0, 34.0))
		baseline = pixels.position.y + pixels.size.y * 0.5 + float(value_size) * 0.36
		value_centre = pixels.position.x + pixels.size.x * 0.5
	var value_width: float = header.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, value_size).x
	draw_string(
		header,
		Vector2(value_centre - value_width * 0.5, baseline),
		value,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		value_size,
		_needle_color()
	)
	var label: String = "HEAT"
	var label_size: int = int(clampf(radius * 0.3, 17.0, 22.0))
	var label_width: float = header.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
	draw_string(
		header,
		Vector2(centre.x - label_width * 0.5, centre.y - radius * 0.44),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		label_size,
		UiThemeBuilder.color("grey")
	)
