class_name BurnRig
extends VBoxContainer

## The machine the player is actually working.
##
## The board used to report a batch through four identical progress bars and a
## line of grey text, so the most dramatic thing in the game — spending money to
## cook your own hardware — looked like a form. This is the same data as a
## machine: output streams down a CRT, heat swings a needle, and the tower smokes,
## catches fire and sets off a beacon as it goes.
##
## It only presents state. Every number still comes from Simulation.

const BEACON_SCENE := preload("res://ui/board/alarm_beacon.tscn")
const CRT_SHADER := preload("res://ui/board/crt_screen.gdshader")

## Which workstation to draw when the run has not said yet.
const DEFAULT_STAGE := 1

## The bay takes every pixel the board can spare and the machine is scaled into it,
## so there is no empty band between the room and the desk. Only a floor is kept, so
## the shortest window still draws a rig rather than a sliver of one.
const MIN_BAY_HEIGHT := 300.0

## Gap kept between an overlay instrument and the edge of the bay.
const INSTRUMENT_PAD := 10.0

## How much of the way to filling the bay the artwork actually travels. Close to all
## the way: the bay is the scene now, so a machine that stops short of it leaves a
## gap where the room used to be cropped out.
const ART_ZOOM_BLEND := 0.94

## Empty band above the machine: the shelf the instruments are mounted on, and the
## only place the smoke can rise into before the bay clips it. Tall enough to clear
## the largest a dial ever gets, so no instrument ever lands on the machine.
const HEADROOM := 190.0

## Height of the band that blends the room into the artwork's own dark field.
const HORIZON_FADE := 150.0

## How wide the console has to be before the instruments are drawn at full size, and
## how far they are allowed to shrink on a narrow one.
const INSTRUMENT_FULL_WIDTH := 560.0
const INSTRUMENT_MIN_SCALE := 0.62

## Columns the terminal is sized to fit. The monitor glass is a fixed fraction of
## the artwork, so the only way to make the output bigger is to print less across:
## a narrow console with large type beats a wide one nobody can read.
const TERMINAL_COLUMNS := 20

const MAX_LINES := 8
const CHARS_PER_SECOND := 110.0
## Sized so the bar plus its percentage stays inside TERMINAL_COLUMNS.
const STATUS_CELLS := 12

# Heat fractions at which the rig starts to complain. Wisps of smoke are
# cosmetic early warning; the beacon and the flames are pinned to the throttle
# line the simulation actually enforces, so the machine looks in trouble exactly
# when it is in trouble.
const SMOKE_RATIO := 0.5
const HEAVY_SMOKE_RATIO := 0.75

@onready var bay: PanelContainer = $Bay
@onready var stage: Control = $Bay/Stage
@onready var horizon: TextureRect = $Bay/Stage/Horizon
@onready var workstation: TextureRect = $Bay/Stage/Workstation
@onready var tower_glow: TextureRect = $Bay/Stage/TowerGlow
@onready var smoke: GPUParticles2D = $Bay/Stage/Smoke
@onready var fire: GPUParticles2D = $Bay/Stage/Fire
@onready var screen: Control = $Bay/Stage/Screen
@onready var glass: ColorRect = $Bay/Stage/Screen/Glass
@onready var terminal: RichTextLabel = $Bay/Stage/Screen/Margin/VBox/Terminal
@onready var forecast_line: Label = $Bay/Stage/Screen/Margin/VBox/ForecastLine
@onready var status_line: Label = $Bay/Stage/Screen/Margin/VBox/StatusLine
@onready var progress_track: ColorRect = $Bay/Stage/Screen/ProgressTrack
@onready var progress_fill: ColorRect = $Bay/Stage/Screen/ProgressTrack/ProgressFill
@onready var crt: ColorRect = $Bay/Stage/Screen/Crt
@onready var heat_gauge: HeatGauge = $Bay/Stage/HeatGauge
@onready var quality_meter: RigMeter = $Bay/Stage/QualityMeter
@onready var deadline_meter: RigMeter = $Bay/Stage/DeadlineMeter

## Which workstation is currently on the desk, and everything the layout needs to
## know about that picture. Read from the catalog rather than from constants, so a
## new tier of art is content and not a code change.
var _stage: int = -1
var _stage_data: Dictionary = {}
## One per extra piece of glass the artwork has. The first screen is the terminal;
## the rest report the contracts the other machines are working.
var _lane_screens: Array = []

