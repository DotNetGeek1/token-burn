class_name BoardProp
extends Button

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

## A readout painted onto something standing in the room.
##
## The desk artwork carries the housing — the thermometer's case, the meter box
## on the wall, the whiteboard, the phone — and this fills the window cut into
## it. That is the difference between a game with a HUD bolted on and a game
## whose HUD is furniture: nothing here floats, and every number is somewhere a
## person at that desk could actually read it.
##
## Props are placed by the shell from `board_scenes.<dwelling>.props` in the
## asset catalog, so where each one sits is a property of the picture rather
## than a constant in this script, and moving the operation to the garage moves
## every readout onto the garage's own furniture.

## Whiteboard marker, and the colour a line gets once it is crossed off. The
## board in the artwork is white, so the plan is written in ink rather than in
## the phosphor the recessed meters glow with.
const MARKER_INK := Color(0.16, 0.17, 0.20)
const MARKER_DONE := Color(0.10, 0.42, 0.24)
## The other pen on the tray, for the line that has stopped being a note to self
## and started being a problem.
const MARKER_URGENT := Color(0.66, 0.14, 0.16)
## Narrowest column the standing figures will be packed into, for a board with
## nothing else written on it yet to take the measure from.
const MIN_LEDGER_COLUMN := 14

## Catalog key this prop was built for. Only used for debugging and tooltips.
var prop_key: String = ""

var _caption: Label = null
var _value: Label = null
var _checklist: VBoxContainer = null
var _glow: float = 0.0
var _ringing: bool = false


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP if _is_interactive() else Control.MOUSE_FILTER_IGNORE
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, _face_style())
	var box := VBoxContainer.new()
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8.0
	box.offset_top = 5.0
	box.offset_right = -8.0
	box.offset_bottom = -5.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centred, because the window the artwork cut is the window the reading has
	# to land in; top-aligning it puts the number on the bezel.
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	add_child(box)
	_caption = _make_label(
		11,
		MARKER_INK if _is_whiteboard() else UiThemeBuilder.color("grey").lightened(0.35)
	)
	_caption.add_theme_font_override("font", UiThemeBuilder.mono_font())
	box.add_child(_caption)
	_value = _make_label(16, UiThemeBuilder.color("white"))
	_value.add_theme_font_override("font", UiThemeBuilder.mono_font())
	box.add_child(_value)
	_checklist = VBoxContainer.new()
	_checklist.name = "Checklist"
	_checklist.visible = false
	_checklist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_checklist.add_theme_constant_override("separation", 0)
	box.add_child(_checklist)
	resized.connect(_fit_to_housing)
	_fit_to_housing()


## The housing is whatever the artwork drew, and the artwork drew a meter box the
## size of a meter box. Type is sized to the window rather than the window being
## sized to the type, and on the smallest faces the caption goes entirely — the
## thing it is bolted to already says what it measures.
func _fit_to_housing() -> void:
	if _caption == null:
		return
	var viewport: Vector2 = get_viewport_rect().size
	# The viewport is in design units and expands past 900 on a phone, so the
	# platform is what decides this, not the canvas width.
	var mobile: bool = ConsoleMetrics.is_mobile() or viewport.x < 900.0
	var mobile_boost: float = 1.0
	if mobile:
		mobile_boost = maxf(1.3, ConsoleMetrics.stretch_compensation())
	var line_floor: int = 12 if mobile else 8
	var height: float = size.y
	if _is_whiteboard():
		height = maxf(height, viewport.y * 0.14)
	var box: Control = get_node_or_null("Box")
	if box != null:
		var inset: float = 6.0 if height < 60.0 else 8.0
		box.offset_left = inset
		box.offset_right = -inset
		box.offset_top = 3.0
		box.offset_bottom = -3.0
	_caption.visible = height >= 46.0
	var caption_max: int = 20 if _is_whiteboard() else 13
	var caption_min: int = 12 if mobile and _is_whiteboard() else 9
	_caption.add_theme_font_size_override(
		"font_size",
		clampi(int(height * 0.16 * mobile_boost), caption_min, caption_max)
	)
	_value.add_theme_font_size_override(
		"font_size", clampi(int(height * (0.3 if _caption.visible else 0.5)), 10, 20)
	)
	var columns: int = 1
	var written: int = 0
	for child in _checklist.get_children():
		var line: Label = child
		if not line.visible:
			continue
		written += 1
		columns = maxi(columns, line.text.length())
	# Sized against however many lines are actually on the board plus room for
	# the caption above them, rather than against a fixed guess: a board given
	# more to say has to write smaller, not run off the bottom of itself.
	var rows: float = maxf(8.5, float(written) + 2.0)
	var line_size: int = clampi(
		mini(int(height / rows), int((size.x - 16.0) / (float(columns) * 0.58))),
		line_floor,
		20
	)
	if mobile and _is_whiteboard():
		line_size = clampi(int(round(float(line_size) * mobile_boost)), line_floor, 20)
	for child in _checklist.get_children():
		(child as Label).add_theme_font_size_override("font_size", line_size)


## How wide the board is already being written, in characters. The plan and the
## contract are what set the column; the figures above them are packed to it.
func _column_budget(body: Array) -> int:
	var budget: int = MIN_LEDGER_COLUMN
	for row in body:
		budget = maxi(budget, str(row[0]).length())
	return budget


