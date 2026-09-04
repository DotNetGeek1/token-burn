extends PlaytestCase

## The Market's SYSTEMS shelf: five rows, one per cabinet system, each showing
## only the tier it can buy next; picking one arms UPGRADE with the price and
## what is left; a short purse, a chapter cap and a top tier each print their
## own blocker. A successful UPGRADE is saved before the install reveal even
## starts, plays the reveal on the maintenance camera, and comes back to the
## Market on the same shelf, row and scroll. The reveal can be skipped.
##
## Runs at 1280x720 so the screenshots it captures (with --shots) show the
## shelf and the reveal at the compact desktop window.

const SYSTEMS: Array[String] = ["compute", "cooling", "power", "backplane", "control"]
const VIEW := Vector2i(1280, 720)
## Enough for any second tier, never a third.
const PURSE := 20_000.0


func play(harness: UiHarness) -> void:
	await harness.boot(211)
	var shell: Node = harness.current_scene()
	assert_true(
		shell != null and shell.has_method("switch_tab") and shell.has_method("maintenance_layer")
		and shell.has_method("is_maintenance"),
		"The cabinet shell is up with switch_tab / maintenance_layer / is_maintenance"
	)
	if shell == null or not shell.has_method("maintenance_layer"):
		return
	await harness.set_viewport(VIEW)
	var screen: CabinetScreen = _find_first(shell, func(node: Node) -> bool: return node is CabinetScreen) as CabinetScreen
	var button: Control = _find_first(shell, func(node: Node) -> bool:
		return node is Button and node.has_method("set_state") and node.has_method("is_enabled")
	) as Control
	var layer: MaintenanceLayer = shell.maintenance_layer()
	assert_true(screen != null and button != null and layer != null, "CRT, commit button and maintenance layer are mounted")
	if screen == null or button == null or layer == null:
		return

	shell.switch_tab("market")
	await harness.settle()
	var market: CabinetTab = screen.active_tab()
	assert_true(
		market != null and market.has_method("select_shelf") and market.has_method("select_item")
		and market.has_method("current_shelf") and market.has_method("selected_id"),
		"MARKET exposes select_shelf / select_item / current_shelf / selected_id"
	)
	if market == null or not market.has_method("select_shelf"):
		return
	if not Simulation.market_open():
		print("    market closed on seed 211 at boot; SYSTEMS shelf not exercised")
		return

	_strip_order(market)
	assert_true(bool(market.call("select_shelf", "systems")), "MARKET has a SYSTEMS shelf")
	shell.refresh_all()
	await harness.settle()
	assert_eq(str(market.call("current_shelf")), "systems", "The SYSTEMS shelf comes up")
	_rows(harness, market)
	await _arms_upgrade(harness, shell, market, button)
	await _short_purse(harness, shell, market, button)
	await _upgrade_and_reveal(harness, shell, screen, market, button, layer)
	await _chapter_cap(harness, shell, market, button)
	await _skipped_reveal(harness, shell, market, button, layer)
	await _maxed(harness, shell, market, button)
	_generation_is_derived()
	Simulation.autosave_enabled = false
	shell.switch_tab("run")
	await harness.settle()
	await harness.set_viewport(UiHarness.VIEW_DESKTOP)


# --- The shelf ---------------------------------------------------------------

## SYSTEMS sits after MODULES and before the hardware shelves in the strip,
## labelled with its five rows.
func _strip_order(market: CabinetTab) -> void:
	var words: Array[String] = []
	var strip: HBoxContainer = _find_first(market, func(node: Node) -> bool: return node is HBoxContainer) as HBoxContainer
	if strip != null:
		for child in strip.get_children():
			if child is Button:
				words.append(str((child as Button).text).strip_edges().to_upper())
	var modules_at: int = -1
	var systems_at: int = -1
	var rig_at: int = -1
	for index in range(words.size()):
		if words[index].begins_with("MODULES"):
			modules_at = index
		elif words[index].begins_with("SYSTEMS"):
			systems_at = index
		elif words[index].begins_with("RIG"):
			rig_at = index
	assert_true(systems_at >= 0, "The strip has a SYSTEMS shelf button (%s)" % str(words))
	assert_true(modules_at >= 0 and systems_at == modules_at + 1, "SYSTEMS comes straight after MODULES in the strip (%s)" % str(words))
	assert_true(rig_at > systems_at, "SYSTEMS comes before the hardware shelves and RIG (%s)" % str(words))
	if systems_at >= 0:
		assert_eq(words[systems_at], "SYSTEMS 5", "The SYSTEMS button counts its five rows")


