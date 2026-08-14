extends Control

## The shell: a desk, in landscape, with the game played on the things standing
## on it.
##
## Nothing here is a page the player navigates to. The room the run is being
## played in fills the window and everything else is mounted onto it at a
## position authored beside the art (`board_scenes.<dwelling>` in the asset
## catalog): the machine stands on the desk in the work column and the readouts
## are painted into the props that carry them. Moving the operation to the garage
## repaints the room and moves every one of those mounts with it. The desk is
## never off screen, so the player is always looking at their own operation.
##
## Everything that is not work — the job board, the market, the build sheet, the
## workflows, the records — used to slide in on a slab bolted to the right-hand
## edge of this scene. They are venues of their own now, each a room with its own
## photograph, and the router takes the player to them. What is left here is the
## desk and the reports that interrupt it.

## Screens that live on the desk, in the work column, where the machine is.
const DESK_SCENES := {
	"office": preload("res://ui/operations/operations_screen.tscn"),
	"board": preload("res://ui/board/burn_board_screen.tscn"),
}

## How far the desk is dimmed. The machine is lit by its own screen, so the desk
## behind it barely tints.
const SCRIM_DESK := 0.10

const ANGEL_INVESTORS := preload("res://ui/screens/angel_investors.tscn")
const RUN_END := preload("res://ui/screens/run_end.tscn")
const ROUND_DEBRIEF := preload("res://ui/screens/session_summary.tscn")
const BILLS_SCREEN := preload("res://ui/screens/month_statement.tscn")
const BURN_LAB := preload("res://ui/debug/burn_lab.tscn")
const TITLE_SCREEN := preload("res://ui/title/title_screen.tscn")
const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

@onready var background: ColorRect = $Background
@onready var board_art: TextureRect = $BoardArt
@onready var board_art_next: TextureRect = $BoardArtNext
@onready var scrim: ColorRect = $Scrim
@onready var prop_layer: Control = $PropLayer
@onready var work_column: Control = $WorkColumn
@onready var content_container: Control = $WorkColumn/ContentContainer
@onready var overlay_root: Control = $OverlayRoot

var _desk_tab: String = "office"
var _screen_cache: Dictionary = {}
var _props: Dictionary = {}
var _angel_investors: Control = null
var _run_end: Control = null
var _round_debrief: Control = null
var _bills_screen: Control = null
var _burn_lab: Control = null
var _last_angel_phase: bool = false
var _pending_statement: Dictionary = {}
var _board_dwelling: String = ""
var _room_reveal_running: bool = false
## The menu, written on notes stuck to the whiteboard.
var _notes: BoardNotes = null
## Which piece of furniture the room is currently leant in on, or "" for the
## room as a whole. Only ever set where `ConsoleMetrics.needs_focus()`.
var _focus_key: String = ""
## Where the room holds still while it comes forward and goes back.
var _focus_point: Vector2 = Vector2(0.5, 0.5)
## The zoom at which that point has finished travelling to the middle of the
## window. Kept while the room withdraws, so the pan retraces its own path.
var _focus_full_zoom: float = 1.0
var _room_zoom: float = 1.0
## Where the window's origin lands once the room is zoomed and panned.
var _room_offset := Vector2.ZERO
var _zoom_tween: Tween = null
## Steps the room back out again. Shown only while leant in, because a way out
## of a view is only worth window space while the player is in it.
var _step_back: Button = null
## Presses on the room itself, which are a request to stand back from whatever
## the player leant in on. Live only while there is something to stand back from.
var _wall: Control = null
var _title_screen: Control = null
## While the title is up the shell behind it is already live (so Continue is
## instant), but its flow overlays must stay quiet until the player commits.
var _title_active: bool = true


func _ready() -> void:
	# The shell is torn down and rebuilt every time the player goes somewhere
	# else and comes back, so the half of this that starts a run only belongs to
	# the first mount. Coming back off a venue is a return to a game already in
	# progress: reloading the save would undo whatever was just bought, and the
	# title would be the front door reappearing over a live run.
	var resuming: bool = SceneRouter.booted
	SceneRouter.booted = true
	UiThemeBuilder.apply(self)
	UiSound.attach(self)
	add_to_group("main_ui")
	background.color = UiThemeBuilder.color("bg")
	scrim.color = UiThemeBuilder.color("bg")
	get_viewport().size_changed.connect(_layout_board)
	_build_props()
	_build_wall()
	_build_step_back()
	_layout_board()
	_build_overlays()
	_show_desk_tab("office")
	_connect_events()
	if resuming:
		_title_active = false
	else:
		if ContentDatabase.jobs.is_empty():
			ContentDatabase.reload()
		if SaveManager.has_save():
			Simulation.load_saved_run()
		else:
			Simulation.start_run()
		_ensure_title_screen()
	refresh_all()
	_sync_overlay_input()
	# Reports that came due while the player was out of the room. Drained after
	# the overlays exist, because replaying one opens it.
	for entry in SceneRouter.take_pending_flow():
		_replay_pending(entry)


## Whatever the router held onto while the desk was unloaded.
func _replay_pending(entry: Dictionary) -> void:
	match str(entry.get("kind", "")):
		"tab":
			switch_tab(str(entry.get("tab", "work")))
		"title":
			open_title()
		"burn_lab":
			open_burn_lab()
		"session":
			replay_work_session(Dictionary(entry.get("result", {})))
		"statement":
			replay_statement(Dictionary(entry.get("statement", {})))


