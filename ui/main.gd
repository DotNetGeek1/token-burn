extends Control

## The shell: a desk, in landscape, with the game played on the things standing
## on it.
##
## Nothing here is a page the player navigates to. The room the run is being
## played in fills the window and everything else is mounted onto it at a
## position authored beside the art (`board_scenes.<dwelling>` in the asset
## catalog): the machine stands on the desk in the work column, the readouts are
## painted into the props that carry them, and the job board, market, build and
## menu slide in from the right over the room rather than replacing it. Moving
## the operation to the garage repaints the room and moves every one of those
## mounts with it. The desk is never off screen, so the player is always looking
## at their own operation.

## Screens that live on the desk, in the work column, where the machine is.
const DESK_SCENES := {
	"office": preload("res://ui/operations/operations_screen.tscn"),
	"board": preload("res://ui/board/burn_board_screen.tscn"),
}

## Screens that slide in on the right-hand panel. They are reference material and
## shopping, not work, so they never take the machine off the screen.
const PANEL_SCENES := {
	"jobs": preload("res://ui/jobs/jobs_screen.tscn"),
	"build": preload("res://ui/build/build_screen.tscn"),
	"market": preload("res://ui/market/market_screen.tscn"),
	"menu": preload("res://ui/menu/menu_screen.tscn"),
}

## Navigation destinations to the icon each one borrows from the art kit. The
## menu itself is printed on the laptop now; these are for the panel's own rail.
const NAV_ICON_KEYS := {
	"work": "office",
	"jobs": "jobs",
	"build": "build",
	"market": "market",
	"ascend": "board",
	"more": "menu",
}

## The rail down the inside edge of the side panel, mirroring the laptop's menu
## for the hand that is already over there.
const RAIL_TABS: Array[String] = ["jobs", "market", "build", "menu"]

## How far the desk is dimmed. The machine is lit by its own screen, so the desk
## behind it barely tints; a panel full of type needs the room further back.
const SCRIM_DESK := 0.10
const SCRIM_PANEL := 0.34

const PANEL_SLIDE_SECONDS := 0.22

const ANGEL_INVESTORS := preload("res://ui/screens/angel_investors.tscn")
const RUN_END := preload("res://ui/screens/run_end.tscn")
const ROUND_DEBRIEF := preload("res://ui/screens/session_summary.tscn")
const BILLS_SCREEN := preload("res://ui/screens/month_statement.tscn")
const BURN_LAB := preload("res://ui/debug/burn_lab.tscn")
const PIPELINE_EDITOR := preload("res://ui/board/pipeline_editor.tscn")
const ASCENSION_SELECT := preload("res://ui/screens/ascension_select.tscn")
const META_HUB := preload("res://ui/screens/meta_hub.tscn")
const ACHIEVEMENTS := preload("res://ui/screens/achievements_screen.tscn")
const INVESTOR_CALL := preload("res://ui/screens/investor_call.tscn")
const TITLE_SCREEN := preload("res://ui/title/title_screen.tscn")
const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

@onready var background: ColorRect = $Background
@onready var board_art: TextureRect = $BoardArt
@onready var board_art_next: TextureRect = $BoardArtNext
@onready var scrim: ColorRect = $Scrim
@onready var prop_layer: Control = $PropLayer
@onready var work_column: Control = $WorkColumn
@onready var content_container: Control = $WorkColumn/ContentContainer
@onready var side_panel: Control = $SidePanel
@onready var panel_bg: PanelContainer = $SidePanel/PanelBg
@onready var panel_body: Control = $SidePanel/PanelBg/PanelRow/PanelBody
@onready var icon_rail: VBoxContainer = $SidePanel/PanelBg/PanelRow/IconRail
@onready var overlay_root: Control = $OverlayRoot

