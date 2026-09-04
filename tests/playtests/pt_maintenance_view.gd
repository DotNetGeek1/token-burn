extends PlaytestCase

## The maintenance view: the machine zooms out over the wall, the menu and the
## five system mounts come up, and resume puts everything back exactly where
## the player left it. Nothing in the core loop needs it.

const SYSTEMS: Array[String] = ["compute", "cooling", "power", "backplane", "control"]
const MENU: Array[String] = ["resume", "settings", "help", "records", "quit"]


func play(harness: UiHarness) -> void:
	await harness.boot(313)
	var shell: Node = harness.current_scene()
	assert_true(
		shell != null and shell.has_method("enter_maintenance") and shell.has_method("exit_maintenance")
		and shell.has_method("is_maintenance") and shell.has_method("camera_state"),
		"The cabinet exposes enter/exit/is_maintenance and camera_state"
	)
	if shell == null or not shell.has_method("is_maintenance"):
		return
	var layer: MaintenanceLayer = shell.maintenance_layer()
	assert_true(layer != null, "The cabinet mounts a MaintenanceLayer")
	if layer == null:
		return
	assert_false(layer.visible, "The maintenance layer is hidden by default")
	assert_eq(str(shell.camera_state()), "operation", "The camera starts in operation")

	await _back_opens_maintenance(harness, shell, layer)
	await _mounts_present(harness, shell, layer)
	await _menu_sheets(harness, shell, layer)
	await _resume_restores(harness, shell, layer)
	await _install_reveal(harness, shell, layer)
	await _core_loop_needs_no_maintenance(harness, shell, layer)
	await _room_focus_aliases(harness, shell)
	await _keyboard_cancel(harness, shell)
	await _reduced_motion_open(harness, shell, layer)
	await _windows(harness, shell, layer)


## Back on the run tab opens maintenance; back again resumes. The route never
## leaves the desk and the MAINT key on the CRT does the same.
func _back_opens_maintenance(harness: UiHarness, shell: Node, layer: MaintenanceLayer) -> void:
	shell.switch_tab("run")
	await harness.settle()
	shell.handle_system_back()
	await settle_camera(harness)
	assert_true(bool(shell.is_maintenance()), "Back on the run tab opens the maintenance view")
	assert_eq(str(shell.camera_state()), "maintenance", "camera_state reads maintenance")
	assert_true(layer.visible, "The maintenance layer is visible while open")
	assert_true(layer.wall().visible and layer.wall().modulate.a > 0.5, "The maintenance wall is faded in behind the machine")
	assert_eq(SceneRouter.current, SceneRouter.DESK, "Maintenance never leaves the desk route")
	var caption: String = layer.generation_caption()
	assert_true(caption != "", "The generation caption is stencilled on the wall")
	assert_eq(
		caption, str(Simulation.cabinet_generation().get("name", "")).to_upper(),
		"The caption is the simulation's generation name"
	)
	for action in MENU:
		var key: Button = layer.menu_key(action)
		assert_true(key != null and key.is_visible_in_tree() and not key.disabled, "Menu key '%s' is up and enabled" % action)
	shell.handle_system_back()
	await settle_camera(harness)
	assert_false(bool(shell.is_maintenance()), "Back again resumes operation")
	assert_false(layer.visible, "The maintenance layer hides on resume")
	assert_eq(str(shell.camera_state()), "operation", "camera_state reads operation after resume")
	# The MAINT key on the CRT.
	await harness.driver.press_command("maint")
	await settle_camera(harness)
	assert_true(bool(shell.is_maintenance()), "The MAINT key on the CRT opens maintenance")
	await harness.driver.press(layer.menu_key("resume"))
	await settle_camera(harness)
	assert_false(bool(shell.is_maintenance()), "RESUME on the menu closes maintenance")


