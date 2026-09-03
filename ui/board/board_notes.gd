class_name BoardNotes
extends Control

const PostItNoteScript := preload("res://ui/board/post_it_note.gd")

## The main menu, as notes stuck down the side of the whiteboard.
##
## The menu used to be printed across the bottom of the laptop, which cost the
## console a line it could not spare and put the game's navigation inside a
## screen the player has to already be looking at. On the board it is furniture
## like everything else: the jobs, the shop and the terms are things written on
## paper and stuck to the wall, and the machine gets its glass back.
##
## The board is whatever size that room's wall gave it, so the notes are sized
## to the column they end up with rather than to a fixed measure — a garage
## hangs a narrow board and gets narrow notes.

## Paper the notes are written on. Cycled so a column of them reads as a pad
## that has been torn from rather than as a set of tabs. Tuned for a desk lamp
## on a night room: muted, slightly deepened pastels rather than clip-art brights.
const PAPER: Array[Color] = [
	Color(0.70, 0.64, 0.40),
	Color(0.60, 0.66, 0.48),
	Color(0.70, 0.56, 0.42),
	Color(0.54, 0.62, 0.66),
	Color(0.66, 0.56, 0.56),
]
## Biro, on paper lit by a desk lamp.
const INK := Color(0.10, 0.10, 0.13)
## How far off square a note is stuck. Nobody lines these up.
const TILT_DEGREES := 1.6
## Width of one character of the fixed-pitch face, as a fraction of its size.
const MONO_ADVANCE := 0.55
## Gap between notes, as a fraction of the cell each one gets.
const GAP_SHARE := 0.16
## Soft corner on the paper face. Bottom-right is larger so it meets the curl.
const PAPER_CORNER := 3
const PAPER_CORNER_CURL := 8

## How many notes are stuck side by side. One for a column down the edge of a
## wide board, more for a block along the bottom of a board too narrow to give
## a column up. Set by the shell, which knows which wall this room hangs.
var columns: int = 1:
	set(value):
		columns = maxi(1, value)
		_relayout()

var _notes: Array[Button] = []
var _keys: Array[String] = []
var _flagged: Dictionary = {}
var _plane_node: Node2D = null
var _plane: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plane_node = Node2D.new()
	_plane_node.name = "Plane"
	add_child(_plane_node)
	resized.connect(_relayout)


## The menu, top to bottom. Each entry is `{key, headline, pressed}`.
func set_entries(entries: Array) -> void:
	for note in _notes:
		if note.get_parent() != null:
			note.get_parent().remove_child(note)
		note.queue_free()
	_notes.clear()
	_keys.clear()
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var key: String = str(entry.get("key", index))
		var note: Button = _make_note(str(entry.get("headline", "")), index)
		var handler: Variant = entry.get("pressed")
		if handler is Callable:
			note.pressed.connect(handler)
		_plane_node.add_child(note)
		_notes.append(note)
		_keys.append(key)
	_relayout()


## Maps the paper and its clickable faces onto the same photographed surface as
## the whiteboard writing. The plane is expressed in this control's 0..1 space.
func set_plane(corners: PackedVector2Array) -> void:
	_plane = corners if corners.size() == 4 else PackedVector2Array()
	_relayout()


## Marks a note as worth a look — stock the player can now afford, say. Drawn as
## a folded corner mark on the same paper rather than rewriting the pad.
func set_flag(key: String, flagged: bool) -> void:
	if bool(_flagged.get(key, false)) == flagged:
		return
	_flagged[key] = flagged
	var index: int = _keys.find(key)
	if index >= 0:
		_paint(_notes[index], index)


func _make_note(headline: String, index: int) -> Button:
	var note: Button = PostItNoteScript.new()
	note.text = headline.to_upper()
	note.focus_mode = Control.FOCUS_NONE
	note.mouse_filter = Control.MOUSE_FILTER_STOP
	note.clip_text = true
	var font: Font = UiThemeBuilder.mono_font()
	if font != null:
		note.add_theme_font_override("font", font)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		note.add_theme_color_override(state, INK)
	_paint(note, index)
	return note


