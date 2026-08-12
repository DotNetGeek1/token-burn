extends ConsoleOverlay

## The meta hub: what the game remembers about the player across every run.
## Read-only — unlocks are spent on the run-end debrief, not here — but this
## is the one place that shows the whole arc at once: age reached, best
## scores, contracts conquered, and the full unlock gallery.
##
## Nothing here can be pressed, so it prints as a record sheet: the bests as
## key/value lines, the contracts and the unlocks as listings underneath.

var _age_flavour: Label = null
var _records_caption: Label = null
var _records: VBoxContainer = null
var _contracts_caption: Label = null
var _contracts: ConsoleTable = null
var _unlocks_caption: Label = null
var _unlocks: ConsoleTable = null


func _ready() -> void:
	super._ready()
	setup("The Legacy")
	_build_body()


func _build_body() -> void:
	var body: VBoxContainer = content()

	_age_flavour = ConsoleStyle.paragraph("", ConsoleStyle.FONT_TINY)
	body.add_child(_age_flavour)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)

	_records_caption = ConsoleStyle.label(
		"RECORDS", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	column.add_child(_records_caption)

	_records = VBoxContainer.new()
	_records.add_theme_constant_override("separation", 2)
	_records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_records)

	_contracts_caption = ConsoleStyle.label(
		"ASCENSION CONTRACTS", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	column.add_child(_contracts_caption)

	_contracts = ConsoleTable.new()
	_contracts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_contracts)
	_contracts.set_columns([
		{"label": "contract", "weight": 2.0},
		{"label": "status", "weight": 1.4, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	])

	_unlocks_caption = ConsoleStyle.label(
		"PERMANENT UNLOCKS", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	column.add_child(_unlocks_caption)

	_unlocks = ConsoleTable.new()
	_unlocks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_unlocks)
	_unlocks.set_columns([
		{"label": "unlock", "weight": 2.0},
		{"label": "kind", "weight": 1.2},
		{"label": "owned", "weight": 0.8, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	])


func refresh() -> void:
	_refresh_age()
	_refresh_records()
	_refresh_contracts()
	_refresh_unlocks()
	_apply_body_metrics()


func fit_console() -> void:
	super.fit_console()
	_apply_body_metrics()


## The body's own widgets are not part of the shell, so they are re-scaled
## alongside it whenever the room is laid out.
func _apply_body_metrics() -> void:
	var scale: float = console_scale()
	var font_tiny: int = ConsoleMetrics.font_tiny(scale)
	for label in [_age_flavour, _records_caption, _contracts_caption, _unlocks_caption]:
		if label != null:
			label.add_theme_font_size_override("font_size", font_tiny)
	if _contracts != null:
		_contracts.set_metrics(scale)
	if _unlocks != null:
		_unlocks.set_metrics(scale)
	_apply_record_fonts()


func _apply_record_fonts() -> void:
	if _records == null:
		return
	var font_small: int = ConsoleMetrics.font_small(console_scale())
	for row in _records.get_children():
		for cell in row.get_children():
			if cell is Label:
				cell.add_theme_font_size_override("font_size", font_small)


func _refresh_age() -> void:
	var age_data: Dictionary = Ages.get_age(MetaProgress.age())
	set_context("AGE · %s" % str(age_data.get("name", "Bedroom Age")).to_upper())
	_age_flavour.text = str(age_data.get("flavour", ""))


func _refresh_records() -> void:
	for child in _records.get_children():
		_records.remove_child(child)
		child.queue_free()
	var best: Dictionary = MetaProgress.best_scores()
	var rows: Array = [
		{"stat": "Best total tokens burned", "value": NumberFormat.format_tokens(float(best.get("total_tokens_burned", 0.0)))},
		{"stat": "Best peak prompt burn", "value": NumberFormat.format_tokens(float(best.get("peak_prompt_tokens", 0.0)))},
		{"stat": "Best sustained throughput", "value": NumberFormat.format_token_rate(float(best.get("peak_token_rate", 0.0)))},
		{"stat": "Ascensions completed", "value": str(_total_ascensions())},
		{"stat": "Pending picks", "value": str(MetaProgress.pending_picks())},
	]
	# Retirement was the old calendar ending. Nothing earns it any more, so the
	# row only appears for profiles that still carry some.
	if MetaProgress.retirements() > 0:
		rows.insert(4, {"stat": "Runs retired (legacy)", "value": str(MetaProgress.retirements())})
	var font_small: int = ConsoleMetrics.font_small(console_scale())
	var separation: int = ConsoleMetrics.px(8, console_scale())
	for row in rows:
		var line: Control = ConsoleStyle.detail_line(row, font_small, separation)
		if line != null:
			_records.add_child(line)


func _total_ascensions() -> int:
	var total: int = 0
	for contract in ContentDatabase.ascension_contracts:
		total += MetaProgress.ascension_completions(str(contract.get("id", "")))
	return total


func _refresh_contracts() -> void:
	_contracts.clear()
	var contracts: Array = ContentDatabase.ascension_contracts
	_contracts_caption.visible = not contracts.is_empty()
	_contracts.visible = not contracts.is_empty()
	for contract in contracts:
		var contract_id: String = str(contract.get("id", ""))
		var completions: int = MetaProgress.ascension_completions(contract_id)
		var lit: Color = ConsoleStyle.PHOSPHOR if completions > 0 else ConsoleStyle.PHOSPHOR_DIM
		_contracts.add_row([
			{"text": str(contract.get("name", contract_id)).to_upper(), "color": lit},
			{
				"text": "COMPLETED ×%d" % completions if completions > 0 else "NOT YET CONQUERED",
				"color": lit,
			},
		], contract_id, lit)


func _refresh_unlocks() -> void:
	_unlocks.clear()
	var catalog: Array = MetaProgress.catalog()
	_unlocks_caption.visible = not catalog.is_empty()
	_unlocks.visible = not catalog.is_empty()
	for unlock in catalog:
		var unlock_id: String = str(unlock.get("id", ""))
		var owned: int = MetaProgress.unlock_count(unlock_id)
		var lit: Color = ConsoleStyle.PHOSPHOR if owned > 0 else ConsoleStyle.PHOSPHOR_DIM
		_unlocks.add_row([
			{"text": str(unlock.get("name", unlock_id)).to_upper(), "color": lit},
			{"text": str(unlock.get("kind", "")).to_upper(), "color": ConsoleStyle.PHOSPHOR_DIM},
			{"text": "×%d" % owned if owned > 0 else "LOCKED", "color": lit},
		], unlock_id, lit)