var _beacon: AlarmBeacon = null
var _lines: Array[Dictionary] = []
var _queue: Array[Dictionary] = []
var _typing: Dictionary = {}
var _typed_chars: float = 0.0
var _keystrokes: int = 0
var _cursor_on: bool = true
var _heat_ratio: float = 0.0
var _throttle_ratio: float = 0.8
var _fire_risk: bool = false
var _shake_origin: Vector2 = Vector2.ZERO
var _shake_tween: Tween = null


func _ready() -> void:
	stage.resized.connect(_layout_rig)
	_style_bay()
	_style_screen()
	_style_instruments()
	_build_particles()
	_build_beacon()
	set_stage(DEFAULT_STAGE)
	var blink := Timer.new()
	blink.wait_time = 0.5
	blink.timeout.connect(_toggle_cursor)
	add_child(blink)
	blink.start()
	_layout_rig()
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout_rig()


## Nothing: the bay used to be a painted alcove with a border, which drew a box
## around the machine and made the room behind it look like wallpaper on a
## different screen. Left bare, the office backdrop *is* the room the rig stands
## in, and the bay is only the rectangle that clips the machine's overhang.
##
## What that costs is a seam. The artwork's own field is flat and darker than the
## lit room, so its top edge ruled a line across the screen. The horizon is a band
## of that field colour fading up into the room, laid over the join, so the room
## sinks into the machine's shadow instead of stopping at an edge.
func _style_bay() -> void:
	bay.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	bay.custom_minimum_size.y = MIN_BAY_HEIGHT
	horizon.texture = _horizon_gradient()


## Reaches the artwork's field colour before the band runs out rather than only in
## its last row: a straight ramp still had a few per cent of lit room showing where
## it met the machine, which is all it takes to see the join as a line.
static func _horizon_gradient() -> GradientTexture2D:
	var field: Color = UiThemeBuilder.color("bay")
	var texture := GradientTexture2D.new()
	texture.gradient = UiFx.ramp(
		[0.0, 0.5, 0.78, 1.0],
		[
			Color(field.r, field.g, field.b, 0.0),
			Color(field.r, field.g, field.b, 0.4),
			field,
			field,
		]
	)
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 8
	texture.height = 256
	return texture


func _style_screen() -> void:
	glass.color = UiThemeBuilder.color("screen")
	var mono: Font = UiThemeBuilder.mono_font()
	if mono != null:
		terminal.add_theme_font_override("normal_font", mono)
		status_line.add_theme_font_override("font", mono)
		forecast_line.add_theme_font_override("font", mono)
	_fit_terminal_type()
	status_line.add_theme_color_override("font_color", UiThemeBuilder.color("green"))
	terminal.add_theme_color_override("default_color", UiThemeBuilder.color("green"))
	# The forecast is the one line that is rewritten rather than printed, so it
	# sits dimmer than the log above it and reads as a standing readout.
	forecast_line.add_theme_color_override(
		"font_color", UiThemeBuilder.color("green").darkened(0.28)
	)
	# A real fill strip along the bottom edge of the glass, under the CRT overlay,
	# so progress is legible at a glance without reading the ASCII meter.
	progress_track.color = Color(1, 1, 1, 0.09)
	progress_fill.color = UiThemeBuilder.color("green")
	progress_fill.anchor_right = 0.0
	# The log is meant to look like output scrolling past, not a document, so the
	# scrollbar is hidden and the view simply follows the newest line.
	terminal.get_v_scroll_bar().modulate.a = 0.0
	terminal.get_v_scroll_bar().custom_minimum_size = Vector2.ZERO
	var material := ShaderMaterial.new()
	material.shader = CRT_SHADER
	material.set_shader_parameter("phosphor", UiThemeBuilder.color("green"))
	crt.material = material
	crt.color = Color.WHITE


## The instruments are photographs of empty hardware with the reading painted into
## their recessed windows. Drawing them bare left three widgets floating over the
## artwork; in a housing they are bolted to the alcove like the machine is.
func _style_instruments() -> void:
	heat_gauge.set_housing(AssetCatalog.rig_instrument("dial"))
	var column: Dictionary = AssetCatalog.rig_instrument("column")
	quality_meter.set_housing(column)
	deadline_meter.set_housing(column)