## Paper, and the shadow it casts. A note is only stuck at one corner, so the
## bottom-right edge lifts: the shadow is biased that way rather than centred.
func _paint(note: Button, index: int) -> void:
	var key: String = _keys[index] if index < _keys.size() else ""
	var paper: Color = PAPER[index % PAPER.size()]
	var is_flagged: bool = bool(_flagged.get(key, false))
	if note is PostItNoteScript:
		var post_it: PostItNoteScript = note
		post_it.paper_color = paper
		post_it.flagged = is_flagged
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		# Pressed reads as the note being pushed flat against the board.
		box.bg_color = paper.darkened(0.18) if state == "pressed" else paper
		if state == "hover":
			box.bg_color = paper.lightened(0.08)
		box.set_corner_radius_all(PAPER_CORNER)
		box.corner_radius_bottom_right = PAPER_CORNER_CURL
		# Soft AA on the stylebox fringes light against the board under shear;
		# project 2D MSAA covers the edge without the halo.
		box.anti_aliasing = false
		box.content_margin_left = 3
		box.content_margin_right = 3
		box.content_margin_top = 2
		box.content_margin_bottom = 4
		# Soft lift under the peeling corner, not a hard double outline.
		box.shadow_color = Color(0, 0, 0, 0.32 if state != "pressed" else 0.12)
		box.shadow_size = 6 if state != "pressed" else 2
		box.shadow_offset = Vector2(2, 4) if state != "pressed" else Vector2(1, 1)
		note.add_theme_stylebox_override(state, box)
	note.queue_redraw()


## Notes are placed by hand rather than by a container, because each one is
## stuck on at its own angle and a container would square them all up again.
func _relayout() -> void:
	var count: int = _notes.size()
	if count == 0 or size.y <= 1.0 or size.x <= 1.0:
		return
	var face: Vector2 = _place_plane()
	var rows: int = ceili(float(count) / float(columns))
	var cell := Vector2(face.x / float(columns), face.y / float(rows))
	var gap: Vector2 = cell * GAP_SHARE
	var paper: Vector2 = (cell - gap).max(Vector2(4.0, 4.0))
	for index in range(count):
		var note: Button = _notes[index]
		note.position = (
			Vector2(float(index % columns), float(index / columns)) * cell + gap * 0.5
		)
		note.size = paper
		note.pivot_offset = paper * 0.5
		# A measured surface already supplies the photographed angle. Adding the
		# hand-placed tilt on top makes the paper disagree with that perspective;
		# keep the small alternating lean only in front-facing rooms.
		note.rotation = (
			0.0
			if _plane.size() == 4
			else deg_to_rad(TILT_DEGREES * (1.0 if index % 2 == 0 else -1.0))
		)
		note.add_theme_font_size_override("font_size", _note_font(note.text, paper))
		# Shadow scale tracks the paper size so a zoomed-in board keeps soft lift.
		_paint(note, index)
		var shadow_scale: float = clampf(mini(paper.x, paper.y) / 40.0, 0.75, 1.6)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var box: StyleBox = note.get_theme_stylebox(state)
			if box is StyleBoxFlat:
				var flat_box: StyleBoxFlat = box
				if state != "pressed":
					flat_box.shadow_size = int(round(6.0 * shadow_scale))
					flat_box.shadow_offset = Vector2(2.0 * shadow_scale, 4.0 * shadow_scale)


## Gives the notes a natural layout size, then shears that layout into the
## photographed plane. Godot applies the same transform to Control hit testing,
## so the tilted notes remain clickable at the pixels where they are drawn.
func _place_plane() -> Vector2:
	if _plane_node == null or _plane.size() != 4:
		if _plane_node != null:
			_plane_node.transform = Transform2D.IDENTITY
		return size
	# Fit the affine Control transform through the centre of the photographed
	# quadrilateral. Averaging opposite edges uses both the top and bottom rail
	# instead of silently throwing away the measured bottom-right corner.
	var centre: Vector2 = (_plane[0] + _plane[1] + _plane[2] + _plane[3]) * size * 0.25
	var across: Vector2 = (
		((_plane[1] - _plane[0]) + (_plane[2] - _plane[3])) * size * 0.5
	)
	var down: Vector2 = (
		((_plane[3] - _plane[0]) + (_plane[2] - _plane[1])) * size * 0.5
	)
	var origin: Vector2 = centre - across * 0.5 - down * 0.5
	if across.length() < 1.0 or down.length() < 1.0:
		_plane_node.transform = Transform2D.IDENTITY
		return size
	_plane_node.transform = Transform2D(across.normalized(), down.normalized(), origin)
	return Vector2(across.length(), down.length())


## Sized to the note rather than the note to the type: the width the word needs
## and the height the paper has, whichever runs out first.
func _note_font(text: String, paper: Vector2) -> int:
	var characters: int = maxi(4, text.length())
	# Plus a margin of paper either side, so the word is not written off the
	# edge of the note it is on.
	var by_width: float = (paper.x - 6.0) / (float(characters) * MONO_ADVANCE)
	# The ceiling is only ever reached with the room leant in on the board,
	# where a note is a third of the window and the word on it should be
	# readable at arm's length rather than held to a size chosen for a note
	# painted a centimetre wide.
	return clampi(int(minf(paper.y * 0.46, by_width)), 6, 48)