## The round's debrief, held over because the round ended while the player was
## reading the market rather than watching the machine.
func replay_work_session(result: Dictionary) -> void:
	if not result.is_empty():
		_on_work_session_finished(result)


func replay_statement(statement: Dictionary) -> void:
	if not statement.is_empty():
		_on_bills_ready(statement)


## Modal sheets are authored against the window, but the screens that open them
## live inside the zoomed room on a handset. They mount here instead, above the
## zoom, so a confirmation never inherits the room's transform.
func mount_overlay(control: Control) -> void:
	overlay_root.add_child(control)


## The round-end reports, which are interruptions in the loop rather than places
## the player goes: they read as paper put down on top of the room, so they stay
## modal on the desk while the catalogue screens have become venues of their own.
##
## The investor's phone and the award splash are not here. Both have to be able
## to arrive while the player is in a venue, and this scene is not on screen
## then, so the router owns them.
func _build_overlays() -> void:
	_angel_investors = ANGEL_INVESTORS.instantiate()
	_run_end = RUN_END.instantiate()
	_round_debrief = ROUND_DEBRIEF.instantiate()
	_bills_screen = BILLS_SCREEN.instantiate()
	_burn_lab = BURN_LAB.instantiate()
	for overlay in [
		_angel_investors, _round_debrief, _bills_screen, _run_end, _burn_lab,
	]:
		if overlay == null:
			push_error("Failed to instantiate a desk overlay")
			continue
		overlay_root.add_child(overlay)
	_round_debrief.continue_pressed.connect(_on_debrief_continue)
	_bills_screen.continue_pressed.connect(_on_bills_continue)


# --- Desk layout -------------------------------------------------------------

## Everything on the desk is placed from the artwork's own coordinates, so a
## repainted room moves the furniture rather than leaving the UI pinned to
## numbers that used to be right.
func _layout_board() -> void:
	_apply_room_transform()
	get_tree().call_group("console_screens", "fit_console")
	# Screens that hang off the room's own furniture rather than off the work
	# column as a whole have to be told the room has moved.
	get_tree().call_group("board_mounted", "relayout_on_board")


## Places the picture and everything measured off it at the current zoom.
##
## The art, the work column and every prop take the same transform, so the
## furniture stays registered on the photograph however far in the room is
## brought; what changes is how much of the room is left in the window. Kept
## separate from the full relayout because the zoom is animated, and re-fitting
## every console on the way is neither cheap nor visible.
func _apply_room_transform() -> void:
	var size: Vector2 = get_viewport_rect().size
	# Where the thing being leant in on is shown. It starts where the artwork
	# painted it and travels to the middle of the window as the room comes
	# forward, so the move reads as the camera walking up to a piece of
	# furniture rather than as the picture being blown up where it stands.
	var travel: float = 0.0
	if _focus_full_zoom > 1.001:
		travel = clampf((_room_zoom - 1.0) / (_focus_full_zoom - 1.0), 0.0, 1.0)
	var shown: Vector2 = _focus_point.lerp(Vector2(0.5, 0.5), travel)
	_room_offset = shown - _focus_point * _room_zoom
	# The picture is the whole room, so no amount of walking up to something at
	# the edge of it may bring the edge into the window: furniture near a wall
	# is leant in on from an angle rather than by stepping outside the room.
	_room_offset = _room_offset.clamp(Vector2.ONE * (1.0 - _room_zoom), Vector2.ZERO)
	var full_rect: Rect2 = _zoom_rect(Rect2(0.0, 0.0, 1.0, 1.0))
	_place(board_art, full_rect, size, full_rect)
	_place(board_art_next, full_rect, size, full_rect)
	_place(work_column, _zoom_rect(
		AssetCatalog.board_region(board_dwelling(), "work_column")
	), size, full_rect)
	_layout_props(size)


## Puts a window-fraction rect through the room's current zoom and pan.
## Applying the same transform to the art and to everything measured off it
## keeps the furniture registered on the picture however far in the room is.
func _zoom_rect(rect: Rect2) -> Rect2:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return rect
	return Rect2(_room_offset + rect.position * _room_zoom, rect.size * _room_zoom)


# --- Leaning in --------------------------------------------------------------

## How long the room takes to come forward. Short enough not to be a transition
## the player waits through, long enough that it reads as the camera moving
## rather than as a cut to another screen.
const FOCUS_SECONDS := 0.26

## The furniture that can be worked at, and where the artwork put it.
func _focus_rect(key: String) -> Rect2:
	var dwelling: String = board_dwelling()
	match key:
		"workstation", "laptop":
			# The bay reserves headroom for smoke and the tallest desktop rig. The
			# generated workstation itself is bottom-aligned inside it, so mobile
			# focus measures the occupied lower band rather than the empty headroom.
			var bay: Rect2 = AssetCatalog.board_workstation_bay(dwelling)
			return Rect2(
				bay.position + Vector2(0.0, bay.size.y * 0.42),
				Vector2(bay.size.x, bay.size.y * 0.58)
			)
		"board":
			return AssetCatalog.board_prop(dwelling, "plan_board")
	return Rect2()


