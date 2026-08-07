extends Control

## The way out of the year: the one boss contract this location has, and what the
## build still has to prove before it can be committed to. Committing switches the
## run into a Final Burn — there is no undo, so this opens as an explicit overlay
## rather than something that could be tapped by accident.
##
## Completing it wins the run and opens the next location. Failing it ends the
## run. Both halves are said plainly on the card, because a player who does not
## know the stakes cannot make the decision this overlay exists to ask for.

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
	var summary: Dictionary = Simulation.ascension_summary()
	var contract: Dictionary = Dictionary(summary.get("contract", {}))
	empty_label.visible = false
	subtitle_label.text = _subtitle(summary)
	if contract.is_empty():
		cards_list.add_child(_note(
			"There is no Ascension Contract for this location yet. Ordinary work is all there is here."
		))
		_refresh_close_button()
		return
	# The checklist is always shown, qualified or not: a card the player cannot
	# yet press has to say what would make it pressable, and one they can press
	# is worth showing the margin on.
	if bool(summary.get("qualified", false)) and not bool(summary.get("committed", false)):
		cards_list.add_child(_build_card(contract))
	for row in _requirement_rows(Dictionary(summary.get("qualification", {}))):
		cards_list.add_child(_requirement_row(
			str(row["label"]), str(row["value"]), bool(row["met"])
		))
	_refresh_close_button()


## Names the boss, where the run stands against it, and what it is worth — win or
## lose. The endgame used to be invisible until it was already available, which is
## how a first run reaches the end of the year without knowing it existed.
func _subtitle(summary: Dictionary) -> String:
	var contract: Dictionary = Dictionary(summary.get("contract", {}))
	var location: String = MetaProgress.location_name(str(summary.get("location", "")))
	if contract.is_empty():
		return "%s has no contract out of it." % location
	var boss: String = str(contract.get("name", "the contract"))
	if bool(summary.get("committed", false)):
		return "%s is underway. Every prompt from here is measured against it." % boss
	if bool(summary.get("qualified", false)):
		return (
			"%s is the way out of %s, and the build has qualified for it. Completing it wins the run; failing it ends it."
			% [boss, location]
		)
	return (
		"%s is the way out of %s. The run ends by completing it, not by the calendar running out. Here is what the build still has to prove."
		% [boss, location]
	)


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
	card.set_kicker(_boss_kicker(contract), UiThemeBuilder.color("red"))
	card.set_headline(str(contract.get("burn_label", "")), "compute")
	card.set_chips(_chips(contract))
	card.set_action_style("warning", "danger", "DangerButton")
	card.pressed.connect(_confirm_commit.bind(contract))
	card.body_pressed.connect(_show_detail.bind(contract))
	return card


func _boss_kicker(contract: Dictionary) -> String:
	return "%s — the way out" % MetaProgress.location_name(str(contract.get("location", "")))


func _chips(contract: Dictionary) -> Array:
	return [
		{"text": "%d prompt deadline" % int(contract.get("deadline_prompts", 12)), "role": "warning"},
		{"text": "Quality %d+" % int(contract.get("quality_min", 0)), "role": "energy"},
		{"text": "Max %d violation(s)" % int(contract.get("max_failed_burns", 0)), "role": "danger"},
		{
			"text": "Banks %d pick(s)" % int(contract.get("picks", 1)),
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
			"value": "%d unlock pick(s)" % int(contract.get("picks", 1)),
			"role": "perk",
		},
	]
	rows.append({
		"rule": "This one ends it, either way",
		"text": _stakes_text(contract),
	})
	if bool(contract.get("unlocks_age", false)):
		rows.append({"rule": "Advances the Compute Age", "text": "Completing this contract moves every future run into the next age."})
	if str(contract.get("ending_unlock", "")) != "":
		rows.append({"rule": "Unique reward", "text": "This ending unlocks a permanent mechanic no other contract grants."})
	_detail_sheet.show_detail(
		str(contract.get("name", "Contract")),
		"%s Ascension Contract" % MetaProgress.location_name(str(contract.get("location", ""))),
		rows,
		[],
		"COMMIT TO THIS",
		UiThemeBuilder.color("red")
	)
	for connection in _detail_sheet.action_confirmed.get_connections():
		_detail_sheet.action_confirmed.disconnect(connection["callable"])
	_detail_sheet.action_confirmed.connect(_confirm_commit.bind(contract))


## What committing actually buys and costs, in one sentence each, because this is
## the only decision in the game that cannot be walked back.
func _stakes_text(contract: Dictionary) -> String:
	var next_location: String = MetaProgress.next_location_after(
		str(contract.get("location", ""))
	)
	var won: String = (
		"Completing it wins the run and unlocks %s to start the next one in."
			% MetaProgress.location_name(next_location)
		if next_location != ""
		else "Completing it wins the run; this is the last location there is."
	)
	return "%s Failing it ends the run there and then." % won


func _confirm_commit(contract: Dictionary) -> void:
	var rows: Array = [
		{"text": "There is no undo. Ordinary contracts still pay the bills, but every round from here is measured against %s." % str(contract.get("name", "this contract"))},
		{"rule": "Win or lose, it ends here", "text": _stakes_text(contract)},
	]
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
