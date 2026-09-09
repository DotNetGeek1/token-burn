class_name TabMarket
extends CabinetTab

## The shop on the glass: five cabinet systems and module cartridges.

## A cabinet system went up a tier at this counter. The shell plays the
## install reveal off it; the tab knows nothing about the machine behind it.
signal system_upgraded(system_id: String, old_tier: int, new_tier: int)

const MODULES := "modules"
const SYSTEMS := "systems"
const CALIBRATE := "calibrate"
const RESTOCK := "restock"

## The painted tile of a system's next tier, as a row thumbnail.
const SYSTEM_TILE_PX := 44.0

var _shelf: String = SYSTEMS
var _selected: String = ""
## On the CALIBRATE shelf: the owned modules picked to be consumed for the
## selected target. Cleared whenever the target or the shelf changes.
var _consume: Array = []
var _strip: HBoxContainer = null
var _shelf_buttons: Dictionary = {}
var _scroll: ScrollContainer = null
var _row: BoxContainer = null
var _empty: Label = null
var _title: Label = null
var _kicker: Label = null
var _rows: VBoxContainer = null
var _summary: VBoxContainer = null
var _cash: Label = null


func tab_key() -> String:
	return "market"


func _ready() -> void:
	super._ready()
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_theme_constant_override("separation", 3)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	_strip = make_strip()
	column.add_child(_strip)
	_cash = CabinetStyle.mono("", CabinetStyle.FONT_SMALL, CabinetStyle.PHOSPHOR)
	_cash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Parented now so it is owned by the tree; the strip rebuild moves it to
	# the end of the row each time.
	_strip.add_child(_cash)

	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var shelf := PanelContainer.new()
	shelf.mouse_filter = Control.MOUSE_FILTER_PASS
	shelf.add_theme_stylebox_override("panel", CabinetStyle.frame(CabinetStyle.AMBER, 0.3, 0.02))
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf.size_flags_stretch_ratio = 1.6
	body.add_child(shelf)
	_scroll = ScrollContainer.new()
	shelf.add_child(_scroll)
	_empty = CabinetStyle.mono("", CabinetStyle.FONT_SMALL, CabinetStyle.PHOSPHOR_DIM)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shelf.add_child(_empty)

	var detail := VBoxContainer.new()
	detail.mouse_filter = Control.MOUSE_FILTER_PASS
	detail.add_theme_constant_override("separation", 2)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(detail)
	_title = CabinetStyle.mono("", CabinetStyle.FONT_SMALL, CabinetStyle.AMBER)
	detail.add_child(_title)
	_kicker = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
	detail.add_child(_kicker)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(detail_scroll)
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_PASS
	_rows.add_theme_constant_override("separation", 1)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_rows)
	_summary = VBoxContainer.new()
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary.add_theme_constant_override("separation", 0)
	detail.add_child(_summary)


func refresh() -> void:
	# The shelf is rebuilt from scratch; the pick and the scroll survive it so a
	# BUY does not throw the player back to the top of the list.
	var scrolls: Dictionary = capture_scroll(self)
	var shelves: Dictionary = _shelves()
	_rebuild_strip(shelves)
	_cash.text = "CREDITS %s" % NumberFormat.format_cash(float(Simulation.run_state.economy.get("cash", 0.0)))
	if not shelves.has(_shelf):
		_shelf = MODULES
	_rebuild_shelf(shelves)
	_refresh_detail()
	restore_scroll(self, scrolls)


## The shelf currently up: SYSTEMS or MODULES.
func current_shelf() -> String:
	return _shelf


## The id of the picked item, "" when the shelf is bare.
func selected_id() -> String:
	return _selected


## Brings a shelf up by key (as `_shelves` names them). Returns false when
## there is no such shelf. For the shell and the playtests; taps go via the strip.
func select_shelf(key: String) -> bool:
	if not _shelves().has(key):
		return false
	if _shelf != key:
		_shelf = key
		_selected = ""
		_consume.clear()
		refresh()
		changed.emit()
	return true


