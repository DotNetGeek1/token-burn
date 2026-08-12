class_name ConsoleSheet
extends ConsoleOverlay

## The console's answer to `DetailSheet`: the long text, the full numbers and the
## confirm/walk-away pair, printed on the glass rather than raised on a rounded
## card.
##
## It keeps `DetailSheet`'s call signature so the screens that open one did not
## have to be rewritten to change their looks — the same `show_detail` arguments
## print as terminal output here.

signal action_confirmed
## Second way out of the same decision. A sheet that offers only one action makes
## the alternative invisible, which is wrong when the alternative is "walk away".
signal secondary_confirmed

var _scroll: ScrollContainer = null
var _lines: VBoxContainer = null
var _chips: Label = null


func _ready() -> void:
	super._ready()
	setup("detail")
	# A sheet is a decision, so it is dismissed deliberately rather than by a
	# stray tap on the room behind it.
	dismiss_on_scrim = false
	compact = true
	_build_body()


func _build_body() -> void:
	if _lines != null:
		return
	var body: VBoxContainer = content()

	_chips = ConsoleStyle.label("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_chips.visible = false
	body.add_child(_chips)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)

	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 4)
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_lines)
	# Wrapped paragraphs report a tall minimum until they have been given a
	# width, so the body is measured again once it has actually been laid out.
	_lines.resized.connect(func() -> void: call_deferred("_fit_lines"))


## `rows` takes the shared detail vocabulary from `ConsoleStyle.detail_line`,
## plus the `role` key the old sheet used to colour a value.
func show_detail(
	title: String,
	kicker: String,
	rows: Array,
	chips: Array = [],
	action_text: String = "",
	accent: Color = Color.TRANSPARENT,
	secondary_text: String = ""
) -> void:
	_build_body()
	setup(title)
	set_context(
		kicker.to_upper(),
		accent if accent != Color.TRANSPARENT else ConsoleStyle.PHOSPHOR_DIM
	)
	_set_chips(chips)
	_set_rows(rows)
	_set_actions(action_text, secondary_text)
	open()


## A sheet that is only a block of text — a cost forecast, a note — with no
## decision attached to it.
func show_content(title: String, body: String) -> void:
	show_detail(title, "", [{"text": body}])


## Kept so the screens that spoke to `DetailSheet` can still dismiss the sheet
## by the name they know.
func hide_sheet() -> void:
	hide_overlay()


func _set_chips(chips: Array) -> void:
	var tags: PackedStringArray = []
	for chip in chips:
		var text: String = str(chip.get("text", "")) if chip is Dictionary else str(chip)
		if text.strip_edges() != "":
			tags.append("[ %s ]" % text.to_upper())
	_chips.text = " ".join(tags)
	_chips.visible = not tags.is_empty()
	_chips.add_theme_font_size_override(
		"font_size", ConsoleMetrics.font_tiny(console_scale())
	)


func _set_rows(rows: Array) -> void:
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	var font_small: int = ConsoleMetrics.font_small(console_scale())
	var separation: int = ConsoleMetrics.px(8, console_scale())
	for row in rows:
		var line: Control = ConsoleStyle.detail_line(_normalise(row), font_small, separation)
		if line != null:
			_lines.add_child(line)
	call_deferred("_fit_lines")


## The body is as tall as its text wants, up to half the window; past that it
## scrolls rather than pushing the confirm line off the bottom of the glass.
func _fit_lines() -> void:
	if _scroll == null:
		return
	var cap: float = get_viewport_rect().size.y * 0.5
	var wanted: float = _lines.get_combined_minimum_size().y
	_scroll.custom_minimum_size = Vector2(0.0, minf(wanted, cap))
	fit_console()


## The old sheet coloured a value by naming a theme role. Console output has one
## palette, so a role only decides whether the figure is ordinary, a warning or
## a loss.
func _normalise(row: Variant) -> Variant:
	if not row is Dictionary:
		return row
	var entry: Dictionary = (row as Dictionary).duplicate()
	if entry.has("role") and not entry.has("color"):
		match str(entry["role"]):
			"danger", "red", "heat":
				entry["color"] = ConsoleStyle.DANGER
			"warning", "risk":
				entry["color"] = ConsoleStyle.WARNING
			_:
				entry["color"] = ConsoleStyle.PHOSPHOR
	return entry


func _set_actions(action_text: String, secondary_text: String) -> void:
	var entries: Array = []
	if action_text != "":
		entries.append({
			"index": "1",
			"headline": action_text.to_upper(),
			"pressed": func() -> void:
				action_confirmed.emit()
				hide_sheet(),
		})
	if secondary_text != "":
		entries.append({
			"index": "2",
			"headline": secondary_text.to_upper(),
			"destructive": true,
			"pressed": func() -> void:
				secondary_confirmed.emit()
				hide_sheet(),
		})
	set_actions(entries)