## Brings the room forward until `key` is at reading size.
##
## Whether leaning in is offered at all is the furniture's decision, not this
## one: on a monitor the room is already at reading size, so nothing asks for
## it and every piece of furniture stays live where it is painted.
func focus_room(key: String) -> void:
	if _focus_key == key:
		return
	var rect: Rect2 = _focus_rect(key)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	_focus_key = key
	_focus_point = rect.get_center()
	_focus_full_zoom = ConsoleMetrics.focus_zoom(rect)
	_tween_room_zoom(_focus_full_zoom)


## Back to the whole room. Called by anything that takes over the window, so the
## player is never left leant in on furniture they have finished with.
func clear_room_focus() -> void:
	if _focus_key == "":
		return
	_focus_key = ""
	_tween_room_zoom(1.0)


func _tween_room_zoom(target: float) -> void:
	var leaning: bool = _focus_key != ""
	if _step_back != null:
		_step_back.visible = leaning
	if _wall != null:
		_wall.visible = leaning
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_zoom_tween.tween_method(_set_room_zoom, _room_zoom, target, FOCUS_SECONDS)
	# The consoles are re-fitted once, at rest. Doing it per frame would size
	# type against a rect that is still moving, for a frame nobody reads.
	_zoom_tween.finished.connect(_layout_board, CONNECT_ONE_SHOT)


func _set_room_zoom(value: float) -> void:
	_room_zoom = value
	_apply_room_transform()


func _unhandled_input(event: InputEvent) -> void:
	if _focus_key == "" or not event.is_action_pressed("ui_cancel"):
		return
	clear_room_focus()
	get_viewport().set_input_as_handled()


## The wall, as something that can be pressed.
##
## Anything the room is not is a way out of it, and the natural way to write
## that is to catch what the furniture did not. But the room is a picture with
## panels, scrims and screens layered over it, any one of which may swallow a
## press on its way past, so the wall is given a surface of its own instead:
## the whole window, under every piece of furniture and over the photograph,
## live only while the player is leant in on something.
func _build_wall() -> void:
	_wall = Control.new()
	_wall.name = "Wall"
	_wall.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wall.mouse_filter = Control.MOUSE_FILTER_STOP
	_wall.visible = false
	_wall.gui_input.connect(_on_wall_input)
	add_child(_wall)
	move_child(_wall, prop_layer.get_index())


func _on_wall_input(event: InputEvent) -> void:
	var released: bool = (
		(event is InputEventMouseButton and not event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT)
		or (event is InputEventScreenTouch and not event.pressed)
	)
	if released:
		clear_room_focus()
		_wall.accept_event()


## The way out, for a player who does not know that the wall is one. It is the
## only thing in the game drawn over the room rather than in it, which is the
## price of the room being a place you can get lost in.
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
	# Sized for the screen it is on rather than for the canvas: this is the one
	# control a player who has leant in on the wrong thing has to be able to
	# find, so it is never the smallest type in the window.
	var scale: float = ConsoleMetrics.stretch_compensation()
	_step_back.add_theme_font_size_override("font_size", ConsoleMetrics.font_body(scale))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		_step_back.add_theme_color_override(state, ConsoleStyle.PHOSPHOR)
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.02, 0.05, 0.04, 0.86 if state != "hover" else 0.96)
		box.border_color = Color(
			ConsoleStyle.PHOSPHOR.r, ConsoleStyle.PHOSPHOR.g, ConsoleStyle.PHOSPHOR.b, 0.45
		)
		box.set_border_width_all(1)
		box.set_corner_radius_all(0)
		box.content_margin_left = ConsoleMetrics.pad_h(scale)
		box.content_margin_right = ConsoleMetrics.pad_h(scale)
		box.content_margin_top = ConsoleMetrics.pad_h(scale) * 0.6
		box.content_margin_bottom = ConsoleMetrics.pad_h(scale) * 0.6
		_step_back.add_theme_stylebox_override(state, box)
	_step_back.pressed.connect(clear_room_focus)
	add_child(_step_back)
	move_child(_step_back, overlay_root.get_index())
	_step_back.reset_size()
	# Bottom right, because leaning in walks the room's own furniture into the
	# top left of the window — the plan board is pinned to the corner of every
	# wall the game has painted, and the way out should not be written over it.
	var margin: float = 12.0
	_step_back.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	_step_back.offset_right = -margin
	_step_back.offset_bottom = -margin
	_step_back.offset_left = -_step_back.size.x - margin
	_step_back.offset_top = -_step_back.size.y - margin


## Anchors a control to a fractional rect of the window, falling back to a
## layout of the caller's own when the artwork does not place it.
func _place(control: Control, region: Rect2, viewport_size: Vector2, fallback: Rect2) -> void:
	var rect: Rect2 = region if region.size.x > 0.0 and region.size.y > 0.0 else fallback
	control.anchor_left = rect.position.x
	control.anchor_top = rect.position.y
	control.anchor_right = rect.position.x + rect.size.x
	control.anchor_bottom = rect.position.y + rect.size.y
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


# --- Diegetic props ----------------------------------------------------------

