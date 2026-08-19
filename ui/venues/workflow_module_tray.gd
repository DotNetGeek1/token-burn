class_name WorkflowModuleTray
extends ScrollContainer

## The left side of the whiteboard: only modules which are not currently used by
## the active workflow. Each card can be tapped or dragged into a diagram slot.

signal module_tapped(meta: Variant)

const GAP := 8

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

var _column: VBoxContainer = null
var _note: Label = null
var _cards: Array[WorkflowCard] = []
var _selected: Variant = null
var _scale: float = 1.0


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", GAP)
	add_child(_column)

	_note = ConsoleStyle.paragraph("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_column.add_child(_note)


func set_modules(entries: Array, note: String = "") -> void:
	while _cards.size() < entries.size():
		var card := WorkflowCard.new()
		card.tapped.connect(func(meta: Variant) -> void: module_tapped.emit(meta))
		_column.add_child(card)
		_cards.append(card)
	for index in range(_cards.size()):
		var card: WorkflowCard = _cards[index]
		card.visible = index < entries.size()
		if not card.visible:
			continue
		card.set_card(Dictionary(entries[index]))
		card.set_metrics(_scale)
		card.set_selected(_selected != null and card.meta == _selected)
	_note.text = note
	_note.visible = note != ""
	_column.move_child(_note, _column.get_child_count() - 1)
	_size_cards()


func select(meta: Variant) -> void:
	_selected = meta
	for card in _cards:
		card.set_selected(meta != null and card.meta == meta)


func clear_selection() -> void:
	select(null)


func set_metrics(scale: float) -> void:
	_scale = scale
	_column.add_theme_constant_override("separation", ConsoleMetrics.px(GAP, scale))
	_note.add_theme_font_size_override("font_size", ConsoleMetrics.font_tiny(scale))
	for card in _cards:
		card.set_metrics(scale)
	_size_cards()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_size_cards()


func _size_cards() -> void:
	if size.x <= 1.0:
		return
	var height: float = WorkflowCard.paper_height(size.x, _scale)
	for card in _cards:
		if not card.visible:
			continue
		card.custom_minimum_size = Vector2(0.0, height)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