## One row per system, in the authored order, each carrying the next tier's
## painted tile, its name, `TIER n → n+1 · <name>`, the effect and the price.
func _rows(harness: UiHarness, market: CabinetTab) -> void:
	var tiles: Array[CabinetTile] = _system_tiles(market)
	assert_eq(tiles.size(), 5, "The SYSTEMS shelf shows five rows")
	var ids: Array[String] = []
	for tile in tiles:
		ids.append(str(tile.meta))
	var authored: Array[String] = []
	for raw in CabinetSystems.system_ids():
		authored.append(str(raw))
	assert_eq(ids, authored, "Rows follow the authored system order")
	var view: Rect2 = harness.get_viewport().get_visible_rect()
	for tile in tiles:
		var id: String = str(tile.meta)
		var info: Dictionary = Simulation.cabinet_system_next(id)
		var texts: Array[String] = _texts(tile)
		var joined: String = " | ".join(texts)
		assert_true(joined.find(str(info.get("name", "")).to_upper()) >= 0, "%s row names the system (%s)" % [id, joined])
		if bool(info.get("maxed", false)):
			assert_true(joined.find("MAXED") >= 0, "%s row says MAXED at the top tier (%s)" % [id, joined])
		else:
			var tier_line: String = "TIER %d → %d · %s" % [int(info["tier"]), int(info["next_tier"]), str(info["next_tier_name"]).to_upper()]
			assert_true(joined.find(tier_line) >= 0, "%s row shows '%s' (%s)" % [id, tier_line, joined])
			assert_true(joined.find(str(info.get("effect", ""))) >= 0, "%s row shows the effect '%s' (%s)" % [id, str(info.get("effect", "")), joined])
			assert_true(joined.find(NumberFormat.format_cash(float(info["cost"]))) >= 0, "%s row shows the price (%s)" % [id, joined])
		# The next tier's painted tile, at a size a tile can be read at.
		var art: TextureRect = _find_first(tile, func(node: Node) -> bool: return node is TextureRect) as TextureRect
		var shown_tier: int = int(info["tier"]) if bool(info.get("maxed", false)) else int(info["next_tier"])
		assert_true(art != null and art.texture != null, "%s row carries a tile texture" % id)
		if art != null:
			assert_true(art.texture == AssetCatalog.cabinet_system_tile(id, shown_tier), "%s row shows the catalogue tile for tier %d" % [id, shown_tier])
			assert_true(art.size.x >= 36.0 and art.size.y >= 36.0, "%s row's tile is drawn at a readable size (%s)" % [id, str(art.size)])
		# Nothing on the row is cut to an ellipsis at this window.
		for label in _labels(tile):
			if label.text.strip_edges() == "" or not label.visible:
				continue
			var font: Font = label.get_theme_font("font")
			var px: int = label.get_theme_font_size("font_size")
			if font != null and label.size.x > 0.0:
				var width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
				assert_true(width <= label.size.x + 1.0, "%s row: '%s' fits its label (%.0f px in %.0f px)" % [id, label.text, width, label.size.x])
		# And the row is on the glass.
		assert_true(view.grow(1.0).encloses(tile.get_global_rect()) or tile.get_global_rect().size.y <= 0.0 or _in_scroll(tile), "%s row sits inside the window" % id)


