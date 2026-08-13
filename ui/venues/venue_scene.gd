class_name VenueScene
extends Control

## A place the player has gone to, as a scene in its own right.
##
## The desk is where the work happens and the room around it is the run. Every
## other screen used to be a slab sliding over that room, which meant the market
## and the job board were always looking at the game through a letterbox — worst
## of all on a handset, where the slab was the whole window anyway and the room
## behind it was a strip of pixels.
##
## So they are places instead. Each one is a photograph of somewhere, with blank
## display panels hanging in it, and the live screen is printed into those panels
## from rects authored beside the picture. Getting there is a real scene change,
## which is why the shell is not underneath any of this.
##
## Two layouts, one scene:
##
## - **Painted.** The picture is the place and the panels land on the surfaces
##   the artwork drew for them. This is the composition on a monitor.
## - **Console.** Where a design pixel is too small to read — which is every
##   handset, and is what `ConsoleMetrics` exists to detect — a painted
##   composition is a worse answer than the slab was, not a better one. The
##   picture drops back to atmosphere and the same panels reflow into one
##   scrolling column at a size a thumb can work. Nothing is authored twice.
##
## Subclasses name the venue, add their panels, and fill them in `refresh`.
## Those overriding `_ready` must call `super._ready()`.

## How far the place is dimmed behind its own panels. Light in painted mode
## because the photograph *is* the screen the player is reading; heavy in console
## mode because there it is only mood behind a column of type.
const SCRIM_PAINTED := 0.20
## Nearly opaque. The place is still behind the column, but a practical light in
## the artwork showing through a gap between two panels reads as a rendering
## fault rather than as atmosphere.
const SCRIM_CONSOLE := 0.93

## How much wider or taller than the window the artwork may be drawn and still be
## laid out on. The picture is cover-cropped rather than letterboxed, so a window
## that is not the shape of the art magnifies it — and the panel rects are
## fractions of that art, so they magnify with it and march off the window. This
## allows the trim a 16:10 or 3:2 screen costs and refuses the 4:3, 5:4 and
## portrait shapes, where the crop is severe enough to walk panels into each
## other. Past it the place prints its console column instead, which fits any
## window because a container decides the layout rather than the paint.
const PAINTED_CROP_LIMIT := 1.2

## Kept off the window edge, so a panel the artwork painted flush to the frame
## still reads as an object in a room.
const EDGE_PAD := 8.0
const CONSOLE_PAD := 12
const CONSOLE_GAP := 10

## How much wider than tall the window has to be before the reflow runs two
## columns instead of one. A handset held on its side is the case this is for: the
## column is sized in millimetres for the thumb, so a screen only a few
## centimetres tall fits four rows of it, and the width it has going spare is the
## only place the rest can go.
const WIDE_CONSOLE_ASPECT := 1.6
## Narrowest a console column may be, in design units at scale 1. Under this a row
## cannot print a caption and its figure on one line, and two cramped columns are
## worse than one that reads.
const CONSOLE_COLUMN_MIN := 300.0

## Where the way out sorts to in console mode. Far negative so it is the first
## thing in the column: a player who came to the wrong place should not have to
## scroll to the bottom to leave.
const BACK_ORDER := -1000

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

var _under: ColorRect = null
var _backdrop: TextureRect = null
var _scrim: ColorRect = null
## Host for the painted composition, where panels are positioned by hand.
var _stage: Control = null
## Host for the console column, where a container positions them instead.
var _console: ScrollContainer = null
## Holds the console columns side by side.
var _console_row: HBoxContainer = null
var _column: VBoxContainer = null
## The second console column, used only where the window is short and wide.
var _column_b: VBoxContainer = null
## How many columns the reflow is currently using.
var _console_columns: int = 1
## `{"region", "panel", "order", "console_hide", "console_min", "grow"}`
var _entries: Array[Dictionary] = []
var _hints: VenuePanel = null
var _back_row: ConsoleMenuRow = null
var _hint_rows: Array[ConsoleMenuRow] = []
var _console_mode: bool = false
## Which layout the panels are currently parented for, so a resize only moves
## them between hosts when the answer actually changed.
var _mounted_mode: String = ""
var _scale: float = 1.0
## Guards the layout against being re-entered by the minimum-size reports its own
## resizing produces.
var _laying_out: bool = false
var _relayout_queued: bool = false


