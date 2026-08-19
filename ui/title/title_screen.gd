extends Control

## The game's front door: a live console printed over the burning compute works.
##
## The menu used to live in the "More" tab, which meant the first thing a new
## player saw was the middle of a run. This screen sits over the shell at boot
## and steps aside once a run is loaded or started, so the run always begins
## with a deliberate press rather than by default.
##
## Nothing here is an app control. The menu is a diegetic system console laid into
## the same overheated venue as the boot splash: fixed-pitch phosphor text that
## types itself on, one touchable line per action, with number-key shortcuts.

signal start_requested

## The rig's own monitor overlay, so the title's glass and the one the player
## works on during a run are the same piece of hardware.
const CRT_SHADER := preload("res://ui/board/crt_screen.gdshader")
const TITLE_BACKGROUND := preload("res://presentation/title/boot_splash_background.png")

const PHOSPHOR := ConsoleStyle.PHOSPHOR
const PHOSPHOR_DIM := ConsoleStyle.PHOSPHOR_DIM

## Glass height every type size below was chosen against. Rendered text is scaled
## from this, so the menu keeps its proportions on a phone and on a 4K monitor.
const REFERENCE_GLASS := Vector2(720.0, 560.0)
const PANEL_WIDTH_RATIO := 0.62
const PANEL_MAX_WIDTH := 800.0
const DESKTOP_BREAKPOINT := 720.0
const MIN_SCALE := 0.82
const MAX_SCALE := 3.0

const BOOT_LINES := [
	"POST OK ... 640K CONTEXT FREE",
	"MOUNTING profile.json ... OK",
	"WARMING INFERENCE CORE ... READY",
]
## Characters per second while a line prints. Fast enough that an impatient
## player rarely reaches for the skip, slow enough to read as output.
const TYPE_SPEED := 120.0
const ROW_TYPE_SPEED := 260.0
const METRIC_INTERVAL := 0.5
const EMBER_COUNT := 22

@onready var backdrop: TextureRect = $Backdrop
@onready var scrim: TextureRect = $Scrim
@onready var vignette: TextureRect = $Vignette
@onready var embers: CPUParticles2D = $Embers
@onready var stage: Control = $Stage
@onready var desk_shadow: TextureRect = $Stage/DeskShadow
@onready var laptop: TextureRect = $Stage/Laptop
@onready var screen_glow: TextureRect = $Stage/ScreenGlow
@onready var terminal: Control = $Stage/Terminal
@onready var glass: ColorRect = $Stage/Terminal/Glass
@onready var crt_overlay: ColorRect = $Stage/Terminal/CrtOverlay
@onready var boot_log: VBoxContainer = $Stage/Terminal/BootLog
@onready var inner: MarginContainer = $Stage/Terminal/Inner
@onready var body: VBoxContainer = $Stage/Terminal/Inner/Body
@onready var header_label: Label = $Stage/Terminal/Inner/Body/HeaderBar/HeaderLabel
@onready var clock_label: Label = $Stage/Terminal/Inner/Body/HeaderBar/ClockLabel
@onready var header_rule: ColorRect = $Stage/Terminal/Inner/Body/HeaderRule
@onready var columns: HBoxContainer = $Stage/Terminal/Inner/Body/Columns
@onready var main_column: VBoxContainer = $Stage/Terminal/Inner/Body/Columns/MainColumn
@onready var wordmark: Label = $Stage/Terminal/Inner/Body/Columns/MainColumn/Wordmark
@onready var tagline: Label = $Stage/Terminal/Inner/Body/Columns/MainColumn/Tagline
@onready var menu_gap: Control = $Stage/Terminal/Inner/Body/Columns/MainColumn/MenuGap
@onready var menu_frame: PanelContainer = (
	$Stage/Terminal/Inner/Body/Columns/MainColumn/MenuFrame
)
@onready var menu_margin: MarginContainer = (
	$Stage/Terminal/Inner/Body/Columns/MainColumn/MenuFrame/MenuMargin
)
@onready var menu_box: VBoxContainer = (
	$Stage/Terminal/Inner/Body/Columns/MainColumn/MenuFrame/MenuMargin/MenuBox
)
@onready var menu_title: Label = (
	$Stage/Terminal/Inner/Body/Columns/MainColumn/MenuFrame/MenuMargin/MenuBox/MenuTitle
)
@onready var rows_box: VBoxContainer = (
	$Stage/Terminal/Inner/Body/Columns/MainColumn/MenuFrame/MenuMargin/MenuBox/Rows
)
@onready var prompt_label: Label = (
	$Stage/Terminal/Inner/Body/Columns/MainColumn/PromptLabel
)
@onready var side_panels: VBoxContainer = $Stage/Terminal/Inner/Body/Columns/SidePanels

