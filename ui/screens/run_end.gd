extends ConsoleOverlay

## End of run. The debrief is the whole point of the endgame rewrite: cash was
## always the means, so the run's legacy is reported here as tokens burned,
## not dollars banked.
##
## A win mid-campaign is a level-up, not the end of the game: the location is
## complete, the next one is unlocked, and the company moves there with
## everything it owns — cash, perks, modules and rig alike. It pays nothing
## permanent. Only the last chapter's win is the ending proper: it banks the
## picks this screen doubles as the spend screen for — choose which area to
## boost permanently — and only it offers the endless tail. A fresh run after
## any of this starts back in the bedroom, carrying the permanent unlocks and
## nothing else.
##
## The verdict is the machine's closing report and is printed as one, but the
## picks under it are deliberately not: what you keep out of a dead company is
## a physical thing you take off the desk, so those stay as cards.

const CARD_SCENE := preload("res://ui/common/card.tscn")

var _statement: ConsoleStatement = null
var _pick_rule: ColorRect = null
var _pick_caption: Label = null
var _pick_list: VBoxContainer = null

## Whether this specific run just banked the pending pick(s) being offered.
## A pick skipped past on a win used to sit in the profile and quietly turn
## up on a *later*, unrelated run's end screen — including a loss — making it
## look like the reward for whatever ended that run. It never was: it is
## always paid out for completing the run that earned it, and only that run.
var _earned_this_run: bool = false
var _loss_reason: String = ""
## An aside the player's own last choice wrote, which survives the redraws that
## spending a pick triggers.
var _keep_note: String = ""
## Moon victory can open a Deep Burn affix picker before the endless tail.
var _picking_depth: bool = false


func _ready() -> void:
	super._ready()
	setup("Run Report")
	# There is no walking away from the end of a run, and an unspent pick has
	# to be spent here or it attaches itself to some later run's ending.
	dismiss_on_scrim = false
	set_closable(false)
	_build_body()


func _build_body() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content().add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)

	_statement = ConsoleStatement.new()
	_statement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_statement)

	_pick_rule = ConsoleStyle.rule(0.22)
	column.add_child(_pick_rule)

	_pick_caption = ConsoleStyle.label("", ConsoleStyle.FONT_BODY, ConsoleStyle.PHOSPHOR)
	column.add_child(_pick_caption)

	_pick_list = VBoxContainer.new()
	_pick_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pick_list.add_theme_constant_override("separation", 8)
	column.add_child(_pick_list)


## The contract `main.gd` drives the end of a run through. The overlay used to
## open itself on `EventBus.run_ended`, which put COMPANY CLOSED on top of a
## round that had just succeeded and whose save was still live. Only the shell
## may raise this, and only while the sim is actually over.
func show_from_state(victory: bool, loss_reason: String) -> void:
	if Simulation.phase != Simulation.Phase.RUN_END:
		if visible:
			hide_overlay()
		return
	_loss_reason = loss_reason
	var outcome: String = str(Simulation.run_state.flags.get("outcome", ""))
	if outcome == "" and victory:
		outcome = "ascended"
	_earned_this_run = outcome == "ascended"
	# A leftover loss verdict used to stick because a redraw skipped the report
	# and only refreshed the picks. Reprint every time: LOCATION COMPLETE must
	# replace COMPANY CLOSED when the outcome is an ascension.
	if visible:
		refresh()
		return
	_keep_note = ""
	_picking_depth = false
	open()


func refresh() -> void:
	var score: Dictionary = RunScore.compute(Simulation.run_state, ContentDatabase)
	_print_report(score)
	_refresh_debrief()
	_apply_body_metrics()
	# The run's legacy is one number, so it is counted up rather than printed.
	var total: float = float(score.get("total_tokens_burned", 0.0))
	if total > 0.0:
		UiTransition.count_up(_statement.figure_label(), total, 0.9, NumberFormat.format)


func fit_console() -> void:
	super.fit_console()
	_apply_body_metrics()


func _apply_body_metrics() -> void:
	if _statement == null:
		return
	var scale: float = console_scale()
	_statement.set_metrics(scale)
	_pick_caption.add_theme_font_size_override("font_size", ConsoleMetrics.font_body(scale))