var _desk_tab: String = "office"
## Which panel screen is loaded. Empty means the panel is shut and the desk has
## the whole window.
var _panel_tab: String = ""
## The tab the slab is still carrying while it slides back out of the room.
var _closing_tab: String = ""
var _panel_slide: float = 1.0
var _panel_tween: Tween = null
var _screen_cache: Dictionary = {}
var _props: Dictionary = {}
var _angel_investors: Control = null
var _run_end: Control = null
var _round_debrief: Control = null
var _bills_screen: Control = null
var _burn_lab: Control = null
var _pipeline_editor: Control = null
var _ascension_select: Control = null
var _meta_hub: Control = null
var _achievements: Control = null
var _investor_call: Control = null
var _achievement_splash: AchievementSplash = null
var _last_angel_phase: bool = false
var _pending_statement: Dictionary = {}
var _board_dwelling: String = ""
var _room_reveal_running: bool = false
var _title_screen: Control = null
## While the title is up the shell behind it is already live (so Continue is
## instant), but its flow overlays must stay quiet until the player commits.
var _title_active: bool = true


func _ready() -> void:
	UiThemeBuilder.apply(self)
	UiSound.attach(self)
	add_to_group("main_ui")
	background.color = UiThemeBuilder.color("bg")
	scrim.color = UiThemeBuilder.color("bg")
	panel_bg.add_theme_stylebox_override("panel", _side_panel_style())
	get_viewport().size_changed.connect(_layout_board)
	_build_props()
	_layout_board()
	_build_icon_rail()
	_build_overlays()
	_show_desk_tab("office")
	_connect_events()
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	if SaveManager.has_save():
		Simulation.load_saved_run()
	else:
		Simulation.start_run()
	_build_title_screen()
	refresh_all()
	_sync_overlay_input()


## Modal sheets are authored against the window, but the screens that open them
## live inside the zoomed room on a handset. They mount here instead, above the
## zoom, so a confirmation never inherits the room's transform.
func mount_overlay(control: Control) -> void:
	overlay_root.add_child(control)


func _build_overlays() -> void:
	_angel_investors = ANGEL_INVESTORS.instantiate()
	_run_end = RUN_END.instantiate()
	_round_debrief = ROUND_DEBRIEF.instantiate()
	_bills_screen = BILLS_SCREEN.instantiate()
	_burn_lab = BURN_LAB.instantiate()
	_pipeline_editor = PIPELINE_EDITOR.instantiate()
	_ascension_select = ASCENSION_SELECT.instantiate()
	_meta_hub = META_HUB.instantiate()
	_achievements = ACHIEVEMENTS.instantiate()
	_investor_call = INVESTOR_CALL.instantiate()
	for overlay in [
		_angel_investors, _round_debrief, _bills_screen, _run_end, _burn_lab,
		_pipeline_editor, _ascension_select, _meta_hub, _achievements,
	]:
		overlay_root.add_child(overlay)
	# The investor is the only person in the game, so he interrupts everything:
	# his call sits above every other overlay rather than queueing behind them.
	overlay_root.add_child(_investor_call)
	_achievement_splash = AchievementSplash.mount(self)
	_round_debrief.continue_pressed.connect(_on_debrief_continue)
	_bills_screen.continue_pressed.connect(_on_bills_continue)


## The panel is a slab bolted to the right-hand edge, not a floating card: it is
## square against the window and only carries an edge on the side that faces
## into the room.
func _side_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var base: Color = UiThemeBuilder.color("bg")
	# Near-opaque: the slab now covers most of the window for the catalogue
	# screens, and at the old 0.93 the desk's own readouts showed through the
	# job tiles behind it.
	style.bg_color = Color(base.r, base.g, base.b, 0.99)
	style.border_width_left = UiThemeBuilder.MODULE_BORDER
	style.border_color = UiThemeBuilder.color("stroke_dim")
	return style


# --- Desk layout -------------------------------------------------------------

