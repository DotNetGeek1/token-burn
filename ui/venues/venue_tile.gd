class_name VenueTile
extends PanelContainer

## One item on a venue's board: a machine on the market's shelf, a contract on
## the job board, a perk in the build sheet.
##
## The catalogue screens used to print as tables, because the side panel was 442
## pixels wide and a table is what fits in a column that narrow. A board on a
## wall is not a column, so the same listing reads as a grid of cards with the
## figure that matters set large — which is the one thing a price list cannot do.
##
## Four lines, in the order a buyer reads them: what it is, what it does for you,
## what it costs you to run, and what it costs to take.
##
## A container with the press surface laid over it, rather than a Button with the
## lines inside: a Button is not a container, so nothing would carry the height of
## its own contents back up and a grid of them collapses onto one line.

signal pressed
signal action_pressed(meta: Variant)

const PAD := 8
const GAP := 4

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

## Whatever the board wants back when this tile is pressed.
var meta: Variant = null

var _margin: MarginContainer = null
var _body: VBoxContainer = null
var _name: Label = null
var _figure_row: HBoxContainer = null
var _icon: TextureRect = null
var _figure: Label = null
var _unit: Label = null
var _spec: Label = null
var _foot: HBoxContainer = null
var _price: Label = null
var _status: Label = null
var _action: Button = null
var _surface: Button = null
var _selected: bool = false
var _compact: bool = false


func _init() -> void:
	_build()


