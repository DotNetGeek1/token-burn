class_name TabMarket
extends CabinetTab

## The shop on the glass. MODULES is a row of cartridges off the shelf; SYSTEMS
## is the cabinet's five tiered systems, each showing only the tier it can buy
## next; the hardware shelves are tiles grouped the way the old market grouped
## them; RIG is what is already installed, sellable back. The big red button is
## BUY, or UPGRADE on the systems shelf, or SELL on the rig shelf, or REROLL
## when the restock line is picked.

## A cabinet system went up a tier at this counter. The shell plays the
## install reveal off it; the tab knows nothing about the machine behind it.
signal system_upgraded(system_id: String, old_tier: int, new_tier: int)

const MODULES := "modules"
const SYSTEMS := "systems"
const RIG := "rig"
const RESTOCK := "restock"

## The painted tile of a system's next tier, as a row thumbnail.
const SYSTEM_TILE_PX := 44.0

var _shelf: String = MODULES
var _selected: String = ""
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


## The shelf currently up: MODULES, SYSTEMS, RIG or a hardware group key.
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
		refresh()
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


## Module shelf, the systems shelf, one shelf per hardware group the run can
## still buy into, and the rig. Keys are stable so a picked shelf survives a
## refresh; insertion order is strip order.
func _shelves() -> Dictionary:
	var shelves: Dictionary = {MODULES: [], SYSTEMS: []}
	for module_id in Simulation.module_market_stock():
		shelves[MODULES].append({"kind": "module", "id": str(module_id)})
	shelves[MODULES].append({"kind": "restock", "id": RESTOCK})
	for system_id in CabinetSystems.system_ids():
		shelves[SYSTEMS].append({"kind": "system", "id": str(system_id)})
	var state := Simulation.run_state
	for upgrade in ContentDatabase.upgrades:
		if not upgrade.repeatable:
			if upgrade.id in state.build["upgrades"]:
				continue
			if upgrade.hardware_key != "" and upgrade.hardware_key in state.build["hardware"]:
				continue
		if upgrade.requires_upgrade != "" and not (upgrade.requires_upgrade in state.build["upgrades"]):
			continue
		var key: String = UpgradePresentation.group_key(upgrade)
		if not shelves.has(key):
			shelves[key] = []
		shelves[key].append({"kind": "upgrade", "id": upgrade.id, "upgrade": upgrade})
	for key in shelves:
		if key == MODULES or key == SYSTEMS:
			continue
		shelves[key].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _quoted(a["upgrade"]) < _quoted(b["upgrade"])
		)
	var rig: Array = []
	for row in UpgradePresentation.installed_inventory():
		rig.append({"kind": "installed", "id": str(row.get("key", "")), "row": row})
	shelves[RIG] = rig
	return shelves


func _quoted(upgrade: UpgradeDefinition) -> float:
	return UpgradeSystem.quoted_cost(
		Simulation.run_state, upgrade, UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id)
	)


func _rebuild_strip(shelves: Dictionary) -> void:
	for child in _strip.get_children():
		_strip.remove_child(child)
		if child != _cash:
			child.queue_free()
	_shelf_buttons.clear()
	var keys: Array = [MODULES]
	for key in shelves:
		if key != MODULES and key != RIG:
			keys.append(key)
	keys.append(RIG)
	for key in keys:
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
		RIG:
			return "RIG"
	return UpgradePresentation.group_label(key).to_upper()


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
	if _shelf == MODULES:
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
			var entry: Dictionary
			match str(Dictionary(item)["kind"]):
				"upgrade":
					entry = _upgrade_entry(item)
				"system":
					entry = _system_entry(item)
				_:
					entry = _installed_entry(item)
			tile.set_entry(entry)
			tile.set_selected(str(Dictionary(item)["id"]) == _selected)
			tile.pressed.connect(func(meta: Variant) -> void: _pick(str(meta)))
			column.add_child(tile)
	_scroll.add_child(_row)
	_empty.visible = items.is_empty()
	_empty.text = "NOTHING INSTALLED" if _shelf == RIG else "SHELF CLEARED — NEW STOCK ARRIVES AS YOU PROGRESS"


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


