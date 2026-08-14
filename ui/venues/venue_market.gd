extends VenueScene

## The market: a back room somewhere with the stock listed on a board.
##
## This is the same shop it has always been — the same shelves, the same
## blockers, the same purchase and sale calls — laid out as a place rather than
## as a price list in a 442-pixel column. The counters go down the left where the
## shop writes them up, the shelf itself is the big board on the wall, and what
## is wrong with the thing you just pointed at is printed on the sign beside it.
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
var _signage_panel: VenuePanel = null
var _sign: VBoxContainer = null
var _detail: ConsoleDetail = null
var _notice: Label = null
var _counter_rows: Dictionary = {}
var _active: String = "hardware"
var _selected: String = ""
var _rows: Dictionary = {}


func venue_key() -> String:
	return "market"


func _hint_entries() -> Array:
	return [{"index": "ENTER", "headline": "VIEW"}]


func _build_venue() -> void:
	_build_index()
	_build_board()
	_build_signage()
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
	_board.tile_selected.connect(_on_tile_selected)
	_board_panel.content().add_child(_board)


## The right-hand sign. It is the shop's own notice until the player points at
## something, and then it is what that thing is and what is stopping them having
## it — which is where a buyer would look anyway.
func _build_signage() -> void:
	# No floor height in the column: the sign is two lines of flavour until
	# something is selected, and reserving a screen inch for it on a handset is
	# reserving it against the shelf the player came to read.
	_signage_panel = add_panel("signage", "", {
		"console_order": 30, "console_min": 0.0,
	})
	var content: VBoxContainer = _signage_panel.content()

	_sign = VBoxContainer.new()
	_sign.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sign.add_theme_constant_override("separation", 8)
	content.add_child(_sign)
	for line in ["NO REFUNDS", "ONLY UPGRADES"]:
		var label: Label = ConsoleStyle.label(
			line, ConsoleStyle.FONT_BODY, ConsoleStyle.PHOSPHOR_DIM
		)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_sign.add_child(label)

	_detail = ConsoleDetail.new()
	_detail.visible = false
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.action_pressed.connect(_on_detail_action)
	_detail.closed.connect(_on_detail_closed)
	content.add_child(_detail)


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
	_refresh_detail()


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
## An empty shelf is absent rather than greyed: the cloud is a rumour until the
## account exists, and a counter with nothing behind it is not a place to stand.
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
	_selected = ""
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
	if _selected != "":
		_board.select(_selected)


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
	var cost: float = UpgradeSystem.purchase_cost(upgrade, level)
	var can_buy: bool = Simulation.can_buy_upgrade(upgrade.id)
	var affordable: bool = float(Simulation.run_state.economy.get("cash", 0.0)) >= cost
	var headline: Dictionary = _headline_figure(upgrade)
	var meta: String = "buy:%s" % upgrade.id
	_rows[meta] = upgrade
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
	}


func _installed_entries() -> Array:
	var entries: Array = []
	for row in UpgradePresentation.installed_inventory():
		var key: String = str(row.get("key", ""))
		var meta: String = "sell:%s" % key
		_rows[meta] = row
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
			"compute.cloud_capacity":
				return {"figure": NumberFormat.format(amount), "unit": "cloud tokens"}
			"build.board.slot_count":
				return {"figure": "+%d" % int(amount), "unit": "pipeline slots"}
			"business.advertising":
				return {
					"figure": NumberFormat.format_cash(amount), "unit": "/ day demand",
				}
	if upgrade.id == Simulation.CLOUD_BURST_UPGRADE:
		var level: int = UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id)
		var multiplier: float = (
			Simulation.CLOUD_BURST_BASE_MULTIPLIER
			+ float(level) * Simulation.CLOUD_BURST_PER_LEVEL
		)
		return {"figure": "×%.1f" % multiplier, "unit": "burst"}
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
		if UpgradeSystem.is_maxed(Simulation.run_state, upgrade):
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
	return UpgradeSystem.purchase_cost(
		upgrade, UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id)
	)


# --- The sign ----------------------------------------------------------------

func _on_tile_selected(meta: Variant) -> void:
	_selected = str(meta) if meta != null else ""
	_refresh_detail()


func _on_detail_closed() -> void:
	_selected = ""
	_board.clear_selection()
	_refresh_detail()


## The sign carries one of two things, never both: what the shop wants you to
## know, or what you just asked about.
func _refresh_detail() -> void:
	var reading: bool = _selected != ""
	_sign.visible = not reading
	_detail.visible = reading
	_signage_panel.set_heading("" if not reading else "Details")
	if not reading:
		return
	if _selected.begins_with("sell:"):
		_show_installed_detail(Dictionary(_rows.get(_selected, {})))
	else:
		_show_upgrade_detail(_rows.get(_selected, null))


func _show_installed_detail(row: Dictionary) -> void:
	if row.is_empty():
		_on_detail_closed()
		return
	var key: String = str(row.get("key", ""))
	var can_sell: bool = Simulation.can_sell_hardware(key)
	var refund: float = float(row.get("refund", 0.0))
	var lines: Array = [
		{"stat": "Owned", "value": "×%d" % int(row.get("count", 1))},
		{"stat": "Sells for", "value": NumberFormat.format_cash(refund)},
		{"text": _installed_spec(row)},
	]
	if not can_sell:
		var reason: String = Simulation.hardware_sale_reason(key)
		if reason != "":
			lines.append({"warn": reason})
	_detail.show_detail(
		str(row.get("name", key)).to_upper(),
		lines,
		"[ ENTER ] SELL FOR %s" % NumberFormat.format_cash(refund)
			if can_sell else "[ -- ] KEEPING IT",
		can_sell
	)


func _show_upgrade_detail(upgrade: UpgradeDefinition) -> void:
	if upgrade == null:
		_on_detail_closed()
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
		"[ ENTER ] BUY FOR %s" % NumberFormat.format_cash(cost)
			if can_buy else "[ -- ] UNAVAILABLE",
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


# --- Actions -----------------------------------------------------------------

func _on_detail_action() -> void:
	if _selected.begins_with("buy:"):
		_buy_upgrade(_selected.trim_prefix("buy:"))
	elif _selected.begins_with("sell:"):
		_sell_hardware(_selected.trim_prefix("sell:"))


func _buy_upgrade(upgrade_id: String) -> void:
	UiSound.play("buy")
	if Simulation.buy_upgrade(upgrade_id):
		# The thing bought is off the shelf now, so nothing is selected: the sign
		# would otherwise be describing stock that is no longer for sale.
		_selected = ""
		_board.clear_selection()
		refresh()
		get_tree().call_group("ui_refresh", "refresh")


func _sell_hardware(hardware_key: String) -> void:
	UiSound.play("buy")
	if Simulation.sell_hardware(hardware_key):
		_selected = ""
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
	if _detail != null:
		_detail.set_metrics(scale)
	_layout_counter_rows()
	var font_body: int = ConsoleMetrics.font_body(scale)
	var font_tiny: int = ConsoleMetrics.font_tiny(scale)
	for label in _sign.get_children():
		if label is Label:
			label.add_theme_font_size_override("font_size", font_body)
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
