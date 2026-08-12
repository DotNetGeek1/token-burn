extends Control

## The market as a stock listing on the terminal: two counters selected by number
## key, the shelves printed as sections of one table, and the pane underneath
## saying what a line does and what is stopping it being bought.
##
## Everything the card grid used to show is still here — the same shelves, the
## same blockers, the same purchase and sale calls — but the player reads down a
## price list instead of across a shop front.

@onready var frame: ConsoleFrame = $Margin/Frame

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

var _tab_row: HBoxContainer = null
var _tabs: Dictionary = {}
var _bills_line: Label = null
var _table: ConsoleTable = null
var _detail: ConsoleDetail = null
var _active_tab: String = "hardware"
var _selected: String = ""
var _rows: Dictionary = {}
var _console_scale: float = 1.0


func _ready() -> void:
	add_to_group("ui_refresh")
	add_to_group("console_screens")
	frame.setup("Market")
	_build_console()
	resized.connect(_fit_console)
	visibility_changed.connect(_on_visibility_changed)
	EventBus.upgrade_purchased.connect(func(_id): refresh())
	EventBus.run_started.connect(refresh)
	refresh()


func _build_console() -> void:
	var content: VBoxContainer = frame.content()

	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 6)
	content.add_child(_tab_row)
	var index: int = 1
	for tab in UpgradePresentation.TABS:
		var key: String = str(tab["key"])
		var button := ConsoleMenuRow.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.index_label = str(index)
		button.headline = str(tab["label"])
		button.pressed.connect(_on_tab_pressed.bind(key))
		_tab_row.add_child(button)
		button.set_metrics(ConsoleStyle.FONT_SMALL, ConsoleTable.ROW_HEIGHT, ConsoleTable.PAD_H)
		_tabs[key] = button
		index += 1

	_bills_line = ConsoleStyle.paragraph("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	content.add_child(_bills_line)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	_table = ConsoleTable.new()
	_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table.row_selected.connect(_on_row_selected)
	scroll.add_child(_table)
	_table.set_columns([
		{"label": "item", "weight": 2.0},
		{"label": "type", "weight": 1.0},
		{"label": "effect", "weight": 2.4},
		{"label": "cost", "weight": 1.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"label": "status", "weight": 1.1},
	])

	_detail = ConsoleDetail.new()
	_detail.size_flags_vertical = Control.SIZE_SHRINK_END
	_detail.action_pressed.connect(_on_detail_action)
	content.add_child(_detail)
	_detail.clear("SELECT AN ITEM")


func fit_console() -> void:
	_fit_console()


func _on_visibility_changed() -> void:
	if visible:
		call_deferred("_fit_console")


func _fit_console() -> void:
	if size.y <= 1.0:
		return
	_console_scale = ConsoleMetrics.compute_scale(size.y, get_viewport_rect().size.x)
	frame.set_metrics(_console_scale)
	if _table != null:
		_table.set_metrics(_console_scale)
	if _detail != null:
		_detail.set_metrics(_console_scale)
	for button in _tabs.values():
		if button is ConsoleMenuRow:
			button.set_metrics(
				ConsoleMetrics.font_small(_console_scale),
				ConsoleMetrics.row_height(_console_scale),
				ConsoleMetrics.pad_h(_console_scale)
			)
	if _bills_line != null:
		_bills_line.add_theme_font_size_override(
			"font_size", ConsoleMetrics.font_tiny(_console_scale)
		)


## The counters answer to the number keys, the way the title menu does.
func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var slot: int = event.keycode - KEY_1
	if slot < 0 or slot >= UpgradePresentation.TABS.size():
		return
	_on_tab_pressed(str(UpgradePresentation.TABS[slot]["key"]))
	get_viewport().set_input_as_handled()


func _on_tab_pressed(key: String) -> void:
	if _active_tab == key:
		return
	_active_tab = key
	_selected = ""
	refresh()


func refresh() -> void:
	var cash: float = float(Simulation.run_state.economy.get("cash", 0.0))
	frame.set_context(
		"WALLET %s" % NumberFormat.format_cash(cash),
		ConsoleStyle.PHOSPHOR if cash >= 0.0 else ConsoleStyle.DANGER
	)
	_refresh_bills_line()
	_rows.clear()
	_table.clear()

	var shelves: Dictionary = _shelves()
	_refresh_tabs(shelves)
	var shown: int = 0
	if _active_tab == "hardware":
		shown += _add_installed_section()
	for key in UpgradePresentation.GROUP_ORDER:
		if UpgradePresentation.tab_for_group(key) != _active_tab:
			continue
		if not shelves.has(key) or shelves[key].is_empty():
			continue
		_table.add_note("── %s ──" % UpgradePresentation.group_label(key).to_upper())
		for upgrade in shelves[key]:
			_add_upgrade_row(upgrade)
		shown += shelves[key].size()
	if shown == 0:
		_table.add_note("SHELF CLEARED — NEW STOCK ARRIVES AS YOU PROGRESS")

	if _selected == "" or not _table.select_meta(_selected):
		_detail.clear("SELECT AN ITEM")
	_fit_console()


## The counter the player is standing at is lit; the other carries its remaining
## stock so an empty shelf does not need visiting to find that out.
func _refresh_tabs(shelves: Dictionary) -> void:
	for tab in UpgradePresentation.TABS:
		var key: String = str(tab["key"])
		var row: ConsoleMenuRow = _tabs.get(key, null)
		if row == null:
			continue
		var count: int = 0
		for group_key in Array(tab["groups"]):
			count += Array(shelves.get(group_key, [])).size()
		row.value_text = "%d" % count
		row.set_selected(key == _active_tab)


# --- Rows --------------------------------------------------------------------

func _add_upgrade_row(upgrade: UpgradeDefinition) -> void:
	var level: int = UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id)
	var cost: float = UpgradeSystem.purchase_cost(upgrade, level)
	var can_buy: bool = Simulation.can_buy_upgrade(upgrade.id)
	var affordable: bool = float(Simulation.run_state.economy.get("cash", 0.0)) >= cost
	var meta: String = "buy:%s" % upgrade.id
	_rows[meta] = upgrade
	var status: String = "OPEN" if can_buy else _blocked_status(upgrade, affordable)
	_table.add_row([
		_row_title(upgrade, level),
		{
			"text": UpgradePresentation.group_label(
				UpgradePresentation.group_key(upgrade)
			).to_upper(),
			"color": ConsoleStyle.PHOSPHOR_DIM,
		},
		{"text": UpgradePresentation.effect_line(upgrade), "color": ConsoleStyle.PHOSPHOR_DIM},
		{
			"text": NumberFormat.format_cash(cost),
			"color": ConsoleStyle.PHOSPHOR if affordable else ConsoleStyle.DANGER,
		},
		{
			"text": status,
			"color": ConsoleStyle.PHOSPHOR if can_buy else ConsoleStyle.PHOSPHOR_DIM,
		},
	], meta)


