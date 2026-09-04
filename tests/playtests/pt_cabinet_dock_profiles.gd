extends PlaytestCase

## The module dock at the wide and the compact layout profile: a cartridge
## armed with a tap in the MODULES bin and seated with a tap on a bay lands in
## that slot of the simulation; bays past the board's slot count are shut —
## no focus, no drop, no press; and focus walks the live bays in index order
## across the grid however the profile folds it.
##
## Everything is driven through the real input path (the driver's pointer
## stream) and public API (`layout_profile_name`, `dock_grid`, the dock's
## `bays()` / `selected_slot()`, the tab's `armed_module_id`).

const PROFILES: Array[Dictionary] = [
	{"size": Vector2i(1280, 720), "profile": "wide", "grid": Vector2i(10, 1)},
	{"size": Vector2i(960, 540), "profile": "compact", "grid": Vector2i(5, 2)},
]

var _presses: Array[int] = []


func play(harness: UiHarness) -> void:
	await harness.boot(101)
	var shell: Node = harness.current_scene()
	assert_true(
		shell != null and shell.has_method("layout_profile_name") and shell.has_method("dock_grid"),
		"The cabinet shell is up and exposes layout_profile_name / dock_grid"
	)
	if shell == null or not shell.has_method("dock_grid"):
		return
	var driver := UiDriver.new(harness, self)
	for entry in PROFILES:
		var viewport_size: Vector2i = entry["size"]
		var label := "%dx%d" % [viewport_size.x, viewport_size.y]
		await harness.set_viewport(viewport_size)
		await harness.settle()
		assert_eq(str(shell.call("layout_profile_name")), str(entry["profile"]), "%s layout profile" % label)
		assert_eq(shell.call("dock_grid"), entry["grid"], "%s dock grid" % label)
		shell.switch_tab("modules")
		await harness.settle()
		var dock: ModuleDock = _find_first(shell, func(node: Node) -> bool: return node is ModuleDock) as ModuleDock
		var screen: CabinetScreen = _find_first(shell, func(node: Node) -> bool: return node is CabinetScreen) as CabinetScreen
		var tab: CabinetTab = screen.active_tab() if screen != null else null
		assert_true(dock != null, "%s the module dock is mounted" % label)
		assert_true(tab != null and tab.has_method("arm"), "%s the MODULES tab is up" % label)
		if dock == null or tab == null:
			continue
		await _seat_by_tapping(harness, driver, shell, tab, dock, label)
		await _locked_bays(harness, shell, tab, dock, label)
		await _focus_order(harness, dock, label)
	shell.switch_tab("run")
	await harness.set_viewport(UiHarness.VIEW_DESKTOP)
	await harness.settle()


# --- Seating -----------------------------------------------------------------