## All five systems have a mount showing the tier the simulation reports, and
## selecting one prints the NAME · TIER N · <stat> readout.
func _mounts_present(harness: UiHarness, shell: Node, layer: MaintenanceLayer) -> void:
	shell.enter_maintenance()
	await settle_camera(harness)
	var tiers: Dictionary = Simulation.cabinet_system_tiers()
	var mounts: Dictionary = layer.mounts()
	assert_eq(mounts.size(), 5, "Five system mounts")
	var rects: Array[Rect2] = []
	for system_id in SYSTEMS:
		var mount: Control = layer.mount(system_id)
		assert_true(mount != null, "Mount for %s exists" % system_id)
		if mount == null:
			continue
		assert_true(mount.is_visible_in_tree(), "Mount for %s is visible" % system_id)
		assert_true(mount.size.x > 24.0 and mount.size.y > 24.0, "Mount for %s has a usable size (%s)" % [system_id, str(mount.size)])
		assert_eq(int(mount.call("tier")), int(tiers.get(system_id, 1)), "Mount for %s shows the simulation's tier" % system_id)
		var tile: TextureRect = mount.call("tile")
		assert_true(tile != null and tile.texture != null, "Mount for %s carries a tile texture" % system_id)
		var expected: Texture2D = AssetCatalog.cabinet_system_tile(system_id, int(tiers.get(system_id, 1)))
		assert_true(tile != null and tile.texture == expected, "Mount for %s shows the catalogue's tile for its tier" % system_id)
		var rect: Rect2 = mount.get_global_rect()
		for other in rects:
			assert_false(rect.intersects(other), "Mount for %s does not overlap another mount" % system_id)
		rects.append(rect)
		var safe: Rect2 = shell.safe_area_rect()
		assert_true(safe.grow(1.0).encloses(rect), "Mount for %s sits inside the safe area (%s in %s)" % [system_id, str(rect), str(safe)])
		# Select and read.
		await harness.driver.press(mount)
		assert_eq(layer.selected_system(), system_id, "Pressing the %s mount selects it" % system_id)
		var text: String = layer.inspection_text()
		var info: Dictionary = Simulation.cabinet_system_next(system_id)
		assert_true(text.begins_with(str(info.get("name", "")).to_upper()), "Inspection starts with the system name (%s)" % text)
		assert_true(text.find("TIER %d" % int(info.get("tier", 0))) >= 0, "Inspection names the tier (%s)" % text)
		assert_true(text.split("·").size() >= 3, "Inspection carries a stat after the tier (%s)" % text)
		assert_true(bool(mount.call("is_selected")), "The selected mount is marked")
	# Only one mount is selected at a time.
	var selected: int = 0
	for system_id in SYSTEMS:
		var mount: Control = layer.mount(system_id)
		if mount != null and bool(mount.call("is_selected")):
			selected += 1
	assert_eq(selected, 1, "Exactly one mount is selected")
	shell.exit_maintenance()
	await settle_camera(harness)