func _print_report(score: Dictionary) -> void:
	_statement.clear()
	_apply_verdict(score)
	# The caption already says what the number is, so the figure is the bare
	# count rather than `format_tokens`' "... tokens".
	_statement.set_figure(
		NumberFormat.format(float(score.get("total_tokens_burned", 0.0))),
		"TOTAL TOKENS BURNED"
	)
	for row in RunScore.rows(score):
		_statement.add_item(str(row.get("label", "")), str(row.get("value", "")))
	UiTransition.stagger(_statement.items())


func _apply_verdict(score: Dictionary) -> void:
	var outcome: String = str(Simulation.run_state.flags.get("outcome", ""))
	# A win with a blank outcome used to fall through to COMPANY CLOSED. The
	# victory flag is the source of truth when the named outcome has not landed.
	if outcome == "" and bool(Simulation.run_state.flags.get("victory", false)):
		outcome = "ascended"
	match outcome:
		"ascended":
			var next_location: String = Simulation.next_location_unlocked()
			_statement.set_title(
				"ASCENDED" if next_location == "" else "LOCATION COMPLETE", ConsoleStyle.PHOSPHOR
			)
			set_context("CONTRACT MET")
			var contract_name: String = str(score.get("contract_name", ""))
			var opening: String = (
				"%s: requirement met." % contract_name
				if contract_name != "" else "The contract is complete."
			)
			_statement.set_note("%s %s%s" % [
				opening, _campaign_progress_text(), _victory_module_unlock_text(),
			])
		"depth_complete":
			_statement.set_title("DEPTH COMPLETE", ConsoleStyle.PHOSPHOR)
			set_context("DEEP BURN")
			var depth_level: int = int(Simulation.run_state.depth.get("level", 0))
			_statement.set_note(
				"Depth %d is done. Keep playing to take another affix and go deeper."
				% depth_level
			)
		"contract_expired":
			_statement.set_title("TIME UP", ConsoleStyle.DANGER)
			set_context("CONTRACT EXPIRED", ConsoleStyle.DANGER)
			var expired: String = (
				"The year ended with the contract unfinished. %s takes the hardware back."
				% InvestorVoice.investor_name()
			)
			_statement.set_note("%s %s" % [expired, _contract_shortfall_text()])
		_:
			_statement.set_title("RUN ENDED", ConsoleStyle.DANGER)
			set_context("COMPANY CLOSED", ConsoleStyle.DANGER)
			_statement.set_note(
				_loss_reason if _loss_reason != "" else "The company collapsed."
			)
	var aside: String = _keep_note
	if aside == "":
		aside = str(score.get("comparison", ""))
	_statement.set_aside(aside)


## Compact angel-pool notice when this banked victory crosses a module gate.
func _victory_module_unlock_text() -> String:
	if not _earned_this_run:
		return ""
	var unlocked: Array[ModuleDefinition] = ContentDatabase.modules_unlocked_at_victory_counts(
		MetaProgress.victories(), MetaProgress.victories_on("hard")
	)
	if unlocked.is_empty():
		return ""
	var names: PackedStringArray = []
	for module in unlocked:
		names.append(module.name)
		if names.size() >= 6:
			break
	var listed: String = ", ".join(names)
	if unlocked.size() > names.size():
		listed = "%s, +%d more" % [listed, unlocked.size() - names.size()]
	return " NEW MODULES CAN APPEAR IN THE MARKET: %s." % listed


## How close the run came, which is the only useful thing to say to somebody who
## has just run out of year.
func _contract_shortfall_text() -> String:
	var progress: Dictionary = Simulation.ascension_progress()
	if progress.is_empty():
		progress = Dictionary(Simulation.ascension_summary().get("progress", {}))
	var total: float = float(progress.get("total_burn", 0.0))
	if total <= 0.0:
		return ""
	var burned: float = float(progress.get("tokens_burned", 0.0))
	return "You burned %s of the %s he asked for — %.0f%% of the way there." % [
		NumberFormat.format(burned), NumberFormat.format(total), (burned / total) * 100.0,
	]