## Readouts painted onto the things in the room: the plan on the wall, the
## thermometer by the desk, the meter on the wall socket, the phone the investor
## rings. Built from the catalog rather than hand-placed, so the artwork decides
## what the room contains.
func _build_props() -> void:
	for key in AssetCatalog.board_prop_keys(board_dwelling()):
		var prop := BoardProp.new()
		prop.prop_key = str(key)
		prop_layer.add_child(prop)
		_props[str(key)] = prop
	var phone: BoardProp = _props.get("phone")
	if phone != null:
		phone.pressed.connect(open_investor_terms)
	var plan: BoardProp = _props.get("plan_board")
	if plan != null:
		plan.pressed.connect(_on_plan_board_pressed)
	_notes = BoardNotes.new()
	_notes.name = "BoardNotes"
	prop_layer.add_child(_notes)
	ConsoleNav.mount(_notes, self)


## How much of the whiteboard the menu is stuck over: a column down one side of
## a board with the width to spare, or a block along the bottom of one without.
const NOTES_COLUMN_SHARE := 0.34
const NOTES_STRIP_SHARE := 0.34
## Kept off the board's own edge, because a note stuck flush to the frame reads
## as part of the furniture rather than as paper on it.
const NOTES_MARGIN := 0.04
## Width, in canvas units, the plan needs to be written at a legible size. Under
## this the menu goes along the bottom instead: every room hangs a board taller
## than it is wide, so width is the measure a narrow one runs out of first.
const PLAN_MIN_WIDTH := 120.0


func _layout_props(viewport_size: Vector2) -> void:
	var dwelling: String = board_dwelling()
	for key in _props:
		var prop: BoardProp = _props[key]
		var rect: Rect2 = AssetCatalog.board_prop(dwelling, str(key))
		_place(prop, _zoom_rect(rect), viewport_size, Rect2())
		# A prop the artwork does not carry has nowhere honest to sit.
		prop.visible = rect.size.x > 0.0
		prop.set_plane(_prop_plane(dwelling, str(key), rect))
	_layout_notes(viewport_size)


## The notes hang in whatever part of the plan board is kept clear for them.
## Which part that is depends on the wall the room hangs: a bedroom's board can
## spare a column down one side, a garage's board is a third the width and
## would have nowhere left to write the plan, so its menu goes underneath.
func _layout_notes(viewport_size: Vector2) -> void:
	if _notes == null:
		return
	var plan: BoardProp = _props.get("plan_board")
	var board: Rect2 = AssetCatalog.board_prop(board_dwelling(), "plan_board")
	_notes.visible = board.size.x > 0.0 and board.size.y > 0.0
	if not _notes.visible:
		return
	var margin: Vector2 = board.size * NOTES_MARGIN
	var down_the_side: bool = (
		board.size.x * viewport_size.x * (1.0 - NOTES_COLUMN_SHARE) >= PLAN_MIN_WIDTH
	)
	var area: Rect2
	if down_the_side:
		_notes.columns = 1
		area = Rect2(
			board.position.x + board.size.x * (1.0 - NOTES_COLUMN_SHARE),
			board.position.y + margin.y,
			board.size.x * NOTES_COLUMN_SHARE - margin.x,
			board.size.y - margin.y * 2.0
		)
	else:
		# Two across rather than five: a note wide enough for the word is wider
		# than a fifth of a narrow board, and three shallow rows cost the plan
		# less than five would.
		_notes.columns = 2
		area = Rect2(
			board.position.x + margin.x,
			board.position.y + board.size.y * (1.0 - NOTES_STRIP_SHARE),
			board.size.x - margin.x * 2.0,
			board.size.y * NOTES_STRIP_SHARE - margin.y
		)
	if plan != null:
		plan.reserve(
			NOTES_COLUMN_SHARE if down_the_side else 0.0,
			0.0 if down_the_side else NOTES_STRIP_SHARE
		)
	_place(_notes, _zoom_rect(area), viewport_size, Rect2())


## The board is a surface, and the notes on it are the buttons. Pressing the
## board itself is therefore only ever a request to read it — which on a
## monitor means the contract, and on a handset means leaning in far enough to
## make out any of it.
func _on_plan_board_pressed() -> void:
	if ConsoleMetrics.needs_focus() and _focus_key != "board":
		focus_room("board")
		return
	SceneRouter.open_terms()


## The room measures a prop's painted surface against the whole picture; the
## prop wants it against itself, so the corners are rebased onto its own rect.
## The zoom cancels out — both are scaled by it — so this is the same quad at
## any magnification.
func _prop_plane(dwelling: String, key: String, rect: Rect2) -> PackedVector2Array:
	var quad: PackedVector2Array = AssetCatalog.board_prop_plane(dwelling, key)
	if quad.size() != 4 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return PackedVector2Array()
	var local := PackedVector2Array()
	for corner in quad:
		local.append((corner - rect.position) / rect.size)
	return local


