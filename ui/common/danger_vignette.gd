class_name DangerVignette
extends TextureRect

## Full-screen red breathing edge for critical heat.
##
## A beacon inside the rig can be scrolled past or glanced over. Once heat is
## past its throttle line the whole screen breathes red, which cannot be. The
## office screen mounts one too, so danger reads from home without opening the
## board.

const PULSE_HIGH := 0.55
const PULSE_LOW := 0.12
const PULSE_SECONDS := 0.5

var _tween: Tween = null
var _pulsing: bool = false


## Mounts a vignette filling `host`, drawn over its existing content.
static func mount(host: Control) -> DangerVignette:
	var red: Color = UiThemeBuilder.semantic("danger")
	var vignette := DangerVignette.new()
	vignette.name = "DangerVignette"
	vignette.texture = UiFx.vignette(Color(red.r, red.g, red.b, 0.85), 0.5)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.modulate.a = 0.0
	vignette.visible = false
	host.add_child(vignette)
	return vignette


## Idempotent: repeated calls with the same state leave the tween alone, so a
## per-tick refresh does not restart the pulse every frame.
func set_alarming(alarming: bool) -> void:
	if alarming == _pulsing:
		return
	_pulsing = alarming
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not alarming:
		_tween = create_tween()
		_tween.tween_property(self, "modulate:a", 0.0, 0.4)
		_tween.tween_callback(func() -> void: visible = false)
		return
	visible = true
	_tween = create_tween().set_loops()
	_tween.tween_property(self, "modulate:a", PULSE_HIGH, PULSE_SECONDS).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(self, "modulate:a", PULSE_LOW, PULSE_SECONDS).set_trans(Tween.TRANS_SINE)
