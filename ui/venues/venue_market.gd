extends VenueScene

## The market: a back room somewhere with the stock listed on a board.
##
## This is the same shop it has always been — the same shelves, the same
## blockers, the same purchase and sale calls — laid out as a place rather than
## as a price list in a 442-pixel column. The counters go down the left where the
## shop writes them up and the shelf itself is the big board on the wall. Stock
## is bought directly from that board, including on a handset where there is no
## useful room for a separate detail sign.
##
## The shelves are grouped one counter at a time rather than all printed under
## section rules. A wall board has the width for tiles and the tiles have room
## for the figure that actually decides a purchase, which the old table could
## only ever put in a column.

## The counter that lists what is already installed, so selling is reachable from
## the same place buying is. Not a shelf — nothing here is for sale to you.
const INSTALLED := "installed"

var _kicker: Label = null
var _index_lines: VBoxContainer = null
var _counters: VBoxContainer = null
var _board_panel: VenuePanel = null
var _board: VenueBoard = null
var _notice: Label = null
var _counter_rows: Dictionary = {}
var _active: String = "hardware"


func venue_key() -> String:
	return "market"


func _hint_entries() -> Array:
	return []


func _build_venue() -> void:
	_build_index()
	_build_board()
	_build_notice()
	EventBus.upgrade_purchased.connect(func(_id: String) -> void: refresh())
	EventBus.run_started.connect(refresh)


## The left-hand panel: who you are in this shop, what you can spend, and which
## counter you are standing at.
func _build_index() -> void:
	var panel: VenuePanel = add_panel("index", "Market", {
		"console_order": 10, "console_min": 190.0,
	})
	var content: VBoxContainer = panel.content()

	_kicker = ConsoleStyle.label(
		"HARDWARE AND SERVICES", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	content.add_child(_kicker)

	_index_lines = VBoxContainer.new()
	_index_lines.add_theme_constant_override("separation", 2)
	content.add_child(_index_lines)

	content.add_child(ConsoleStyle.rule(0.22))

	_counters = VBoxContainer.new()
	_counters.add_theme_constant_override("separation", 0)
	_counters.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_counters)


func _build_board() -> void:
	_board_panel = add_panel("board", "Hardware", {
		"console_order": 20, "console_min": 300.0, "grow": true,
	})
	_board = VenueBoard.new()
	_board.tile_action.connect(_on_market_action)
	_board_panel.content().add_child(_board)