func _refresh_props() -> void:
	var state := Simulation.run_state
	var heat: float = float(state.compute.get("heat", 0.0))
	var capacity: float = maxf(1.0, float(state.compute.get("heat_capacity", 100.0)))
	var ratio: float = heat / capacity
	_set_prop("heat_readout", "HEAT", "%d%%" % int(round(ratio * 100.0)), _heat_role(ratio))
	var watts: float = float(state.compute.get("power_draw", 0.0))
	_set_prop("power_meter", "POWER", "%.1f kW" % (watts / 1000.0), "energy")
	_set_prop_lines(
		"plan_board",
		"BURN PLAN",
		_plan_lines(),
		_contract_lines(),
		_ledger_figures(),
		_ledger_ink()
	)
	var plan: BoardProp = _props.get("plan_board")
	if plan != null:
		plan.tooltip_text = _board_tooltip()
	if _notes != null:
		ConsoleNav.refresh(_notes)
	# Always the terms line: tapping re-reads the contract. There is nothing to
	# qualify for any more, so the phone does not ring for a "ready" state.
	_set_prop("phone", "ANGEL", "TERMS", "neutral")
	var phone: BoardProp = _props.get("phone")
	if phone != null:
		phone.set_ringing(false)


func _heat_role(ratio: float) -> String:
	if ratio >= 0.9:
		return "danger"
	if ratio >= 0.7:
		return "heat"
	return "success"


## The checklist on the wall: what this run still has to do, ticked off as it
## gets done. It is the tutorial that never has to be dismissed.
func _plan_lines() -> Array:
	var state := Simulation.run_state
	var has_contracts: bool = not Array(state.business.get("job_queue", [])).is_empty() \
		or not Array(state.business.get("active_jobs", [])).is_empty()
	return [
		["CONTRACTS", has_contracts],
		["UPGRADE RIG", Array(state.build.get("hardware", [])).size() > 1],
		["STAY COOL", float(state.compute.get("heat", 0.0))
			< 0.7 * maxf(1.0, float(state.compute.get("heat_capacity", 100.0)))],
	]


func _set_prop(key: String, caption: String, value: String, role: String) -> void:
	var prop: BoardProp = _props.get(key)
	if prop != null:
		prop.set_readout(caption, value, UiThemeBuilder.semantic(role))


func _set_prop_lines(
	key: String,
	caption: String,
	lines: Array,
	notes: Array = [],
	ledger: Array = [],
	ledger_ink: Color = BoardProp.MARKER_INK
) -> void:
	var prop: BoardProp = _props.get(key)
	if prop != null:
		prop.set_checklist(caption, lines, notes, ledger, ledger_ink)


## The investor's terms, written up on the board under the plan rather than on a
## plate in the corner of the window. It is the one thing in the run with a
## deadline attached, so it belongs where the player writes down what they still
## have to do.
func _contract_lines() -> Array:
	var summary: Dictionary = Simulation.ascension_summary()
	var contract: Dictionary = Dictionary(summary.get("contract", {}))
	if contract.is_empty():
		return []
	var progress: Dictionary = Dictionary(summary.get("progress", {}))
	var burned: float = float(progress.get("tokens_burned", 0.0))
	var total: float = maxf(1.0, float(progress.get("total_burn", contract.get("total_burn", 1.0))))
	var filled: int = clampi(int(round(burned / total * 10.0)), 0, 10)
	var lines: Array = [
		str(contract.get("name", "The contract")).to_upper(),
		"%s/%s" % [NumberFormat.format(burned), NumberFormat.format(total)],
		"%s%s" % ["|".repeat(filled), "-".repeat(10 - filled)],
	]
	var quality_min: float = float(progress.get("quality_min", 0.0))
	var tail: String = "%d rnd(s)" % maxi(0, int(progress.get("rounds_remaining", 0)))
	if quality_min > 0.0:
		tail += " q%s/%s" % [
			JobPresentation.quality_mark(float(progress.get("quality_average", 0.0))),
			JobPresentation.quality_mark(quality_min),
		]
	lines.append(tail)
	return lines


# --- Title -------------------------------------------------------------------

## The title sits between the shell and the overlay stack: it hides the run in
## progress, but The Legacy and the Burn Lab still open on top of it.
##
## Built on demand rather than with the rest of the shell, because the shell is
## rebuilt every time the player comes back from a venue and the front door is
## not something a live run should be paying for on each return.
func _ensure_title_screen() -> void:
	if _title_screen != null:
		return
	_title_screen = TITLE_SCREEN.instantiate()
	add_child(_title_screen)
	move_child(_title_screen, overlay_root.get_index())
	_title_screen.start_requested.connect(_on_title_start)


func _on_title_start() -> void:
	_title_active = false
	refresh_all()
	# The investor's opening call is the first thing a fresh run does, before the
	# player has touched anything.
	_maybe_open_intro_call()


## Skips the front door. Used by the screenshot tool, which needs to land on a
## specific tab rather than press its way in.
func dismiss_title() -> void:
	if _title_screen != null:
		_title_screen.visible = false
	_title_active = false
	refresh_all()


## Returning to the front door from the menu. The run stays loaded, so Continue
## picks it straight back up.
func open_title() -> void:
	_ensure_title_screen()
	_title_active = true
	get_tree().call_group("flow_overlay", "hide_overlay")
	_title_screen.open()
	_sync_overlay_input()


func sync_overlay_input() -> void:
	_sync_overlay_input()


func _sync_overlay_input() -> void:
	var blocking := false
	for child in overlay_root.get_children():
		if child is CanvasItem and child.visible:
			blocking = true
			break
	overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP if blocking else Control.MOUSE_FILTER_IGNORE


# --- Navigation --------------------------------------------------------------

