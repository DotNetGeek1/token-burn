class_name TapGesture
extends RefCounted

## Tells a tap apart from a scroll drag.
##
## Every card-like surface in the game lives inside a ScrollContainer, so a
## surface that acts the moment a finger lands turns each flick of the list into
## an accidental activation. A gesture only counts as a tap when the finger lifts
## close to where it landed.

## How far the finger may drift and still count as a tap, in pixels of the
## 1080-wide design viewport.
const DRAG_SLOP := 24.0

var _pressing: bool = false
var _origin: Vector2 = Vector2.ZERO
var _drift: float = 0.0


## Feeds one input event in. Returns true on the release that completes a tap.
##
## Touch on Android arrives twice, once as a screen touch and again as an
## emulated mouse button, so a release is only reported while a press is live.
func feed(event: InputEvent) -> bool:
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


## Abandons the press in progress, for when something else claims the gesture.
func cancel() -> void:
	_pressing = false


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