# --- Subclass contract -------------------------------------------------------

## Which entry in the catalog's `venue_scenes` block this place is.
func venue_key() -> String:
	return ""


## Where the subclass adds its panels. Called once, before the first layout.
func _build_venue() -> void:
	pass


## Redraws whatever the panels are showing. Called on mount and by the
## `ui_refresh` group.
func refresh() -> void:
	pass


## Called after every layout pass, once the panels have their final rects and
## metrics. For anything that has to be measured rather than declared — how many
## tiles fit across the board, mostly.
func _on_venue_layout() -> void:
	pass


## Extra key hints printed with the way out, as
## `{"index": "ENTER", "headline": "VIEW"}`.
func _hint_entries() -> Array:
	return []


# --- Chassis ----------------------------------------------------------------

func _ready() -> void:
	UiThemeBuilder.apply(self)
	UiSound.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("ui_refresh")
	add_to_group("console_screens")
	_build_chassis()
	_build_venue()
	_build_hints()
	get_viewport().size_changed.connect(_layout)
	resized.connect(_layout)
	_layout()
	refresh()
	# The panels are sized by the layout pass, and anything that lays itself out
	# against its own width needs a second look once it has one.
	call_deferred("_layout")


func _build_chassis() -> void:
	_under = ColorRect.new()
	_under.name = "Under"
	_under.color = UiThemeBuilder.color("bg")
	_under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_under.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_under)

	_backdrop = TextureRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.texture = AssetCatalog.venue_art(venue_key())
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_scrim)

	_stage = Control.new()
	_stage.name = "Stage"
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)

	_console = ScrollContainer.new()
	_console.name = "Console"
	_console.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_console.visible = false
	add_child(_console)

	# Two columns rather than one, because a handset held on its side has plenty
	# of width and almost no height. The second one is empty and ignored until
	# the window turns out to be that shape.
	_console_row = HBoxContainer.new()
	_console_row.name = "Columns"
	_console_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_console.add_child(_console_row)

	_column = _build_console_column("Column")
	_column_b = _build_console_column("ColumnB")
	_column_b.visible = false


