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
## Three layouts, one scene:
##
## - **Painted.** The picture is the place and the panels land on the surfaces
##   the artwork drew for them. This is the composition on a monitor.
## - **Room.** On a handset a design pixel is too small to read, so the place is
##   worked the way the desk is. The whole of it is on screen and every panel
##   prints its whole screenful at the size it was authored — the monitor's
##   composition, shrunk with the room it hangs in, so the place reads as somewhere
##   with screens in it that are too far away to make out. Pressing one walks the
##   camera up to it until it is at reading size. Nothing is reflowed and nothing
##   is blanked; the player just gets nearer.
## - **Console.** The fallback for a place the artwork cannot carry — no picture,
##   or a panel the catalog never measured — and for a desktop window so far from
##   the shape of the art that the painted rects no longer land on it. The panels
##   stack into scrolling columns that fit any window. Nothing is authored twice.
##
## Subclasses name the venue, add their panels, and fill them in `refresh`.
## Those overriding `_ready` must call `super._ready()`.

## How far the place is dimmed behind its own panels. Light where the picture is
## the screen the player is reading — painted and room alike; heavy in console mode
## because there it is only mood behind a column of type.
const SCRIM_PAINTED := 0.20
## Nearly opaque. The place is still behind the column, but a practical light in
## the artwork showing through a gap between two panels reads as a rendering
## fault rather than as atmosphere.
const SCRIM_CONSOLE := 0.93

## How far from the shape of the artwork a window may be and still be painted on.
## See `_shape_fits`.
const STRETCH_LIMIT := 1.45

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

## How long the camera takes to walk up to a panel. Matches the desk's own lean-in,
## because it is the same gesture in a different room.
const LEAN_SECONDS := 0.26


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
## `{"region", "panel", "surface", "order", "console_hide", "painted_hide",
## "console_min", "grow"}`
var _entries: Array[Dictionary] = []
var _hints: VenuePanel = null
var _back_row: ConsoleMenuRow = null
var _hint_rows: Array[ConsoleMenuRow] = []
var _console_mode: bool = false
## Whether the place is being looked at whole and leant in on, rather than read
## where it hangs. Only ever true where `ConsoleMetrics.needs_focus()`.
var _room_mode: bool = false
## Which panel the player has walked up to, by region name. Empty is the whole room.
var _leaning_on: String = ""
## How far the camera has come forward. 1.0 is the whole place.
var _zoom: float = 1.0
## Where the panel being leant in on sits when the place is seen whole, and the
## zoom that brings it up to reading size.
var _lean_point: Vector2 = Vector2.ZERO
var _lean_zoom: float = 1.0
var _zoom_tween: Tween = null
## The camera, as the transform every drawn rect goes through.
var _cam_origin: Vector2 = Vector2.ZERO
var _cam_zoom: float = 1.0
## Anything the place is not: pressing it steps back out of a panel.
var _wall: Control = null
## The way out for a player who does not know the wall is one.
var _step_back: Button = null
## Which layout the panels are currently parented for, so a resize only moves
## them between hosts when the answer actually changed.
var _mounted_mode: String = ""
var _scale: float = 1.0
## Guards the layout against being re-entered by the minimum-size reports its own
## resizing produces.
var _laying_out: bool = false
var _relayout_queued: bool = false
var _panel_minimums: Dictionary = {}


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


## Whether the artwork contains a physical screen for the key legend. Venues
## without one still keep BACK in the reflowed phone/console column.
func _painted_hints() -> bool:
	return true


## Whether a handset may keep this venue as a painted room and lean into its
## panels. Dense venues can opt out when a narrow painted panel would need more
## zoom than the window can show; they then use the scrolling console layout.
func _room_layout_supported() -> bool:
	return true


## Whether a desktop window outside the artwork's authored aspect may still use
## the painted composition. Handsets remain subject to the console fallback.
func _painted_desktop_at_any_aspect() -> bool:
	return false


# --- Chassis ----------------------------------------------------------------