## A win is a chapter, not just a score: the location is behind the player and
## the next one is open. Naming it here is the only place the campaign's shape
## is visible at the moment it changes.
func _campaign_progress_text() -> String:
	var location: String = MetaProgress.location_name(
		str(Simulation.run_state.build.get("dwelling", ""))
	)
	var next_location: String = MetaProgress.location_name(Simulation.next_location_unlocked())
	if next_location == "":
		return "%s is behind you, and there is nowhere further up to go. You have beaten the game — and the company does not have to stop here." % location
	return "%s is behind you. %s took the meeting and bought you the %s — the company moves there with everything it owns, against a bigger contract." % [
		location, InvestorVoice.investor_name(), next_location
	]


## A banked pick has to be spent before the next run starts, so every way off
## this screen waits until the player has chosen what they are keeping —
## otherwise an unclaimed pick sits in the profile and turns up attached to
## whatever run happens to end next, win or lose.
func _refresh_debrief() -> void:
	for child in _pick_list.get_children():
		_pick_list.remove_child(child)
		child.queue_free()
	if _picking_depth:
		_show_depth_picks()
		return
	var choices: Array = Simulation.debrief_choices()
	var has_pick: bool = not choices.is_empty()
	_pick_rule.visible = has_pick
	_pick_caption.visible = has_pick
	_pick_list.visible = has_pick
	_pick_caption.text = (
		"CHOOSE YOUR REWARD FOR ASCENDING" if _earned_this_run
		else "AN UNCLAIMED REWARD FROM AN EARLIER ASCENSION"
	)
	_set_exits(has_pick)
	if not has_pick:
		return
	for unlock in choices:
		var card: GameCard = CARD_SCENE.instantiate()
		var owned: int = MetaProgress.unlock_count(str(unlock.get("id", "")))
		var ranks: Array = Array(unlock.get("ranks", []))
		var chip_text: String = "Permanent"
		if owned > 0:
			chip_text = "Already kept ×%d" % owned if ranks.is_empty() else "Rank %d / %d" % [owned, ranks.size()]
		var hard_req: Array = Array(unlock.get("hard_victories_required", []))
		if not ranks.is_empty() and owned < ranks.size() and owned < hard_req.size():
			var needed: int = int(hard_req[owned])
			if needed > MetaProgress.victories_on("hard"):
				chip_text = "%s · needs %d Hard win(s)" % [chip_text, needed]
		card.setup(
			str(unlock.get("name", "Unlock")),
			"%s\n%s" % [str(unlock.get("description", "")), str(unlock.get("flavour", ""))],
			"",
			"KEEP THIS",
			AssetCatalog.unlock_icon(str(unlock.get("kind", "")))
		)
		card.set_chips([{
			"text": chip_text,
			"role": "perk",
			"filled": true,
		}])
		card.set_action_style("reputation", "perk")
		card.pressed.connect(_keep.bind(str(unlock.get("id", ""))))
		_pick_list.add_child(card)
	UiTransition.stagger(_pick_list)


func _set_exits(has_pick: bool) -> void:
	var pending: int = MetaProgress.pending_picks()
	var entries: Array = []
	# Carrying on into the endless tail is only on the table for the run that
	# beat the last chapter: a mid-campaign win's continuation is the next
	# location, and the build has to still exist for there to be anything to
	# carry.
	if _can_keep_playing():
		entries.append({
			"index": "1",
			"headline": "KEEP PLAYING",
			"value": "Deep Burn" if FeatureFlags.is_enabled("depth_ladder_enabled") else "Endless",
			"enabled": not has_pick,
			"pressed": _on_continue,
		})
	if has_pick:
		entries.append({
			"index": str(entries.size() + 1),
			"headline": "CHOOSE WHAT YOU KEEP",
			"value": (
				"%d left to spend" % pending if pending > 1 else "One left to spend"
			),
			"enabled": false,
		})
	else:
		entries.append({
			"index": str(entries.size() + 1),
			"headline": "NEXT CHAPTER" if _chapter_ahead() else "NEW RUN",
			"value": _new_run_subtitle(),
			"pressed": _on_restart,
		})
	entries.append({
		"index": str(entries.size() + 1),
		"headline": "TITLE SCREEN",
		"enabled": not has_pick,
		"pressed": _on_menu,
	})
	set_actions(entries)


