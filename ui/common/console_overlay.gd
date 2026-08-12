class_name ConsoleOverlay
extends Control

## A console screen that arrives over the room instead of in the side panel.
##
## The panel screens get their chrome from `ConsoleFrame`, but the overlays —
## workflows, the trophy cabinet, the debrief — are modal: they dim the desk,
## centre themselves on the glass and have to be dismissed. Each one used to
## carry its own panel, margins, header and close button, which is how they all
## drifted out of the console language. They share this shell instead, so an
## overlay only has to fill `content()` and say what its footer does.
##
## Subclasses that override `_ready` must call `super._ready()`.

## Emitted after the overlay has been dismissed, however it was dismissed.
signal closed

## The widest the glass gets on a big monitor. Past this, console text is
## running across a metre of desk and the eye loses the column.
const MAX_WIDTH := 720.0
const EDGE_PAD := 16
const SCRIM := Color(0.0, 0.0, 0.0, 0.62)

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

var _scrim: ColorRect = null
var _frame: ConsoleFrame = null
var _body: VBoxContainer = null
var _footer: VBoxContainer = null
var _footer_rule: ColorRect = null
var _close_row: ConsoleMenuRow = null
var _action_rows: Array[ConsoleMenuRow] = []
var _scale: float = 1.0
var _scrim_tap := TapGesture.new()
## Whether tapping the dimmed room behind the overlay dismisses it. Off for
## overlays that are a decision the player has to actually answer.
var dismiss_on_scrim: bool = true
## Whether the glass shrinks to the height of what is printed on it. A screen
## full of listings wants the whole window; a five-line confirmation does not.
var compact: bool = false
## The cap `MAX_WIDTH` sets is about keeping a column of console text readable.
## An overlay that lays things out side by side rather than printing lines can
## raise it, because its content is what stops the eye instead.
var max_width: float = MAX_WIDTH


func _ready() -> void:
	_ensure_built()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("flow_overlay")
	add_to_group("console_screens")
	resized.connect(_fit_console)
	visibility_changed.connect(func() -> void:
		if visible:
			call_deferred("_fit_console")
	)


func _ensure_built() -> void:
	if _frame != null:
		return

	_scrim = ColorRect.new()
	_scrim.color = SCRIM
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)

	_frame = ConsoleFrame.new()
	_frame.name = "Panel"
	add_child(_frame)
	_frame.setup("console")

	var frame_content: VBoxContainer = _frame.content()

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame_content.add_child(_body)

	_footer_rule = ConsoleStyle.rule(0.22)
	frame_content.add_child(_footer_rule)

	_footer = VBoxContainer.new()
	_footer.add_theme_constant_override("separation", 0)
	frame_content.add_child(_footer)

	_close_row = ConsoleMenuRow.new()
	_close_row.index_label = "ESC"
	_close_row.headline = "CLOSE"
	_close_row.pressed.connect(close)
	_footer.add_child(_close_row)


## The screen name printed in the frame's header ticker.
func setup(screen_name: String) -> void:
	_ensure_built()
	_frame.setup(screen_name)


## Where a subclass builds its tables, detail panes and readouts.
func content() -> VBoxContainer:
	_ensure_built()
	return _body


func set_context(text: String, color: Color = ConsoleStyle.PHOSPHOR_DIM) -> void:
	_ensure_built()
	_frame.set_context(text, color)


## Footer commands, printed above the close line. Each entry is
## `{"index": "1", "headline": "DELIVER", "value": "", "destructive": false,
## "enabled": true, "pressed": Callable}`.
func set_actions(entries: Array) -> void:
	_ensure_built()
	for row in _action_rows:
		_footer.remove_child(row)
		row.queue_free()
	_action_rows.clear()
	for entry in entries:
		if not entry is Dictionary:
			continue
		var row := ConsoleMenuRow.new()
		_footer.add_child(row)
		_footer.move_child(row, _footer.get_child_count() - 2)
		row.index_label = str(entry.get("index", str(_action_rows.size() + 1)))
		row.headline = str(entry.get("headline", ""))
		row.value_text = str(entry.get("value", ""))
		row.destructive = bool(entry.get("destructive", false))
		var enabled: bool = bool(entry.get("enabled", true))
		row.disabled = not enabled
		row.modulate.a = 1.0 if enabled else 0.45
		var handler: Variant = entry.get("pressed", null)
		if enabled and handler is Callable:
			row.pressed.connect(handler)
		_action_rows.append(row)
	_apply_metrics()


