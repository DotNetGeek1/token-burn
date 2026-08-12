extends Control

## The "More" tab: everything that is not the run itself.
##
## Starting, resuming and deleting runs moved to the title screen, so this tab is
## now settings plus the way back to the front door. It prints as a console
## index — a numbered line per destination — because it shares the side panel
## with the job board and the market, and a stack of raised cards next to those
## reads as a different game.

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

@onready var frame: ConsoleFrame = $Margin/Frame

var _rows: Dictionary = {}
var _section_labels: Array[Label] = []
var _note: Label = null
var _console_scale: float = 1.0


func _ready() -> void:
	add_to_group("ui_refresh")
	add_to_group("console_screens")
	frame.setup("More")
	_build_console()
	resized.connect(_fit_console)
	visibility_changed.connect(_on_visibility_changed)
	EventBus.run_started.connect(refresh)
	refresh()


func _build_console() -> void:
	var content: VBoxContainer = frame.content()

	_section(content, "DIFFICULTY · APPLIES FROM YOUR NEXT NEW RUN")
	_row(content, "normal", "1", "NORMAL", _on_pick_difficulty.bind("normal"))
	_row(content, "hard", "2", "HARD", _on_pick_difficulty.bind("hard"))
	_row(content, "endless", "3", "ENDLESS MODE", _on_toggle_endless)

	content.add_child(ConsoleStyle.rule(0.22))

	_section(content, "RECORDS AND TOOLS")
	_row(content, "workflows", "W", "WORKFLOWS", _on_workflows)
	_row(content, "meta", "L", "THE LEGACY", _on_meta_hub)
	_row(content, "achievements", "T", "THE TROPHY CABINET", _on_achievements)
	_row(content, "burn_lab", "D", "BURN LAB", _on_burn_lab)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(spacer)

	_note = ConsoleStyle.paragraph("", ConsoleStyle.FONT_TINY)
	content.add_child(_note)

	content.add_child(ConsoleStyle.rule(0.22))
	_row(content, "title", "X", "QUIT TO TITLE", _on_title, true)


func _section(parent: Node, text: String) -> void:
	var label: Label = ConsoleStyle.label(text, ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	parent.add_child(label)
	_section_labels.append(label)


func _row(
	parent: Node,
	key: String,
	index_label: String,
	headline: String,
	handler: Callable,
	destructive: bool = false
) -> void:
	var row := ConsoleMenuRow.new()
	parent.add_child(row)
	row.index_label = index_label
	row.headline = headline
	row.destructive = destructive
	row.pressed.connect(handler)
	_rows[key] = row


func fit_console() -> void:
	_fit_console()


func _on_visibility_changed() -> void:
	if visible:
		call_deferred("_fit_console")


func _fit_console() -> void:
	if size.y <= 1.0:
		return
	_console_scale = ConsoleMetrics.compute_scale(size.y, get_viewport_rect().size.x)
	frame.set_metrics(_console_scale)
	var font_small: int = ConsoleMetrics.font_small(_console_scale)
	var font_tiny: int = ConsoleMetrics.font_tiny(_console_scale)
	var height: int = ConsoleMetrics.row_height(_console_scale)
	var pad_h: int = ConsoleMetrics.pad_h(_console_scale)
	for key in _rows:
		(_rows[key] as ConsoleMenuRow).set_metrics(font_small, height, pad_h)
	for label in _section_labels:
		label.add_theme_font_size_override("font_size", font_tiny)
	if _note != null:
		_note.add_theme_font_size_override("font_size", font_tiny)


func refresh() -> void:
	_rows["burn_lab"].visible = FeatureFlags.is_enabled("burn_lab_enabled")
	_note.text = (
		"Autosave runs after every decision. Difficulty and endless settings "
		+ "apply from your next new run."
	)
	_refresh_difficulty()
	_refresh_endless()
	_rows["achievements"].value_text = "%d / %d EARNED" % [
		MetaProgress.achievement_count(), ContentDatabase.achievements.size(),
	]
	_rows["meta"].value_text = "UNLOCKS"
	_rows["burn_lab"].value_text = "DEBUG"
	_rows["title"].value_text = "RUN IS SAVED"
	# Only meaningful inside a run: workflows belong to the run, not the profile.
	var in_run: bool = Simulation.phase != Simulation.Phase.IDLE
	_rows["workflows"].visible = in_run
	if in_run:
		_rows["workflows"].value_text = "%d OF %d DEFINED" % [
			Simulation.workflow_count(), Simulation.workflow_capacity(),
		]
	frame.set_context(MetaProgress.difficulty().to_upper())
	_fit_console()


func _refresh_difficulty() -> void:
	var current: String = MetaProgress.difficulty()
	_rows["normal"].set_selected(current == "normal")
	_rows["hard"].set_selected(current == "hard")


func _refresh_endless() -> void:
	var unlocked: bool = MetaProgress.endless_unlocked()
	var row: ConsoleMenuRow = _rows["endless"]
	row.visible = unlocked
	if not unlocked:
		return
	var on: bool = MetaProgress.endless_enabled()
	row.value_text = "ON" if on else "OFF"
	row.set_selected(on)


func _on_pick_difficulty(difficulty_id: String) -> void:
	MetaProgress.set_difficulty(difficulty_id)
	_refresh_difficulty()
	frame.set_context(MetaProgress.difficulty().to_upper())


func _on_toggle_endless() -> void:
	MetaProgress.set_endless_enabled(not MetaProgress.endless_enabled())
	_refresh_endless()


func _on_workflows() -> void:
	get_tree().call_group("main_ui", "open_pipeline_editor")


func _on_meta_hub() -> void:
	get_tree().call_group("main_ui", "open_meta_hub")


func _on_achievements() -> void:
	get_tree().call_group("main_ui", "open_achievements")


func _on_burn_lab() -> void:
	get_tree().call_group("main_ui", "open_burn_lab")


func _on_title() -> void:
	get_tree().call_group("main_ui", "open_title")
