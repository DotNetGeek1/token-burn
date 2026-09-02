extends VenueScene

## The Legacy: the archive of what the game remembers across every run.
##
## Read-only — unlocks are spent on the run-end debrief, not here — so nothing in
## this room is a decision. What it owes the player is scale: the age reached, the
## bests, the contracts conquered and the whole unlock gallery, all legible at once
## instead of stacked in a 442-pixel column.
##
## The records go up the left because they are figures rather than things. The
## board is the gallery: permanent unlocks, every module in the angel pool with
## its lock reason when gated, and which ascension contracts have been beaten.

const UNLOCKS := "unlocks"
const CONTRACTS := "contracts"
const MODULES := "modules"

var _kicker: Label = null
var _records: VBoxContainer = null
var _counters: VBoxContainer = null
var _counter_rows: Dictionary = {}
var _board_panel: VenuePanel = null
var _board: VenueBoard = null
var _signage_panel: VenuePanel = null
var _completion: VBoxContainer = null
var _notice: Label = null
var _shelf: String = UNLOCKS


func venue_key() -> String:
	return "legacy"


func _build_venue() -> void:
	_build_index()
	_build_board()
	_build_signage()
	_build_notice()
	EventBus.run_started.connect(refresh)


func _build_index() -> void:
	var panel: VenuePanel = add_panel("index", "The Legacy", {
		"console_order": 10, "console_min": 210.0,
	})
	var content: VBoxContainer = panel.content()

	_kicker = ConsoleStyle.label(
		"RECORDS", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	content.add_child(_kicker)

	_records = VBoxContainer.new()
	_records.add_theme_constant_override("separation", 2)
	content.add_child(_records)

	content.add_child(ConsoleStyle.rule(0.22))

	_counters = VBoxContainer.new()
	_counters.add_theme_constant_override("separation", 0)
	_counters.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_counters)


func _build_board() -> void:
	_board_panel = add_panel("board", "Permanent unlocks", {
		"console_order": 20, "console_min": 220.0, "grow": true,
	})
	_board = VenueBoard.new()
	_board_panel.content().add_child(_board)


## The right-hand panel: how much of the whole game has been seen. It is the one
## figure in this room that is about the player rather than about a run, so it
## stands apart from the records.
func _build_signage() -> void:
	_signage_panel = add_panel("signage", "Career", {
		"console_order": 30, "console_min": 120.0,
	})
	_completion = VBoxContainer.new()
	_completion.add_theme_constant_override("separation", 2)
	_completion.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_signage_panel.content().add_child(_completion)


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
	_refresh_records()
	_refresh_counters()
	_refresh_board()
	_refresh_completion()
	_refresh_notice()


func _refresh_records() -> void:
	for child in _records.get_children():
		_records.remove_child(child)
		child.queue_free()
	var best: Dictionary = MetaProgress.best_scores()
	var rows: Array = [
		{
			"stat": "Best burned",
			"value": NumberFormat.format_tokens(
				float(best.get("total_tokens_burned", 0.0))
			),
		},
		{
			"stat": "Best prompt",
			"value": NumberFormat.format_tokens(
				float(best.get("peak_prompt_tokens", 0.0))
			),
		},
		{
			"stat": "Best throughput",
			"value": NumberFormat.format_token_rate(
				float(best.get("peak_token_rate", 0.0))
			),
		},
		{"stat": "Ascensions", "value": str(_total_ascensions())},
		{"stat": "Pending picks", "value": str(MetaProgress.pending_picks())},
		{"stat": "Won on normal", "value": str(MetaProgress.victories_on("normal"))},
		{"stat": "Won on hard", "value": str(MetaProgress.victories_on("hard"))},
	]
	# Retirement was the old calendar ending. Nothing earns it any more, so the
	# line only appears for profiles that still carry some.
	if MetaProgress.retirements() > 0:
		rows.append({
			"stat": "Retired (legacy)", "value": str(MetaProgress.retirements()),
		})
	var font: int = ConsoleMetrics.font_small(console_scale())
	for row in rows:
		var line: Control = ConsoleStyle.detail_line(row, font)
		if line != null:
			_records.add_child(line)


func _total_ascensions() -> int:
	var total: int = 0
	for contract in ContentDatabase.ascension_contracts:
		total += MetaProgress.ascension_completions(str(contract.get("id", "")))
	return total