## Fits the standing figures onto as few lines as the board is wide enough for.
## Some rooms hang a narrow board, and a single long line of figures would be
## the widest thing on it — which would force the plan underneath to be written
## smaller to match, for the sake of a line nobody reads across.
func _pack_ledger(parts: Array, budget: int) -> Array:
	var packed: Array = []
	var current: String = ""
	for part in parts:
		var text: String = str(part)
		if text == "":
			continue
		if current == "":
			current = text
			continue
		var joined: String = "%s · %s" % [current, text]
		if joined.length() <= budget:
			current = joined
		else:
			packed.append(current)
			current = text
	if current != "":
		packed.append(current)
	return packed


## The phone rings the investor and the whiteboard carries his contract, so both
## are worth pressing; the rest are readouts, and a readout that eats a click on
## the desk behind it is a bug.
func _is_interactive() -> bool:
	return prop_key == "phone" or prop_key == "plan_board"


## The plan board is a whiteboard in the artwork, not an instrument: it has no
## glass to sink a reading into, and painting one over it was what made the
## board look like a widget stuck to the wall rather than something written on.
func _is_whiteboard() -> bool:
	return prop_key == "plan_board"


## Recessed window: near-black glass with a lip around it, so the reading looks
## sunk into the housing the artwork drew rather than printed on top of it. The
## whiteboard instead gets nothing at all, so the painted surface shows through
## and the plan reads as marker on the board.
func _face_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if _is_whiteboard():
		style.bg_color = Color(1, 1, 1, 0.0)
		style.set_corner_radius_all(0)
		return style
	var bay: Color = UiThemeBuilder.color("bay")
	style.bg_color = Color(bay.r, bay.g, bay.b, 0.78)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = UiThemeBuilder.color("stroke_dim")
	style.set_corner_radius_all(UiThemeBuilder.CARD_CORNER)
	return style


func _make_label(font_size: int, font_color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	# An outline is what keeps a lit reading legible against the dark inside of
	# its housing; on a white board it would only smear the marker.
	if not _is_whiteboard():
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	return label


## A single number on a device face: what it measures, and what it reads.
func set_readout(caption: String, value: String, value_color: Color) -> void:
	if _caption == null:
		return
	_checklist.visible = false
	_value.visible = true
	_caption.text = caption
	_value.text = value
	_value.add_theme_color_override("font_color", value_color)


## The plan on the wall. Each line is `[text, done]`; done lines are ticked and
## dimmed, so the board is a to-do list the run crosses off rather than a static
## piece of set dressing.
## `notes` are written underneath in the same marker but without a box, for
## things that are being tracked rather than ticked off — the investor's
## contract and how much of it is burned.
## `ledger` goes above the list, for the standing figures the board is kept in
## the corner of the eye for at all. It is given as separate figures rather than
## as finished lines so the board can pack them to its own width.
func set_checklist(
	caption: String,
	lines: Array,
	notes: Array = [],
	ledger: Array = [],
	ledger_ink: Color = MARKER_INK
) -> void:
	if _caption == null:
		return
	_caption.text = caption
	_value.visible = false
	_checklist.visible = true
	var body: Array = []
	for entry in lines:
		var row: Array = Array(entry)
		var done: bool = row.size() > 1 and bool(row[1])
		body.append(["%s %s" % ["[x]" if done else "[ ]", str(row[0])], done])
	if not notes.is_empty():
		body.append(["", false])
		for note in notes:
			body.append([str(note), false])
	var written: Array = []
	for line in _pack_ledger(ledger, _column_budget(body)):
		written.append([line, false, ledger_ink])
	if not ledger.is_empty() and not body.is_empty():
		written.append(["", false])
	written.append_array(body)
	while _checklist.get_child_count() < written.size():
		var line_label: Label = _make_label(11, MARKER_INK)
		line_label.add_theme_font_override("font", UiThemeBuilder.mono_font())
		_checklist.add_child(line_label)
	for index in range(_checklist.get_child_count()):
		var label: Label = _checklist.get_child(index)
		if index >= written.size():
			label.visible = false
			continue
		var row: Array = written[index]
		label.visible = true
		label.text = str(row[0])
		var ink: Color = MARKER_DONE if bool(row[1]) else MARKER_INK
		if row.size() > 2:
			ink = Color(row[2])
		label.add_theme_color_override("font_color", ink)
	# Sized once the lines are written, because how wide the longest one is is
	# what the type has to fit inside.
	_fit_to_housing()


## The phone lights up when the investor has something to say. Drawn rather than
## tweened so it keeps time with the rest of the room even while a burn is
## animating and tweens are being killed and restarted.
func set_ringing(ringing: bool) -> void:
	if _ringing == ringing:
		return
	_ringing = ringing
	set_process(ringing)
	if not ringing:
		_glow = 0.0
		queue_redraw()


func _process(delta: float) -> void:
	_glow = fmod(_glow + delta * 2.4, TAU)
	queue_redraw()


func _draw() -> void:
	if not _ringing:
		return
	var pulse: float = 0.35 + 0.4 * (0.5 + 0.5 * sin(_glow))
	var accent: Color = UiThemeBuilder.semantic("danger")
	draw_rect(
		Rect2(Vector2.ZERO, size),
		Color(accent.r, accent.g, accent.b, pulse * 0.28),
		true
	)
	draw_rect(
		Rect2(Vector2.ZERO, size),
		Color(accent.r, accent.g, accent.b, pulse),
		false,
		2.0
	)