## WORK is the home button: it shows the burn board from the moment there is
## something to work on, and the empty desk otherwise. It used to hold the
## office back until the session was running, which put a screen between
## accepting a contract and doing it that only restated the contract and asked
## for a START WORK press. The deck starts the session on its first BURN now.
func _desk_tab_now() -> String:
	if Simulation.is_work_running():
		return "board"
	return "board" if Simulation.run_state.has_pending_work() else "office"


## Kept for the screens and the screenshot tool, which ask for a destination by
## name without knowing where it lives. The desk's own tabs are handled here;
## everywhere else is a scene of its own now, so the router takes it.
func switch_tab(tab_name: String) -> void:
	match tab_name:
		"work":
			_show_desk_tab(_desk_tab_now())
		"office", "board":
			_show_desk_tab(tab_name)
		"more":
			SceneRouter.open_menu()
		_:
			SceneRouter.goto(tab_name)


func _show_desk_tab(tab_name: String) -> void:
	if not DESK_SCENES.has(tab_name):
		return
	_desk_tab = tab_name
	_mount(content_container, DESK_SCENES, tab_name)
	_update_board_art()
	_update_scrim()


## Screens are built once and then kept: switching is a visibility flip and a
## refresh, so returning to the job board does not rebuild every card.
func _mount(host: Control, scenes: Dictionary, tab_name: String) -> void:
	for child in host.get_children():
		child.visible = false
	if not _screen_cache.has(tab_name):
		var screen: Control = scenes[tab_name].instantiate()
		host.add_child(screen)
		_screen_cache[tab_name] = screen
	var mounted: Control = _screen_cache[tab_name]
	if mounted.get_parent() != host:
		mounted.reparent(host)
	mounted.visible = true
	if mounted.has_method("refresh"):
		mounted.refresh()
	if mounted.has_method("fit_console"):
		mounted.call_deferred("fit_console")


## The burn lab takes the window off the room, so it stands the room back up on
## its way in. The player closes it onto the room they left, not onto the inside
## of a whiteboard.
func open_burn_lab() -> void:
	if _burn_lab != null and FeatureFlags.is_enabled("burn_lab_enabled"):
		clear_room_focus()
		_burn_lab.open()


# --- The desk artwork --------------------------------------------------------

func _update_board_art() -> void:
	var dwelling: String = AssetCatalog.dwelling_for_build(Simulation.run_state.build)
	if dwelling != _board_dwelling and not _room_reveal_running:
		var first_room: bool = _board_dwelling.is_empty()
		_board_dwelling = dwelling
		# Every mount in the shell is measured off the picture, so a new room has
		# to move the furniture before it is shown, not after.
		_layout_board()
		if first_room:
			board_art.texture = AssetCatalog.board_scene_art(dwelling)
		else:
			_reveal_room(dwelling)
	board_art.visible = board_art.texture != null
	scrim.visible = board_art.visible


## The room the shell is currently laid out against. Screens mounted inside a
## region ask for this so they can place themselves off the same picture.
func board_dwelling() -> String:
	if _board_dwelling.is_empty():
		return AssetCatalog.dwelling_for_build(Simulation.run_state.build)
	return _board_dwelling


func _update_scrim() -> void:
	var base: Color = UiThemeBuilder.color("bg")
	scrim.color = Color(base.r, base.g, base.b, SCRIM_DESK)


## Moving premises is the reward for finishing a chapter, so the chrome steps
## out of the way, the new room fades in, and then it all comes back.
func _reveal_room(dwelling: String) -> void:
	_room_reveal_running = true
	board_art_next.texture = AssetCatalog.board_scene_art(dwelling)
	board_art_next.visible = board_art_next.texture != null
	var chrome: Array[Control] = [work_column, prop_layer]
	var tween: Tween = create_tween()
	for control in chrome:
		tween.parallel().tween_property(control, "modulate:a", 0.0, 0.22)
	tween.tween_property(board_art_next, "modulate:a", 1.0, 0.5)
	tween.tween_interval(0.4)
	for control in chrome:
		tween.parallel().tween_property(control, "modulate:a", 1.0, 0.28)
	tween.tween_callback(_finish_room_reveal)


func _finish_room_reveal() -> void:
	board_art.texture = board_art_next.texture
	board_art.visible = board_art.texture != null
	board_art_next.modulate.a = 0.0
	board_art_next.visible = false
	_room_reveal_running = false
	_update_board_art()


# --- Events ------------------------------------------------------------------

func _connect_events() -> void:
	EventBus.run_started.connect(refresh_all)
	EventBus.run_started.connect(_reset_ascension_prompts)
	Simulation.work_session_finished.connect(_on_work_session_finished)
	Simulation.round_statement_ready.connect(_on_bills_ready)
	# Taking a contract and starting one both hand the window back to the desk,
	# which is the router's call now: the press that did it may have come from a
	# venue, and this scene is not on screen to answer for it.
	EventBus.round_started.connect(refresh_all)
	EventBus.reward_calculated.connect(func(_a): refresh_all())
	EventBus.perk_acquired.connect(func(_a): refresh_all())
	EventBus.upgrade_purchased.connect(func(_a): refresh_all())
	EventBus.hardware_sold.connect(func(_a): refresh_all())
	EventBus.run_ended.connect(func(_victory): refresh_all())
	EventBus.run_ended.connect(_on_run_ended_call)
	# Burning and billing move cash mid-prompt. The board on the wall is where
	# the player watches it, so keep the room honest without rebuilding every
	# screen behind it.
	EventBus.tokens_consumed.connect(func(_amount): _refresh_props())
	EventBus.bill_due.connect(func(_type, _amount): _refresh_props())


