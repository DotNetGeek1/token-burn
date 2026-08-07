extends Control

## End of run. The debrief is the whole point of the endgame rewrite: cash was
## always the means, so the run's legacy is reported here as tokens burned,
## not dollars banked. On a win this doubles as the pick screen: exactly one
## thing survives into the next attempt (more, for a higher Ascension tier).
##
## Beating the game does not have to close the run down with it. A victory here is
## also an offer: keep the build and carry it on into an endless tail, where the
## bills climb every round and the only thing left to find out is how far it goes.

const CARD_SCENE := preload("res://ui/common/card.tscn")

@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/TitleLabel
@onready var body_label: Label = $Panel/Margin/VBox/BodyLabel
@onready var headline_label: Label = $Panel/Margin/VBox/HeadlineLabel
@onready var comparison_label: Label = $Panel/Margin/VBox/ComparisonLabel
@onready var score_list: VBoxContainer = $Panel/Margin/VBox/ScoreScroll/ScoreList
@onready var debrief_label: Label = $Panel/Margin/VBox/DebriefLabel
@onready var debrief_scroll: ScrollContainer = $Panel/Margin/VBox/DebriefScroll
@onready var debrief_list: VBoxContainer = $Panel/Margin/VBox/DebriefScroll/DebriefList
@onready var continue_button: GameButton = $Panel/Margin/VBox/ContinueButton
@onready var restart_button: GameButton = $Panel/Margin/VBox/RestartButton
@onready var menu_button: GameButton = $Panel/Margin/VBox/MenuButton

## Whether this specific run just banked the pending pick(s) being offered.
## A pick skipped past on a win used to sit in the profile and quietly turn
## up on a *later*, unrelated run's end screen — including a loss — making it
## look like the reward for whatever ended that run. It never was: it is
## always paid out for completing the run that earned it, and only that run.
var _earned_this_run: bool = false


func _ready() -> void:
	continue_button.pressed.connect(_on_continue)
	restart_button.pressed.connect(_on_restart)
	menu_button.pressed.connect(_on_menu)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("flow_overlay")
	EventBus.run_ended.connect(_on_run_ended)


func _on_run_ended(victory: bool) -> void:
	show_from_state(victory, Simulation.run_state.flags.get("loss_reason", ""))


func show_from_state(victory: bool, loss_reason: String) -> void:
	var outcome: String = str(Simulation.run_state.flags.get("outcome", "" if not victory else "ascended"))
	_earned_this_run = outcome == "ascended"
	var score: Dictionary = RunScore.compute(Simulation.run_state, ContentDatabase)
	_set_verdict(outcome, loss_reason, score)
	headline_label.text = RunScore.headline(score)
	comparison_label.text = str(score.get("comparison", ""))
	comparison_label.visible = comparison_label.text != ""
	_fill_score_rows(score)
	_refresh_debrief()
	UiTransition.enter(self)
	UiTransition.stagger(score_list)
	_count_up_legacy(score)
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().call_group("main_ui", "sync_overlay_input")


## The run's legacy is one number, so it is counted up rather than printed. The
## headline carries its own wording, so the ticker rewrites the figure inside it
## instead of formatting cash.
func _count_up_legacy(score: Dictionary) -> void:
	var total: float = float(score.get("total_tokens_burned", 0.0))
	if total <= 0.0:
		return
	var tween: Tween = headline_label.create_tween()
	tween.tween_method(
		func(value: float) -> void:
			headline_label.text = (
				"TOTAL TOKENS BURNED: %s" % NumberFormat.format_tokens(value)
			),
		0.0,
		total,
		0.9
	).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)


func _set_verdict(outcome: String, loss_reason: String, score: Dictionary) -> void:
	match outcome:
		"ascended":
			title_label.text = "ASCENDED"
			title_label.add_theme_color_override("font_color", UiThemeBuilder.semantic("success"))
			var contract_name: String = str(score.get("contract_name", ""))
			body_label.text = (
				"%s: requirement met. The infrastructure holds, for now." % contract_name
				if contract_name != "" else "The Ascension Contract is complete."
			)
			body_label.text += " " + _campaign_progress_text()
		"retired":
			# Only reachable from a save written before overtime existed; the
			# calendar no longer ends a run on its own.
			title_label.text = "RETIRED"
			title_label.add_theme_color_override("font_color", UiThemeBuilder.semantic("neutral"))
			body_label.text = "The year ran out under the old rules, before an Ascension Contract was ever signed. The company retires quietly, comfortably, and without a legacy."
		_:
			title_label.text = "RUN ENDED"
			title_label.add_theme_color_override("font_color", UiThemeBuilder.semantic("failure"))
			body_label.text = loss_reason if loss_reason != "" else "The company collapsed."
			# Overtime bills are what kill a run that never reached for a
			# contract, so name the cause rather than leaving it as bad luck.
			if bool(Simulation.run_state.flags.get("overtime", false)) and outcome != "ascension_failed":
				body_label.text += " The year had already run out: overtime costs climb every round until an Ascension Contract is completed."


