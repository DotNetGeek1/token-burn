class_name ModuleCartridge
extends Control

## A module as a cartridge: the generated gunmetal frame over a window of glass
## tinted in the module's category colour, with its glyph, name and badge
## printed in the window. Lives in the MODULES bin and the market shelf; can be
## tapped to arm and dragged onto a dock bay to seat.

signal pressed

## Where the frame's window and label strip fall, as fractions of the drawn frame.
const WINDOW := Rect2(0.16, 0.085, 0.68, 0.62)
const STRIP := Rect2(0.16, 0.735, 0.68, 0.12)

var module_id: String = ""
var draggable: bool = true
var _frame: TextureRect = null
var _glass: CabinetStyle.ModuleScreen = null
var _strip: Panel = null
var _glyph: TextureRect = null
var _name: Label = null
var _badge: Label = null
var _outline: Panel = null
var _tap := TapGesture.new()


## Built in `_init` so a cartridge can be loaded before it is put on the glass.
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_glass = CabinetStyle.ModuleScreen.new()
	add_child(_glass)
	_strip = Panel.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	_glyph = CabinetStyle.glyph(null, 24.0)
	add_child(_glyph)
	_name = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.WHITE)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.clip_text = false
	_name.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(_name)
	_badge = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.AMBER)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_badge)
	_frame = TextureRect.new()
	_frame.texture = AssetCatalog.cabinet_texture("cartridge")
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	_outline = Panel.new()
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline.visible = false
	_outline.add_theme_stylebox_override("panel", CabinetStyle.frame(CabinetStyle.AMBER, 1.0, 0.0, 2))
	add_child(_outline)
	gui_input.connect(_on_input)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	if _frame == null or _frame.texture == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var texture_size: Vector2 = _frame.texture.get_size()
	var scale: float = minf(size.x / texture_size.x, size.y / texture_size.y)
	var drawn: Vector2 = texture_size * scale
	var origin: Vector2 = (size - drawn) * 0.5
	var window := Rect2(origin + WINDOW.position * drawn, WINDOW.size * drawn)
	var strip := Rect2(origin + STRIP.position * drawn, STRIP.size * drawn)
	_glass.position = window.position
	_glass.size = window.size
	_strip.position = strip.position
	_strip.size = strip.size
	var glyph_size: float = clampf(window.size.x * 0.5, 12.0, 64.0)
	_glyph.custom_minimum_size = Vector2.ONE * glyph_size
	_glyph.size = Vector2.ONE * glyph_size
	_glyph.position = window.position + Vector2((window.size.x - glyph_size) * 0.5, window.size.y * 0.12)
	# The name may wrap to a second line on a narrow cartridge; it is never let
	# down below 9 px, where it stops being a name.
	var font: int = clampi(int(window.size.x * 0.11), 9, 13)
	_name.add_theme_font_size_override("font_size", font)
	_name.position = window.position + Vector2(window.size.x * 0.05, window.size.y * 0.48)
	_name.size = Vector2(window.size.x * 0.9, window.size.y * 0.48)
	_badge.add_theme_font_size_override("font_size", clampi(int(strip.size.y * 0.6), 7, 12))
	_badge.position = strip.position
	_badge.size = strip.size
	_outline.position = origin + Vector2(2, 2)
	_outline.size = drawn - Vector2(4, 4)


func set_module(id: String) -> void:
	module_id = id
	var module: ModuleDefinition = ContentDatabase.get_module(id)
	var tint: Color = CabinetStyle.category_color(module.category if module != null else "")
	_glass.set_look(tint, module != null)
	var strip := StyleBoxFlat.new()
	strip.bg_color = Color(0.01, 0.02, 0.02, 1.0).lerp(tint, 0.08)
	_strip.add_theme_stylebox_override("panel", strip)
	if module == null:
		_name.text = id
		_badge.text = ""
		_glyph.texture = null
		return
	_name.text = module.name.to_upper()
	_badge.text = Simulation.get_module_badge(id).to_upper()
	_badge.add_theme_color_override("font_color", AssetCatalog.rarity_color(module.rarity))
	_glyph.texture = AssetCatalog.cabinet_module_glyph(module.category)
	_glyph.modulate = tint
	tooltip_text = Simulation.get_module_description(id)


func set_selected(selected: bool) -> void:
	_outline.visible = selected


func is_selected() -> bool:
	return _outline.visible


func _on_input(event: InputEvent) -> void:
	if _tap.feed(event):
		pressed.emit()
		accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if not draggable or module_id == "":
		return null
	_tap.cancel()
	var preview: Label = CabinetStyle.mono(_name.text, CabinetStyle.FONT_SMALL, CabinetStyle.WHITE)
	preview.add_theme_stylebox_override("normal", CabinetStyle.frame(CabinetStyle.PHOSPHOR, 0.9, 0.6))
	set_drag_preview(preview)
	return {"kind": "module", "module_id": module_id}