var _detail_sheet: ConsoleSheet = null
var _rows: Array[ConsoleMenuRow] = []
var _panels: Dictionary = {}
var _scale: float = 1.0
var _boot_tween: Tween = null
var _cursor_tween: Tween = null
var _booted: bool = false
var _metric_clock: float = 0.0


func _ready() -> void:
	UiThemeBuilder.apply(self)
	add_to_group("title_screen")
	_build_scene()
	_build_panels()
	_detail_sheet = ConsoleSheet.new()
	add_child(_detail_sheet)
	refresh()
	_layout_stage()
	_play_boot()


# --- The room and the machine ------------------------------------------------

func _build_scene() -> void:
	backdrop.texture = TITLE_BACKGROUND
	# A horizontal scrim leaves the burning turbine intact while making the live
	# menu feel printed into the darker half of the venue.
	var scrim_texture := GradientTexture2D.new()
	scrim_texture.gradient = UiFx.ramp(
		[0.0, 0.46, 0.76, 1.0],
		[
			Color(0.005, 0.016, 0.012, 0.92),
			Color(0.005, 0.016, 0.012, 0.72),
			Color(0.005, 0.016, 0.012, 0.16),
			Color(0.005, 0.016, 0.012, 0.03),
		]
	)
	scrim_texture.fill_from = Vector2(0.0, 0.5)
	scrim_texture.fill_to = Vector2(1.0, 0.5)
	scrim_texture.width = 256
	scrim_texture.height = 8
	scrim.texture = scrim_texture
	vignette.texture = UiFx.vignette(Color(0, 0, 0, 0.78), 0.28)

	# The old laptop nodes remain in the scene for save-compatible node paths,
	# but the new title is full-bleed venue art rather than another machine shot.
	laptop.visible = false
	desk_shadow.visible = false
	screen_glow.texture = UiFx.radial_dot(96, 0.15)
	screen_glow.modulate = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.07)
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	screen_glow.material = glow_material

	var crt_material := ShaderMaterial.new()
	crt_material.shader = CRT_SHADER
	crt_material.set_shader_parameter("phosphor", PHOSPHOR)
	crt_overlay.material = crt_material
	crt_overlay.color = Color.WHITE

	glass.color = Color(0.009, 0.032, 0.023, 0.48)

	var menu_style := StyleBoxFlat.new()
	menu_style.bg_color = Color(0.006, 0.025, 0.017, 0.62)
	menu_style.border_color = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.34)
	menu_style.set_border_width_all(1)
	menu_style.set_corner_radius_all(0)
	menu_frame.add_theme_stylebox_override("panel", menu_style)
	header_rule.color = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.26)

	header_label.text = "TOKEN_BURN %s" % _version()
	wordmark.text = "TOKEN_BURN"
	wordmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tagline.text = "BUILD.  OPTIMIZE.  BURN."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	menu_title.text = "\u2500\u2500  MAIN MENU"
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# The venue and its fire are the secondary readout now. Keeping the old live
	# metric widgets built but hidden preserves their data path without crowding
	# the action list the player came here to use.
	side_panels.visible = false
	_refresh_clock()
	_build_embers()


func _build_embers() -> void:
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(540, 20)
	embers.direction = Vector2(0, -1)
	embers.spread = 24.0
	embers.initial_velocity_min = 18.0
	embers.initial_velocity_max = 60.0
	embers.gravity = Vector2(6, -12)
	embers.scale_amount_min = 0.6
	embers.scale_amount_max = 2.0
	embers.color = UiThemeBuilder.color("orange")
	embers.color_ramp = UiFx.ramp(
		[0.0, 0.2, 1.0],
		[Color(1, 1, 1, 0), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)]
	)
	embers.texture = UiFx.radial_dot(32)
	embers.amount = EMBER_COUNT
	embers.lifetime = 7.0
	embers.preprocess = 3.0
	embers.emitting = true


