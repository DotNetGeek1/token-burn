extends SceneTree

## Dev tool: measures the blank screen panels in the rig artwork and the recessed
## windows in the instrument housings, and prints them as the fractional rects the
## asset catalog's `rig_stages` and `rig_instruments` sections want. Run it after
## changing or adding any of that art rather than reading pixels off it by hand:
##   godot --headless --script res://tools/scan_rig_screens.gd
##
## Works on a coarse grid of blocks rather than on pixels: the panels carry a faint
## gradient, and a per-pixel mask fragments across it.

const CELL := 8

const SCREENS := [
	"res://presentation/rig/rig_stage_01.png",
	"res://presentation/rig/rig_stage_02.png",
	"res://presentation/rig/rig_stage_03.png",
	"res://presentation/rig/rig_stage_04_desk.png",
	"res://presentation/rig/rig_stage_05_desk.png",
]
const EXPECTED_SCREEN_COUNTS := [1, 1, 2, 2, 3]

const WINDOWS := [
	"res://presentation/rig/instrument_dial.png",
	"res://presentation/rig/instrument_column.png",
]


func _initialize() -> void:
	var failures: int = 0
	for index in range(SCREENS.size()):
		var path: String = SCREENS[index]
		var boxes: Array = _scan(path, false)
		if boxes.size() != EXPECTED_SCREEN_COUNTS[index]:
			push_error(
				"%s: found %d monitor panels, expected %d" % [
					path, boxes.size(), EXPECTED_SCREEN_COUNTS[index]
				]
			)
			failures += 1
	for path in WINDOWS:
		_scan(path, true)
	quit(failures)


func _scan(path: String, dark_windows: bool) -> Array:
	var image: Image = (load(path) as Texture2D).get_image()
	var width: int = image.get_width()
	var height: int = image.get_height()
	var cols: int = width / CELL
	var rows: int = height / CELL
	var mask := PackedByteArray()
	mask.resize(cols * rows)
	for row in range(rows):
		for col in range(cols):
			mask[row * cols + col] = 1 if _is_flat_panel(image, col, row, dark_windows) else 0
	var seen := PackedByteArray()
	seen.resize(cols * rows)
	var boxes: Array = []
	for row in range(rows):
		for col in range(cols):
			var index: int = row * cols + col
			if mask[index] == 0 or seen[index] == 1:
				continue
			var box: Rect2i = _flood(mask, seen, cols, rows, col, row)
			var area: float = float(box.size.x * box.size.y) / float(cols * rows)
			if area < 0.008:
				continue
			# The field behind the artwork is flat and dark too, so a component that
			# runs off the edge of the image is the backdrop rather than a panel.
			if dark_windows and (
				box.position.x <= 0 or box.position.y <= 0
				or box.end.x >= cols - 1 or box.end.y >= rows - 1
			):
				continue
			boxes.append(box)
	boxes.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.position.x < b.position.x)
	print("--- %s (%dx%d)" % [path.get_file(), width, height])
	for box in boxes:
		print("  [%.4f, %.4f, %.4f, %.4f]" % [
			float(box.position.x) / float(cols),
			float(box.position.y) / float(rows),
			float(box.size.x) / float(cols),
			float(box.size.y) / float(rows),
		])
	return boxes


## A panel is a block that is dark, almost perfectly flat, and — for screen glass —
## tinted toward green over red. Machined casing is neutral and grainy, so the
## flatness test alone throws most of it out.
func _is_flat_panel(image: Image, col: int, row: int, dark_windows: bool) -> bool:
	var total := Color(0, 0, 0)
	var lowest: float = 1.0
	var highest: float = 0.0
	for y in range(row * CELL, row * CELL + CELL):
		for x in range(col * CELL, col * CELL + CELL):
			var pixel: Color = image.get_pixel(x, y)
			# Generated workstation assets are transparent cutouts. Transparent
			# outside pixels are not dark monitor glass even when their RGB is zero.
			if pixel.a < 0.5:
				return false
			total += pixel
			lowest = minf(lowest, pixel.v)
			highest = maxf(highest, pixel.v)
	var count: float = float(CELL * CELL)
	var mean := Color(total.r / count, total.g / count, total.b / count)
	if highest - lowest > 0.035:
		return false
	if dark_windows:
		return mean.v < 0.075
	return mean.v > 0.02 and mean.v < 0.34 and mean.g - mean.r > 0.006


func _flood(
	mask: PackedByteArray, seen: PackedByteArray, cols: int, rows: int, col: int, row: int
) -> Rect2i:
	var box := Rect2i(col, row, 1, 1)
	var stack: Array[Vector2i] = [Vector2i(col, row)]
	seen[row * cols + col] = 1
	while not stack.is_empty():
		var point: Vector2i = stack.pop_back()
		box = box.expand(point).expand(point + Vector2i.ONE)
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = point + offset
			if next.x < 0 or next.y < 0 or next.x >= cols or next.y >= rows:
				continue
			var index: int = next.y * cols + next.x
			if mask[index] == 0 or seen[index] == 1:
				continue
			seen[index] = 1
			stack.append(next)
	return box
