class_name TapGesture
extends RefCounted

## Tells a tap apart from a scroll drag.
##
## Every card-like surface in the game lives inside a ScrollContainer, so a
## surface that acts the moment a finger lands turns each flick of the list into
## an accidental activation. A gesture only counts as a tap when the finger lifts
## close to where it landed.
##
## Every pointer press reaches a Control twice. The project turns mouse clicks
## into touches (`emulate_touch_from_mouse`) and Android turns touches into mouse
## clicks (`emulate_mouse_from_touch`), so a press arrives once as the real
## event and once more as its emulated twin, tagged `DEVICE_ID_EMULATION`. The
## twin is dropped here: feeding both would let the emulated press re-arm a
## gesture a consumer had just cancelled, and the emulated release would fire a
## second tap. The real event alone carries the whole gesture.

## How far the finger may drift and still count as a tap, in pixels of the
## 1080-wide design viewport.
const DRAG_SLOP := 24.0

var _pressing: bool = false
var _origin: Vector2 = Vector2.ZERO
var _drift: float = 0.0


## Feeds one input event in. Returns true on the release that completes a tap.
func feed(event: InputEvent) -> bool:
	if is_emulated(event):
		return false
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin(event.position)
			return false
		return _release(event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin(event.position)
			return false
		return _release(event.position)
	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		if _pressing:
			_drift = maxf(_drift, event.position.distance_to(_origin))
	return false


## Whether a press is live: a finger has landed and not yet lifted.
func is_pressing() -> bool:
	return _pressing


## Abandons the press in progress, for when something else claims the gesture.
func cancel() -> void:
	_pressing = false


## Whether the engine synthesised this pointer event from another one (a touch
## from a mouse click, or a mouse click from a touch). Such events duplicate a
## press the control has already been handed.
static func is_emulated(event: InputEvent) -> bool:
	return event != null and event.device == InputEvent.DEVICE_ID_EMULATION


func _begin(position: Vector2) -> void:
	_pressing = true
	_origin = position
	_drift = 0.0


func _release(position: Vector2) -> bool:
	if not _pressing:
		return false
	_pressing = false
	_drift = maxf(_drift, position.distance_to(_origin))
	return _drift <= DRAG_SLOP
