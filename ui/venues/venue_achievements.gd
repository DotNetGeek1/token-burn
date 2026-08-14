extends VenueScene

## The Trophy Cabinet: every award, whether it has been earned, and what earning
## it hands over.
##
## Read-only. Awards are not bought, and half of them are for things no sensible
## player would attempt on purpose, so the room's job is to make the shape of the
## collection legible: what is already yours, what is still out there, and which
## modules are waiting behind which disaster.
##
## A locked secret gives nothing away. It is a gap in the shelf rather than a line
## on a to-do list, which is why its name and its flavour are withheld.

const CATEGORY_ORDER := ["milestone", "disaster", "secret"]
const SHELVES := [
	{"id": "all", "label": "EVERYTHING"},
	{"id": "milestone", "label": "MILESTONES"},
	{"id": "disaster", "label": "DISASTERS"},
	{"id": "secret", "label": "CLASSIFIED"},
]
const REDACTED_NAME := "? ? ?"
const REDACTED_HINT := "Classified. You will know when it happens."

var _kicker: Label = null
var _index_lines: VBoxContainer = null
var _counters: VBoxContainer = null
var _counter_rows: Dictionary = {}
var _board_panel: VenuePanel = null
var _board: VenueBoard = null
var _signage_panel: VenuePanel = null
var _sign: VBoxContainer = null
var _detail: ConsoleDetail = null
var _notice: Label = null
var _shelf: String = "all"
var _selected: String = ""


func venue_key() -> String:
	return "achievements"


func _hint_entries() -> Array:
	return [{"index": "ENTER", "headline": "READ"}]


func _build_venue() -> void:
	_build_index()
	_build_board()
	_build_signage()
	_build_notice()
	EventBus.achievement_unlocked.connect(func(_id: String) -> void: refresh())


func _build_index() -> void:
	var panel: VenuePanel = add_panel("index", "Trophy Cabinet", {
		"console_order": 10, "console_min": 190.0,
	})
	var content: VBoxContainer = panel.content()

	_kicker = ConsoleStyle.label(
		"AWARDS ARE PERMANENT", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	content.add_child(_kicker)

	_index_lines = VBoxContainer.new()
	_index_lines.add_theme_constant_override("separation", 2)
	content.add_child(_index_lines)

	content.add_child(ConsoleStyle.rule(0.22))

	_counters = VBoxContainer.new()
	_counters.add_theme_constant_override("separation", 0)
	_counters.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_counters)


func _build_board() -> void:
	_board_panel = add_panel("board", "Everything", {
		"console_order": 20, "console_min": 240.0, "grow": true,
	})
	_board = VenueBoard.new()
	_board.tile_selected.connect(_on_tile_selected)
	_board_panel.content().add_child(_board)


func _build_signage() -> void:
	_signage_panel = add_panel("signage", "", {
		"console_order": 30, "console_min": 0.0,
	})
	var content: VBoxContainer = _signage_panel.content()

	_sign = VBoxContainer.new()
	_sign.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sign.add_theme_constant_override("separation", 8)
	content.add_child(_sign)
	for line in ["SOME OF THESE", "ARE NOT PRAISE"]:
		var label: Label = ConsoleStyle.label(
			line, ConsoleStyle.FONT_BODY, ConsoleStyle.PHOSPHOR_DIM
		)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_sign.add_child(label)

	_detail = ConsoleDetail.new()
	_detail.visible = false
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.closed.connect(_on_detail_closed)
	content.add_child(_detail)


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
	_refresh_index()
	_refresh_counters()
	_refresh_board()
	_refresh_notice()
	_refresh_detail()


func _refresh_index() -> void:
	for child in _index_lines.get_children():
		_index_lines.remove_child(child)
		child.queue_free()
	var font: int = ConsoleMetrics.font_small(console_scale())
	for category in CATEGORY_ORDER:
		var entries: Array = _entries_in(category)
		if entries.is_empty():
			continue
		var line: Control = ConsoleStyle.detail_line({
			"stat": _shelf_label(category).capitalize(),
			"value": "%d / %d" % [_earned_in(entries), entries.size()],
		}, font)
		if line != null:
			_index_lines.add_child(line)


