extends ConsoleOverlay

## End of run. The debrief is the whole point of the endgame rewrite: cash was
## always the means, so the run's legacy is reported here as tokens burned,
## not dollars banked.
##
## Meeting a target is a level-up, not the end of the game: the same business
## carries on, in the same room and on the same calendar, against the next
## Investor Target. Every target met also brings the investor's perk table,
## which has to be answered (one run perk, or nothing) before any exit opens.
## Only the final target's completion is the ending proper: it banks the
## Permanent Unlock picks this screen doubles as the spend screen for — choose
## which area to boost permanently — and only it offers Deep Burn, the endless
## tail. A fresh run after any of this starts from nothing, carrying the
## Permanent Unlocks and nothing else.
##
## The verdict is the machine's closing report and is printed as one, but the
## picks under it are deliberately not: what you keep out of a dead company is
## a physical thing you take off the desk, so those stay as cards.

const CARD_SCENE := preload("res://ui/common/card.tscn")

## The player asked to see the investor's perk table. The flow raises the
## angel_investors overlay over this one; the exits stay shut until the pick
## is made or declined.
signal investor_draft_requested

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
## Completing the game can open a Deep Burn affix picker before the endless tail.
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
	# and only refreshed the picks. Reprint every time: TARGET COMPLETE must
	# replace COMPANY CLOSED when the outcome is a met target.
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
			_statement.set_title(
				"TOKEN BURN COMPLETE" if Simulation.game_completed() else "TARGET COMPLETE",
				ConsoleStyle.PHOSPHOR
			)
			set_context("INVESTOR TARGET MET")
			var target_name: String = str(score.get("contract_name", ""))
			var opening: String = (
				"%s: requirement met." % target_name
				if target_name != "" else "The target is complete."
			)
			_statement.set_note("%s %s%s" % [
				opening, _target_progress_text(), _victory_module_unlock_text(),
			])
		"depth_complete":
			_statement.set_title("DEPTH COMPLETE", ConsoleStyle.PHOSPHOR)
			var depth_level: int = int(Simulation.run_state.depth.get("level", 0))
			set_context("DEEP BURN // TARGET %d" % depth_level)
			_statement.set_note(
				"Deep Burn target %d is done. Keep burning to take another affix and go deeper."
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
	var progress: Dictionary = Simulation.investor_progress()
	if progress.is_empty():
		progress = Dictionary(Simulation.investor_summary().get("progress", {}))
	var total: float = float(progress.get("total_burn", 0.0))
	if total <= 0.0:
		return ""
	var burned: float = float(progress.get("tokens_burned", 0.0))
	return "You burned %s of the %s he asked for — %.0f%% of the way there." % [
		NumberFormat.format(burned), NumberFormat.format(total), (burned / total) * 100.0,
	]


## A met target is a level, not just a score: the Investor Level behind the
## player, and the one ahead. The next target itself is not live until the
## player takes it, so it is named by number rather than by its terms.
func _target_progress_text() -> String:
	var level: int = Simulation.investor_level()
	if Simulation.game_completed():
		return (
			"Investor Target %d is behind you, and there is nothing left to prove. "
			+ "Token Burn is complete — and the company does not have to stop here."
		) % level
	return (
		"Investor Target %d is behind you. Investor Target %d is next: the same business, "
		+ "the same room, the same calendar, against a bigger figure from %s."
	) % [level, level + 1, InvestorVoice.investor_name()]


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
		"CHOOSE YOUR PERMANENT UNLOCK" if _earned_this_run
		else "AN UNCLAIMED PERMANENT UNLOCK FROM AN EARLIER COMPLETION"
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
	# The investor's perk table has to be answered before the company moves
	# anywhere: the sim refuses to advance or continue while it is open.
	var draft_open: bool = Simulation.investor_draft_pending()
	var held: bool = has_pick or draft_open
	var entries: Array = []
	if draft_open:
		entries.append({
			"index": "1",
			"headline": "THE INVESTOR'S TERMS",
			"value": "%s has %d perks on the table. Take one, or take nothing." % [
				InvestorVoice.investor_name(), Simulation.pending_choices.size()
			],
			"pressed": _on_meet_investor,
		})
	# A met target that is not the final one continues in place: the next
	# Investor Target, same business, same calendar. Nothing else is on offer
	# for it — no endless tail, no fresh start — because the run is not over.
	if _target_ahead():
		entries.append({
			"index": str(entries.size() + 1),
			"headline": "NEXT TARGET",
			"value": "Investor Target %d, with everything you own" % (Simulation.investor_level() + 1),
			"enabled": not draft_open,
			"pressed": _on_next_target,
		})
	# Deep Burn is only on the table for the run that completed the game (or
	# is already in it): the build has to still exist for there to be anything
	# to carry.
	if _can_keep_playing():
		entries.append({
			"index": str(entries.size() + 1),
			"headline": "KEEP BURNING",
			"value": _keep_burning_subtitle(),
			"enabled": not held,
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
	elif not _target_ahead():
		entries.append({
			"index": str(entries.size() + 1),
			"headline": "NEW RUN",
			"value": "Start again from nothing, with your Permanent Unlocks",
			"enabled": not draft_open,
			"pressed": _on_restart,
		})
	entries.append({
		"index": str(entries.size() + 1),
		"headline": "TITLE SCREEN",
		"enabled": not has_pick,
		"pressed": _on_menu,
	})
	set_actions(entries)


func _on_meet_investor() -> void:
	if not Simulation.investor_draft_pending():
		refresh()
		return
	investor_draft_requested.emit()


func _keep(unlock_id: String) -> void:
	if not Simulation.spend_debrief_pick(unlock_id):
		return
	var unlock: Dictionary = MetaProgress.get_unlock(unlock_id)
	_keep_note = (
		"%s is yours for good, in every run from here. Everything else belongs to this company."
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
	return _earned_this_run and Simulation.game_completed()


## Whether this win opened a next Investor Target the company can take.
func _target_ahead() -> bool:
	return (
		_earned_this_run
		and not Simulation.game_completed()
		and bool(Simulation.run_state.flags.get("target_complete", false))
	)


## What KEEP BURNING leads into: the Deep Burn target the next affix opens.
func _keep_burning_subtitle() -> String:
	if not FeatureFlags.is_enabled("depth_ladder_enabled"):
		return "Endless"
	var depth_level: int = int(Simulation.run_state.depth.get("level", 0))
	return "DEEP BURN // TARGET %d" % (depth_level + 1)


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
		"value": "%s · the next target grows" % _keep_burning_subtitle(),
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
	if Simulation.investor_draft_pending():
		_on_meet_investor()
		return
	if not Simulation.continue_after_victory() and not Simulation.continue_after_depth():
		return
	hide_overlay()
	get_tree().call_group("flow_overlay", "hide_overlay")
	get_tree().call_group("ui_refresh", "refresh")
	get_tree().call_group("main_ui", "refresh_all")


## Takes the next Investor Target: the same company carries on in place, one
## level higher. The sim refuses while the investor's table is unanswered, so
## the table is raised instead of the exit silently doing nothing.
func _on_next_target() -> void:
	if Simulation.investor_draft_pending():
		_on_meet_investor()
		return
	if not Simulation.continue_after_target():
		refresh()
		return
	hide_overlay()
	get_tree().call_group("flow_overlay", "hide_overlay")
	get_tree().call_group("ui_refresh", "refresh")
	get_tree().call_group("main_ui", "refresh_all")


## A fresh game from nothing, carrying only the Permanent Unlocks.
func _on_restart() -> void:
	if Simulation.investor_draft_pending():
		_on_meet_investor()
		return
	hide_overlay()
	get_tree().call_group("flow_overlay", "hide_overlay")
	Simulation.start_run()
	get_tree().call_group("ui_refresh", "refresh")
	get_tree().call_group("main_ui", "refresh_all")


func _on_menu() -> void:
	hide_overlay()
	get_tree().call_group("flow_overlay", "hide_overlay")
	SceneRouter.open_title()
