extends Control

const CARD_SCENE := preload("res://ui/common/card.tscn")
const BOTTOM_SHEET := preload("res://ui/common/bottom_sheet.tscn")
const PERK_SLOT_LIMIT := 5

@onready var header: ScreenHeader = $Margin/VBox/Header
@onready var empty_label: Label = $Margin/VBox/EmptyLabel
@onready var synergies_list: VBoxContainer = $Margin/VBox/SynergiesPanel/SynergiesList
@onready var perks_list: GridContainer = $Margin/VBox/Scroll/PerksGrid
@onready var token_rate_row: StatRow = $Margin/VBox/Footer/TokenRateRow
@onready var cloud_row: StatRow = $Margin/VBox/Footer/CloudRow

var _sheet: BottomSheet = null


func _ready() -> void:
	add_to_group("ui_refresh")
	header.setup("Your Build")
	_setup_bottom_sheet()
	EventBus.perk_acquired.connect(func(_id): refresh())
	EventBus.run_started.connect(refresh)
	refresh()


func refresh() -> void:
	var perks: Array = Simulation.run_state.build.get("perks", [])
	header.set_context("%d / %d" % [perks.size(), PERK_SLOT_LIMIT])
	empty_label.visible = perks.is_empty()
	_refresh_perk_grid(perks)
	_refresh_synergies()
	_refresh_stats()


func _refresh_perk_grid(perks: Array) -> void:
	for child in perks_list.get_children():
		child.queue_free()
	for perk_id in perks:
		var perk: PerkDefinition = ContentDatabase.get_perk(str(perk_id))
		if perk == null:
			continue
		var desc: String = Simulation.get_perk_description(str(perk_id))
		var card: GameCard = CARD_SCENE.instantiate()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 132)
		card.setup(
			perk.name,
			_short_perk_text(desc),
			"",
			"",
			AssetCatalog.perk_icon(str(perk_id)),
			perk.rarity
		)
		card.set_chips([{
			"text": perk.rarity,
			"accent": AssetCatalog.rarity_color(perk.rarity),
			"filled": true,
		}])
		card.pressed.connect(_show_perk.bind(perk, desc))
		perks_list.add_child(card)
	UiTransition.stagger(perks_list)


func _refresh_synergies() -> void:
	for child in synergies_list.get_children():
		child.queue_free()
	var entries: Array[Dictionary] = _active_synergy_entries()
	if entries.is_empty():
		var none_label := Label.new()
		none_label.text = "None recognised yet"
		none_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none_label.theme_type_variation = &"MutedLabel"
		synergies_list.add_child(none_label)
		return
	for entry in entries:
		var name_label := Label.new()
		name_label.text = "⚡ %s" % str(entry.get("name", "Synergy"))
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_color_override("font_color", UiThemeBuilder.semantic("energy"))
		synergies_list.add_child(name_label)
		var combo_label := Label.new()
		combo_label.text = str(entry.get("perks", ""))
		combo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		combo_label.theme_type_variation = &"MutedLabel"
		synergies_list.add_child(combo_label)


func _refresh_stats() -> void:
	var multiplier: float = _token_rate_multiplier()
	token_rate_row.setup("Token rate", "×%.1f" % multiplier, "tokens")
	cloud_row.setup(
		"Cloud liability",
		NumberFormat.format_cash(float(Simulation.run_state.economy.get("cloud_liability", 0.0))),
		"cloud"
	)


func _show_perk(perk: PerkDefinition, desc: String) -> void:
	var body_parts: PackedStringArray = []
	body_parts.append(desc)
	body_parts.append("")
	body_parts.append("Rarity: %s" % perk.rarity.capitalize())
	if perk.tags.size() > 0:
		body_parts.append("Tags: %s" % ", ".join(perk.tags))
	if not perk.parameters.is_empty():
		body_parts.append("")
		body_parts.append("Parameters:")
		for key in perk.parameters.keys():
			body_parts.append("  • %s: %s" % [key, str(perk.parameters[key])])
	_sheet.show_content(perk.name, "\n".join(body_parts))


func _setup_bottom_sheet() -> void:
	_sheet = BOTTOM_SHEET.instantiate()
	add_child(_sheet)


func _active_synergy_entries() -> Array[Dictionary]:
	var owned: Array = Simulation.run_state.build.get("perks", [])
	var entries: Array[Dictionary] = []
	for synergy in ContentDatabase.synergies:
		if not synergy is Dictionary:
			continue
		var required: Array = synergy.get("perks", [])
		var has_all := true
		for req in required:
			if str(req) not in owned:
				has_all = false
				break
		if not has_all:
			continue
		var perk_names: PackedStringArray = []
		for req in required:
			var req_perk: PerkDefinition = ContentDatabase.get_perk(str(req))
			if req_perk != null:
				perk_names.append(req_perk.name)
		entries.append({
			"name": str(synergy.get("name", "Synergy")),
			"perks": " + ".join(perk_names),
		})
	return entries


func _token_rate_multiplier() -> float:
	var compute: Dictionary = Simulation.run_state.compute
	var base_rate: float = (_hardware_token_rate() + float(compute.get("cloud_capacity", 0.0))) * float(
		compute.get("efficiency", 1.0)
	)
	if base_rate <= 0.0:
		return 1.0
	return float(compute.get("token_rate", 0.0)) / base_rate


func _hardware_token_rate() -> float:
	var total: float = 0.0
	var curves: Dictionary = ContentDatabase.balance.get("hardware_curves", {})
	for hardware_id in Simulation.run_state.build.get("hardware", []):
		var hw: Dictionary = curves.get(str(hardware_id), {})
		total += float(hw.get("token_rate", 0.0))
	return total


func _short_perk_text(desc: String) -> String:
	if desc.length() <= 72:
		return desc
	return desc.substr(0, 69) + "..."
