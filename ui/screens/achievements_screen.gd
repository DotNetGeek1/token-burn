extends Control

## The trophy cabinet: every award, whether it has been earned, and what earning
## it hands over.
##
## Read-only. Awards are not bought, and half of them are for things no sensible
## player would attempt on purpose, so the screen's job is to make the shape of
## the collection legible: what is already yours, what is still out there, and
## which modules are waiting behind which disaster.

const CATEGORY_ORDER := ["milestone", "disaster", "secret"]
const CATEGORY_LABELS := {
	"milestone": "MILESTONES",
	"disaster": "DISASTERS",
	"secret": "CLASSIFIED",
}
const CATEGORY_ACCENTS := {
	"milestone": "success",
	"disaster": "danger",
	"secret": "perk",
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

@onready var progress_label: Label = $Panel/Margin/VBox/ProgressLabel
@onready var filter_row: HBoxContainer = $Panel/Margin/VBox/FilterRow
@onready var content: VBoxContainer = $Panel/Margin/VBox/Scroll/Content
@onready var close_button: GameButton = $Panel/Margin/VBox/CloseButton

var _detail_sheet: DetailSheet = null
var _filter: String = "all"


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("flow_overlay")
	close_button.pressed.connect(hide_overlay)
	_detail_sheet = preload("res://ui/common/detail_sheet.tscn").instantiate()
	add_child(_detail_sheet)
	_build_filters()


func open() -> void:
	_refresh()
	UiTransition.enter(self)
	UiTransition.stagger(content)
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().call_group("main_ui", "sync_overlay_input")


func hide_overlay() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().call_group("main_ui", "sync_overlay_input")


func _build_filters() -> void:
	for filter in FILTERS:
		var button := Button.new()
		button.text = str(filter["label"])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", UiThemeBuilder.FONT_BODY)
		button.clip_text = true
		button.pressed.connect(_on_filter.bind(str(filter["id"])))
		filter_row.add_child(button)
	_style_filters()


func _on_filter(filter_id: String) -> void:
	UiSound.play("tap")
	_filter = filter_id
	_style_filters()
	_refresh_list()
	UiTransition.stagger(content)


func _style_filters() -> void:
	var index: int = 0
	for child in filter_row.get_children():
		if child is Button:
			var active: bool = str(FILTERS[index]["id"]) == _filter
			child.theme_type_variation = &"PrimaryButton" if active else &"SecondaryButton"
			index += 1


func _refresh() -> void:
	_refresh_progress()
	_refresh_list()


func _refresh_progress() -> void:
	var total: int = ContentDatabase.achievements.size()
	var earned: int = 0
	for achievement in ContentDatabase.achievements:
		if MetaProgress.has_achievement(str(achievement.get("id", ""))):
			earned += 1
	progress_label.text = "%d / %d EARNED" % [earned, total]


func _refresh_list() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	for category in CATEGORY_ORDER:
		if _filter != "all" and _filter != category:
			continue
		var entries: Array = _entries_in(category)
		if entries.is_empty():
			continue
		content.add_child(_section_label(category, entries))
		for achievement in entries:
			content.add_child(_achievement_row(achievement))


func _entries_in(category: String) -> Array:
	var entries: Array = []
	for achievement in ContentDatabase.achievements:
		if str(achievement.get("category", "milestone")) == category:
			entries.append(achievement)
	return entries


func _section_label(category: String, entries: Array) -> Control:
	var earned: int = 0
	for achievement in entries:
		if MetaProgress.has_achievement(str(achievement.get("id", ""))):
			earned += 1
	var label := Label.new()
	label.theme_type_variation = &"SectionLabel"
	label.text = "%s · %d/%d" % [
		str(CATEGORY_LABELS.get(category, category.to_upper())), earned, entries.size(),
	]
	label.add_theme_color_override(
		"font_color", UiThemeBuilder.semantic(str(CATEGORY_ACCENTS.get(category, "neutral")))
	)
	return label


func _achievement_row(achievement: Dictionary) -> Control:
	var id: String = str(achievement.get("id", ""))
	var earned: bool = MetaProgress.has_achievement(id)
	var redacted: bool = bool(achievement.get("hidden", false)) and not earned

	# A PanelContainer rather than a Button holding a layout: the row's height is
	# whatever its wrapped text needs, and a Button does not grow for children it
	# does not own. The tap target is a flat button stretched over the top, which
	# the panel sizes to the same rect for free.
	var card := PanelContainer.new()
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, UiThemeBuilder.SPACE_MD)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, UiThemeBuilder.SPACE_SM)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiThemeBuilder.SPACE_MD)
	margin.add_child(row)

	var icon_rect := TextureRect.new()
	icon_rect.texture = _icon_for(achievement, earned, redacted)
	icon_rect.custom_minimum_size = Vector2(48, 48)
	icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Unearned awards are the same art with the light off, so the cabinet reads
	# as a set with gaps in it rather than as two unrelated lists.
	icon_rect.modulate = Color.WHITE if earned else Color(0.42, 0.42, 0.5)
	row.add_child(icon_rect)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", UiThemeBuilder.SPACE_XS)
	row.add_child(text_box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiThemeBuilder.SPACE_SM)
	text_box.add_child(header)

	var name_label := Label.new()
	name_label.text = REDACTED_NAME if redacted else str(achievement.get("name", id))
	name_label.theme_type_variation = &"TitleLabel"
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not earned:
		name_label.add_theme_color_override("font_color", UiThemeBuilder.color("grey"))
	header.add_child(name_label)

	var status_label := Label.new()
	status_label.text = "EARNED" if earned else "LOCKED"
	status_label.theme_type_variation = &"SectionLabel"
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override(
		"font_color", UiThemeBuilder.semantic("success" if earned else "neutral")
	)
	header.add_child(status_label)

	var hint_label := Label.new()
	hint_label.text = REDACTED_HINT if redacted else str(achievement.get("hint", ""))
	hint_label.theme_type_variation = &"MutedLabel"
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(hint_label)

	var reward_text: String = _reward_text(achievement)
	if reward_text != "" and not redacted:
		var reward_label := Label.new()
		reward_label.text = reward_text
		reward_label.theme_type_variation = &"MutedLabel"
		reward_label.add_theme_color_override("font_color", UiThemeBuilder.semantic("perk"))
		text_box.add_child(reward_label)

	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_row_pressed.bind(achievement))
	card.add_child(button)
	return card


