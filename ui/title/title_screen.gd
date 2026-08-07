extends Control

## The game's front door.
##
## The menu used to live in the "More" tab, which meant the first thing a new
## player saw was the middle of a run. This screen sits over the shell at boot
## and steps aside once a run is loaded or started, so the run always begins
## with a deliberate press rather than by default.

signal start_requested

const EMBER_COUNT := 26

@onready var key_art: TextureRect = $KeyArt
@onready var vignette: ColorRect = $Vignette
@onready var embers: GPUParticles2D = $Embers
@onready var token_label: Label = $Layout/Margin/VBox/Wordmark/TokenLabel
@onready var burn_label: Label = $Layout/Margin/VBox/Wordmark/BurnLabel
@onready var tagline: Label = $Layout/Margin/VBox/Tagline
@onready var menu: VBoxContainer = $Layout/Margin/VBox/Menu
@onready var continue_button: GameButton = $Layout/Margin/VBox/Menu/ContinueButton
@onready var new_run_button: GameButton = $Layout/Margin/VBox/Menu/NewRunButton
@onready var difficulty_row: HBoxContainer = $Layout/Margin/VBox/Menu/DifficultyRow
@onready var normal_button: GameButton = $Layout/Margin/VBox/Menu/DifficultyRow/NormalButton
@onready var hard_button: GameButton = $Layout/Margin/VBox/Menu/DifficultyRow/HardButton
@onready var endless_button: GameButton = $Layout/Margin/VBox/Menu/EndlessButton
@onready var legacy_button: GameButton = $Layout/Margin/VBox/Menu/LegacyButton
@onready var achievements_button: GameButton = $Layout/Margin/VBox/Menu/AchievementsButton
@onready var burn_lab_button: GameButton = $Layout/Margin/VBox/Menu/BurnLabButton
@onready var delete_save_button: GameButton = $Layout/Margin/VBox/Menu/DeleteSaveButton
@onready var quit_button: GameButton = $Layout/Margin/VBox/Menu/QuitButton
@onready var version_label: Label = $Layout/Margin/VBox/VersionLabel

var _detail_sheet: DetailSheet = null
var _neon_tween: Tween = null


func _ready() -> void:
	UiThemeBuilder.apply(self)
	add_to_group("title_screen")
	key_art.texture = AssetCatalog.title_art()
	_style_chrome()
	_build_embers()
	_detail_sheet = preload("res://ui/common/detail_sheet.tscn").instantiate()
	add_child(_detail_sheet)
	continue_button.pressed.connect(_on_continue)
	new_run_button.pressed.connect(_on_new_run)
	normal_button.pressed.connect(_on_pick_difficulty.bind("normal"))
	hard_button.pressed.connect(_on_pick_difficulty.bind("hard"))
	endless_button.pressed.connect(_on_toggle_endless)
	legacy_button.pressed.connect(_on_legacy)
	achievements_button.pressed.connect(_on_achievements)
	burn_lab_button.pressed.connect(_on_burn_lab)
	delete_save_button.pressed.connect(_on_delete_save)
	quit_button.pressed.connect(_on_quit)
	refresh()


func _style_chrome() -> void:
	# The key art is bright at the top and dark at the bottom, so the menu gets a
	# gradient scrim rather than a flat wash that would grey out the artwork.
	var scrim := TextureRect.new()
	scrim.texture = UiFx.scrim(UiThemeBuilder.color("bg"), 0.12, 0.94)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(scrim)
	move_child(scrim, vignette.get_index())

	tagline.add_theme_color_override("font_color", UiThemeBuilder.color("grey").lightened(0.35))
	version_label.add_theme_color_override("font_color", UiThemeBuilder.color("grey"))
	# "TOKEN" stays cool and "BURN" burns, which is the whole pitch of the game in
	# two words.
	token_label.add_theme_color_override("font_color", UiThemeBuilder.color("white"))
	burn_label.add_theme_color_override("font_color", UiThemeBuilder.color("red"))
	for label: Label in [token_label, burn_label]:
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	version_label.text = "v%s · Early Access" % (version if version != "" else "0.1.0")
	_animate_neon()
	_animate_wordmark()


## A slow pulse on the burning half of the wordmark, so the title screen is
## never a still image.
func _animate_wordmark() -> void:
	var red: Color = UiThemeBuilder.color("red")
	var tween: Tween = create_tween().set_loops()
	tween.tween_property(burn_label, "modulate", Color(1.25, 1.05, 1.0), 1.6).set_trans(
		Tween.TRANS_SINE
	)
	tween.tween_property(burn_label, "modulate", Color(0.88, 0.88, 0.92), 2.1).set_trans(
		Tween.TRANS_SINE
	)
	burn_label.add_theme_color_override("font_outline_color", red.darkened(0.7))