func _refresh_counters() -> void:
	var wanted: Array[String] = []
	for shelf in SHELVES:
		var id: String = str(Dictionary(shelf)["id"])
		# A category the content has none of is absent rather than an empty shelf.
		if id == "all" or not _entries_in(id).is_empty():
			wanted.append(id)
	if wanted != _counter_order():
		for child in _counters.get_children():
			_counters.remove_child(child)
			child.queue_free()
		_counter_rows.clear()
		var index: int = 1
		for key in wanted:
			var row := ConsoleMenuRow.new()
			row.index_label = str(index)
			row.headline = _shelf_label(key)
			row.pressed.connect(_on_counter_pressed.bind(key))
			_counters.add_child(row)
			_counter_rows[key] = row
			index += 1
	if not (_shelf in wanted):
		_shelf = "all"
	# No count beside the label: the lines above the rule already report the set
	# category by category, and repeating it here only costs the label its last
	# few characters at this panel's width.
	for key in _counter_rows:
		(_counter_rows[key] as ConsoleMenuRow).set_selected(str(key) == _shelf)
	_layout_rows()


func _counter_order() -> Array[String]:
	var keys: Array[String] = []
	for child in _counters.get_children():
		for key in _counter_rows:
			if _counter_rows[key] == child:
				keys.append(str(key))
	return keys


func _shelf_label(key: String) -> String:
	for shelf in SHELVES:
		if str(Dictionary(shelf)["id"]) == key:
			return str(Dictionary(shelf)["label"])
	return key.to_upper()


func _entries_in(category: String) -> Array:
	var entries: Array = []
	for achievement in ContentDatabase.achievements:
		if str(Dictionary(achievement).get("category", "milestone")) == category:
			entries.append(achievement)
	return entries


func _shelf_entries(key: String) -> Array:
	if key != "all":
		return _entries_in(key)
	var entries: Array = []
	for category in CATEGORY_ORDER:
		entries.append_array(_entries_in(category))
	return entries


func _earned_in(entries: Array) -> int:
	var earned: int = 0
	for achievement in entries:
		if MetaProgress.has_achievement(str(Dictionary(achievement).get("id", ""))):
			earned += 1
	return earned


func _on_counter_pressed(key: String) -> void:
	if _shelf == key:
		return
	_shelf = key
	_selected = ""
	_board.clear_selection()
	refresh()
	lean_on("board")


func _refresh_board() -> void:
	_board_panel.set_heading(_shelf_label(_shelf).capitalize())
	var entries: Array = []
	for achievement in _shelf_entries(_shelf):
		entries.append(_award_entry(Dictionary(achievement)))
	_board.set_entries(entries)
	if _selected != "":
		_board.select(_selected)


func _refresh_notice() -> void:
	var entries: Array = _shelf_entries("all")
	_notice.text = "%d / %d\nEARNED" % [_earned_in(entries), entries.size()]


# --- Tiles -------------------------------------------------------------------

## An earned award prints at full brightness and a locked one is dimmed, so the
## gaps in the set are visible at a glance across the board. What it hands over is
## the figure, because a module in the draft pool is the only part of an award that
## changes a future run.
func _award_entry(achievement: Dictionary) -> Dictionary:
	var id: String = str(achievement.get("id", ""))
	var earned: bool = MetaProgress.has_achievement(id)
	var redacted: bool = bool(achievement.get("hidden", false)) and not earned
	var lit: Color = ConsoleStyle.PHOSPHOR if earned else ConsoleStyle.PHOSPHOR_DIM
	return {
		"meta": id,
		"name": REDACTED_NAME if redacted else str(achievement.get("name", id)),
		"figure": "" if redacted else _reward_label(achievement),
		"figure_color": lit,
		"unit": "" if redacted or _reward_label(achievement) == "" else "unlocks",
		"spec": REDACTED_HINT if redacted else str(achievement.get("hint", "")),
		"status": "EARNED" if earned else "LOCKED",
		"status_color": lit,
	}