func _icon_for(achievement: Dictionary, earned: bool, redacted: bool) -> Texture2D:
	if redacted:
		return AssetCatalog.achievement_icon("locked")
	var icon: Texture2D = AssetCatalog.achievement_icon(str(achievement.get("icon", "")))
	if icon != null:
		return icon
	return AssetCatalog.achievement_icon("trophy" if earned else "locked")


## What the award hands over, phrased as the module it puts into the pool rather
## than as an id nobody would recognise.
func _reward_text(achievement: Dictionary) -> String:
	var reward: Dictionary = Dictionary(achievement.get("reward", {}))
	if str(reward.get("type", "none")) != "unlock_module":
		return ""
	var operation: OperationDefinition = ContentDatabase.get_operation(
		str(reward.get("operation_id", ""))
	)
	if operation == null:
		return ""
	return "Unlocks module · %s" % operation.name


func _on_row_pressed(achievement: Dictionary) -> void:
	UiSound.play("tap")
	var id: String = str(achievement.get("id", ""))
	var earned: bool = MetaProgress.has_achievement(id)
	var redacted: bool = bool(achievement.get("hidden", false)) and not earned
	var rows: Array = []
	if redacted:
		rows.append({"text": "A secret award. Whatever it is, it is not something you can plan for."})
	else:
		rows.append({"text": str(achievement.get("description", ""))})
		rows.append({"stat": "How", "value": str(achievement.get("hint", ""))})
	var reward_text: String = _reward_text(achievement)
	if reward_text != "" and not redacted:
		var operation: OperationDefinition = ContentDatabase.get_operation(
			str(Dictionary(achievement.get("reward", {})).get("operation_id", ""))
		)
		rows.append({
			"rule": "Reward · %s" % operation.name,
			"text": "%s Joins the angel draft pool in every run once this award is earned." % _module_summary(operation),
			"role": "perk",
		})
	_detail_sheet.show_detail(
		REDACTED_NAME if redacted else str(achievement.get("name", id)),
		"EARNED" if earned else "LOCKED",
		rows,
		[],
		"",
		UiThemeBuilder.semantic("success" if earned else "neutral")
	)


func _module_summary(operation: OperationDefinition) -> String:
	return ExpressionEvaluator.new().render_template(
		operation.description_template, operation.parameters
	)