## The modules picked to be consumed on the CALIBRATE shelf, for the playtests.
func consume_picks() -> Array:
	return _consume.duplicate()


## Toggles one owned module in or out of the consume pick. Returns false when
## it cannot be picked (not owned, the target itself, or seated in a workflow).
func toggle_consume(module_id: String) -> bool:
	if _shelf != CALIBRATE or module_id == _selected:
		return false
	if module_id in _consume:
		_consume.erase(module_id)
	else:
		if not (module_id in CalibrationSystem.consumable_modules(Simulation.run_state, _selected)):
			return false
		if _consume.size() >= CalibrationSystem.modules_consumed():
			_consume.pop_front()
		_consume.append(module_id)
	_refresh_detail()
	changed.emit()
	return true


## Picks an item on the current shelf by id. Returns false when it is not there.
func select_item(id: String) -> bool:
	var found: bool = false
	for item in Array(_shelves().get(_shelf, [])):
		if str(Dictionary(item)["id"]) == id:
			found = true
			break
	if not found:
		return false
	_pick(id)
	return true


## Stable shelf keys preserve selection after a purchase.
func _shelves() -> Dictionary:
	var shelves: Dictionary = {SYSTEMS: [], MODULES: [], CALIBRATE: []}
	for module_id in Simulation.module_market_stock():
		shelves[MODULES].append({"kind": "module", "id": str(module_id)})
	shelves[MODULES].append({"kind": "restock", "id": RESTOCK})
	for system_id in CabinetSystems.system_ids():
		shelves[SYSTEMS].append({"kind": "system", "id": str(system_id)})
	# Every owned module is a calibration target; the consume picks come from
	# the same list minus the target and anything seated in a workflow.
	for module_id in Array(Simulation.run_state.build.get("modules", [])):
		shelves[CALIBRATE].append({"kind": "calibrate", "id": str(module_id)})
	return shelves



func _rebuild_strip(shelves: Dictionary) -> void:
	for child in _strip.get_children():
		_strip.remove_child(child)
		if child != _cash:
			child.queue_free()
	_shelf_buttons.clear()
	for key in shelves:
		var label: String = _shelf_label(key)
		var button: Button = CabinetStyle.tab("%s %d" % [label, Array(shelves[key]).size() - (1 if key == MODULES else 0)])
		button.add_theme_font_size_override("font_size", CabinetStyle.FONT_TINY)
		button.pressed.connect(_on_shelf.bind(key))
		CabinetStyle.set_tab_active(button, key == _shelf)
		_strip.add_child(button)
		_shelf_buttons[key] = button
	_strip.add_child(_cash)


func _shelf_label(key: String) -> String:
	match key:
		MODULES:
			return "MODULES"
		SYSTEMS:
			return "SYSTEMS"
		CALIBRATE:
			return "CALIBRATE"
	return key.to_upper()


func _rebuild_shelf(shelves: Dictionary) -> void:
	if _row != null:
		_scroll.remove_child(_row)
		_row.queue_free()
		_row = null
	var items: Array = shelves[_shelf]
	var ids: Array[String] = []
	for item in items:
		ids.append(str(Dictionary(item)["id"]))
	if not (_selected in ids):
		_selected = ids[0] if not ids.is_empty() else ""
		_consume.clear()
	if _shelf == MODULES or _shelf == CALIBRATE:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_theme_constant_override("separation", 4)
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_row = row
		var height: float = shelf_card_height(_scroll)
		for item in items:
			var id: String = str(Dictionary(item)["id"])
			if id == RESTOCK:
				var restock := CabinetTile.new()
				restock.custom_minimum_size = Vector2(height * 0.7, 0)
				restock.set_entry(_restock_entry())
				restock.set_selected(id == _selected)
				restock.pressed.connect(func(_meta: Variant) -> void: _pick(RESTOCK))
				row.add_child(restock)
				continue
			var cartridge := ModuleCartridge.new()
			cartridge.draggable = false
			cartridge.custom_minimum_size = Vector2(height * 0.58, height)
			cartridge.pressed.connect(_pick.bind(id))
			row.add_child(cartridge)
			cartridge.set_module(id)
			cartridge.set_selected(id == _selected)
	else:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_PASS
		column.add_theme_constant_override("separation", 2)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_row = column
		for item in items:
			var tile := CabinetTile.new()
			tile.set_entry(_system_entry(item))
			tile.set_selected(str(Dictionary(item)["id"]) == _selected)
			tile.pressed.connect(func(meta: Variant) -> void: _pick(str(meta)))
			column.add_child(tile)
	_scroll.add_child(_row)
	_empty.visible = items.is_empty()
	_empty.text = "NO MODULES OWNED" if _shelf == CALIBRATE else "SHELF CLEARED"