## The name of the thing the award puts into the pool, or empty for the awards that
## are their own reward. The sentence about what it does is on the sheet.
func _reward_label(achievement: Dictionary) -> String:
	var reward: Dictionary = Dictionary(achievement.get("reward", {}))
	match str(reward.get("type", "none")):
		"unlock_module":
			var module: ModuleDefinition = ContentDatabase.get_module(
				str(reward.get("module_id", ""))
			)
			return module.name if module != null else ""
		"unlock_perk":
			var perk: PerkDefinition = ContentDatabase.get_perk(
				str(reward.get("perk_id", ""))
			)
			return perk.name if perk != null else ""
		_:
			return ""


# --- The sheet ---------------------------------------------------------------

func _on_tile_selected(meta: Variant) -> void:
	_selected = str(meta) if meta != null else ""
	_refresh_detail()


func _on_detail_closed() -> void:
	_selected = ""
	_board.clear_selection()
	_refresh_detail()


func _refresh_detail() -> void:
	var achievement: Dictionary = ContentDatabase.get_achievement(_selected)
	var reading: bool = not achievement.is_empty()
	_sign.visible = not reading
	_detail.visible = reading
	_signage_panel.set_heading("" if not reading else "The award")
	if not reading:
		return
	var id: String = str(achievement.get("id", ""))
	var earned: bool = MetaProgress.has_achievement(id)
	var redacted: bool = bool(achievement.get("hidden", false)) and not earned
	var lines: Array = []
	if redacted:
		lines.append({
			"text": "A secret award. Whatever it is, it is not something you can plan for.",
		})
	else:
		lines.append({"text": str(achievement.get("description", ""))})
		lines.append({"stat": "How", "value": str(achievement.get("hint", ""))})
		lines.append_array(_reward_lines(achievement))
	_detail.show_detail(
		REDACTED_NAME if redacted else str(achievement.get("name", id)).to_upper(),
		lines,
		"[ -- ] EARNED" if earned else "[ -- ] NOT YET EARNED",
		false
	)


func _reward_lines(achievement: Dictionary) -> Array:
	var reward: Dictionary = Dictionary(achievement.get("reward", {}))
	var evaluator := ExpressionEvaluator.new()
	match str(reward.get("type", "none")):
		"unlock_module":
			var module: ModuleDefinition = ContentDatabase.get_module(
				str(reward.get("module_id", ""))
			)
			if module == null:
				return []
			return [
				{"stat": "Hands over", "value": module.name},
				{
					"text": "%s Joins the angel draft pool in every run once this award is earned." % evaluator.render_template(
						module.description_template, module.parameters
					),
				},
			]
		"unlock_perk":
			var perk: PerkDefinition = ContentDatabase.get_perk(
				str(reward.get("perk_id", ""))
			)
			if perk == null:
				return []
			return [
				{"stat": "Hands over", "value": perk.name},
				{
					"text": "%s Joins His Table in every run once this award is earned." % evaluator.render_template(
						perk.description_template, perk.parameters
					),
				},
			]
		_:
			return []


# --- Layout ------------------------------------------------------------------

func _on_venue_layout() -> void:
	var scale: float = console_scale()
	if _board != null:
		_board.set_console(console_mode())
		_board.set_metrics(scale, content_width("board"))
	if _detail != null:
		_detail.set_metrics(scale)
	_layout_rows()
	var font_tiny: int = ConsoleMetrics.font_tiny(scale)
	for label in [_kicker, _notice]:
		if label != null:
			label.add_theme_font_size_override("font_size", font_tiny)
	var font_body: int = ConsoleMetrics.font_body(scale)
	for label in _sign.get_children():
		if label is Label:
			label.add_theme_font_size_override("font_size", font_body)
	var font_small: int = ConsoleMetrics.font_small(scale)
	for line in _index_lines.get_children():
		_apply_line_font(line, font_small)


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
