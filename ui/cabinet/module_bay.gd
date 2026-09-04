class_name ModuleBay
extends Control

## One socket of the module dock. A live bay holds a module as a landscape
## cartridge — the generated gunmetal frame around a gridded screen glowing in
## the module's category colour, with its name, glyph and rarity pips on the
## glass and the edge connector hanging below. An empty live bay shows a dead
## cartridge; bays past the board's slot count show the bare socket. Tapping
## selects, dragging one bay onto another swaps, and a cartridge dragged from
## the MODULES bin seats itself here.

signal pressed(index: int)
## `payload` is the drag dictionary: `{"kind": "module", "module_id"}` from the
## bin, or `{"kind": "slot", "slot_index"}` from another bay.
signal dropped(payload: Dictionary, index: int)

const RARITY_LEVEL := {"common": 1, "uncommon": 2, "rare": 3, "epic": 4, "legendary": 5}
## Where the frame's window, top tab and body fall, as fractions of the texture.
const WINDOW := Rect2(0.064, 0.141, 0.870, 0.644)
const TAB := Rect2(0.42, 0.0, 0.16, 0.115)
## The frame body ends here; the connector pins take the rest.
const BODY_HEIGHT := 0.86
## How far the frame may be widened past its own aspect to fill a socket.
const MAX_STRETCH := 1.2

var index: int = 0
## The dock-wide slot index this bay is showing, which differs from `index` once
## the dock is paged past its ten sockets.
var slot_index: int = -1
var module_id: String = ""
var covered: bool = true
var selected: bool = false
var targeted: bool = false
var lit_step: bool = false

var _screen: CabinetStyle.ModuleScreen = null
var _frame: TextureRect = null
## The kit's shutter, drawn over a locked bay in place of the frame.
var _shutter: TextureRect = null
var _led: Panel = null
var _outline: Panel = null
var _name: Label = null
var _glyph: TextureRect = null
var _bars_holder: CenterContainer = null
var _note: Label = null
var _tap := TapGesture.new()
var _pulse: Tween = null
var _body: Rect2 = Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_screen = CabinetStyle.ModuleScreen.new()
	add_child(_screen)
	_name = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.WHITE)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)
	_glyph = CabinetStyle.glyph(null, 18.0)
	add_child(_glyph)
	_bars_holder = CenterContainer.new()
	_bars_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bars_holder)
	_note = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.GREY)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_note)
	_frame = TextureRect.new()
	_frame.texture = AssetCatalog.cabinet_texture("bay_frame")
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_shutter = TextureRect.new()
	_shutter.name = "Shutter"
	_shutter.texture = AssetCatalog.cabinet_v2_texture("bay_shutter")
	_shutter.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shutter.stretch_mode = TextureRect.STRETCH_SCALE
	_shutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shutter.visible = false
	add_child(_shutter)
	_led = Panel.new()
	_led.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_led)
	_outline = Panel.new()
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline.visible = false
	add_child(_outline)
	gui_input.connect(_on_input)
	resized.connect(_fit)
	_fit()
	_render()


## The frame is drawn as wide as the bay allows at its own aspect, hung from
## the top so the body sits in the painted socket and the pins hang over its lip.
func _fit() -> void:
	if _frame == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var texture_size: Vector2 = _frame.texture.get_size() if _frame.texture != null else Vector2(640, 382)
	# Hung from the top at the bay's height; the painted sockets are a little
	# wider than the frame's own aspect, so it is let out sideways by up to a
	# fifth to fill them — not enough to read as a stretch on the screws.
	var scale_y: float = size.y / texture_size.y
	var scale_x: float = minf(size.x / texture_size.x, scale_y * MAX_STRETCH)
	var drawn := Vector2(texture_size.x * scale_x, texture_size.y * scale_y)
	var origin := Vector2((size.x - drawn.x) * 0.5, 0.0)
	_frame.position = origin
	_frame.size = drawn
	# The shutter is cut to the frame's aspect and sits where the frame would.
	_shutter.position = origin
	_shutter.size = drawn
	_body = Rect2(origin, Vector2(drawn.x, drawn.y * BODY_HEIGHT))
	var window := Rect2(origin + WINDOW.position * drawn, WINDOW.size * drawn)
	_screen.position = window.position
	_screen.size = window.size
	var tiny: int = clampi(int(window.size.y * 0.22), 8, 13)
	_name.add_theme_font_size_override("font_size", tiny)
	_name.position = window.position + Vector2(window.size.x * 0.04, window.size.y * 0.04)
	_name.size = Vector2(window.size.x * 0.92, window.size.y * 0.26)
	var glyph_size: float = clampf(window.size.y * 0.46, 10.0, 40.0)
	_glyph.custom_minimum_size = Vector2.ONE * glyph_size
	_glyph.size = Vector2.ONE * glyph_size
	_glyph.position = window.position + Vector2((window.size.x - glyph_size) * 0.5, window.size.y * 0.30)
	_bars_holder.position = window.position + Vector2(0.0, window.size.y * 0.78)
	_bars_holder.size = Vector2(window.size.x, window.size.y * 0.18)
	_note.add_theme_font_size_override("font_size", tiny)
	_note.position = window.position
	_note.size = window.size
	var tab := Rect2(origin + TAB.position * drawn, TAB.size * drawn)
	var led_size: float = clampf(tab.size.y * 0.45, 3.0, 7.0)
	_led.size = Vector2.ONE * led_size
	_led.position = tab.get_center() - _led.size * 0.5
	_outline.position = _body.position + Vector2(1, 1)
	_outline.size = _body.size - Vector2(2, 2)


