extends VenueScene

## Terms: the contract this location is being played for, and how far through it
## the run is.
##
## There is nothing to decide in this room. The investor set the terms before the
## first prompt and the run has been measured against them since round one, so this
## is the meeting the player calls on themselves to re-read what they agreed to.
##
## Both halves of the deal are said plainly and every time: finishing wins the run,
## and the year running out ends it. A player who does not know the deadline cannot
## play against it.

## How many cells a progress strip is drawn with. Ten reads as a percentage without
## asking anyone to count dots.
const PROGRESS_DOTS := 10

var _kicker: Label = null
var _index_lines: VBoxContainer = null
var _subtitle: Label = null
var _board_panel: VenuePanel = null
var _board: VenueBoard = null
var _stakes: Label = null
var _notice: Label = null


func venue_key() -> String:
	return "terms"


func _build_venue() -> void:
	_build_index()
	_build_board()
	_build_signage()
	_build_notice()
	EventBus.round_started.connect(refresh)
	EventBus.run_started.connect(refresh)
	Simulation.work_session_finished.connect(func(_result: Dictionary) -> void: refresh())


func _build_index() -> void:
	var panel: VenuePanel = add_panel("index", "Terms", {
		"console_order": 10, "console_min": 210.0,
	})
	var content: VBoxContainer = panel.content()

	_kicker = ConsoleStyle.label(
		"THE DEAL", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	content.add_child(_kicker)

	_index_lines = VBoxContainer.new()
	_index_lines.add_theme_constant_override("separation", 2)
	content.add_child(_index_lines)

	content.add_child(ConsoleStyle.rule(0.22))

	# The whole deal in a sentence, which is the thing this room exists to say.
	# It sits under the figures rather than over them because the figures are what
	# a returning player came back to check.
	_subtitle = ConsoleStyle.paragraph("", ConsoleStyle.FONT_SMALL)
	_subtitle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_subtitle)


func _build_board() -> void:
	_board_panel = add_panel("board", "Clauses", {
		"console_order": 20, "console_min": 220.0, "grow": true,
	})
	_board = VenueBoard.new()
	_board_panel.content().add_child(_board)


## The stakes, on the wall where a meeting room would hang the thing nobody wants
## to look at.
func _build_signage() -> void:
	var panel: VenuePanel = add_panel("signage", "Stakes", {
		"console_order": 30, "console_min": 110.0,
	})
	_stakes = ConsoleStyle.paragraph("", ConsoleStyle.FONT_TINY, ConsoleStyle.WARNING)
	_stakes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.content().add_child(_stakes)


