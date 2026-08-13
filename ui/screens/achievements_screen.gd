extends ConsoleOverlay

## The trophy cabinet: every award, whether it has been earned, and what earning
## it hands over.
##
## Read-only. Awards are not bought, and half of them are for things no sensible
## player would attempt on purpose, so the screen's job is to make the shape of
## the collection legible: what is already yours, what is still out there, and
## which modules are waiting behind which disaster.
##
## The cabinet prints as one listing with a category column rather than as a
## grid of tiles, because the question the player brings to it — how much of the
## set is missing — is answered by a column of EARNED/LOCKED, not by artwork.

const CATEGORY_ORDER := ["milestone", "disaster", "secret"]
const CATEGORY_LABELS := {
	"milestone": "MILESTONES",
	"disaster": "DISASTERS",
	"secret": "CLASSIFIED",
}
const FILTERS := [
	{"id": "all", "label": "ALL"},
	{"id": "milestone", "label": "WINS"},
	{"id": "disaster", "label": "OOPS"},
	{"id": "secret", "label": "SECRET"},
]
## A locked secret gives nothing away, so its name and flavour are withheld and
## it reads as a gap in the shelf rather than as a to-do list.
const REDACTED_NAME := "? ? ?"
const REDACTED_HINT := "Classified. You will know when it happens."

var _filter_row: HBoxContainer = null
var _filter_rows: Array[ConsoleMenuRow] = []
var _blurb: Label = null
var _table: ConsoleTable = null
var _detail_sheet: ConsoleSheet = null
var _filter: String = "all"


func _ready() -> void:
	super._ready()
	setup("Trophy Cabinet")
	_build_body()
	_detail_sheet = ConsoleSheet.new()
	add_child(_detail_sheet)


func _build_body() -> void:
	var body: VBoxContainer = content()

	_blurb = ConsoleStyle.paragraph(
		"Awards are permanent. Some of them hand over a module that joins the draft pool in every run from then on.",
		ConsoleStyle.FONT_TINY
	)
	body.add_child(_blurb)

	_filter_row = HBoxContainer.new()
	_filter_row.add_theme_constant_override("separation", 8)
	body.add_child(_filter_row)
	for i in range(FILTERS.size()):
		var filter: Dictionary = FILTERS[i]
		var row := ConsoleMenuRow.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_filter_row.add_child(row)
		row.index_label = str(i + 1)
		row.headline = str(filter["label"])
		row.pressed.connect(_on_filter.bind(str(filter["id"])))
		_filter_rows.append(row)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)

	_table = ConsoleTable.new()
	_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table.row_selected.connect(_on_row_selected)
	scroll.add_child(_table)
	_table.set_columns([
		{"label": "award", "weight": 1.8},
		{"label": "status", "weight": 0.7},
		{"label": "how", "weight": 3.0},
		{"label": "unlocks", "weight": 1.2},
	])


func refresh() -> void:
	_refresh_filters()
	_refresh_progress()
	_refresh_list()
	_apply_body_metrics()


func fit_console() -> void:
	super.fit_console()
	_apply_body_metrics()


## The body's own widgets are not part of the shell, so they are re-scaled
## alongside it whenever the room is laid out.
func _apply_body_metrics() -> void:
	var scale: float = console_scale()
	if _blurb != null:
		_blurb.add_theme_font_size_override("font_size", ConsoleMetrics.font_tiny(scale))
	var font_small: int = ConsoleMetrics.font_small(scale)
	var height: int = ConsoleMetrics.row_height(scale)
	var pad_h: int = ConsoleMetrics.pad_h(scale)
	for row in _filter_rows:
		row.set_metrics(font_small, height, pad_h)
	if _table != null:
		_table.set_metrics(scale)


func _on_filter(filter_id: String) -> void:
	_filter = filter_id
	_refresh_filters()
	_refresh_list()
	_apply_body_metrics()


func _refresh_filters() -> void:
	for i in range(_filter_rows.size()):
		_filter_rows[i].set_selected(str(FILTERS[i]["id"]) == _filter)


## How much of the set is in the cabinet, reported in the header where the
## machine reports its state.
func _refresh_progress() -> void:
	var total: int = ContentDatabase.achievements.size()
	var earned: int = 0
	for achievement in ContentDatabase.achievements:
		if MetaProgress.has_achievement(str(achievement.get("id", ""))):
			earned += 1
	set_context("%d / %d EARNED" % [earned, total])


func _refresh_list() -> void:
	_table.clear()
	for category in CATEGORY_ORDER:
		if _filter != "all" and _filter != category:
			continue
		var entries: Array = _entries_in(category)
		if entries.is_empty():
			continue
		_table.add_note(_section_text(category, entries))
		for achievement in entries:
			_add_row(achievement)


