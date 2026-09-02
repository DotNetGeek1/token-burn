extends SceneTree

## Renders the four Android launcher PNGs from the title palette.
## icon.svg uses <text>, which ThorVG drops; title_key_art is a full room.
## The mark is therefore painted: a CRT bezel and phosphor burn bar that
## matches boot_splash / ConsoleStyle.

const OUT := "res://presentation/android"
const BG := Color(0.0118, 0.0275, 0.0235, 1.0)
const PHOSPHOR := Color(0.42, 0.92, 0.60, 1.0)
const GLASS := Color(0.012, 0.055, 0.042, 1.0)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var mark: Image = _paint_mark(432)
	_write(mark, "%s/adaptive_foreground_432.png" % OUT)
	_write(_flat(432, BG), "%s/adaptive_background_432.png" % OUT)
	_write(_mono(mark), "%s/adaptive_monochrome_432.png" % OUT)
	_write(_composite_192(mark), "%s/icon_192.png" % OUT)
	print("Wrote Android launcher icons to %s" % OUT)
	quit(0)


func _flat(size: int, color: Color) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _paint_mark(size: int) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	# Adaptive icons keep the inner ~66% safe. All geometry lives there.
	var inset := int(round(float(size) * 0.17))
	var area := Rect2i(inset, inset, size - inset * 2, size - inset * 2)
	var bezel := maxi(4, int(round(float(size) * 0.028)))
	var radius := maxi(6, int(round(float(size) * 0.04)))
	_fill_round(image, area, PHOSPHOR, radius)
	var glass := Rect2i(
		area.position.x + bezel,
		area.position.y + bezel,
		area.size.x - bezel * 2,
		area.size.y - bezel * 2
	)
	_fill_round(image, glass, GLASS, maxi(4, radius - 2))
	var bar_h := maxi(8, int(round(float(glass.size.y) * 0.14)))
	var bar_w := int(round(float(glass.size.x) * 0.62))
	var bar := Rect2i(
		glass.position.x + int(round(float(glass.size.x - bar_w) * 0.5)),
		glass.position.y + int(round(float(glass.size.y) * 0.58)),
		bar_w,
		bar_h
	)
	_fill_round(image, bar, PHOSPHOR, maxi(2, bar_h / 3))
	var stem_w := maxi(6, int(round(float(glass.size.x) * 0.08)))
	var stem := Rect2i(
		glass.position.x + (glass.size.x - stem_w) / 2,
		glass.position.y + int(round(float(glass.size.y) * 0.22)),
		stem_w,
		int(round(float(glass.size.y) * 0.28))
	)
	_fill_rect(image, stem, PHOSPHOR)
	return image


func _composite_192(mark: Image) -> Image:
	var image := _flat(192, BG)
	var scaled := Image.new()
	scaled.copy_from(mark)
	scaled.resize(192, 192, Image.INTERPOLATE_LANCZOS)
	image.blend_rect(scaled, Rect2i(0, 0, 192, 192), Vector2i.ZERO)
	return image


func _mono(mark: Image) -> Image:
	var image := Image.create(mark.get_width(), mark.get_height(), false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in mark.get_height():
		for x in mark.get_width():
			var pixel: Color = mark.get_pixel(x, y)
			if pixel.a <= 0.01:
				continue
			var lit: float = maxf(pixel.r, maxf(pixel.g, pixel.b)) * pixel.a
			image.set_pixel(x, y, Color(1, 1, 1, clampf(lit, 0.0, 1.0)))
	return image


func _write(image: Image, path: String) -> void:
	var err: Error = image.save_png(path)
	if err != OK:
		push_error("Failed to write %s (%s)" % [path, err])


func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				image.set_pixel(x, y, color)


func _fill_round(image: Image, rect: Rect2i, color: Color, radius: int) -> void:
	var r: int = mini(radius, mini(rect.size.x, rect.size.y) / 2)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			if _inside_round(x, y, rect, r):
				image.set_pixel(x, y, color)


func _inside_round(x: int, y: int, rect: Rect2i, radius: int) -> bool:
	var left: int = rect.position.x
	var top: int = rect.position.y
	var right: int = rect.position.x + rect.size.x - 1
	var bottom: int = rect.position.y + rect.size.y - 1
	var cx: int = x
	var cy: int = y
	if x < left + radius and y < top + radius:
		return _in_circle(x, y, left + radius, top + radius, radius)
	if x > right - radius and y < top + radius:
		return _in_circle(x, y, right - radius, top + radius, radius)
	if x < left + radius and y > bottom - radius:
		return _in_circle(x, y, left + radius, bottom - radius, radius)
	if x > right - radius and y > bottom - radius:
		return _in_circle(x, y, right - radius, bottom - radius, radius)
	return cx >= left and cx <= right and cy >= top and cy <= bottom


func _in_circle(x: int, y: int, cx: int, cy: int, radius: int) -> bool:
	var dx: int = x - cx
	var dy: int = y - cy
	return dx * dx + dy * dy <= radius * radius
