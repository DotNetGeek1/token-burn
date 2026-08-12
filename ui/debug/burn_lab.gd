extends ConsoleOverlay

## The tuning bench: the multipliers the simulation is currently running on, the
## last few effects it resolved, and a batch runner to sanity-check a change
## against a thousand runs.
##
## This is a debug tool rather than a screen in the fiction, but it is still the
## same machine talking, so it prints in the same phosphor as everything else and
## the reload and batch commands sit in the footer where every other console
## screen keeps its commands.

const BATCH_RUNS := 1000
## Only the tail of the trace is worth reading; the resolver keeps far more than
## fits on the glass.
const TRACE_LINES := 30
const KNOB_STEP := 0.1

## The tuning knobs, in the order the bench prints them.
const KNOBS := [
	{"key": "economy_multiplier", "label": "ECONOMY MULTIPLIER", "min": 0.5, "max": 3.0},
	{"key": "token_multiplier", "label": "TOKEN MULTIPLIER", "min": 0.5, "max": 3.0},
	{"key": "cloud_cost_multiplier", "label": "CLOUD COST MULTIPLIER", "min": 0.0, "max": 3.0},
	{
		"key": "event_probability_multiplier",
		"label": "EVENT PROBABILITY MULTIPLIER",
		"min": 0.0,
		"max": 3.0,
	},
]

var _captions: Array[Label] = []
var _sliders: Dictionary = {}
var _readouts: Dictionary = {}
var _trace_caption: Label = null
var _trace: ConsoleTable = null
## The last batch result, kept so it survives the trace being rebuilt under it.
var _batch_note: String = ""


func _ready() -> void:
	super._ready()
	setup("Burn Lab")
	set_context("DEBUG TUNING", ConsoleStyle.WARNING)
	_build_body()


func _build_body() -> void:
	var body: VBoxContainer = content()

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)

	for knob in KNOBS:
		_build_knob(column, knob)

	_trace_caption = ConsoleStyle.label(
		"EFFECT TRACE · LATEST", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	column.add_child(_trace_caption)

	_trace = ConsoleTable.new()
	_trace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_trace)
	_trace.set_columns([
		{"label": "operation", "weight": 1.4},
		{"label": "target", "weight": 1.4},
		{"label": "after", "weight": 1.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	])

	_refresh_actions()


func _build_knob(column: VBoxContainer, knob: Dictionary) -> void:
	var key: String = str(knob["key"])

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	var caption: Label = ConsoleStyle.label(
		str(knob["label"]), ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(caption)
	_captions.append(caption)

	var readout: Label = ConsoleStyle.label("", ConsoleStyle.FONT_SMALL)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(readout)
	_readouts[key] = readout

	var slider := _slider(float(knob["min"]), float(knob["max"]))
	column.add_child(slider)
	slider.value_changed.connect(_on_knob_changed.bind(key))
	_sliders[key] = slider


## An HSlider in the console language: a hairline track with a square phosphor
## grabber, because the default theme's rounded pill belongs to the app palette
## these screens deliberately ignore.
func _slider(minimum: float, maximum: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = KNOB_STEP
	slider.custom_minimum_size = Vector2(0, 20)
	slider.add_theme_stylebox_override("slider", ConsoleStyle.frame_box(0.24, 0.03))
	slider.add_theme_stylebox_override("grabber_area", _fill_box(0.45))
	slider.add_theme_stylebox_override("grabber_area_highlight", _fill_box(0.7))
	var grabber: Texture2D = _grabber_texture(ConsoleStyle.PHOSPHOR)
	for item in ["grabber", "grabber_highlight", "grabber_disabled"]:
		slider.add_theme_icon_override(item, grabber)
	return slider


func _fill_box(alpha: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(
		ConsoleStyle.PHOSPHOR.r, ConsoleStyle.PHOSPHOR.g, ConsoleStyle.PHOSPHOR.b, alpha
	)
	box.set_corner_radius_all(0)
	return box


func _grabber_texture(color: Color) -> Texture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([color, color])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 6
	texture.height = 16
	return texture


func refresh() -> void:
	for knob in KNOBS:
		var key: String = str(knob["key"])
		var slider: HSlider = _sliders[key]
		slider.value = float(Simulation.tuning.get(key, 1.0))
		_refresh_readout(key)
	_refresh_trace()
	_apply_body_metrics()


func fit_console() -> void:
	super.fit_console()
	_apply_body_metrics()


## The body's own widgets are not part of the shell, so they are re-scaled
## alongside it whenever the room is laid out.
func _apply_body_metrics() -> void:
	var scale: float = console_scale()
	var font_tiny: int = ConsoleMetrics.font_tiny(scale)
	var font_small: int = ConsoleMetrics.font_small(scale)
	for caption in _captions:
		caption.add_theme_font_size_override("font_size", font_tiny)
	if _trace_caption != null:
		_trace_caption.add_theme_font_size_override("font_size", font_tiny)
	for readout in _readouts.values():
		(readout as Label).add_theme_font_size_override("font_size", font_small)
	for slider in _sliders.values():
		(slider as HSlider).custom_minimum_size = Vector2(0, ConsoleMetrics.px(20, scale))
	if _trace != null:
		_trace.set_metrics(scale)


func _refresh_actions() -> void:
	set_actions([
		{"index": "R", "headline": "HOT RELOAD CONTENT", "pressed": _reload_content},
		{
			"index": "B",
			"headline": "RUN BATCH SIMULATIONS",
			"value": "%d RUNS" % BATCH_RUNS,
			"pressed": _run_batch,
		},
	])


func _on_knob_changed(value: float, key: String) -> void:
	Simulation.set_tuning(key, value)
	_refresh_readout(key)


func _refresh_readout(key: String) -> void:
	var readout: Label = _readouts[key]
	readout.text = "%.1f×" % float(_sliders[key].value)


func _reload_content() -> void:
	ContentDatabase.reload()
	_refresh_trace()


func _refresh_trace() -> void:
	_trace.clear()
	var entries: Array = Simulation.effect_resolver.get_trace().slice(-TRACE_LINES)
	for entry in entries:
		_trace.add_row([
			str(entry.get("operation", "")),
			{"text": str(entry.get("target", "")), "color": ConsoleStyle.PHOSPHOR_DIM},
			str(entry.get("after", "")),
		])
	if entries.is_empty():
		_trace.add_note("NO EFFECTS RESOLVED YET")
	if _batch_note != "":
		_trace.add_note(_batch_note, ConsoleStyle.WARNING)


func _run_batch() -> void:
	var runner := BatchRunner.new()
	var summary: Dictionary = runner.run(BATCH_RUNS, "random")
	_batch_note = "BATCH: %d RUNS, WIN RATE %.1f%%" % [
		int(summary.get("runs", 0)), float(summary.get("win_rate", 0.0)) * 100.0
	]
	_refresh_trace()
	_apply_body_metrics()
