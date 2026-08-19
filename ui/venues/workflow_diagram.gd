class_name WorkflowDiagram
extends Control

## A connected, drag-and-drop view of one workflow. Stages run left-to-right on
## the first row, right-to-left on the second, and so on, so the path remains one
## continuous diagram without long diagonal connectors.

signal slot_tapped(meta: Variant)
signal module_dropped(module_id: String, slot_index: int)
signal slot_dropped(from_index: int, to_index: int)

const GAP := 18.0
const TOP_PAD := 12.0
const MIN_CARD_WIDTH := 165.0
const CARD_HEIGHT := WorkflowCard.MIN_HEIGHT

var _cards: Array[WorkflowCard] = []
var _entries: Array = []
var _selected: Variant = null
var _scale: float = 1.0
var _card_rects: Array[Rect2] = []


func set_slots(entries: Array) -> void:
	_entries = entries.duplicate(true)
	while _cards.size() < entries.size():
		var card := WorkflowCard.new()
		card.tapped.connect(func(meta: Variant) -> void: slot_tapped.emit(meta))
		card.data_dropped.connect(_on_card_drop)
		add_child(card)
		_cards.append(card)
	for index in range(_cards.size()):
		var card: WorkflowCard = _cards[index]
		card.visible = index < entries.size()
		if not card.visible:
			continue
		card.set_card(Dictionary(entries[index]))
		card.set_metrics(_scale)
		card.set_selected(_selected != null and card.meta == _selected)
	_layout_cards()


func select(meta: Variant) -> void:
	_selected = meta
	for card in _cards:
		card.set_selected(meta != null and card.meta == meta)


func clear_selection() -> void:
	select(null)


func set_metrics(scale: float) -> void:
	_scale = scale
	for card in _cards:
		card.set_metrics(scale)
	_layout_cards()


func _on_card_drop(target_meta: Variant, data: Dictionary) -> void:
	var target: int = int(str(target_meta).trim_prefix("slot:"))
	match str(data.get("kind", "")):
		WorkflowCard.ROLE_MODULE:
			module_dropped.emit(str(data.get("module_id", "")), target)
		WorkflowCard.ROLE_SLOT:
			slot_dropped.emit(int(data.get("slot_index", -1)), target)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_cards()
	elif what == NOTIFICATION_DRAW:
		_draw_connections()


func _layout_cards() -> void:
	if _cards.is_empty() or size.x <= 1.0:
		return
	var gap: float = GAP * _scale
	var fit: int = clampi(int((size.x + gap) / (MIN_CARD_WIDTH * _scale + gap)), 1, 4)
	# Five or six stages stay a two-row snake (3+2 / 3+3). A fourth column on a
	# wide board would leave a single card on the second row.
	var column_cap: int = 3 if _entries.size() <= 6 else 4
	var columns: int = clampi(mini(fit, maxi(1, _entries.size())), 1, column_cap)
	var rows: int = ceili(float(_entries.size()) / float(columns))
	var available_card_width: float = (size.x - gap * float(columns - 1)) / float(columns)
	var card_width: float = available_card_width
	var top_pad: float = TOP_PAD * _scale
	var card_height: float = CARD_HEIGHT * _scale
	if rows > 0 and size.y > 1.0:
		var room: float = (
			size.y - top_pad * 2.0 - gap * float(maxi(0, rows - 1))
		) / float(rows)
		if room > 1.0:
			card_height = minf(card_height, room)
	var block_height: float = (
		float(rows) * card_height + float(maxi(0, rows - 1)) * gap
	)
	# Notes sit under the heading and against the photographed divider, not in a
	# centred island that leaves the writing surface empty on three sides.
	var origin := Vector2(0.0, top_pad)
	_card_rects.clear()
	_card_rects.resize(_entries.size())
	for index in range(_entries.size()):
		var row: int = index / columns
		var along: int = index % columns
		var column: int = along if row % 2 == 0 else columns - 1 - along
		var rect := Rect2(
			origin + Vector2(column * (card_width + gap), row * (card_height + gap)),
			Vector2(card_width, card_height)
		)
		_card_rects[index] = rect
		_cards[index].position = rect.position
		_cards[index].size = rect.size
	custom_minimum_size.y = top_pad * 2.0 + block_height
	queue_redraw()


func _draw_connections() -> void:
	if _card_rects.size() < 2:
		return
	var line_color := Color(0.08, 0.25, 0.18, 0.78)
	for index in range(_card_rects.size() - 1):
		var a: Rect2 = _card_rects[index]
		var b: Rect2 = _card_rects[index + 1]
		var points := PackedVector2Array()
		if absf(a.get_center().y - b.get_center().y) < 1.0:
			var rightward: bool = b.get_center().x > a.get_center().x
			var start := Vector2(a.end.x, a.get_center().y) if rightward else Vector2(a.position.x, a.get_center().y)
			var finish := Vector2(b.position.x, b.get_center().y) if rightward else Vector2(b.end.x, b.get_center().y)
			points = PackedVector2Array([start, finish])
		else:
			var start := Vector2(a.get_center().x, a.end.y)
			var finish := Vector2(b.get_center().x, b.position.y)
			var middle_y: float = (start.y + finish.y) * 0.5
			points = PackedVector2Array([start, Vector2(start.x, middle_y), Vector2(finish.x, middle_y), finish])
		draw_polyline(points, line_color, 3.0 * _scale, true)
		_draw_arrow(points[points.size() - 2], points[points.size() - 1], line_color)


func _draw_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	var direction: Vector2 = (to - from).normalized()
	if direction.length_squared() < 0.5:
		return
	var normal := Vector2(-direction.y, direction.x)
	var length: float = 10.0 * _scale
	var width: float = 6.0 * _scale
	var tip: Vector2 = to - direction * 2.0 * _scale
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip - direction * length + normal * width,
		tip - direction * length - normal * width,
	]), color)
