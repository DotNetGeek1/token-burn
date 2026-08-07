class_name UiTransition
extends RefCounted

## Entrance and exit motion for overlays and lists.
##
## Every overlay used to appear by flipping `visible`, which reads as a redraw
## glitch rather than a screen arriving: the player cannot tell whether the bills
## replaced the board or were always there. A short rise-and-fade gives
## each one a direction, and staggering a freshly built list makes cards look
## dealt instead of pasted.

const FADE_SECONDS := 0.22
const ENTER_SCALE := 0.965
const STAGGER_STEP := 0.045
## Past this many rows the wait before the last card lands is longer than the
## reveal is worth, so the tail arrives together.
const STAGGER_LIMIT := 8


## Fades an overlay in and settles its panel out of a slight shrink. `panel`
## defaults to a child named "Panel", which is what the flow overlays use.
static func enter(overlay: Control, panel: Control = null) -> void:
	overlay.visible = true
	overlay.modulate.a = 0.0
	var fade: Tween = overlay.create_tween()
	fade.tween_property(overlay, "modulate:a", 1.0, FADE_SECONDS).set_ease(Tween.EASE_OUT)
	var target: Control = panel
	if target == null and overlay.has_node("Panel"):
		target = overlay.get_node("Panel")
	if target == null:
		return
	# Position is owned by the layout pass, so the panel grows into place rather
	# than sliding: scale is the one transform a container will not overwrite.
	target.pivot_offset = target.size * 0.5
	target.scale = Vector2(ENTER_SCALE, ENTER_SCALE)
	var settle: Tween = target.create_tween()
	settle.tween_property(target, "scale", Vector2.ONE, FADE_SECONDS * 1.5).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_OUT)


## Bottom sheets grow up out of the edge they are anchored to, so the pivot sits
## at the bottom of the sheet rather than its middle.
static func reveal_sheet(sheet: Control) -> void:
	sheet.visible = true
	sheet.modulate.a = 0.0
	sheet.pivot_offset = Vector2(sheet.size.x * 0.5, sheet.size.y)
	sheet.scale = Vector2(1.0, ENTER_SCALE)
	var tween: Tween = sheet.create_tween()
	tween.tween_property(sheet, "modulate:a", 1.0, FADE_SECONDS * 0.8)
	tween.parallel().tween_property(sheet, "scale", Vector2.ONE, FADE_SECONDS * 1.5).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_OUT)


## Fades an overlay out, then hides it. Awaitable, but callers that need the
## simulation to move on immediately can ignore the return.
static func leave(overlay: Control) -> Tween:
	var fade: Tween = overlay.create_tween()
	fade.tween_property(overlay, "modulate:a", 0.0, FADE_SECONDS * 0.7).set_ease(Tween.EASE_IN)
	fade.tween_callback(func() -> void:
		overlay.visible = false
		overlay.modulate.a = 1.0
	)
	return fade


## Deals the children of a just-rebuilt list in, one shortly after another.
static func stagger(container: Node) -> void:
	var index: int = 0
	for child in container.get_children():
		if child is not Control:
			continue
		var row: Control = child
		var delay: float = STAGGER_STEP * float(mini(index, STAGGER_LIMIT))
		row.modulate.a = 0.0
		var tween: Tween = row.create_tween()
		tween.tween_interval(delay)
		tween.tween_property(row, "modulate:a", 1.0, FADE_SECONDS).set_ease(Tween.EASE_OUT)
		index += 1


## Counts a money figure up from zero. The reward is the point of a debrief, so
## it lands as an event rather than as text that was always on screen.
static func count_up(label: Label, amount: float, seconds: float = 0.7) -> void:
	if amount <= 0.0:
		label.text = NumberFormat.format_cash(amount)
		return
	var shown: Callable = func(value: float) -> void:
		label.text = NumberFormat.format_cash(value)
	var tween: Tween = label.create_tween()
	tween.tween_method(shown, 0.0, amount, seconds).set_trans(Tween.TRANS_QUINT).set_ease(
		Tween.EASE_OUT
	)
