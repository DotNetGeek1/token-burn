shader_type canvas_item;

// Maps a pixel on the rectangular draw surface back into the live panel
// texture. Supplying the inverse homography rather than bending a two-triangle
// mesh keeps every horizontal and vertical UI rule straight.
uniform vec3 inverse_row_0 = vec3(1.0, 0.0, 0.0);
uniform vec3 inverse_row_1 = vec3(0.0, 1.0, 0.0);
uniform vec3 inverse_row_2 = vec3(0.0, 0.0, 1.0);

void fragment() {
	vec3 destination = vec3(UV, 1.0);
	vec3 source = vec3(
		dot(inverse_row_0, destination),
		dot(inverse_row_1, destination),
		dot(inverse_row_2, destination)
	);
	if (abs(source.z) < 0.00001) {
		COLOR = vec4(0.0);
	} else {
		vec2 panel_uv = source.xy / source.z;
		if (
			panel_uv.x < 0.0 || panel_uv.x > 1.0
			|| panel_uv.y < 0.0 || panel_uv.y > 1.0
		) {
			COLOR = vec4(0.0);
		} else {
			// COLOR already contains a sample at the mesh's ordinary UV. Sampling
			// it again would multiply the straight and warped images together.
			COLOR = texture(TEXTURE, panel_uv);
		}
	}
}
