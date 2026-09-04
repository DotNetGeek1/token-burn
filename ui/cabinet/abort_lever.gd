class_name AbortLever
extends Control

## The red lever on the left of the cabinet, made to pull. The handle is the
## plate's own painted handle, cut out of the artwork and slid down its channel
## on a pull, so it never stops looking like part of the machine.
##
## During a burn a pull is KILL; between prompts it is ABANDON (through the
## shell's confirmation), and with nothing on the bench it does nothing but
## thunk.

signal pulled

var _handle: TextureRect = null
var _cover: ColorRect = null
var _legend: PanelContainer = null
var _tag: Label = null
var _channel: Rect2 = Rect2()
var _handle_rect: Rect2 = Rect2()
var _pulling: bool = false
var _tap := TapGesture.new()
var _armed: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_cover = ColorRect.new()
	_cover.color = Color(0.03, 0.03, 0.03, 1.0)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)
	_handle = TextureRect.new()
	_handle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_handle.stretch_mode = TextureRect.STRETCH_SCALE
	_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_handle)
	# The legend plate under the channel: what a pull does right now, engraved
	# on a small plate like the painted label above the lever.
	_legend = PanelContainer.new()
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.add_theme_stylebox_override("panel", CabinetStyle.legend_plate())
	add_child(_legend)
	_tag = CabinetStyle.caption("", CabinetStyle.FONT_TINY, CabinetStyle.AMBER)
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_legend.add_child(_tag)
	gui_input.connect(_on_input)


## Cuts the handle out of the plate. `plate` is the plate's pixel rect in the
## parent; this control spans the lever region of it.
func layout(plate: Rect2, plate_texture: Texture2D) -> void:
	var region: Rect2 = AssetCatalog.cabinet_region("lever")
	position = plate.position + region.position * plate.size
	size = region.size * plate.size
	var channel: Rect2 = AssetCatalog.cabinet_region("lever_channel")
	var handle: Rect2 = AssetCatalog.cabinet_region("lever_handle")
	_channel = Rect2((channel.position - region.position) * plate.size, channel.size * plate.size)
	_handle_rect = Rect2((handle.position - region.position) * plate.size, handle.size * plate.size)
	# Only the painted handle is blacked out, so the pivot bracket under it
	# stays painted; the sliding handle draws over the bracket on a pull.
	_cover.position = _handle_rect.position
	_cover.size = _handle_rect.size
	_handle.position = _handle_rect.position
	_handle.size = _handle_rect.size
	if plate_texture != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = plate_texture
		var texture_size: Vector2 = plate_texture.get_size()
		atlas.region = Rect2(handle.position * texture_size, handle.size * texture_size)
		_handle.texture = atlas
	# The legend plate sits on the rail between the channel's foot and the
	# workflow keys, the width of the painted label above.
	var legend: Rect2 = AssetCatalog.cabinet_region("lever_legend")
	if legend.size.x <= 0.0:
		legend = Rect2(channel.position.x, channel.end.y + 0.005, channel.size.x, 0.0275)
	_legend.position = (legend.position - region.position) * plate.size
	_legend.size = legend.size * plate.size
	_tag.add_theme_font_size_override("font_size", clampi(int(_legend.size.y * 0.5), 7, 12))


## What a pull would do right now, engraved on the plate under the channel:
## KILL in red, ABANDON in brass, or a blank plate when there is nothing to pull for.
func set_armed(action: String) -> void:
	_armed = action
	_tag.text = action.to_upper()
	_tag.add_theme_color_override("font_color", CabinetStyle.RED if action == "KILL" else CabinetStyle.AMBER)
	tooltip_text = {
		"KILL": "Pull to kill the batch after the current stage.",
		"ABANDON": "Pull to abandon the contract on the bench.",
	}.get(action, "Nothing to abort.")


func _on_input(event: InputEvent) -> void:
	if _tap.feed(event):
		pull()
		accept_event()


func pull() -> void:
	if _pulling:
		return
	_pulling = true
	UiSound.play("alarm" if _armed == "KILL" else "tap")
	var travel: float = _channel.size.y - _handle_rect.size.y
	var tween: Tween = create_tween()
	tween.tween_property(_handle, "position:y", _handle_rect.position.y + travel, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func() -> void: pulled.emit())
	tween.tween_interval(0.18)
	tween.tween_property(_handle, "position:y", _handle_rect.position.y, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func() -> void: _pulling = false)
