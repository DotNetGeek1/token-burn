extends Control

## The meta hub: what the game remembers about the player across every run.
## Read-only — unlocks are spent on the run-end debrief, not here — but this
## is the one place that shows the whole arc at once: age reached, best
## scores, contracts conquered, and the full unlock gallery.

@onready var age_label: Label = $Panel/Margin/VBox/AgeLabel
@onready var age_flavour_label: Label = $Panel/Margin/VBox/AgeFlavourLabel
@onready var stats_list: VBoxContainer = $Panel/Margin/VBox/StatsList
@onready var contracts_label: Label = $Panel/Margin/VBox/Scroll/Content/ContractsLabel
@onready var contracts_list: VBoxContainer = $Panel/Margin/VBox/Scroll/Content/ContractsList
@onready var unlocks_label: Label = $Panel/Margin/VBox/Scroll/Content/UnlocksLabel
@onready var unlocks_list: VBoxContainer = $Panel/Margin/VBox/Scroll/Content/UnlocksList
@onready var close_button: GameButton = $Panel/Margin/VBox/CloseButton


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("flow_overlay")
	close_button.pressed.connect(hide_overlay)


func open() -> void:
	_refresh()
	UiTransition.enter(self)
	UiTransition.stagger(stats_list)
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().call_group("main_ui", "sync_overlay_input")


func hide_overlay() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().call_group("main_ui", "sync_overlay_input")


func _refresh() -> void:
	_refresh_age()
	_refresh_stats()
	_refresh_contracts()
	_refresh_unlocks()


func _refresh_age() -> void:
	var age_data: Dictionary = Ages.get_age(MetaProgress.age())
	age_label.text = "CURRENT AGE · %s" % str(age_data.get("name", "Bedroom Age")).to_upper()
	age_flavour_label.text = str(age_data.get("flavour", ""))


func _refresh_stats() -> void:
	for child in stats_list.get_children():
		child.queue_free()
	var best: Dictionary = MetaProgress.best_scores()
	var rows: Array = [
		{"label": "Best total tokens burned", "value": NumberFormat.format_tokens(float(best.get("total_tokens_burned", 0.0)))},
		{"label": "Best peak prompt burn", "value": NumberFormat.format_tokens(float(best.get("peak_prompt_tokens", 0.0)))},
		{"label": "Best sustained throughput", "value": NumberFormat.format_token_rate(float(best.get("peak_token_rate", 0.0)))},
		{"label": "Ascensions completed", "value": str(_total_ascensions())},
		{"label": "Pending picks", "value": str(MetaProgress.pending_picks())},
	]
	# Retirement was the old calendar ending. Nothing earns it any more, so the
	# row only appears for profiles that still carry some.
	if MetaProgress.retirements() > 0:
		rows.insert(4, {"label": "Runs retired (legacy)", "value": str(MetaProgress.retirements())})
	for row in rows:
		stats_list.add_child(_stat_row(str(row["label"]), str(row["value"])))


func _total_ascensions() -> int:
	var total: int = 0
	for contract in ContentDatabase.ascension_contracts:
		total += MetaProgress.ascension_completions(str(contract.get("id", "")))
	return total


func _stat_row(label_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiThemeBuilder.SPACE_MD)
	var name_label := Label.new()
	name_label.text = label_text.to_upper()
	name_label.theme_type_variation = &"SectionLabel"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value_label := Label.new()
	value_label.text = value_text
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return row


func _refresh_contracts() -> void:
	for child in contracts_list.get_children():
		child.queue_free()
	var contracts: Array = ContentDatabase.ascension_contracts
	contracts_label.visible = not contracts.is_empty()
	for contract in contracts:
		var contract_id: String = str(contract.get("id", ""))
		var completions: int = MetaProgress.ascension_completions(contract_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiThemeBuilder.SPACE_MD)
		var name_label := Label.new()
		name_label.text = str(contract.get("name", contract_id))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if completions <= 0:
			name_label.add_theme_color_override("font_color", UiThemeBuilder.color("grey"))
		row.add_child(name_label)
		var status_label := Label.new()
		status_label.text = "Completed ×%d" % completions if completions > 0 else "Not yet conquered"
		status_label.add_theme_color_override(
			"font_color", UiThemeBuilder.semantic("success" if completions > 0 else "neutral")
		)
		row.add_child(status_label)
		contracts_list.add_child(row)


func _refresh_unlocks() -> void:
	for child in unlocks_list.get_children():
		child.queue_free()
	var catalog: Array = MetaProgress.catalog()
	unlocks_label.visible = not catalog.is_empty()
	for unlock in catalog:
		var unlock_id: String = str(unlock.get("id", ""))
		var owned: int = MetaProgress.unlock_count(unlock_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiThemeBuilder.SPACE_MD)
		var icon_rect := TextureRect.new()
		icon_rect.texture = AssetCatalog.unlock_icon(str(unlock.get("kind", "")))
		icon_rect.custom_minimum_size = Vector2(40, 40)
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.modulate = Color.WHITE if owned > 0 else Color(0.5, 0.5, 0.55)
		row.add_child(icon_rect)
		var name_label := Label.new()
		name_label.text = str(unlock.get("name", unlock_id))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if owned <= 0:
			name_label.add_theme_color_override("font_color", UiThemeBuilder.color("grey"))
		row.add_child(name_label)
		var owned_label := Label.new()
		owned_label.text = "×%d" % owned if owned > 0 else "Locked"
		owned_label.add_theme_color_override(
			"font_color", UiThemeBuilder.semantic("perk" if owned > 0 else "neutral")
		)
		row.add_child(owned_label)
		unlocks_list.add_child(row)
