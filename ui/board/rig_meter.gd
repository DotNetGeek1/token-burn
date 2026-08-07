class_name RigMeter
extends Control

## Vertical segment gauge bolted to the side of the rig.
##
## Quality and deadline used to be two more horizontal `ResourceBar`s stacked
## under the machine, which is what made the board read as a form with a picture
## on top. Mounted on the case as a column of lit segments they belong to the
## hardware, and they cost a fraction of the width a full-width bar does.
##
## Drawn rather than composed from nodes because the whole thing is a label, a
## stack of rectangles and a number: a scene would be three nodes and a layout
## pass to achieve the same pixels.

const SEGMENTS := 10
const SEGMENT_GAP := 3.0
## Below this the meter reads as a warning rather than as progress. Quality under
## its target and a deadline nearly spent are the two states worth colouring.
const LOW_RATIO := 0.34

var _label: String = ""
var _value_text: String = ""
var _ratio: float = 0.0
var _shown_ratio: float = 0.0
var _accent: Color = Color.WHITE
## Whether a low reading is the bad one. Quality fills upward toward a target, so
## low is bad; a deadline counts down, so low is also bad. Kept explicit anyway
## because a future meter (heat headroom) inverts.
var _low_is_bad: bool = true
var _fill_tween: Tween = null
## Housing art and the sub-rects to draw into, when the meter is mounted on the
## rig. Empty means "draw the bare column on its own dark plate".
var _housing: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(84, 148)


## Mounts the column in a photographed instrument housing: the label goes in its
## engraved plate, the segments into its recessed channel and the reading into its
## readout window, so the meter looks bolted to the machine.
func set_housing(housing: Dictionary) -> void:
	_housing = housing
	queue_redraw()


## `stat_key` picks the accent from the same table the progress bars used, so a
## quality meter stays yellow and a deadline meter stays green.
func setup(
	label: String, current: float, maximum: float, stat_key: String, value_text: String = ""
) -> void:
	_label = label.to_upper()
	_accent = UiThemeBuilder.progress_fill_for(stat_key).bg_color
	_ratio = clampf(current / maxf(1.0, maximum), 0.0, 1.0)
	_value_text = value_text if value_text != "" else "%d/%d" % [
		int(round(current)), int(round(maximum))
	]
	if _fill_tween != null and _fill_tween.is_valid():
		_fill_tween.kill()
	# Segments light up in sequence rather than snapping, so a burn that moves
	# quality is visible as movement and not only as a different number.
	_fill_tween = create_tween()
	_fill_tween.tween_method(
		func(value: float) -> void:
			_shown_ratio = value
			queue_redraw(),
		_shown_ratio,
		_ratio,
		0.35
	).set_ease(Tween.EASE_OUT)


## Flash used when a burn pushes this stat, matching what `ResourceBar.pulse`
## did before these meters replaced it.
func pulse() -> void:
	modulate = Color(1.6, 1.6, 1.6)
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.4)


func _draw() -> void:
	var caption: Font = UiThemeBuilder.mono_font()
	if caption == null:
		caption = ThemeDB.fallback_font
	if not _housing.is_empty():
		_draw_mounted(caption)
		return
	var label_size: int = int(clampf(size.x * 0.2, 11.0, 17.0))
	var value_size: int = _fitted_size(caption, _value_text, int(clampf(size.x * 0.25, 13.0, 21.0)))
	var label_band: float = float(label_size) + 6.0
	var value_band: float = float(value_size) + 6.0

	# A dark plate behind the column, so the segments read against whatever part
	# of the artwork the meter happens to land on.
	var plate := Rect2(Vector2.ZERO, size)
	draw_rect(plate, Color(0, 0, 0, 0.62), true)
	draw_rect(plate, Color(_accent.r, _accent.g, _accent.b, 0.35), false, 2.0)

	_draw_centred(caption, _label, label_band - 5.0, label_size, UiThemeBuilder.color("grey"))
	_draw_centred(
		caption, _value_text, size.y - 6.0, value_size, _reading_color()
	)
	_draw_segments(label_band, size.y - value_band)


