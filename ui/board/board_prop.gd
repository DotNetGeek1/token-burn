class_name BoardProp
extends Button

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
##
## Both pens are darker than a screen palette would pick. The board is lit by a
## desk lamp at night rather than by an office ceiling, so it renders as a mid
## grey: a green at screen brightness lands on almost exactly the board's own
## luminance and disappears, however green it looks against a white page.
const MARKER_INK := Color(0.09, 0.10, 0.12)
const MARKER_DONE := Color(0.04, 0.18, 0.09)
## The other pen on the tray, for the line that has stopped being a note to self
## and started being a problem.
const MARKER_URGENT := Color(0.48, 0.07, 0.09)
## Narrowest column the standing figures will be packed into, for a board with
## nothing else written on it yet to take the measure from.
const MIN_LEDGER_COLUMN := 14
## How tall a written line stands against the size of its type.
const LINE_HEIGHT := 1.35

## Catalog key this prop was built for. Only used for debugging and tooltips.
var prop_key: String = ""

var _caption: Label = null
var _value: Label = null
var _checklist: VBoxContainer = null
var _plane_node: Node2D = null
## Corners of the surface the readout is painted on, in this prop's own 0..1
## space. Empty for a prop that faces the camera.
var _plane: PackedVector2Array = PackedVector2Array()
## Fractions of the face something else is using. The whiteboard hangs the menu
## on itself — down one side of a wide board, across the bottom of a narrow one
## — and the plan is written in what is left.
var _reserved := Vector2.ZERO
var _glow: float = 0.0
var _ringing: bool = false


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP if _is_interactive() else Control.MOUSE_FILTER_IGNORE
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, _face_style())
	# The readout hangs off a Node2D rather than being anchored to the face,
	# because a prop lying flat on the desk needs its content sheared into the
	# picture's plane and only a Node2D carries an arbitrary transform. With no
	# plane measured the transform is the identity and this is a plain inset box.
	_plane_node = Node2D.new()
	_plane_node.name = "Plane"
	add_child(_plane_node)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centred, because the window the artwork cut is the window the reading has
	# to land in; top-aligning it puts the number on the bezel.
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	_plane_node.add_child(box)
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
	var face: Vector2 = _face_size()
	var height: float = face.y
	if _is_whiteboard():
		height = maxf(height, viewport.y * 0.14)
	_place_box(6.0 if height < 60.0 else 8.0)
	_caption.visible = height >= 46.0
	# Everything here is sized to the surface it is written on and nothing else.
	# A handset used to inflate it, because the board was a centimetre of a
	# picture and the marker would otherwise have been invisible; the player
	# leans the room in on the board now, which grows the board itself, so type
	# written larger than the board is only type written off the edge of it.
	var caption_max: int = 40 if _is_whiteboard() else 13
	# Fitted to the width as well as the height. The caption is the one line
	# nobody chose the wording of at runtime, so a face too narrow for it used
	# to write "BURN PLAN" as "BURN P" rather than write it a size smaller.
	var caption_width: float = (face.x - 12.0) / maxf(4.0, float(_caption.text.length()) * 0.55)
	_caption.add_theme_font_size_override(
		"font_size", clampi(int(minf(height * 0.16, caption_width)), 9, caption_max)
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
	# more to say has to write smaller, not run off the bottom of itself. A
	# written line stands taller than its type is big, so the count is paid for
	# at the line height rather than at the font size.
	var rows: float = maxf(8.0, float(written) + 1.0) * LINE_HEIGHT
	var line_size: int = clampi(
		mini(int(height / rows), int((face.x - 16.0) / (float(columns) * 0.58))),
		8,
		40 if _is_whiteboard() else 20
	)
	for child in _checklist.get_children():
		(child as Label).add_theme_font_size_override("font_size", line_size)


## Keeps a strip down the right of this prop's face, or along the bottom of it,
## clear for something else to be mounted on. The prop still covers its whole
## rect — the whiteboard's own surface has to reach its frame — but nothing is
## written into the reserved part.
func reserve(right: float, bottom: float) -> void:
	var reserved := Vector2(clampf(right, 0.0, 0.9), clampf(bottom, 0.0, 0.9))
	if reserved.is_equal_approx(_reserved):
		return
	_reserved = reserved
	_fit_to_housing()


## The surface this prop's readout is painted on, as four corners in the prop's
## own 0..1 space: top-left, top-right, bottom-right, bottom-left. Set by the
## shell from the room's catalog entry.
func set_plane(corners: PackedVector2Array) -> void:
	_plane = corners if corners.size() == 4 else PackedVector2Array()
	_fit_to_housing()


## How big the painted surface is in pixels. For a prop facing the camera that
## is the prop's own rect; for one lying flat it is the length of the plane's
## edges, which is what the type has to fit between.
func _face_size() -> Vector2:
	var face: Vector2 = size
	if _plane.size() == 4:
		face = Vector2(
			((_plane[1] - _plane[0]) * size).length(), ((_plane[3] - _plane[0]) * size).length()
		)
	return face * (Vector2.ONE - _reserved)


## Lays the readout onto the surface. With no plane this is an inset box on the
## prop's face; with one, the box is built at the plane's own dimensions and
## then mapped onto it, so the type is rendered upright at its natural size and
## sheared into the picture rather than drawn small and stretched.
func _place_box(inset: float) -> void:
	var box: Control = _plane_node.get_node_or_null("Box") if _plane_node != null else null
	if box == null:
		return
	var face: Vector2 = _face_size()
	if _plane.size() != 4:
		_plane_node.transform = Transform2D.IDENTITY
		box.position = Vector2(inset, 3.0)
		box.size = Vector2(maxf(1.0, face.x - inset * 2.0), maxf(1.0, face.y - 6.0))
		return
	var origin: Vector2 = _plane[0] * size
	var across: Vector2 = (_plane[1] - _plane[0]) * size
	var down: Vector2 = (_plane[3] - _plane[0]) * size
	if across.length() < 1.0 or down.length() < 1.0:
		return
	_plane_node.transform = Transform2D(across.normalized(), down.normalized(), origin)
	box.position = Vector2(inset, inset)
	box.size = Vector2(maxf(1.0, face.x - inset * 2.0), maxf(1.0, face.y - inset * 2.0))


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
		# The board is the one prop that is read rather than glanced at, and the
		# artwork lights it for a room at night: a dark grey surface no marker
		# can get real contrast against. This is the board catching a little
		# more of the desk lamp than the photograph gave it — enough to write
		# on, and short of the flat panel that used to make it look like a
		# widget screwed to the wall.
		style.bg_color = Color(1, 1, 1, 0.20)
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