## One cabinet system as a row: the next tier's painted tile, the system's
## name, `TIER n → n+1 · <next tier name>`, what that does to the numbers, and
## the price (or MAXED). A maxed system shows the tier it is on.
func _system_entry(item: Dictionary) -> Dictionary:
	var id: String = str(item["id"])
	var info: Dictionary = Simulation.cabinet_system_next(id)
	var tier: int = int(info.get("tier", 1))
	var next_tier: int = int(info.get("next_tier", tier))
	var maxed: bool = bool(info.get("maxed", false))
	var can: bool = bool(info.get("can_upgrade", false))
	var cost: float = float(info.get("cost", -1.0))
	var cash: float = float(Simulation.run_state.economy.get("cash", 0.0))
	var reason: String = str(info.get("reason", ""))
	var sub: String
	if maxed:
		sub = "TIER %d · %s · TOP TIER" % [tier, str(info.get("tier_name", "")).to_upper()]
	else:
		sub = "TIER %d → %d · %s" % [tier, next_tier, str(info.get("next_tier_name", "")).to_upper()]
	var figure_color: Color = CabinetStyle.PHOSPHOR
	if maxed:
		figure_color = CabinetStyle.PHOSPHOR_DIM
	elif not can and cost > cash:
		figure_color = CabinetStyle.RED
	elif not can:
		figure_color = CabinetStyle.PHOSPHOR_DIM
	return {
		"meta": id,
		"name": str(info.get("name", id)).to_upper(),
		"sub": sub,
		"note": str(info.get("effect", "")),
		"figure": "MAXED" if maxed else NumberFormat.format_cash(cost),
		"figure_color": figure_color,
		"status": "OPEN" if can else _system_status(reason, maxed),
		"status_color": CabinetStyle.PHOSPHOR if can else CabinetStyle.PHOSPHOR_DIM,
		"icon": AssetCatalog.cabinet_system_tile(id, tier if maxed else next_tier),
		"icon_size": SYSTEM_TILE_PX,
		"icon_tint": CabinetStyle.WHITE,
		"accent": CabinetStyle.AMBER,
		"tooltip": "%s — %s" % [str(info.get("name", id)), str(info.get("effect", "")) if not maxed else "Top tier fitted."],
	}


## The short word under the price; the full sentence is on the button and in
## the detail column.
func _system_status(reason: String, maxed: bool) -> String:
	if maxed:
		return "TOP TIER"
	if reason == BLOCK_MARKET_CLOSED:
		return "CLOSED"
	if reason.begins_with("NEED "):
		return "TOO DEAR"
	if reason.begins_with("NEXT CHAPTER"):
		return "LOCKED"
	return "BLOCKED"


## "GENERATION 1 · IMPROVISED CABINET": the cabinet's derived generation, for
## the detail column. Presentation only; nothing reads a number out of it.
func _generation_line() -> String:
	var generation: Dictionary = Simulation.cabinet_generation()
	return "GENERATION %d · %s" % [int(generation.get("index", 0)) + 1, str(generation.get("name", "")).to_upper()]