func _version() -> String:
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	return "v%s" % (version if version != "" else "0.1.0")


# --- Placing the venue console -----------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout_stage()


## Wide displays leave the turbine unobstructed. Narrow displays promote the
## console to a near-full-screen sheet so every action remains touchable.
func _layout_stage() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_layout_backdrop()
	var desktop: bool = size.x >= DESKTOP_BREAKPOINT and size.x / size.y >= 1.15
	var glass_rect: Rect2
	if desktop:
		var margin_x: float = maxf(42.0, size.x * 0.055)
		var margin_y: float = maxf(26.0, size.y * 0.052)
		glass_rect = Rect2(
			Vector2(margin_x, margin_y),
			Vector2(minf(size.x * PANEL_WIDTH_RATIO, PANEL_MAX_WIDTH), size.y - margin_y * 2.0)
		)
	else:
		var margin: float = maxf(12.0, size.x * 0.032)
		glass_rect = Rect2(
			Vector2(margin, margin), Vector2(size.x - margin * 2.0, size.y - margin * 2.0)
		)
	terminal.position = glass_rect.position
	terminal.size = glass_rect.size
	screen_glow.position = glass_rect.position - glass_rect.size * Vector2(0.12, 0.08)
	screen_glow.size = glass_rect.size * Vector2(1.24, 1.16)

	embers.position = Vector2(size.x * 0.82, size.y + 20.0)
	embers.emission_rect_extents = Vector2(maxf(80.0, size.x * 0.22), 20)

	var crt_material: ShaderMaterial = crt_overlay.material
	if crt_material != null:
		crt_material.set_shader_parameter(
			"scanline_count", maxf(60.0, glass_rect.size.y * 0.5)
		)

	var fit_scale: float = minf(
		glass_rect.size.x / REFERENCE_GLASS.x, glass_rect.size.y / REFERENCE_GLASS.y
	)
	if not desktop:
		fit_scale = maxf(fit_scale, glass_rect.size.x / 460.0)
	_apply_metrics(clampf(fit_scale * 1.18, MIN_SCALE, MAX_SCALE))


## Everything printed on the glass is sized from the glass, so the menu reads the
## same whether the window is a phone in landscape or a desktop monitor.
func _apply_metrics(new_scale: float) -> void:
	_scale = new_scale
	inner.add_theme_constant_override("margin_left", _px(12))
	inner.add_theme_constant_override("margin_right", _px(12))
	inner.add_theme_constant_override("margin_top", _px(9))
	inner.add_theme_constant_override("margin_bottom", _px(9))
	body.add_theme_constant_override("separation", _px(5))
	columns.add_theme_constant_override("separation", _px(14))
	main_column.add_theme_constant_override("separation", _px(2))
	menu_margin.add_theme_constant_override("margin_left", _px(6))
	menu_margin.add_theme_constant_override("margin_right", _px(6))
	menu_margin.add_theme_constant_override("margin_top", _px(5))
	menu_margin.add_theme_constant_override("margin_bottom", _px(5))
	menu_box.add_theme_constant_override("separation", _px(4))
	rows_box.add_theme_constant_override("separation", _px(1))
	side_panels.add_theme_constant_override("separation", _px(6))
	side_panels.custom_minimum_size = Vector2(_px(168), 0)
	menu_gap.custom_minimum_size = Vector2(0, _px(6))
	boot_log.add_theme_constant_override("separation", _px(2))
	# Floated below the header rule rather than over it, since the log is not part
	# of the body's flow.
	boot_log.position = Vector2(_px(12), _px(28))

	_mono(header_label, _px(11), PHOSPHOR_DIM)
	_mono(clock_label, _px(11), PHOSPHOR_DIM)
	_mono(wordmark, _px(38), PHOSPHOR)
	_mono(tagline, _px(11), PHOSPHOR_DIM)
	_mono(menu_title, _px(10), PHOSPHOR_DIM)
	_mono(prompt_label, _px(13), PHOSPHOR)
	for child in boot_log.get_children():
		if child is Label:
			_mono(child as Label, _px(10), PHOSPHOR_DIM)
	for row in _rows:
		row.set_metrics(_px(14), _px(27), _px(8))
	for key in _panels:
		(_panels[key] as ConsolePanel).set_metrics(_scale)