## What is already installed, above the stock, because floor space is the binding
## constraint on the Hardware counter and the way past it is often to sell
## something rather than to move somewhere bigger.
func _add_installed_section() -> int:
	var inventory: Array = UpgradePresentation.installed_inventory()
	if inventory.is_empty():
		return 0
	_table.add_note("── INSTALLED ──")
	for row in inventory:
		var key: String = str(row.get("key", ""))
		var meta: String = "sell:%s" % key
		_rows[meta] = row
		var can_sell: bool = Simulation.can_sell_hardware(key)
		var count: int = int(row.get("count", 1))
		_table.add_row([
			str(row.get("name", key)),
			{
				"text": "COMPONENT" if bool(row.get("component", false)) else "HARDWARE",
				"color": ConsoleStyle.PHOSPHOR_DIM,
			},
			{"text": _installed_effect(row), "color": ConsoleStyle.PHOSPHOR_DIM},
			{
				"text": NumberFormat.format_cash(float(row.get("refund", 0.0))),
				"color": ConsoleStyle.PHOSPHOR if can_sell else ConsoleStyle.PHOSPHOR_DIM,
			},
			{
				"text": "OWNED x%d" % count,
				"color": ConsoleStyle.PHOSPHOR_DIM,
			},
		], meta)
	return inventory.size()


func _installed_effect(row: Dictionary) -> String:
	var parts: PackedStringArray = []
	var token_line: String = UpgradePresentation.token_rate_text(float(row.get("token_rate", 0.0)))
	if token_line != "":
		parts.append(token_line)
	if float(row.get("power_draw", 0.0)) > 0.0:
		parts.append("%dW draw" % int(row["power_draw"]))
	if bool(row.get("component", false)):
		parts.append("fitted inside, no floor space")
	else:
		var count: int = int(row.get("count", 1))
		parts.append("1 floor slot" if count == 1 else "%d floor slots" % count)
	return " · ".join(parts)