## The right-hand sign. It is the shop's own notice until the player points at
## something, and then it is what that thing is and what is stopping them having
## it — which is where a buyer would look anyway.
## The crate by the door, which is where the shop keeps the one number that stops
## a purchase being a mistake: what the room this stock has to stand in has left.
func _build_notice() -> void:
	var panel: VenuePanel = add_panel("notice", "", {
		"console_order": 40, "console_hide": true,
	})
	_notice = ConsoleStyle.paragraph("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.content().add_child(_notice)


# --- Refresh -----------------------------------------------------------------

func refresh() -> void:
	if _board == null:
		return
	var shelves: Dictionary = _shelves()
	if not _counter_exists(_active, shelves):
		_active = _first_counter(shelves)
	_refresh_index(shelves)
	_refresh_counters(shelves)
	_refresh_board(shelves)
	_refresh_notice()


func _refresh_index(_shelves_data: Dictionary) -> void:
	for child in _index_lines.get_children():
		_index_lines.remove_child(child)
		child.queue_free()
	var cash: float = float(Simulation.run_state.economy.get("cash", 0.0))
	var outlook: Dictionary = Simulation.bills_outlook()
	var lines: Array = [
		{
			"stat": "Wallet",
			"value": NumberFormat.format_cash(cash),
			"color": ConsoleStyle.PHOSPHOR if cash >= 0.0 else ConsoleStyle.DANGER,
		},
		{
			"stat": "Safe to spend",
			"value": NumberFormat.format_cash(float(outlook.get("spendable", 0.0))),
		},
		{
			"stat": "Due at round end",
			"value": NumberFormat.format_cash(float(outlook.get("due", 0.0))),
			"color": ConsoleStyle.WARNING,
		},
	]
	for entry in lines:
		var line: Control = ConsoleStyle.detail_line(
			entry, ConsoleMetrics.font_small(console_scale())
		)
		if line != null:
			_index_lines.add_child(line)


## One line per counter that has something on it, with its stock count beside it.
## An empty shelf is absent rather than greyed: a counter with nothing behind
## it is not a place to stand.
func _refresh_counters(shelves: Dictionary) -> void:
	var wanted: Array[String] = []
	for key in UpgradePresentation.GROUP_ORDER:
		if shelves.has(key) and not Array(shelves[key]).is_empty():
			wanted.append(str(key))
	if not UpgradePresentation.installed_inventory().is_empty():
		wanted.append(INSTALLED)
	# Rebuilt only when the set of counters changes, because rebuilding a row the
	# pointer is over drops the hover the player is using to read it.
	if wanted != _counter_order():
		for child in _counters.get_children():
			_counters.remove_child(child)
			child.queue_free()
		_counter_rows.clear()
		var index: int = 1
		for key in wanted:
			var row := ConsoleMenuRow.new()
			row.index_label = str(index)
			row.headline = _counter_label(key)
			row.pressed.connect(_on_counter_pressed.bind(key))
			_counters.add_child(row)
			_counter_rows[key] = row
			index += 1
	for key in _counter_rows:
		var row: ConsoleMenuRow = _counter_rows[key]
		row.value_text = "%d" % _counter_count(str(key), shelves)
		row.set_selected(str(key) == _active)
	_layout_counter_rows()


func _counter_order() -> Array[String]:
	var keys: Array[String] = []
	for child in _counters.get_children():
		for key in _counter_rows:
			if _counter_rows[key] == child:
				keys.append(str(key))
	return keys


func _counter_label(key: String) -> String:
	if key == INSTALLED:
		return "INSTALLED"
	return UpgradePresentation.group_label(key).to_upper()


func _counter_count(key: String, shelves: Dictionary) -> int:
	if key == INSTALLED:
		return UpgradePresentation.installed_inventory().size()
	return Array(shelves.get(key, [])).size()


func _counter_exists(key: String, shelves: Dictionary) -> bool:
	if key == INSTALLED:
		return not UpgradePresentation.installed_inventory().is_empty()
	return shelves.has(key) and not Array(shelves[key]).is_empty()


func _first_counter(shelves: Dictionary) -> String:
	for key in UpgradePresentation.GROUP_ORDER:
		if shelves.has(key) and not Array(shelves[key]).is_empty():
			return str(key)
	return INSTALLED


func _on_counter_pressed(key: String) -> void:
	if _active == key:
		return
	_active = key
	_board.clear_selection()
	refresh()
	lean_on("board")


## The counters answer to the number keys, the way the title menu does.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if SceneRouter.investor_busy():
		return
	var slot: int = event.keycode - KEY_1
	var order: Array[String] = _counter_order()
	if slot < 0 or slot >= order.size():
		return
	_on_counter_pressed(order[slot])
	get_viewport().set_input_as_handled()


func _refresh_board(shelves: Dictionary) -> void:
	_board_panel.set_heading(_counter_label(_active))
	var entries: Array = []
	if _active == INSTALLED:
		entries = _installed_entries()
	else:
		for upgrade in Array(shelves.get(_active, [])):
			entries.append(_upgrade_entry(upgrade))
	var note: String = ""
	if entries.is_empty():
		note = "SHELF CLEARED — NEW STOCK ARRIVES AS YOU PROGRESS"
	_board.set_entries(entries, note)


func _refresh_notice() -> void:
	var space: Dictionary = UpgradePresentation.hardware_space()
	_notice.text = "%s\n%d / %d FLOOR SLOTS" % [
		str(space.get("dwelling", "")).to_upper(),
		int(space.get("used", 0)),
		int(space.get("total", 0)),
	]


# --- Tiles -------------------------------------------------------------------

func _upgrade_entry(upgrade: UpgradeDefinition) -> Dictionary:
	var level: int = UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id)
	var cost: float = UpgradeSystem.quoted_cost(Simulation.run_state, upgrade, level)
	var can_buy: bool = Simulation.can_buy_upgrade(upgrade.id)
	var affordable: bool = float(Simulation.run_state.economy.get("cash", 0.0)) >= cost
	var headline: Dictionary = _headline_figure(upgrade)
	var meta: String = "buy:%s" % upgrade.id
	return {
		"meta": meta,
		"name": _row_title(upgrade, level),
		"figure": str(headline.get("figure", "")),
		"unit": str(headline.get("unit", "")),
		"spec": _spec_line(upgrade),
		"price": NumberFormat.format_cash(cost),
		"price_color": ConsoleStyle.PHOSPHOR if affordable else ConsoleStyle.DANGER,
		"status": "OPEN" if can_buy else _blocked_status(upgrade, affordable),
		"status_color": ConsoleStyle.PHOSPHOR if can_buy else ConsoleStyle.PHOSPHOR_DIM,
		"icon": AssetCatalog.category_icon(upgrade.category),
		"tooltip": upgrade.description,
		"action_text": "BUY",
		"action_enabled": can_buy,
		"action_tooltip": _buy_action_tooltip(upgrade, cost, can_buy),
	}


