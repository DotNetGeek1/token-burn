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
@onready var token_label: Label = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/Wordmark/TokenLabel
@onready var burn_label: Label = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/Wordmark/BurnLabel
@onready var tagline: Label = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/Tagline
@onready var primary_row: HBoxContainer = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/PrimaryRow
@onready var continue_button: GameButton = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/PrimaryRow/ContinueButton
@onready var new_run_button: GameButton = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/PrimaryRow/NewRunButton
@onready var difficulty_row: HBoxContainer = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/DifficultyRow
@onready var normal_button: GameButton = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/DifficultyRow/NormalButton
@onready var hard_button: GameButton = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/DifficultyRow/HardButton
@onready var feature_grid: GridContainer = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/FeatureGrid
@onready var endless_button: GameButton = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/EndlessButton
@onready var legacy_button: Button = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/FeatureGrid/LegacyButton
@onready var achievements_button: Button = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/FeatureGrid/AchievementsButton
@onready var burn_lab_button: Button = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/FeatureGrid/BurnLabButton
@onready var utility_row: HBoxContainer = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/UtilityRow
@onready var delete_save_button: GameButton = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/UtilityRow/DeleteSaveButton
@onready var quit_button: GameButton = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/UtilityRow/QuitButton
@onready var version_label: Label = $Layout/LeftPanel/PanelVBox/Margin/MenuColumn/VersionLabel

var _detail_sheet: DetailSheet = null
var _neon_tween: Tween = null


func _ready() -> void:
	UiThemeBuilder.apply(self)
	add_to_group("title_screen")
	key_art.texture = AssetCatalog.title_art()
	_style_chrome()
	_style_menu()
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
	var scrim := TextureRect.new()
	scrim.texture = UiFx.scrim(UiThemeBuilder.color("bg"), 0.08, 0.88)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(scrim)
	move_child(scrim, vignette.get_index())

	tagline.add_theme_color_override("font_color", UiThemeBuilder.color("grey").lightened(0.35))
	version_label.add_theme_color_override("font_color", UiThemeBuilder.color("grey"))
	token_label.add_theme_color_override("font_color", UiThemeBuilder.color("white"))
	burn_label.add_theme_color_override("font_color", UiThemeBuilder.color("red"))
	for label: Label in [token_label, burn_label]:
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	version_label.text = "v%s · Early Access" % (version if version != "" else "0.1.0")
	_animate_neon()
	_animate_wordmark()


## Control modules rather than filled app buttons. Only the two run actions are
## lit by default; everything below them waits for the pointer.
func _style_menu() -> void:
	for button in [continue_button, new_run_button]:
		button.allow_wide = true
	# CONTINUE is the powered cyan primary, NEW RUN the burn-orange second tier.
	_style_module(continue_button, "action", true)
	_style_module(new_run_button, "heat", true)
	_style_module(normal_button, "action", false)
	_style_module(hard_button, "neutral", false)
	_style_module(endless_button, "perk", false)
	_style_module(delete_save_button, "danger", false)
	_style_module(quit_button, "neutral", false)
	# The destructive key only turns threatening once the pointer reaches it.
	delete_save_button.add_theme_color_override(
		"font_hover_color", UiThemeBuilder.semantic("danger").lightened(0.75)
	)


func _style_module(button: GameButton, accent_key: String, filled: bool) -> void:
	button.theme_type_variation = &"SecondaryButton"
	button.accent_key = accent_key
	var accent: Color = UiThemeBuilder.semantic(accent_key)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(
			state, UiThemeBuilder.module_style(accent, state, filled)
		)


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
	new_run_button.size_flags_stretch_ratio = 1.0 if has_save else 1.0
	continue_button.size_flags_stretch_ratio = 1.65 if has_save else 0.0
	if has_save:
		continue_button.set_lines("CONTINUE", _save_summary())
	burn_lab_button.visible = FeatureFlags.is_enabled("burn_lab_enabled")
	feature_grid.columns = 3 if burn_lab_button.visible else 2
	quit_button.visible = not OS.has_feature("web")
	_refresh_difficulty()
	_refresh_endless()
	var earned_text := "%d / %d earned" % [
		MetaProgress.achievement_count(), ContentDatabase.achievements.size(),
	]
	if legacy_button.has_method("set_lines"):
		legacy_button.set_lines("LEGACY", "Permanent unlocks and records")
	if achievements_button.has_method("set_lines"):
		achievements_button.set_lines("TROPHY CABINET", earned_text)
	if burn_lab_button.has_method("set_lines"):
		burn_lab_button.set_lines("BURN LAB", "Debug tooling")


func _save_summary() -> String:
	var payload: Dictionary = SaveManager.load_run()
	var run_state: Variant = payload.get("run_state")
	if not run_state is Dictionary:
		return "Resume your run"
	var calendar: Variant = Dictionary(run_state).get("calendar")
	if not calendar is Dictionary:
		return "Resume your run"
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


## A latched hardware selector rather than two buttons: the chosen side shows a
## lit indicator and a powered surface, the other reads as an open contact.
func _refresh_difficulty() -> void:
	var current: String = MetaProgress.difficulty()
	_latch(normal_button, "NORMAL", "action", current == "normal")
	_latch(hard_button, "HARD", "danger", current == "hard")


func _latch(button: GameButton, label: String, accent_key: String, on: bool) -> void:
	button.headline = "%s  %s" % ["\u25cf" if on else "\u25cb", label]
	_style_module(button, accent_key if on else "neutral", on)


func _refresh_endless() -> void:
	var unlocked: bool = MetaProgress.endless_unlocked()
	endless_button.visible = unlocked
	if not unlocked:
		return
	var on: bool = MetaProgress.endless_enabled()
	endless_button.set_lines(
		"%s  ENDLESS MODE" % ("\u25cf" if on else "\u25cb"), "ON" if on else "OFF"
	)
	_style_module(endless_button, "perk", on)


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


func _leave() -> void:
	start_requested.emit()
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.32)
	tween.tween_callback(func() -> void:
		visible = false
		modulate.a = 1.0
		embers.emitting = false
	)


func open() -> void:
	visible = true
	modulate.a = 0.0
	embers.emitting = true
	refresh()
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.28)