func _upgrade_entry(item: Dictionary) -> Dictionary:
	var upgrade: UpgradeDefinition = item["upgrade"]
	var level: int = UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id)
	var cost: float = UpgradeSystem.quoted_cost(Simulation.run_state, upgrade, level)
	var can_buy: bool = Simulation.can_buy_upgrade(upgrade.id)
	var affordable: bool = float(Simulation.run_state.economy.get("cash", 0.0)) >= cost
	var name: String = upgrade.name
	if level > 0:
		name = "%s ×%d" % [upgrade.name, level] if upgrade.category in ["hardware", "component"] else "%s Lv%d" % [upgrade.name, level]
	return {
		"meta": upgrade.id,
		"name": name.to_upper(),
		"sub": UpgradePresentation.effect_line(upgrade),
		"figure": NumberFormat.format_cash(cost),
		"figure_color": CabinetStyle.PHOSPHOR if affordable else CabinetStyle.RED,
		"status": "OPEN" if can_buy else _blocked_status(upgrade, affordable),
		"status_color": CabinetStyle.PHOSPHOR if can_buy else CabinetStyle.PHOSPHOR_DIM,
		"icon": AssetCatalog.cabinet_glyph("hardware"),
		"accent": UpgradePresentation.group_color(UpgradePresentation.group_key(upgrade)),
		"tooltip": upgrade.description,
	}


func _installed_entry(item: Dictionary) -> Dictionary:
	var row: Dictionary = item["row"]
	var key: String = str(row.get("key", ""))
	var can_sell: bool = Simulation.can_sell_hardware(key)
	var rate: float = float(row.get("token_rate", 0.0))
	return {
		"meta": key,
		"name": ("%s ×%d" % [str(row.get("name", key)), int(row.get("count", 1))]).to_upper(),
		"sub": ("%s TOKENS / PROMPT" % NumberFormat.format_token_rate(rate)) if rate > 0.0 else "fitted",
		"figure": NumberFormat.format_cash(float(row.get("refund", 0.0))),
		"figure_color": CabinetStyle.PHOSPHOR if can_sell else CabinetStyle.PHOSPHOR_DIM,
		"status": "SELLS FOR" if can_sell else "KEEPING IT",
		"status_color": CabinetStyle.PHOSPHOR_DIM,
		"icon": AssetCatalog.cabinet_glyph("hardware"),
		"accent": CabinetStyle.GREY,
		"tooltip": "" if can_sell else Simulation.hardware_sale_reason(key),
	}


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