## A win is a chapter, not just a score: the location is behind the player and
## the next one is open. Naming it here is the only place the campaign's shape
## is visible at the moment it changes.
func _campaign_progress_text() -> String:
	var location: String = MetaProgress.location_name(
		str(Simulation.run_state.build.get("dwelling", ""))
	)
	var next_location: String = MetaProgress.location_name(Simulation.next_location_unlocked())
	if next_location == "":
		return "%s is behind you, and there is nowhere further up to go. The company does not have to stop here." % location
	return "%s is behind you. %s is unlocked — a new run starts there." % [location, next_location]


func _fill_score_rows(score: Dictionary) -> void:
	for child in score_list.get_children():
		child.queue_free()
	for row in RunScore.rows(score):
		score_list.add_child(_stat_row(str(row.get("label", "")), str(row.get("value", ""))))


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


## A banked pick has to be spent before the next run starts, so both the New
## Run and Menu buttons wait until the player has chosen what they are
## keeping — otherwise an unclaimed pick sits in the profile and turns up
## attached to whatever run happens to end next, win or lose.
func _refresh_debrief() -> void:
	for child in debrief_list.get_children():
		child.queue_free()
	var choices: Array = Simulation.debrief_choices()
	var has_pick: bool = not choices.is_empty()
	debrief_label.visible = has_pick
	debrief_label.text = (
		"CHOOSE YOUR REWARD FOR ASCENDING" if _earned_this_run
		else "AN UNCLAIMED REWARD FROM AN EARLIER ASCENSION"
	)
	debrief_scroll.visible = has_pick
	restart_button.disabled = has_pick
	menu_button.disabled = has_pick
	# Carrying on is only on the table for the run that just won: the build has to
	# still exist for there to be anything to carry.
	continue_button.visible = _earned_this_run
	continue_button.disabled = has_pick
	var pending: int = MetaProgress.pending_picks()
	if has_pick:
		restart_button.set_lines(
			"CHOOSE WHAT YOU KEEP",
			"%d rewards left to spend" % pending if pending > 1 else "One reward left to spend"
		)
	else:
		restart_button.set_lines("NEW RUN", "Back to the bedroom")
	# A verdict is a page of numbers and sits in a scrolling panel; make room
	# for the debrief cards too when there is a pick to spend.
	panel.anchor_top = 0.04
	panel.anchor_bottom = 0.96
	if not has_pick:
		return
	for unlock in choices:
		var card: GameCard = CARD_SCENE.instantiate()
		var owned: int = MetaProgress.unlock_count(str(unlock.get("id", "")))
		card.setup(
			str(unlock.get("name", "Unlock")),
			"%s\n%s" % [str(unlock.get("description", "")), str(unlock.get("flavour", ""))],
			"",
			"KEEP THIS",
			AssetCatalog.unlock_icon(str(unlock.get("kind", "")))
		)
		card.set_chips([{
			"text": "Already kept ×%d" % owned if owned > 0 else "Permanent",
			"role": "perk",
			"filled": true,
		}])
		card.set_action_style("reputation", "perk")
		card.pressed.connect(_keep.bind(str(unlock.get("id", ""))))
		debrief_list.add_child(card)
	UiTransition.stagger(debrief_list)


func hide_overlay() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().call_group("main_ui", "sync_overlay_input")


func _keep(unlock_id: String) -> void:
	if not Simulation.spend_debrief_pick(unlock_id):
		return
	var unlock: Dictionary = MetaProgress.get_unlock(unlock_id)
	body_label.text = "%s stays with you. Everything else was the company's, and there is no company." % str(
		unlock.get("name", "It")
	)
	_refresh_debrief()


func _on_continue() -> void:
	if not Simulation.continue_after_victory():
		return
	hide_overlay()
	get_tree().call_group("flow_overlay", "hide_overlay")
	get_tree().call_group("ui_refresh", "refresh")
	get_tree().call_group("main_ui", "refresh_all")


## A new run after a win starts in the location the win opened, rather than
## dropping the player back into the chapter they have just beaten.
func _on_restart() -> void:
	hide_overlay()
	get_tree().call_group("flow_overlay", "hide_overlay")
	var next_location: String = Simulation.next_location_unlocked()
	if _earned_this_run and next_location != "":
		MetaProgress.select_location(next_location)
	Simulation.start_run()
	get_tree().call_group("ui_refresh", "refresh")
	get_tree().call_group("main_ui", "refresh_all")


func _on_menu() -> void:
	hide_overlay()
	get_tree().call_group("flow_overlay", "hide_overlay")
	get_tree().call_group("main_ui", "open_title")
