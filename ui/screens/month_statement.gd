extends PhoneOverlay

## End-of-round bills: rent and the other running costs the round just racked up,
## with a plain-language explanation for each line. Follows the job shipping,
## so the money going out is read against the money that came in — the header
## carries what the round paid and delivered, and the investor's one-line
## verdict on it, now that there is no separate debrief.
##
## Printed as a statement rather than shown as a docket: this is the invoice the
## machine hands over, and CONTINUE is the only way off it because the round
## cannot advance until the bills have been read.

signal continue_pressed

var _statement: PhoneStatement = null
var _data: Dictionary = {}


func _ready() -> void:
	super._ready()
	setup("Bills")
	# The bills are a mandatory step in the round flow, so neither a stray tap
	# on the room nor ESC may leave them: CONTINUE is what advances the flow.
	dismiss_on_scrim = false
	set_closable(false)
	_build_body()


func _build_body() -> void:
	_statement = PhoneStatement.new()
	_statement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content().add_child(_statement)
	set_actions([{"headline": "CONTINUE", "pressed": _on_continue}])


## The contract `main.gd` drives the end-of-round flow through.
func show_statement(statement: Dictionary) -> void:
	_data = statement
	open()


func refresh() -> void:
	if _data.is_empty():
		return
	_print_statement(_data)


func _print_statement(statement: Dictionary) -> void:
	var round_number: int = int(statement.get("round", 1))
	var prompts_used: int = int(statement.get("prompts_used", 0))
	var paid: bool = bool(statement.get("paid_in_full", true))
	var success_color: Color = UiThemeBuilder.semantic("success")
	var warning_color: Color = UiThemeBuilder.semantic("warning")
	var danger_color: Color = UiThemeBuilder.semantic("danger")

	set_kicker("ROUND %d" % round_number)
	_print_round_context()
	_statement.clear()
	if bool(statement.get("waived", false)):
		_statement.set_title("ROUND %d BILLS COVERED" % round_number, success_color)
		_statement.set_note(
			"The contract is complete, so the investor settled this round's %s of rent and standing costs."
			% NumberFormat.format_cash(float(statement.get("waived_total", 0.0)))
		)
	elif paid:
		_statement.set_title("ROUND %d BILLS PAID" % round_number, success_color)
		_statement.set_note("Rent and running costs are settled. Here is where the money went.")
	else:
		_statement.set_title("BILLS UNPAID", danger_color)
		_statement.set_note("You could not cover round %d. The shortfall became debt — miss twice in a row and you are evicted." % round_number)
	var round_total: float = float(statement.get("round_total", 0.0))
	_statement.set_figure(
		NumberFormat.format_cash(round_total),
		"OUT THIS ROUND",
		success_color if paid else danger_color
	)
	UiTransition.count_up(_statement.figure_label(), round_total)

	_statement.add_item(
		"Rent",
		NumberFormat.format_cash(float(statement.get("rent", 0.0))),
		"A flat charge every round, however many prompts the round took. Moving somewhere bigger raises it."
	)
	var recurring: float = float(statement.get("recurring", 0.0))
	if recurring > 0.0:
		_statement.add_item(
			"Subscriptions",
			NumberFormat.format_cash(recurring),
			"Standing fees from the upgrades you own, charged every round. Every purchase adds to this forever."
		)
	# Only worth a subtotal once rent is not the whole bill.
	if recurring > 0.0:
		_statement.add_item(
			"Bills total",
			NumberFormat.format_cash(float(statement.get("bill_total", 0.0))),
			"The lump that came out of your balance just now.",
			{"rule_above": true}
		)
	_statement.add_item(
		"Power",
		NumberFormat.format_cash(float(statement.get("operating", 0.0))),
		"Already paid prompt by prompt while you worked — %d prompt(s) this round. A longer round costs more here; the rent above does not move." % prompts_used
	)
	_statement.add_item(
		"Round total",
		NumberFormat.format_cash(round_total),
		"Everything this round cost to keep the lights on.",
		{"emphasis": true}
	)
	if paid:
		_statement.add_item(
			"Cash now",
			NumberFormat.format_cash(float(statement.get("cash_after", 0.0))),
			"What is left to spend on hardware and contracts in the next round."
		)
	else:
		_statement.add_item(
			"Debt added",
			NumberFormat.format_cash(float(statement.get("debt_added", 0.0))),
			"The part you could not pay. Total debt is now %s." % NumberFormat.format_cash(float(statement.get("debt", 0.0))),
			{"value_color": danger_color}
		)
		var streak: int = int(statement.get("unpaid_streak", 0))
		if streak >= 1:
			_statement.add_item(
				"Eviction warning",
				"%d of 2 missed" % streak,
				"Miss the bills two rounds running and the run ends.",
				{"value_color": danger_color}
			)
	if statement.has("event"):
		_statement.add_item(
			"Something happened",
			str(statement.get("event", "")),
			"An end-of-round event fired. Check the office for what it changed.",
			{"value_color": warning_color}
		)
	UiTransition.stagger(_statement.items())


## What the round brought in, under the title, and the investor's verdict on it
## as the statement's aside. Both come from the work session that just ended;
## a bills screen shown with no session behind it says nothing here.
func _print_round_context() -> void:
	var summary: Dictionary = Simulation.last_session_summary
	if summary.is_empty():
		set_context("")
		_statement.set_aside("")
		return
	var success: bool = bool(summary.get("success", false))
	set_context(
		"PAID %s · %d delivered · %d missed" % [
			NumberFormat.format_cash(float(summary.get("reward", 0.0))),
			int(summary.get("completed", 0)),
			int(summary.get("failed", 0)),
		]
	)
	# The bills go along too, so a round that delivered and then missed the rent
	# gets his line about the rent.
	var quip: String = InvestorVoice.debrief_quip(summary, _data)
	if quip == "":
		_statement.set_aside("")
		return
	var paid: bool = bool(_data.get("paid_in_full", true))
	_statement.set_aside(
		"%s — %s" % [quip, InvestorVoice.investor_name()],
		UiThemeBuilder.semantic("success") if success and paid else UiThemeBuilder.semantic("danger")
	)


func _on_continue() -> void:
	hide_overlay()
	continue_pressed.emit()