func _build() -> void:
	if _body != null:
		return
	# Both layers pass pointer events so a drag can climb from the button surface
	# to the VenueBoard ScrollContainer instead of stopping on the highlighted
	# tile.
	mouse_filter = Control.MOUSE_FILTER_PASS
	_margin = MarginContainer.new()
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_%s" % side, PAD)
	add_child(_margin)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", GAP)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(_body)

	_name = ConsoleStyle.label("", ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_name)

	# The headline figure is why the player is looking at the tile at all, so it
	# gets the icon beside it and the largest type on the card.
	_figure_row = HBoxContainer.new()
	_figure_row.add_theme_constant_override("separation", GAP * 2)
	_figure_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_figure_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_figure_row)

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.modulate = ConsoleStyle.PHOSPHOR_DIM
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_figure_row.add_child(_icon)

	var figure_box := VBoxContainer.new()
	figure_box.add_theme_constant_override("separation", 0)
	figure_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	figure_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	figure_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_figure_row.add_child(figure_box)

	_figure = ConsoleStyle.label("", ConsoleStyle.FONT_HEAD, ConsoleStyle.PHOSPHOR)
	_figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_figure.clip_text = true
	figure_box.add_child(_figure)

	_unit = ConsoleStyle.label("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_unit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	figure_box.add_child(_unit)

	_spec = ConsoleStyle.label("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_spec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_spec)

	_foot = HBoxContainer.new()
	_foot.add_theme_constant_override("separation", GAP)
	_foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_foot)

	_price = ConsoleStyle.label("", ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR)
	_price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_foot.add_child(_price)

	_status = ConsoleStyle.label("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_foot.add_child(_status)

	# Added last so it sits over the lines and takes the press. It carries no
	# look of its own; the frame around the card is this control's stylebox.
	_surface = Button.new()
	_surface.flat = true
	_surface.mouse_filter = Control.MOUSE_FILTER_PASS
	_surface.focus_mode = Control.FOCUS_ALL
	_surface.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		_surface.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_surface.pressed.connect(_on_surface_pressed)
	for signal_name in ["mouse_entered", "mouse_exited", "focus_entered", "focus_exited"]:
		_surface.connect(signal_name, _apply_palette)
	add_child(_surface)
	# Keep the full-card press surface behind the content. Labels ignore input,
	# while an optional per-card action remains a genuine button above it.
	move_child(_surface, 0)

	_action = Button.new()
	_action.visible = false
	_action.clip_text = true
	_action.focus_mode = Control.FOCUS_ALL
	_action.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_action.add_theme_font_override("font", UiThemeBuilder.mono_font())
	_action.pressed.connect(func() -> void:
		UiSound.play("tap")
		action_pressed.emit(meta)
	)
	_body.add_child(_action)

	_apply_palette()


func _on_surface_pressed() -> void:
	UiSound.play("tap")
	pressed.emit()


## Everything printed on the tile in one call, because a half-set tile is a bug
## the board cannot see.
func set_entry(entry: Dictionary) -> void:
	_build()
	meta = entry.get("meta", null)
	_name.text = str(entry.get("name", "")).to_upper()
	_figure.text = str(entry.get("figure", ""))
	_unit.text = str(entry.get("unit", "")).to_upper()
	_unit.visible = _unit.text != "" and not _compact
	_spec.text = str(entry.get("spec", ""))
	_spec.visible = _spec.text != ""
	_price.text = str(entry.get("price", ""))
	_status.text = str(entry.get("status", "")).to_upper()
	_price.add_theme_color_override(
		"font_color", Color(entry.get("price_color", ConsoleStyle.PHOSPHOR))
	)
	_status.add_theme_color_override(
		"font_color", Color(entry.get("status_color", ConsoleStyle.PHOSPHOR_DIM))
	)
	_figure.add_theme_color_override(
		"font_color", Color(entry.get("figure_color", ConsoleStyle.PHOSPHOR))
	)
	var icon: Variant = entry.get("icon", null)
	_icon.texture = icon if icon is Texture2D else null
	_icon.visible = _icon.texture != null
	_surface.tooltip_text = str(entry.get("tooltip", ""))
	var action_text: String = str(entry.get("action_text", ""))
	_action.text = action_text.to_upper()
	_action.visible = action_text != ""
	_action.disabled = not bool(entry.get("action_enabled", true))
	_action.tooltip_text = str(entry.get("action_tooltip", ""))
	_style_action(bool(entry.get("action_warning", false)))


func _style_action(warning: bool) -> void:
	if _action == null:
		return
	var lit: Color = ConsoleStyle.WARNING if warning else ConsoleStyle.PHOSPHOR
	_action.add_theme_color_override("font_color", lit)
	_action.add_theme_color_override("font_hover_color", ConsoleStyle.INK)
	_action.add_theme_color_override("font_pressed_color", ConsoleStyle.INK)
	_action.add_theme_color_override("font_disabled_color", ConsoleStyle.PHOSPHOR_DIM)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box_state: String = "normal" if _action.disabled else state
		_action.add_theme_stylebox_override(state, ConsoleStyle.row_box(box_state, lit))


## Whether the card puts its figure on a line of its own.
##
## A shelf of machines is read by scanning the figures down a column, so there the
## figure gets its own line and the largest type on the card. A pipeline is read as
## an order, one stage per row across the full width of the board, and a card three
## lines deep means two stages on screen where the old table showed six — so the
## name and the figure share a line instead.
func set_compact(compact: bool) -> void:
	_build()
	if _compact == compact:
		return
	_compact = compact
	# Sharing the line means something has to give when the row is tight, and it
	# cannot be the figure: `clip_text` reports no minimum width at all, so the
	# name took the whole row and a rate came out as "0.0M/prompt" with its leading
	# digits cut off. Off the clip, the figure keeps its width and the name — which
	# wraps — is what gives. In the grid the figure has a line to its own and the
	# clip stays on, because there a long one would set the width of every column.
	_figure.clip_text = not compact
	_name.get_parent().remove_child(_name)
	if compact:
		_figure_row.add_child(_name)
		_figure_row.move_child(_name, 1)
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_figure_row.size_flags_vertical = Control.SIZE_FILL
	else:
		_body.add_child(_name)
		_body.move_child(_name, 0)
		_name.size_flags_horizontal = Control.SIZE_FILL
		_name.size_flags_vertical = Control.SIZE_FILL
		_figure_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_unit.visible = not compact and _unit.text != ""


func set_selected(selected: bool) -> void:
	_selected = selected
	_apply_palette()


## A selected tile is the lit one on the board. Hover and selection both raise
## the edge rather than flooding the card, so a grid of these stays a grid of
## dark panels with one of them powered up.
func _apply_palette() -> void:
	if _surface == null:
		return
	var border: float = 0.22
	var fill: float = 0.03
	if _selected:
		border = 0.55
		fill = 0.09
	if _surface.is_hovered() or _surface.has_focus():
		border = 0.75
		fill = 0.11
	add_theme_stylebox_override("panel", ConsoleStyle.frame_box(border, fill))


func set_metrics(scale: float) -> void:
	_build()
	var pad: int = ConsoleMetrics.px(PAD, scale)
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_%s" % side, pad)
	var gap: int = ConsoleMetrics.px(GAP, scale)
	_body.add_theme_constant_override("separation", gap)
	_figure_row.add_theme_constant_override("separation", gap * 2)
	_foot.add_theme_constant_override("separation", gap)
	_name.add_theme_font_size_override("font_size", ConsoleMetrics.font_small(scale))
	_figure.add_theme_font_size_override("font_size", ConsoleMetrics.font_head(scale))
	_unit.add_theme_font_size_override("font_size", ConsoleMetrics.font_tiny(scale))
	_spec.add_theme_font_size_override("font_size", ConsoleMetrics.font_tiny(scale))
	_price.add_theme_font_size_override("font_size", ConsoleMetrics.font_small(scale))
	_status.add_theme_font_size_override("font_size", ConsoleMetrics.font_tiny(scale))
	_action.add_theme_font_size_override("font_size", ConsoleMetrics.font_small(scale))
	_action.custom_minimum_size.y = ConsoleMetrics.action_height(scale)
	var glyph: float = float(ConsoleMetrics.px(26, scale))
	_icon.custom_minimum_size = Vector2(glyph, glyph)
