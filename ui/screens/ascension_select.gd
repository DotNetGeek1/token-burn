extends Control

## The contract this location is being played for, and how far through it the run
## is. There is nothing to decide here: the investor set the terms before the
## first prompt and the run is measured against them from round one. This is the
## sheet the player opens to re-read what he asked for.
##
## Completing it wins the run and opens the next location. Reaching the end of
## the year without it ends the run. Both halves are said plainly, because a
## player who does not know the deadline cannot play against it.

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
	close_button.set_lines("BACK TO WORK", "The clock does not stop while you read")
	if contract.is_empty():
		cards_list.add_child(_note(
			"There is no contract for this location yet. Ordinary work is all there is here."
		))
		return
	var progress: Dictionary = Dictionary(summary.get("progress", {}))
	for row in _progress_rows(contract, progress):
		cards_list.add_child(_progress_row(
			str(row["label"]), str(row["value"]), bool(row["met"])
		))
	cards_list.add_child(_note(_stakes_text(contract)))


## Names the contract and where the run stands against it. The deadline is stated
## every time: the year running out is the loss condition, and a player who only
## reads this screen once should still leave knowing that.
func _subtitle(summary: Dictionary) -> String:
	var contract: Dictionary = Dictionary(summary.get("contract", {}))
	var location: String = MetaProgress.location_name(str(summary.get("location", "")))
	if contract.is_empty():
		return "%s has no contract out of it." % location
	var progress: Dictionary = Dictionary(summary.get("progress", {}))
	return "%s is what %s wants out of %s, and it is due by the end of round %d. Finish it and the run is won; miss it and the run is over." % [
		str(contract.get("name", "The contract")),
		InvestorVoice.investor_name(),
		location,
		int(progress.get("deadline_round", 12)),
	]


func _progress_rows(contract: Dictionary, progress: Dictionary) -> Array:
	var total: float = float(contract.get("total_burn", 0.0))
	var burned: float = float(progress.get("tokens_burned", 0.0))
	var quality_min: float = float(contract.get("quality_min", 0.0))
	var quality_now: float = float(progress.get("quality_average", 0.0))
	var rounds_left: int = int(progress.get("rounds_remaining", 0))
	var rows: Array = [
		{
			"label": "Tokens burned",
			"value": "%s of %s" % [NumberFormat.format(burned), NumberFormat.format(total)],
			"met": burned >= total,
		},
		{
			"label": "Rounds left",
			"value": "%d of %d" % [rounds_left, int(progress.get("deadline_round", 12))],
			"met": rounds_left > 3,
		},
	]
	if quality_min > 0.0:
		rows.append({
			"label": "Average quality",
			"value": "%s of %s needed" % [
				JobPresentation.quality_mark(quality_now),
				JobPresentation.quality_mark(quality_min),
			],
			"met": quality_now >= quality_min,
		})
	rows.append({
		"label": "Pays out",
		"value": "%d unlock pick(s)" % int(contract.get("picks", 1)),
		"met": true,
	})
	return rows


func _progress_row(label_text: String, value_text: String, met: bool) -> Control:
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


## What finishing and missing the contract each mean, in one sentence, because
## this is the only deadline in the game that ends the run on its own.
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
	return "%s The year ending without it ends the run there and then, as does missing the rent twice." % won