## Machines are counted rather than levelled: a second desktop is another box on
## the floor, not the same box upgraded.
func _row_title(upgrade: UpgradeDefinition, level: int) -> String:
	if level <= 0:
		return upgrade.name
	if upgrade.category == "hardware" or upgrade.category == "component":
		return "%s ×%d" % [upgrade.name, level]
	return "%s Lv%d" % [upgrade.name, level]


## Which wall the player hit, said in the status column so a locked line explains
## itself without being opened.
func _blocked_status(upgrade: UpgradeDefinition, affordable: bool) -> String:
	if UpgradePresentation.prerequisite_text(upgrade) != "":
		return "LOCKED"
	if UpgradePresentation.hardware_space_full(upgrade):
		return "NO FLOOR SPACE"
	if UpgradePresentation.component_capacity_reached(upgrade):
		return "ALL FITTED"
	if not affordable:
		return "TOO DEAR"
	return "BLOCKED"


## Stock the run could still be shown. Items whose unlock has not happened yet
## are absent rather than greyed: the cloud shelf is a rumour until the account
## exists. Premises are absent entirely — where the run happens was settled
## before it started and no amount of cash moves it.
func _shelves() -> Dictionary:
	var shelves: Dictionary = {}
	for upgrade in ContentDatabase.upgrades:
		if upgrade.category == "dwelling":
			continue
		if UpgradeSystem.is_maxed(Simulation.run_state, upgrade):
			continue
		if not upgrade.repeatable:
			if upgrade.id in Simulation.run_state.build["upgrades"]:
				continue
			if upgrade.hardware_key != "" and upgrade.hardware_key in Simulation.run_state.build["hardware"]:
				continue
		if upgrade.requires_upgrade != "":
			if not (upgrade.requires_upgrade in Simulation.run_state.build["upgrades"]):
				continue
		var key: String = UpgradePresentation.group_key(upgrade)
		if not shelves.has(key):
			shelves[key] = []
		shelves[key].append(upgrade)
	# Cheapest first, so a shelf reads as a run of affordable steps.
	for key in shelves:
		shelves[key].sort_custom(func(a: UpgradeDefinition, b: UpgradeDefinition) -> bool:
			return _card_cost(a) < _card_cost(b)
		)
	return shelves


func _card_cost(upgrade: UpgradeDefinition) -> float:
	return UpgradeSystem.purchase_cost(
		upgrade, UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id)
	)


# --- Detail pane -------------------------------------------------------------

func _on_row_selected(meta: Variant) -> void:
	_selected = str(meta) if meta != null else ""
	if _selected.begins_with("sell:"):
		_show_installed_detail(_rows.get(_selected, {}))
	elif _selected.begins_with("buy:"):
		_show_upgrade_detail(_rows.get(_selected, null))
	else:
		_detail.clear("SELECT AN ITEM")


func _show_installed_detail(row: Dictionary) -> void:
	if row.is_empty():
		_detail.clear("SELECT AN ITEM")
		return
	var key: String = str(row.get("key", ""))
	var can_sell: bool = Simulation.can_sell_hardware(key)
	var lines: Array = [
		{"stat": "Owned", "value": "×%d" % int(row.get("count", 1))},
		{"stat": "Sells for", "value": NumberFormat.format_cash(float(row.get("refund", 0.0)))},
		{"text": _installed_effect(row)},
	]
	if not can_sell:
		var reason: String = Simulation.hardware_sale_reason(key)
		if reason != "":
			lines.append({"text": reason})
	_detail.show_detail(
		str(row.get("name", key)).to_upper(),
		lines,
		"[ ENTER ] SELL FOR %s" % NumberFormat.format_cash(float(row.get("refund", 0.0)))
			if can_sell else "[ -- ] KEEPING IT",
		can_sell
	)


