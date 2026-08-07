extends Control

## The ladder out of the year, one rung at a time: which Ascension Contract to
## commit to next. Committing switches the run into a Final Burn — there is no
## undo, so this opens as an explicit overlay rather than something that could be
## tapped by accident.
##
## Only the top rung ends the run. The two below it are level-ups that pay their
## picks straight back into the run, which is what the cards have to say plainly:
## a player who reads "Banks 1 pick" as "the game is over now" will never take the
## first one.

const CARD_SCENE := preload("res://ui/common/card.tscn")
const DETAIL_SHEET := preload("res://ui/common/detail_sheet.tscn")

@onready var subtitle_label: Label = $Panel/Margin/VBox/Subtitle
@onready var cards_list: VBoxContainer = $Panel/Margin/VBox/Scroll/CardsList
@onready var empty_label: Label = $Panel/Margin/VBox/EmptyLabel
@onready var close_button: GameButton = $Panel/Margin/VBox/CloseButton

var _detail_sheet: DetailSheet = null


func _ready() -> void:
	close_button.pressed.connect(hide_overlay)
	_detail_sheet = DETAIL_SHEET.instantiate()
	add_child(_detail_sheet)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("flow_overlay")


func open() -> void:
	_refresh()
	UiTransition.enter(self)
	UiTransition.stagger(cards_list)
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().call_group("main_ui", "sync_overlay_input")


func hide_overlay() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().call_group("main_ui", "sync_overlay_input")


func _refresh() -> void:
	for child in cards_list.get_children():
		child.queue_free()
	var contracts: Array = Simulation.ascension_eligible_contracts()
	empty_label.visible = false
	if contracts.is_empty():
		_show_qualification_progress()
	else:
		subtitle_label.text = _rung_subtitle()
		for contract in contracts:
			cards_list.add_child(_build_card(contract))
	_refresh_close_button()


## Says which rung this is and what clearing it does, because the answer changes
## at the top: below it the run continues and gets paid, at it the run is won.
func _rung_subtitle() -> String:
	var ladder: Dictionary = Simulation.ascension_ladder()
	var rung: int = int(ladder.get("rung", 1))
	var total: int = int(ladder.get("total", 3))
	if rung >= total:
		return (
			"Rung %d of %d — the last one. Completing any of these beats the game. There is no undo."
			% [rung, total]
		)
	return (
		"Rung %d of %d. Completing one pays its picks straight back into this run and opens the tier above. There is no undo."
		% [rung, total]
	)


## With nothing in reach, the overlay stops being a dead end and becomes the
## checklist instead: every bar the run has to clear, and where it stands on
## each. The endgame was invisible until it was already available, which is how
## a first run reaches the end of the year without knowing it existed.
func _show_qualification_progress() -> void:
	var q: Dictionary = Simulation.ascension_qualification()
	var ladder: Dictionary = Simulation.ascension_ladder()
	subtitle_label.text = (
		"These are the %d rungs out of the year, climbed one at a time. The run ends by completing the last one, not by the calendar running out. Here is what the build still has to prove for rung %d."
		% [int(ladder.get("total", 3)), int(ladder.get("rung", 1))]
	)
	for row in _requirement_rows(q):
		cards_list.add_child(_requirement_row(
			str(row["label"]), str(row["value"]), bool(row["met"])
		))
	if bool(q.get("qualified", false)):
		cards_list.add_child(_note(
			"The build qualifies, but nothing on rung %d is within reach of its infrastructure tier yet. "
			% int(ladder.get("rung", 1))
			+ "Take the next property or the next machine up."
		))


func _requirement_rows(q: Dictionary) -> Array:
	return [
		{
			"label": "Round",
			"value": "%d of %d needed" % [
				int(Simulation.run_state.calendar.get("round", 1)),
				int(q.get("earliest_round", 1)),
			],
			"met": bool(q.get("round_ok", false)),
		},
		{
			"label": "Peak throughput",
			"value": "%s of %s needed" % [
				NumberFormat.format_token_rate(float(q.get("peak_token_rate", 0.0))),
				NumberFormat.format_token_rate(float(q.get("min_peak_token_rate", 0.0))),
			],
			"met": bool(q.get("peak_ok", false)),
		},
		{
			"label": "Infrastructure tier",
			"value": "%d of %d needed" % [
				int(q.get("infrastructure_tier", 0)),
				int(q.get("min_infrastructure_tier", 0)),
			],
			"met": bool(q.get("infra_ok", false)),
		},
		{
			"label": "Income vs costs",
			"value": "%.2f× of %.2f× needed" % [
				float(q.get("income_ratio", 0.0)),
				float(q.get("min_income_ratio", 1.0)),
			],
			"met": bool(q.get("income_ok", false)),
		},
	]


func _requirement_row(label_text: String, value_text: String, met: bool) -> Control:
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
	value_label.add_theme_color_override(
		"font_color", UiThemeBuilder.semantic("success" if met else "warning")
	)
	row.add_child(value_label)
	return row