## The artwork's off-frame neon sign never sits still, so the vignette that
## fakes its spill onto the UI shouldn't either.
func _animate_neon() -> void:
	var red: Color = UiThemeBuilder.color("red")
	vignette.color = Color(red.r, red.g, red.b, 0.05)
	_neon_tween = create_tween().set_loops()
	_neon_tween.tween_property(vignette, "color:a", 0.11, 2.4).set_trans(Tween.TRANS_SINE)
	_neon_tween.tween_property(vignette, "color:a", 0.04, 1.7).set_trans(Tween.TRANS_SINE)
	_neon_tween.tween_property(vignette, "color:a", 0.09, 0.35)
	_neon_tween.tween_property(vignette, "color:a", 0.05, 0.5)


func _build_embers() -> void:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(540, 20, 1)
	material.direction = Vector3(0, -1, 0)
	material.spread = 24.0
	material.initial_velocity_min = 22.0
	material.initial_velocity_max = 70.0
	material.gravity = Vector3(6, -14, 0)
	material.scale_min = 0.7
	material.scale_max = 2.4
	material.color = UiThemeBuilder.color("orange")
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = UiFx.ramp(
		[0.0, 0.2, 1.0],
		[Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)]
	)
	material.color_ramp = ramp_texture
	embers.process_material = material
	embers.texture = UiFx.radial_dot(32)
	embers.amount = EMBER_COUNT
	embers.lifetime = 7.0
	embers.preprocess = 3.0
	embers.emitting = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_place_embers()


func _place_embers() -> void:
	embers.position = Vector2(size.x * 0.5, size.y + 20.0)
	var material: ParticleProcessMaterial = embers.process_material
	if material != null:
		material.emission_box_extents = Vector3(maxf(80.0, size.x * 0.5), 20, 1)


func refresh() -> void:
	var has_save: bool = SaveManager.has_save()
	continue_button.visible = has_save
	delete_save_button.visible = has_save
	if has_save:
		continue_button.set_lines("CONTINUE", _save_summary())
	burn_lab_button.visible = FeatureFlags.is_enabled("burn_lab_enabled")
	quit_button.visible = not OS.has_feature("web")
	_refresh_difficulty()
	_refresh_endless()
	achievements_button.set_lines(
		"THE TROPHY CABINET",
		"%d / %d earned" % [MetaProgress.achievement_count(), ContentDatabase.achievements.size()]
	)


## A save file is only worth resuming if the player can tell where they left off.
func _save_summary() -> String:
	var payload: Dictionary = SaveManager.load_run()
	var run_state: Variant = payload.get("run_state")
	if not run_state is Dictionary:
		return "Resume your run"
	var calendar: Variant = Dictionary(run_state).get("calendar")
	if not calendar is Dictionary:
		return "Resume your run"
	# An unmigrated save still calls the round a month and the prompt a round, so
	# both vocabularies are read here rather than migrating just to draw a label.
	var data: Dictionary = Dictionary(calendar)
	if data.has("month"):
		return "Round %d · Prompt %d" % [
			int(data.get("month", 1)),
			int(data.get("round", 1)),
		]
	return "Round %d · Prompt %d" % [
		int(data.get("round", 1)),
		int(data.get("prompt", 1)),
	]


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


# --- Actions -----------------------------------------------------------------

func _on_continue() -> void:
	if Simulation.load_saved_run():
		_leave()


func _on_new_run() -> void:
	get_tree().call_group("flow_overlay", "hide_overlay")
	Simulation.start_run()
	_leave()


func _on_pick_difficulty(difficulty_id: String) -> void:
	MetaProgress.set_difficulty(difficulty_id)
	_refresh_difficulty()


func _on_toggle_endless() -> void:
	MetaProgress.set_endless_enabled(not MetaProgress.endless_enabled())
	_refresh_endless()


func _on_legacy() -> void:
	get_tree().call_group("main_ui", "open_meta_hub")


func _on_achievements() -> void:
	get_tree().call_group("main_ui", "open_achievements")


func _on_burn_lab() -> void:
	get_tree().call_group("main_ui", "open_burn_lab")


## Throwing away a run is the one destructive button on the screen, so it asks.
func _on_delete_save() -> void:
	_detail_sheet.show_detail(
		"Delete your save?",
		"This cannot be undone",
		[
			{"text": "The run in progress is erased. Permanent unlocks in The Legacy are kept."},
			{"stat": "Progress", "value": _save_summary()},
		],
		[],
		"DELETE SAVE",
		UiThemeBuilder.semantic("danger")
	)
	for connection in _detail_sheet.action_confirmed.get_connections():
		_detail_sheet.action_confirmed.disconnect(connection["callable"])
	_detail_sheet.action_confirmed.connect(func() -> void:
		SaveManager.delete_save()
		refresh()
	)


func _on_quit() -> void:
	get_tree().quit()


## Hands the screen over to the run with a short fade, so booting into the game
## does not feel like a hard cut.
func _leave() -> void:
	start_requested.emit()
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.32)
	tween.tween_callback(func() -> void:
		visible = false
		modulate.a = 1.0
		embers.emitting = false
	)


## Reopening from the run's More tab, so the embers and fade have to reset.
func open() -> void:
	visible = true
	modulate.a = 0.0
	embers.emitting = true
	refresh()
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.28)