func _restock_entry() -> Dictionary:
	var cost: float = Simulation.module_market_reroll_cost()
	var can: bool = Simulation.can_reroll_module_market()
	var market: Dictionary = Dictionary(Simulation.run_state.business.get("module_market", {}))
	return {
		"meta": RESTOCK,
		"name": "RESTOCK SHELF",
		"sub": "reroll #%d" % (int(market.get("rerolls", 0)) + 1),
		"figure": NumberFormat.format_cash(cost),
		"figure_color": CabinetStyle.PHOSPHOR if can else CabinetStyle.RED,
		"status": "OPEN" if can else "TOO DEAR",
		"status_color": CabinetStyle.PHOSPHOR if can else CabinetStyle.PHOSPHOR_DIM,
		"icon": AssetCatalog.cabinet_glyph("cache"),
		"accent": CabinetStyle.AMBER,
		"tooltip": "Redraws the shelf. Escalates until the next free restock.",
	}



func _selected_item() -> Dictionary:
	for item in Array(_shelves().get(_shelf, [])):
		if str(Dictionary(item)["id"]) == _selected:
			return item
	return {}


func _refresh_detail() -> void:
	var item: Dictionary = _selected_item()
	if item.is_empty():
		_title.text = "—"
		_kicker.text = ""
		detail_rows(_rows, [])
		detail_rows(_summary, [])
		return
	var cash: float = float(Simulation.run_state.economy.get("cash", 0.0))
	match str(item["kind"]):
		"module":
			var module: ModuleDefinition = ContentDatabase.get_module(str(item["id"]))
			if module == null:
				return
			var cost: float = Simulation.module_market_price(module.id)
			_title.text = module.name.to_upper()
			_kicker.text = "%s · %s · %s" % [module.rarity.to_upper(), module.category.to_upper(), Simulation.get_module_badge(module.id).to_upper()]
			_kicker.add_theme_color_override("font_color", AssetCatalog.rarity_color(module.rarity))
			var rows: Array = [{"text": Simulation.get_module_description(module.id)}]
			var partners: Array = module.combo_partners()
			if not partners.is_empty():
				var names: PackedStringArray = []
				for partner in partners:
					var other: ModuleDefinition = ContentDatabase.get_module(str(partner))
					names.append(other.name if other != null else str(partner))
				rows.append({"rule": "SYNERGY", "text": "Pairs with " + ", ".join(names)})
			var warning: String = Simulation.purchase_bill_warning(cost)
			if warning != "":
				rows.append({"warn": warning})
			detail_rows(_rows, rows)
			detail_rows(_summary, [
				{"stat": "Cost", "value": NumberFormat.format_cash(cost), "color": CabinetStyle.PHOSPHOR if cash >= cost else CabinetStyle.RED},
				{"stat": "You have", "value": NumberFormat.format_cash(cash)},
				{"stat": "After", "value": NumberFormat.format_cash(cash - cost), "color": CabinetStyle.PHOSPHOR if cash >= cost else CabinetStyle.RED},
			])
		"calibrate":
			_refresh_calibrate_detail(str(item["id"]), cash)
		"restock":
			var cost: float = Simulation.module_market_reroll_cost()
			_title.text = "RESTOCK SHELF"
			_kicker.text = "NEXT FREE RESTOCK: ROUND %d" % Simulation.module_market_next_restock_round()
			_kicker.add_theme_color_override("font_color", CabinetStyle.PHOSPHOR_DIM)
			detail_rows(_rows, [{"text": "Redraws every module on the shelf. Each paid reroll costs more until the shelf restocks itself."}])
			detail_rows(_summary, [
				{"stat": "Cost", "value": NumberFormat.format_cash(cost), "color": CabinetStyle.PHOSPHOR if cash >= cost else CabinetStyle.RED},
				{"stat": "You have", "value": NumberFormat.format_cash(cash)},
			])
		"system":
			var id: String = str(item["id"])
			var info: Dictionary = Simulation.cabinet_system_next(id)
			var tier: int = int(info.get("tier", 1))
			var maxed: bool = bool(info.get("maxed", false))
			var can: bool = bool(info.get("can_upgrade", false))
			var cost: float = float(info.get("cost", -1.0))
			_title.text = str(info.get("name", id)).to_upper()
			_kicker.text = "TIER %d · %s" % [tier, str(info.get("tier_name", "")).to_upper()]
			_kicker.add_theme_color_override("font_color", CabinetStyle.PHOSPHOR_DIM)
			var rows: Array = [{"rule": "FITTED", "text": _fitted_stats(id)}]
			if maxed:
				rows.append({"rule": "NEXT", "text": "TOP TIER — nothing more to fit"})
			else:
				rows.append({"rule": "NEXT", "text": "TIER %d · %s" % [int(info.get("next_tier", tier + 1)), str(info.get("next_tier_name", "")).to_upper()]})
				var effect: String = str(info.get("effect", ""))
				if effect != "":
					rows.append({"text": effect})
			if not can:
				rows.append({"warn": str(info.get("reason", ""))})
			elif cost > 0.0:
				var warning: String = Simulation.purchase_bill_warning(cost)
				if warning != "":
					rows.append({"warn": warning})
			rows.append({"text": _generation_line()})
			detail_rows(_rows, rows)
			var summary: Array = []
			if maxed:
				summary.append({"stat": "Cost", "value": "MAXED", "color": CabinetStyle.PHOSPHOR_DIM})
			else:
				summary.append({"stat": "Cost", "value": NumberFormat.format_cash(cost), "color": CabinetStyle.PHOSPHOR if cash >= cost else CabinetStyle.RED})
			summary.append({"stat": "You have", "value": NumberFormat.format_cash(cash)})
			if not maxed:
				summary.append({"stat": "After", "value": NumberFormat.format_cash(cash - cost), "color": CabinetStyle.PHOSPHOR if cash >= cost else CabinetStyle.RED})
			detail_rows(_summary, summary)



