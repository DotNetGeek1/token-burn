class_name CabinetFrame
extends Control

## A region of the cabinet dressed in one of the kit's 9-slice frames: the CRT
## bezel, the telemetry frame, the deck plate, the backplane rail. The frame is
## a NinePatchRect drawn at a uniform scale chosen by the layout so its rim
## lands at a sensible thickness for the region's size (a NinePatchRect draws
## its corners at texture pixels otherwise, and a 110 px bezel would eat a
## 400 px CRT), and `content` is the Control left inside that rim for the live
## instruments. Children of the region go under `content`, never beside it.

var frame_key: String = ""
## Where the region's live content goes: the rect inside the frame's rim.
var content: Control = null

var _layout: CabinetLayout = null
var _patch: NinePatchRect = null


func _init(key: String, layout: CabinetLayout) -> void:
	frame_key = key
	_layout = layout
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_patch = NinePatchRect.new()
	_patch.name = "Frame"
	_patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_patch.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	_patch.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	add_child(_patch)
	content = Control.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(content)


func _ready() -> void:
	resized.connect(_fit)
	_fit()


func _fit() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var spec: Dictionary = _layout.frame_spec(frame_key, size)
	if spec.is_empty():
		_patch.visible = false
		content.position = Vector2.ZERO
		content.size = size
		return
	_patch.visible = true
	_patch.texture = spec["texture"]
	var margins: Array = Array(spec["margins"])
	_patch.patch_margin_left = int(margins[0])
	_patch.patch_margin_top = int(margins[1])
	_patch.patch_margin_right = int(margins[2])
	_patch.patch_margin_bottom = int(margins[3])
	var scale_factor: float = maxf(0.01, float(spec["scale"]))
	_patch.scale = Vector2(scale_factor, scale_factor)
	_patch.position = Vector2.ZERO
	_patch.size = size / scale_factor
	var inner: Rect2 = _layout.frame_content_rect(frame_key, size)
	content.position = inner.position
	content.size = inner.size


## The rim's on-screen thickness per side, `[left, top, right, bottom]`.
func lip() -> Array:
	return _layout.frame_lip_px(frame_key, size)