func _build_notice() -> void:
	var panel: VenuePanel = add_panel("notice", "", {
		"console_order": 40, "console_min": 70.0,
	})
	_notice = ConsoleStyle.paragraph("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.content().add_child(_notice)


# --- Refresh -----------------------------------------------------------------

func refresh() -> void:
	if _board == null:
		return
	var summary: Dictionary = Simulation.ascension_summary()
	var contract: Dictionary = Dictionary(summary.get("contract", {}))
	var progress: Dictionary = Dictionary(summary.get("progress", {}))
	_subtitle.text = _subtitle_text(summary)
	_refresh_index(summary, contract, progress)
	_refresh_board(contract, progress)
	_refresh_stakes(contract)
	_refresh_notice(summary, contract, progress)


func _refresh_index(
	summary: Dictionary, contract: Dictionary, progress: Dictionary
) -> void:
	for child in _index_lines.get_children():
		_index_lines.remove_child(child)
		child.queue_free()
	var lines: Array = [
		{
			"stat": "Location",
			"value": MetaProgress.location_name(str(summary.get("location", ""))),
		},
	]
	if not contract.is_empty():
		var rounds_left: int = int(progress.get("rounds_remaining", 0))
		lines.append({"stat": "Contract", "value": str(contract.get("name", ""))})
		lines.append({
			"stat": "Rounds left",
			"value": "%d" % rounds_left,
			# Three rounds is the point at which the deadline stops being a date and
			# starts being the thing that decides the run.
			"color": ConsoleStyle.DANGER if rounds_left <= 3 else ConsoleStyle.PHOSPHOR,
		})
		lines.append({
			"stat": "Burned",
			"value": "%.0f%%" % (float(progress.get("burn_ratio", 0.0)) * 100.0),
		})
	var font: int = ConsoleMetrics.font_small(console_scale())
	for entry in lines:
		var line: Control = ConsoleStyle.detail_line(entry, font)
		if line != null:
			_index_lines.add_child(line)


## One card per clause. Every clause is the same shape — what it asks, how far
## along the run is, whether that is good enough yet — so the board is a listing
## rather than a grid.
func _refresh_board(contract: Dictionary, progress: Dictionary) -> void:
	if contract.is_empty():
		_board_panel.set_heading("No contract")
		_board.set_entries([], "NO CONTRACT FOR THIS LOCATION — ORDINARY WORK IS ALL THERE IS HERE")
		return
	_board_panel.set_heading("Clauses")
	var entries: Array = []
	for row in _progress_rows(contract, progress):
		var met: bool = bool(row["met"])
		var accent: Color = ConsoleStyle.PHOSPHOR if met else ConsoleStyle.WARNING
		entries.append({
			"meta": null,
			"name": str(row["label"]),
			"figure": _progress_strip(float(row["ratio"])),
			"figure_color": accent,
			"spec": str(row["value"]),
			"status": "MET" if met else "OUTSTANDING",
			"status_color": accent,
		})
	_board.set_entries(entries)


## The strip drawn out of characters rather than as dots on a table cell, because a
## card has no cells. Ten filled blocks is the whole clause done.
func _progress_strip(ratio: float) -> String:
	var filled: int = int(round(clampf(ratio, 0.0, 1.0) * float(PROGRESS_DOTS)))
	return "█".repeat(filled) + "·".repeat(PROGRESS_DOTS - filled)


func _progress_rows(contract: Dictionary, progress: Dictionary) -> Array:
	var total: float = float(contract.get("total_burn", 0.0))
	var burned: float = float(progress.get("tokens_burned", 0.0))
	var quality_min: float = float(contract.get("quality_min", 0.0))
	var quality_now: float = float(progress.get("quality_average", 0.0))
	var rounds_left: int = int(progress.get("rounds_remaining", 0))
	var deadline: int = int(progress.get("deadline_round", 12))
	var rows: Array = [
		{
			"label": "Tokens burned",
			"value": "%s of %s" % [
				NumberFormat.format(burned), NumberFormat.format(total),
			],
			"met": burned >= total,
			"ratio": burned / total if total > 0.0 else 1.0,
		},
		{
			"label": "Rounds left",
			"value": "%d of %d" % [rounds_left, deadline],
			"met": rounds_left > 3,
			"ratio": float(rounds_left) / float(deadline) if deadline > 0 else 0.0,
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
			"ratio": quality_now / quality_min,
		})
	rows.append({
		"label": "Pays out",
		"value": "%d unlock pick(s)" % int(contract.get("picks", 1)),
		"met": true,
		"ratio": 1.0,
	})
	return rows


## Names the contract and where the run stands against it. The deadline is stated
## every time: the year running out is the loss condition, and a player who only
## reads this screen once should still leave knowing that.
func _subtitle_text(summary: Dictionary) -> String:
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


## What finishing and missing the contract each mean, in one sentence, because this
## is the only deadline in the game that ends the run on its own.
func _refresh_stakes(contract: Dictionary) -> void:
	if contract.is_empty():
		_stakes.text = "Nothing is riding on this location beyond the rent."
		return
	var next_location: String = MetaProgress.next_location_after(
		str(contract.get("location", ""))
	)
	var won: String = (
		"Completing it wins the run and unlocks %s to start the next one in."
			% MetaProgress.location_name(next_location)
		if next_location != ""
		else "Completing it wins the run; this is the last location there is."
	)
	_stakes.text = "%s The year ending without it ends the run there and then, as does missing the rent twice." % won


func _refresh_notice(
	summary: Dictionary, contract: Dictionary, progress: Dictionary
) -> void:
	if contract.is_empty():
		_notice.text = MetaProgress.location_name(
			str(summary.get("location", ""))
		).to_upper()
		return
	_notice.text = "%.0f%% BURNED\n%d ROUND(S) LEFT" % [
		float(progress.get("burn_ratio", 0.0)) * 100.0,
		int(progress.get("rounds_remaining", 0)),
	]


# --- Layout ------------------------------------------------------------------

func _on_venue_layout() -> void:
	var scale: float = console_scale()
	if _board != null:
		_board.set_console(console_mode())
		_board.set_metrics(scale, content_width("board"))
	var font_tiny: int = ConsoleMetrics.font_tiny(scale)
	for label in [_kicker, _stakes, _notice]:
		if label != null:
			label.add_theme_font_size_override("font_size", font_tiny)
	var font_small: int = ConsoleMetrics.font_small(scale)
	if _subtitle != null:
		_subtitle.add_theme_font_size_override("font_size", font_small)
	for line in _index_lines.get_children():
		_apply_line_font(line, font_small)


func _apply_line_font(line: Node, font_size: int) -> void:
	if line is Label:
		line.add_theme_font_size_override("font_size", font_size)
		return
	for child in line.get_children():
		_apply_line_font(child, font_size)