## Picking a system arms UPGRADE with `$cost · LEFT $rest`; one row is
## marked; the detail column names the tier, the next tier and the generation.
func _arms_upgrade(harness: UiHarness, shell: Node, market: CabinetTab, button: Control) -> void:
	Simulation.run_state.economy["cash"] = PURSE
	assert_true(bool(market.call("select_item", "control")), "MARKET can pick the control rack")
	shell.refresh_all()
	await harness.settle()
	assert_eq(str(market.call("selected_id")), "control", "The control rack is the selection")
	assert_eq(_selected_count(market), 1, "Exactly one system row is marked")
	var info: Dictionary = Simulation.cabinet_system_next("control")
	var cost: float = float(info.get("cost", 0.0))
	var reading: Dictionary = _button_reading(button)
	assert_eq(str(reading["label"]), "UPGRADE", "A system row arms UPGRADE")
	assert_true(bool(reading["enabled"]), "UPGRADE is enabled with cash in hand")
	assert_eq(str(button.call("state")), "armed", "UPGRADE takes the armed face")
	var expected_sub: String = "%s · LEFT %s" % [NumberFormat.format_cash(cost), NumberFormat.format_cash(PURSE - cost)]
	assert_eq(str(reading["sub"]), expected_sub, "UPGRADE's sub is the price and what is left")
	var action: Dictionary = CabinetTab.normalize_action(market.primary_action())
	assert_eq(str(action["label"]), "UPGRADE", "primary_action label is UPGRADE")
	assert_true(bool(action["enabled"]), "primary_action is enabled")
	assert_eq(str(action["tone"]), CabinetTab.TONE_NORMAL, "UPGRADE is a normal-tone action")
	assert_eq(str(action["confirm"]), CabinetTab.CONFIRM_PRESS, "UPGRADE confirms on a press")
	assert_true(action["pressed"] is Callable and Callable(action["pressed"]).is_valid(), "UPGRADE carries a pressed callable")
	# The detail column.
	var detail: String = " | ".join(_texts(market))
	assert_true(detail.find("TIER %d · %s" % [int(info["tier"]), str(info["tier_name"]).to_upper()]) >= 0, "Detail shows the fitted tier and its name (%s)" % detail)
	assert_true(detail.find("TIER %d · %s" % [int(info["next_tier"]), str(info["next_tier_name"]).to_upper()]) >= 0, "Detail shows the next tier and its name")
	assert_true(detail.find(str(info["effect"])) >= 0, "Detail shows the stat delta")
	var generation: Dictionary = Simulation.cabinet_generation()
	var line: String = "GENERATION %d · %s" % [int(generation.get("index", 0)) + 1, str(generation.get("name", "")).to_upper()]
	assert_true(detail.find(line) >= 0, "Detail shows the generation line '%s'" % line)
	assert_true(detail.find("FITTED") >= 0, "Detail shows the fitted stat")
	await harness.get_tree().process_frame
	harness.capture("systems-armed-1280x720")


## No cash: the button is blocked and says NEED $N MORE; the detail says so too.
func _short_purse(harness: UiHarness, shell: Node, market: CabinetTab, button: Control) -> void:
	Simulation.run_state.economy["cash"] = 0.0
	shell.refresh_all()
	await harness.settle()
	var cost: float = float(Simulation.cabinet_system_next("control").get("cost", 0.0))
	var reading: Dictionary = _button_reading(button)
	assert_eq(str(reading["label"]), "UPGRADE", "A short purse keeps the UPGRADE word")
	assert_false(bool(reading["enabled"]), "UPGRADE is disabled with no cash")
	assert_eq(str(reading["sub"]), "NEED %s MORE" % NumberFormat.format_cash(cost), "UPGRADE says NEED $N MORE")
	assert_eq(str(button.call("state")), "blocked", "A short purse is the blocked face")
	var detail: String = " | ".join(_texts(market))
	assert_true(detail.find("NEED %s MORE" % NumberFormat.format_cash(cost)) >= 0, "Detail column prints the same blocker")
	Simulation.run_state.economy["cash"] = PURSE
	shell.refresh_all()
	await harness.settle()


