extends PlaytestCase

## The one red button under the glass relabels itself to whatever the active
## CRT tab commits. This walks every tab and checks the word on the button is
## one the tab is allowed to say, that the button and the tab's
## `primary_action()` agree, and that a disabled button always explains itself
## with a blocker line.
##
## Selection is driven only through public tab API (`arm`, `set_dock_slot`,
## the dock's `select_slot`); where a tab has no public way to pick a row, the
## default selection is what gets checked. Nothing here reads the shell's
## private button field, which is being renamed by a concurrent refactor.

## Tab key -> the words the commit button may show while that tab is up.
const EXPECTED := {
	"run": ["BURN", "BURN AGAIN"],
	"contracts": ["ACCEPT"],
	"modules": ["SEAT", "EJECT"],
	"market": ["BUY", "REROLL", "SELL", "UPGRADE"],
	"perks": ["FIT", "BENCH"],
}

const TAB_ORDER: Array[String] = ["run", "contracts", "modules", "market", "perks"]


func play(harness: UiHarness) -> void:
	await harness.boot(101)
	var shell: Node = harness.current_scene()
	assert_true(
		shell != null and shell.has_method("switch_tab") and shell.has_method("current_tab"),
		"The cabinet shell is up and exposes switch_tab / current_tab"
	)
	if shell == null:
		return
	var screen: CabinetScreen = _find_screen(shell)
	var button: Control = _find_commit_button(shell)
	assert_true(screen != null, "The CRT (CabinetScreen) is mounted")
	assert_true(button != null, "The commit button is mounted")
	if screen == null or button == null:
		return

	for key in TAB_ORDER:
		shell.switch_tab(key)
		await harness.settle()
		assert_eq(str(shell.current_tab()), key, "switch_tab(%s) lands on that tab" % key)
		assert_eq(screen.active_key(), key, "CabinetScreen shows %s" % key)
		_check_deck(shell, screen, button, key, "default selection")

	await _modules_matrix(harness, shell, screen, button)
	await _systems_shelf(harness, shell, screen, button)
	await _contract_shape(harness, shell, screen)
	await _blocked_states(harness, shell, screen, button)
	await _sell_hold(harness, shell, screen, button)
	await _busy_during_burn(harness, shell, screen, button)
	shell.switch_tab("run")
	await harness.settle()


# --- The extended contract ---------------------------------------------------

## Every tab's primary_action, normalised, carries tone / confirm /
## hold_seconds; the legacy shapes normalise the way the docs promise.
func _contract_shape(harness: UiHarness, shell: Node, screen: CabinetScreen) -> void:
	for key in TAB_ORDER:
		if key == "run":
			continue
		shell.switch_tab(key)
		await harness.settle()
		var tab: CabinetTab = screen.active_tab()
		if tab == null:
			continue
		var action: Dictionary = tab.primary_action()
		var full: Dictionary = CabinetTab.normalize_action(action)
		for field in ["label", "enabled", "sub", "tone", "confirm", "hold_seconds", "pressed"]:
			assert_true(full.has(field), "%s primary_action carries '%s' after normalisation" % [key, field])
		assert_true(
			str(full.get("tone", "")) in [CabinetTab.TONE_NORMAL, CabinetTab.TONE_DANGER],
			"%s tone is normal or danger" % key
		)
		assert_true(
			str(full.get("confirm", "")) in [CabinetTab.CONFIRM_PRESS, CabinetTab.CONFIRM_HOLD],
			"%s confirm is press or hold" % key
		)
		assert_true(float(full.get("hold_seconds", 0.0)) > 0.0, "%s hold_seconds is positive" % key)
		if str(full["tone"]) == CabinetTab.TONE_DANGER:
			assert_eq(str(full["confirm"]), CabinetTab.CONFIRM_HOLD, "%s danger tone asks for a hold" % key)
	# Legacy shapes.
	var old: Dictionary = CabinetTab.normalize_action({"label": "X", "enabled": true, "sub": "", "pressed": Callable()})
	assert_eq(str(old["tone"]), CabinetTab.TONE_NORMAL, "Missing tone defaults to normal")
	assert_eq(str(old["confirm"]), CabinetTab.CONFIRM_PRESS, "Missing confirm defaults to press")
	assert_true(is_equal_approx(float(old["hold_seconds"]), CabinetTab.DEFAULT_HOLD_SECONDS), "Missing hold_seconds defaults to 0.65")
	var legacy_danger: Dictionary = CabinetTab.normalize_action({"label": "X", "enabled": true, "danger": true})
	assert_eq(str(legacy_danger["tone"]), CabinetTab.TONE_DANGER, "Legacy danger:true maps to tone danger")
	assert_eq(str(legacy_danger["confirm"]), CabinetTab.CONFIRM_HOLD, "Legacy danger:true maps to confirm hold")
	assert_true(CabinetTab.normalize_action({}).is_empty(), "An empty action stays empty (shell-owned BURN)")