## Settings and Records open as CRT sheets over the maintenance view and close
## back to it; Help is the flow's existing sheet.
func _menu_sheets(harness: UiHarness, shell: Node, layer: MaintenanceLayer) -> void:
	shell.enter_maintenance()
	await settle_camera(harness)
	var settings: MaintenanceSettingsSheet = _find_first(shell, func(node: Node) -> bool: return node is MaintenanceSettingsSheet) as MaintenanceSettingsSheet
	var records: MaintenanceRecordsSheet = _find_first(shell, func(node: Node) -> bool: return node is MaintenanceRecordsSheet) as MaintenanceRecordsSheet
	assert_true(settings != null, "A settings sheet is mounted")
	assert_true(records != null, "A records sheet is mounted")

	if settings != null:
		assert_false(settings.visible, "Settings is closed to start")
		await harness.driver.press(layer.menu_key("settings"))
		assert_true(settings.visible, "SETTINGS opens the settings sheet")
		assert_true(bool(shell.is_maintenance()), "Settings opens over maintenance, not instead of it")
		for key in ["normal", "hard", "sound", "motion"]:
			var row: ConsoleMenuRow = settings.row(key)
			assert_true(row != null and row.is_visible_in_tree(), "Settings has a '%s' row" % key)
		var endless: ConsoleMenuRow = settings.row("endless")
		assert_true(endless != null, "Settings has an endless row")
		if endless != null:
			assert_eq(endless.visible, MetaProgress.endless_unlocked(), "The endless row shows only once endless is unlocked")
		# Difficulty picks round-trip.
		var difficulty_before: String = MetaProgress.difficulty()
		var other: String = "hard" if difficulty_before == "normal" else "normal"
		await harness.driver.press(settings.row(other))
		assert_eq(MetaProgress.difficulty(), other, "Picking a difficulty row sets it")
		await harness.driver.press(settings.row(difficulty_before))
		assert_eq(MetaProgress.difficulty(), difficulty_before, "Picking the old difficulty restores it")
		# The reduced-motion toggle round-trips through the profile.
		var motion_before: bool = UiFx.reduced_motion()
		var motion_row: ConsoleMenuRow = settings.row("motion")
		if motion_row != null:
			await harness.driver.press(motion_row)
			assert_eq(UiFx.reduced_motion(), not motion_before, "Toggling reduced motion flips UiFx.reduced_motion()")
			await harness.driver.press(motion_row)
			assert_eq(UiFx.reduced_motion(), motion_before, "Toggling reduced motion again restores it")
		# The sound toggle round-trips too.
		var sound_before: bool = MetaProgress.sound_muted()
		var sound_row: ConsoleMenuRow = settings.row("sound")
		if sound_row != null:
			await harness.driver.press(sound_row)
			assert_eq(MetaProgress.sound_muted(), not sound_before, "Toggling sound flips the mute")
			await harness.driver.press(sound_row)
			assert_eq(MetaProgress.sound_muted(), sound_before, "Toggling sound again restores it")
		# Back closes the sheet first, and maintenance is still up.
		shell.handle_system_back()
		await harness.settle()
		assert_false(settings.visible, "Back closes the settings sheet")
		assert_true(bool(shell.is_maintenance()), "Closing settings leaves maintenance open")

	if records != null:
		await harness.driver.press(layer.menu_key("records"))
		assert_true(records.visible, "RECORDS opens the records sheet")
		assert_true(records.award_count() > 0, "Records lists the awards")
		var first: String = ""
		for achievement in ContentDatabase.achievements:
			if achievement is Dictionary:
				first = str(Dictionary(achievement).get("id", ""))
			if first != "":
				break
		if first != "":
			assert_true(records.select_award(first), "An award can be selected for its detail")
			assert_eq(records.selected_award(), first, "The selected award is reported")
		shell.handle_system_back()
		await harness.settle()
		assert_false(records.visible, "Back closes the records sheet")
		assert_true(bool(shell.is_maintenance()), "Closing records leaves maintenance open")

	# Help is the flow's sheet.
	var help: Control = _find_first(shell, func(node: Node) -> bool: return node is HelpOverlay) as Control
	assert_true(help != null, "The flow's help sheet is mounted")
	await harness.driver.press(layer.menu_key("help"))
	await harness.settle()
	assert_true(help != null and help.visible, "HELP opens the help sheet")
	shell.handle_system_back()
	await harness.settle()
	assert_true(help == null or not help.visible, "Back closes help")
	assert_true(bool(shell.is_maintenance()), "Closing help leaves maintenance open")

	# Nothing in maintenance routes to the old venues.
	assert_eq(SceneRouter.current, SceneRouter.DESK, "Menu sheets never leave the desk")
	shell.exit_maintenance()
	await settle_camera(harness)


