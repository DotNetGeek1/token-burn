extends ConsoleOverlay

## Round Debrief: what the round just finished delivered, earned and cost, with a
## plain-language explanation for each number. Shown at the end of every round,
## and every contract the round took is accounted for in it — the round only ends
## once they have all resolved, so there is no "still in progress" to hide.
##
## Printed as a statement rather than shown as a docket: the machine reports the
## round back to the operator, and CONTINUE is the only way off it because the
## bills are waiting behind this screen.

signal continue_pressed

var _statement: ConsoleStatement = null
var _summary: Dictionary = {}


func _ready() -> void:
	super._ready()
	setup("Round Debrief")
	# The debrief is a mandatory step in the round flow, so neither a stray tap
	# on the room nor ESC may leave it: CONTINUE is what advances the flow.
	dismiss_on_scrim = false
	set_closable(false)
	_build_body()


func _build_body() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content().add_child(scroll)

	_statement = ConsoleStatement.new()
	_statement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_statement)

	set_actions([{"index": "1", "headline": "CONTINUE", "pressed": _on_continue}])


## The contract `main.gd` drives the end-of-round flow through.
func show_summary(summary: Dictionary) -> void:
	_summary = summary
	open()
	# The payout is the thing the round was for, so it lands as an event rather
	# than as a figure that was always on the glass.
	UiTransition.count_up(_statement.figure_label(), float(summary.get("reward", 0.0)), 0.55)
	UiSound.play("complete")


func refresh() -> void:
	if _summary.is_empty():
		return
	_print_statement(_summary)
	_apply_body_metrics()


func fit_console() -> void:
	super.fit_console()
	_apply_body_metrics()


func _apply_body_metrics() -> void:
	if _statement != null:
		_statement.set_metrics(console_scale())


func _print_statement(summary: Dictionary) -> void:
	var success: bool = bool(summary.get("success", false))
	var completed: int = int(summary.get("completed", 0))
	var failed: int = int(summary.get("failed", 0))
	var round_number: int = int(summary.get("round", 1))
	var prompts_used: int = int(summary.get("prompts_used", 0))

	set_context("ROUND %d" % round_number)
	_statement.clear()
	_statement.set_title("ROUND %d DEBRIEF" % round_number, _verdict_color(success, completed))
	if success:
		_statement.set_note("Every contract resolved and the clients accepted the work. The bills are next.")
	elif completed > 0:
		_statement.set_note("Some work landed, some ran out of time. You keep partial pay for what was finished, but reputation takes a hit.")
	else:
		_statement.set_note("Nothing was delivered this round. The bills still land, so the next round has to earn its way back.")
	_show_verdict(summary, success)
	_statement.set_figure(
		NumberFormat.format_cash(float(summary.get("reward", 0.0))), "PAID FOR THIS ROUND"
	)

	_statement.add_item(
		"Contracts",
		"%d delivered · %d missed" % [completed, failed],
		"Every contract you took this round is in one of these two columns — a round does not end until they all resolve."
	)
	_statement.add_item(
		"Prompts spent",
		str(prompts_used),
		"Each burn or cool is one prompt. Rent is the same however many the round took, but power is metered per prompt."
	)
	var slots: int = int(summary.get("job_slots", 1))
	if slots > 1:
		_statement.add_item(
			"Parallel lanes",
			"%d machines" % slots,
			"Your machines worked %d contracts side by side, sharing one batch between them. More machines means more deadlines moving at once, not a bigger batch." % slots
		)
	var early_jobs: int = int(summary.get("early_jobs", 0))
	if early_jobs > 0:
		_statement.add_item(
			"Early delivery",
			"+%d%% on %d contract(s)" % [int(round(float(summary.get("early_bonus_pct", 0.0)) * 100.0)), early_jobs],
			"Clients pay a premium for work that arrives before they expected it. Every prompt to spare is worth more fee."
		)
	_statement.add_item(
		"Money earned",
		NumberFormat.format_cash(float(summary.get("reward", 0.0))),
		"Payout received for delivered work, after quality adjustments."
	)
	_statement.add_item(
		"Money spent",
		NumberFormat.format_cash(float(summary.get("spent", 0.0))),
		"Running costs during the round: energy and other burn. Rent is not in here — that lands on the next screen.",
		{"value_color": ConsoleStyle.WARNING}
	)
	_statement.add_item(
		"Cash now",
		NumberFormat.format_cash(float(summary.get("cash_after", 0.0))),
		"Your new balance. If it hits zero, the run is over.",
		{"emphasis": true}
	)
	var quality: float = float(summary.get("avg_quality", 0.0))
	var threshold: float = float(summary.get("avg_quality_threshold", 0.0))
	var multiplier: float = float(summary.get("quality_multiplier", 1.0))
	_statement.add_item(
		"Average quality",
		JobPresentation.quality_against_bar(quality, threshold),
		"Final quality across the round's contracts, marked out of ten against what the clients asked for.",
		{"rule_above": true}
	)
	_statement.add_item(
		"Quality payout",
		"×%.2f" % multiplier,
		_quality_payout_note(multiplier)
	)
	var reputation_delta: float = float(summary.get("reputation_delta", 0.0))
	if absf(reputation_delta) > 0.01:
		_statement.add_item(
			"Reputation",
			"%+.0f" % reputation_delta,
			"Clearing the quality bar comfortably earns more than scraping under it. Reputation opens bigger clients and raises what they pay."
		)
	var bugs: int = int(summary.get("bugs", 0))
	if bugs > 0:
		_statement.add_item(
			"Bugs",
			str(bugs),
			"Bugs appeared during the work and dragged quality down. Perks can soften this.",
			{"value_color": ConsoleStyle.DANGER}
		)
	_statement.add_item(
		"Tokens processed",
		NumberFormat.format_tokens(float(summary.get("tokens_processed", 0.0))),
		"Total AI output produced this round."
	)
	_statement.add_item(
		"Throughput",
		"%s / prompt" % NumberFormat.format_tokens(float(summary.get("tokens_per_tick", 0.0))),
		"Tokens produced per prompt. Upgrade hardware to finish contracts in fewer prompts."
	)
	UiTransition.stagger(_statement.items())


func _verdict_color(success: bool, completed: int) -> Color:
	if success:
		return ConsoleStyle.PHOSPHOR
	return ConsoleStyle.WARNING if completed > 0 else ConsoleStyle.DANGER


func _quality_payout_note(multiplier: float) -> String:
	if multiplier > 1.001:
		return "Work above the client's bar is paid for. The fee went up by %d%%." % int(round((multiplier - 1.0) * 100.0))
	if multiplier < 0.999:
		return "Delivering under the bar tapers the fee rather than voiding it. This round kept %d%% of it." % int(round(multiplier * 100.0))
	return "The work landed exactly on the client's bar, so the fee was paid in full."


## The one voice in the game gets the last word on the round. This is the opening
## line of the call he is about to make, so the note on the statement and the
## phone that follows it are the same man saying the same thing.
func _show_verdict(summary: Dictionary, success: bool) -> void:
	var quip: String = InvestorVoice.debrief_quip(summary)
	if quip == "":
		_statement.set_aside("")
		return
	_statement.set_aside(
		"%s — %s" % [quip, InvestorVoice.investor_name()],
		ConsoleStyle.PHOSPHOR if success else ConsoleStyle.DANGER
	)


func _on_continue() -> void:
	hide_overlay()
	continue_pressed.emit()
