class_name ModuleDock
extends Control

## The module dock along the foot of the cabinet: ten sockets painted into the
## plate, each carrying one live bay. The bays show the active workflow's slots
## in order; sockets past the board's slot count are shut. Pipelines longer than
## ten sockets page, a bank of ten at a time.

signal bay_pressed(slot_index: int)
signal bay_dropped(payload: Dictionary, slot_index: int)

const BAYS := 10

var _bays: Array[ModuleBay] = []
var _page: int = 0
var _prev: Button = null
var _next: Button = null
var _selected: int = -1
var _armed: bool = false
var _lit: int = -1
var _plate: Rect2 = Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in range(BAYS):
		var bay := ModuleBay.new()
		bay.index = index
		bay.pressed.connect(func(slot: int) -> void: bay_pressed.emit(slot))
		bay.dropped.connect(func(payload: Dictionary, slot: int) -> void: bay_dropped.emit(payload, slot))
		add_child(bay)
		_bays.append(bay)
	_prev = CabinetStyle.key("◄", CabinetStyle.AMBER, CabinetStyle.FONT_SMALL)
	_prev.pressed.connect(func() -> void: _turn(-1))
	add_child(_prev)
	_next = CabinetStyle.key("►", CabinetStyle.AMBER, CabinetStyle.FONT_SMALL)
	_next.pressed.connect(func() -> void: _turn(1))
	add_child(_next)
	_prev.visible = false
	_next.visible = false


## Places every bay over the socket the plate painted for it. `plate` is the
## plate's rect in this control's parent, and the dock itself spans the plate.
func layout(plate: Rect2) -> void:
	_plate = plate
	position = plate.position
	size = plate.size
	var sockets: Array[Rect2] = AssetCatalog.cabinet_sockets()
	for index in range(BAYS):
		var bay: ModuleBay = _bays[index]
		if index >= sockets.size():
			bay.visible = false
			continue
		bay.visible = true
		var socket: Rect2 = sockets[index]
		# The cartridge body fills the painted socket; its edge connector hangs
		# over the lower lip, so the bay is a little taller than the socket.
		var lip: float = socket.size.y * 0.05
		bay.position = Vector2(socket.position.x, socket.position.y - lip) * plate.size
		bay.size = Vector2(socket.size.x, (socket.size.y + lip) / ModuleBay.BODY_HEIGHT) * plate.size
	var dock: Rect2 = AssetCatalog.cabinet_region("dock")
	var key_size := Vector2(plate.size.x * 0.022, plate.size.y * 0.05)
	_prev.size = key_size
	_next.size = key_size
	_prev.position = Vector2(dock.position.x * plate.size.x - key_size.x * 0.4, (dock.position.y + dock.size.y * 0.45) * plate.size.y)
	_next.position = Vector2((dock.position.x + dock.size.x) * plate.size.x - key_size.x * 0.6, _prev.position.y)


func refresh() -> void:
	var slots: Array = Simulation.board_slots()
	var pages: int = maxi(1, int(ceil(float(slots.size()) / BAYS)))
	_page = clampi(_page, 0, pages - 1)
	for index in range(BAYS):
		var slot: int = _page * BAYS + index
		var bay: ModuleBay = _bays[index]
		var live: bool = slot < slots.size()
		bay.show_slot(slot, str(slots[slot]) if live else "", not live)
		bay.set_selected(live and slot == _selected)
		bay.set_targeted(live and _armed and slot != _selected)
		bay.set_lit_step(live and slot == _lit)
	_prev.visible = pages > 1
	_next.visible = pages > 1
	_prev.disabled = _page <= 0
	_next.disabled = _page >= pages - 1


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
	if slot >= 0 and (slot < _page * BAYS or slot >= (_page + 1) * BAYS):
		_page = slot / BAYS
	refresh()


## The dock-space centre of a slot's bay, for anything animating towards it.
func slot_centre(slot: int) -> Vector2:
	var index: int = slot - _page * BAYS
	if index < 0 or index >= BAYS:
		return Vector2.ZERO
	return _bays[index].position + _bays[index].size * 0.5