## Tap a loose cartridge in the bin (arms it, lights the bays), tap an empty
## live bay: the module is seated in that slot and the bay is picked.
func _seat_by_tapping(harness: UiHarness, driver: UiDriver, shell: Node, tab: CabinetTab, dock: ModuleDock, label: String) -> void:
	var slots: Array = Simulation.board_slots()
	var loose: Array[String] = _loose_modules(slots)
	# A starter board seats everything it owns; eject one so there is a
	# cartridge in the bin, and put it back at the end.
	var ejected_id: String = ""
	var ejected_from: int = -1
	if loose.is_empty():
		for index in range(slots.size()):
			if str(slots[index]) != "" and Simulation.clear_slot(index):
				ejected_id = str(slots[index])
				ejected_from = index
				break
		shell.call("refresh_all")
		await harness.settle()
		slots = Simulation.board_slots()
		loose = _loose_modules(slots)
	if loose.is_empty():
		print("    %s no cartridge to arm on seed 101; seating not exercised" % label)
		return
	var module_id: String = loose[0]
	var target: int = -1
	for index in range(slots.size()):
		if str(slots[index]) == "":
			target = index
			break
	if target < 0 or target >= dock.bays_shown():
		print("    %s no empty slot on the first page; seating not exercised" % label)
		_restore(ejected_id, ejected_from)
		return

	tab.call("arm", "")
	dock.select_slot(-1)
	await harness.settle()
	var cartridge: Control = _find_first(tab, func(node: Node) -> bool:
		return node is ModuleCartridge and str(node.get("module_id")) == module_id
	) as Control
	assert_true(cartridge != null, "%s the bin shows a cartridge for %s" % [label, module_id])
	if cartridge == null:
		_restore(ejected_id, ejected_from)
		return
	await driver.press(cartridge)
	assert_eq(str(tab.get("armed_module_id")), module_id, "%s tapping the cartridge arms it" % label)
	var bay: ModuleBay = dock.bays()[target]
	assert_false(bay.covered, "%s bay %d is live" % [label, target + 1])
	assert_true(bay.targeted, "%s bay %d lights as a target while a cartridge is armed" % [label, target + 1])

	await driver.press(bay)
	assert_eq(str(Simulation.board_slots()[target]), module_id, "%s tapping bay %d seats the armed module there" % [label, target + 1])
	assert_eq(str(tab.get("armed_module_id")), "", "%s seating disarms the bin" % label)
	assert_eq(dock.selected_slot(), target, "%s the seated bay is picked" % label)
	assert_eq(bay.module_id, module_id, "%s bay %d shows the seated module" % [label, target + 1])

	# Leave the board as it was found.
	dock.select_slot(-1)
	tab.call("set_dock_slot", -1)
	Simulation.clear_slot(target)
	_restore(ejected_id, ejected_from)
	shell.call("refresh_all")
	await harness.settle()


func _restore(ejected_id: String, ejected_from: int) -> void:
	if ejected_id != "" and ejected_from >= 0:
		Simulation.place_module(ejected_id, ejected_from)


# --- Locked bays -------------------------------------------------------------

## Bays past the board's slot count are shut: no focus, no drop, and a press
## on one neither reaches the shell nor seats anything, armed or not.
func _locked_bays(harness: UiHarness, shell: Node, tab: CabinetTab, dock: ModuleDock, label: String) -> void:
	var capacity: int = Simulation.board_slots().size()
	var locked: Array[ModuleBay] = []
	for bay in dock.bays():
		if bay.covered:
			locked.append(bay)
	assert_eq(
		locked.size(), maxi(0, dock.bays_shown() - capacity),
		"%s every bay past the board's %d slots is locked" % [label, capacity]
	)
	if locked.is_empty():
		print("    %s the board fills the grid; locked bays not exercised" % label)
		return
	var before: Array = Simulation.board_slots().duplicate()
	var loose: Array[String] = _loose_modules(before)
	var armed: String = loose[0] if not loose.is_empty() else ""
	if armed != "":
		tab.call("arm", armed)
		await harness.settle()
	_presses.clear()
	dock.bay_pressed.connect(_count_press)
	for bay in locked:
		assert_true(bay.is_visible_in_tree(), "%s locked %s is drawn (shuttered)" % [label, bay.name])
		assert_eq(bay.focus_mode, Control.FOCUS_NONE, "%s locked %s takes no focus" % [label, bay.name])
		assert_false(bay.targeted, "%s locked %s does not light as a target" % [label, bay.name])
		assert_false(
			bool(bay._can_drop_data(bay.size * 0.5, {"kind": "module", "module_id": armed if armed != "" else "x"})),
			"%s locked %s refuses a module drop" % [label, bay.name]
		)
		assert_false(
			bool(bay._can_drop_data(bay.size * 0.5, {"kind": "slot", "slot_index": 0})),
			"%s locked %s refuses a slot drop" % [label, bay.name]
		)
		await _tap_raw(harness, bay)
	dock.bay_pressed.disconnect(_count_press)
	assert_true(_presses.is_empty(), "%s taps on locked bays never reach the shell (got %s)" % [label, _presses])
	assert_eq(Simulation.board_slots(), before, "%s taps on locked bays seat nothing" % label)
	if armed != "":
		assert_eq(str(tab.get("armed_module_id")), armed, "%s the armed cartridge stays armed" % label)
		tab.call("arm", "")
	dock.select_slot(-1)
	tab.call("set_dock_slot", -1)
	await harness.settle()