func _build_beacon() -> void:
	_beacon = BEACON_SCENE.instantiate()
	stage.add_child(_beacon)
	# Centred on the instrument shelf, between the dial and the meters: the corners
	# are taken now, and from the middle its beams sweep across the whole machine
	# rather than raking one side of it.
	_beacon.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_beacon.offset_left = -48.0
	_beacon.offset_top = 8.0
	_beacon.offset_right = 48.0
	_beacon.offset_bottom = 104.0


func _build_particles() -> void:
	smoke.texture = _soft_dot()
	smoke.process_material = _smoke_material(Color(0.58, 0.58, 0.66), 30.0, 0.9, 2.4)
	smoke.amount = 40
	smoke.lifetime = 2.0
	smoke.emitting = false
	fire.texture = _soft_dot()
	fire.process_material = _smoke_material(UiThemeBuilder.color("orange"), 52.0, 0.5, 1.2)
	fire.amount = 30
	fire.lifetime = 0.8
	fire.emitting = false
	tower_glow.texture = _soft_dot()
	tower_glow.modulate = Color(1, 0.42, 0.14, 0.0)


func _smoke_material(
	tint: Color, speed: float, scale_min: float, scale_max: float
) -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(34, 4, 1)
	material.direction = Vector3(0, -1, 0)
	material.spread = 18.0
	material.initial_velocity_min = speed * 0.5
	material.initial_velocity_max = speed
	material.gravity = Vector3(10, -26, 0)
	material.scale_min = scale_min
	material.scale_max = scale_max
	material.damping_min = 8.0
	material.damping_max = 18.0
	material.color = tint
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = UiFx.ramp(
		[0.0, 0.18, 1.0],
		[Color(1, 1, 1, 0), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)]
	)
	material.color_ramp = ramp_texture
	return material


static func _soft_dot() -> Texture2D:
	return UiFx.radial_dot()


# --- Hardware ----------------------------------------------------------------

## Puts a different machine on the desk. The run's hardware decides which one, so
## buying a second desktop or a rack is visible on the board it is bought for
## rather than only in the market's inventory.
func set_stage(stage_index: int) -> void:
	var wanted: int = clampi(stage_index, 1, 5)
	if wanted == _stage:
		return
	var data: Dictionary = AssetCatalog.rig_stage(wanted)
	if data.is_empty():
		return
	# Announced only if the machine has already been printing. The board sets the
	# stage before it boots the terminal, so a run resumed on a rack does not open
	# by claiming its hardware just changed.
	var upgraded: bool = _stage > 0 and wanted > _stage and not _lines.is_empty()
	_stage = wanted
	_stage_data = data
	workstation.texture = _cropped_art(data)
	_build_lane_screens(maxi(0, _screen_rects().size() - 1))
	if upgraded:
		push_line("$ hardware changed · rig rebuilt", "compute")
	_layout_rig()


func stage_index() -> int:
	return _stage


func _screen_rects() -> Array:
	return Array(_stage_data.get("screens", []))


static func _cropped_art(data: Dictionary) -> Texture2D:
	var source: Texture2D = data.get("texture")
	if source == null:
		return null
	var top: float = float(data.get("crop_top", 0.0))
	var bottom: float = float(data.get("crop_height", 1.0))
	if top <= 0.001 and bottom >= 0.999:
		return source
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	var full: Vector2 = source.get_size()
	atlas.region = Rect2(0.0, full.y * top, full.x, full.y * (bottom - top))
	return atlas


## The artwork's spare glass, one panel per extra screen it was drawn with. Built
## from the picture rather than from the machine count: how many monitors are on
## the desk is a fact about the art, and what is reported on them is a fact about
## the run.
func _build_lane_screens(wanted: int) -> void:
	while _lane_screens.size() > wanted:
		var spare: LaneScreen = _lane_screens.pop_back()
		spare.queue_free()
	while _lane_screens.size() < wanted:
		var panel := LaneScreen.new()
		panel.build(CRT_SHADER)
		# Behind the instruments and the beacon, which are mounted on the bay.
		stage.add_child(panel)
		stage.move_child(panel, screen.get_index() + 1)
		_lane_screens.append(panel)