## Covers the window with the venue. Portrait crops toward the burning machinery
## so the few exposed edges still carry the scene's orange/green contrast.
func _layout_backdrop() -> void:
	var texture: Texture2D = backdrop.texture
	if texture == null:
		return
	var room: Vector2 = texture.get_size()
	if room.x <= 0.0 or room.y <= 0.0:
		return
	var drawn: Vector2 = room * maxf(size.x / room.x, size.y / room.y)
	var focus_x: float = 0.64 if size.x < size.y else 0.5
	backdrop.position = Vector2((size.x - drawn.x) * focus_x, (size.y - drawn.y) * 0.5)
	backdrop.size = drawn
	vignette.position = Vector2.ZERO
	vignette.size = size


func _px(reference_units: int) -> int:
	return maxi(1, int(round(float(reference_units) * _scale)))


func _mono(label: Label, font_size: int, color: Color) -> void:
	var font: Font = UiThemeBuilder.mono_font()
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)


# --- Menu model --------------------------------------------------------------

## Every line the menu could show, in order, with the condition that earns it a
## slot. Numbers are handed out to whatever survives, so the player never sees a
## gap in the sequence.
func _entries() -> Array[Dictionary]:
	var has_save: bool = SaveManager.has_save()
	var entries: Array[Dictionary] = []
	if has_save:
		entries.append({"id": "continue", "label": "CONTINUE", "value": _save_summary()})
	entries.append({
		"id": "new_run", "label": "NEW RUN", "value": "Start again from the bedroom",
	})
	entries.append({
		"id": "difficulty",
		"label": "DIFFICULTY",
		"value": MetaProgress.difficulty().capitalize(),
	})
	if MetaProgress.endless_unlocked():
		entries.append({
			"id": "endless",
			"label": "ENDLESS MODE",
			"value": "ON" if MetaProgress.endless_enabled() else "OFF",
		})
	entries.append({
		"id": "legacy", "label": "LEGACY", "value": "Permanent unlocks and records",
	})
	entries.append({
		"id": "achievements",
		"label": "TROPHY CABINET",
		"value": "%d / %d earned" % [
			MetaProgress.achievement_count(), ContentDatabase.achievements.size(),
		],
	})
	if FeatureFlags.is_enabled("burn_lab_enabled"):
		entries.append({"id": "burn_lab", "label": "BURN LAB", "value": "Debug tooling"})
	if has_save:
		entries.append({
			"id": "delete_save", "label": "DELETE SAVE", "value": "", "destructive": true,
		})
	if not OS.has_feature("web"):
		entries.append({"id": "quit", "label": "QUIT", "value": "", "destructive": true})
	return entries


func refresh() -> void:
	if not is_node_ready():
		return
	_build_rows()
	_refresh_panels()
	if _booted:
		_blink_cursor()


func _build_rows() -> void:
	_rows.clear()
	# Detached before freeing: queue_free only takes effect at the end of the
	# frame, and the numbering below has to see an empty column.
	for child in rows_box.get_children():
		rows_box.remove_child(child)
		child.queue_free()
	var entries: Array[Dictionary] = _entries()
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var row := ConsoleMenuRow.new()
		row.index_label = str(i + 1)
		row.headline = str(entry.get("label", ""))
		row.value_text = str(entry.get("value", ""))
		row.destructive = bool(entry.get("destructive", false))
		row.set_meta("entry_id", str(entry.get("id", "")))
		row.pressed.connect(_activate.bind(str(entry.get("id", ""))))
		rows_box.add_child(row)
		row.set_metrics(_px(14), _px(27), _px(8))
		_rows.append(row)
		if not _booted:
			row.set_reveal(0)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.focus_mode = Control.FOCUS_NONE
	prompt_label.text = "Select option [1-%d]: _" % maxi(1, _rows.size())


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


# --- Side panels -------------------------------------------------------------