func _keep(unlock_id: String) -> void:
	if not Simulation.spend_debrief_pick(unlock_id):
		return
	var unlock: Dictionary = MetaProgress.get_unlock(unlock_id)
	_keep_note = (
		"%s stays with you. Everything else was the company's, and there is no company."
		% str(unlock.get("name", "It"))
	)
	_statement.set_aside(_keep_note)
	_refresh_debrief()


func _on_continue() -> void:
	if _should_offer_depth():
		var picks: Array = Simulation.offer_depth_picks()
		if not picks.is_empty():
			_picking_depth = true
			_refresh_debrief()
			return
	_leave_into_continuation()


func _can_keep_playing() -> bool:
	if _is_depth_complete_overlay():
		return true
	return _earned_this_run and Simulation.next_location_unlocked() == ""


func _is_depth_complete_overlay() -> bool:
	return (
		str(Simulation.run_state.flags.get("outcome", "")) == "depth_complete"
		or bool(Simulation.run_state.flags.get("depth_complete", false))
	)


func _should_offer_depth() -> bool:
	if _picking_depth:
		return false
	if not FeatureFlags.is_enabled("depth_ladder_enabled"):
		return false
	if Simulation.depth_is_complete() or _is_depth_complete_overlay():
		return true
	return Simulation.can_begin_depth() and int(Simulation.run_state.depth.get("level", 0)) == 0


func _show_depth_picks() -> void:
	var picks: Array = Array(Simulation.run_state.depth.get("pending_picks", []))
	_pick_rule.visible = true
	_pick_caption.visible = true
	_pick_list.visible = true
	_pick_caption.text = "CHOOSE A DEEP BURN AFFIX"
	set_actions([{
		"index": "1",
		"headline": "PICK AN AFFIX",
		"value": "The next contract grows",
		"enabled": false,
	}])
	for affix in picks:
		if not affix is Dictionary:
			continue
		var card: GameCard = CARD_SCENE.instantiate()
		card.setup(
			str(affix.get("name", "Affix")),
			str(affix.get("description", "")),
			"Score ×%s" % str(affix.get("score_mult", 1.0)),
			"TAKE THIS",
			null,
			"danger"
		)
		card.set_action_style("reputation", "danger")
		card.pressed.connect(_choose_depth.bind(str(affix.get("id", ""))))
		_pick_list.add_child(card)
	UiTransition.stagger(_pick_list)


func _choose_depth(affix_id: String) -> void:
	var result: Dictionary = Simulation.choose_depth_affix(affix_id)
	if not bool(result.get("ok", false)):
		return
	_picking_depth = false
	_leave_into_continuation()


func _leave_into_continuation() -> void:
	if not Simulation.continue_after_victory() and not Simulation.continue_after_depth():
		return
	hide_overlay()
	get_tree().call_group("flow_overlay", "hide_overlay")
	get_tree().call_group("ui_refresh", "refresh")
	get_tree().call_group("main_ui", "refresh_all")


## Whether this win opened a next chapter the current company can move into.
func _chapter_ahead() -> bool:
	return _earned_this_run and Simulation.next_location_unlocked() != ""


## What the main exit leads to. After a mid-campaign win it is the move into
## the newly opened chapter; otherwise it is a fresh game from the bottom of
## the campaign, carrying only the permanent unlocks.
func _new_run_subtitle() -> String:
	if _chapter_ahead():
		return "Move into the %s with everything you own" % MetaProgress.location_name(
			Simulation.next_location_unlocked()
		)
	var location: String = MetaProgress.location_name(MetaProgress.selected_location())
	if location == "":
		return "Start again"
	return "Start again from the %s" % location


func _on_restart() -> void:
	hide_overlay()
	get_tree().call_group("flow_overlay", "hide_overlay")
	# A mid-campaign win continues as the same business in the next location;
	# only a loss (or the final chapter) starts over.
	if not Simulation.advance_to_next_chapter():
		Simulation.start_run()
	get_tree().call_group("ui_refresh", "refresh")
	get_tree().call_group("main_ui", "refresh_all")


func _on_menu() -> void:
	hide_overlay()
	get_tree().call_group("flow_overlay", "hide_overlay")
	SceneRouter.open_title()