## Pins the terminal, the smoke and the glow onto the machine wherever the
## artwork actually landed after aspect-fitting.
func _layout_rig() -> void:
	var texture: Texture2D = workstation.texture
	if texture == null or size.x <= 0.0:
		return
	var texture_size: Vector2 = texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	if stage.size.x <= 0.0 or stage.size.y <= HEADROOM:
		return
	# The artwork is placed by hand rather than left to the TextureRect's own
	# aspect fitting, because everything else on the rig is positioned against it.
	var available := Vector2(stage.size.x, stage.size.y - HEADROOM)
	var contain: float = minf(available.x / texture_size.x, available.y / texture_size.y)
	var cover: float = maxf(available.x / texture_size.x, available.y / texture_size.y)
	# The rig takes whatever height the board can spare, which is usually more than
	# the art's aspect wants. Rather than leave the machine small in an empty room
	# it is scaled up toward covering the bay and the bay clips the overhang.
	#
	# How far it may go is a fact about the picture: past the point where the art's
	# safe width no longer fits across the bay, the crop starts eating the machine
	# instead of the black around it, and the bay reads as a crop of a photograph.
	var safe: float = float(_stage_data.get("safe_width", 1.0))
	var crop_limit: float = available.x / maxf(1.0, texture_size.x * safe)
	var fit: float = lerpf(contain, minf(cover, maxf(contain, crop_limit)), ART_ZOOM_BLEND)
	var drawn: Vector2 = texture_size * fit
	# Bottom-aligned rather than centred: when the bay is taller than the art the
	# leftover belongs above the machine, where the instruments and the beacon are
	# mounted and where smoke has somewhere to go. Centring it would split that
	# shelf into two half-height voids and put the machine off the floor.
	var origin := Vector2(
		(stage.size.x - drawn.x) * 0.5, stage.size.y - drawn.y
	)
	workstation.position = origin
	workstation.size = drawn
	# Sits on the machine's top edge and runs up into the room, so the two dark
	# fields meet in a gradient rather than on a line. Never taller than the shelf
	# it fades into, or it would wash the instruments out.
	var fade: float = minf(HORIZON_FADE, origin.y)
	horizon.position = Vector2(0.0, origin.y - fade)
	horizon.size = Vector2(stage.size.x, fade)
	var rects: Array = _screen_rects()
	if not rects.is_empty():
		var glass_rect: Rect2 = rects[0]
		screen.position = origin + glass_rect.position * drawn
		screen.size = glass_rect.size * drawn
	for index in range(_lane_screens.size()):
		var panel: LaneScreen = _lane_screens[index]
		if index + 1 >= rects.size():
			panel.visible = false
			continue
		var panel_rect: Rect2 = rects[index + 1]
		panel.visible = true
		panel.position = origin + panel_rect.position * drawn
		panel.size = panel_rect.size * drawn
		panel.fit_type()
	var vent: Vector2 = _stage_data.get("vent", Vector2(0.5, 0.1))
	var tower: Vector2 = origin + vent * drawn
	smoke.position = tower
	fire.position = tower
	tower_glow.size = Vector2(drawn.x * 0.3, drawn.x * 0.3)
	tower_glow.position = tower - tower_glow.size * Vector2(0.5, 0.5)
	_fit_terminal_type()
	_layout_instruments()
	_shake_origin = stage.position


## Sets the terminal type from the width of the monitor glass rather than from a
## fixed size. The glass is a fraction of the artwork, so a fixed size that reads
## well on one canvas spills outside the bezel on a smaller one; sizing to a
## column count keeps the output as large as it can be and still fit the machine.
func _fit_terminal_type() -> void:
	var mono: Font = UiThemeBuilder.mono_font()
	if mono == null or screen.size.x <= 0.0:
		return
	# Both horizontal margins on the glass, from the scene.
	var inner: float = screen.size.x - 20.0
	# Measured rather than assumed: the advance width of a monospace glyph is the
	# only thing that decides how many columns fit.
	var advance: float = mono.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x / 100.0
	if advance <= 0.0:
		return
	var body: int = int(clampf(inner / (advance * float(TERMINAL_COLUMNS)), 13.0, 30.0))
	terminal.add_theme_font_size_override("normal_font_size", body)
	status_line.add_theme_font_size_override("font_size", body)
	forecast_line.add_theme_font_size_override("font_size", maxi(body - 2, 12))


