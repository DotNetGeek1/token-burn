class_name UiFx
extends RefCounted

## Procedural textures for the game's effects layer.
##
## Smoke, embers, glows and light beams all want soft falloff art that the SVG kit
## does not ship, so it is generated here instead of adding PNGs for four blurry
## circles.
##
## `Gradient.set_color` takes a point *index*, and adding a mid point shifts the
## last point's index, so building a ramp with set_color/add_point calls silently
## leaves the outer stop at its default opaque white — which turns every soft glow
## into a hard-edged square. Everything here assigns the stops as arrays instead,
## where the mapping is explicit.


static func ramp(offsets: Array, colors: Array) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	gradient.colors = PackedColorArray(colors)
	return gradient


## Soft round blob, used as the particle texture for smoke, fire and embers and
## as the bloom behind glowing hardware.
static func radial_dot(resolution: int = 64, core: float = 0.35) -> GradientTexture2D:
	var texture := GradientTexture2D.new()
	texture.gradient = ramp(
		[0.0, core, 1.0],
		[Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)]
	)
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = resolution
	texture.height = resolution
	return texture


## Falloff strip sampled along the length of the alarm beacon's light beams.
static func beam_falloff() -> GradientTexture2D:
	var texture := GradientTexture2D.new()
	texture.gradient = ramp(
		[0.0, 0.25, 1.0],
		[Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)]
	)
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1, 0)
	texture.width = 128
	texture.height = 4
	return texture


## Radial vignette: clear in the middle, `edge` at the corners. Used to flood the
## screen with a colour without hiding what is underneath it.
static func vignette(edge: Color, clear_to: float = 0.5) -> GradientTexture2D:
	var texture := GradientTexture2D.new()
	texture.gradient = ramp(
		[0.0, clear_to, 1.0],
		[Color(edge.r, edge.g, edge.b, 0.0), Color(edge.r, edge.g, edge.b, 0.0), edge]
	)
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	return texture


## Vertical scrim, so a menu can sit over key art without flattening the whole
## image. `from` and `to` are where the ramp starts and finishes down the texture;
## the defaults hold the two ends flat for a while before the fade begins, which is
## what a scrim over artwork wants. A ramp that has to run edge to edge — one band
## of a scene blending into the next — passes 0 and 1.
static func scrim(
	base: Color,
	top_alpha: float,
	bottom_alpha: float,
	from: float = 0.22,
	to: float = 0.88
) -> GradientTexture2D:
	var texture := GradientTexture2D.new()
	texture.gradient = ramp(
		[0.0, 1.0],
		[Color(base.r, base.g, base.b, top_alpha), Color(base.r, base.g, base.b, bottom_alpha)]
	)
	texture.fill_from = Vector2(0, from)
	texture.fill_to = Vector2(0, to)
	texture.width = 8
	texture.height = 256
	return texture