## Pressing UPGRADE: the tier goes up and the cash down at once, the save on
## disk already carries the new tier while the camera is still moving, the
## reveal plays on the maintenance layer and lands back on the Market with the
## same shelf, row and scroll.
func _upgrade_and_reveal(harness: UiHarness, shell: Node, screen: CabinetScreen, market: CabinetTab, button: Control, layer: MaintenanceLayer) -> void:
	Simulation.autosave_enabled = true
	SaveManager.delete_save()
	var system_id: String = "control"
	var tier_before: int = int(Simulation.cabinet_system_tiers().get(system_id, 1))
	var cash_before: float = float(Simulation.run_state.economy.get("cash", 0.0))
	var cost: float = float(Simulation.cabinet_system_next(system_id).get("cost", 0.0))
	var scroll: ScrollContainer = _shelf_scroll(market)
	var scroll_before := Vector2.ZERO
	if scroll != null:
		scroll.scroll_vertical = 24
		await harness.settle()
		scroll_before = Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
	var upgraded: Array = []
	var on_upgraded := func(id: String, tier: int) -> void: upgraded.append([id, tier])
	EventBus.cabinet_system_upgraded.connect(on_upgraded)

	await harness.driver.press(button)
	# Straight after the press: the simulation has moved and the save is down.
	var tier_after: int = int(Simulation.cabinet_system_tiers().get(system_id, 1))
	assert_eq(tier_after, tier_before + 1, "UPGRADE raises the tier by one")
	assert_true(is_equal_approx(float(Simulation.run_state.economy.get("cash", 0.0)), cash_before - cost), "UPGRADE charges the quoted price")
	assert_eq(upgraded.size(), 1, "cabinet_system_upgraded fires once")
	assert_true(bool(shell.is_maintenance()), "The reveal opens the maintenance camera")
	assert_true(bool(shell.is_revealing()), "The shell reports a reveal in flight")
	var revealing: bool = layer.is_transitioning() or layer.is_installing()
	assert_true(revealing, "The camera is moving or the install is playing right after the press")
	var saved: Dictionary = SaveManager.load_run()
	var saved_tiers: Dictionary = Dictionary(Dictionary(Dictionary(saved.get("run_state", {})).get("build", {})).get("cabinet_systems", {}))
	assert_eq(int(saved_tiers.get(system_id, -1)), tier_after, "The save on disk carries the new tier before the reveal has finished")
	# The install lands on the right mount with the menu locked.
	var installing: bool = await wait_until(harness, func() -> bool: return layer.is_installing(), 4000)
	assert_true(installing, "The install reveal starts once the camera has settled")
	if installing:
		assert_eq(layer.selected_system(), system_id, "The reveal selects the upgraded mount")
		var resume: Button = layer.menu_key("resume")
		assert_true(resume != null and resume.disabled, "The maintenance menu is locked during the reveal")
		if harness.shots_enabled:
			# Real time for the frame: at the harness clock the flicker is over
			# in a frame or two.
			var clock: float = Engine.time_scale
			Engine.time_scale = 1.0
			var started: int = Time.get_ticks_msec()
			while Time.get_ticks_msec() - started < 180 and layer.is_installing():
				await harness.get_tree().process_frame
			harness.capture("systems-reveal-1280x720")
			Engine.time_scale = clock
	var over: bool = await wait_until(harness, func() -> bool:
		return not bool(shell.is_maintenance()) and not layer.is_transitioning()
	, 8000)
	assert_true(over, "The reveal ends and the camera returns to operation on its own")
	await harness.settle()
	assert_false(bool(shell.is_revealing()), "The reveal is over once the camera is back")
	assert_eq(str(shell.current_tab()), "market", "The Market is back on the glass")
	assert_true(screen.active_tab() == market, "The same Market tab instance is up")
	assert_eq(str(market.call("current_shelf")), "systems", "The SYSTEMS shelf is still up")
	assert_eq(str(market.call("selected_id")), system_id, "The upgraded system is still the selection")
	assert_eq(_selected_count(market), 1, "Still exactly one row marked")
	if scroll != null and scroll.is_inside_tree():
		assert_eq(Vector2(scroll.scroll_horizontal, scroll.scroll_vertical), scroll_before, "The shelf's scroll survives the reveal")
	var mount: Control = layer.mount(system_id)
	assert_true(mount != null and int(mount.call("tier")) == tier_after, "The mount wears the new tier after the reveal")
	assert_eq(layer.generation_caption(), str(Simulation.cabinet_generation().get("name", "")).to_upper(), "The generation stencil re-reads the run")
	var rows: Array[CabinetTile] = _system_tiles(market)
	for tile in rows:
		if str(tile.meta) == system_id:
			var joined: String = " | ".join(_texts(tile))
			assert_true(joined.find("TIER %d" % tier_after) >= 0, "The row now starts from tier %d (%s)" % [tier_after, joined])
	var resume_after: Button = layer.menu_key("resume")
	assert_true(resume_after == null or not bool(shell.is_maintenance()), "Menu lock does not outlive the reveal")
	EventBus.cabinet_system_upgraded.disconnect(on_upgraded)