## The CALIBRATE detail: the target's rank and what a rank buys, the consume
## picks as toggles, and the cost against the cash in hand.
func _refresh_calibrate_detail(id: String, cash: float) -> void:
	var module: ModuleDefinition = ContentDatabase.get_module(id)
	if module == null:
		return
	var state: RunState = Simulation.run_state
	var rank: int = Simulation.module_calibration_rank(id)
	var cap: int = CalibrationSystem.max_rank()
	var cost: float = Simulation.module_calibration_cost(id)
	var needed: int = CalibrationSystem.modules_consumed()
	_title.text = module.name.to_upper()
	_kicker.text = "%s · CALIBRATION %d/%d" % [module.rarity.to_upper(), rank, cap]
	_kicker.add_theme_color_override("font_color", AssetCatalog.rarity_color(module.rarity))
	var rows: Array = [{"text": Simulation.get_module_description(id)}]
	rows.append({"rule": "PER RANK", "text": "%s heat · %s power · %s tokens on this stage" % [
		_pct(CalibrationSystem.per_rank(CalibrationSystem.STAT_HEAT)),
		_pct(CalibrationSystem.per_rank(CalibrationSystem.STAT_POWER)),
		_pct(CalibrationSystem.per_rank(CalibrationSystem.STAT_EFFECT)),
	]})
	if rank > 0:
		rows.append({"rule": "FITTED", "text": "%s heat · %s power · %s tokens" % [
			_pct(CalibrationSystem.multiplier(state, id, CalibrationSystem.STAT_HEAT)),
			_pct(CalibrationSystem.multiplier(state, id, CalibrationSystem.STAT_POWER)),
			_pct(CalibrationSystem.multiplier(state, id, CalibrationSystem.STAT_EFFECT)),
		]})
	var candidates: Array = CalibrationSystem.consumable_modules(state, id)
	if rank >= cap:
		rows.append({"text": "Fully calibrated — nothing more to tune."})
	else:
		rows.append({"rule": "CONSUME", "text": "Pick %d benched modules to strip for parts (%d/%d)." % [needed, _consume.size(), needed]})
		if candidates.is_empty():
			rows.append({"warn": "No benched modules to consume. Unseat one on the MODULES tab."})
	var reason: String = Simulation.calibration_block_reason(id, _consume)
	if reason != "" and rank < cap and _consume.size() == needed:
		rows.append({"warn": reason})
	elif reason == "":
		var warning: String = Simulation.purchase_bill_warning(cost)
		if warning != "":
			rows.append({"warn": warning})
	detail_rows(_rows, rows)
	if rank < cap and not candidates.is_empty():
		_rows.add_child(_consume_toggles(candidates))
	var summary: Array = []
	if rank >= cap:
		summary.append({"stat": "Cost", "value": "MAXED", "color": CabinetStyle.PHOSPHOR_DIM})
	else:
		summary.append({"stat": "Cost", "value": NumberFormat.format_cash(cost), "color": CabinetStyle.PHOSPHOR if cash >= cost else CabinetStyle.RED})
	summary.append({"stat": "You have", "value": NumberFormat.format_cash(cash)})
	if rank < cap:
		summary.append({"stat": "After", "value": NumberFormat.format_cash(cash - cost), "color": CabinetStyle.PHOSPHOR if cash >= cost else CabinetStyle.RED})
	detail_rows(_summary, summary)