## Everything on the desk is placed from the artwork's own coordinates, so a
## repainted room moves the furniture rather than leaving the UI pinned to
## numbers that used to be right.
func _layout_board() -> void:
	var size: Vector2 = get_viewport_rect().size
	var panel_width: float = _base_panel_width(size)
	# On a handset the room is zoomed in around the laptop glass, so the console
	# type — which has to grow to stay physically readable — still prints on the
	# painted screen instead of floating past the bezel. The art, the work
	# column and every prop take the same transform, so the picture and the
	# furniture keep their registration; the edges of the room crop away.
	var zoom: float = ConsoleMetrics.room_zoom()
	var focus: Vector2 = _room_focus()
	var full_rect: Rect2 = _zoom_rect(Rect2(0.0, 0.0, 1.0, 1.0), zoom, focus)
	_place(board_art, full_rect, size, full_rect)
	_place(board_art_next, full_rect, size, full_rect)
	_place(work_column, _zoom_rect(
		AssetCatalog.board_region(board_dwelling(), "work_column"), zoom, focus
	), size, full_rect)
	side_panel.offset_left = -panel_width
	side_panel.offset_right = 0.0
	_apply_panel_slide(_panel_slide)
	_layout_props(size, zoom, focus)
	get_tree().call_group("console_screens", "fit_console")
	# Screens that hang off the room's own furniture rather than off the work
	# column as a whole have to be told the room has moved.
	get_tree().call_group("board_mounted", "relayout_on_board")


## Screens that are catalogues rather than status readouts. On the narrow slab a
## job offer got a column 442px wide, which wrapped its title over three lines
## and fitted two cards on screen; given most of the window they lay out as a
## grid of tiles, which is what the width is for.
const WIDE_PANEL_TABS := ["jobs", "market", "build"]
## Kept back from the full window so the room is still visibly behind the slab
## and the player can see what they are shopping for.
const WIDE_PANEL_RATIO := 0.62
const WIDE_PANEL_RATIO_MOBILE := 0.82
const MOBILE_VIEWPORT_WIDTH := 900.0
const SHORT_VIEWPORT_HEIGHT := 400.0
const WIDE_PANEL_RATIO_SHORT := 0.88


## How far the slab comes out for whatever it is currently carrying.
func _panel_width(viewport_size: Vector2) -> float:
	var base: float = _base_panel_width(viewport_size)
	var tab: String = _panel_tab if _panel_tab != "" else _closing_tab
	if tab in WIDE_PANEL_TABS:
		return maxf(base, viewport_size.x * _wide_panel_ratio(viewport_size))
	return base


func _wide_panel_ratio(viewport_size: Vector2) -> float:
	if viewport_size.y < SHORT_VIEWPORT_HEIGHT:
		return WIDE_PANEL_RATIO_SHORT
	# The viewport is design units, which expand past 900 on a phone; the
	# platform is what decides this, not the canvas width.
	if ConsoleMetrics.is_mobile() or viewport_size.x < MOBILE_VIEWPORT_WIDTH:
		return WIDE_PANEL_RATIO_MOBILE
	return WIDE_PANEL_RATIO


## The slab at rest, which is what the desk and the nav bar are laid out around.
## The desk keeps this measure whatever the panel is doing: a wide slide-over is
## an overlay on the room, not a resize of it.
func _base_panel_width(viewport_size: Vector2) -> float:
	var region: Rect2 = AssetCatalog.board_region(board_dwelling(), "side_panel")
	if region.size.x > 0.0:
		return region.size.x * viewport_size.x
	return minf(UiThemeBuilder.SIDE_PANEL_WIDTH, viewport_size.x * 0.4)


## Scales a window-fraction rect about the room's focus point. Applying the
## same transform to the art and to everything measured off it keeps the
## furniture registered on the picture at any zoom.
func _zoom_rect(rect: Rect2, zoom: float, focus: Vector2) -> Rect2:
	if zoom <= 1.001 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return rect
	return Rect2(focus + (rect.position - focus) * zoom, rect.size * zoom)