## With nothing picked, every tab's button is idle and says why; a pick that
## cannot be acted on is blocked and says why.
func _blocked_states(harness: UiHarness, shell: Node, screen: CabinetScreen, button: Control) -> void:
	# Contracts: whatever is picked by default, a disabled button explains itself
	# and is one of the two disabled faces.
	shell.switch_tab("contracts")
	await harness.settle()
	shell.refresh_all()
	await harness.settle()
	var contracts_reading: Dictionary = _button_reading(button)
	if not bool(contracts_reading["enabled"]):
		assert_true(str(contracts_reading["sub"]) != "", "CONTRACTS blocked button carries a reason")
		assert_true(str(button.call("state")) in ["idle", "blocked"], "CONTRACTS with no pick is idle/blocked (got %s)" % str(button.call("state")))
	# Market: a shelf with stock picks its first item, so the button is armed
	# with a spend line; one selection only.
	shell.switch_tab("market")
	await harness.settle()
	var market: CabinetTab = screen.active_tab()
	if market != null and market.has_method("select_shelf"):
		market.call("select_shelf", "modules")
		shell.refresh_all()
		await harness.settle()
		var stock: Array = Simulation.module_market_stock()
		if not stock.is_empty():
			assert_true(str(market.call("selected_id")) != "", "MARKET picks one item by default on a stocked shelf")
			assert_eq(_selected_tile_count(market), 1, "MARKET marks exactly one selected card")
		# An unaffordable buy is blocked with a NEED $N MORE line.
		var cash_before: float = float(Simulation.run_state.economy.get("cash", 0.0))
		if not stock.is_empty() and Simulation.market_open():
			Simulation.run_state.economy["cash"] = 0.0
			market.call("select_item", str(stock[0]))
			shell.refresh_all()
			await harness.settle()
			var broke: Dictionary = _button_reading(button)
			assert_false(bool(broke["enabled"]), "MARKET BUY with no cash is disabled")
			assert_true(str(broke["sub"]).begins_with("NEED "), "MARKET BUY with no cash says NEED $N MORE (got '%s')" % str(broke["sub"]))
			assert_eq(str(button.call("state")), "blocked", "MARKET BUY with no cash is the blocked face")
			Simulation.run_state.economy["cash"] = cash_before
			shell.refresh_all()
			await harness.settle()
	# Modules: nothing armed → SELECT A BAY / a selection blocker, idle.
	shell.switch_tab("modules")
	await harness.settle()
	var modules: CabinetTab = screen.active_tab()
	if modules != null and modules.has_method("arm"):
		modules.call("arm", "")
		modules.call("set_dock_slot", -1)
		shell.refresh_all()
		await harness.settle()
		var reading: Dictionary = _button_reading(button)
		assert_false(bool(reading["enabled"]), "MODULES with nothing armed is disabled")
		assert_true(str(reading["sub"]) != "", "MODULES with nothing armed carries a reason")


