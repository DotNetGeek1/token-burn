class_name PostItNote
extends Button

## A single menu note stuck to the whiteboard.
##
## The StyleBoxFlat underneath supplies the paper colour and soft shadow; this
## draws the things that make it read as paper rather than a flat colour chip:
## lamp light falling down the face, a sparse grain, a peeled bottom-right
## corner, and — when the note has news — a small corner mark instead of
## repainting the whole pad.

## How far the bottom-right corner curls up, as a fraction of the shorter edge.
const CURL_SHARE := 0.28
## Speckles scattered across the face. Seeded from the paper colour so a column
## of notes does not share the same noise pattern.
const GRAIN_COUNT := 22
## Accent painted into the top-left when the note is flagged.
const FLAG_MARK := Color(0.62, 0.36, 0.14)

var paper_color: Color = Color(0.70, 0.64, 0.40):
	set(value):
		paper_color = value
		queue_redraw()

var flagged: bool = false:
	set(value):
		if flagged == value:
			return
		flagged = value
		queue_redraw()


func _ready() -> void:
	# The stylebox already paints the face; keep this transparent so we only
	# layer the paper details on top.
	flat = false
	resized.connect(queue_redraw)


func _draw() -> void:
	var face: Rect2 = Rect2(Vector2.ZERO, size)
	if face.size.x < 2.0 or face.size.y < 2.0:
		return
	_draw_lamp_wash(face)
	_draw_grain(face)
	_draw_curl(face)
	if flagged:
		_draw_flag_mark(face)


## Soft top-to-bottom wash so the paper catches the desk lamp rather than
## sitting as a flat fill.
func _draw_lamp_wash(face: Rect2) -> void:
	var bands: int = maxi(4, int(face.size.y / 3.0))
	for i in range(bands):
		var t: float = float(i) / float(bands)
		var band := Rect2(
			face.position.x,
			face.position.y + face.size.y * t,
			face.size.x,
			ceili(face.size.y / float(bands)) + 1.0
		)
		# Brighten near the top, shade toward the lifting edge.
		var wash: Color = (
			Color(1, 1, 1, 0.05 * (1.0 - t)) if t < 0.55
			else Color(0, 0, 0, 0.06 * (t - 0.45))
		)
		draw_rect(band, wash, true)


## Sparse seeded speckles. Enough to break the flat fill, not enough to read as
## dirt or a texture atlas.
func _draw_grain(face: Rect2) -> void:
	var seed: int = int(paper_color.r * 97.0 + paper_color.g * 53.0 + paper_color.b * 31.0) * 7919
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for _i in range(GRAIN_COUNT):
		var p := Vector2(
			rng.randf_range(1.0, maxf(2.0, face.size.x - 2.0)),
			rng.randf_range(1.0, maxf(2.0, face.size.y - 2.0))
		)
		var shade: float = rng.randf_range(-0.10, 0.05)
		var speck: Color = (
			paper_color.lightened(shade) if shade > 0.0 else paper_color.darkened(-shade)
		)
		speck.a = 0.28
		draw_rect(Rect2(p, Vector2(1.0, 1.0)), speck, true)


## Bottom-right corner peeled up. The triangle of underside plus the thin
## highlight along the fold sell the "stuck at one corner" read that the
## shadow already implies.
func _draw_curl(face: Rect2) -> void:
	var curl: float = mini(face.size.x, face.size.y) * CURL_SHARE
	curl = clampf(curl, 5.0, 16.0)
	var tip := Vector2(face.end.x, face.end.y)
	var left := Vector2(tip.x - curl, tip.y)
	var up := Vector2(tip.x, tip.y - curl)
	# Cover the sharp stylebox corner with the peeled flap.
	var underside := PackedVector2Array([left, tip, up])
	draw_colored_polygon(underside, paper_color.darkened(0.28))
	# Inner face of the flap, slightly lighter, inset from the tip.
	var flap_inset: float = curl * 0.22
	var flap := PackedVector2Array([
		left + Vector2(flap_inset, -1.0),
		tip + Vector2(-flap_inset * 0.6, -flap_inset * 0.6),
		up + Vector2(-1.0, flap_inset),
	])
	draw_colored_polygon(flap, paper_color.lightened(0.06).darkened(0.10))
	# Fold highlight along the diagonal.
	draw_line(left, up, paper_color.lightened(0.22), 1.2, true)
	# Soft shade cast by the lifted corner onto the face above the fold.
	var shade_band := PackedVector2Array([
		left + Vector2(0.0, -1.0),
		up + Vector2(-1.0, 0.0),
		up.lerp(left, 0.5) + Vector2(-curl * 0.18, -curl * 0.18),
	])
	draw_colored_polygon(shade_band, Color(0, 0, 0, 0.12))


## Small mark in the pinned corner — news without rewriting the pad.
func _draw_flag_mark(face: Rect2) -> void:
	var mark: float = mini(face.size.x, face.size.y) * 0.26
	mark = clampf(mark, 5.0, 11.0)
	var origin := face.position
	var triangle := PackedVector2Array([
		origin,
		origin + Vector2(mark, 0.0),
		origin + Vector2(0.0, mark),
	])
	draw_colored_polygon(triangle, FLAG_MARK)
	# Tiny crease so it reads as a folded tip rather than a badge.
	draw_line(
		origin + Vector2(mark, 0.0),
		origin + Vector2(0.0, mark),
		FLAG_MARK.darkened(0.28),
		1.0,
		true
	)