func _blocked_status(upgrade: UpgradeDefinition, affordable: bool) -> String:
	if UpgradeSystem.is_maxed(Simulation.run_state, upgrade):
		return "MAX %d/%d" % [UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id), upgrade.max_level]
	if UpgradePresentation.prerequisite_text(upgrade) != "":
		return "LOCKED"
	if UpgradePresentation.hardware_space_full(upgrade):
		return "NO FLOOR SPACE"
	if UpgradePresentation.component_capacity_reached(upgrade):
		return "ALL FITTED"
	if not UpgradePresentation.cooling_shortfall(upgrade).is_empty():
		return "NEEDS COOLING"
	if not affordable:
		return "TOO DEAR"
	if not Simulation.market_open():
		return "CLOSED"
	return "BLOCKED"


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
		"upgrade":
			var upgrade: UpgradeDefinition = item["upgrade"]
			var cost: float = _quoted(upgrade)
			_title.text = upgrade.name.to_upper()
			_kicker.text = UpgradePresentation.group_label(UpgradePresentation.group_key(upgrade)).to_upper()
			_kicker.add_theme_color_override("font_color", CabinetStyle.PHOSPHOR_DIM)
			var rows: Array = [{"text": upgrade.description}]
			var effect: String = UpgradePresentation.effect_line(upgrade)
			if effect != "":
				rows.append({"rule": "EFFECT", "text": effect})
			var affordable: bool = cash >= cost
			for blocker in UpgradePresentation.blockers(upgrade, affordable):
				rows.append({"warn": str(blocker)})
			var warning: String = Simulation.purchase_bill_warning(cost)
			if warning != "":
				rows.append({"warn": warning})
			var heat: String = Simulation.upgrade_heat_warning(upgrade.id)
			if heat != "":
				rows.append({"warn": heat})
			detail_rows(_rows, rows)
			var summary: Array = [
				{"stat": "Cost", "value": NumberFormat.format_cash(cost), "color": CabinetStyle.PHOSPHOR if affordable else CabinetStyle.RED},
				{"stat": "You have", "value": NumberFormat.format_cash(cash)},
			]
			if upgrade.recurring_cost_delta > 0.0:
				summary.append({"stat": "Running cost", "value": "%s / round" % NumberFormat.format_cash(upgrade.recurring_cost_delta), "color": CabinetStyle.AMBER})
			var curve: Dictionary = UpgradePresentation.curve(upgrade)
			if float(curve.get("power_draw", 0.0)) > 0.0:
				summary.append({"stat": "Draw", "value": "%dW" % int(curve["power_draw"])})
			detail_rows(_summary, summary)
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
		"installed":
			var row: Dictionary = item["row"]
			var key: String = str(row.get("key", ""))
			_title.text = str(row.get("name", key)).to_upper()
			_kicker.text = "INSTALLED ×%d" % int(row.get("count", 1))
			_kicker.add_theme_color_override("font_color", CabinetStyle.PHOSPHOR_DIM)
			var rows: Array = []
			var reason: String = Simulation.hardware_sale_reason(key)
			if reason != "":
				rows.append({"warn": reason})
			else:
				rows.append({"text": "Sells back for part of its price. Its power draw and running cost leave with it."})
			detail_rows(_rows, rows)
			detail_rows(_summary, [
				{"stat": "Refund", "value": NumberFormat.format_cash(float(row.get("refund", 0.0))), "role": "money"},
				{"stat": "Draw", "value": "%dW" % int(row.get("power_draw", 0.0))},
			])


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
		"upgrade":
			var upgrade: UpgradeDefinition = item["upgrade"]
			var cost: float = _quoted(upgrade)
			var can: bool = Simulation.can_buy_upgrade(upgrade.id)
			if not can:
				return blocked_action("BUY", _upgrade_block(upgrade, cost, cash))
			return normalize_action({
				"label": "BUY", "enabled": true,
				"sub": _spend_sub(cost, cash),
				"pressed": _buy_upgrade.bind(upgrade.id),
			})
		"installed":
			var key: String = str(item["id"])
			var can: bool = Simulation.can_sell_hardware(key)
			if not can:
				var reason: String = Simulation.hardware_sale_reason(key).to_upper()
				return blocked_action("SELL", reason if reason != "" else "KEEPING IT")
			# Selling is the one market action that cannot be undone at the
			# same price, so it takes the hazard face and a hold.
			return normalize_action({
				"label": "SELL", "enabled": true,
				"tone": TONE_DANGER, "confirm": CONFIRM_HOLD,
				"sub": "%s BACK" % NumberFormat.format_cash(Simulation.hardware_sale_refund(key)),
				"pressed": _sell.bind(key),
			})
	return blocked_action("BUY", BLOCK_SELECT_ITEM)


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


func _upgrade_block(upgrade: UpgradeDefinition, cost: float, cash: float) -> String:
	if not Simulation.market_open():
		return BLOCK_MARKET_CLOSED
	if UpgradeSystem.is_maxed(Simulation.run_state, upgrade):
		return "MAXED OUT"
	if UpgradePresentation.prerequisite_text(upgrade) != "":
		return "LOCKED · %s" % UpgradePresentation.prerequisite_text(upgrade).to_upper()
	if UpgradePresentation.hardware_space_full(upgrade):
		return "NO FLOOR SPACE"
	if UpgradePresentation.component_capacity_reached(upgrade):
		return "ALL FITTED"
	if not UpgradePresentation.cooling_shortfall(upgrade).is_empty():
		return "NEEDS COOLING"
	if cost > cash:
		return need_more_blocker(int(ceil(cost - cash)))
	return "UNAVAILABLE"


func _buy_module(id: String) -> void:
	if Simulation.buy_module(id):
		UiSound.play("buy")
		_after_trade()
	else:
		UiSound.play("error")


func _buy_upgrade(id: String) -> void:
	if Simulation.buy_upgrade(id):
		UiSound.play("buy")
		_after_trade()
	else:
		UiSound.play("error")


func _sell(key: String) -> void:
	if Simulation.sell_hardware(key):
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
	refresh()
	changed.emit()