func _show_upgrade_detail(upgrade: UpgradeDefinition) -> void:
	if upgrade == null:
		_detail.clear("SELECT AN ITEM")
		return
	var level: int = UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id)
	var cost: float = UpgradeSystem.purchase_cost(upgrade, level)
	var can_buy: bool = Simulation.can_buy_upgrade(upgrade.id)
	var lines: Array = [{"stat": "Cost", "value": NumberFormat.format_cash(cost)}]
	if level > 0:
		var counted: bool = upgrade.category == "hardware" or upgrade.category == "component"
		lines.insert(0, {"stat": "Owned" if counted else "Level", "value": str(level)})
	if upgrade.recurring_cost_delta > 0.0:
		lines.append({
			"stat": "Adds to bills",
			"value": "%s / round" % NumberFormat.format_cash(upgrade.recurring_cost_delta),
			"color": ConsoleStyle.WARNING,
		})
	lines.append({"text": upgrade.description})
	lines.append({"text": UpgradePresentation.effect_line(upgrade)})
	lines.append_array(_blocker_lines(upgrade, cost, can_buy))
	if upgrade.repeatable and level > 0:
		lines.append({
			"text": "Each one after the first costs %d%% more than the last." % int(
				round((upgrade.cost_growth - 1.0) * 100.0)
			),
		})
	_detail.show_detail(
		upgrade.name.to_upper(),
		lines,
		"[ ENTER ] BUY FOR %s" % NumberFormat.format_cash(cost) if can_buy else "[ -- ] UNAVAILABLE",
		can_buy
	)


func _blocker_lines(upgrade: UpgradeDefinition, cost: float, can_buy: bool) -> Array:
	var lines: Array = []
	var cooling: Dictionary = UpgradePresentation.cooling_shortfall(upgrade)
	if not cooling.is_empty():
		lines.append({
			"warn": "Cooling %d / %d — running this adds %.0f heat per prompt. Buy cooling or a bigger space first." % [
				int(cooling["have"]), int(cooling["need"]), float(cooling["heat_per_prompt"]),
			],
		})
	var prerequisite: String = UpgradePresentation.prerequisite_text(upgrade)
	if prerequisite != "":
		var reason: String = "Take the step before it first."
		if upgrade.requires_dwelling != "":
			reason = "This belongs to a later chapter than the one this run is in."
		lines.append({"warn": "%s — %s" % [prerequisite, reason]})
	if UpgradePresentation.hardware_space_full(upgrade):
		var space: Dictionary = UpgradePresentation.hardware_space()
		lines.append({
			"warn": "The %s holds %d machines and all %d are running. Sell something first." % [
				space.get("dwelling", ""), int(space.get("total", 0)), int(space.get("used", 0)),
			],
		})
	if UpgradePresentation.component_capacity_reached(upgrade):
		lines.append({
			"warn": "One fits per %s you own. Buy another machine and there will be somewhere to put this." % UpgradePresentation.hardware_name(upgrade.requires_hardware),
		})
	if not can_buy:
		var shortfall: float = cost - float(Simulation.run_state.economy.get("cash", 0.0))
		if shortfall > 0.0:
			lines.append({
				"warn": "Need %s more. Finish a contract or take a better paying one." % NumberFormat.format_cash(shortfall),
			})
	elif _rent_shortfall(cost) > 0.0:
		lines.append({
			"warn": "%s short of rent if you buy this." % NumberFormat.format_cash(_rent_shortfall(cost)),
		})
	return lines


func _rent_shortfall(cost: float) -> float:
	var outlook: Dictionary = Simulation.bills_outlook()
	var left: float = float(outlook.get("cash", 0.0)) - cost
	return maxf(0.0, float(outlook.get("due", 0.0)) - left)


## The shop is the easiest place to spend rent money by accident, so what is safe
## to spend sits under the counters.
func _refresh_bills_line() -> void:
	var outlook: Dictionary = Simulation.bills_outlook()
	var line: String = "SAFE TO SPEND %s · %s DUE AT ROUND END" % [
		NumberFormat.format_cash(float(outlook.get("spendable", 0.0))),
		NumberFormat.format_cash(float(outlook.get("due", 0.0))),
	]
	if _active_tab == "hardware":
		var space: Dictionary = UpgradePresentation.hardware_space()
		line += " · %s: %d/%d HARDWARE SLOTS USED" % [
			str(space.get("dwelling", "")).to_upper(),
			int(space.get("used", 0)),
			int(space.get("total", 0)),
		]
	_bills_line.text = line


# --- Actions -----------------------------------------------------------------

func _on_detail_action() -> void:
	if _selected.begins_with("buy:"):
		_buy_upgrade(_selected.trim_prefix("buy:"))
	elif _selected.begins_with("sell:"):
		_sell_hardware(_selected.trim_prefix("sell:"))


func _buy_upgrade(upgrade_id: String) -> void:
	UiSound.play("buy")
	if Simulation.buy_upgrade(upgrade_id):
		refresh()
		get_tree().call_group("ui_refresh", "refresh")


func _sell_hardware(hardware_key: String) -> void:
	UiSound.play("buy")
	if Simulation.sell_hardware(hardware_key):
		refresh()
		get_tree().call_group("ui_refresh", "refresh")
