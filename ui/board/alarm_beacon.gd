class_name AlarmBeacon
extends Control

## Rotating warning light for the rig.
##
## Critical heat is the one state on the board the player must not miss, and a
## bar going orange is easy to miss. This spins a light cone, pulses the lamp,
## and sounds a klaxon on the way up, then goes quiet again once the rig cools.

const KLAXON_INTERVAL := 1.35
const BEAM_LENGTH := 330.0
const BEAM_HALF_WIDTH := 46.0

@onready var _cones: Node2D = $Cones
@onready var _lamp: TextureRect = $Lamp
@onready var _glow: TextureRect = $Glow

var _active: bool = false
var _spin: Tween = null
var _pulse: Tween = null
var _klaxon: Timer = null


func _ready() -> void:
	_lamp.texture = AssetCatalog.rig_texture("alarm_beacon")
	_glow.texture = _glow_texture()
	# The lamp art arrives on an opaque near-black field. Additive blending drops
	# that field for free and is also how a light should composite anyway.
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_lamp.material = additive
	_glow.material = additive
	_build_cones()
	_klaxon = Timer.new()
	_klaxon.wait_time = KLAXON_INTERVAL
	_klaxon.timeout.connect(func() -> void: UiSound.play("alarm"))
	add_child(_klaxon)
	modulate.a = 0.0
	visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout()


func _layout() -> void:
	_cones.position = Vector2(size.x * 0.5, size.y * 0.44)
	_cones.scale = Vector2.ONE * maxf(0.4, size.x / 96.0)


## Two opposed beams, which is what a single rotating mirror actually throws. The
## shape is a trapezoid so it widens with distance, and the fade comes from a
## gradient sampled along its length, which is smoother than interpolating vertex
## colours across a triangle.
func _build_cones() -> void:
	var red: Color = UiThemeBuilder.color("red")
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var falloff: Texture2D = _beam_texture()
	for direction in [1.0, -1.0]:
		var length: float = BEAM_LENGTH * direction
		var beam := Polygon2D.new()
		beam.material = additive
		beam.texture = falloff
		beam.color = Color(red.r, red.g, red.b, 0.5)
		beam.polygon = PackedVector2Array([
			Vector2(0, -7),
			Vector2(length, -BEAM_HALF_WIDTH),
			Vector2(length, BEAM_HALF_WIDTH),
			Vector2(0, 7),
		])
		var width: float = float(falloff.get_width())
		var height: float = float(falloff.get_height())
		beam.uv = PackedVector2Array([
			Vector2(0, 0),
			Vector2(width, 0),
			Vector2(width, height),
			Vector2(0, height),
		])
		_cones.add_child(beam)


static func _beam_texture() -> Texture2D:
	return UiFx.beam_falloff()


static func _glow_texture() -> Texture2D:
	return UiFx.radial_dot(96, 0.25)


## `severity` scales how fast the light spins and how hard the lamp pulses, so
## "nearly too hot" and "about to throttle" do not look identical.
func set_alarm(active: bool, severity: float = 1.0) -> void:
	if active == _active:
		if active:
			_apply_severity(severity)
		return
	_active = active
	if active:
		visible = true
		_layout()
		_apply_severity(severity)
		_klaxon.start()
		UiSound.play("alarm")
		var fade: Tween = create_tween()
		fade.tween_property(self, "modulate:a", 1.0, 0.25)
	else:
		_klaxon.stop()
		if _spin != null and _spin.is_valid():
			_spin.kill()
		if _pulse != null and _pulse.is_valid():
			_pulse.kill()
		var fade: Tween = create_tween()
		fade.tween_property(self, "modulate:a", 0.0, 0.35)
		fade.tween_callback(func() -> void: visible = false)


func _apply_severity(severity: float) -> void:
	var urgency: float = clampf(severity, 0.0, 1.0)
	var revolution: float = lerpf(1.5, 0.65, urgency)
	if _spin == null or not _spin.is_valid():
		_spin = create_tween().set_loops()
		_spin.tween_method(_set_cone_rotation, 0.0, TAU, revolution)
	if _pulse == null or not _pulse.is_valid():
		var beat: float = lerpf(0.6, 0.28, urgency)
		_pulse = create_tween().set_loops()
		_pulse.tween_property(_glow, "modulate:a", 1.0, beat).set_trans(Tween.TRANS_SINE)
		_pulse.parallel().tween_property(_lamp, "modulate", Color(1.4, 1.0, 1.0), beat)
		_pulse.tween_property(_glow, "modulate:a", 0.25, beat).set_trans(Tween.TRANS_SINE)
		_pulse.parallel().tween_property(_lamp, "modulate", Color(0.7, 0.7, 0.75), beat)
	_klaxon.wait_time = lerpf(2.2, 1.0, urgency)


func _set_cone_rotation(value: float) -> void:
	_cones.rotation = value
