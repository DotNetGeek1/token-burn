extends Control

const CARD_SCENE := preload("res://ui/common/card.tscn")
const DETAIL_SHEET := preload("res://ui/common/detail_sheet.tscn")

@onready var header: ScreenHeader = $Margin/VBox/Header
@onready var tab_row: HBoxContainer = $Margin/VBox/TabRow
@onready var empty_label: Label = $Margin/VBox/EmptyLabel
@onready var upgrades_list: VBoxContainer = $Margin/VBox/Scroll/UpgradesList

var _detail_sheet: DetailSheet = null
var _active_tab: String = "property"
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	add_to_group("ui_refresh")
	header.setup("Market")
	_detail_sheet = DETAIL_SHEET.instantiate()
	add_child(_detail_sheet)
	_build_tabs()
	EventBus.upgrade_purchased.connect(func(_id): refresh())
	EventBus.run_started.connect(refresh)
	refresh()


func _build_tabs() -> void:
	for tab in UpgradePresentation.TABS:
		var key: String = str(tab["key"])
		var button := GameButton.new()
		button.compact = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_tab_pressed.bind(key))
		tab_row.add_child(button)
		button.set_lines(str(tab["label"]))
		_tab_buttons[key] = button


func _on_tab_pressed(key: String) -> void:
	if _active_tab == key:
		return
	_active_tab = key
	refresh()


func refresh() -> void:
	var cash: float = float(Simulation.run_state.economy.get("cash", 0.0))
	header.set_context(NumberFormat.format_cash(cash), "money" if cash >= 0.0 else "danger")
	_refresh_bills_line()
	for child in upgrades_list.get_children():
		child.queue_free()
	var shelves: Dictionary = _shelves()
	_refresh_tabs(shelves)
	var shown: int = 0
	if _active_tab == "hardware":
		_build_owned_section()
	for key in UpgradePresentation.GROUP_ORDER:
		if UpgradePresentation.tab_for_group(key) != _active_tab:
			continue
		if not shelves.has(key) or shelves[key].is_empty():
			continue
		upgrades_list.add_child(_section_label(key))
		for upgrade in shelves[key]:
			upgrades_list.add_child(_build_upgrade_card(upgrade, key))
		shown += shelves[key].size()
	empty_label.visible = shown == 0
	UiTransition.stagger(upgrades_list)


## The counter the player is standing at is the loud one; the others carry their
## remaining stock so an empty shelf does not need visiting to find that out.
func _refresh_tabs(shelves: Dictionary) -> void:
	for tab in UpgradePresentation.TABS:
		var key: String = str(tab["key"])
		var button: GameButton = _tab_buttons.get(key, null)
		if button == null:
			continue
		var count: int = 0
		for group_key in Array(tab["groups"]):
			count += Array(shelves.get(group_key, [])).size()
		var active: bool = key == _active_tab
		button.theme_type_variation = &"PrimaryButton" if active else &"SecondaryButton"
		button.accent_key = "action" if active else "neutral"
		button.set_lines(str(tab["label"]), "%d" % count)


## Stock the run could still be shown. Items whose unlock has not happened yet
## are absent rather than greyed: the cloud shelf is a rumour until the account
## exists. Property further up the ladder stays visible, because seeing the next
## rung is the point of a ladder.
func _shelves() -> Dictionary:
	var shelves: Dictionary = {}
	for upgrade in ContentDatabase.upgrades:
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
	# Cheapest first, which for property is also the order the ladder is climbed.
	for key in shelves:
		shelves[key].sort_custom(func(a: UpgradeDefinition, b: UpgradeDefinition) -> bool:
			return _card_cost(a) < _card_cost(b)
		)
	return shelves


## What is already installed, above the stock, because floor space is the binding
## constraint on the Hardware counter and the way past it is often to sell
## something rather than to move somewhere bigger.
func _build_owned_section() -> void:
	var inventory: Array = UpgradePresentation.installed_inventory()
	if inventory.is_empty():
		return
	upgrades_list.add_child(_section_label_text("INSTALLED", "hardware"))
	for row in inventory:
		upgrades_list.add_child(_build_owned_card(row))