## The instruments are mounted along the top of the bay: the heat dial in the left
## corner, quality and deadline in the right. They used to stand on the floor beside
## the machine, which put the three brightest things on the board in the same band
## as the keys and left the shelf above the machine empty. On the shelf they read as
## panel-mounted gear in the room, and the machine gets the floor to itself.
func _layout_instruments() -> void:
	# Instruments shrink on a narrow window so they never eat the machine.
	var scale: float = clampf(
		stage.size.x / INSTRUMENT_FULL_WIDTH, INSTRUMENT_MIN_SCALE, 1.0
	)
	# Both instruments are sized to their housing's aspect: the art is a photograph
	# of a plate, and a plate stretched to a different shape stops reading as one.
	var gauge := Vector2(164.0, 164.0) * scale
	# `size` is clamped by the combined minimum, so the authored floor has to come
	# down first or the instruments never shrink.
	heat_gauge.custom_minimum_size = gauge
	heat_gauge.size = gauge
	heat_gauge.position = Vector2(INSTRUMENT_PAD, INSTRUMENT_PAD)

	var meter := Vector2(112.0, 149.0) * scale
	for instrument in [quality_meter, deadline_meter]:
		instrument.custom_minimum_size = meter
		instrument.size = meter
	# Side by side and bottom-aligned with the dial, so the three of them share one
	# shelf line rather than stepping down the corner.
	var top: float = INSTRUMENT_PAD + gauge.y - meter.y
	var right: float = stage.size.x - meter.x - INSTRUMENT_PAD
	deadline_meter.position = Vector2(right, top)
	quality_meter.position = Vector2(right - meter.x - INSTRUMENT_PAD, top)


# --- Terminal ----------------------------------------------------------------

## Replaces the log with a fresh banner. Called when the focused contract
## changes, so the screen always describes the job in front of it.
func boot(job_name: String, detail: String) -> void:
	_lines.clear()
	_queue.clear()
	_typing = {}
	push_line("$ burn --target \"%s\"" % job_name, "grey")
	if detail != "":
		push_line(detail, "compute")
	_render()


func push_line(text: String, role: String = "success") -> void:
	_queue.append({"text": text, "role": role})


## Skips the typing animation, for refreshes that are not part of a burn.
func flush_lines() -> void:
	if not _typing.is_empty():
		_lines.append(_typing)
		_typing = {}
	while not _queue.is_empty():
		_lines.append(_queue.pop_front())
	_trim()
	_render()


func _process(delta: float) -> void:
	if _typing.is_empty() and not _queue.is_empty():
		_typing = _queue.pop_front()
		_typing["shown"] = 0
		_typed_chars = 0.0
	if _typing.is_empty():
		return
	_typed_chars += delta * CHARS_PER_SECOND
	var full: String = str(_typing.get("text", ""))
	var shown: int = mini(full.length(), int(_typed_chars))
	if shown != int(_typing.get("shown", 0)):
		_typing["shown"] = shown
		_render()
		_keystrokes += 1
		if _keystrokes % 6 == 0:
			UiSound.play("key")
	if shown >= full.length():
		_lines.append({"text": full, "role": _typing.get("role", "success")})
		_typing = {}
		_trim()
		_render()


func _trim() -> void:
	while _lines.size() > MAX_LINES:
		_lines.pop_front()


func _toggle_cursor() -> void:
	_cursor_on = not _cursor_on
	_render()


func _render() -> void:
	if terminal == null:
		return
	var out: PackedStringArray = []
	for line in _lines:
		out.append(_format_line(str(line.get("text", "")), str(line.get("role", "success"))))
	if not _typing.is_empty():
		var full: String = str(_typing.get("text", ""))
		var shown: int = int(_typing.get("shown", 0))
		out.append(_format_line(full.substr(0, shown), str(_typing.get("role", "success"))))
	var cursor: String = "[color=#%s]_[/color]" % UiThemeBuilder.color("green").to_html(false)
	terminal.text = "\n".join(out) + (cursor if _cursor_on else " ")


func _format_line(text: String, role: String) -> String:
	return "[color=#%s]%s[/color]" % [UiThemeBuilder.semantic(role).to_html(false), text]


# --- Readouts ----------------------------------------------------------------