## The bedroom caps every system at tier 2: the control rack, now at 2, is
## blocked with the chapter line rather than a price.
func _chapter_cap(harness: UiHarness, shell: Node, market: CabinetTab, button: Control) -> void:
	var cap: int = CabinetSystems.max_tier_for_chapter(Simulation.run_state)
	var tier: int = int(Simulation.cabinet_system_tiers().get("control", 1))
	if tier < cap or tier >= CabinetSystems.max_tier():
		print("    control is at tier %d under a chapter cap of %d; cap blocker not exercised" % [tier, cap])
		return
	Simulation.run_state.economy["cash"] = 1_000_000.0
	market.call("select_item", "control")
	shell.refresh_all()
	await harness.settle()
	var reading: Dictionary = _button_reading(button)
	assert_eq(str(reading["label"]), "UPGRADE", "A capped system keeps the UPGRADE word")
	assert_false(bool(reading["enabled"]), "UPGRADE is disabled past the chapter cap")
	assert_eq(str(reading["sub"]), "NEXT CHAPTER UNLOCKS TIER %d" % (tier + 1), "The blocker names the chapter cap")
	assert_eq(str(button.call("state")), "blocked", "The chapter cap is the blocked face")
	var detail: String = " | ".join(_texts(market))
	assert_true(detail.find("NEXT CHAPTER UNLOCKS TIER %d" % (tier + 1)) >= 0, "Detail column prints the chapter cap")
	# Pressing through the simulation is refused for the same reason.
	var result: Dictionary = Simulation.upgrade_cabinet_system("control")
	assert_false(bool(result.get("ok", true)), "The simulation refuses a tier past the chapter cap")
	assert_eq(str(result.get("reason", "")), "NEXT CHAPTER UNLOCKS TIER %d" % (tier + 1), "…with the same words")
	Simulation.run_state.economy["cash"] = PURSE


## A reveal can be skipped: the install jumps to its end and the camera comes
## straight back, still on the same row.
func _skipped_reveal(harness: UiHarness, shell: Node, market: CabinetTab, button: Control, layer: MaintenanceLayer) -> void:
	var system_id: String = "backplane"
	Simulation.run_state.economy["cash"] = PURSE
	market.call("select_item", system_id)
	shell.refresh_all()
	await harness.settle()
	var reading: Dictionary = _button_reading(button)
	if not bool(reading["enabled"]):
		print("    backplane not upgradable (%s); skip path not exercised" % str(reading["sub"]))
		return
	var tier_before: int = int(Simulation.cabinet_system_tiers().get(system_id, 1))
	await harness.driver.press(button)
	assert_true(bool(shell.is_maintenance()), "The second reveal opens the camera")
	var installing: bool = await wait_until(harness, func() -> bool: return layer.is_installing(), 4000)
	assert_true(installing, "The second install starts")
	layer.skip_install()
	assert_false(layer.is_installing(), "skip_install ends the install at once")
	await settle_camera(harness)
	assert_false(bool(shell.is_maintenance()), "A skipped reveal returns the camera at once")
	assert_eq(str(market.call("current_shelf")), "systems", "The SYSTEMS shelf is still up after a skip")
	assert_eq(str(market.call("selected_id")), system_id, "The skipped system is still the selection")
	assert_eq(int(Simulation.cabinet_system_tiers().get(system_id, 1)), tier_before + 1, "The skip changed nothing in the simulation")
	var mount: Control = layer.mount(system_id)
	assert_true(mount != null and int(mount.call("tier")) == tier_before + 1, "The mount wears the new tier after a skip")
	# System back during a reveal skips it too.
	var third: String = "cooling"
	market.call("select_item", third)
	shell.refresh_all()
	await harness.settle()
	if bool(_button_reading(button)["enabled"]):
		await harness.driver.press(button)
		var started: bool = await wait_until(harness, func() -> bool: return layer.is_installing(), 4000)
		assert_true(started, "The third install starts")
		shell.handle_system_back()
		assert_false(layer.is_installing(), "System back during a reveal skips the install")
		await settle_camera(harness)
		assert_false(bool(shell.is_maintenance()), "System back during a reveal lands back in operation")
		assert_eq(str(market.call("selected_id")), third, "The selection survives a back-skipped reveal")