## SELL is a danger action: it needs a hold, the hold shows progress, releasing
## early cancels without selling, and holding through sells exactly once.
func _sell_hold(harness: UiHarness, shell: Node, screen: CabinetScreen, button: Control) -> void:
	shell.switch_tab("market")
	await harness.settle()
	var market: CabinetTab = screen.active_tab()
	if market == null or not market.has_method("select_shelf"):
		assert_true(false, "MARKET tab exposes select_shelf")
		return
	var sellable: String = _first_sellable()
	if sellable == "":
		sellable = _buy_something_sellable()
		shell.refresh_all()
		await harness.settle()
	if sellable == "":
		print("    market: nothing sellable on seed 101; SELL hold path not exercised")
		return
	assert_true(market.call("select_shelf", "rig"), "MARKET has a RIG shelf")
	assert_true(market.call("select_item", sellable), "MARKET can pick %s on the rig shelf" % sellable)
	shell.refresh_all()
	await harness.settle()
	var reading: Dictionary = _button_reading(button)
	assert_eq(str(reading["label"]), "SELL", "A sellable rig item arms SELL")
	assert_true(bool(reading["enabled"]), "SELL is enabled")
	assert_eq(str(button.call("state")), "danger", "SELL takes the danger face")
	assert_true(bool(button.call("requires_hold")), "SELL requires a hold")
	assert_true(str(reading["sub"]).find("HOLD") >= 0 or str(button.call("action").get("sub", "")) != "", "SELL sub explains the consequence")
	var hardware_before: int = Array(Simulation.run_state.build.get("hardware", [])).size()

	# A plain press does not sell.
	await harness.driver.press(button)
	await harness.settle()
	assert_eq(
		Array(Simulation.run_state.build.get("hardware", [])).size(), hardware_before,
		"A single press on SELL sells nothing"
	)

	# Press, wait a little, release early: progress was visible, nothing sold.
	# The hold is measured in game seconds, so the harness's fast clock would
	# finish it inside a frame; run this part at real speed.
	var clock_before: float = Engine.time_scale
	Engine.time_scale = 1.0
	var viewport: Viewport = button.get_viewport()
	var centre: Vector2 = button.get_global_rect().get_center()
	var seen_progress: Array[float] = []
	var on_progress := func(ratio: float) -> void: seen_progress.append(ratio)
	button.connect("hold_progress", on_progress)
	_push_mouse(viewport, centre, true)
	var partial: float = float(button.call("hold_seconds")) * 0.35
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(partial * 1000.0):
		await harness.get_tree().process_frame
	assert_true(bool(button.call("is_holding")), "SELL is holding while the button is down")
	assert_true(float(button.call("hold_ratio")) > 0.0 and float(button.call("hold_ratio")) < 1.0, "SELL hold shows partial progress")
	harness.capture("commit-danger-hold")
	_push_mouse(viewport, centre, false)
	await harness.settle()
	assert_false(bool(button.call("is_holding")), "Releasing cancels the hold")
	assert_true(is_zero_approx(float(button.call("hold_ratio"))), "A cancelled hold resets its ring")
	assert_eq(
		Array(Simulation.run_state.build.get("hardware", [])).size(), hardware_before,
		"An early release sells nothing"
	)
	assert_true(seen_progress.size() > 0 and seen_progress[seen_progress.size() - 1] == 0.0, "hold_progress reported the cancel as 0")

	# Hold through: sells once.
	var fired: Array[int] = [0]
	var on_commit := func() -> void: fired[0] += 1
	button.connect("committed", on_commit)
	_push_mouse(viewport, centre, true)
	var sold: bool = await wait_until(harness, func() -> bool:
		return Array(Simulation.run_state.build.get("hardware", [])).size() < hardware_before
	, int(float(button.call("hold_seconds")) * 1000.0) + 2500)
	_push_mouse(viewport, centre, false)
	await harness.settle()
	assert_true(sold, "Holding SELL through the ring sells the item")
	assert_eq(fired[0], 1, "The hold commits exactly once")
	button.disconnect("committed", on_commit)
	button.disconnect("hold_progress", on_progress)
	Engine.time_scale = clock_before
	# Selection is preserved where it still exists, else the shelf stays on RIG.
	assert_eq(str(market.call("current_shelf")), "rig", "The RIG shelf stays up after a sale")


