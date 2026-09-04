class_name MaintenanceRecordsSheet
extends ConsoleOverlay

## The records, on a CRT sheet over the maintenance view: the career figures
## and completion the old Legacy venue printed, then the trophy cabinet — every
## award, earned or not, with what it hands over. Read-only: the same
## MetaProgress calls `venue_legacy` and `venue_achievements` make, on one
## scrolling sheet, with nothing to press but the award rows (which print the
## award's detail under the list).

const REDACTED_NAME := "[ REDACTED ]"
const REDACTED_HINT := "A secret award. Whatever it is, it is not something you can plan for."

var _scroll: ScrollContainer = null
var _column: VBoxContainer = null
var _records: VBoxContainer = null
var _completion: VBoxContainer = null
var _awards: VBoxContainer = null
var _award_rows: Dictionary = {}
var _detail: VBoxContainer = null
var _selected: String = ""
var _headings: Array[Label] = []


func _ready() -> void:
	super._ready()
	name = "MaintenanceRecords"
	setup("records")
	var body: VBoxContainer = content()
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 6)
	_scroll.add_child(_column)

	_column.add_child(_heading("THE LEGACY"))
	_records = VBoxContainer.new()
	_records.add_theme_constant_override("separation", 1)
	_column.add_child(_records)
	_column.add_child(_heading("COMPLETION"))
	_completion = VBoxContainer.new()
	_completion.add_theme_constant_override("separation", 1)
	_column.add_child(_completion)
	_column.add_child(_heading("THE TROPHY CABINET"))
	_awards = VBoxContainer.new()
	_awards.add_theme_constant_override("separation", 0)
	_column.add_child(_awards)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 1)
	_detail.visible = false
	_column.add_child(_detail)
	set_close_label("BACK TO MAINTENANCE")