func _build_owned_card(row: Dictionary) -> GameCard:
	var card: GameCard = CARD_SCENE.instantiate()
	var key: String = str(row.get("key", ""))
	var count: int = int(row.get("count", 1))
	var refund: float = float(row.get("refund", 0.0))
	var can_sell: bool = Simulation.can_sell_hardware(key)
	var parts: PackedStringArray = []
	var token_line: String = UpgradePresentation.token_rate_text(float(row.get("token_rate", 0.0)))
	if token_line != "":
		parts.append(token_line)
	if float(row.get("power_draw", 0.0)) > 0.0:
		parts.append("%dW draw" % int(row["power_draw"]))
	var is_component: bool = bool(row.get("component", false))
	if is_component:
		parts.append("fitted inside, no floor space")
	else:
		parts.append("1 floor slot" if count == 1 else "%d floor slots" % count)
	var title: String = str(row.get("name", key))
	if count > 1:
		title = "%s ×%d" % [title, count]
	var action: String = "KEEPING IT"
	if can_sell:
		action = "SELL %s" % NumberFormat.format_cash(refund)
	card.setup(title, " · ".join(parts), "", action, AssetCatalog.category_icon("hardware"))
	card.set_accent(UpgradePresentation.group_color("component" if is_component else "hardware"))
	card.set_kicker("Installed", UiThemeBuilder.semantic("success"))
	card.set_disabled(not can_sell)
	var reason: String = Simulation.hardware_sale_reason(key)
	if not can_sell and reason != "":
		# Neutral rather than a warning: nothing is wrong, this unit simply is
		# not going anywhere.
		card.set_warnings([{"text": reason, "role": "neutral"}])
	if can_sell:
		card.set_action_style("cash", "money", "MoneyButton")
		card.pressed.connect(_sell_hardware.bind(key, card))
	else:
		card.set_action_style("warning", "neutral", "SecondaryButton")
	return card


func _sell_hardware(hardware_key: String, card: GameCard) -> void:
	UiSound.play("buy")
	if card != null:
		card.play_press_feedback()
		await get_tree().create_timer(0.1).timeout
	if Simulation.sell_hardware(hardware_key):
		refresh()
		get_tree().call_group("ui_refresh", "refresh")


func _card_cost(upgrade: UpgradeDefinition) -> float:
	return UpgradeSystem.purchase_cost(
		upgrade, UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id)
	)


func _section_label(group_key: String) -> Label:
	return _section_label_text(UpgradePresentation.group_label(group_key).to_upper(), group_key)


func _section_label_text(text: String, group_key: String) -> Label:
	var section := Label.new()
	section.text = text
	section.theme_type_variation = &"SectionLabel"
	section.add_theme_color_override("font_color", UpgradePresentation.group_color(group_key))
	section.add_theme_constant_override("outline_size", 8)
	section.add_theme_color_override("font_outline_color", UiThemeBuilder.color("bg"))
	return section


## Compact upgrade card: name, price, one line of consequence, and — when it is
## out of reach — why. The full description lives in the detail sheet.
func _build_upgrade_card(upgrade: UpgradeDefinition, group_key: String) -> GameCard:
	var card: GameCard = CARD_SCENE.instantiate()
	var level: int = UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id)
	var cost: float = UpgradeSystem.purchase_cost(upgrade, level)
	var can_buy: bool = Simulation.can_buy_upgrade(upgrade.id)
	var affordable: bool = float(Simulation.run_state.economy.get("cash", 0.0)) >= cost
	var blockers: Array = UpgradePresentation.blockers(upgrade, affordable)
	var action_text: String = "BUY" if can_buy else _blocked_action_text(upgrade, affordable)
	var title: String = _card_title(upgrade, level)
	card.setup(
		title,
		UpgradePresentation.effect_line(upgrade),
		"",
		action_text,
		AssetCatalog.category_icon(upgrade.category)
	)
	card.set_accent(UpgradePresentation.group_color(group_key))
	card.set_headline(NumberFormat.format_cash(cost), "money" if affordable else "danger")
	card.set_warnings(blockers + _bill_warnings(upgrade, can_buy))
	card.set_disabled(not can_buy)
	card.body_pressed.connect(_show_upgrade_detail.bind(upgrade, group_key, can_buy))
	if can_buy:
		card.pressed.connect(_buy_upgrade.bind(upgrade.id, card))
	# Spending money is a money action, so this button stays green while the
	# neutral "tap to compare" interactions elsewhere are cyan.
	if can_buy:
		card.set_action_style("cash", "money", "MoneyButton")
	else:
		card.set_action_style("warning", "neutral", "SecondaryButton")
	return card


## Machines are counted rather than levelled: a second desktop is another box on
## the floor, not the same box upgraded. Everything else still reads as a level.
func _card_title(upgrade: UpgradeDefinition, level: int) -> String:
	if level <= 0:
		return upgrade.name
	if upgrade.category == "hardware" or upgrade.category == "component":
		return "%s · owned ×%d" % [upgrade.name, level]
	return "%s · Lv %d" % [upgrade.name, level]


## The button says which wall the player hit, so a locked card does not need
## the chips underneath it to explain why it will not press.
func _blocked_action_text(upgrade: UpgradeDefinition, affordable: bool) -> String:
	if UpgradePresentation.prerequisite_text(upgrade) != "":
		return "LOCKED"
	if UpgradePresentation.hardware_space_full(upgrade):
		return "NO SPACE"
	if UpgradePresentation.component_capacity_reached(upgrade):
		return "ALL FITTED"
	if not affordable:
		return "CAN'T AFFORD"
	return "NOT NOW"