func _first_sellable() -> String:
	for row in UpgradePresentation.installed_inventory():
		var key: String = str(Dictionary(row).get("key", ""))
		if key != "" and Simulation.can_sell_hardware(key):
			return key
	return ""


## A starter rig came with the run and cannot be sold; buy one machine through
## the simulation (with a cash top-up that is taken back) so SELL has a target.
func _buy_something_sellable() -> String:
	if not Simulation.market_open():
		return ""
	var cash_before: float = float(Simulation.run_state.economy.get("cash", 0.0))
	Simulation.run_state.economy["cash"] = cash_before + 1_000_000.0
	var bought: String = ""
	for upgrade in ContentDatabase.upgrades:
		if upgrade.hardware_key == "" or upgrade.category == "component":
			continue
		if not Simulation.can_buy_upgrade(upgrade.id):
			continue
		if Simulation.buy_upgrade(upgrade.id):
			bought = upgrade.hardware_key
			break
	Simulation.run_state.economy["cash"] = cash_before
	if bought != "" and Simulation.can_sell_hardware(bought):
		return bought
	return _first_sellable()


## Selected cards and cartridges under a tab, by their own `is_selected`.
func _selected_tile_count(root: Node) -> int:
	var count: Array[int] = [0]
	_walk(root, func(node: Node) -> void:
		if (node is CabinetTile or node is ModuleCartridge) and node.has_method("is_selected") and bool(node.call("is_selected")):
			count[0] += 1
	)
	return count[0]


func _walk(node: Node, visit: Callable) -> void:
	visit.call(node)
	for child in node.get_children():
		_walk(child, visit)


func _push_mouse(viewport: Viewport, at: Vector2, down: bool) -> void:
	if viewport == null:
		return
	if down:
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		viewport.push_input(motion)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = at
	event.global_position = at
	viewport.push_input(event)


## While a burn plays back the commit is busy: WORKING, disabled, and a press
## on it does not skip the playback. The CRT's SKIP key does.
func _busy_during_burn(harness: UiHarness, shell: Node, screen: CabinetScreen, button: Control) -> void:
	shell.switch_tab("run")
	await harness.settle()
	if not Simulation.can_start_work() and not Simulation.is_work_running():
		# Take the first offer through the simulation so the shell stays put.
		for job in Array(Simulation.run_state.business.get("job_offers", [])):
			if Simulation.accept_job(str(Dictionary(job).get("id", ""))):
				break
		shell.refresh_all()
		await harness.settle()
	if not Simulation.can_start_work() and not Simulation.is_work_running():
		print("    run: cannot start work on seed 101 at this point; busy path not exercised")
		return
	shell.refresh_all()
	await harness.settle()
	var reading: Dictionary = _button_reading(button)
	assert_true(str(reading["label"]).begins_with("BURN"), "RUN arms BURN before the burn")
	assert_true(bool(reading["enabled"]), "BURN is enabled when work can start")
	assert_eq(str(button.call("state")), "armed", "BURN is the armed face")
	harness.capture("commit-armed")
	await harness.driver.press(button)
	var burning: bool = await wait_until(harness, func() -> bool: return bool(button.call("is_busy")), 3000)
	assert_true(burning, "Pressing BURN puts the commit into busy")
	if burning:
		var busy: Dictionary = _button_reading(button)
		assert_eq(str(busy["label"]), "WORKING", "Busy commit says WORKING")
		assert_false(bool(busy["enabled"]), "Busy commit is disabled")
		assert_eq(str(button.call("state")), "busy", "Busy commit is the busy state")
		await harness.get_tree().process_frame
		harness.capture("commit-busy")
		# Pressing the busy button never skips. The driver refuses disabled
		# controls, so the press goes straight to the viewport.
		var before: int = Time.get_ticks_msec()
		var viewport: Viewport = button.get_viewport()
		var centre: Vector2 = button.get_global_rect().get_center()
		_push_mouse(viewport, centre, true)
		_push_mouse(viewport, centre, false)
		await harness.settle()
		assert_true(bool(button.call("is_busy")), "A press on the busy commit does not end the burn")
		# SKIP lives on the CRT while the burn is skippable.
		if screen.is_skip_visible():
			await harness.driver.press(screen.skip_key())
			var settled: bool = await wait_until(harness, func() -> bool: return not bool(button.call("is_busy")), 12000)
			assert_true(settled, "SKIP on the CRT ends the playback (%d ms)" % (Time.get_ticks_msec() - before))
		else:
			print("    run: burn was not skippable; waiting it out")
	var over: bool = await wait_until(harness, func() -> bool: return not bool(button.call("is_busy")), BURN_DEADLINE_MSEC)
	assert_true(over, "The burn playback ends")
	await harness.settle()
	assert_false(screen.is_skip_visible(), "SKIP hides once the burn is over")
	assert_true(str(button.call("state")) != "busy", "The commit leaves busy once the burn is over")