func _on_work_session_finished(result: Dictionary) -> void:
	if _desk_tab == "board":
		_show_desk_tab("office")
	var summary: Dictionary = result.get("summary", {})
	if not summary.is_empty() and Simulation.phase != Simulation.Phase.RUN_END:
		# The debrief gets the stage to itself; the angel draft reopens when the
		# player hits Continue.
		_angel_investors.hide_overlay()
		_round_debrief.show_summary(summary)
	refresh_all()


## Debrief → Bills → Angels, always in that order: the player reads what the
## work earned before what the round cost, and only hears the investor's offers
## once the rent has actually cleared.
func _on_debrief_continue() -> void:
	if not _pending_statement.is_empty():
		var statement: Dictionary = _pending_statement
		_pending_statement = {}
		_bills_screen.show_statement(statement)
		refresh_all()
		return
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		_angel_investors.show_choices()
		_last_angel_phase = true
	refresh_all()


func _on_bills_ready(statement: Dictionary) -> void:
	if statement.is_empty():
		return
	_angel_investors.hide_overlay()
	if _round_debrief.visible:
		_pending_statement = statement
		refresh_all()
		return
	_bills_screen.show_statement(statement)
	refresh_all()


func _on_bills_continue() -> void:
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		_angel_investors.show_choices()
		_last_angel_phase = true
	refresh_all()


func refresh_all() -> void:
	_refresh_props()
	_update_board_art()
	for screen in _screen_cache.values():
		if screen.has_method("refresh"):
			screen.refresh()
	if _title_active:
		_sync_overlay_input()
		return
	var report_open: bool = _round_debrief.visible or _bills_screen.visible
	var in_angel: bool = Simulation.phase == Simulation.Phase.ANGEL_ROUND
	if in_angel and not _last_angel_phase and not report_open:
		_angel_investors.show_choices()
	if not (in_angel and report_open):
		_last_angel_phase = in_angel
	# A run that ends on the bills waits for the statement to be read, so the
	# verdict never lands before the reason for it. A leftover report covering a
	# live round is the other direction of the same bug: hide it the moment the
	# sim is playable again.
	if Simulation.phase == Simulation.Phase.RUN_END and not _bills_screen.visible and _pending_statement.is_empty():
		_clear_stage_for(_run_end)
		_run_end.show_from_state(
			bool(Simulation.run_state.flags.get("victory", false)),
			str(Simulation.run_state.flags.get("loss_reason", ""))
		)
	elif _run_end != null and _run_end.visible:
		_run_end.hide_overlay()
	if Simulation.phase == Simulation.Phase.ROUND_PREP:
		_maybe_call_ascension_beat()
	_sync_overlay_input()


## The verdict is the last word on a run and no other report may share the screen
## with it. A loss can land while an earlier one is still standing — the angel
## draft survives the loss check that follows a pick, and a settled ascension and
## the collapse that follows it both end the same run — and a reward table left
## open behind "the company collapsed" reads as winning and losing at once.
##
## The router's own overlays are left alone: the investor rings off over the top
## of the verdict, which is his last word rather than a competing one. The bills
## are not cleared either, because the caller only raises the verdict once the
## statement behind it has been read.
func _clear_stage_for(verdict: Control) -> void:
	for overlay in get_tree().get_nodes_in_group("flow_overlay"):
		if overlay == verdict or SceneRouter.is_ancestor_of(overlay):
			continue
		if overlay is CanvasItem and overlay.visible and overlay.has_method("hide_overlay"):
			overlay.hide_overlay()


## The round the deadline stops being background reading and starts being the
## thing the player is running out of time for.
const ASCENSION_WARNING_ROUND := 9
## How near the deadline the investor rings to remind the player it exists.
const INVESTOR_FINAL_CALL_ROUNDS := 3

## The investor introduces himself once per run, not once per load.
var _intro_call_shown: bool = false


## Everything the board is kept in the corner of the eye for. What the company
## has, what it is thought of, and how much of the year is left — the last three
## numbers that used to float in a strip over the room instead of being written
## somewhere a person at this desk could have written them.
##
## Handed over as three separate figures, because the board a room hangs is
## whatever size that room's wall is: a wide one writes them across a line, a
## narrow one stacks them, and neither has to be told which it is.
func _ledger_figures() -> Array:
	var state := Simulation.run_state
	var round_number: int = int(state.calendar.get("round", 1))
	var deadline: int = round_number + Simulation.rounds_remaining() - 1
	return [
		NumberFormat.format_cash(float(state.economy.get("cash", 0.0))),
		"REP %d" % int(state.business.get("reputation", 0.0)),
		"R%d/%d" % [round_number, deadline],
	]


## The board goes up in the red pen when the company is in trouble on either
## count, which is what anyone keeping it would do to it.
func _ledger_ink() -> Color:
	var round_number: int = int(Simulation.run_state.calendar.get("round", 1))
	var trouble: bool = (
		float(Simulation.run_state.economy.get("cash", 0.0)) < 0.0
		or Simulation.rounds_remaining() <= 2
		or _ascension_urgency_line(round_number) != ""
	)
	return BoardProp.MARKER_URGENT if trouble else BoardProp.MARKER_INK