func _refresh_counters() -> void:
	var wanted: Array[String] = [UNLOCKS, MODULES]
	if not ContentDatabase.ascension_contracts.is_empty():
		wanted.append(CONTRACTS)
	if wanted != _counter_order():
		for child in _counters.get_children():
			_counters.remove_child(child)
			child.queue_free()
		_counter_rows.clear()
		var index: int = 1
		for key in wanted:
			var row := ConsoleMenuRow.new()
			row.index_label = str(index)
			row.headline = _counter_label(key)
			row.pressed.connect(_on_counter_pressed.bind(key))
			_counters.add_child(row)
			_counter_rows[key] = row
			index += 1
	if not (_shelf in wanted):
		_shelf = UNLOCKS
	for key in _counter_rows:
		var row: ConsoleMenuRow = _counter_rows[key]
		row.value_text = "%d" % _shelf_size(str(key))
		row.set_selected(str(key) == _shelf)
	_layout_rows()


func _counter_order() -> Array[String]:
	var keys: Array[String] = []
	for child in _counters.get_children():
		for key in _counter_rows:
			if _counter_rows[key] == child:
				keys.append(str(key))
	return keys


## Short enough to survive the archive's narrow index panel alongside a count.
func _counter_label(key: String) -> String:
	match key:
		CONTRACTS:
			return "CONTRACTS"
		MODULES:
			return "MODULES"
		_:
			return "UNLOCKS"


## The full name, for the heading over the board where there is room for it.
func _shelf_heading(key: String) -> String:
	match key:
		CONTRACTS:
			return "Ascension contracts"
		MODULES:
			return "Modules"
		_:
			return "Permanent unlocks"


func _shelf_size(key: String) -> int:
	match key:
		CONTRACTS:
			return ContentDatabase.ascension_contracts.size()
		MODULES:
			return ContentDatabase.modules.size()
		_:
			return MetaProgress.catalog().size()


func _on_counter_pressed(key: String) -> void:
	if _shelf == key:
		return
	_shelf = key
	refresh()
	lean_on("board")


func _refresh_board() -> void:
	_board_panel.set_heading(_shelf_heading(_shelf))
	var entries: Array = []
	match _shelf:
		CONTRACTS:
			for contract in ContentDatabase.ascension_contracts:
				entries.append(_contract_entry(Dictionary(contract)))
		MODULES:
			for module in ContentDatabase.modules:
				entries.append(_module_entry(module))
		_:
			for unlock in MetaProgress.catalog():
				entries.append(_unlock_entry(Dictionary(unlock)))
	var note: String = ""
	if entries.is_empty():
		note = "NOTHING RECORDED YET — FINISH A RUN AND THIS FILLS UP"
	_board.set_entries(entries, note)


## Nothing in this room is selectable, so the cards carry no meta: the archive is
## read, not operated.
func _unlock_entry(unlock: Dictionary) -> Dictionary:
	var unlock_id: String = str(unlock.get("id", ""))
	var owned: int = MetaProgress.unlock_count(unlock_id)
	var ranks: Array = Array(unlock.get("ranks", []))
	var figure: String = "—"
	if owned > 0:
		figure = "×%d" % owned if ranks.is_empty() else "%d / %d" % [owned, ranks.size()]
	return {
		"meta": null,
		"name": str(unlock.get("name", unlock_id)),
		"figure": figure,
		"figure_color": ConsoleStyle.PHOSPHOR if owned > 0 else ConsoleStyle.PHOSPHOR_DIM,
		"unit": "ranks" if not ranks.is_empty() else "owned",
		"spec": str(unlock.get("description", "")),
		"price": str(unlock.get("kind", "")).replace("_", " ").to_upper(),
		"price_color": ConsoleStyle.PHOSPHOR_DIM,
		"status": "OWNED" if owned > 0 else "LOCKED",
		"status_color": ConsoleStyle.PHOSPHOR if owned > 0 else ConsoleStyle.PHOSPHOR_DIM,
	}


func _contract_entry(contract: Dictionary) -> Dictionary:
	var contract_id: String = str(contract.get("id", ""))
	var completions: int = MetaProgress.ascension_completions(contract_id)
	return {
		"meta": null,
		"name": str(contract.get("name", contract_id)),
		"figure": "×%d" % completions if completions > 0 else "—",
		"figure_color": (
			ConsoleStyle.PHOSPHOR if completions > 0 else ConsoleStyle.PHOSPHOR_DIM
		),
		"unit": "completed",
		"spec": str(contract.get("description", "")),
		"status": "CONQUERED" if completions > 0 else "NOT YET CONQUERED",
		"status_color": (
			ConsoleStyle.PHOSPHOR if completions > 0 else ConsoleStyle.PHOSPHOR_DIM
		),
	}