func _build_console_column(node_name: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = node_name
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_FILL
	column.add_theme_constant_override("separation", CONSOLE_GAP)
	_console_row.add_child(column)
	return column


## Registers a panel against a named rect in the artwork.
##
## `options` takes `console_order` (where it sorts in the reflowed column),
## `console_hide` (signage and flavour, which a handset has no room for),
## `console_min` (its height in the column, in design units) and `grow` (whether
## it takes the slack in the column).
func add_panel(region: String, heading: String = "", options: Dictionary = {}) -> VenuePanel:
	var panel := VenuePanel.new()
	panel.name = region.capitalize()
	panel.set_heading(heading)
	# What a panel needs changes while the venue is open — opening a contract
	# sheet in the signage panel is the loud case — and the painted layout is
	# positioned by hand, so nothing would otherwise notice that a panel had
	# outgrown the rect it was placed in.
	panel.minimum_size_changed.connect(_on_panel_minimum_changed)
	_stage.add_child(panel)
	_entries.append({
		"region": region,
		"panel": panel,
		"order": int(options.get("console_order", _entries.size())),
		"console_hide": bool(options.get("console_hide", false)),
		"console_min": float(options.get("console_min", 120.0)),
		"grow": bool(options.get("grow", false)),
	})
	return panel


## The way out, and whatever else the venue wants to say about its keys. Printed
## into the artwork's own hint panel where there is one.
func _build_hints() -> void:
	_hints = add_panel("hints", "", {
		"console_order": BACK_ORDER, "console_min": 0.0,
	})
	var content: VBoxContainer = _hints.content()
	for entry in _hint_entries():
		if not entry is Dictionary:
			continue
		var hint := ConsoleMenuRow.new()
		hint.index_label = str(entry.get("index", ""))
		hint.headline = str(entry.get("headline", ""))
		hint.disabled = true
		content.add_child(hint)
		_hint_rows.append(hint)
	_back_row = ConsoleMenuRow.new()
	_back_row.index_label = "ESC"
	_back_row.headline = "BACK"
	_back_row.pressed.connect(_on_back)
	content.add_child(_back_row)


func _on_back() -> void:
	UiSound.play("tap")
	SceneRouter.back()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# The investor rings over the top of a venue from a layer this scene knows
	# nothing about, so escape belongs to him while he is talking.
	if SceneRouter.investor_busy():
		return
	get_viewport().set_input_as_handled()
	SceneRouter.back()


# --- Layout ------------------------------------------------------------------

## The `console_screens` group contract, so a venue re-fits with everything else.
func fit_console() -> void:
	_layout()


func console_mode() -> bool:
	return _console_mode


func console_scale() -> float:
	return _scale


## Re-runs the layout at the end of the frame, once, however many panels report a
## new minimum in it. Deferred rather than immediate because this arrives from
## inside the container's own sizing pass, and capped at one pass because laying
## out changes widths, which is itself a thing that can change a minimum.
func _on_panel_minimum_changed() -> void:
	if _relayout_queued or _laying_out or _stage == null:
		return
	_relayout_queued = true
	call_deferred("_flush_relayout")


func _flush_relayout() -> void:
	_relayout_queued = false
	_layout()


func _layout() -> void:
	if _stage == null or _laying_out:
		return
	_laying_out = true
	_layout_pass()
	_laying_out = false


func _layout_pass() -> void:
	var view: Vector2 = get_viewport_rect().size
	if size.x > 1.0 and size.y > 1.0:
		view = size
	if view.x <= 1.0 or view.y <= 1.0:
		return
	_scale = ConsoleMetrics.compute_scale(view.y, view.x)
	_console_mode = (
		ConsoleMetrics.needs_focus()
		or not _painted_ready()
		or not _art_carries(view)
	)
	_console_columns = _console_column_count(view) if _console_mode else 1
	_layout_backdrop(view)
	_scrim.color = _scrim_color()
	_mount_panels()
	if _console_mode:
		_layout_console(view)
	else:
		_layout_painted(view)
	for entry in _entries:
		(entry["panel"] as VenuePanel).set_metrics(_scale)
	_layout_hint_rows()
	_on_venue_layout()


## Whether the artwork can actually carry this venue. A place with no picture, or
## with a panel the catalog never measured, has nowhere honest to put its
## screens — so it goes to the console column rather than guessing at rects.
func _painted_ready() -> bool:
	if _backdrop == null or _backdrop.texture == null:
		return false
	for entry in _entries:
		if bool(entry["console_hide"]):
			continue
		var rect: Rect2 = AssetCatalog.venue_region(venue_key(), str(entry["region"]))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return false
	return true


## Whether this window is near enough the artwork's own shape for the painted
## composition to mean anything. It is a question about the window rather than
## about the screen: a tall window on a monitor crops the picture exactly as hard
## as a handset does, and the panels pile into one corner either way.
func _art_carries(view: Vector2) -> bool:
	var drawn: Vector2 = _art_rect(view).size
	if drawn.x <= 0.0 or drawn.y <= 0.0:
		return false
	return (
		drawn.x <= view.x * PAINTED_CROP_LIMIT
		and drawn.y <= view.y * PAINTED_CROP_LIMIT
	)


func _scrim_color() -> Color:
	var base: Color = UiThemeBuilder.color("bg")
	var alpha: float = SCRIM_CONSOLE if _console_mode else SCRIM_PAINTED
	return Color(base.r, base.g, base.b, alpha)


## The picture fills the window and is cropped rather than letterboxed, so a
## place is never a photograph with bars around it. The panels are measured off
## the drawn rect and not off the window, which is what keeps a readout on the
## board it was painted onto when the window is not the design shape.
func _layout_backdrop(view: Vector2) -> void:
	if _backdrop == null:
		return
	_backdrop.visible = _backdrop.texture != null
	if _backdrop.texture == null:
		return
	var drawn: Rect2 = _art_rect(view)
	_backdrop.position = drawn.position
	_backdrop.size = drawn.size


func _art_rect(view: Vector2) -> Rect2:
	if _backdrop == null or _backdrop.texture == null:
		return Rect2(Vector2.ZERO, view)
	var source: Vector2 = _backdrop.texture.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return Rect2(Vector2.ZERO, view)
	var cover: float = maxf(view.x / source.x, view.y / source.y)
	var drawn: Vector2 = source * cover
	return Rect2((view - drawn) * 0.5, drawn)


func _layout_painted(view: Vector2) -> void:
	_stage.visible = true
	_console.visible = false
	var art: Rect2 = _art_rect(view)
	for entry in _entries:
		var panel: VenuePanel = entry["panel"]
		var region: Rect2 = AssetCatalog.venue_region(venue_key(), str(entry["region"]))
		if region.size.x <= 0.0 or region.size.y <= 0.0:
			panel.visible = false
			continue
		panel.visible = true
		var rect := Rect2(
			art.position + region.position * art.size, region.size * art.size
		)
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
		panel.custom_minimum_size = Vector2.ZERO
		panel.size = rect.size
		# A panel cannot be smaller than what is mounted in it, so the rect the
		# artwork authored is a request rather than a guarantee: a contract sheet
		# with a fee, a deadline and an ACCEPT row on it needs more width than a
		# painted panel a tenth of the picture wide. Whatever it actually took is
		# what has to be kept on screen — sizing to the region and trusting it
		# left the accept row hanging off the right edge of the window, drawn but
		# with most of it outside anything the player could press.
		rect.size = rect.size.max(panel.get_combined_minimum_size())
		rect = _clamp_to_window(rect, view)
		panel.position = rect.position
		panel.size = rect.size


## Keeps a panel inside the window: a rect that would hang over an edge is pulled
## back in, and one wider than the window is trimmed to it. Reached both by a crop
## far from the design aspect and by a panel whose contents came out bigger than
## the surface the artwork painted for them.
func _clamp_to_window(rect: Rect2, view: Vector2) -> Rect2:
	rect.size.x = minf(rect.size.x, view.x - EDGE_PAD * 2.0)
	rect.size.y = minf(rect.size.y, view.y - EDGE_PAD * 2.0)
	rect.position.x = clampf(rect.position.x, EDGE_PAD, view.x - EDGE_PAD - rect.size.x)
	rect.position.y = clampf(rect.position.y, EDGE_PAD, view.y - EDGE_PAD - rect.size.y)
	return rect


## Whether this window can carry a second column without either of them becoming
## too narrow to print a caption and its figure on one line.
func _console_column_count(view: Vector2) -> int:
	if view.x < view.y * WIDE_CONSOLE_ASPECT:
		return 1
	var narrowest: float = float(ConsoleMetrics.px(CONSOLE_COLUMN_MIN, _scale))
	return 2 if view.x >= narrowest * 2.0 else 1


func _layout_console(view: Vector2) -> void:
	_stage.visible = false
	_console.visible = true
	var pad: float = float(ConsoleMetrics.px(CONSOLE_PAD, _scale))
	_console.position = Vector2(pad, pad)
	_console.size = view - Vector2(pad, pad) * 2.0
	var gap: int = ConsoleMetrics.px(CONSOLE_GAP, _scale)
	_console_row.add_theme_constant_override("separation", gap)
	_column.add_theme_constant_override("separation", gap)
	_column_b.add_theme_constant_override("separation", gap)
	_column_b.visible = _console_columns > 1
	for entry in _entries:
		var panel: VenuePanel = entry["panel"]
		if bool(entry["console_hide"]):
			panel.visible = false
			continue
		panel.visible = true
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = (
			Control.SIZE_EXPAND_FILL if bool(entry["grow"]) else Control.SIZE_FILL
		)
		panel.custom_minimum_size = Vector2(
			0.0, float(entry["console_min"]) * _scale
		)


## Moves the panels between the hosts, which is the whole of the difference
## between the layouts: the same nodes, positioned by the artwork or stacked by a
## container.
func _mount_panels() -> void:
	var wanted: String = "painted"
	if _console_mode:
		wanted = "console:%d" % _console_columns
	if _mounted_mode == wanted:
		return
	_mounted_mode = wanted
	var ordered: Array[Dictionary] = _entries.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["order"]) < int(b["order"])
	)
	if not _console_mode:
		for entry in ordered:
			_mount_panel(entry["panel"], _stage)
		return
	var hosts: Array[VBoxContainer] = [_column]
	if _console_columns > 1:
		hosts.append(_column_b)
	# Filled by weight rather than by dealing them out in turn, so a tall board
	# and a short index end up beside each other instead of one column running off
	# the bottom of a screen the other has left half empty. The way out is pinned
	# to the head of the first column: a player who came to the wrong place should
	# find it where they started reading.
	var filled: Array[float] = []
	filled.resize(hosts.size())
	filled.fill(0.0)
	for entry in ordered:
		var index: int = 0
		if hosts.size() > 1 and int(entry["order"]) != BACK_ORDER:
			for i in range(hosts.size()):
				if filled[i] < filled[index]:
					index = i
		_mount_panel(entry["panel"], hosts[index])
		if not bool(entry["console_hide"]):
			filled[index] += float(entry["console_min"])