## One toggle per consumable module; picked ones are lit like an active tab.
func _consume_toggles(candidates: Array) -> Control:
	var flow := HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_PASS
	flow.add_theme_constant_override("h_separation", 2)
	flow.add_theme_constant_override("v_separation", 2)
	for candidate in candidates:
		var module_id: String = str(candidate)
		var module: ModuleDefinition = ContentDatabase.get_module(module_id)
		var button: Button = CabinetStyle.tab(module.name if module != null else module_id)
		button.add_theme_font_size_override("font_size", CabinetStyle.FONT_TINY)
		CabinetStyle.set_tab_active(button, module_id in _consume)
		button.tooltip_text = Simulation.get_module_description(module_id)
		button.pressed.connect(_on_consume_toggle.bind(module_id))
		flow.add_child(button)
	return flow


func _on_consume_toggle(module_id: String) -> void:
	UiSound.play("tap")
	toggle_consume(module_id)


## "−8%" / "+6%": a multiplier as the change it makes.
func _pct(mult: float) -> String:
	var delta: int = int(round((mult - 1.0) * 100.0))
	return "%s%d%%" % ["+" if delta >= 0 else "−", absi(delta)]


## "16 COOLING · 100 HEAT CAP": what the fitted tier is worth right now.
func _fitted_stats(system_id: String) -> String:
	var parts: PackedStringArray = []
	for stat_key in CabinetSystems.stat_keys(system_id):
		var key: String = str(stat_key)
		var value: float = CabinetSystems.capacity(Simulation.run_state, system_id, key)
		var figure: String = NumberFormat.format(value) if key == "base_token_rate" else str(int(round(value)))
		parts.append("%s %s" % [figure, CabinetSystems.stat_label(key)])
	return " · ".join(parts)