## Where the zoom holds still: the centre of the laptop glass, which is the
## thing the player has to be able to read.
func _room_focus() -> Vector2:
	var dwelling: String = board_dwelling()
	var glass: Rect2 = AssetCatalog.board_laptop_screen(dwelling)
	if glass.size.x > 0.0 and glass.size.y > 0.0:
		return glass.get_center()
	var column: Rect2 = AssetCatalog.board_region(dwelling, "work_column")
	if column.size.x > 0.0 and column.size.y > 0.0:
		return column.get_center()
	return Vector2(0.5, 0.55)


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
		plan.pressed.connect(open_ascension_select)


func _layout_props(viewport_size: Vector2, zoom: float = 1.0, focus: Vector2 = Vector2(0.5, 0.5)) -> void:
	var dwelling: String = board_dwelling()
	for key in _props:
		var prop: Control = _props[key]
		var rect: Rect2 = AssetCatalog.board_prop(dwelling, str(key))
		_place(prop, _zoom_rect(rect, zoom, focus), viewport_size, Rect2())
		# A prop the artwork does not carry has nowhere honest to sit.
		prop.visible = rect.size.x > 0.0


func _refresh_props() -> void:
	var state := Simulation.run_state
	var heat: float = float(state.compute.get("heat", 0.0))
	var capacity: float = maxf(1.0, float(state.compute.get("heat_capacity", 100.0)))
	var ratio: float = heat / capacity
	_set_prop("heat_readout", "HEAT", "%d%%" % int(round(ratio * 100.0)), _heat_role(ratio))
	var watts: float = float(state.compute.get("power_draw", 0.0))
	_set_prop("power_meter", "POWER", "%.1f kW" % (watts / 1000.0), "energy")
	_set_prop_lines(
		"plan_board", "BURN PLAN", _plan_lines(), _contract_lines(), _ledger_lines()
	)
	var plan: BoardProp = _props.get("plan_board")
	if plan != null:
		plan.tooltip_text = _board_tooltip()
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
	key: String, caption: String, lines: Array, notes: Array = [], ledger: Array = []
) -> void:
	var prop: BoardProp = _props.get(key)
	if prop != null:
		prop.set_checklist(caption, lines, notes, ledger)


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
func _build_title_screen() -> void:
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
	if _title_screen == null:
		return
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

## A second way into the panel's screens, down its own inside edge, for the hand
## that is already on that side of the window.
func _build_icon_rail() -> void:
	for tab in RAIL_TABS:
		var button := Button.new()
		button.name = tab.capitalize()
		button.flat = true
		button.tooltip_text = tab.capitalize()
		button.custom_minimum_size = Vector2(52, 52)
		button.icon = AssetCatalog.nav_icon(str(NAV_ICON_KEYS.get(tab, tab)))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 26)
		button.pressed.connect(_on_rail_pressed.bind(tab))
		icon_rail.add_child(button)
	var close := Button.new()
	close.name = "Close"
	close.flat = true
	close.text = "×"
	close.tooltip_text = "Back to the desk"
	close.custom_minimum_size = Vector2(52, 52)
	close.add_theme_font_size_override("font_size", 28)
	close.pressed.connect(close_panel)
	icon_rail.add_child(close)
	icon_rail.move_child(close, 0)


func _on_rail_pressed(tab: String) -> void:
	UiSound.play("tap")
	open_panel(tab)


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
## name without knowing whether it lives on the desk or in the panel.
func switch_tab(tab_name: String) -> void:
	match tab_name:
		"work":
			close_panel()
			_show_desk_tab(_desk_tab_now())
		"office", "board":
			close_panel()
			_show_desk_tab(tab_name)
		"more":
			open_panel("menu")
		_:
			if PANEL_SCENES.has(tab_name):
				open_panel(tab_name)


func open_panel(tab_name: String) -> void:
	if not PANEL_SCENES.has(tab_name):
		return
	# Tapping the tab you are already on shuts the panel, which is how a slab
	# bolted to the edge of the room should behave.
	if _panel_tab == tab_name and _panel_slide <= 0.01:
		close_panel()
		return
	_panel_tab = tab_name
	_closing_tab = ""
	_mount(panel_body, PANEL_SCENES, tab_name)
	_slide_panel(0.0)
	_update_scrim()