## Says the quiet part out loud from round nine on: the year is the deadline, and
## the contract is not going to finish itself.
func _ascension_urgency_line(round_number: int) -> String:
	if Simulation.in_post_victory():
		return ""
	var progress: Dictionary = Simulation.ascension_progress()
	if progress.is_empty():
		return ""
	if round_number < ASCENSION_WARNING_ROUND:
		return ""
	var contract: Dictionary = Dictionary(progress.get("contract", {}))
	return "%s is %.0f%% done with %d round(s) left. Miss it and the run is over." % [
		str(contract.get("name", "The contract")),
		float(progress.get("burn_ratio", 0.0)) * 100.0,
		int(progress.get("rounds_remaining", 0)),
	]


func _reset_ascension_prompts() -> void:
	_intro_call_shown = false


# --- The investor ------------------------------------------------------------

## Fresh runs open with the phone ringing: the investor sets the terms before the
## player has spent a penny. A loaded run has already had that conversation.
func _maybe_open_intro_call() -> void:
	if _intro_call_shown or _title_active:
		return
	if int(Simulation.run_state.calendar.get("round", 1)) > 1:
		_intro_call_shown = true
		return
	if Simulation.prompts_used_this_round() > 0:
		_intro_call_shown = true
		return
	_intro_call_shown = true
	SceneRouter.investor_says("run_intro")


## The investor, on demand. Tapping the phone on the desk is how the player
## re-reads the terms they agreed to.
func open_investor_terms() -> void:
	clear_room_focus()
	SceneRouter.investor_says("terms")


## Any beat the rest of the game wants him to weigh in on.
func investor_says(trigger: String, context: Dictionary = {}) -> void:
	SceneRouter.investor_says(trigger, context)


## The beats of the run he insists on being present for. Each fires once, when
## the state that earns it first appears, so he interrupts the moment rather than
## every refresh that follows it. Remembered on the run, not on this scene: the
## shell is torn down every time the player leaves the desk.
func _maybe_call_ascension_beat() -> void:
	if _title_active or SceneRouter.investor_busy():
		return
	var progress: Dictionary = Simulation.ascension_progress()
	if progress.is_empty():
		return
	# The last rounds take precedence: being behind with the year nearly gone is
	# the more urgent of the two things he could be ringing about.
	var rounds_left: int = int(progress.get("rounds_remaining", 99))
	if rounds_left <= INVESTOR_FINAL_CALL_ROUNDS and not Simulation.run_state.investor_beat_heard("contract_final_call"):
		Simulation.run_state.mark_investor_beat("contract_final_call")
		investor_says("contract_final_call", {"rounds_remaining": rounds_left})
		return
	if float(progress.get("burn_ratio", 0.0)) >= 0.5 and not Simulation.run_state.investor_beat_heard("contract_halfway"):
		Simulation.run_state.mark_investor_beat("contract_halfway")
		investor_says("contract_halfway")


## The end of a run is his call to make either way: on a win he is buying the
## next location, on a loss he is closing the account.
func _on_run_ended_call(victory: bool) -> void:
	if _title_active:
		return
	investor_says("ascension_complete" if victory else "run_lost")


## The board is written in shorthand, so pressing it is what spells the
## shorthand out: what the round is, and what reputation is actually doing.
## Reputation in particular is three things at once, and a bare number leaves
## the player to infer all three.
func _board_tooltip() -> String:
	var state := Simulation.run_state
	var round_number: int = int(state.calendar.get("round", 1))
	var deadline: int = round_number + Simulation.rounds_remaining() - 1
	var lines: PackedStringArray = [
		"Round %d of %d" % [round_number, deadline],
		"%d prompt(s) spent this round" % Simulation.prompts_used_this_round(),
		"A round runs until every contract you took resolves, then the bills land.",
	]
	var urgency: String = _ascension_urgency_line(round_number)
	if urgency != "":
		lines.append(urgency)
	var slots: int = Simulation.job_slots()
	if slots > 1:
		lines.append("%d machines: %d contracts advance per prompt" % [slots, slots])
	else:
		lines.append(
			"One machine: one contract advances per prompt. Buy another to work in parallel."
		)
	lines.append("")
	lines.append_array(_reputation_lines(float(int(state.business.get("reputation", 0.0)))))
	return "\n".join(lines)


func _reputation_lines(reputation: float) -> PackedStringArray:
	var state := Simulation.run_state
	var bonus: int = int(round(
		(JobSystem.reputation_reward_multiplier(state, ContentDatabase) - 1.0) * 100.0
	))
	var lines: PackedStringArray = [
		"Reputation %d" % int(reputation),
		"+%d%% on every contract fee" % bonus,
	]
	var next_tier: Dictionary = JobSystem.next_reputation_tier(state, ContentDatabase)
	if next_tier.is_empty():
		lines.append("Every client tier is already open to you")
	else:
		lines.append("Tier %d clients at %d reputation" % [
			int(next_tier["tier"]), int(ceil(float(next_tier["reputation"]))),
		])
	lines.append("Delivering above a client's quality bar earns it; missing deadlines costs it")
	if reputation <= 0.0:
		lines.append("At -5 the business collapses")
	return lines