func _installed_entries() -> Array:
	var entries: Array = []
	for row in UpgradePresentation.installed_inventory():
		var key: String = str(row.get("key", ""))
		var meta: String = "sell:%s" % key
		var can_sell: bool = Simulation.can_sell_hardware(key)
		var rate: float = float(row.get("token_rate", 0.0))
		entries.append({
			"meta": meta,
			"name": "%s ×%d" % [str(row.get("name", key)), int(row.get("count", 1))],
			"figure": NumberFormat.format_token_rate(rate) if rate > 0.0 else "",
			"unit": "TOKENS / PROMPT" if rate > 0.0 else "",
			"spec": _installed_spec(row),
			"price": NumberFormat.format_cash(float(row.get("refund", 0.0))),
			"price_color": ConsoleStyle.PHOSPHOR if can_sell else ConsoleStyle.PHOSPHOR_DIM,
			"status": "SELLS FOR" if can_sell else "KEEPING IT",
			"status_color": ConsoleStyle.PHOSPHOR_DIM,
			"icon": AssetCatalog.category_icon(
				"component" if bool(row.get("component", false)) else "hardware"
			),
			"action_text": "SELL",
			"action_enabled": can_sell,
			"action_warning": true,
			"action_tooltip": "" if can_sell else Simulation.hardware_sale_reason(key),
		})
	return entries


## The one number a purchase turns on. Machines are bought for their rate, so
## that is what the tile sets large; everything else leads with whatever it
## actually changes, because "£15,000" on its own is not a reason.
func _headline_figure(upgrade: UpgradeDefinition) -> Dictionary:
	var hardware: Dictionary = UpgradePresentation.curve(upgrade)
	var rate: float = float(hardware.get("token_rate", 0.0))
	if rate > 0.0:
		return {"figure": NumberFormat.format_token_rate(rate), "unit": "tokens / prompt"}
	for effect in upgrade.effects:
		var amount: float = 0.0
		if effect.value is float or effect.value is int:
			amount = float(effect.value)
		match effect.target:
			"compute.cooling":
				return {"figure": "+%d" % int(amount), "unit": "cooling"}
			"build.board.slot_count":
				return {"figure": "+%d" % int(amount), "unit": "pipeline slots"}
	return {"figure": "", "unit": ""}


## What it costs to run, as opposed to what it costs to buy: the two numbers a
## market screen has to keep apart, because the second one is the one that
## bankrupts a player who only read the first.
func _spec_line(upgrade: UpgradeDefinition) -> String:
	var parts: PackedStringArray = []
	var hardware: Dictionary = UpgradePresentation.curve(upgrade)
	var watts: float = float(hardware.get("power_draw", 0.0))
	if watts > 0.0:
		parts.append("%dW" % int(watts))
	if upgrade.category == "component" and upgrade.requires_hardware != "":
		var fitted: int = UpgradeSystem.installed_count(
			Simulation.run_state, upgrade.component_key
		)
		var hosts: int = UpgradeSystem.installed_count(
			Simulation.run_state, upgrade.requires_hardware
		)
		parts.append("%d of %d fitted" % [fitted, hosts])
	elif UpgradePresentation.occupies_floor(upgrade):
		parts.append("1 slot")
	if upgrade.recurring_cost_delta > 0.0:
		parts.append("%s / rnd" % NumberFormat.format_cash(upgrade.recurring_cost_delta))
	if parts.is_empty():
		return upgrade.description
	return " · ".join(parts)


func _installed_spec(row: Dictionary) -> String:
	var parts: PackedStringArray = []
	if float(row.get("power_draw", 0.0)) > 0.0:
		parts.append("%dW" % int(row["power_draw"]))
	if bool(row.get("component", false)):
		parts.append("fitted inside")
	else:
		var count: int = int(row.get("count", 1))
		parts.append("1 slot" if count == 1 else "%d slots" % count)
	return " · ".join(parts)


## Machines are counted rather than levelled: a second desktop is another box on
## the floor, not the same box upgraded.
func _row_title(upgrade: UpgradeDefinition, level: int) -> String:
	if level <= 0:
		return upgrade.name
	if upgrade.category == "hardware" or upgrade.category == "component":
		return "%s ×%d" % [upgrade.name, level]
	return "%s Lv%d" % [upgrade.name, level]


## Which wall the player hit, said on the tile so a locked line explains itself
## without being opened.
func _blocked_status(upgrade: UpgradeDefinition, affordable: bool) -> String:
	if UpgradeSystem.is_maxed(Simulation.run_state, upgrade):
		return "MAX %d/%d" % [
			UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id), upgrade.max_level,
		]
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
	return "BLOCKED"


