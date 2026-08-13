extends Control

## The game's front door: the menu running on the laptop that starts the run.
##
## The menu used to live in the "More" tab, which meant the first thing a new
## player saw was the middle of a run. This screen sits over the shell at boot
## and steps aside once a run is loaded or started, so the run always begins
## with a deliberate press rather than by default.
##
## Nothing here is an app control. The bedroom is the backdrop, the used laptop
## from the rig art is the machine, and the menu is what is printed on its glass:
## fixed-pitch phosphor text that types itself on at boot, one touchable line per
## action, with the number keys as a shortcut for anyone who would rather type at
## it. Everything is measured off the screen rect the artwork was authored with,
## so the menu stays pinned to the glass at any window size.

signal start_requested

## The rig's own monitor overlay, so the title's glass and the one the player
## works on during a run are the same piece of hardware.
const CRT_SHADER := preload("res://ui/board/crt_screen.gdshader")
const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

const PHOSPHOR := ConsoleStyle.PHOSPHOR
const PHOSPHOR_DIM := ConsoleStyle.PHOSPHOR_DIM

## The laptop the run starts on. Same artwork the board puts on the desk, so the
## machine on the title is the machine the player is about to use.
const LAPTOP_STAGE := 1
## Where the machine itself sits inside its picture, measured off the artwork.
## The picture is mostly black field, so the composition is framed on this rather
## than on the file: the laptop is centred and scaled by where the plastic is.
const MACHINE_UV := Rect2(0.18, 0.06, 0.66, 0.93)
## How much of the window's width the machine is asked to fill. The glass is only
## 46% of the picture across, so this is the dial that decides whether the menu
## is legible; what it costs is the front of the keyboard, which runs off the
## bottom of the frame as though the player were leaning over it.
const MACHINE_WIDTH := 0.74
## Where the top of the lid sits, as a fraction of the window height.
const MACHINE_TOP := 0.045
## Ceiling on how far the artwork may overhang vertically, so a short window
## crops the keyboard rather than swallowing the whole machine.
const MAX_ART_OVERFLOW := 1.5
## The key art is a portrait room and the window is landscape, so most of it is
## cropped away. Centring the crop lands on the floor; this pulls it up to the
## band with the desk, the window and the neon in it.
const BACKDROP_FOCUS := 0.3
## Glass height every type size below was chosen against. Rendered text is scaled
## from this, so the menu keeps its proportions on a phone and on a 4K monitor.
const REFERENCE_GLASS := 350.0
const MIN_SCALE := 0.55
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
@onready var vignette: TextureRect = $Vignette
@onready var embers: GPUParticles2D = $Embers
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
var _glass_uv: Rect2 = Rect2()
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
	backdrop.texture = AssetCatalog.title_art()
	vignette.texture = UiFx.vignette(Color(0, 0, 0, 0.82), 0.22)

	var art: Dictionary = AssetCatalog.rig_stage(LAPTOP_STAGE)
	laptop.texture = _cropped_art(art)
	var screens: Array = Array(art.get("screens", []))
	_glass_uv = screens[0] if not screens.is_empty() else Rect2(0.27, 0.1, 0.46, 0.42)
	# The photograph is a machine on a black field. Added rather than pasted, so
	# the field contributes nothing and the laptop's edges melt into the room
	# instead of covering it with a rectangle.
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	laptop.material = additive
	laptop.modulate = Color(1.0, 1.0, 1.0)

	# Added art is see-through, so the room is pushed down under the machine
	# first, or the monitors behind it show through the lid.
	desk_shadow.texture = UiFx.radial_dot(64, 0.42)
	desk_shadow.modulate = Color(0, 0, 0, 0.55)
	screen_glow.texture = UiFx.radial_dot(96, 0.15)
	screen_glow.modulate = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.13)
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	screen_glow.material = glow_material

	var crt_material := ShaderMaterial.new()
	crt_material.shader = CRT_SHADER
	crt_material.set_shader_parameter("phosphor", PHOSPHOR)
	crt_overlay.material = crt_material
	crt_overlay.color = Color.WHITE

	glass.color = Color(0.027, 0.063, 0.055, 0.97)

	var menu_style := StyleBoxFlat.new()
	menu_style.bg_color = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.03)
	menu_style.border_color = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.26)
	menu_style.set_border_width_all(1)
	menu_style.set_corner_radius_all(0)
	menu_frame.add_theme_stylebox_override("panel", menu_style)
	header_rule.color = Color(PHOSPHOR.r, PHOSPHOR.g, PHOSPHOR.b, 0.26)

	header_label.text = "TOKEN_BURN %s" % _version()
	menu_title.text = "\u2500\u2500  MAIN MENU  \u2500\u2500"
	_refresh_clock()
	_build_embers()


