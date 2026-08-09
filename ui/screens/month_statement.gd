extends Control

## End-of-round bills: rent and the other running costs the round just racked up,
## with a plain-language explanation for each line. Always follows the Round
## Debrief, so the money going out is read against the money that came in.

signal continue_pressed

@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var subtitle_label: Label = $Panel/Margin/VBox/Subtitle
@onready var rows: VBoxContainer = $Panel/Margin/VBox/Scroll/Rows
@onready var continue_button: GameButton = $Panel/Margin/VBox/ContinueButton
@onready var _panel: PanelContainer = $Panel

var _stat_grid: GridContainer = null


func _ready() -> void:
	continue_button.pressed.connect(_on_continue)
	_panel.add_theme_stylebox_override("panel", UiThemeBuilder.docket_style())
	subtitle_label.add_theme_color_override("font_color", UiThemeBuilder.docket_ink("muted"))


func show_statement(statement: Dictionary) -> void:
	var round_number: int = int(statement.get("round", 1))
	var prompts_used: int = int(statement.get("prompts_used", 0))
	var paid: bool = bool(statement.get("paid_in_full", true))
	if paid:
		title_label.text = "ROUND %d BILLS PAID" % round_number
		title_label.add_theme_color_override(
			"font_color", UiThemeBuilder.semantic("success").darkened(0.45)
		)
		subtitle_label.text = "Rent and running costs are settled. Here is where the money went."
	else:
		title_label.text = "BILLS UNPAID"
		title_label.add_theme_color_override(
			"font_color", UiThemeBuilder.color("red").darkened(0.35)
		)
		subtitle_label.text = "You could not cover round %d. The shortfall became debt — miss twice in a row and you are evicted." % round_number

	for child in rows.get_children():
		child.queue_free()
	_begin_stat_grid()

	_add_row(
		"Rent",
		NumberFormat.format_cash(float(statement.get("rent", 0.0))),
		"A flat charge every round, however many prompts the round took. Moving somewhere bigger raises it."
	)
	var recurring: float = float(statement.get("recurring", 0.0))
	if recurring > 0.0:
		_add_row(
			"Subscriptions",
			NumberFormat.format_cash(recurring),
			"Standing fees from the upgrades you own, charged every round. Every purchase adds to this forever."
		)
	var cloud_bill: float = float(statement.get("cloud_bill", 0.0))
	if cloud_bill > 0.0:
		_add_row(
			"Cloud bill",
			NumberFormat.format_cash(cloud_bill),
			"Metered charges for rented capacity you burned this round."
		)
	# Only worth a subtotal once rent is not the whole bill.
	if recurring > 0.0 or cloud_bill > 0.0:
		_add_row(
			"Bills total",
			NumberFormat.format_cash(float(statement.get("bill_total", 0.0))),
			"The lump that came out of your balance just now."
		)
	_add_row(
		"Power and cloud",
		NumberFormat.format_cash(float(statement.get("operating", 0.0))),
		"Already paid prompt by prompt while you worked — %d prompt(s) this round. A longer round costs more here; the rent above does not move." % prompts_used
	)
	_add_row(
		"Round total",
		NumberFormat.format_cash(float(statement.get("round_total", 0.0))),
		"Everything this round cost to keep the lights on."
	)
	if paid:
		_add_row(
			"Cash now",
			NumberFormat.format_cash(float(statement.get("cash_after", 0.0))),
			"What is left to spend on hardware and contracts in the next round."
		)
	else:
		_add_row(
			"Debt added",
			NumberFormat.format_cash(float(statement.get("debt_added", 0.0))),
			"The part you could not pay. Total debt is now %s." % NumberFormat.format_cash(float(statement.get("debt", 0.0)))
		)
		var streak: int = int(statement.get("unpaid_streak", 0))
		if streak >= 1:
			_add_row(
				"Eviction warning",
				"%d of 2 missed" % streak,
				"Miss the bills two rounds running and the run ends."
			)
	if statement.has("event"):
		_add_row(
			"Something happened",
			str(statement.get("event", "")),
			"An end-of-round event fired. Check the office for what it changed."
		)

	UiTransition.enter(self)
	UiTransition.stagger(rows)
	var main := get_tree().get_first_node_in_group("main_ui")
	if main != null and main.has_method("sync_overlay_input"):
		main.sync_overlay_input()


func _begin_stat_grid() -> void:
	_stat_grid = GridContainer.new()
	_stat_grid.columns = 2
	_stat_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat_grid.add_theme_constant_override("h_separation", UiThemeBuilder.SPACE_LG)
	_stat_grid.add_theme_constant_override("v_separation", UiThemeBuilder.SPACE_MD)
	rows.add_child(_stat_grid)


func _add_row(name_text: String, value_text: String, explanation: String) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	var line := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = name_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", UiThemeBuilder.docket_ink("title"))
	line.add_child(name_label)
	var value_label := Label.new()
	value_label.text = value_text
	value_label.theme_type_variation = &"AccentLabel"
	value_label.add_theme_font_override("font", UiThemeBuilder.mono_font())
	value_label.add_theme_color_override("font_color", UiThemeBuilder.docket_ink())
	line.add_child(value_label)
	box.add_child(line)
	var explain := Label.new()
	explain.text = explanation
	explain.theme_type_variation = &"MutedLabel"
	explain.add_theme_color_override("font_color", UiThemeBuilder.docket_ink("muted"))
	explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(explain)
	(_stat_grid if _stat_grid != null else rows).add_child(box)


func _on_continue() -> void:
	visible = false
	continue_pressed.emit()
	var main := get_tree().get_first_node_in_group("main_ui")
	if main != null and main.has_method("sync_overlay_input"):
		main.sync_overlay_input()