func _entries_in(category: String) -> Array:
	var entries: Array = []
	for achievement in ContentDatabase.achievements:
		if str(achievement.get("category", "milestone")) == category:
			entries.append(achievement)
	return entries


func _section_text(category: String, entries: Array) -> String:
	var earned: int = 0
	for achievement in entries:
		if MetaProgress.has_achievement(str(achievement.get("id", ""))):
			earned += 1
	return "%s · %d/%d" % [
		str(CATEGORY_LABELS.get(category, category.to_upper())), earned, entries.size(),
	]


func _add_row(achievement: Dictionary) -> void:
	var id: String = str(achievement.get("id", ""))
	var earned: bool = MetaProgress.has_achievement(id)
	var redacted: bool = bool(achievement.get("hidden", false)) and not earned
	# An earned award prints at full brightness and a locked one is dimmed, so
	# the gaps in the set are visible at a glance down the column.
	var lit: Color = ConsoleStyle.PHOSPHOR if earned else ConsoleStyle.PHOSPHOR_DIM
	# The listing only has room for the module's name; the sentence about what it
	# does is printed on the sheet the row opens.
	var reward: Dictionary = _reward_entry(achievement)
	_table.add_row([
		{
			"text": REDACTED_NAME if redacted else str(achievement.get("name", id)).to_upper(),
			"color": lit,
		},
		{
			"text": "EARNED" if earned else "LOCKED",
			"color": ConsoleStyle.PHOSPHOR if earned else ConsoleStyle.PHOSPHOR_DIM,
		},
		{
			"text": REDACTED_HINT if redacted else str(achievement.get("hint", "")),
			"color": ConsoleStyle.PHOSPHOR_DIM,
		},
		{
			"text": "" if redacted else _reward_label(reward),
			"color": ConsoleStyle.PHOSPHOR_DIM,
		},
	], id, lit)


func _reward_entry(achievement: Dictionary) -> Dictionary:
	return Dictionary(achievement.get("reward", {}))


func _reward_label(reward: Dictionary) -> String:
	match str(reward.get("type", "none")):
		"unlock_module":
			var operation: OperationDefinition = ContentDatabase.get_operation(str(reward.get("operation_id", "")))
			return operation.name.to_upper() if operation != null else ""
		"unlock_perk":
			var perk: PerkDefinition = ContentDatabase.get_perk(str(reward.get("perk_id", "")))
			return perk.name.to_upper() if perk != null else ""
		_:
			return ""


## The module the award puts into the draft pool, or null for the awards that
## are their own reward.
func _reward_module(achievement: Dictionary) -> OperationDefinition:
	var reward: Dictionary = _reward_entry(achievement)
	if str(reward.get("type", "none")) != "unlock_module":
		return null
	return ContentDatabase.get_operation(str(reward.get("operation_id", "")))


func _reward_perk(achievement: Dictionary) -> PerkDefinition:
	var reward: Dictionary = _reward_entry(achievement)
	if str(reward.get("type", "none")) != "unlock_perk":
		return null
	return ContentDatabase.get_perk(str(reward.get("perk_id", "")))


func _on_row_selected(meta: Variant) -> void:
	var achievement: Dictionary = ContentDatabase.get_achievement(str(meta))
	if achievement.is_empty():
		return
	var id: String = str(achievement.get("id", ""))
	var earned: bool = MetaProgress.has_achievement(id)
	var redacted: bool = bool(achievement.get("hidden", false)) and not earned
	var rows: Array = []
	if redacted:
		rows.append({"text": "A secret award. Whatever it is, it is not something you can plan for."})
	else:
		rows.append({"text": str(achievement.get("description", ""))})
		rows.append({"stat": "How", "value": str(achievement.get("hint", ""))})
	var operation: OperationDefinition = _reward_module(achievement)
	var perk: PerkDefinition = _reward_perk(achievement)
	if operation != null and not redacted:
		rows.append({
			"rule": "Reward · %s" % operation.name,
			"text": "%s Joins the angel draft pool in every run once this award is earned." % _module_summary(operation),
			"role": "perk",
		})
	elif perk != null and not redacted:
		rows.append({
			"rule": "Reward · %s" % perk.name,
			"text": "%s Joins His Table in every run once this award is earned." % _perk_summary(perk),
			"role": "perk",
		})
	_detail_sheet.show_detail(
		REDACTED_NAME if redacted else str(achievement.get("name", id)),
		"EARNED" if earned else "LOCKED",
		rows,
		[],
		"",
		ConsoleStyle.PHOSPHOR if earned else ConsoleStyle.PHOSPHOR_DIM
	)


func _module_summary(operation: OperationDefinition) -> String:
	return ExpressionEvaluator.new().render_template(
		operation.description_template, operation.parameters
	)


func _perk_summary(perk: PerkDefinition) -> String:
	return ExpressionEvaluator.new().render_template(
		perk.description_template, perk.parameters
	)
