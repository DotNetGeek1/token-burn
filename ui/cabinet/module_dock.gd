class_name ModuleDock
extends Control

## The module dock in the backplane: a grid of bays, `columns` by `rows` from
## the layout profile (ten in a row on a wide window, five by two on a compact
## one), each carrying one live bay. The bays show the active workflow's slots
## in order; bays past the board's slot count are shut behind the kit's
## shutter and take no focus, drop or press. Pipelines longer than the grid
## page, a grid at a time.

signal bay_pressed(slot_index: int)
signal bay_dropped(payload: Dictionary, slot_index: int)

## The bay frame's aspect when the catalog has no frame to measure.
const FALLBACK_BAY_ASPECT := 640.0 / 382.0

var columns: int = 10
var rows: int = 1
## The gap between cells as a fraction of the smaller cell side.
var gap_of_cell: float = 0.04
## How far past its own aspect a bay may be widened to fill its cell.
var bay_max_stretch: float = 1.15

var _bays: Array[ModuleBay] = []
var _page: int = 0
var _prev: Button = null
var _next: Button = null
var _selected: int = -1
var _armed: bool = false
var _lit: int = -1
var _paged: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prev = CabinetStyle.key("◄", CabinetStyle.AMBER, CabinetStyle.FONT_SMALL)
	_prev.pressed.connect(func() -> void: _turn(-1))
	add_child(_prev)
	_next = CabinetStyle.key("►", CabinetStyle.AMBER, CabinetStyle.FONT_SMALL)
	_next.pressed.connect(func() -> void: _turn(1))
	add_child(_next)
	_prev.visible = false
	_next.visible = false
	_ensure_bays(columns * rows)
	resized.connect(_layout_bays)
	_layout_bays()


## The grid the profile calls for. Bays are created or retired to match.
func set_grid(new_columns: int, new_rows: int) -> void:
	columns = maxi(1, new_columns)
	rows = maxi(1, new_rows)
	_ensure_bays(columns * rows)
	_layout_bays()
	if is_inside_tree():
		refresh()


## The dock's tuning from the layout profiles (`dock`).
func set_tuning(tuning: Dictionary) -> void:
	gap_of_cell = clampf(float(tuning.get("gap_of_cell", gap_of_cell)), 0.0, 0.3)
	bay_max_stretch = clampf(float(tuning.get("bay_max_stretch", bay_max_stretch)), 1.0, 1.5)
	_layout_bays()


func grid() -> Vector2i:
	return Vector2i(columns, rows)


## How many bays the grid shows at once.
func bays_shown() -> int:
	return columns * rows


## The bays in index order (the grid reads left to right, top to bottom).
func bays() -> Array[ModuleBay]:
	return _bays


func _ensure_bays(count: int) -> void:
	while _bays.size() < count:
		var bay := ModuleBay.new()
		bay.index = _bays.size()
		bay.name = "Bay%d" % (bay.index + 1)
		bay.pressed.connect(func(slot: int) -> void: bay_pressed.emit(slot))
		bay.dropped.connect(func(payload: Dictionary, slot: int) -> void: bay_dropped.emit(payload, slot))
		add_child(bay)
		# The page keys stay last so the bays keep tree order for focus.
		if _prev != null:
			move_child(_prev, -1)
			move_child(_next, -1)
		_bays.append(bay)
	while _bays.size() > count:
		var gone: ModuleBay = _bays.pop_back()
		remove_child(gone)
		gone.queue_free()


## Equal cells across the grid, each bay centred in its cell at the frame's
## own aspect. Page keys, when there are pages, take a narrow column each side.
func _layout_bays() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or _bays.is_empty():
		return
	var key_w: float = clampf(size.y * 0.25, 18.0, 40.0) if _paged else 0.0
	var key_gap: float = 4.0 if _paged else 0.0
	var grid_rect := Rect2(key_w + key_gap, 0.0, maxf(1.0, size.x - 2.0 * (key_w + key_gap)), size.y)
	var cell_w: float = grid_rect.size.x / columns
	var cell_h: float = grid_rect.size.y / rows
	var gap: float = minf(cell_w, cell_h) * gap_of_cell
	var inner_w: float = maxf(1.0, cell_w - gap)
	var inner_h: float = maxf(1.0, cell_h - gap)
	var aspect: float = _bay_aspect()
	var bay_h: float = minf(inner_h, inner_w / aspect)
	var bay_w: float = minf(inner_w, bay_h * aspect * bay_max_stretch)
	for index in range(_bays.size()):
		var bay: ModuleBay = _bays[index]
		var col: int = index % columns
		var row: int = index / columns
		var origin: Vector2 = grid_rect.position + Vector2(col * cell_w, row * cell_h)
		bay.position = origin + Vector2((cell_w - bay_w) * 0.5, (cell_h - bay_h) * 0.5)
		bay.size = Vector2(bay_w, bay_h)
	var key_h: float = minf(size.y, maxf(28.0, size.y * 0.5))
	_prev.size = Vector2(key_w, key_h)
	_next.size = Vector2(key_w, key_h)
	_prev.position = Vector2(0.0, (size.y - key_h) * 0.5)
	_next.position = Vector2(size.x - key_w, _prev.position.y)