func _module_entry(module: ModuleDefinition) -> Dictionary:
	var unlocked: bool = ContentDatabase.module_is_unlocked(module)
	var reasons: PackedStringArray = ContentDatabase.module_lock_reasons(module)
	var rarity: String = str(module.rarity).to_upper()
	var evaluator := ExpressionEvaluator.new()
	var spec: String = evaluator.render_template(module.description_template, module.parameters)
	if not unlocked and not reasons.is_empty():
		spec = " · ".join(reasons)
	return {
		"meta": null,
		"name": module.name,
		"figure": rarity if rarity != "" else "—",
		"figure_color": ConsoleStyle.PHOSPHOR if unlocked else ConsoleStyle.PHOSPHOR_DIM,
		"unit": "rarity",
		"spec": spec,
		"price": str(module.category).replace("_", " ").to_upper(),
		"price_color": ConsoleStyle.PHOSPHOR_DIM,
		"status": "IN POOL" if unlocked else "LOCKED",
		"status_color": ConsoleStyle.PHOSPHOR if unlocked else ConsoleStyle.PHOSPHOR_DIM,
	}


func _refresh_completion() -> void:
	for child in _completion.get_children():
		_completion.remove_child(child)
		child.queue_free()
	var summary: Dictionary = MetaProgress.completion_summary()
	var achievements: Dictionary = Dictionary(summary.get("achievements", {}))
	var perks: Dictionary = Dictionary(summary.get("perks", {}))
	var modules: Dictionary = Dictionary(summary.get("modules", {}))
	var legacy: Dictionary = Dictionary(summary.get("legacy", {}))
	var rows: Array = [
		{"stat": "Overall", "value": "%.0f%%" % float(summary.get("percent", 0.0))},
		{"stat": "Awards", "value": _fraction(achievements, "earned", "total")},
		{"stat": "Perks", "value": _fraction(perks, "unlocked", "total")},
		{"stat": "Modules", "value": _fraction(modules, "unlocked", "total")},
		{"stat": "Legacy ranks", "value": _fraction(legacy, "ranks_owned", "total_ranks")},
	]
	if bool(summary.get("overall_complete", false)):
		rows.append({"stat": "Status", "value": "COMPLETE"})
	# Stacked rather than laid out as stat-and-value rows: the picture painted a
	# tall narrow board here, and a label with a figure beside it clips its own
	# figure off the edge at this width.
	for row in rows:
		var caption: Label = ConsoleStyle.label(
			str(row["stat"]).to_upper(), ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
		)
		# Marked so the layout pass can tell the two sizes apart on the way back.
		caption.set_meta("caption", true)
		_completion.add_child(caption)
		var value: Label = ConsoleStyle.label(
			str(row["value"]), ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR
		)
		_completion.add_child(value)


func _fraction(source: Dictionary, have: String, total: String) -> String:
	return "%d / %d" % [int(source.get(have, 0)), int(source.get(total, 0))]


## The age the career has reached, and what that age is like to live in.
func _refresh_notice() -> void:
	var age: Dictionary = Ages.get_age(MetaProgress.age())
	_notice.text = "AGE\n%s" % str(age.get("name", "Bedroom Age")).to_upper()
	_notice.tooltip_text = str(age.get("flavour", ""))


# --- Layout ------------------------------------------------------------------

func _on_venue_layout() -> void:
	var scale: float = console_scale()
	if _board != null:
		_board.set_console(console_mode())
		_board.set_metrics(scale, content_width("board"))
	_layout_rows()
	var font_tiny: int = ConsoleMetrics.font_tiny(scale)
	for label in [_kicker, _notice]:
		if label != null:
			label.add_theme_font_size_override("font_size", font_tiny)
	var font: int = ConsoleMetrics.font_small(scale)
	for line in _records.get_children():
		_apply_line_font(line, font)
	for line in _completion.get_children():
		_apply_line_font(line, font_tiny if line.has_meta("caption") else font)


func _apply_line_font(line: Node, font_size: int) -> void:
	if line is Label:
		line.add_theme_font_size_override("font_size", font_size)
		return
	for child in line.get_children():
		_apply_line_font(child, font_size)


func _layout_rows() -> void:
	var scale: float = console_scale()
	var font: int = ConsoleMetrics.font_small(scale)
	var height: int = ConsoleMetrics.row_height(scale)
	var pad: int = ConsoleMetrics.pad_h(scale)
	for key in _counter_rows:
		(_counter_rows[key] as ConsoleMenuRow).set_metrics(font, height, pad)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if SceneRouter.investor_busy():
		return
	var slot: int = event.keycode - KEY_1
	var order: Array[String] = _counter_order()
	if slot < 0 or slot >= order.size():
		return
	_on_counter_pressed(order[slot])
	get_viewport().set_input_as_handled()