func _count_press(slot: int) -> void:
	_presses.append(slot)


## A pointer tap at a control's centre through the viewport, for controls the
## driver refuses (a locked bay ignores the mouse on purpose).
func _tap_raw(harness: UiHarness, control: Control) -> void:
	var viewport: Viewport = control.get_viewport()
	var centre: Vector2 = control.get_global_rect().get_center()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = centre
	down.global_position = centre
	viewport.push_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = centre
	up.global_position = centre
	viewport.push_input(up)
	await harness.settle()


# --- Focus order -------------------------------------------------------------

## Focus runs through the live bays in index order — right along a row and on
## to the next — and a focused bay takes `ui_accept` as a press.
func _focus_order(harness: UiHarness, dock: ModuleDock, label: String) -> void:
	var live: Array[ModuleBay] = []
	for bay in dock.bays():
		if not bay.covered:
			live.append(bay)
	if live.size() < 2:
		print("    %s fewer than two live bays; focus order not exercised" % label)
		return
	var columns: int = dock.grid().x
	for position in range(live.size()):
		var bay: ModuleBay = live[position]
		assert_eq(bay.focus_mode, Control.FOCUS_ALL, "%s live %s is focusable" % [label, bay.name])
		if position + 1 < live.size():
			assert_eq(
				bay.get_node_or_null(bay.focus_next), live[position + 1],
				"%s focus_next of %s is the next live bay" % [label, bay.name]
			)
			assert_eq(
				bay.get_node_or_null(bay.focus_neighbor_right), live[position + 1],
				"%s right of %s is the next live bay" % [label, bay.name]
			)
		if position > 0:
			assert_eq(
				bay.get_node_or_null(bay.focus_previous), live[position - 1],
				"%s focus_previous of %s is the previous live bay" % [label, bay.name]
			)
		if position + columns < live.size():
			assert_eq(
				bay.get_node_or_null(bay.focus_neighbor_bottom), live[position + columns],
				"%s below %s is the bay one row down" % [label, bay.name]
			)
	# Walk it with the engine's own resolution from the first bay.
	live[0].grab_focus()
	await harness.settle()
	var walked: Array[String] = [str(live[0].name)]
	var current: Control = live[0]
	for _step in range(live.size() - 1):
		current = current.find_next_valid_focus()
		if current == null:
			break
		walked.append(str(current.name))
	var expected: Array[String] = []
	for bay in live:
		expected.append(str(bay.name))
	assert_eq(walked, expected, "%s find_next_valid_focus walks the live bays in index order" % label)

	# The keyboard picks a bay: accept on the focused bay is a press.
	var first: ModuleBay = live[0]
	first.grab_focus()
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	first.get_viewport().push_input(accept)
	await harness.settle()
	assert_eq(dock.selected_slot(), first.slot_index, "%s ui_accept on the focused bay picks it" % label)
	dock.select_slot(-1)
	first.release_focus()
	await harness.settle()


# --- Helpers -----------------------------------------------------------------

func _loose_modules(slots: Array) -> Array[String]:
	var loose: Array[String] = []
	for module_id in Simulation.owned_modules():
		if not (str(module_id) in slots):
			loose.append(str(module_id))
	return loose


func _find_first(node: Node, predicate: Callable) -> Node:
	if node == null:
		return null
	if bool(predicate.call(node)):
		return node
	for child in node.get_children():
		var found: Node = _find_first(child, predicate)
		if found != null:
			return found
	return null