func _note(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"MutedLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## Past the twelfth round there is no "not yet" left, so the way out of the
## overlay says what walking away now actually costs.
func _refresh_close_button() -> void:
	if Simulation.in_overtime():
		close_button.set_lines("BACK TO WORK", "Overtime: costs rise every round until a contract is done")
	else:
		close_button.set_lines("NOT YET", "Keep taking ordinary contracts")


func _build_card(contract: Dictionary) -> GameCard:
	var card: GameCard = CARD_SCENE.instantiate()
	card.setup(
		str(contract.get("name", "Contract")),
		str(contract.get("flavour", "")),
		"",
		"COMMIT TO THIS",
		AssetCatalog.unlock_icon("ascension")
	)
	card.set_kicker(_tier_kicker(contract), UiThemeBuilder.color("red"))
	card.set_headline(str(contract.get("burn_label", "")), "compute")
	card.set_chips(_chips(contract))
	card.set_action_style("warning", "danger", "DangerButton")
	card.pressed.connect(_confirm_commit.bind(contract))
	card.body_pressed.connect(_show_detail.bind(contract))
	return card


func _is_final(contract: Dictionary) -> bool:
	return int(contract.get("tier", 1)) >= AscensionSystem.FINAL_TIER


func _tier_kicker(contract: Dictionary) -> String:
	var tier: int = int(contract.get("tier", 1))
	if _is_final(contract):
		return "Tier %d — the finish line" % tier
	return "Tier %d — a level-up, not the end" % tier


func _chips(contract: Dictionary) -> Array:
	var picks: int = int(contract.get("picks", 1))
	return [
		{"text": "%d prompt deadline" % int(contract.get("deadline_prompts", 12)), "role": "warning"},
		{"text": "Quality %d+" % int(contract.get("quality_min", 0)), "role": "energy"},
		{"text": "Max %d violation(s)" % int(contract.get("max_failed_burns", 0)), "role": "danger"},
		{
			"text": "Banks %d pick(s)" % picks if _is_final(contract) else "Pays %d pick(s) into this run" % picks,
			"role": "perk",
			"filled": true,
		},
	]


func _show_detail(contract: Dictionary) -> void:
	var rows: Array = [
		{"text": str(contract.get("flavour", ""))},
		{"stat": "Burn requirement", "value": str(contract.get("burn_label", "")), "role": "compute"},
		{"stat": "Minimum throughput", "value": NumberFormat.format_token_rate(float(contract.get("min_prompt_rate", 0.0)))},
		{"stat": "Quality floor", "value": str(int(contract.get("quality_min", 0)))},
		{"stat": "Heat ceiling", "value": "%d%%" % int(float(contract.get("max_heat_pct", 1.0)) * 100.0)},
		{"stat": "Deadline", "value": "%d prompts" % int(contract.get("deadline_prompts", 12))},
		{
			"stat": "Reward",
			"value": (
				"%d unlock pick(s)" % int(contract.get("picks", 1)) if _is_final(contract)
				else "%d reward pick(s), spent now" % int(contract.get("picks", 1))
			),
			"role": "perk",
		},
	]
	if _is_final(contract):
		rows.append({
			"rule": "This one ends it",
			"text": "Completing a Tier %d contract beats the game. You can carry the run on into an endless tail afterwards." % AscensionSystem.FINAL_TIER,
		})
	else:
		rows.append({
			"rule": "The run continues",
			"text": "Completing this hands the run back with its reward picks to spend and the next tier of contracts on the table.",
		})
	if bool(contract.get("unlocks_age", false)):
		rows.append({"rule": "Advances the Compute Age", "text": "Completing this contract moves every future run into the next age."})
	if str(contract.get("ending_unlock", "")) != "":
		rows.append({"rule": "Unique reward", "text": "This ending unlocks a permanent mechanic no other contract grants."})
	_detail_sheet.show_detail(
		str(contract.get("name", "Contract")),
		"Tier %d Ascension Contract" % int(contract.get("tier", 1)),
		rows,
		[],
		"COMMIT TO THIS",
		UiThemeBuilder.color("red")
	)
	for connection in _detail_sheet.action_confirmed.get_connections():
		_detail_sheet.action_confirmed.disconnect(connection["callable"])
	_detail_sheet.action_confirmed.connect(_confirm_commit.bind(contract))


func _confirm_commit(contract: Dictionary) -> void:
	var rows: Array = [
		{"text": "There is no undo. Ordinary contracts still pay the bills, but every round from here is measured against %s." % str(contract.get("name", "this contract"))},
	]
	if not _is_final(contract):
		rows.append({
			"rule": "Clearing it is not the end",
			"text": "The run carries on with %d reward pick(s) to spend and the tier above unlocked." % int(contract.get("picks", 1)),
		})
	_detail_sheet.show_detail(
		"Commit to %s?" % str(contract.get("name", "this contract")),
		"Final Burn",
		rows,
		[],
		"COMMIT — START THE FINAL BURN",
		UiThemeBuilder.color("red")
	)
	for connection in _detail_sheet.action_confirmed.get_connections():
		_detail_sheet.action_confirmed.disconnect(connection["callable"])
	_detail_sheet.action_confirmed.connect(func() -> void:
		if Simulation.commit_ascension_contract(str(contract.get("id", ""))):
			hide_overlay()
			get_tree().call_group("ui_refresh", "refresh")
			get_tree().call_group("main_ui", "refresh_all")
	)