func close_panel() -> void:
	if _panel_slide >= 0.99:
		return
	# The tab is cleared only once the slab is off screen: it decides how wide
	# the slab is, so dropping it now would snap a wide panel to the narrow
	# measure and slide the wrong shape out.
	_slide_panel(1.0)
	_closing_tab = _panel_tab
	_panel_tab = ""
	_update_scrim()


func _slide_panel(target: float) -> void:
	if _panel_tween != null and _panel_tween.is_valid():
		_panel_tween.kill()
	_panel_tween = create_tween()
	_panel_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_panel_tween.tween_method(_apply_panel_slide, _panel_slide, target, PANEL_SLIDE_SECONDS)
	if target <= 0.01:
		_panel_tween.finished.connect(func() -> void:
			get_tree().call_group("console_screens", "fit_console")
		, CONNECT_ONE_SHOT)


func _apply_panel_slide(value: float) -> void:
	_panel_slide = value
	var width: float = _panel_width(get_viewport_rect().size)
	side_panel.offset_left = -width + width * value
	side_panel.offset_right = width * value


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
		if host == panel_body:
			_fit_to_panel(screen)
		_screen_cache[tab_name] = screen
	var mounted: Control = _screen_cache[tab_name]
	if mounted.get_parent() != host:
		mounted.reparent(host)
	mounted.visible = true
	if mounted.has_method("refresh"):
		mounted.refresh()
	if mounted.has_method("fit_console"):
		mounted.call_deferred("fit_console")


## The panel is narrower than the screens were drawn for, so anything mounted in
## it is pinned to the slab and clipped at its edge rather than allowed to spill
## over the desk behind it.
func _fit_to_panel(screen: Control) -> void:
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.clip_contents = true
	for margin in screen.find_children("*", "MarginContainer", true, false):
		for side in ["left", "right"]:
			if margin.get_theme_constant("margin_" + side) > UiThemeBuilder.SPACE_MD:
				margin.add_theme_constant_override("margin_" + side, UiThemeBuilder.SPACE_MD)


func open_burn_lab() -> void:
	if FeatureFlags.is_enabled("burn_lab_enabled"):
		_burn_lab.open()


func open_pipeline_editor() -> void:
	_pipeline_editor.open()


func open_ascension_select() -> void:
	_ascension_select.open()


func open_meta_hub() -> void:
	_meta_hub.open()


func open_achievements() -> void:
	_achievements.open()


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
	var alpha: float = SCRIM_PANEL if _panel_slide < 0.5 else SCRIM_DESK
	scrim.color = Color(base.r, base.g, base.b, alpha)


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
	# Taking a contract is done with, so the panel shuts and the desk comes back.
	EventBus.job_accepted.connect(func(_id): switch_tab("work"))
	EventBus.job_started.connect(func(_id): switch_tab("board"))
	EventBus.round_started.connect(refresh_all)
	EventBus.reward_calculated.connect(func(_a): refresh_all())
	EventBus.perk_acquired.connect(func(_a): refresh_all())
	EventBus.upgrade_purchased.connect(func(_a): refresh_all())
	EventBus.run_ended.connect(func(_victory): refresh_all())
	EventBus.run_ended.connect(_on_run_ended_call)
	# Burning and billing move cash mid-prompt. The board on the wall is where
	# the player watches it, so keep the room honest without rebuilding every
	# screen behind it.
	EventBus.tokens_consumed.connect(func(_amount): _refresh_props())
	EventBus.bill_due.connect(func(_type, _amount): _refresh_props())
	EventBus.achievement_unlocked.connect(_on_achievement_unlocked)


## Awards can land in the middle of a burn, several at once, so the splash owns a
## queue of its own and this only has to hand them over.
func _on_achievement_unlocked(achievement_id: String) -> void:
	if _achievement_splash != null:
		_achievement_splash.enqueue(achievement_id)


