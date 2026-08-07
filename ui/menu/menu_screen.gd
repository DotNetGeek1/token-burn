extends Control

## The "More" tab: everything that is not the run itself.
##
## Starting, resuming and deleting runs moved to the title screen, so this tab is
## now settings plus the way back to the front door.

@onready var normal_button: GameButton = $Panel/Margin/VBox/DifficultyRow/NormalButton
@onready var hard_button: GameButton = $Panel/Margin/VBox/DifficultyRow/HardButton
@onready var endless_button: GameButton = $Panel/Margin/VBox/EndlessButton
@onready var workflows_button: GameButton = $Panel/Margin/VBox/WorkflowsButton
@onready var meta_hub_button: GameButton = $Panel/Margin/VBox/MetaHubButton
@onready var achievements_button: GameButton = $Panel/Margin/VBox/AchievementsButton
@onready var burn_lab_button: GameButton = $Panel/Margin/VBox/BurnLabButton
@onready var title_button: GameButton = $Panel/Margin/VBox/TitleButton
@onready var save_label: Label = $Panel/Margin/VBox/SaveLabel


func _ready() -> void:
	normal_button.pressed.connect(_on_pick_difficulty.bind("normal"))
	hard_button.pressed.connect(_on_pick_difficulty.bind("hard"))
	endless_button.pressed.connect(_on_toggle_endless)
	workflows_button.pressed.connect(_on_workflows)
	meta_hub_button.pressed.connect(_on_meta_hub)
	achievements_button.pressed.connect(_on_achievements)
	burn_lab_button.pressed.connect(_on_burn_lab)
	title_button.pressed.connect(_on_title)
	add_to_group("ui_refresh")
	EventBus.run_started.connect(refresh)
	refresh()


func refresh() -> void:
	burn_lab_button.visible = FeatureFlags.is_enabled("burn_lab_enabled")
	save_label.text = "Autosave runs after every decision. Difficulty and endless settings apply from your next new run."
	_refresh_difficulty()
	_refresh_endless()
	achievements_button.set_lines(
		"THE TROPHY CABINET",
		"%d / %d earned" % [MetaProgress.achievement_count(), ContentDatabase.achievements.size()]
	)
	# Only meaningful inside a run: workflows belong to the run, not the profile.
	workflows_button.visible = Simulation.phase != Simulation.Phase.IDLE
	if workflows_button.visible:
		workflows_button.set_lines(
			"WORKFLOWS",
			"%d of %d defined" % [Simulation.workflow_count(), Simulation.workflow_capacity()]
		)


func _refresh_difficulty() -> void:
	var current: String = MetaProgress.difficulty()
	_set_toggle_state(normal_button, current == "normal", "action")
	_set_toggle_state(hard_button, current == "hard", "danger")


func _refresh_endless() -> void:
	var unlocked: bool = MetaProgress.endless_unlocked()
	endless_button.visible = unlocked
	if not unlocked:
		return
	var on: bool = MetaProgress.endless_enabled()
	endless_button.set_lines("ENDLESS MODE", "ON" if on else "OFF")
	_set_toggle_state(endless_button, on, "perk")


func _set_toggle_state(button: GameButton, selected: bool, accent: String) -> void:
	button.theme_type_variation = &"PrimaryButton" if selected else &"SecondaryButton"
	button.accent_key = accent if selected else "neutral"


func _on_pick_difficulty(difficulty_id: String) -> void:
	MetaProgress.set_difficulty(difficulty_id)
	_refresh_difficulty()


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
