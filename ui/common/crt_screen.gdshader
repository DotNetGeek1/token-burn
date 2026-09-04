shader_type canvas_item;

// Overlay for the rig's monitor. Draws on top of the live terminal text: dark
// scanlines, a darkened tube edge, a faint mains flicker, and a refresh band
// that crawls down the glass so the screen is never a static rectangle.

uniform float scanline_count = 130.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.26;
uniform float edge_darkness : hint_range(0.0, 3.0) = 0.85;
uniform float flicker_strength : hint_range(0.0, 0.3) = 0.03;
uniform float band_speed = 0.16;
uniform float band_strength : hint_range(0.0, 1.0) = 0.09;
uniform vec4 phosphor : source_color = vec4(0.22, 1.0, 0.53, 1.0);

void fragment() {
	// Hard-edged scanlines rather than a sine, which is what reads as "CRT"
	// once the screen is only a couple of hundred pixels tall.
	float scan = step(0.5, fract(UV.y * scanline_count));
	float dark = scan * scanline_strength;

	// Tube edges fall away towards the bezel.
	vec2 centered = UV - vec2(0.5);
	float edge = clamp(dot(centered, centered) * edge_darkness, 0.0, 1.0);

	float flicker = flicker_strength * (0.5 + 0.5 * sin(TIME * 17.0));

	// Narrow enough to read as one travelling line rather than a green wash over
	// a fifth of the glass.
	float band_position = fract(TIME * band_speed);
	float band = exp(-pow((UV.y - band_position) * 46.0, 2.0)) * band_strength;

	float alpha = clamp(dark + edge * 0.7 + flicker, 0.0, 0.85);
	// The band lifts the glass towards phosphor green instead of darkening it,
	// so it passes as light rather than dirt.
	vec3 tint = mix(vec3(0.0, 0.015, 0.02), phosphor.rgb, clamp(band * 3.0, 0.0, 1.0));
	COLOR = vec4(tint, clamp(alpha + band, 0.0, 0.9));
}