func _bay_aspect() -> float:
	var frame: Texture2D = AssetCatalog.cabinet_texture("bay_frame")
	if frame == null or frame.get_size().y <= 0.0:
		return FALLBACK_BAY_ASPECT
	return frame.get_size().x / frame.get_size().y


func refresh() -> void:
	var slots: Array = Simulation.board_slots()
	var per_page: int = bays_shown()
	var pages: int = maxi(1, int(ceil(float(slots.size()) / per_page)))
	_page = clampi(_page, 0, pages - 1)
	for index in range(_bays.size()):
		var slot: int = _page * per_page + index
		var bay: ModuleBay = _bays[index]
		var live: bool = slot < slots.size()
		bay.show_slot(slot, str(slots[slot]) if live else "", not live)
		bay.set_selected(live and slot == _selected)
		bay.set_targeted(live and _armed and slot != _selected)
		bay.set_lit_step(live and slot == _lit)
	_wire_focus()
	var paged: bool = pages > 1
	_prev.visible = paged
	_next.visible = paged
	_prev.disabled = _page <= 0
	_next.disabled = _page >= pages - 1
	if paged != _paged:
		_paged = paged
		_layout_bays()


## Focus walks the live bays in index order — across a row and down to the
## next — whatever the scene tree or the geometry would have picked. Locked
## bays take no focus at all.
func _wire_focus() -> void:
	var live: Array[ModuleBay] = []
	for bay in _bays:
		if bay.covered:
			bay.focus_mode = Control.FOCUS_NONE
			bay.focus_neighbor_left = NodePath()
			bay.focus_neighbor_right = NodePath()
			bay.focus_neighbor_top = NodePath()
			bay.focus_neighbor_bottom = NodePath()
			bay.focus_next = NodePath()
			bay.focus_previous = NodePath()
		else:
			bay.focus_mode = Control.FOCUS_ALL
			live.append(bay)
	for position in range(live.size()):
		var bay: ModuleBay = live[position]
		var previous: ModuleBay = live[position - 1] if position > 0 else bay
		var next: ModuleBay = live[position + 1] if position + 1 < live.size() else bay
		var above: ModuleBay = live[position - columns] if position - columns >= 0 else bay
		var below: ModuleBay = live[position + columns] if position + columns < live.size() else bay
		bay.focus_neighbor_left = bay.get_path_to(previous)
		bay.focus_neighbor_right = bay.get_path_to(next)
		bay.focus_previous = bay.get_path_to(previous)
		bay.focus_next = bay.get_path_to(next)
		bay.focus_neighbor_top = bay.get_path_to(above)
		bay.focus_neighbor_bottom = bay.get_path_to(below)


func _turn(delta: int) -> void:
	_page += delta
	refresh()


## Which slot the player has picked out, or -1.
func selected_slot() -> int:
	return _selected


func select_slot(slot: int) -> void:
	_selected = slot
	refresh()


## Whether a cartridge is armed in the bin, which lights every bay as a target.
func set_armed(armed: bool) -> void:
	_armed = armed
	refresh()


## Lights the bay whose stage the batch is on; -1 clears.
func light_step(slot: int) -> void:
	_lit = slot
	var per_page: int = bays_shown()
	if slot >= 0 and (slot < _page * per_page or slot >= (_page + 1) * per_page):
		_page = slot / per_page
	refresh()


## The dock-space centre of a slot's bay, for anything animating towards it.
func slot_centre(slot: int) -> Vector2:
	var index: int = slot - _page * bays_shown()
	if index < 0 or index >= _bays.size():
		return Vector2.ZERO
	return _bays[index].position + _bays[index].size * 0.5
