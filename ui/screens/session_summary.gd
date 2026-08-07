extends Control

## Round Debrief: what the round just finished delivered, earned and cost, with a
## plain-language explanation for each number. Shown at the end of every round,
## and every contract the round took is accounted for in it — the round only ends
## once they have all resolved, so there is no "still in progress" to hide.

signal continue_pressed

## What the client says about the work. The verdict, not the spreadsheet, is
## what the player remembers about a contract.
const VERDICTS := {
	"great": [
		"\"Genuinely better than the humans we replaced.\"",
		"\"We are forwarding this to the board. Unedited.\"",
		"\"Do you have capacity for six more of these?\"",
	],
	"good": [
		"\"Fine. Ship it.\"",
		"\"Nobody complained, which is our highest praise.\"",
		"\"A few notes, but we'll live with them.\"",
	],
	"poor": [
		"\"It technically satisfies the brief.\"",
		"\"Our intern has already found three problems.\"",
		"\"We paid, but we're not thrilled.\"",
	],
	"failed": [
		"\"We went with someone else. Faster, apparently.\"",
		"\"The deadline was the one part that mattered.\"",
		"\"Let's call this a learning experience. Yours.\"",
	],
}

@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var subtitle_label: Label = $Panel/Margin/VBox/Subtitle
@onready var verdict_label: Label = $Panel/Margin/VBox/Verdict
@onready var reward_value: Label = $Panel/Margin/VBox/RewardValue
@onready var rows: VBoxContainer = $Panel/Margin/VBox/Scroll/Rows
@onready var continue_button: GameButton = $Panel/Margin/VBox/ContinueButton


func _ready() -> void:
	continue_button.pressed.connect(_on_continue)


func show_summary(summary: Dictionary) -> void:
	var success: bool = bool(summary.get("success", false))
	var completed: int = int(summary.get("completed", 0))
	var failed: int = int(summary.get("failed", 0))
	var round_number: int = int(summary.get("round", 1))
	var prompts_used: int = int(summary.get("prompts_used", 0))
	title_label.text = "ROUND %d DEBRIEF" % round_number
	if success:
		title_label.add_theme_color_override("font_color", UiThemeBuilder.semantic("success"))
		subtitle_label.text = "Every contract resolved and the clients accepted the work. The bills are next."
	elif completed > 0:
		title_label.add_theme_color_override("font_color", UiThemeBuilder.semantic("warning"))
		subtitle_label.text = "Some work landed, some ran out of time. You keep partial pay for what was finished, but reputation takes a hit."
	else:
		title_label.add_theme_color_override("font_color", UiThemeBuilder.semantic("failure"))
		subtitle_label.text = "Nothing was delivered this round. The bills still land, so the next round has to earn its way back."
	_show_verdict(summary, success)
	_slam_reward(float(summary.get("reward", 0.0)))

	for child in rows.get_children():
		child.queue_free()

	_add_row(
		"Contracts",
		"%d delivered · %d missed" % [completed, failed],
		"Every contract you took this round is in one of these two columns — a round does not end until they all resolve."
	)
	_add_row(
		"Prompts spent",
		str(prompts_used),
		"Each burn or cool is one prompt. Rent is the same however many the round took, but power is metered per prompt."
	)
	var slots: int = int(summary.get("job_slots", 1))
	if slots > 1:
		_add_row(
			"Parallel lanes",
			"%d machines" % slots,
			"Your machines worked %d contracts side by side, sharing one batch between them. More machines means more deadlines moving at once, not a bigger batch." % slots
		)
	var early_jobs: int = int(summary.get("early_jobs", 0))
	if early_jobs > 0:
		_add_row(
			"Early delivery",
			"+%d%% on %d contract(s)" % [int(round(float(summary.get("early_bonus_pct", 0.0)) * 100.0)), early_jobs],
			"Clients pay a premium for work that arrives before they expected it. Every prompt to spare is worth more fee."
		)
	_add_row(
		"Money earned",
		NumberFormat.format_cash(float(summary.get("reward", 0.0))),
		"Payout received for delivered work, after quality adjustments."
	)
	_add_row(
		"Money spent",
		NumberFormat.format_cash(float(summary.get("spent", 0.0))),
		"Running costs during the round: energy, cloud rental and other burn. Rent is not in here — that lands on the next screen."
	)
	_add_row(
		"Cash now",
		NumberFormat.format_cash(float(summary.get("cash_after", 0.0))),
		"Your new balance. If it hits zero, the run is over."
	)
	var quality: float = float(summary.get("avg_quality", 0.0))
	var threshold: float = float(summary.get("avg_quality_threshold", 0.0))
	var multiplier: float = float(summary.get("quality_multiplier", 1.0))
	_add_row(
		"Average quality",
		"%.0f vs bar of %.0f" % [quality, threshold],
		"Final quality across the round's contracts, against what the clients asked for."
	)
	_add_row(
		"Quality payout",
		"×%.2f" % multiplier,
		_quality_payout_note(multiplier)
	)
	var reputation_delta: float = float(summary.get("reputation_delta", 0.0))
	if absf(reputation_delta) > 0.01:
		_add_row(
			"Reputation",
			"%+.0f" % reputation_delta,
			"Clearing the quality bar comfortably earns more than scraping under it. Reputation opens bigger clients and raises what they pay."
		)
	var bugs: int = int(summary.get("bugs", 0))
	if bugs > 0:
		_add_row(
			"Bugs",
			str(bugs),
			"Bugs appeared during the work and dragged quality down. Perks can soften this."
		)
	_add_row(
		"Tokens processed",
		NumberFormat.format_tokens(float(summary.get("tokens_processed", 0.0))),
		"Total AI output produced this round."
	)
	_add_row(
		"Throughput",
		"%s / prompt" % NumberFormat.format_tokens(float(summary.get("tokens_per_tick", 0.0))),
		"Tokens produced per prompt. Upgrade hardware to finish contracts in fewer prompts."
	)

	UiTransition.enter(self)
	UiTransition.stagger(rows)
	var main := get_tree().get_first_node_in_group("main_ui")
	if main != null and main.has_method("sync_overlay_input"):
		main.sync_overlay_input()