## The housing already is the plate, the border and the channel, so all this draws
## is the three readings, each into the window the art left for it.
func _draw_mounted(caption: Font) -> void:
	draw_texture_rect(_housing["texture"], Rect2(Vector2.ZERO, size), false)
	var channel: Rect2 = _pixels(_housing.get("channel", Rect2()))
	if channel.size.y > 0.0:
		# Inset so the lit cells sit inside the channel's machined surround rather
		# than hard against it.
		_draw_segments_in(channel.grow_individual(
			-channel.size.x * 0.1,
			-channel.size.y * 0.02,
			-channel.size.x * 0.1,
			-channel.size.y * 0.02
		))
	_draw_in_window(
		caption, _housing.get("label", Rect2()), _label, UiThemeBuilder.color("grey")
	)
	_draw_in_window(
		caption, _housing.get("readout", Rect2()), _value_text, _reading_color()
	)


func _pixels(fraction: Rect2) -> Rect2:
	return Rect2(fraction.position * size, fraction.size * size)


## Centred in one of the housing's recessed windows, sized down if the reading is
## wider than the window. The quality readout carries a payout multiplier, which is
## the one that runs long.
func _draw_in_window(font: Font, window: Rect2, text: String, color: Color) -> void:
	if text == "" or window.size.y <= 0.0:
		return
	var pixels: Rect2 = _pixels(window)
	# The engraved windows are shallow, so the type fills them almost completely and
	# has a floor: a reading nobody can read is worse than one that overhangs its
	# window by a pixel.
	var wanted: int = int(clampf(pixels.size.y * 0.95, 10.0, 20.0))
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, wanted).x
	if width > pixels.size.x and width > 0.0:
		wanted = maxi(8, int(float(wanted) * pixels.size.x / width))
		width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, wanted).x
	draw_string(
		font,
		Vector2(
			pixels.position.x + (pixels.size.x - width) * 0.5,
			pixels.position.y + pixels.size.y * 0.5 + float(wanted) * 0.36
		),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		wanted,
		color
	)


## The quality readout carries its payout multiplier, which is wider than the
## plate at the authored size. Now that the meters sit side by side the overflow
## would run into the neighbouring instrument, so the type comes down to fit.
func _fitted_size(font: Font, text: String, wanted: int) -> int:
	if text == "":
		return wanted
	var room: float = size.x - 6.0
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, wanted).x
	if width <= room or width <= 0.0:
		return wanted
	return maxi(9, int(float(wanted) * room / width))


## Bottom-up column: segment 0 is at the base, so a draining deadline empties
## downward the way a tank does.
func _draw_segments(top: float, bottom: float) -> void:
	var inset: float = size.x * 0.22
	_draw_segments_in(Rect2(inset, top, size.x - inset * 2.0, bottom - top))


## Fills the given area with the segment column.
func _draw_segments_in(column: Rect2) -> void:
	if column.size.y <= 0.0 or column.size.x <= 0.0:
		return
	var segment_height: float = (
		column.size.y - SEGMENT_GAP * float(SEGMENTS - 1)
	) / float(SEGMENTS)
	if segment_height <= 0.0:
		return
	var bottom: float = column.end.y
	var lit: float = _shown_ratio * float(SEGMENTS)
	var reading: Color = _reading_color()
	for index in range(SEGMENTS):
		var y: float = bottom - segment_height - float(index) * (segment_height + SEGMENT_GAP)
		var cell := Rect2(column.position.x, y, column.size.x, segment_height)
		# The partially reached segment is dimmed rather than skipped, which is
		# what stops a slow fill from looking like it is doing nothing.
		var coverage: float = clampf(lit - float(index), 0.0, 1.0)
		if coverage <= 0.0:
			draw_rect(cell, Color(1, 1, 1, 0.08), true)
			continue
		draw_rect(
			cell, Color(reading.r, reading.g, reading.b, 0.28 + 0.72 * coverage), true
		)


## Warning colour once the reading is low, so a contract about to miss its
## deadline is not the same green as one with rounds to spare.
func _reading_color() -> Color:
	if _low_is_bad and _ratio <= LOW_RATIO:
		return UiThemeBuilder.color("red")
	return _accent


func _draw_centred(
	font: Font, text: String, baseline: float, font_size: int, color: Color
) -> void:
	var width: float = font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	).x
	draw_string(
		font,
		Vector2((size.x - width) * 0.5, baseline),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		color
	)
