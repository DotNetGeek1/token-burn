extends SceneTree

## Removes the light neutral transparency grid occasionally baked into generated
## cutouts. The workstation hardware is dark and coloured at its lit edges, so a
## strict high-value/low-chroma key clears the grid without touching screen glass,
## metalwork, legends, or emissive accents.
##
## Usage:
##   godot --headless --script res://tools/extract_generated_alpha.gd -- path.png [...]

const LIGHT_FLOOR := 0.68
const MAX_CHROMA := 0.10


func _initialize() -> void:
	var paths: PackedStringArray = OS.get_cmdline_user_args()
	if paths.is_empty():
		push_error("Pass at least one res:// PNG path")
		quit(1)
		return
	var failures := 0
	for path in paths:
		var image := Image.load_from_file(path)
		if image == null or image.is_empty():
			push_error("Could not load %s" % path)
			failures += 1
			continue
		image.convert(Image.FORMAT_RGBA8)
		var cleared := 0
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var pixel: Color = image.get_pixel(x, y)
				var lowest: float = minf(pixel.r, minf(pixel.g, pixel.b))
				var highest: float = maxf(pixel.r, maxf(pixel.g, pixel.b))
				if lowest >= LIGHT_FLOOR and highest - lowest <= MAX_CHROMA:
					pixel.a = 0.0
					image.set_pixel(x, y, pixel)
					cleared += 1
		var error: Error = image.save_png(path)
		if error != OK:
			push_error("Could not save %s (%s)" % [path, error_string(error)])
			failures += 1
		else:
			print("%s: cleared %d background pixels" % [path, cleared])
	quit(failures)
