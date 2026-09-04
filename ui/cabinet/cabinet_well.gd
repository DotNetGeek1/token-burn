class_name CabinetWell
extends PanelContainer

## A small glass well with an engraved caption and a body of text: the NEXT
## ACTION window, and anything else that is one caption over a few words.

var _caption: Label = null
var _body: Label = null
## Caption set before the labels exist, applied once they do.
var _caption_text: String = ""


func _ready() -> void:
	add_theme_stylebox_override("panel", CabinetStyle.glass_box())
	clip_contents = true
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	_caption = CabinetStyle.caption(_caption_text)
	column.add_child(_caption)
	_body = CabinetStyle.prose("", CabinetStyle.FONT_SMALL, CabinetStyle.PHOSPHOR)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(_body)
	add_child(CabinetStyle.crt_overlay(0.12))
	resized.connect(_fit)
	_fit()


## The painted glass can be a shallow strip, so the type is sized to it: the
## caption on one line at the top, the body in the two lines under it.
func _fit() -> void:
	if _caption == null or size.y <= 0.0:
		return
	var glass: StyleBoxFlat = CabinetStyle.glass_box()
	var pad: int = clampi(int(size.y * 0.06), 1, 4)
	glass.content_margin_top = pad
	glass.content_margin_bottom = pad
	add_theme_stylebox_override("panel", glass)
	_caption.add_theme_font_size_override("font_size", clampi(int(size.y * 0.16), 6, CabinetStyle.FONT_TINY))
	_body.add_theme_font_size_override("font_size", clampi(int(size.y * 0.21), 7, CabinetStyle.FONT_SMALL))


func set_caption(text: String) -> void:
	_caption_text = text.to_upper()
	if _caption != null:
		_caption.text = _caption_text


func set_body(text: String, color: Color = CabinetStyle.PHOSPHOR) -> void:
	if _body == null:
		return
	_body.text = text.to_upper()
	_body.add_theme_color_override("font_color", color)