func show_slot(slot: int, id: String, is_covered: bool) -> void:
	slot_index = slot
	module_id = id
	covered = is_covered
	mouse_filter = Control.MOUSE_FILTER_IGNORE if covered else Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW if covered else Control.CURSOR_POINTING_HAND
	if covered:
		if has_focus():
			release_focus()
		focus_mode = Control.FOCUS_NONE
	tooltip_text = "Locked bay — the backplane has no slot here yet." if covered else ""
	_render()


func set_selected(value: bool) -> void:
	selected = value
	_render()


## Lit while a cartridge is armed in the bin and this bay could take it.
func set_targeted(value: bool) -> void:
	if targeted == value:
		return
	targeted = value
	_render()


## The stage the batch is currently on, while a burn runs.
func set_lit_step(value: bool) -> void:
	if lit_step == value:
		return
	lit_step = value
	_render()


func _render() -> void:
	if _screen == null:
		return
	var module: ModuleDefinition = ContentDatabase.get_module(module_id) if module_id != "" else null
	# A locked bay is shut behind the kit's shutter and shows nothing else.
	_frame.visible = not covered
	_shutter.visible = covered and _shutter.texture != null
	_screen.visible = not covered
	_led.visible = not covered
	_note.visible = not covered and module == null
	_name.visible = module != null
	_glyph.visible = module != null
	_bars_holder.visible = module != null
	for child in _bars_holder.get_children():
		_bars_holder.remove_child(child)
		child.queue_free()
	var tint: Color = CabinetStyle.category_color(module.category) if module != null else CabinetStyle.GREY
	_screen.set_look(tint, module != null)
	_set_led(tint if module != null else CabinetStyle.GREY, module != null)
	if module == null:
		_note.text = "EMPTY"
		_note.add_theme_color_override("font_color", CabinetStyle.PHOSPHOR_DIM)
	else:
		_name.text = module.name.to_upper()
		_glyph.texture = AssetCatalog.cabinet_module_glyph(module.category)
		_glyph.modulate = tint
		var level: int = int(RARITY_LEVEL.get(module.rarity.to_lower(), 1))
		var pip: float = clampf(_screen.size.y * 0.11, 3.0, 6.0)
		_bars_holder.add_child(CabinetStyle.pips(level, AssetCatalog.rarity_color(module.rarity), 5, pip, Color(1, 1, 1, 0.08)))
	_outline.visible = (selected or targeted or lit_step) and not covered
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
		_outline.modulate.a = 1.0
	if lit_step:
		_outline.add_theme_stylebox_override("panel", CabinetStyle.frame(CabinetStyle.AMBER, 1.0, 0.18, 2))
	elif selected:
		_outline.add_theme_stylebox_override("panel", CabinetStyle.frame(CabinetStyle.AMBER, 0.95, 0.06, 2))
	elif targeted:
		_outline.add_theme_stylebox_override("panel", CabinetStyle.frame(CabinetStyle.PHOSPHOR, 0.9, 0.05, 1))
		_pulse = create_tween().set_loops()
		_pulse.tween_property(_outline, "modulate:a", 0.3, 0.5)
		_pulse.tween_property(_outline, "modulate:a", 1.0, 0.5)


## The small lamp on the frame's top tab, in the category colour when a module
## is seated.
func _set_led(color: Color, lit: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color if lit else Color(color.r * 0.25, color.g * 0.25, color.b * 0.25)
	box.set_corner_radius_all(32)
	box.border_color = Color(0, 0, 0, 0.7)
	box.set_border_width_all(1)
	if lit:
		box.shadow_color = Color(color.r, color.g, color.b, 0.5)
		box.shadow_size = 3
	_led.add_theme_stylebox_override("panel", box)


func _on_input(event: InputEvent) -> void:
	if covered:
		return
	if _tap.feed(event):
		pressed.emit(slot_index)
		accept_event()
		return
	# A focused bay takes the accept action like a key, so a controller or a
	# keyboard can seat and pick without a pointer.
	if event.is_action_pressed("ui_accept") and has_focus():
		pressed.emit(slot_index)
		accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if covered or module_id == "":
		return null
	_tap.cancel()
	var preview: Label = CabinetStyle.mono(_name.text, CabinetStyle.FONT_SMALL, CabinetStyle.WHITE)
	preview.add_theme_stylebox_override("normal", CabinetStyle.frame(CabinetStyle.AMBER, 0.9, 0.6))
	set_drag_preview(preview)
	return {"kind": "slot", "slot_index": slot_index, "module_id": module_id}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if covered or not data is Dictionary:
		return false
	var kind: String = str(Dictionary(data).get("kind", ""))
	if kind == "slot":
		return int(Dictionary(data).get("slot_index", -1)) != slot_index
	return kind == "module"


func _drop_data(_at: Vector2, data: Variant) -> void:
	dropped.emit(Dictionary(data), slot_index)