## Stock the run could still be shown. Items whose unlock has not happened yet
## are absent rather than greyed. Premises are absent entirely — where the run
## happens was settled before it started and no amount of cash moves it.
func _shelves() -> Dictionary:
	var shelves: Dictionary = {}
	for upgrade in ContentDatabase.upgrades:
		if upgrade.category == "dwelling":
			continue
		if not upgrade.repeatable:
			if upgrade.id in Simulation.run_state.build["upgrades"]:
				continue
			if upgrade.hardware_key != "" \
					and upgrade.hardware_key in Simulation.run_state.build["hardware"]:
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
	return UpgradeSystem.quoted_cost(
		Simulation.run_state, upgrade, UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id)
	)


## Card actions replace the old detail sign, so a disabled BUY still explains
## the exact gate without asking the player to open another surface.
func _buy_action_tooltip(
	upgrade: UpgradeDefinition, cost: float, can_buy: bool
) -> String:
	if can_buy:
		var outlook: Dictionary = Simulation.bills_outlook()
		var left: float = float(outlook.get("cash", 0.0)) - cost
		var rent_shortfall: float = maxf(0.0, float(outlook.get("due", 0.0)) - left)
		if rent_shortfall > 0.0:
			return "%s short of rent after this purchase." % NumberFormat.format_cash(
				rent_shortfall
			)
		return "Buy for %s" % NumberFormat.format_cash(cost)
	if not MarketService.market_open(Simulation):
		return "The Market is closed once a round is under way. Shop between rounds."
	if UpgradeSystem.is_maxed(Simulation.run_state, upgrade):
		return "Maximum level reached."
	var prerequisite: String = UpgradePresentation.prerequisite_text(upgrade)
	if prerequisite != "":
		return prerequisite
	if UpgradePresentation.hardware_space_full(upgrade):
		return "No floor space. Sell hardware first."
	if UpgradePresentation.component_capacity_reached(upgrade):
		return "No compatible machine has a free component slot."
	var cooling: Dictionary = UpgradePresentation.cooling_shortfall(upgrade)
	if not cooling.is_empty():
		return "Needs %d cooling; only %d available." % [
			int(cooling.get("need", 0)), int(cooling.get("have", 0)),
		]
	var shortfall: float = cost - float(Simulation.run_state.economy.get("cash", 0.0))
	if shortfall > 0.0:
		return "Need %s more." % NumberFormat.format_cash(shortfall)
	return "Unavailable"


# --- Actions -----------------------------------------------------------------

func _on_market_action(meta: Variant) -> void:
	var action: String = str(meta)
	if action.begins_with("buy:"):
		_buy_upgrade(action.trim_prefix("buy:"))
	elif action.begins_with("sell:"):
		_sell_hardware(action.trim_prefix("sell:"))


func _buy_upgrade(upgrade_id: String) -> void:
	UiSound.play("buy")
	if Simulation.buy_upgrade(upgrade_id):
		_board.clear_selection()
		refresh()
		get_tree().call_group("ui_refresh", "refresh")


func _sell_hardware(hardware_key: String) -> void:
	UiSound.play("buy")
	if Simulation.sell_hardware(hardware_key):
		_board.clear_selection()
		refresh()
		get_tree().call_group("ui_refresh", "refresh")


# --- Layout ------------------------------------------------------------------

func _on_venue_layout() -> void:
	var scale: float = console_scale()
	if _board != null:
		_board.set_console(console_mode())
		_board.set_metrics(scale, content_width("board"))
	if _kicker != null:
		_kicker.add_theme_font_size_override("font_size", ConsoleMetrics.font_tiny(scale))
	_layout_counter_rows()
	var font_tiny: int = ConsoleMetrics.font_tiny(scale)
	if _notice != null:
		_notice.add_theme_font_size_override("font_size", font_tiny)
	for line in _index_lines.get_children():
		_apply_line_font(line, ConsoleMetrics.font_small(scale))


func _apply_line_font(line: Node, font_size: int) -> void:
	if line is Label:
		line.add_theme_font_size_override("font_size", font_size)
		return
	for child in line.get_children():
		_apply_line_font(child, font_size)


func _layout_counter_rows() -> void:
	var scale: float = console_scale()
	var font: int = ConsoleMetrics.font_small(scale)
	var height: int = ConsoleMetrics.row_height(scale)
	var pad: int = ConsoleMetrics.pad_h(scale)
	for key in _counter_rows:
		(_counter_rows[key] as ConsoleMenuRow).set_metrics(font, height, pad)