func _build_panels() -> void:
	for child in side_panels.get_children():
		side_panels.remove_child(child)
		child.queue_free()
	_panels.clear()
	for spec in [
		{"key": "system", "kicker": "SYSTEM STATUS", "spark": true},
		{"key": "tokens", "kicker": "TOKENS BURNED", "spark": false},
		{"key": "contracts", "kicker": "CONTRACTS DONE", "spark": false},
		{"key": "records", "kicker": "RECORDS", "spark": false},
	]:
		var panel := ConsolePanel.new()
		side_panels.add_child(panel)
		panel.setup(str(spec["kicker"]), bool(spec["spark"]))
		panel.set_metrics(_scale)
		_panels[str(spec["key"])] = panel
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_panels.add_child(filler)


func _refresh_panels() -> void:
	if _panels.is_empty():
		return
	_refresh_system_panel()
	_panels["tokens"].set_readout(
		_compact(MetaProgress.lifetime_stat("tokens_burned")), "lifetime"
	)
	_panels["contracts"].set_readout(
		_compact(MetaProgress.lifetime_stat("completed_jobs")),
		"%d runs played" % int(MetaProgress.lifetime_stat("runs"))
	)
	var best: Dictionary = MetaProgress.best_scores()
	_panels["records"].set_readout(
		_compact(float(best.get("total_tokens_burned", 0.0))),
		"best burn · %d wins" % MetaProgress.victories()
	)


func _refresh_system_panel() -> void:
	var panel: ConsolePanel = _panels.get("system") as ConsolePanel
	if panel == null:
		return
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var memory: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	panel.set_readout("%d FPS" % int(round(fps)), "%.0f MB resident" % memory)
	panel.push_sample(fps)


## Big lifetime counters run to seven figures, and the panel is a fifth of a
## laptop screen wide.
func _compact(value: float) -> String:
	var magnitude: float = absf(value)
	if magnitude >= 1_000_000_000.0:
		return "%.1fB" % (value / 1_000_000_000.0)
	if magnitude >= 1_000_000.0:
		return "%.1fM" % (value / 1_000_000.0)
	if magnitude >= 10_000.0:
		return "%.0fK" % (value / 1_000.0)
	if magnitude >= 1_000.0:
		return "%.1fK" % (value / 1_000.0)
	return "%d" % int(round(value))


# --- Boot printer ------------------------------------------------------------

## Prints the screen on the way a terminal would: log lines, then the wordmark,
## then the menu a row at a time, then the readouts. Any input skips to the end.
func _play_boot() -> void:
	_booted = false
	_kill_boot()
	_reset_for_boot()
	_boot_tween = create_tween()
	for line in BOOT_LINES:
		var label: Label = Label.new()
		_mono(label, _px(10), PHOSPHOR_DIM)
		label.text = str(line)
		label.visible_characters = 0
		boot_log.add_child(label)
		var seconds: float = float(label.text.length()) / TYPE_SPEED
		_boot_tween.tween_method(
			_type_into.bind(label), 0.0, float(label.text.length()), seconds
		)
		_boot_tween.tween_interval(0.06)
	_boot_tween.tween_interval(0.12)
	_boot_tween.tween_callback(func() -> void: boot_log.visible = false)
	_boot_tween.tween_property(wordmark, "modulate:a", 1.0, 0.18)
	_boot_tween.tween_property(tagline, "modulate:a", 1.0, 0.16)
	_boot_tween.tween_interval(0.1)
	for row in _rows:
		var length: int = row.reveal_length()
		_boot_tween.tween_callback(func() -> void: UiSound.play("key"))
		_boot_tween.tween_method(
			_reveal_row.bind(row), 0.0, float(length), float(length) / ROW_TYPE_SPEED
		)
	_boot_tween.tween_property(side_panels, "modulate:a", 1.0, 0.25)
	_boot_tween.tween_property(prompt_label, "modulate:a", 1.0, 0.16)
	_boot_tween.tween_callback(_finish_boot)


## The boot log is floated over the glass rather than laid out with the menu, so
## the log filling the screen does not shove the menu around as it prints.
func _reset_for_boot() -> void:
	for child in boot_log.get_children():
		boot_log.remove_child(child)
		child.queue_free()
	boot_log.visible = true
	wordmark.modulate.a = 0.0
	tagline.modulate.a = 0.0
	prompt_label.modulate.a = 0.0
	side_panels.modulate.a = 0.0
	for row in _rows:
		row.set_reveal(0)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.focus_mode = Control.FOCUS_NONE