## Reads the deck for the active tab and checks it against the table. Returns
## the label seen, for callers that want to assert a specific word.
func _check_deck(shell: Node, screen: CabinetScreen, button: Control, key: String, context: String) -> String:
	shell.refresh_all()
	var allowed: Array = EXPECTED.get(key, [])
	var reading: Dictionary = _button_reading(button)
	var label: String = str(reading["label"])
	var enabled: bool = bool(reading["enabled"])
	var sub: String = str(reading["sub"])
	var where := "%s (%s)" % [key, context]
	assert_true(
		label in allowed,
		"%s commit label '%s' is one of %s" % [where, label, allowed]
	)
	if not enabled:
		assert_true(
			sub.strip_edges() != "",
			"%s disabled commit '%s' prints a blocker line" % [where, label]
		)
	# The run deck is the shell's own; every other tab answers primary_action.
	if key != "run":
		var tab: CabinetTab = screen.active_tab()
		assert_true(tab != null, "%s has an active CabinetTab" % where)
		if tab != null:
			var action: Dictionary = tab.primary_action()
			assert_eq(
				str(action.get("label", "")).to_upper(), label,
				"%s primary_action label matches the button" % where
			)
			assert_eq(
				bool(action.get("enabled", false)), enabled,
				"%s primary_action enabled state matches the button" % where
			)
			if not bool(action.get("enabled", false)):
				assert_true(
					str(action.get("sub", "")).strip_edges() != "",
					"%s disabled primary_action carries a sub/blocker text" % where
				)
			else:
				assert_true(
					action.get("pressed") is Callable and Callable(action["pressed"]).is_valid(),
					"%s enabled primary_action carries a valid pressed callable" % where
				)
	print("    %s -> %s%s%s" % [where, label, "" if enabled else " (disabled)", (" · " + sub) if sub != "" else ""])
	return label