## Relabels the dismiss line, for overlays where leaving means something more
## specific than closing a window.
func set_close_label(headline: String, index_label: String = "ESC") -> void:
	_ensure_built()
	_close_row.headline = headline
	_close_row.index_label = index_label


func set_closable(value: bool) -> void:
	_ensure_built()
	_close_row.visible = value
	_footer_rule.visible = value or not _action_rows.is_empty()


func open() -> void:
	_ensure_built()
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Shown before the refresh, because a screen that only redraws itself while
	# it is on the glass would otherwise open empty.
	UiTransition.enter(self, _frame)
	if has_method("refresh"):
		call("refresh")
	call_deferred("_fit_console")
	get_tree().call_group("main_ui", "sync_overlay_input")


func close() -> void:
	hide_overlay()
	get_tree().call_group("main_ui", "refresh_all")


## The `flow_overlay` group contract: returning to the title dismisses every
## overlay through this, without refreshing the run behind it.
func hide_overlay() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_inside_tree():
		get_tree().call_group("main_ui", "sync_overlay_input")
	closed.emit()


func _on_scrim_input(event: InputEvent) -> void:
	if dismiss_on_scrim and _scrim_tap.feed(event):
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _close_row.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Called by `main.gd` whenever the room is laid out, and by `open`.
func fit_console() -> void:
	_fit_console()


func _fit_console() -> void:
	if _frame == null:
		return
	var area: Vector2 = _window()
	if area.x <= 1.0 or area.y <= 1.0:
		return
	_scale = ConsoleMetrics.compute_scale(area.y, area.x)
	_apply_metrics()
	# Centred on the glass and inset from every edge, so the room stays visible
	# around it and the overlay reads as something laid on top of the desk.
	var pad: float = float(ConsoleMetrics.px(EDGE_PAD, _scale))
	var width: float = minf(area.x - pad * 2.0, max_width * _scale)
	var height: float = area.y - pad * 2.0
	if compact:
		height = clampf(_frame.get_combined_minimum_size().y, 0.0, height)
	_frame.set_anchors_preset(Control.PRESET_CENTER)
	_frame.offset_left = -width * 0.5
	_frame.offset_right = width * 0.5
	_frame.offset_top = -height * 0.5
	_frame.offset_bottom = height * 0.5


## The overlay is always the whole window, but it is often built and mounted in
## the same frame its host is, before the layout pass has given it a rect. The
## parent's area — and failing that the viewport — is the size it is going to
## end up at anyway.
func _window() -> Vector2:
	if size.x > 1.0 and size.y > 1.0:
		return size
	var parent_area: Vector2 = get_parent_area_size()
	if parent_area.x > 1.0 and parent_area.y > 1.0:
		return parent_area
	return get_viewport_rect().size


func _apply_metrics() -> void:
	if _frame == null:
		return
	_frame.set_metrics(_scale)
	_body.add_theme_constant_override("separation", ConsoleMetrics.px(8, _scale))
	var font_small: int = ConsoleMetrics.font_small(_scale)
	var height: int = ConsoleMetrics.row_height(_scale)
	var pad_h: int = ConsoleMetrics.pad_h(_scale)
	for row in _action_rows:
		row.set_metrics(font_small, height, pad_h)
	_close_row.set_metrics(font_small, height, pad_h)


## The scale the shell settled on, for subclasses sizing their own widgets.
func console_scale() -> float:
	return _scale