func _ready() -> void:
	UiThemeBuilder.apply(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("ui_refresh")
	add_to_group("console_screens")
	_build_chassis()
	_build_venue()
	_build_hints()
	_follow_sheets()
	get_viewport().size_changed.connect(_layout)
	resized.connect(_layout)
	_layout()
	refresh()
	# The panels are sized by the layout pass, and anything that lays itself out
	# against its own width needs a second look once it has one.
	call_deferred("_layout")


func route_activated() -> void:
	_layout()
	refresh()
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

	# Anything the place is not is a way out of whatever is being read, and the
	# natural way to write that is to catch what the panels did not. But a panel
	# leant in on fills the window and its own surface swallows presses, so the
	# room is given a surface of its own instead: under the panels, over the
	# picture, live only while the player is leant in on something.
	_wall = Control.new()
	_wall.name = "Wall"
	_wall.mouse_filter = Control.MOUSE_FILTER_STOP
	_wall.visible = false
	_wall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wall.gui_input.connect(_on_wall_input)
	add_child(_wall)

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
	_console_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_console_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_console.add_child(_console_row)

	_column = _build_console_column("Column")
	_column_b = _build_console_column("ColumnB")
	_column_b.visible = false

	_build_step_back()


## The way back to the room, for a player who does not know the wall is one. Drawn
## over the place rather than in it, which is the price of a room being somewhere
## you can get lost in. Bottom right, because leaning in walks a panel into the
## middle of the window and the way out should not be written over it.
func _build_step_back() -> void:
	_step_back = Button.new()
	_step_back.name = "StepBack"
	_step_back.text = "◄ ROOM"
	_step_back.flat = true
	_step_back.focus_mode = Control.FOCUS_NONE
	_step_back.visible = false
	var font: Font = UiThemeBuilder.mono_font()
	if font != null:
		_step_back.add_theme_font_override("font", font)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		_step_back.add_theme_color_override(state, ConsoleStyle.PHOSPHOR)
	_step_back.pressed.connect(func() -> void:
		UiSound.play("tap")
		if _leaning_on != "":
			step_back_to_room()
			return
		SceneRouter.back()
	)
	add_child(_step_back)


func _build_console_column(node_name: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = node_name
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	# Native uses the true projective mount. Web cannot safely keep the
	# SubViewport + Polygon2D pair alive across routed screens, so it keeps a
	# plain Node2D which `_place_panel_affine` skews onto the photographed plane.
	# That preserves perspective without the render-resource teardown that caused
	# blank canvases.
	var measured: PackedVector2Array = AssetCatalog.venue_plane(venue_key(), region)
	var surface: Node = VenueSurface.new() if _uses_warped_surface(measured) else Node2D.new()
	surface.name = "%sSurface" % region.capitalize()
	_stage.add_child(surface)
	# What a panel needs changes while the venue is open — opening a contract
	# sheet in the signage panel is the loud case — and the painted layout is
	# positioned by hand, so nothing would otherwise notice that a panel had
	# outgrown the rect it was placed in.
	panel.minimum_size_changed.connect(_on_panel_minimum_changed)
	panel.pressed.connect(lean_on.bind(region))
	surface.add_child(panel)
	_entries.append({
		"region": region,
		"panel": panel,
		"surface": surface,
		"order": int(options.get("console_order", _entries.size())),
		"console_hide": bool(options.get("console_hide", false)),
		"painted_hide": bool(options.get("painted_hide", false)),
		"console_min": float(options.get("console_min", 120.0)),
		"grow": bool(options.get("grow", false)),
	})
	return panel


func _uses_warped_surface(measured: PackedVector2Array) -> bool:
	return measured.size() == 4 and not _is_web()


func _is_web() -> bool:
	return OS.has_feature("web") or OS.get_name() == "Web"


## The way out, and whatever else the venue wants to say about its keys. Printed
## into the artwork's own hint panel where there is one.
func _build_hints() -> void:
	_hints = add_panel("hints", "", {
		"console_order": BACK_ORDER,
		"console_min": 0.0,
		"painted_hide": not _painted_hints(),
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


## Makes the room follow the sheets a venue prints.
##
## The detail of a chosen thing is not printed where it was chosen: a shop puts the
## sheet on the board beside the shelf, the office puts the contract on the pad
## beside the wire. On a monitor that is the composition — the thing and its terms
## side by side. In room mode the player is stood at the shelf and the sheet is on a
## panel behind them, with the one row that accepts it, so the room walks them over
## to it and back out again when it goes.
##
## Watched rather than announced, because a venue already says where its sheet is by
## putting it in a panel, and saying it twice is a thing that can disagree.
func _follow_sheets() -> void:
	for entry in _entries:
		for sheet in _sheets_in(entry["panel"]):
			sheet.visibility_changed.connect(
				_on_sheet_shown.bind(sheet, str(entry["region"]))
			)


func _sheets_in(node: Node) -> Array[ConsoleDetail]:
	var found: Array[ConsoleDetail] = []
	if node is ConsoleDetail:
		found.append(node)
	for child in node.get_children():
		found.append_array(_sheets_in(child))
	return found


func _on_sheet_shown(sheet: ConsoleDetail, region: String) -> void:
	if not _room_mode:
		return
	if sheet.is_visible_in_tree():
		lean_on(region)
	elif _leaning_on == region:
		step_back_to_room()


func _on_back() -> void:
	UiSound.play("tap")
	SceneRouter.back()


func _on_wall_input(event: InputEvent) -> void:
	var released: bool = (
		(event is InputEventMouseButton and not event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT)
		or (event is InputEventScreenTouch and not event.pressed)
	)
	if released:
		step_back_to_room()
		_wall.accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# The investor rings over the top of a venue from a layer this scene knows
	# nothing about, so escape belongs to him while he is talking.
	if SceneRouter.investor_busy():
		return
	get_viewport().set_input_as_handled()
	# Leaning in is somewhere the player has gone, so it is what escape backs out
	# of first. Only once they are looking at the whole place does it leave.
	if _leaning_on != "":
		step_back_to_room()
		return
	SceneRouter.back()


# --- Layout ------------------------------------------------------------------

## The `console_screens` group contract, so a venue re-fits with everything else.
func fit_console() -> void:
	_layout()


func console_mode() -> bool:
	return _console_mode


## What the type on this place is currently sized against.
##
## Normally the readability scale: a design pixel is a certain number of
## millimetres on the player's screen and body text has a millimetre target to
## hit. A place seen whole on a handset cannot honour that — the panels are a
## centimetre across, and type at reading size in them would be three words and a
## clipped edge — so it prints at the size it was authored, which is the
## composition a monitor gets, shrunk with the room it is in. It reads as a shop
## with screens in it that are too far away to make out, and that is exactly what
## it is. Leaning in on one puts it back on the millimetre target.
func console_scale() -> float:
	if _room_mode:
		return _lean_scale() if _leaning_on != "" else 1.0
	return _scale


## The scale for a panel the player has come up to: the millimetre target, which is
## the whole reason for having come. The room only ever makes the panel wide enough
## for it — a long one scrolls rather than shrinking its type back down.
func _lean_scale() -> float:
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
	if not _panel_minimums_changed():
		return
	_layout()


func _panel_minimums_changed() -> bool:
	for entry in _entries:
		var panel: VenuePanel = entry["panel"]
		var key: int = panel.get_instance_id()
		if not _panel_minimums.has(key):
			return true
		if not panel.get_combined_minimum_size().is_equal_approx(_panel_minimums[key]):
			return true
	return false


func _capture_panel_minimums() -> void:
	_panel_minimums.clear()
	for entry in _entries:
		var panel: VenuePanel = entry["panel"]
		_panel_minimums[panel.get_instance_id()] = panel.get_combined_minimum_size()


func _layout() -> void:
	if _stage == null or _laying_out:
		return
	_laying_out = true
	_layout_pass()
	_laying_out = false


func _layout_pass() -> void:
	var view: Vector2 = get_viewport_rect().size
	if view.x <= 1.0 or view.y <= 1.0:
		return
	_scale = ConsoleMetrics.compute_scale(view.y, view.x)
	# A handset gets the room rather than the reflow: the place is the thing being
	# navigated, and it is only unreadable because it is far away, which is a
	# problem the player can be given the means to solve rather than one the layout
	# has to solve for them. The column is left for a place with no picture to hang
	# the panels on, and for a window too far from the shape of the art to land
	# them — neither of which leaning in would rescue.
	var handset: bool = ConsoleMetrics.needs_focus()
	var shape_fits: bool = _shape_fits(view)
	_room_mode = _use_room_mode(handset, shape_fits)
	_console_mode = (
		not _painted_ready()
		or (
			not _room_mode
			and (
				handset
				or (not shape_fits and not _painted_desktop_at_any_aspect())
			)
		)
	)
	if not _room_mode:
		_leaning_on = ""
		_zoom = 1.0
	_console_columns = _console_column_count(view) if _console_mode else 1
	_aim_camera(view)
	_layout_backdrop(view)
	_scrim.color = _scrim_color()
	_mount_panels()
	# Panel chrome contributes to its minimum size, so apply the current scale
	# before the painted placement measures that minimum.
	for entry in _entries:
		(entry["panel"] as VenuePanel).set_metrics(console_scale())
	_layout_hint_rows()
	if _console_mode:
		_layout_console(view)
	else:
		_layout_painted(view)
	_layout_step_back()
	_sync_lean_chrome()
	_on_venue_layout()
	# Venue content such as tile boards needs the placed width before it can pick
	# columns and font metrics. Refit painted panels once after that bounded pass
	# so their final geometry includes the resulting minimum size.
	if not _console_mode:
		_place_panels(view)
	_capture_panel_minimums()


func _use_room_mode(handset: bool, shape_fits: bool) -> bool:
	return handset and _room_layout_supported() and _painted_ready() and shape_fits


## Sized for the screen it is on rather than for the canvas: this is the one
## control a player who has leant in on the wrong panel has to be able to find, so
## it is never the smallest type in the window.
func _layout_step_back() -> void:
	if _step_back == null:
		return
	_step_back.add_theme_font_size_override(
		"font_size", ConsoleMetrics.font_body(_scale)
	)
	var pad: float = float(ConsoleMetrics.pad_h(_scale))
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.02, 0.05, 0.04, 0.96 if state == "hover" else 0.86)
		box.border_color = Color(
			ConsoleStyle.PHOSPHOR.r, ConsoleStyle.PHOSPHOR.g, ConsoleStyle.PHOSPHOR.b, 0.45
		)
		box.set_border_width_all(1)
		box.content_margin_left = pad
		box.content_margin_right = pad
		box.content_margin_top = pad * 0.6
		box.content_margin_bottom = pad * 0.6
		_step_back.add_theme_stylebox_override(state, box)
	_anchor_step_back()


func _anchor_step_back() -> void:
	if _step_back == null:
		return
	_step_back.reset_size()
	_step_back.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	_step_back.offset_right = -EDGE_PAD
	_step_back.offset_bottom = -EDGE_PAD
	_step_back.offset_left = -_step_back.size.x - EDGE_PAD
	_step_back.offset_top = -_step_back.size.y - EDGE_PAD


## Whether the artwork can actually carry this venue. A place with no picture, or
## with a panel the catalog never measured, has nowhere honest to put its
## screens — so it goes to the console column rather than guessing at rects.
func _painted_ready() -> bool:
	if _backdrop == null or _backdrop.texture == null:
		return false
	for entry in _entries:
		if bool(entry["console_hide"]):
			continue
		if bool(entry["painted_hide"]):
			continue
		var rect: Rect2 = AssetCatalog.venue_region(venue_key(), str(entry["region"]))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return false
	return true


## Whether the painted composition survives being stretched into this window.
##
## The picture is pulled to the window rather than cropped, so a window that is not
## the shape of the artwork distorts it, and the panels with it. A handset on its
## side and a 16:10 or 4:3 monitor all pull a 16:9 room about by a fifth to a
## third, which reads as a slightly wider or squarer room. An upright phone would
## pull it by three times, which reads as nothing at all: a place that far from its
## own shape prints the console column instead, where a container decides the
## layout rather than the paint.
func _shape_fits(view: Vector2) -> bool:
	if _backdrop == null or _backdrop.texture == null:
		return false
	var source: Vector2 = _backdrop.texture.get_size()
	if source.x <= 0.0 or source.y <= 0.0 or view.y <= 0.0:
		return false
	var painted: float = source.x / source.y
	var window: float = view.x / view.y
	return maxf(painted / window, window / painted) <= STRETCH_LIMIT


# --- The camera --------------------------------------------------------------

## Works out where the room is drawn from, for the lean-in the player has asked
## for. Everything drawn afterwards — the picture and every panel on it — goes
## through `_camera`, so the panels stay registered on the photograph however far
## forward it has come.
func _aim_camera(view: Vector2) -> void:
	_cam_zoom = maxf(_zoom, 1.0)
	# The panel being read travels from where it hangs in the room to the middle of
	# the window as the camera comes forward, so the move reads as walking up to
	# something rather than as the picture being blown up where it stands.
	var travel: float = 0.0
	if _lean_zoom > 1.001:
		travel = clampf((_cam_zoom - 1.0) / (_lean_zoom - 1.0), 0.0, 1.0)
	var shown: Vector2 = _lean_point.lerp(view * 0.5, travel)
	_cam_origin = shown - _lean_point * _cam_zoom
	# The picture is the whole place, so no amount of walking up to something at
	# the edge of it may bring the edge into the window: a panel by a wall is read
	# from an angle rather than by stepping outside the room.
	_cam_origin = _cam_origin.clamp(view * (1.0 - _cam_zoom), Vector2.ZERO)


## Where something in the room is drawn, given where it sits when the place is
## seen whole.
func _camera(rect: Rect2) -> Rect2:
	return Rect2(_cam_origin + rect.position * _cam_zoom, rect.size * _cam_zoom)


## Brings the room forward until the panel mounted at `region` is at reading size.
##
## Called by the room when a sign is pressed, and by a venue whose panels answer
## one another: pressing a category on the index changes what the board says, and
## in room mode the board is a sign somewhere behind the player. Does nothing
## outside room mode, so a venue may call it without asking which layout it is in.
func lean_on(region: String) -> void:
	if not _room_mode or _leaning_on == region:
		return
	var view: Vector2 = _view()
	var rect: Rect2 = _region_rect(region, view)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	_leaning_on = region
	_lean_point = rect.get_center()
	# `focus_zoom` brings the whole panel up to fill the window, which is the right
	# answer for a piece of furniture. A panel is not furniture though — it is type —
	# so a tall narrow one has to come further forward than fitting it would ask
	# for, or the player is left reading a readable height at an unreadable width.
	# It scrolls instead: see `VenuePanel.set_scrollable`.
	var readable: float = float(ConsoleMetrics.px(CONSOLE_COLUMN_MIN, _scale)) / rect.size.x
	_lean_zoom = clampf(
		maxf(ConsoleMetrics.focus_zoom(Rect2(rect.position / view, rect.size / view)), readable),
		1.0,
		ConsoleMetrics.MAX_FOCUS_ZOOM
	)
	_tween_zoom(_lean_zoom)


## Back to the whole place.
func step_back_to_room() -> void:
	if _leaning_on == "":
		return
	_leaning_on = ""
	_tween_zoom(1.0)


func _tween_zoom(target: float) -> void:
	_sync_lean_chrome()
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_zoom_tween.tween_method(_set_zoom, _zoom, target, LEAN_SECONDS)
	# The panels are re-fitted once, at rest. Sizing type against a rect that is
	# still moving costs a full layout a frame for something nobody reads.
	_zoom_tween.finished.connect(_layout, CONNECT_ONE_SHOT)


func _set_zoom(value: float) -> void:
	_zoom = value
	var view: Vector2 = _view()
	_aim_camera(view)
	_layout_backdrop(view)
	_place_panels(view)


## The chrome the room needs: something to press to get back out of a panel, and —
## since a handset has neither an escape key nor the room to print a legend saying
## so — something to press to leave the place altogether.
func _sync_lean_chrome() -> void:
	var leaning: bool = _leaning_on != ""
	if _wall != null:
		_wall.visible = leaning
	if _step_back == null:
		return
	_step_back.visible = leaning or _room_mode
	_step_back.text = "◄ ROOM" if leaning else "◄ BACK"
	_anchor_step_back()


func _view() -> Vector2:
	if size.x > 1.0 and size.y > 1.0:
		return size
	return get_viewport_rect().size


func _scrim_color() -> Color:
	var base: Color = UiThemeBuilder.color("bg")
	var alpha: float = SCRIM_CONSOLE if _console_mode else SCRIM_PAINTED
	return Color(base.r, base.g, base.b, alpha)


## The picture fills the window, stretched to it rather than cropped or bordered.
## The same as the desk's own room: a place is never a photograph with bars around
## it, and nothing painted into it may be cropped away either, because the panels
## are fractions of the picture and would go with it.
func _layout_backdrop(view: Vector2) -> void:
	if _backdrop == null:
		return
	_backdrop.visible = _backdrop.texture != null
	if _backdrop.texture == null:
		return
	var drawn: Rect2 = _camera(Rect2(Vector2.ZERO, view))
	_backdrop.position = drawn.position
	_backdrop.size = drawn.size


## Where the artwork put the panel mounted at `region`, in the place seen whole.
##
## A fraction of the window, because the picture is the window: the desk's room
## works this way and it is what keeps a place filling the screen instead of
## sitting in it. The catalog authored these rects against the artwork and the
## artwork is drawn over the whole window, so the two are the same fractions.
func _region_rect(region: String, view: Vector2) -> Rect2:
	var authored: Rect2 = AssetCatalog.venue_region(venue_key(), region)
	if authored.size.x <= 0.0 or authored.size.y <= 0.0:
		return Rect2()
	return Rect2(authored.position * view, authored.size * view)


## Axis-aligned mount of a photographed plane: the largest rectangle that still
## sits on the writing surface. Kept as a conservative last-resort fallback for a
## degenerate measured plane; normal Web panels use `_place_panel_affine` instead.
func _axis_aligned_region_rect(region: String, view: Vector2) -> Rect2:
	var authored: Rect2 = AssetCatalog.venue_axis_aligned_region(venue_key(), region)
	if authored.size.x <= 0.0 or authored.size.y <= 0.0:
		return Rect2()
	return Rect2(authored.position * view, authored.size * view)


func _layout_painted(view: Vector2) -> void:
	_stage.visible = true
	_console.visible = false
	_place_panels(view)


## Puts every panel where the camera says it is drawn. Split from the layout pass
## because the lean-in is animated, and re-fitting the type on the way is neither
## cheap nor visible.
func _place_panels(view: Vector2) -> void:
	for entry in _entries:
		var panel: VenuePanel = entry["panel"]
		var region: String = str(entry["region"])
		if bool(entry["painted_hide"]):
			panel.visible = false
			(entry["surface"] as CanvasItem).visible = false
			continue
		var rect: Rect2 = _region_rect(region, view)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			panel.visible = false
			(entry["surface"] as CanvasItem).visible = false
			continue
		# The key legend is desk furniture. A room on a handset is worked with a
		# thumb, and its way out is the chrome button rather than a painted panel
		# printing the names of keys the device does not have.
		if panel == _hints and _room_mode:
			panel.visible = false
			(entry["surface"] as CanvasItem).visible = false
			continue
		panel.visible = true
		(entry["surface"] as CanvasItem).visible = true
		# Everything the player has not come up to is too small to aim at, so it
		# takes a press as a request to come and read it instead.
		var leaning: bool = region == _leaning_on
		panel.set_far_off(_room_mode and not leaning)
		# The one being read scrolls within whatever the room gives it; everything
		# else reports its full height, so the layout can see what it needs.
		panel.set_scrollable(leaning)
		var plane: PackedVector2Array = AssetCatalog.venue_plane(venue_key(), region)
		if plane.size() == 4:
			if entry["surface"] is VenueSurface:
				if _place_panel_on_plane(entry, panel, plane, view):
					continue
				(entry["surface"] as VenueSurface).mount_flat(panel)
			if _place_panel_affine(entry, panel, plane, view):
				continue
			# A malformed measured plane still gets the conservative inner rectangle
			# rather than falling back to the full bounding box and painting controls
			# over a rail.
			var inner: Rect2 = _axis_aligned_region_rect(region, view)
			if inner.size.x > 0.0 and inner.size.y > 0.0:
				rect = _camera(inner)
				_reset_flat_surface(entry)
				panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
				panel.custom_minimum_size = Vector2.ZERO
				panel.position = rect.position
				panel.size = rect.size
				continue
		_reset_flat_surface(entry)
		rect = _camera(rect)
		# A panel the player is working is kept whole and kept on screen. It cannot
		# be smaller than what is mounted in it, so the rect the artwork authored is
		# a request rather than a guarantee: a contract sheet with a fee, a deadline
		# and an ACCEPT row on it needs more width than a painted panel a tenth of
		# the picture wide, and sizing to the region and trusting it left the accept
		# row hanging off the right edge of the window.
		#
		# A panel across the room is not being worked, so it is left exactly where
		# the artwork hung it: growing the far side of a shop to fit type nobody can
		# read would walk the place apart, and the panels around the one being read
		# are supposed to be off the window anyway.
		if leaning:
			rect.size = rect.size.max(panel.get_combined_minimum_size())
			rect = _clamp_to_window(rect, view)
		_place_panel_rect(entry, panel, rect)


func _place_panel_rect(entry: Dictionary, panel: VenuePanel, rect: Rect2) -> void:
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	panel.custom_minimum_size = Vector2.ZERO
	if entry["surface"] is Node2D:
		var local_size: Vector2 = rect.size.max(panel.get_combined_minimum_size())
		if local_size.x <= 0.0 or local_size.y <= 0.0:
			return
		panel.position = Vector2.ZERO
		panel.size = local_size
		(entry["surface"] as Node2D).transform = Transform2D(
			Vector2(rect.size.x / local_size.x, 0.0),
			Vector2(0.0, rect.size.y / local_size.y),
			rect.position
		)
		return
	panel.position = rect.position
	panel.size = rect.size


## Web cannot use the projective SubViewport/Polygon2D mount without risking the
## Compatibility renderer during route changes. CanvasItem transforms are safe,
## and although they are affine rather than projective they preserve the panel's
## photographed angle and skew. The best-fit parallelogram is centred over the
## four measured corners, so perspective error is shared between opposite rails
## instead of every control being forced horizontal inside a bounding rectangle.
func _place_panel_affine(
	entry: Dictionary,
	panel: VenuePanel,
	plane: PackedVector2Array,
	view: Vector2
) -> bool:
	if not entry["surface"] is Node2D or plane.size() != 4:
		return false
	var points := PackedVector2Array()
	for corner in plane:
		points.append(_camera(Rect2(corner * view, Vector2.ZERO)).position)
	var across: Vector2 = ((points[1] - points[0]) + (points[2] - points[3])) * 0.5
	var down: Vector2 = ((points[3] - points[0]) + (points[2] - points[1])) * 0.5
	if across.length() < 1.0 or down.length() < 1.0:
		return false
	var center: Vector2 = (points[0] + points[1] + points[2] + points[3]) * 0.25
	var origin: Vector2 = center - (across + down) * 0.5
	var face := Vector2(across.length(), down.length())
	panel.custom_minimum_size = Vector2.ZERO
	var local_size: Vector2 = face.max(panel.get_combined_minimum_size())
	if local_size.x <= 0.0 or local_size.y <= 0.0:
		return false
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	panel.position = Vector2.ZERO
	panel.size = local_size
	var surface: Node2D = entry["surface"]
	surface.transform = Transform2D(
		across / local_size.x,
		down / local_size.y,
		origin
	)
	return true


func _reset_flat_surface(entry: Dictionary) -> void:
	if entry["surface"] is Node2D:
		(entry["surface"] as Node2D).transform = Transform2D.IDENTITY


## Fits a panel into the photographed quadrilateral without allowing its
## contents to push the housing wider or longer. The four-corner mount can
## follow a trapezoid rather than approximating it as a parallelogram; if the
## content needs more room, its texture scales into the physical surface instead
## of overflowing it.
func _place_panel_on_plane(
	entry: Dictionary,
	panel: VenuePanel,
	plane: PackedVector2Array,
	view: Vector2
) -> bool:
	var points := PackedVector2Array()
	for corner in plane:
		points.append(_camera(Rect2(corner * view, Vector2.ZERO)).position)
	var across: Vector2 = ((points[1] - points[0]) + (points[2] - points[3])) * 0.5
	var down: Vector2 = ((points[3] - points[0]) + (points[2] - points[1])) * 0.5
	if across.length() < 1.0 or down.length() < 1.0:
		return false
	var face := Vector2(across.length(), down.length())
	panel.custom_minimum_size = Vector2.ZERO
	var local_size: Vector2 = face.max(panel.get_combined_minimum_size())
	var surface: VenueSurface = entry["surface"]
	return surface.set_surface(panel, points, local_size)


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
			var surface: Node = entry["surface"]
			if surface is VenueSurface:
				surface.mount_panel(entry["panel"])
			else:
				_mount_panel(entry["panel"], surface)
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
	var view: Vector2 = _view()
	var rect: Rect2 = _region_rect(region, view)
	if rect.size.x <= 0.0:
		return Rect2()
	return _clamp_to_window(_camera(rect), view)


## Where an unwarped live panel sits after the camera: the inscribed writing
## surface of a measured plane, or the authored region when there is no plane.
func writing_surface_rect(region: String) -> Rect2:
	return _camera(_axis_aligned_region_rect(region, _view()))