## MODULES has a public way to arm a selection: arm a loose cartridge and pick
## a bay for SEAT, pick a seated bay with nothing armed for EJECT.
func _modules_matrix(harness: UiHarness, shell: Node, screen: CabinetScreen, button: Control) -> void:
	shell.switch_tab("modules")
	await harness.settle()
	var tab: CabinetTab = screen.active_tab()
	var dock: ModuleDock = _find_dock(shell)
	assert_true(tab != null and tab.has_method("arm") and tab.has_method("set_dock_slot"), "MODULES tab exposes arm / set_dock_slot")
	assert_true(dock != null, "The module dock is mounted")
	if tab == null or dock == null or not tab.has_method("arm"):
		return

	var slots: Array = Simulation.board_slots()
	var loose: Array[String] = _loose_modules(slots)
	# A starter board seats everything it owns. Eject one through the
	# simulation so the bin has a cartridge to arm; it goes back at the end.
	var ejected_id: String = ""
	var ejected_from: int = -1
	if loose.is_empty():
		for index in range(slots.size()):
			if str(slots[index]) != "" and Simulation.clear_slot(index):
				ejected_id = str(slots[index])
				ejected_from = index
				break
		shell.refresh_all()
		await harness.settle()
		slots = Simulation.board_slots()
		loose = _loose_modules(slots)
	var seated_slot: int = -1
	for index in range(slots.size()):
		if str(slots[index]) != "":
			seated_slot = index
			break
	var empty_slot: int = -1
	for index in range(slots.size()):
		if str(slots[index]) == "":
			empty_slot = index
			break

	# Nothing armed, nothing picked: SEAT, disabled, with its blocker.
	tab.call("arm", "")
	tab.call("set_dock_slot", -1)
	dock.select_slot(-1)
	await harness.settle()
	var idle: String = _check_deck(shell, screen, button, "modules", "nothing armed")
	assert_eq(idle, "SEAT", "MODULES with nothing armed shows SEAT")
	assert_false(_button_reading(button)["enabled"], "MODULES with nothing armed is disabled")

	# Armed but no bay picked: SEAT, disabled, 'tap a bay in the dock'.
	if not loose.is_empty():
		tab.call("arm", loose[0])
		tab.call("set_dock_slot", -1)
		await harness.settle()
		var armed: String = _check_deck(shell, screen, button, "modules", "armed, no bay")
		assert_eq(armed, "SEAT", "MODULES with a cartridge armed shows SEAT")
		assert_false(_button_reading(button)["enabled"], "SEAT is disabled until a bay is picked")
		# Armed and a bay picked: SEAT, enabled.
		var target: int = empty_slot if empty_slot >= 0 else (seated_slot if seated_slot >= 0 else -1)
		if target >= 0:
			dock.select_slot(target)
			tab.call("set_dock_slot", target)
			await harness.settle()
			var ready: String = _check_deck(shell, screen, button, "modules", "armed, bay %d" % (target + 1))
			assert_eq(ready, "SEAT", "MODULES armed over a bay shows SEAT")
			assert_eq(
				bool(_button_reading(button)["enabled"]), not Simulation.is_work_running(),
				"SEAT arms once a bay is picked (between burns)"
			)
		tab.call("arm", "")
	else:
		print("    modules: no loose cartridge to arm on seed 101; SEAT-enabled path not exercised")

	# Nothing armed, a seated bay picked: EJECT.
	if seated_slot >= 0:
		dock.select_slot(seated_slot)
		tab.call("set_dock_slot", seated_slot)
		await harness.settle()
		var eject: String = _check_deck(shell, screen, button, "modules", "seated bay %d picked" % (seated_slot + 1))
		assert_eq(eject, "EJECT", "MODULES over a seated bay shows EJECT")
		assert_eq(
			bool(_button_reading(button)["enabled"]), not Simulation.is_work_running(),
			"EJECT is armed between burns"
		)
	else:
		print("    modules: no seated module on seed 101; EJECT path not exercised")

	# Leave the dock as it was found for the next persona.
	dock.select_slot(-1)
	tab.call("set_dock_slot", -1)
	tab.call("arm", "")
	if ejected_id != "" and ejected_from >= 0:
		Simulation.place_module(ejected_id, ejected_from)
	shell.refresh_all()
	await harness.settle()


