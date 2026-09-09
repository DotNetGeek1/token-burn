class_name BugGlyph
extends Control

## A beetle, drawn: a body, a head, six legs and a seam down the back. The
## cabinet has glyphs for every module category but nothing for a defect, and a
## defect needs a shape of its own so the red callout is read before the number
## on it is.

var color: Color = CabinetStyle.RED


func _init(size_px: float = 48.0, tint: Color = CabinetStyle.RED) -> void:
	color = tint
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	var c: Vector2 = size * 0.5
	var body_w: float = s * 0.42
	var body_h: float = s * 0.56
	var line: float = maxf(1.5, s * 0.06)
	# Legs first, so the body sits over their roots.
	for side in [-1.0, 1.0]:
		for i in range(3):
			var y: float = c.y - body_h * 0.28 + float(i) * body_h * 0.3
			var root := Vector2(c.x + side * body_w * 0.42, y)
			var knee := Vector2(c.x + side * body_w * 0.78, y - s * 0.08 + float(i) * s * 0.05)
			var foot := Vector2(c.x + side * body_w * 0.98, y + s * 0.1)
			draw_line(root, knee, color, line)
			draw_line(knee, foot, color, line)
	# Antennae.
	for side in [-1.0, 1.0]:
		var from := Vector2(c.x + side * s * 0.06, c.y - body_h * 0.5 - s * 0.04)
		var to := Vector2(c.x + side * s * 0.16, c.y - body_h * 0.5 - s * 0.16)
		draw_line(from, to, color, line)
	# Head, then body over it.
	draw_circle(Vector2(c.x, c.y - body_h * 0.42), s * 0.11, color)
	_draw_ellipse(Vector2(c.x, c.y + body_h * 0.06), Vector2(body_w * 0.5, body_h * 0.46), color)
	# The seam and the wing line, in the glass's dark so they cut the body.
	var dark := Color(0.0, 0.02, 0.012, 1.0)
	draw_line(
		Vector2(c.x, c.y - body_h * 0.3), Vector2(c.x, c.y + body_h * 0.5), dark, line * 0.8
	)
	draw_line(
		Vector2(c.x - body_w * 0.48, c.y - body_h * 0.18),
		Vector2(c.x + body_w * 0.48, c.y - body_h * 0.18),
		dark,
		line * 0.8
	)


func _draw_ellipse(center: Vector2, radii: Vector2, fill: Color) -> void:
	var points := PackedVector2Array()
	var steps: int = 28
	for i in range(steps):
		var angle: float = TAU * float(i) / float(steps)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, fill)