func _quality_payout_note(multiplier: float) -> String:
	if multiplier > 1.001:
		return "Work above the client's bar is paid for. The fee went up by %d%%." % int(round((multiplier - 1.0) * 100.0))
	if multiplier < 0.999:
		return "Delivering under the bar tapers the fee rather than voiding it. This round kept %d%% of it." % int(round(multiplier * 100.0))
	return "The work landed exactly on the client's bar, so the fee was paid in full."


func _show_verdict(summary: Dictionary, success: bool) -> void:
	var quality: float = float(summary.get("avg_quality", 0.0))
	var band: String = "failed"
	if success:
		band = "great" if quality >= 80.0 else ("good" if quality >= 55.0 else "poor")
	var pool: Array = VERDICTS[band]
	# Seeded on the round's numbers so the same result reads the same way if the
	# player reopens the debrief.
	var index: int = absi(int(quality) + int(summary.get("reward", 0.0))) % pool.size()
	verdict_label.text = str(pool[index])
	verdict_label.add_theme_color_override(
		"font_color",
		UiThemeBuilder.semantic("success" if success else "failure")
	)


## The payout arrives with weight: it slams in oversized and counts up as it
## settles, so the number the round was for is the thing that moves.
func _slam_reward(reward: float) -> void:
	UiTransition.count_up(reward_value, reward, 0.55)
	reward_value.pivot_offset = reward_value.size / 2.0
	reward_value.scale = Vector2(1.6, 1.6)
	reward_value.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(reward_value, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(reward_value, "scale", Vector2.ONE, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	UiSound.play("complete")


func _add_row(name_text: String, value_text: String, explanation: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var line := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = name_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	var value_label := Label.new()
	value_label.text = value_text
	value_label.theme_type_variation = &"AccentLabel"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(value_label)
	box.add_child(line)
	var explain := Label.new()
	explain.text = explanation
	explain.theme_type_variation = &"MutedLabel"
	explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(explain)
	rows.add_child(box)


func _on_continue() -> void:
	visible = false
	continue_pressed.emit()
	var main := get_tree().get_first_node_in_group("main_ui")
	if main != null and main.has_method("sync_overlay_input"):
		main.sync_overlay_input()