## MARKET's SYSTEMS shelf: a picked system arms UPGRADE, live exactly when the
## simulation says the next tier can be bought, blocked with its reason when
## not (no cash → NEED $N MORE; the top tier → MAXED OUT).
func _systems_shelf(harness: UiHarness, shell: Node, screen: CabinetScreen, button: Control) -> void:
	shell.switch_tab("market")
	await harness.settle()
	var market: CabinetTab = screen.active_tab()
	if market == null or not market.has_method("select_shelf"):
		assert_true(false, "MARKET tab exposes select_shelf")
		return
	assert_true(bool(market.call("select_shelf", "systems")), "MARKET has a SYSTEMS shelf")
	assert_true(bool(market.call("select_item", "control")), "MARKET can pick the control rack")
	await harness.settle()
	var info: Dictionary = Simulation.cabinet_system_next("control")
	var label: String = _check_deck(shell, screen, button, "market", "systems shelf, control picked")
	assert_eq(label, "UPGRADE", "A picked system arms UPGRADE")
	assert_eq(
		bool(_button_reading(button)["enabled"]), bool(info.get("can_upgrade", false)),
		"UPGRADE is live exactly when the simulation allows the next tier"
	)
	if bool(info.get("can_upgrade", false)):
		var cash: float = float(Simulation.run_state.economy.get("cash", 0.0))
		assert_true(
			str(_button_reading(button)["sub"]).begins_with(NumberFormat.format_cash(float(info.get("cost", 0.0)))),
			"UPGRADE's sub leads with the price (got '%s', cash %s)" % [str(_button_reading(button)["sub"]), NumberFormat.format_cash(cash)]
		)
	else:
		assert_eq(str(_button_reading(button)["sub"]), str(info.get("reason", "")), "UPGRADE's blocker is the simulation's reason")
	# No cash: blocked with NEED $N MORE (when the market is open and the tier
	# is otherwise available).
	var cash_before: float = float(Simulation.run_state.economy.get("cash", 0.0))
	if Simulation.market_open() and not bool(info.get("maxed", false)) and int(info.get("next_tier", 9)) <= CabinetSystems.max_tier_for_chapter(Simulation.run_state):
		Simulation.run_state.economy["cash"] = 0.0
		shell.refresh_all()
		await harness.settle()
		var broke: Dictionary = _button_reading(button)
		assert_eq(str(broke["label"]), "UPGRADE", "MARKET UPGRADE with no cash keeps its word")
		assert_false(bool(broke["enabled"]), "MARKET UPGRADE with no cash is disabled")
		assert_true(str(broke["sub"]).begins_with("NEED "), "MARKET UPGRADE with no cash says NEED $N MORE (got '%s')" % str(broke["sub"]))
		assert_eq(str(button.call("state")), "blocked", "MARKET UPGRADE with no cash is the blocked face")
		Simulation.run_state.economy["cash"] = cash_before
	# The top tier: MAXED OUT.
	var was: int = int(Simulation.cabinet_system_tiers().get("control", 1))
	CabinetSystems.set_tier(Simulation.run_state, "control", CabinetSystems.max_tier())
	shell.refresh_all()
	await harness.settle()
	var maxed: Dictionary = _button_reading(button)
	assert_false(bool(maxed["enabled"]), "MARKET UPGRADE at the top tier is disabled")
	assert_eq(str(maxed["sub"]), "MAXED OUT", "MARKET UPGRADE at the top tier says MAXED OUT")
	CabinetSystems.set_tier(Simulation.run_state, "control", was)
	assert_true(bool(market.call("select_shelf", "modules")), "MARKET goes back to MODULES")
	shell.refresh_all()
	await harness.settle()


func _loose_modules(slots: Array) -> Array[String]:
	var loose: Array[String] = []
	for module_id in Simulation.owned_modules():
		if not (str(module_id) in slots):
			loose.append(str(module_id))
	return loose


# --- Reading the button ------------------------------------------------------

## The commit button paints its word and its sub-line on two Labels in that
## order; `disabled` is the real Button state the driver and a keyboard see.
func _button_reading(button: Control) -> Dictionary:
	var labels: Array[Label] = []
	_collect_labels(button, labels)
	var label: String = labels[0].text.strip_edges().to_upper() if labels.size() > 0 else ""
	var sub: String = labels[1].text.strip_edges() if labels.size() > 1 else ""
	var enabled: bool = not (button as Button).disabled if button is Button else true
	if button.has_method("is_enabled"):
		enabled = bool(button.call("is_enabled"))
	return {"label": label, "sub": sub, "enabled": enabled}


func _collect_labels(node: Node, out: Array[Label]) -> void:
	for child in node.get_children():
		if child is Label:
			out.append(child)
		_collect_labels(child, out)


# --- Locators ----------------------------------------------------------------

func _find_screen(root: Node) -> CabinetScreen:
	return _find_first(root, func(node: Node) -> bool: return node is CabinetScreen) as CabinetScreen


func _find_dock(root: Node) -> ModuleDock:
	return _find_first(root, func(node: Node) -> bool: return node is ModuleDock) as ModuleDock


func _find_commit_button(root: Node) -> Control:
	return _find_first(root, func(node: Node) -> bool:
		return node is Button and node.has_method("set_action") and node.has_method("is_enabled")
	) as Control


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