## Resume comes back to the same tab, the same selection and the same scroll.
func _resume_restores(harness: UiHarness, shell: Node, layer: MaintenanceLayer) -> void:
	shell.switch_tab("market")
	await harness.settle()
	var screen: CabinetScreen = _find_first(shell, func(node: Node) -> bool: return node is CabinetScreen) as CabinetScreen
	var market: CabinetTab = screen.active_tab() if screen != null else null
	if market == null or not market.has_method("select_item"):
		assert_true(false, "MARKET tab is active and exposes select_item")
		return
	var stock: Array = Simulation.module_market_stock()
	var picked: String = ""
	if stock.size() > 1:
		picked = str(stock[stock.size() - 1])
		market.call("select_item", picked)
	elif not stock.is_empty():
		picked = str(stock[0])
		market.call("select_item", picked)
	await harness.settle()
	var shelf_before: String = str(market.call("current_shelf"))
	var selected_before: String = str(market.call("selected_id"))
	# Scroll the shelf a little so there is something to preserve.
	var scroll: ScrollContainer = _find_first(market, func(node: Node) -> bool: return node is ScrollContainer) as ScrollContainer
	var scroll_before := Vector2.ZERO
	if scroll != null:
		scroll.scroll_horizontal = 40
		scroll.scroll_vertical = 0
		await harness.settle()
		scroll_before = Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)

	shell.enter_maintenance()
	await settle_camera(harness)
	assert_true(bool(shell.is_maintenance()), "Maintenance opens from the market tab")
	shell.exit_maintenance()
	await settle_camera(harness)
	assert_false(bool(shell.is_maintenance()), "Resume closes maintenance")
	assert_eq(str(shell.current_tab()), "market", "Resume returns to the market tab")
	var after: CabinetTab = screen.active_tab()
	assert_true(after == market, "The same tab instance is still on the glass")
	assert_eq(str(market.call("current_shelf")), shelf_before, "Resume keeps the shelf")
	assert_eq(str(market.call("selected_id")), selected_before, "Resume keeps the selection")
	if scroll != null and scroll.is_inside_tree():
		var scroll_after := Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
		assert_eq(scroll_after, scroll_before, "Resume keeps the shelf's scroll position")
	# The grid is back at rest.
	var grid: Control = _find_named(shell, "OperationGrid") as Control
	if grid != null:
		assert_true(grid.scale.is_equal_approx(Vector2.ONE), "The operation grid returns to full scale (%s)" % str(grid.scale))
	shell.switch_tab("run")
	await harness.settle()


## show_install swaps a tile with a reveal and calls back; it can be skipped.
func _install_reveal(harness: UiHarness, shell: Node, layer: MaintenanceLayer) -> void:
	shell.enter_maintenance()
	await settle_camera(harness)
	var system_id: String = "compute"
	var mount: Control = layer.mount(system_id)
	var tiers: Dictionary = Simulation.cabinet_system_tiers()
	var old_tier: int = int(tiers.get(system_id, 1))
	var new_tier: int = mini(old_tier + 1, CabinetSystems.max_tier())
	var done: Array[int] = [0]
	var finished: Array[String] = []
	var on_finished := func(id: String) -> void: finished.append(id)
	layer.install_finished.connect(on_finished)

	# Full play: completes on its own within the budget, calls back once.
	var started: int = Time.get_ticks_msec()
	layer.show_install(system_id, old_tier, new_tier, func() -> void: done[0] += 1)
	assert_true(layer.is_installing(), "show_install starts an install")
	assert_eq(layer.selected_system(), system_id, "The install selects its mount")
	var completed: bool = await wait_until(harness, func() -> bool: return done[0] >= 1, 4000)
	# The harness runs the clock fast; measure in the game's seconds.
	var elapsed_s: float = float(Time.get_ticks_msec() - started) / 1000.0 * Engine.time_scale
	assert_true(completed, "show_install calls on_done")
	assert_true(elapsed_s >= 0.9 and elapsed_s <= 2.2, "The reveal runs about 1.0–1.5 s (%.2f s)" % elapsed_s)
	assert_eq(done[0], 1, "on_done fires once")
	assert_false(layer.is_installing(), "The install is over once on_done fires")
	assert_eq(int(mount.call("tier")), new_tier, "The mount shows the new tier after the reveal")
	assert_true(finished.size() == 1 and finished[0] == system_id, "install_finished names the system")
	var tile: TextureRect = mount.call("tile")
	assert_true(tile != null and is_equal_approx(tile.modulate.a, 1.0), "The tile is fully opaque after the reveal")

	# Skipped: ends at once with the same end state.
	done[0] = 0
	layer.show_install(system_id, new_tier, old_tier, func() -> void: done[0] += 1)
	assert_true(layer.is_installing(), "A second show_install starts")
	await harness.get_tree().process_frame
	layer.skip_install()
	assert_false(layer.is_installing(), "skip_install ends the install at once")
	assert_eq(done[0], 1, "A skipped install still calls on_done once")
	assert_eq(int(mount.call("tier")), old_tier, "A skipped install lands on the target tier")
	assert_true(tile != null and is_equal_approx(tile.modulate.a, 1.0), "A skipped install leaves the tile opaque")

	# A press on the layer skips too.
	done[0] = 0
	layer.show_install(system_id, old_tier, new_tier, func() -> void: done[0] += 1)
	await harness.get_tree().process_frame
	var viewport: Viewport = layer.get_viewport()
	var at: Vector2 = _bare_point(layer)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	down.global_position = at
	viewport.push_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	up.global_position = at
	viewport.push_input(up)
	await harness.settle()
	assert_false(layer.is_installing(), "A press on the layer skips the reveal")
	assert_eq(done[0], 1, "A press-skipped install calls on_done once")

	# The reveal is presentation only: the simulation is untouched, and a
	# refresh re-reads the real tier.
	assert_eq(int(Simulation.cabinet_system_tiers().get(system_id, 1)), old_tier, "show_install never changes the simulation")
	layer.refresh()
	assert_eq(int(mount.call("tier")), int(Simulation.cabinet_system_tiers().get(system_id, 1)), "refresh() re-reads the real tier")
	layer.install_finished.disconnect(on_finished)
	shell.exit_maintenance()
	await settle_camera(harness)