func primary_action() -> Dictionary:
	var item: Dictionary = _selected_item()
	if item.is_empty():
		return blocked_action("UPGRADE" if _shelf == SYSTEMS else "BUY", BLOCK_SELECT_ITEM)
	var cash: float = float(Simulation.run_state.economy.get("cash", 0.0))
	match str(item["kind"]):
		"system":
			var id: String = str(item["id"])
			var info: Dictionary = Simulation.cabinet_system_next(id)
			if not bool(info.get("can_upgrade", false)):
				var reason: String = str(info.get("reason", "")).strip_edges()
				return blocked_action("UPGRADE", reason if reason != "" else "UNAVAILABLE")
			return normalize_action({
				"label": "UPGRADE", "enabled": true,
				"sub": _spend_sub(float(info.get("cost", 0.0)), cash),
				"pressed": _upgrade_system.bind(id),
			})
		"module":
			var id: String = str(item["id"])
			var cost: float = Simulation.module_market_price(id)
			var can: bool = Simulation.can_buy_module(id)
			if not can:
				return blocked_action("BUY", _module_block(id, cost, cash))
			return normalize_action({
				"label": "BUY", "enabled": true,
				"sub": _spend_sub(cost, cash),
				"pressed": _buy_module.bind(id),
			})
		"calibrate":
			var id: String = str(item["id"])
			var reason: String = Simulation.calibration_block_reason(id, _consume)
			if reason != "":
				return blocked_action("CALIBRATE", reason)
			return normalize_action({
				"label": "CALIBRATE", "enabled": true,
				"sub": _spend_sub(Simulation.module_calibration_cost(id), cash),
				"pressed": _calibrate.bind(id),
			})
		"restock":
			var cost: float = Simulation.module_market_reroll_cost()
			var can: bool = Simulation.can_reroll_module_market()
			if not can:
				return blocked_action("REROLL", _restock_block(cost, cash))
			return normalize_action({
				"label": "REROLL", "enabled": true,
				"sub": _spend_sub(cost, cash),
				"pressed": _reroll,
			})
	return blocked_action("BUY", BLOCK_SELECT_ITEM)


func _calibrate(id: String) -> void:
	if Simulation.calibrate_module(id, _consume.duplicate()):
		UiSound.play("buy")
		_consume.clear()
		_selected = id
		_after_trade()
	else:
		UiSound.play("error")


## "$480 · LEFT $1,120": the price and what the player is left holding. Kept
## short because it sits under the commit word on a housing that is narrow at
## the handset size.
func _spend_sub(cost: float, cash: float) -> String:
	return "%s · LEFT %s" % [NumberFormat.format_cash(cost), NumberFormat.format_cash(maxf(0.0, cash - cost))]


func _module_block(id: String, cost: float, cash: float) -> String:
	if not Simulation.market_open():
		return BLOCK_MARKET_CLOSED
	if id in Array(Simulation.run_state.build.get("modules", [])):
		return "ALREADY OWNED"
	if cost > cash:
		return need_more_blocker(int(ceil(cost - cash)))
	return "UNAVAILABLE"


func _restock_block(cost: float, cash: float) -> String:
	if not Simulation.market_open():
		return BLOCK_MARKET_CLOSED
	if cost > cash:
		return need_more_blocker(int(ceil(cost - cash)))
	return "UNAVAILABLE"



func _buy_module(id: String) -> void:
	if Simulation.buy_module(id):
		UiSound.play("buy")
		_after_trade()
	else:
		UiSound.play("error")




func _reroll() -> void:
	if Simulation.reroll_module_market():
		UiSound.play("buy")
		_after_trade()
	else:
		UiSound.play("error")


## Buys the next tier of a cabinet system. The simulation charges, applies and
## autosaves before this returns; the shelf then refreshes with the same row
## picked and the same scroll, and the shell is told so it can play the
## install. A refusal prints its reason in the detail column and on the button.
func _upgrade_system(id: String) -> void:
	var result: Dictionary = Simulation.upgrade_cabinet_system(id)
	if bool(result.get("ok", false)):
		_selected = id
		_after_trade()
		system_upgraded.emit(id, int(result.get("previous_tier", 0)), int(result.get("tier", 0)))
	else:
		UiSound.play("error")
		refresh()
		changed.emit()


func _after_trade() -> void:
	shell.call("refresh_all")
	changed.emit()
	get_tree().call_group("ui_refresh", "refresh")


func _pick(id: String) -> void:
	UiSound.play("tap")
	if id != _selected:
		# A new calibration target starts with a clean consume pick.
		_consume.clear()
	_selected = id
	if _row != null:
		for child in _row.get_children():
			if child is ModuleCartridge:
				child.set_selected(child.module_id == id)
			elif child is CabinetTile:
				child.set_selected(str(child.meta) == id)
	_refresh_detail()
	changed.emit()


func _on_shelf(key: String) -> void:
	if _shelf == key:
		return
	UiSound.play("tap")
	_shelf = key
	_selected = ""
	_consume.clear()
	refresh()
	changed.emit()
