extends ConsoleOverlay

## The contract this location is being played for, and how far through it the run
## is. There is nothing to decide here: the investor set the terms before the
## first prompt and the run is measured against them from round one. This is the
## sheet the player opens to re-read what he asked for.
##
## Completing it wins the run and opens the next location. Reaching the end of
## the year without it ends the run. Both halves are said plainly, because a
## player who does not know the deadline cannot play against it.
##
## The terms are printed as a listing rather than as a stack of cards: every line
## is the same shape — a clause, how far along it is, where the run stands — and
## a column of them is how the machine would report a contract it is measuring.

## How many cells the progress strip is drawn with. Ten reads as a percentage
## without asking anyone to count dots.
const PROGRESS_DOTS := 10

var _subtitle: Label = null
var _terms_caption: Label = null
var _terms: ConsoleTable = null
var _stakes: ConsoleDetail = null


func _ready() -> void:
	super._ready()
	setup("Terms")
	set_close_label("BACK TO WORK")
	_build_body()


func _build_body() -> void:
	var body: VBoxContainer = content()

	_subtitle = ConsoleStyle.paragraph("", ConsoleStyle.FONT_SMALL)
	body.add_child(_subtitle)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)

	_terms_caption = ConsoleStyle.label(
		"TERMS", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	column.add_child(_terms_caption)

	_terms = ConsoleTable.new()
	_terms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_terms)
	_terms.set_columns([
		{"label": "clause", "weight": 1.4},
		{"label": "progress", "weight": 1.2},
		{"label": "standing", "weight": 1.8, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	])

	_stakes = ConsoleDetail.new()
	_stakes.size_flags_vertical = Control.SIZE_SHRINK_END
	body.add_child(_stakes)
	_stakes.clear("STAKES")


func refresh() -> void:
	var summary: Dictionary = Simulation.ascension_summary()
	var contract: Dictionary = Dictionary(summary.get("contract", {}))
	var progress: Dictionary = Dictionary(summary.get("progress", {}))
	_subtitle.text = _subtitle_text(summary)
	set_context(_context_text(summary))
	_terms.clear()
	if contract.is_empty():
		_terms.add_note(
			"NO CONTRACT FOR THIS LOCATION — ORDINARY WORK IS ALL THERE IS HERE"
		)
		_stakes.clear("STAKES")
	else:
		for row in _progress_rows(contract, progress):
			var met: bool = bool(row["met"])
			var accent: Color = ConsoleStyle.PHOSPHOR if met else ConsoleStyle.WARNING
			_terms.add_row([
				str(row["label"]).to_upper(),
				{
					"dots": _dot_count(float(row["ratio"])),
					"max": PROGRESS_DOTS,
					"color": accent,
				},
				{"text": str(row["value"]), "color": accent},
			], null, accent)
		_stakes.show_detail("STAKES", [{"text": _stakes_text(contract)}])
	_apply_body_metrics()


func fit_console() -> void:
	super.fit_console()
	_apply_body_metrics()


## The body's own widgets are not part of the shell, so they are re-scaled
## alongside it whenever the room is laid out.
func _apply_body_metrics() -> void:
	var scale: float = console_scale()
	if _subtitle != null:
		_subtitle.add_theme_font_size_override("font_size", ConsoleMetrics.font_small(scale))
	if _terms_caption != null:
		_terms_caption.add_theme_font_size_override("font_size", ConsoleMetrics.font_tiny(scale))
	if _terms != null:
		_terms.set_metrics(scale)
	if _stakes != null:
		_stakes.set_metrics(scale)


func _dot_count(ratio: float) -> int:
	return int(round(clampf(ratio, 0.0, 1.0) * float(PROGRESS_DOTS)))


## Where the run stands, in the header where the machine reports its state.
func _context_text(summary: Dictionary) -> String:
	var location: String = MetaProgress.location_name(str(summary.get("location", "")))
	var contract: Dictionary = Dictionary(summary.get("contract", {}))
	if contract.is_empty():
		return location.to_upper()
	var progress: Dictionary = Dictionary(summary.get("progress", {}))
	return "%s · %d ROUNDS LEFT" % [
		location.to_upper(), int(progress.get("rounds_remaining", 0))
	]


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
			"value": "%s of %s" % [NumberFormat.format(burned), NumberFormat.format(total)],
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