## A system at the top tier shows MAXED, and UPGRADE is blocked with MAXED OUT.
func _maxed(harness: UiHarness, shell: Node, market: CabinetTab, button: Control) -> void:
	var system_id: String = "compute"
	var was: int = int(Simulation.cabinet_system_tiers().get(system_id, 1))
	CabinetSystems.set_tier(Simulation.run_state, system_id, CabinetSystems.max_tier())
	market.call("select_item", system_id)
	shell.refresh_all()
	await harness.settle()
	var reading: Dictionary = _button_reading(button)
	assert_eq(str(reading["label"]), "UPGRADE", "A maxed system keeps the UPGRADE word")
	assert_false(bool(reading["enabled"]), "UPGRADE is disabled at the top tier")
	assert_eq(str(reading["sub"]), "MAXED OUT", "The blocker says MAXED OUT")
	assert_eq(str(button.call("state")), "blocked", "MAXED OUT is the blocked face")
	var found: bool = false
	for tile in _system_tiles(market):
		if str(tile.meta) == system_id:
			found = true
			var joined: String = " | ".join(_texts(tile))
			assert_true(joined.find("MAXED") >= 0, "The maxed row shows MAXED in place of a price (%s)" % joined)
			assert_true(joined.find("TOP TIER") >= 0, "The maxed row says TOP TIER (%s)" % joined)
			var art: TextureRect = _find_first(tile, func(node: Node) -> bool: return node is TextureRect) as TextureRect
			assert_true(art != null and art.texture == AssetCatalog.cabinet_system_tile(system_id, CabinetSystems.max_tier()), "The maxed row shows its own top tile")
	assert_true(found, "The maxed system still has a row")
	var detail: String = " | ".join(_texts(market))
	assert_true(detail.find("MAXED OUT") >= 0 or detail.find("TOP TIER") >= 0, "Detail column says the system is at the top")
	CabinetSystems.set_tier(Simulation.run_state, system_id, was)
	shell.refresh_all()
	await harness.settle()


## The generation is a function of the tier sum and nothing else; no run
## number is read from it.
func _generation_is_derived() -> void:
	var generation: Dictionary = Simulation.cabinet_generation()
	var total: int = CabinetSystems.tier_sum(Simulation.run_state)
	var expected: Dictionary = CabinetSystems.generation_for_sum(total)
	assert_eq(int(generation.get("index", -1)), int(expected.get("index", -2)), "Generation index is derived from the tier sum")
	assert_eq(str(generation.get("name", "")), str(expected.get("name", "?")), "Generation name is derived from the tier sum")
	assert_false(Simulation.run_state.build.has("generation"), "The run stores no generation of its own")
	assert_false(Simulation.run_state.compute.has("generation"), "Compute stores no generation of its own")


# --- Reading the glass -------------------------------------------------------

func _system_tiles(market: Node) -> Array[CabinetTile]:
	var out: Array[CabinetTile] = []
	_walk(market, func(node: Node) -> void:
		if node is CabinetTile and str((node as CabinetTile).meta) in SYSTEMS:
			out.append(node)
	)
	return out


func _selected_count(root: Node) -> int:
	var count: Array[int] = [0]
	_walk(root, func(node: Node) -> void:
		if (node is CabinetTile or node is ModuleCartridge) and node.has_method("is_selected") and bool(node.call("is_selected")):
			count[0] += 1
	)
	return count[0]


## The shelf's own ScrollContainer: the first one under the tab.
func _shelf_scroll(market: Node) -> ScrollContainer:
	return _find_first(market, func(node: Node) -> bool: return node is ScrollContainer) as ScrollContainer


func _in_scroll(node: Node) -> bool:
	var parent: Node = node.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false


func _labels(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	_walk(root, func(node: Node) -> void:
		if node is Label:
			out.append(node)
	)
	return out


func _texts(root: Node) -> Array[String]:
	var out: Array[String] = []
	for label in _labels(root):
		if label.is_visible_in_tree() and label.text.strip_edges() != "":
			out.append(label.text.strip_edges())
	return out


## The commit button paints its word and its sub-line on two Labels in that
## order; `is_enabled` is the real Button state.
func _button_reading(button: Control) -> Dictionary:
	var labels: Array[Label] = _labels(button)
	var label: String = labels[0].text.strip_edges().to_upper() if labels.size() > 0 else ""
	var sub: String = labels[1].text.strip_edges() if labels.size() > 1 else ""
	var enabled: bool = bool(button.call("is_enabled")) if button.has_method("is_enabled") else not (button as Button).disabled
	return {"label": label, "sub": sub, "enabled": enabled}


func _walk(node: Node, visit: Callable) -> void:
	visit.call(node)
	for child in node.get_children():
		_walk(child, visit)


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