## `AssetCatalog` reports the screen rects against the cropped picture, so the
## same crop has to be taken out of the texture or the glass lands low.
static func _cropped_art(data: Dictionary) -> Texture2D:
	var source: Variant = data.get("texture")
	if not source is Texture2D:
		return null
	var texture: Texture2D = source
	var top: float = float(data.get("crop_top", 0.0))
	var bottom: float = float(data.get("crop_height", 1.0))
	if top <= 0.001 and bottom >= 0.999:
		return texture
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	var full: Vector2 = texture.get_size()
	atlas.region = Rect2(0.0, full.y * top, full.x, full.y * (bottom - top))
	return atlas


func _build_embers() -> void:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(540, 20, 1)
	material.direction = Vector3(0, -1, 0)
	material.spread = 24.0
	material.initial_velocity_min = 18.0
	material.initial_velocity_max = 60.0
	material.gravity = Vector3(6, -12, 0)
	material.scale_min = 0.6
	material.scale_max = 2.0
	material.color = UiThemeBuilder.color("orange")
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = UiFx.ramp(
		[0.0, 0.2, 1.0],
		[Color(1, 1, 1, 0), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)]
	)
	material.color_ramp = ramp_texture
	embers.process_material = material
	embers.texture = UiFx.radial_dot(32)
	embers.amount = EMBER_COUNT
	embers.lifetime = 7.0
	embers.preprocess = 3.0
	embers.emitting = true


func _version() -> String:
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	return "v%s" % (version if version != "" else "0.1.0")


# --- Placing the machine and its glass ---------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout_stage()