## Every tab and its commit are reachable with maintenance closed, and nothing
## on the way opens it.
func _core_loop_needs_no_maintenance(harness: UiHarness, shell: Node, layer: MaintenanceLayer) -> void:
	var driver: UiDriver = harness.driver
	var screen: CabinetScreen = _find_first(shell, func(node: Node) -> bool: return node is CabinetScreen) as CabinetScreen
	for tab_key in ["contracts", "modules", "market", "perks", "run"]:
		await driver.press_command(tab_key)
		assert_eq(str(shell.current_tab()), tab_key, "The %s tab opens from the strip" % tab_key)
		assert_false(bool(shell.is_maintenance()), "Opening %s never opens maintenance" % tab_key)
		assert_false(layer.visible, "The maintenance layer stays hidden on %s" % tab_key)
		if screen != null and tab_key != "run":
			var tab: CabinetTab = screen.active_tab()
			assert_true(tab != null and not tab.primary_action().is_empty(), "%s answers primary_action without maintenance" % tab_key)
	var commit: Control = _find_first(shell, func(node: Node) -> bool:
		return node is Button and node.has_method("set_state") and node.has_method("is_enabled")
	) as Control
	assert_true(commit != null and commit.is_visible_in_tree(), "The commit button is on the deck in operation")
	var lever: Control = _find_first(shell, func(node: Node) -> bool: return node is AbortLever) as Control
	assert_true(lever != null and lever.is_visible_in_tree(), "The abort lever is on the rail in operation")
	# The MAINT key is the only way in from the strip; no tab hides behind it.
	assert_true(screen != null and screen.maintenance_key() != null and screen.maintenance_key().is_visible_in_tree(), "The MAINT key is on the strip")
	assert_false(screen.has_tab("menu"), "There is no MENU tab or door on the strip any more")


## The old room-focus API keeps its signatures and maps onto maintenance.
func _room_focus_aliases(harness: UiHarness, shell: Node) -> void:
	if not shell.has_method("focus_room"):
		return
	shell.focus_room("anything")
	await settle_camera(harness)
	assert_true(bool(shell.room_focused_on("anything")), "focus_room enters maintenance (room_focused_on)")
	assert_true(bool(shell.is_maintenance()), "focus_room enters maintenance")
	shell.clear_room_focus()
	await settle_camera(harness)
	assert_false(bool(shell.is_maintenance()), "clear_room_focus leaves maintenance")
	assert_false(bool(shell.room_focused_on("anything")), "room_focused_on reads false after clear")


## ui_cancel on the cabinet walks the same back chain.
func _keyboard_cancel(harness: UiHarness, shell: Node) -> void:
	shell.switch_tab("perks")
	await harness.settle()
	var press := InputEventAction.new()
	press.action = "ui_cancel"
	press.pressed = true
	Input.parse_input_event(press)
	await harness.settle()
	assert_eq(str(shell.current_tab()), "run", "ui_cancel on a non-run tab returns to the run tab")
	Input.parse_input_event(press)
	await settle_camera(harness)
	assert_true(bool(shell.is_maintenance()), "ui_cancel on the run tab opens maintenance")
	Input.parse_input_event(press)
	await settle_camera(harness)
	assert_false(bool(shell.is_maintenance()), "ui_cancel in maintenance resumes")