func _mount_panel(panel: VenuePanel, host: Node) -> void:
	if panel.get_parent() != host:
		panel.reparent(host)
	host.move_child(panel, host.get_child_count() - 1)


func _layout_hint_rows() -> void:
	var font: int = ConsoleMetrics.font_small(_scale)
	var height: int = ConsoleMetrics.row_height(_scale)
	var pad: int = ConsoleMetrics.pad_h(_scale)
	for row in _hint_rows:
		row.set_metrics(font, height, pad)
		# The key legend is desk furniture: a handset has no arrow keys and no
		# room to say so, so only the way out survives the reflow.
		row.visible = not _console_mode
	if _back_row != null:
		_back_row.set_metrics(font, height, pad)


## How wide whatever is mounted in `region` actually gets to be.
##
## Answered from the layout this venue just performed rather than by measuring the
## containers inside the panel, which are a frame or two behind and settle on the
## wrong answer in between. Anything sizing itself by column count needs the real
## number on the first pass.
func content_width(region: String) -> float:
	var pad: float = float(ConsoleMetrics.px(VenuePanel.PAD, _scale)) * 2.0
	if _console_mode:
		# Less the gutter the column's own scrollbar takes.
		return maxf(0.0, _console.size.x - pad - float(ConsoleMetrics.px(14, _scale)))
	# The panel's own width rather than the region's, because a panel is allowed
	# to come out wider than the surface the artwork painted for it.
	for entry in _entries:
		if str(entry["region"]) == region:
			var panel: VenuePanel = entry["panel"]
			if panel.size.x > 1.0:
				return maxf(0.0, panel.size.x - pad)
			break
	return maxf(0.0, region_rect(region).size.x - pad)


## The rect a named region landed on, for a venue that wants to mount something
## of its own against the artwork rather than into a panel.
func region_rect(region: String) -> Rect2:
	var view: Vector2 = size if size.x > 1.0 else get_viewport_rect().size
	var normalized: Rect2 = AssetCatalog.venue_region(venue_key(), region)
	if normalized.size.x <= 0.0:
		return Rect2()
	var art: Rect2 = _art_rect(view)
	return _clamp_to_window(
		Rect2(art.position + normalized.position * art.size, normalized.size * art.size),
		view
	)
