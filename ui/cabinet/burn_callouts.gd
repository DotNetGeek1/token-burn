class_name BurnCallouts
extends Control

## The big numbers a batch throws up on the glass as it runs.
##
## The drum and the feed report every beat, but they are instruments: small,
## steady, in the corner of the eye. When a stage doubles the multiplier or
## runs the stage above it again, the batch should feel like it just did
## something, so the ratio and the rate it bought slam up over the whole glass,
## hold for a breath and lift away. They are printed, never laid out, and take
## no input; several can be in the air at once, and each one that lands while
## another is still fading is thrown a little off centre so the two read as
## two.

## The multiplier (or the AGAIN!) in the big face.
const HEADLINE_SIZE := 60
## The rate the multiplier bought, under it.
const RATE_SIZE := 17
const PAD_H := 22
const PAD_V := 8
const PUNCH_SECONDS := 0.16
const HOLD_SECONDS := 0.55
const FADE_SECONDS := 0.5
const RISE := 26.0
## Where a callout lands when the one before it is still up: a small orbit
## around the middle of the glass, in fractions of the glass's size.
const SCATTER: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(-0.2, -0.16), Vector2(0.2, 0.12),
	Vector2(0.18, -0.2), Vector2(-0.22, 0.14), Vector2(0.0, -0.24),
]
## Below this height (a handset canvas) the type comes down with the glass.
const COMPACT_HEIGHT := 260.0
const COMPACT_TYPE_SCALE := 0.6

var _live: int = 0
var _scatter_index: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


## Throws `headline` (say "×2" or "AGAIN! ×2") up in `color`, with `rate` (say
## "7.0M TOKENS/MIN") under it.
func flash(headline: String, rate: String, color: Color = CabinetStyle.AMBER) -> void:
	_flash(headline, rate, color, null)


## The red one: a beetle beside how many bugs the batch just wrote, with the
## job's running total under it.
func flash_bugs(added: int, total: int) -> void:
	var compact: bool = size.y < COMPACT_HEIGHT
	var glyph := BugGlyph.new(HEADLINE_SIZE * (COMPACT_TYPE_SCALE if compact else 1.0), CabinetStyle.RED)
	_flash(
		"×%d" % maxi(1, added),
		"%d BUG%s ON THIS JOB" % [total, "" if total == 1 else "S"],
		CabinetStyle.RED,
		glyph
	)


func _flash(headline: String, rate: String, color: Color, icon: Control) -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		if icon != null:
			icon.free()
		return
	var compact: bool = size.y < COMPACT_HEIGHT
	var type_scale: float = COMPACT_TYPE_SCALE if compact else 1.0

	# Printed on a slab of darker glass, so the number reads over whatever
	# figures the tab underneath has in the same place.
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slab := StyleBoxFlat.new()
	slab.bg_color = Color(0.0, 0.02, 0.012, 0.86)
	slab.border_color = Color(color.r, color.g, color.b, 0.55)
	slab.set_border_width_all(1)
	slab.set_corner_radius_all(2)
	slab.content_margin_left = PAD_H * type_scale
	slab.content_margin_right = PAD_H * type_scale
	slab.content_margin_top = PAD_V * type_scale
	slab.content_margin_bottom = PAD_V * type_scale
	slab.shadow_color = Color(color.r, color.g, color.b, 0.25)
	slab.shadow_size = int(round(10.0 * type_scale))
	card.add_theme_stylebox_override("panel", slab)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 0)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(stack)
	var head: Label = CabinetStyle.mono(headline, int(round(HEADLINE_SIZE * type_scale)), color)
	head.clip_text = false
	head.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if icon == null:
		stack.add_child(head)
	else:
		# The icon sits beside the big number, both centred on the same line.
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", int(round(10.0 * type_scale)))
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(head)
		stack.add_child(row)
	if rate != "":
		var line: Label = CabinetStyle.mono(rate, int(round(RATE_SIZE * type_scale)), CabinetStyle.WHITE)
		line.clip_text = false
		line.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(line)
	add_child(card)

	# Off centre only while something else is still up: the first callout of a
	# quiet batch lands dead centre, where the eye already is.
	var offset: Vector2 = Vector2.ZERO
	if _live > 0:
		_scatter_index = (_scatter_index + 1) % SCATTER.size()
		offset = SCATTER[_scatter_index] * size
	else:
		_scatter_index = 0
	_live += 1

	# Laid out once so the card's size is known, then parked by hand: a
	# container would fight the tween.
	card.size = card.get_combined_minimum_size()
	card.pivot_offset = card.size * 0.5
	var rest: Vector2 = (size - card.size) * 0.5 + offset
	rest.x = clampf(rest.x, 0.0, maxf(0.0, size.x - card.size.x))
	rest.y = clampf(rest.y, 0.0, maxf(0.0, size.y - card.size.y))
	card.position = rest
	card.scale = Vector2(1.6, 1.6)
	card.modulate.a = 0.0

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "scale", Vector2.ONE, PUNCH_SECONDS).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate:a", 1.0, PUNCH_SECONDS * 0.6)
	tween.chain().tween_interval(HOLD_SECONDS)
	tween.chain().tween_property(card, "modulate:a", 0.0, FADE_SECONDS).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(card, "position:y", rest.y - RISE, FADE_SECONDS).set_ease(
		Tween.EASE_OUT
	)
	tween.chain().tween_callback(func() -> void:
		_live = maxi(0, _live - 1)
		card.queue_free()
	)


## How many callouts are still on the glass, for the playtests.
func live_count() -> int:
	return _live
