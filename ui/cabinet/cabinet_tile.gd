class_name CabinetTile
extends PanelContainer

## A selectable line on the glass for anything that is not a cartridge or a
## paper tag: a hardware upgrade on the market shelf, a perk on the rack. Name
## and a sub-line on the left, the figure that decides it on the right.

signal pressed(meta: Variant)

var meta: Variant = null
var _accent: Color = CabinetStyle.PHOSPHOR
var _selected: bool = false
var _glyph: TextureRect = null
var _marker: Label = null
var _name: Label = null
var _sub: Label = null
var _note: Label = null
var _figure: Label = null
var _status: Label = null
var _right: VBoxContainer = null
var _sub_text: String = ""
var _status_text: String = ""
var _tap: TapGesture = TapGesture.new()

## Under this width the right-hand column is folded into the sub-line, so the
## name keeps enough room to read on a handset's narrow racks.
const FOLD_WIDTH := 170.0


## Built in `_init` so a tile can be filled before it is put on the glass.
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	# The pick marker: a notch that only the selected line carries, so the
	# selection reads by shape as well as by the frame's colour.
	_marker = CabinetStyle.mono("►", CabinetStyle.FONT_TINY, CabinetStyle.WHITE)
	_marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_marker.visible = false
	_keep_width(_marker)
	row.add_child(_marker)
	_glyph = CabinetStyle.glyph(null, 16.0)
	_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_glyph)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	_name = CabinetStyle.mono("", CabinetStyle.FONT_SMALL, CabinetStyle.WHITE)
	text.add_child(_name)
	_sub = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
	text.add_child(_sub)
	# A third line for rows that have more to say than a sub-line holds (the
	# SYSTEMS shelf's stat delta). Hidden unless the entry fills it.
	_note = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR)
	_note.visible = false
	text.add_child(_note)
	_right = VBoxContainer.new()
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right.add_theme_constant_override("separation", 0)
	row.add_child(_right)
	_figure = CabinetStyle.mono("", CabinetStyle.FONT_SMALL, CabinetStyle.PHOSPHOR)
	_figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_keep_width(_figure)
	_right.add_child(_figure)
	_status = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_keep_width(_status)
	_right.add_child(_status)
	gui_input.connect(_on_input)
	resized.connect(_fold)
	_restyle()


## Narrow tiles fold the status into the sub-line and drop an empty figure
## column, otherwise the fixed-width right column eats the name.
func _fold() -> void:
	var narrow: bool = size.x > 0.0 and size.x < FOLD_WIDTH
	if narrow:
		var parts: PackedStringArray = []
		if _sub_text != "":
			parts.append(_sub_text)
		if _status_text != "":
			parts.append(_status_text)
		_sub.text = " · ".join(parts)
		_status.visible = false
		_right.visible = _figure.text != ""
	else:
		_sub.text = _sub_text
		_status.visible = _status_text != ""
		_right.visible = true
	_sub.visible = _sub.text != ""


## The figure column keeps its width; the name column is what gives way. A
## clipping Label reports a 1 px minimum, so left to clip the price would
## vanish into the expanding text column beside it.
static func _keep_width(label: Label) -> void:
	label.clip_text = false
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING


## `entry` keys: meta, name, sub, note, figure, figure_color, status,
## status_color, icon, icon_size (px, default 16), icon_tint (default: the
## accent; pass WHITE for painted art), accent, tooltip.
func set_entry(entry: Dictionary) -> void:
	meta = entry.get("meta")
	_name.text = str(entry.get("name", ""))
	_sub_text = str(entry.get("sub", ""))
	_status_text = str(entry.get("status", ""))
	_note.text = str(entry.get("note", ""))
	_note.visible = _note.text != ""
	_note.add_theme_color_override("font_color", Color(entry.get("note_color", CabinetStyle.PHOSPHOR)))
	_figure.text = str(entry.get("figure", ""))
	_figure.add_theme_color_override("font_color", Color(entry.get("figure_color", CabinetStyle.PHOSPHOR)))
	_status.text = _status_text
	_status.add_theme_color_override("font_color", Color(entry.get("status_color", CabinetStyle.PHOSPHOR_DIM)))
	var icon: Variant = entry.get("icon")
	_glyph.texture = icon if icon is Texture2D else null
	_glyph.visible = _glyph.texture != null
	var icon_size: float = maxf(8.0, float(entry.get("icon_size", 16.0)))
	_glyph.custom_minimum_size = Vector2(icon_size, icon_size)
	_accent = Color(entry.get("accent", CabinetStyle.PHOSPHOR))
	_glyph.modulate = Color(entry.get("icon_tint", _accent))
	tooltip_text = str(entry.get("tooltip", ""))
	_fold()
	_restyle()


func set_selected(selected: bool) -> void:
	_selected = selected
	_restyle()


func is_selected() -> bool:
	return _selected


func _restyle() -> void:
	# Selected: a full 2 px frame plus the notch; unselected: a hairline with
	# the accent rail on the left. Two shapes, not two colours.
	var box: StyleBoxFlat = CabinetStyle.frame(_accent if _selected else CabinetStyle.PHOSPHOR, 0.95 if _selected else 0.18, 0.10 if _selected else 0.03, 2 if _selected else 1)
	box.border_width_left = 4 if _selected else 3
	if _marker != null:
		_marker.visible = _selected
		_marker.add_theme_color_override("font_color", _accent if _selected else CabinetStyle.WHITE)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	add_theme_stylebox_override("panel", box)


func _on_input(event: InputEvent) -> void:
	if _tap.feed(event):
		pressed.emit(meta)
		accept_event()