func _on_work_session_finished(result: Dictionary) -> void:
	if _desk_tab == "board":
		_show_desk_tab("office")
	var summary: Dictionary = result.get("summary", {})
	if not summary.is_empty() and Simulation.phase != Simulation.Phase.RUN_END:
		# The debrief gets the stage to itself; the angel draft reopens when the
		# player hits Continue.
		_angel_investors.visible = false
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
	_angel_investors.visible = false
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
	# verdict never lands before the reason for it.
	if Simulation.phase == Simulation.Phase.RUN_END and not _bills_screen.visible and _pending_statement.is_empty():
		_run_end.show_from_state(
			bool(Simulation.run_state.flags.get("victory", false)),
			str(Simulation.run_state.flags.get("loss_reason", ""))
		)
	if Simulation.phase == Simulation.Phase.ROUND_PREP:
		_maybe_call_ascension_beat()
	_sync_overlay_input()


## The round the deadline stops being background reading and starts being the
## thing the player is running out of time for.
const ASCENSION_WARNING_ROUND := 9
## How near the deadline the investor rings to remind the player it exists.
const INVESTOR_FINAL_CALL_ROUNDS := 3

## The investor introduces himself once per run, not once per load.
var _intro_call_shown: bool = false
## Which of his set-piece calls this run has already heard.
var _investor_beats: Dictionary = {}


## Everything the board is kept in the corner of the eye for. What the company
## has, what it is thought of, and how much of the year is left — the last three
## numbers that used to float in a strip over the room instead of being written
## somewhere a person at this desk could have written them.
##
## All on one line, because the board is a fixed piece of wall and the plan and
## the contract under this have to fit on it too. It goes up in the red pen when
## the company is in trouble on either count, which is what anyone keeping this
## board would do to it.
func _ledger_lines() -> Array:
	var state := Simulation.run_state
	var cash: float = float(state.economy.get("cash", 0.0))
	var round_number: int = int(state.calendar.get("round", 1))
	var deadline: int = round_number + Simulation.rounds_remaining() - 1
	var trouble: bool = (
		cash < 0.0
		or Simulation.rounds_remaining() <= 2
		or _ascension_urgency_line(round_number) != ""
	)
	return [[
		"%s · REP %d · R%d/%d" % [
			NumberFormat.format_cash(cash),
			int(state.business.get("reputation", 0.0)),
			round_number,
			deadline,
		],
		BoardProp.MARKER_URGENT if trouble else BoardProp.MARKER_INK,
	]]


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
	_investor_beats.clear()


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
	_investor_call.call_player("run_intro")


## The investor, on demand. Tapping the phone on the desk is how the player
## re-reads the terms they agreed to.
func open_investor_terms() -> void:
	_investor_call.call_player("terms")


## Any beat the rest of the game wants him to weigh in on.
func investor_says(trigger: String, context: Dictionary = {}) -> void:
	_investor_call.call_player(trigger, context)


## The beats of the run he insists on being present for. Each fires once, when
## the state that earns it first appears, so he interrupts the moment rather than
## every refresh that follows it.
func _maybe_call_ascension_beat() -> void:
	if _title_active or _investor_call.visible:
		return
	var progress: Dictionary = Simulation.ascension_progress()
	if progress.is_empty():
		return
	# The last rounds take precedence: being behind with the year nearly gone is
	# the more urgent of the two things he could be ringing about.
	var rounds_left: int = int(progress.get("rounds_remaining", 99))
	if rounds_left <= INVESTOR_FINAL_CALL_ROUNDS and not _investor_beats.has("contract_final_call"):
		_investor_beats["contract_final_call"] = true
		investor_says("contract_final_call", {"rounds_remaining": rounds_left})
		return
	if float(progress.get("burn_ratio", 0.0)) >= 0.5 and not _investor_beats.has("contract_halfway"):
		_investor_beats["contract_halfway"] = true
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