func _heading(text: String) -> Label:
	var label: Label = ConsoleStyle.label(text, ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_headings.append(label)
	return label


func refresh() -> void:
	var font: int = ConsoleMetrics.font_small(console_scale())
	_fill(_records, _record_rows(), font)
	_fill(_completion, _completion_rows(), font)
	_refresh_awards(font)
	_refresh_detail(font)
	var summary: Dictionary = MetaProgress.completion_summary()
	set_context("RECORDS · %.0f%% CAREER COMPLETE · %d / %d AWARDS" % [
		float(summary.get("percent", 0.0)), MetaProgress.achievement_count(), ContentDatabase.achievements.size(),
	])


func _fill(host: VBoxContainer, rows: Array, font: int) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()
	for row in rows:
		var line: Control = ConsoleStyle.detail_line(row, font)
		if line != null:
			host.add_child(line)


## The career figures, as the Legacy venue printed them.
func _record_rows() -> Array:
	var best: Dictionary = MetaProgress.best_scores()
	var rows: Array = [
		{"stat": "Best burned", "value": NumberFormat.format_tokens(float(best.get("total_tokens_burned", 0.0)))},
		{"stat": "Best prompt", "value": NumberFormat.format_tokens(float(best.get("peak_prompt_tokens", 0.0)))},
		{"stat": "Best throughput", "value": NumberFormat.format_token_rate(float(best.get("peak_token_rate", 0.0)))},
		{"stat": "Ascensions", "value": str(_total_ascensions())},
		{"stat": "Pending picks", "value": str(MetaProgress.pending_picks())},
		{"stat": "Won on normal", "value": str(MetaProgress.victories_on("normal"))},
		{"stat": "Won on hard", "value": str(MetaProgress.victories_on("hard"))},
	]
	if MetaProgress.retirements() > 0:
		rows.append({"stat": "Retired (legacy)", "value": str(MetaProgress.retirements())})
	var age: Dictionary = Ages.get_age(MetaProgress.age())
	rows.append({"stat": "Age", "value": str(age.get("name", "Bedroom Age")).to_upper()})
	return rows


func _total_ascensions() -> int:
	var total: int = 0
	for contract in ContentDatabase.ascension_contracts:
		total += MetaProgress.ascension_completions(str(contract.get("id", "")))
	return total


func _completion_rows() -> Array:
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
	return rows


func _fraction(source: Dictionary, have: String, total: String) -> String:
	return "%d / %d" % [int(source.get(have, 0)), int(source.get(total, 0))]


## Every award as a console row: earned rows lit, locked rows dim, hidden and
## unearned rows redacted. Pressing one prints its detail under the list.
func _refresh_awards(font: int) -> void:
	for child in _awards.get_children():
		_awards.remove_child(child)
		child.queue_free()
	_award_rows.clear()
	var scale: float = console_scale()
	var height: int = ConsoleMetrics.row_height(scale)
	var pad: int = ConsoleMetrics.pad_h(scale)
	var index: int = 0
	for raw in ContentDatabase.achievements:
		if not raw is Dictionary:
			continue
		var achievement: Dictionary = raw
		var id: String = str(achievement.get("id", ""))
		var earned: bool = MetaProgress.has_achievement(id)
		var redacted: bool = bool(achievement.get("hidden", false)) and not earned
		index += 1
		var row := ConsoleMenuRow.new()
		row.name = "Award%s" % id.to_pascal_case()
		row.index_label = str(index)
		row.headline = REDACTED_NAME if redacted else str(achievement.get("name", id)).to_upper()
		row.value_text = "EARNED" if earned else ("LOCKED" if not redacted else "SECRET")
		row.modulate.a = 1.0 if earned else 0.6
		row.pressed.connect(_on_award.bind(id))
		row.set_metrics(font, height, pad)
		_awards.add_child(row)
		_award_rows[id] = row
	for id in _award_rows:
		(_award_rows[id] as ConsoleMenuRow).set_selected(id == _selected)


func award_count() -> int:
	return _award_rows.size()


func selected_award() -> String:
	return _selected


func select_award(id: String) -> bool:
	if not _award_rows.has(id):
		return false
	_on_award(id)
	return true


func _on_award(id: String) -> void:
	_selected = "" if _selected == id else id
	UiSound.play("tap")
	for other in _award_rows:
		(_award_rows[other] as ConsoleMenuRow).set_selected(other == _selected)
	_refresh_detail(ConsoleMetrics.font_small(console_scale()))


func _refresh_detail(font: int) -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	var achievement: Dictionary = ContentDatabase.get_achievement(_selected) if _selected != "" else {}
	_detail.visible = not achievement.is_empty()
	if achievement.is_empty():
		return
	var id: String = str(achievement.get("id", ""))
	var earned: bool = MetaProgress.has_achievement(id)
	var redacted: bool = bool(achievement.get("hidden", false)) and not earned
	var lines: Array = [{"text": ""}]
	if redacted:
		lines.append({"rule": REDACTED_NAME, "text": REDACTED_HINT})
	else:
		lines.append({"rule": str(achievement.get("name", id)).to_upper(), "text": str(achievement.get("description", ""))})
		lines.append({"stat": "How", "value": str(achievement.get("hint", ""))})
		lines.append_array(_reward_lines(achievement))
	lines.append({"stat": "Status", "value": "EARNED" if earned else "NOT YET EARNED", "color": ConsoleStyle.PHOSPHOR if earned else ConsoleStyle.PHOSPHOR_DIM})
	for line in lines:
		var control: Control = ConsoleStyle.detail_line(line, font)
		if control != null:
			_detail.add_child(control)


func _reward_lines(achievement: Dictionary) -> Array:
	var reward: Dictionary = Dictionary(achievement.get("reward", {}))
	var evaluator := ExpressionEvaluator.new()
	match str(reward.get("type", "none")):
		"unlock_module":
			var module: ModuleDefinition = ContentDatabase.get_module(str(reward.get("module_id", "")))
			if module == null:
				return []
			return [
				{"stat": "Hands over", "value": module.name},
				{"text": "%s Can appear in the Market in every run once this award is earned." % evaluator.render_template(module.description_template, module.parameters)},
			]
		"unlock_perk":
			var perk: PerkDefinition = ContentDatabase.get_perk(str(reward.get("perk_id", "")))
			if perk == null:
				return []
			return [
				{"stat": "Hands over", "value": perk.name},
				{"text": "%s Joins His Table in every run once this award is earned." % evaluator.render_template(perk.description_template, perk.parameters)},
			]
		_:
			return []


func _fit_console() -> void:
	super._fit_console()
	var tiny: int = ConsoleMetrics.font_tiny(console_scale())
	for heading in _headings:
		heading.add_theme_font_size_override("font_size", tiny)