func set_job(job: Dictionary) -> void:
	if job.is_empty():
		status_line.text = "[ NO CONTRACT LOADED ]"
		_set_progress(0.0)
		return
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var remaining: float = maxf(0.0, float(job.get("tokens_remaining", 0.0)))
	var done: float = requirement - remaining
	# An ASCII meter belongs on a terminal in a way a rounded bar does not, and it
	# gives the screen a readout that survives the CRT overlay.
	var ratio: float = clampf(done / requirement, 0.0, 1.0)
	var filled: int = int(round(ratio * STATUS_CELLS))
	status_line.text = "[%s%s] %3d%%" % [
		"#".repeat(filled),
		"-".repeat(STATUS_CELLS - filled),
		int(round(ratio * 100.0)),
	]
	_set_progress(ratio)


## Slides the fill strip along the bottom of the glass. Driven by the right
## anchor rather than by width so it keeps up with the monitor being re-laid out.
func _set_progress(ratio: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(progress_fill, "anchor_right", ratio, 0.3).set_ease(Tween.EASE_OUT)


## Quality and deadline, mounted on the case beside the monitor.
func set_meters(
	quality: float,
	quality_target: float,
	prompts_left: int,
	deadline_prompts: int,
	quality_readout: String = ""
) -> void:
	quality_meter.visible = true
	deadline_meter.visible = true
	if quality_readout == "":
		quality_readout = "%d/%d" % [int(round(quality)), int(round(quality_target))]
	quality_meter.setup(
		"QUAL", quality, maxf(1.0, quality_target), "quality", quality_readout
	)
	deadline_meter.setup(
		"TIME", float(maxi(0, prompts_left)), float(maxi(1, deadline_prompts)), "deadline",
		"%d pr" % maxi(0, prompts_left)
	)


func hide_meters() -> void:
	quality_meter.visible = false
	deadline_meter.visible = false


## Pulses the quality meter, for a burn stage that moved it.
func pulse_quality() -> void:
	quality_meter.pulse()


## What the run's other machines are working, printed on the artwork's other
## monitors. The focused contract owns the terminal, so these are the lanes a burn
## would also advance — the ones that used to be invisible unless the player
## counted the "1 of N lanes" note on the forecast line.
func set_lanes(lanes: Array) -> void:
	for index in range(_lane_screens.size()):
		var panel: LaneScreen = _lane_screens[index]
		if index < lanes.size():
			panel.show_lane(index + 2, lanes[index])
		else:
			panel.show_idle(index + 2)


func set_throughput(text: String) -> void:
	forecast_line.text = text
	forecast_line.visible = text != ""


## Heat drives everything physical about the rig, so it is applied in one place:
## the needle, the smoke, the fire, the glow and the beacon.
##
## `throttle_ratio` is the line at which the simulation starts cutting output and
## `fire_risk` is its "this can now destroy hardware" flag, both passed in so the
## visuals never drift from the rules.
func set_heat(
	heat: float, capacity: float, throttle_ratio: float = 0.8, fire_risk: bool = false
) -> void:
	var safe_capacity: float = maxf(1.0, capacity)
	_heat_ratio = clampf(heat / safe_capacity, 0.0, 1.4)
	_throttle_ratio = clampf(throttle_ratio, 0.2, 1.0)
	_fire_risk = fire_risk
	heat_gauge.setup(heat, safe_capacity)
	_apply_heat_fx()


func _apply_heat_fx() -> void:
	var smoking: bool = _heat_ratio >= SMOKE_RATIO
	smoke.emitting = smoking
	if smoking:
		var weight: float = clampf(
			(_heat_ratio - SMOKE_RATIO) / maxf(0.01, HEAVY_SMOKE_RATIO - SMOKE_RATIO), 0.0, 1.6
		)
		smoke.amount_ratio = clampf(0.25 + weight * 0.75, 0.1, 1.0)
		smoke.speed_scale = lerpf(0.75, 1.5, clampf(weight, 0.0, 1.0))
	# Flames mean the throttle has engaged: output is being cut right now.
	var burning: bool = _heat_ratio >= _throttle_ratio
	fire.emitting = burning
	if burning:
		fire.amount_ratio = clampf((_heat_ratio - _throttle_ratio) / 0.2 + 0.35, 0.2, 1.0)
	var glow: float = clampf((_heat_ratio - HEAVY_SMOKE_RATIO) / 0.3, 0.0, 1.0) * 0.55
	var glow_tween: Tween = create_tween()
	glow_tween.tween_property(tower_glow, "modulate:a", glow, 0.4)
	var severity: float = 1.0 if _fire_risk else clampf(
		(_heat_ratio - _throttle_ratio) / maxf(0.05, 1.0 - _throttle_ratio), 0.0, 1.0
	)
	_beacon.set_alarm(burning or _fire_risk, severity)


func alarm_active() -> bool:
	return _beacon != null and _beacon.visible


# --- Feedback ----------------------------------------------------------------

## Each landed stage thumps the machine. Small enough not to hurt to read,
## big enough that a five stage pipeline feels like five hits.
func shake(strength: float = 6.0) -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	for i in range(4):
		var falloff: float = strength * (1.0 - float(i) / 4.0)
		var offset := Vector2(randf_range(-falloff, falloff), randf_range(-falloff, falloff))
		_shake_tween.tween_property(stage, "position", _shake_origin + offset, 0.05)
	_shake_tween.tween_property(stage, "position", _shake_origin, 0.06)


## Lights the glass for an instant, so a stage landing is felt on the screen and
## not only in the text that scrolls past.
func flash_screen(role: String = "compute") -> void:
	var accent: Color = UiThemeBuilder.semantic(role)
	glass.color = UiThemeBuilder.color("screen").lerp(accent, 0.4)
	var tween: Tween = create_tween()
	tween.tween_property(glass, "color", UiThemeBuilder.color("screen"), 0.35)


## One of the artwork's spare monitors, reporting a contract the player is not
## looking at. Built in code rather than as a scene because the number of them is
## a property of the picture, and because it is a pane of glass, four lines of
## monospace and the same CRT overlay the terminal wears.
class LaneScreen:
	extends Control

	## Columns the readout is sized to fit, matching how the terminal picks its
	## type: these panels are much narrower than the main glass, so a fixed size
	## either overflows the bezel or wastes it.
	const COLUMNS := 16
	const CELLS := 8
	const PADDING := 6.0

	var _glass: ColorRect = null
	var _label: Label = null
	var _crt: ColorRect = null

	func build(shader: Shader) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		_glass = ColorRect.new()
		_glass.color = UiThemeBuilder.color("screen")
		_glass.set_anchors_preset(Control.PRESET_FULL_RECT)
		_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_glass)
		_label = Label.new()
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.offset_left = PADDING
		_label.offset_top = PADDING
		_label.offset_right = -PADDING
		_label.offset_bottom = -PADDING
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_label.clip_text = true
		var mono: Font = UiThemeBuilder.mono_font()
		if mono != null:
			_label.add_theme_font_override("font", mono)
		# Dimmer than the terminal's phosphor: this is a machine being watched
		# rather than the one being typed at.
		_label.add_theme_color_override(
			"font_color", UiThemeBuilder.color("green").darkened(0.3)
		)
		add_child(_label)
		_crt = ColorRect.new()
		_crt.set_anchors_preset(Control.PRESET_FULL_RECT)
		_crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crt.color = Color.WHITE
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("phosphor", UiThemeBuilder.color("green"))
		_crt.material = material
		add_child(_crt)

	func fit_type() -> void:
		var mono: Font = UiThemeBuilder.mono_font()
		if mono == null or _label == null or size.x <= 0.0:
			return
		var advance: float = mono.get_string_size(
			"0", HORIZONTAL_ALIGNMENT_LEFT, -1, 100
		).x / 100.0
		if advance <= 0.0:
			return
		var room: float = size.x - PADDING * 2.0
		_label.add_theme_font_size_override(
			"font_size", int(clampf(room / (advance * float(COLUMNS)), 10.0, 22.0))
		)

	func show_idle(lane_number: int) -> void:
		_label.text = "$ lane %d\nidle" % lane_number

	func show_lane(lane_number: int, job: Dictionary) -> void:
		var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
		var remaining: float = maxf(0.0, float(job.get("tokens_remaining", 0.0)))
		var ratio: float = clampf((requirement - remaining) / requirement, 0.0, 1.0)
		var filled: int = int(round(ratio * float(CELLS)))
		var prompts: int = maxi(0, int(job.get("prompts_remaining", 0)))
		_label.text = "\n".join([
			"$ lane %d" % lane_number,
			str(job.get("name", "contract")).to_lower().left(COLUMNS),
			"[%s%s]%3d%%" % [
				"#".repeat(filled), "-".repeat(CELLS - filled), int(round(ratio * 100.0))
			],
			"%d pr left" % prompts,
		])