func _bill_warnings(upgrade: UpgradeDefinition, can_buy: bool) -> Array:
	# Only worth saying on something the player could actually click.
	if not can_buy:
		return []
	var cost: float = UpgradeSystem.purchase_cost(
		upgrade,
		UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id)
	)
	var outlook: Dictionary = Simulation.bills_outlook()
	var left: float = float(outlook.get("cash", 0.0)) - cost
	var due: float = float(outlook.get("due", 0.0))
	if left >= due:
		return []
	return [{
		"text": "%s short of rent" % NumberFormat.format_cash(due - left),
		"role": "danger",
	}]


func _show_upgrade_detail(upgrade: UpgradeDefinition, group_key: String, can_buy: bool) -> void:
	var level: int = UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id)
	var cost: float = UpgradeSystem.purchase_cost(upgrade, level)
	var rows: Array = [
		{"stat": "Cost", "value": NumberFormat.format_cash(cost), "role": "money"},
	]
	if level > 0:
		var counted: bool = upgrade.category == "hardware" or upgrade.category == "component"
		rows.insert(0, {"stat": "Owned" if counted else "Level", "value": str(level)})
	if upgrade.recurring_cost_delta > 0.0:
		rows.append({
			"stat": "Adds to bills",
			"value": "%s / round" % NumberFormat.format_cash(upgrade.recurring_cost_delta),
			"role": "warning",
		})
	rows.append({"text": upgrade.description})
	rows.append({"stat": "Effect", "value": ""})
	rows.append({"text": UpgradePresentation.effect_line(upgrade)})
	var cooling: Dictionary = UpgradePresentation.cooling_shortfall(upgrade)
	if not cooling.is_empty():
		rows.append({
			"rule": "Cooling %d / %d" % [int(cooling["have"]), int(cooling["need"])],
			"text": "Running this adds %.0f heat per prompt. Buy cooling or a bigger space first, or the run overheats." % float(cooling["heat_per_prompt"]),
			"role": "heat",
		})
	var prerequisite: String = UpgradePresentation.prerequisite_text(upgrade)
	if prerequisite != "":
		rows.append({
			"rule": prerequisite,
			"text": "This is further up the ladder than you are. Take the step before it first.",
			"role": "warning",
		})
	if UpgradePresentation.hardware_space_full(upgrade):
		var space: Dictionary = UpgradePresentation.hardware_space()
		rows.append({
			"rule": "No hardware space",
			"text": "The %s holds %d machines and all %d are running. Move somewhere bigger before buying another." % [
				space.get("dwelling", ""),
				int(space.get("total", 0)),
				int(space.get("used", 0)),
			],
			"role": "danger",
		})
	if UpgradePresentation.component_capacity_reached(upgrade):
		rows.append({
			"rule": "Every machine already has one",
			"text": "One fits per %s you own. Buy another machine and there will be somewhere to put this." % UpgradePresentation.hardware_name(upgrade.requires_hardware),
			"role": "warning",
		})
	if upgrade.repeatable and level > 0:
		rows.append({
			"text": "Each one after the first costs %d%% more than the last." % int(round((upgrade.cost_growth - 1.0) * 100.0)),
		})
	if not can_buy:
		var shortfall: float = cost - float(Simulation.run_state.economy.get("cash", 0.0))
		if shortfall > 0.0:
			rows.append({
				"rule": "Need %s more" % NumberFormat.format_cash(shortfall),
				"text": "Finish a contract or take a better paying one.",
				"role": "danger",
			})
	_detail_sheet.show_detail(
		upgrade.name,
		UpgradePresentation.group_label(group_key),
		rows,
		[],
		"BUY" if can_buy else "",
		UpgradePresentation.group_color(group_key)
	)
	for connection in _detail_sheet.action_confirmed.get_connections():
		_detail_sheet.action_confirmed.disconnect(connection["callable"])
	if can_buy:
		_detail_sheet.action_confirmed.connect(_buy_upgrade.bind(upgrade.id, null))


## The shop is the easiest place to spend rent money by accident, so what is
## owed and when it lands sits directly under the title.
func _refresh_bills_line() -> void:
	var outlook: Dictionary = Simulation.bills_outlook()
	var due: float = float(outlook.get("due", 0.0))
	var line: String = "%s bills due at the end of this round · safe to spend %s" % [
		NumberFormat.format_cash(due),
		NumberFormat.format_cash(float(outlook.get("spendable", 0.0))),
	]
	# Machines are bought against floor space as much as against cash, so the
	# Hardware counter says how much room is left before anything is priced.
	if _active_tab == "hardware":
		var space: Dictionary = UpgradePresentation.hardware_space()
		line += "\n%s: %d of %d hardware slots used" % [
			space.get("dwelling", ""),
			int(space.get("used", 0)),
			int(space.get("total", 0)),
		]
	header.set_sub_line(line)


func _buy_upgrade(upgrade_id: String, card: GameCard) -> void:
	UiSound.play("buy")
	if card != null:
		card.play_press_feedback()
		await get_tree().create_timer(0.1).timeout
	if Simulation.buy_upgrade(upgrade_id):
		refresh()
		get_tree().call_group("ui_refresh", "refresh")