## Under reduced motion the camera does not move: the grid is small at once
## and the layer fades.
func _reduced_motion_open(harness: UiHarness, shell: Node, layer: MaintenanceLayer) -> void:
	var before: bool = UiFx.reduced_motion()
	MetaProgress.set_reduced_motion(true)
	assert_true(UiFx.reduced_motion(), "Reduced motion can be switched on")
	var grid: Control = _find_named(shell, "OperationGrid") as Control
	shell.enter_maintenance()
	await harness.get_tree().process_frame
	if grid != null:
		assert_true(grid.scale.x < 0.99, "Under reduced motion the grid is already small on the first frame (%s)" % str(grid.scale))
	await settle_camera(harness)
	assert_true(bool(shell.is_maintenance()), "Reduced motion still opens maintenance")
	shell.exit_maintenance()
	await settle_camera(harness)
	assert_false(bool(shell.is_maintenance()), "Reduced motion still resumes")
	if grid != null:
		assert_true(grid.scale.is_equal_approx(Vector2.ONE), "The grid is back at full scale under reduced motion")
	MetaProgress.set_reduced_motion(before)


## The maintenance view at the windows it has to work in: every mount and menu
## key on screen, finite and inside the viewport; a screenshot of each.
func _windows(harness: UiHarness, shell: Node, layer: MaintenanceLayer) -> void:
	for size in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(960, 540)]:
		await harness.set_viewport(size)
		var label := "%dx%d" % [size.x, size.y]
		shell.enter_maintenance()
		await settle_camera(harness)
		var view: Rect2 = shell.get_viewport().get_visible_rect()
		for system_id in SYSTEMS:
			var mount: Control = layer.mount(system_id)
			var rect: Rect2 = mount.get_global_rect()
			assert_true(view.grow(1.0).encloses(rect), "%s: mount %s is inside the viewport (%s)" % [label, system_id, str(rect)])
			assert_true(rect.size.x >= 44.0 and rect.size.y >= 44.0, "%s: mount %s is a touch target (%s)" % [label, system_id, str(rect.size)])
		for action in MENU:
			var key: Button = layer.menu_key(action)
			var rect: Rect2 = key.get_global_rect()
			assert_true(view.grow(1.0).encloses(rect), "%s: menu key %s is inside the viewport (%s)" % [label, action, str(rect)])
			assert_true(rect.size.y >= 40.0, "%s: menu key %s is tall enough to touch (%s)" % [label, action, str(rect.size)])
		var grid: Control = _find_named(shell, "OperationGrid") as Control
		if grid != null:
			var shown: Rect2 = grid.get_global_transform() * Rect2(Vector2.ZERO, grid.size)
			for system_id in SYSTEMS:
				assert_false(shown.intersects(layer.mount(system_id).get_global_rect()), "%s: mount %s does not sit over the shrunken machine" % [label, system_id])
		await harness.get_tree().process_frame
		harness.capture("maintenance-%s" % label)
		shell.exit_maintenance()
		await settle_camera(harness)
	await harness.set_viewport(UiHarness.VIEW_DESKTOP)


# --- Locators ----------------------------------------------------------------

## A point on the layer that no button or panel of its own covers, so a press
## there reaches the layer itself.
func _bare_point(layer: Control) -> Vector2:
	var rect: Rect2 = layer.get_global_rect()
	var covered: Array[Rect2] = []
	_collect_rects(layer, layer, covered)
	for fy in [0.5, 0.35, 0.65, 0.2, 0.8, 0.1, 0.9]:
		for fx in [0.5, 0.35, 0.65, 0.2, 0.8, 0.1, 0.9]:
			var candidate: Vector2 = rect.position + Vector2(rect.size.x * float(fx), rect.size.y * float(fy))
			var clear: bool = true
			for other in covered:
				if other.has_point(candidate):
					clear = false
					break
			if clear:
				return candidate
	return rect.get_center()


func _collect_rects(root: Control, node: Node, out: Array[Rect2]) -> void:
	for child in node.get_children():
		if child is Control and child != root and (child as Control).is_visible_in_tree() and (child as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			out.append((child as Control).get_global_rect())
		_collect_rects(root, child, out)


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


func _find_named(node: Node, wanted: String) -> Node:
	return _find_first(node, func(candidate: Node) -> bool: return candidate.name == wanted)