## Places the laptop by hand rather than leaving it to the TextureRect's own
## aspect fitting, because the menu, the glow and the shadow are all positioned
## against wherever the picture actually landed.
func _layout_stage() -> void:
	var texture: Texture2D = laptop.texture
	if texture == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var art_size: Vector2 = texture.get_size()
	if art_size.x <= 0.0 or art_size.y <= 0.0:
		return
	_layout_backdrop()
	var contain: float = minf(size.x / art_size.x, size.y / art_size.y)
	var fit: float = (MACHINE_WIDTH * size.x) / (MACHINE_UV.size.x * art_size.x)
	fit = minf(fit, (size.y * MAX_ART_OVERFLOW) / art_size.y)
	fit = maxf(fit, contain)
	var drawn: Vector2 = art_size * fit
	# Positioned by the machine rather than by the file: the lid is centred across
	# the window and hung just below the top edge, and whatever black field that
	# leaves over is spent off the bottom.
	var origin := Vector2(
		size.x * 0.5 - (MACHINE_UV.position.x + MACHINE_UV.size.x * 0.5) * drawn.x,
		size.y * MACHINE_TOP - MACHINE_UV.position.y * drawn.y
	)
	var glass_rect := Rect2(origin + _glass_uv.position * drawn, _glass_uv.size * drawn)
	# On a handset the painted glass is a couple of centimetres tall, so the
	# whole machine is blown up around its screen until the menu can print at a
	# readable size — the keyboard runs off the frame as though the player were
	# leaning right over it. Desktop keeps the machine the artwork drew.
	var grow: float = _glass_grow(glass_rect)
	if grow > 1.001:
		var focus: Vector2 = glass_rect.get_center()
		drawn *= grow
		origin = focus + (origin - focus) * grow
		glass_rect = Rect2(origin + _glass_uv.position * drawn, _glass_uv.size * drawn)
		# Keep the grown glass on the window; the machine follows it.
		var shift := Vector2(
			clampf(
				glass_rect.position.x, 8.0, maxf(8.0, size.x - glass_rect.size.x - 8.0)
			) - glass_rect.position.x,
			clampf(
				glass_rect.position.y,
				size.y * 0.04,
				maxf(size.y * 0.04, size.y - glass_rect.size.y - 8.0)
			) - glass_rect.position.y
		)
		origin += shift
		glass_rect.position += shift
	laptop.position = origin
	laptop.size = drawn
	terminal.position = glass_rect.position
	terminal.size = glass_rect.size

	# The shadow is a soft blob over the machine's own footprint rather than the
	# whole picture, so the room keeps its corners. The glow is a tighter one over
	# the glass, so light appears to spill onto the bezel.
	var machine := Rect2(
		origin + MACHINE_UV.position * drawn, MACHINE_UV.size * drawn
	)
	desk_shadow.position = machine.position - machine.size * 0.05
	desk_shadow.size = machine.size * 1.1
	screen_glow.position = glass_rect.position - glass_rect.size * 0.2
	screen_glow.size = glass_rect.size * 1.4

	embers.position = Vector2(size.x * 0.5, size.y + 20.0)
	var ember_material: ParticleProcessMaterial = embers.process_material
	if ember_material != null:
		ember_material.emission_box_extents = Vector3(maxf(80.0, size.x * 0.5), 20, 1)

	var crt_material: ShaderMaterial = crt_overlay.material
	if crt_material != null:
		# Two device pixels per scanline, whatever the glass ended up being.
		crt_material.set_shader_parameter(
			"scanline_count", maxf(60.0, glass_rect.size.y * 0.5)
		)

	_apply_metrics(clampf(glass_rect.size.y / REFERENCE_GLASS, MIN_SCALE, MAX_SCALE))


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
	_mono(wordmark, _px(28), PHOSPHOR)
	_mono(tagline, _px(10), PHOSPHOR_DIM)
	_mono(menu_title, _px(10), PHOSPHOR_DIM)
	_mono(prompt_label, _px(12), PHOSPHOR)
	for child in boot_log.get_children():
		if child is Label:
			_mono(child as Label, _px(10), PHOSPHOR_DIM)
	for row in _rows:
		row.set_metrics(_px(13), _px(24), _px(8))
	for key in _panels:
		(_panels[key] as ConsolePanel).set_metrics(_scale)


## How far the machine has to be blown up for the menu on its glass to reach a
## readable physical size on this screen. 1.0 wherever the artwork already
## delivers that.
func _glass_grow(glass_rect: Rect2) -> float:
	var boost: float = ConsoleMetrics.stretch_compensation()
	if boost <= 1.2 or glass_rect.size.y <= 1.0:
		return 1.0
	var wanted_height: float = minf(
		REFERENCE_GLASS * clampf(boost, 1.0, MAX_SCALE), size.y * 0.88
	)
	return maxf(1.0, wanted_height / glass_rect.size.y)


## Covers the window with the room, biased up the picture so the crop keeps the
## desk rather than the empty floor beneath it.
func _layout_backdrop() -> void:
	var texture: Texture2D = backdrop.texture
	if texture == null:
		return
	var room: Vector2 = texture.get_size()
	if room.x <= 0.0 or room.y <= 0.0:
		return
	var drawn: Vector2 = room * maxf(size.x / room.x, size.y / room.y)
	backdrop.position = Vector2(
		(size.x - drawn.x) * 0.5, (size.y - drawn.y) * BACKDROP_FOCUS
	)
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
		row.set_metrics(_px(13), _px(24), _px(8))
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