func _type_into(characters: float, label: Label) -> void:
	label.visible_characters = int(characters)


func _reveal_row(characters: float, row: ConsoleMenuRow) -> void:
	row.set_reveal(int(characters))


func _finish_boot() -> void:
	_booted = true
	boot_log.visible = false
	wordmark.modulate.a = 1.0
	tagline.modulate.a = 1.0
	prompt_label.modulate.a = 1.0
	side_panels.modulate.a = 1.0
	for row in _rows:
		row.set_reveal(-1)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.focus_mode = Control.FOCUS_ALL
	_blink_cursor()


func _skip_boot() -> void:
	if _booted:
		return
	_kill_boot()
	_finish_boot()


func _kill_boot() -> void:
	if _boot_tween != null and _boot_tween.is_valid():
		_boot_tween.kill()
	_boot_tween = null


func _blink_cursor() -> void:
	if _cursor_tween != null and _cursor_tween.is_valid():
		_cursor_tween.kill()
	var base: String = prompt_label.text.trim_suffix("_")
	_cursor_tween = create_tween().set_loops()
	_cursor_tween.tween_callback(func() -> void: prompt_label.text = base + "_")
	_cursor_tween.tween_interval(0.5)
	_cursor_tween.tween_callback(func() -> void: prompt_label.text = base)
	_cursor_tween.tween_interval(0.4)


# --- Input -------------------------------------------------------------------

## The skip has to be caught ahead of the GUI: the panels the terminal is built
## from stop mouse events, so a click on the glass would never reach this Control
## through the normal `_gui_input` route.
func _input(event: InputEvent) -> void:
	if _booted or not visible:
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		_skip_boot()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if not visible or key_event == null or not key_event.pressed or key_event.echo:
		return
	if not _booted:
		_skip_boot()
		get_viewport().set_input_as_handled()
		return
	# The delete confirmation is a modal over the terminal, and its own buttons
	# own the keyboard while it is up.
	if _detail_sheet != null and _detail_sheet.visible:
		return
	var key: int = key_event.keycode
	var slot: int = -1
	if key >= KEY_1 and key <= KEY_9:
		slot = key - KEY_1
	elif key >= KEY_KP_1 and key <= KEY_KP_9:
		slot = key - KEY_KP_1
	if slot < 0 or slot >= _rows.size():
		return
	var row: ConsoleMenuRow = _rows[slot]
	row.grab_focus()
	_activate(str(row.get_meta("entry_id", "")))
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_metric_clock += delta
	if _metric_clock < METRIC_INTERVAL:
		return
	_metric_clock = 0.0
	_refresh_clock()
	if _booted:
		_refresh_system_panel()


func _refresh_clock() -> void:
	var now: Dictionary = Time.get_time_dict_from_system()
	clock_label.text = "%02d:%02d" % [int(now.get("hour", 0)), int(now.get("minute", 0))]


# --- Actions -----------------------------------------------------------------

func _activate(entry_id: String) -> void:
	match entry_id:
		"continue":
			if Simulation.load_saved_run():
				_leave()
		"new_run":
			get_tree().call_group("flow_overlay", "hide_overlay")
			Simulation.start_run()
			_leave()
		"difficulty":
			MetaProgress.set_difficulty(
				"hard" if MetaProgress.difficulty() == "normal" else "normal"
			)
			refresh()
		"endless":
			MetaProgress.set_endless_enabled(not MetaProgress.endless_enabled())
			refresh()
		"legacy":
			SceneRouter.open_legacy()
		"achievements":
			SceneRouter.open_achievements()
		"burn_lab":
			SceneRouter.open_burn_lab()
		"delete_save":
			_confirm_delete_save()
		"quit":
			get_tree().quit()


func _confirm_delete_save() -> void:
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
	_layout_stage()
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.28)
	# Returning to the front door replays the print-on: it is short, and it makes
	# stepping out of a run feel like the machine came back to its own screen.
	_play_boot()
