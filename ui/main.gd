extends Control

## The shell: a desk, in landscape, with the game played on the things standing
## on it.
##
## Nothing here is a page the player navigates to. The desk artwork fills the
## window and everything else is mounted onto it at a position authored beside
## the art (`board_scene.regions` / `board_scene.props` in the asset catalog):
## the machine stands on the desk in the work column, the readouts are painted
## into the props that carry them, and the job board, market, build and menu
## slide in from the right over the room rather than replacing it. The desk is
## never off screen, so the player is always looking at their own operation.

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

## Bottom navigation buttons to the icon each one borrows from the art kit.
const NAV_ICON_KEYS := {
	"work": "office",
	"jobs": "jobs",
	"build": "build",
	"market": "market",
	"ascend": "board",
	"more": "menu",
}

## Which nav button owns each tab, so the highlight survives WORK resolving to
## either the office or the burn board.
const TAB_TO_NAV := {
	"office": "work",
	"board": "work",
	"jobs": "jobs",
	"build": "build",
	"market": "market",
	"menu": "more",
}

## The rail down the inside edge of the side panel, mirroring the nav for the
## hand that is already over there.
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

const HUD_HEIGHT := 76.0
const NAV_HEIGHT := 78.0
const CHIP_FONT_SIZE := 22
const CHIP_FONT_SIZE_MIN := 15

@onready var background: ColorRect = $Background
@onready var board_art: TextureRect = $BoardArt
@onready var board_art_next: TextureRect = $BoardArtNext
@onready var scrim: ColorRect = $Scrim
@onready var prop_layer: Control = $PropLayer
@onready var work_column: Control = $WorkColumn
@onready var content_container: Control = $WorkColumn/ContentContainer
@onready var top_hud: PanelContainer = $TopHud
@onready var logo: Label = $TopHud/HudMargin/HudRow/Wordmark/Logo
@onready var version_label: Label = $TopHud/HudMargin/HudRow/Wordmark/Version
@onready var stats_row: HBoxContainer = $TopHud/HudMargin/HudRow/StatsRow
@onready var cash_chip: StatChip = $TopHud/HudMargin/HudRow/StatsRow/CashChip
@onready var token_chip: StatChip = $TopHud/HudMargin/HudRow/StatsRow/TokenChip
@onready var heat_chip: StatChip = $TopHud/HudMargin/HudRow/StatsRow/HeatChip
@onready var power_chip: StatChip = $TopHud/HudMargin/HudRow/StatsRow/PowerChip
@onready var rep_chip: StatChip = $TopHud/HudMargin/HudRow/StatsRow/RepChip
@onready var round_chip: StatChip = $TopHud/HudMargin/HudRow/StatsRow/RoundChip
@onready var ascension_goal: Button = $TopHud/HudMargin/HudRow/AscensionGoal
@onready var goal_name: Label = $TopHud/HudMargin/HudRow/AscensionGoal/GoalVBox/GoalName
@onready var goal_kicker: Label = $TopHud/HudMargin/HudRow/AscensionGoal/GoalVBox/GoalKicker
@onready var goal_bar: ProgressBar = $TopHud/HudMargin/HudRow/AscensionGoal/GoalVBox/GoalRow/GoalBar
@onready var goal_count: Label = $TopHud/HudMargin/HudRow/AscensionGoal/GoalVBox/GoalRow/GoalCount
@onready var side_panel: Control = $SidePanel
@onready var panel_bg: PanelContainer = $SidePanel/PanelBg
@onready var panel_body: Control = $SidePanel/PanelBg/PanelRow/PanelBody
@onready var icon_rail: VBoxContainer = $SidePanel/PanelBg/PanelRow/IconRail
@onready var bottom_nav: PanelContainer = $BottomNav
@onready var nav_bar: HBoxContainer = $BottomNav/NavHBox
@onready var overlay_root: Control = $OverlayRoot

var _desk_tab: String = "office"
## Which panel screen is loaded. Empty means the panel is shut and the desk has
## the whole window.
var _panel_tab: String = ""
## The tab the slab is still carrying while it slides back out of the room.
var _closing_tab: String = ""
var _panel_slide: float = 1.0
var _panel_tween: Tween = null
var _chip_font_size: int = CHIP_FONT_SIZE
var _fitting_hud: bool = false
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
var _market_badge: Label = null
var _board_stage: int = -1
var _stage_reveal_running: bool = false
var _hud_values: Dictionary = {}
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
	# The HUD floats directly over the room, the way the readouts in the artwork
	# do, instead of sitting in an opaque bar bolted across the top.
	top_hud.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	bottom_nav.add_theme_stylebox_override("panel", UiThemeBuilder.nav_bar_style())
	panel_bg.add_theme_stylebox_override("panel", _side_panel_style())
	logo.add_theme_color_override("font_color", UiThemeBuilder.color("red"))
	version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0")
	_style_ascension_goal()
	get_viewport().size_changed.connect(_layout_board)
	stats_row.minimum_size_changed.connect(_fit_hud)
	_build_props()
	_layout_board()
	_apply_nav_icons()
	_connect_nav_buttons()
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
	style.border_width_left = 2
	style.border_color = UiThemeBuilder.color("stroke_dim").lightened(0.2)
	return style


func _style_ascension_goal() -> void:
	ascension_goal.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	ascension_goal.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	ascension_goal.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	ascension_goal.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	goal_bar.add_theme_stylebox_override("background", UiThemeBuilder.progress_bg())
	goal_bar.add_theme_stylebox_override(
		"fill", UiThemeBuilder.progress_fill(UiThemeBuilder.semantic("perk"))
	)
	for label: Label in [goal_kicker, goal_name, goal_count]:
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.05, 1))
		label.add_theme_constant_override("outline_size", 6)


# --- Desk layout -------------------------------------------------------------

## Everything on the desk is placed from the artwork's own coordinates, so a
## repainted room moves the furniture rather than leaving the UI pinned to
## numbers that used to be right.
func _layout_board() -> void:
	var size: Vector2 = get_viewport_rect().size
	var panel_width: float = _base_panel_width(size)
	_place(work_column, AssetCatalog.board_region("work_column"), size, Rect2(
		0.014, HUD_HEIGHT / size.y, 1.0 - (panel_width / size.x) - 0.03,
		1.0 - (HUD_HEIGHT + NAV_HEIGHT) / size.y
	))
	top_hud.offset_bottom = HUD_HEIGHT
	side_panel.offset_left = -panel_width
	side_panel.offset_right = 0.0
	bottom_nav.offset_top = -NAV_HEIGHT
	_apply_panel_slide(_panel_slide)
	_layout_props(size)
	_fit_hud()


## Screens that are catalogues rather than status readouts. On the narrow slab a
## job offer got a column 442px wide, which wrapped its title over three lines
## and fitted two cards on screen; given most of the window they lay out as a
## grid of tiles, which is what the width is for.
const WIDE_PANEL_TABS := ["jobs", "market", "build"]
## Kept back from the full window so the room is still visibly behind the slab
## and the player can see what they are shopping for.
const WIDE_PANEL_RATIO := 0.62


## How far the slab comes out for whatever it is currently carrying.
func _panel_width(viewport_size: Vector2) -> float:
	var base: float = _base_panel_width(viewport_size)
	var tab: String = _panel_tab if _panel_tab != "" else _closing_tab
	if tab in WIDE_PANEL_TABS:
		return maxf(base, viewport_size.x * WIDE_PANEL_RATIO)
	return base


## The slab at rest, which is what the desk and the nav bar are laid out around.
## The desk keeps this measure whatever the panel is doing: a wide slide-over is
## an overlay on the room, not a resize of it.
func _base_panel_width(viewport_size: Vector2) -> float:
	var region: Rect2 = AssetCatalog.board_region("side_panel")
	if region.size.x > 0.0:
		return region.size.x * viewport_size.x
	return minf(UiThemeBuilder.SIDE_PANEL_WIDTH, viewport_size.x * 0.4)


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
	for key in AssetCatalog.board_prop_keys():
		var prop := BoardProp.new()
		prop.prop_key = str(key)
		prop_layer.add_child(prop)
		_props[str(key)] = prop
	var phone: BoardProp = _props.get("phone")
	if phone != null:
		phone.pressed.connect(open_investor_terms)


func _layout_props(viewport_size: Vector2) -> void:
	for key in _props:
		var prop: Control = _props[key]
		_place(prop, AssetCatalog.board_prop(str(key)), viewport_size, Rect2())
		# A prop the artwork does not carry has nowhere honest to sit.
		prop.visible = AssetCatalog.board_prop(str(key)).size.x > 0.0


func _refresh_props() -> void:
	var state := Simulation.run_state
	var heat: float = float(state.compute.get("heat", 0.0))
	var capacity: float = maxf(1.0, float(state.compute.get("heat_capacity", 100.0)))
	var ratio: float = heat / capacity
	_set_prop("heat_readout", "HEAT", "%d%%" % int(round(ratio * 100.0)), _heat_role(ratio))
	var watts: float = float(state.compute.get("power_draw", 0.0))
	_set_prop("power_meter", "POWER", "%.1f kW" % (watts / 1000.0), "energy")
	_set_prop_lines("plan_board", "BURN PLAN", _plan_lines())
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
	var progress: Dictionary = Simulation.ascension_progress()
	var contract_done: bool = not progress.is_empty() \
		and float(progress.get("burn_ratio", 0.0)) >= 1.0 \
		and float(progress.get("quality_average", 0.0)) \
			>= float(progress.get("quality_min", 0.0))
	return [
		["CONTRACTS", has_contracts],
		["UPGRADE RIG", Array(state.build.get("hardware", [])).size() > 1],
		["STAY COOL", float(state.compute.get("heat", 0.0))
			< 0.7 * maxf(1.0, float(state.compute.get("heat_capacity", 100.0)))],
		["CONTRACT", contract_done],
	]


func _set_prop(key: String, caption: String, value: String, role: String) -> void:
	var prop: BoardProp = _props.get(key)
	if prop != null:
		prop.set_readout(caption, value, UiThemeBuilder.semantic(role))


func _set_prop_lines(key: String, caption: String, lines: Array) -> void:
	var prop: BoardProp = _props.get(key)
	if prop != null:
		prop.set_checklist(caption, lines)


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


# --- HUD ---------------------------------------------------------------------

## The HUD is one row over the room and the numbers in it grow all run, so it is
## the chips that give: they read a size smaller rather than pushing the goal
## plate off the right-hand edge.
func _fit_hud() -> void:
	if _fitting_hud or stats_row == null:
		return
	_fitting_hud = true
	var strip: float = top_hud.size.x
	if strip <= 1.0:
		strip = get_viewport_rect().size.x
	var budget: float = maxf(
		120.0, strip - 36.0 - 150.0 - ascension_goal.custom_minimum_size.x - 28.0
	)
	var chip_size: int = CHIP_FONT_SIZE
	while chip_size > CHIP_FONT_SIZE_MIN and _chips_width(chip_size) > budget:
		chip_size -= 1
	_set_chip_font_size(chip_size)
	_fitting_hud = false


func _hud_chips() -> Array[StatChip]:
	return [cash_chip, token_chip, heat_chip, power_chip, rep_chip, round_chip]


func _chips_width(font_size: int) -> float:
	var chips: Array[StatChip] = _hud_chips()
	var total: float = stats_row.get_theme_constant("separation") * float(chips.size() - 1)
	for chip in chips:
		total += chip.width_at_font_size(font_size)
	return total


## Re-applying an override re-measures every chip and restarts their count-up
## animations, so the size is only pushed when it has actually moved.
func _set_chip_font_size(font_size: int) -> void:
	if font_size == _chip_font_size:
		return
	_chip_font_size = font_size
	for chip in _hud_chips():
		chip.set_value_font_size(font_size)


# --- Navigation --------------------------------------------------------------

func _apply_nav_icons() -> void:
	for child in nav_bar.get_children():
		if child is Button:
			var nav_key: String = child.name.to_lower()
			var icon: Texture2D = AssetCatalog.nav_icon(str(NAV_ICON_KEYS.get(nav_key, nav_key)))
			if icon != null:
				child.icon = icon
			child.add_theme_constant_override("icon_max_width", 30)
			child.add_theme_constant_override("h_separation", 6)
			child.add_theme_font_size_override("font_size", 19)
			child.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			child.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
			child.expand_icon = false
	var market_button: Button = nav_bar.get_node_or_null("Market")
	if market_button != null and _market_badge == null:
		_market_badge = Label.new()
		_market_badge.text = "!"
		_market_badge.tooltip_text = "You can afford upgrades — spend your cash in the Market."
		_market_badge.add_theme_font_size_override("font_size", 22)
		_market_badge.add_theme_color_override("font_color", UiThemeBuilder.color("green"))
		_market_badge.add_theme_color_override("font_outline_color", UiThemeBuilder.color("bg"))
		_market_badge.add_theme_constant_override("outline_size", 5)
		_market_badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_market_badge.offset_left = 22.0
		_market_badge.offset_top = 0.0
		_market_badge.visible = false
		market_button.add_child(_market_badge)


func _connect_nav_buttons() -> void:
	for child in nav_bar.get_children():
		if child is Button:
			child.pressed.connect(_on_nav_pressed.bind(child.name.to_lower()))


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


func _on_nav_pressed(nav_key: String) -> void:
	UiSound.play("tap")
	match nav_key:
		"work":
			close_panel()
			_show_desk_tab(_desk_tab_now())
		"ascend":
			open_ascension_select()
		"more":
			open_panel("menu")
		_:
			open_panel(nav_key)


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
	_update_nav_highlight()


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
	_update_nav_highlight()


func _slide_panel(target: float) -> void:
	if _panel_tween != null and _panel_tween.is_valid():
		_panel_tween.kill()
	_panel_tween = create_tween()
	_panel_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_panel_tween.tween_method(_apply_panel_slide, _panel_slide, target, PANEL_SLIDE_SECONDS)


func _apply_panel_slide(value: float) -> void:
	_panel_slide = value
	var width: float = _panel_width(get_viewport_rect().size)
	side_panel.offset_left = -width + width * value
	side_panel.offset_right = width * value
	# The HUD is the room's own signage, so it retreats to the desk rather than
	# running on behind the slab where the goal plate would be half-covered.
	top_hud.offset_right = -width * (1.0 - value)
	# The nav is the room's, not the slab's, so it gives up whatever floor the
	# slab is standing on. Without this a wide slide-over buries half the tabs.
	bottom_nav.offset_right = -width * (1.0 - value)
	# The goal plate is the widest thing on the strip and the panel is where its
	# business gets done, so it stands down rather than squeezing the chips.
	ascension_goal.visible = value > 0.5
	_fit_hud()


func _show_desk_tab(tab_name: String) -> void:
	if not DESK_SCENES.has(tab_name):
		return
	_desk_tab = tab_name
	_mount(content_container, DESK_SCENES, tab_name)
	_update_board_art()
	_update_scrim()
	_update_nav_highlight()


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
	var stage: int = AssetCatalog.office_stage_for_build(Simulation.run_state.build)
	if stage != _board_stage and not _stage_reveal_running:
		if _board_stage < 0:
			_board_stage = stage
			board_art.texture = AssetCatalog.board_scene_art(stage)
		else:
			_reveal_stage(stage)
	board_art.visible = board_art.texture != null
	scrim.visible = board_art.visible


func _update_scrim() -> void:
	var base: Color = UiThemeBuilder.color("bg")
	var alpha: float = SCRIM_PANEL if _panel_slide < 0.5 else SCRIM_DESK
	scrim.color = Color(base.r, base.g, base.b, alpha)


## Buying something that changes the room is the reward, so the chrome steps out
## of the way, the new desk fades in, and then it all comes back.
func _reveal_stage(stage: int) -> void:
	_stage_reveal_running = true
	_board_stage = stage
	board_art_next.texture = AssetCatalog.board_scene_art(stage)
	board_art_next.visible = board_art_next.texture != null
	var chrome: Array[Control] = [top_hud, work_column, bottom_nav, prop_layer]
	var tween: Tween = create_tween()
	for control in chrome:
		tween.parallel().tween_property(control, "modulate:a", 0.0, 0.22)
	tween.tween_property(board_art_next, "modulate:a", 1.0, 0.5)
	tween.tween_interval(0.4)
	for control in chrome:
		tween.parallel().tween_property(control, "modulate:a", 1.0, 0.28)
	tween.tween_callback(_finish_stage_reveal)


func _finish_stage_reveal() -> void:
	board_art.texture = board_art_next.texture
	board_art.visible = board_art.texture != null
	board_art_next.modulate.a = 0.0
	board_art_next.visible = false
	_stage_reveal_running = false
	_update_board_art()


func _update_nav_highlight() -> void:
	var active_nav: String = "work" if _panel_slide > 0.5 else str(TAB_TO_NAV.get(_panel_tab, ""))
	for child in nav_bar.get_children():
		if child is Button:
			var nav_key: String = child.name.to_lower()
			var active: bool = nav_key == active_nav
			child.disabled = false
			child.modulate = Color.WHITE
			child.add_theme_color_override(
				"icon_normal_color",
				Color.WHITE if active else Color(0.6, 0.6, 0.68)
			)
			child.add_theme_color_override(
				"font_color",
				UiThemeBuilder.color("blue") if active else Color(0.92, 0.92, 0.95)
			)
			child.add_theme_stylebox_override("normal", UiThemeBuilder.nav_tab_style(active))
			child.add_theme_stylebox_override("hover", UiThemeBuilder.nav_tab_style(active))
			child.add_theme_stylebox_override("pressed", UiThemeBuilder.nav_tab_style(true))
			child.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var work_button: Button = nav_bar.get_node_or_null("Work")
	if work_button != null:
		work_button.text = "BURN" if Simulation.is_work_running() else "DESK"


# --- Events ------------------------------------------------------------------

func _connect_events() -> void:
	ascension_goal.pressed.connect(open_ascension_select)
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
	# Burning and billing move cash mid-prompt. The HUD is the only place the
	# player watches it, so keep it honest without rebuilding every screen.
	EventBus.tokens_consumed.connect(func(_amount): _refresh_hud())
	EventBus.bill_due.connect(func(_type, _amount): _refresh_hud())
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
	_refresh_hud()
	_update_board_art()
	_update_market_badge()
	_update_nav_highlight()
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


func _update_market_badge() -> void:
	if _market_badge == null:
		return
	var cash: float = float(Simulation.run_state.economy.get("cash", 0.0))
	var owned: Array = Simulation.run_state.build.get("upgrades", [])
	var affordable: bool = false
	for upgrade in ContentDatabase.upgrades:
		if not (upgrade.id in owned) and upgrade.cost > 0.0 and upgrade.cost <= cash:
			affordable = true
			break
	_market_badge.visible = affordable


func _refresh_hud() -> void:
	var state := Simulation.run_state
	var cash: float = float(state.economy.get("cash", 0.0))
	var token_rate: float = float(state.compute.get("token_rate", 0.0))
	var reputation: float = float(int(state.business.get("reputation", 0.0)))
	var heat: float = float(state.compute.get("heat", 0.0))
	var capacity: float = maxf(1.0, float(state.compute.get("heat_capacity", 100.0)))
	var heat_ratio: float = heat / capacity
	var watts: float = float(state.compute.get("power_draw", 0.0))
	cash_chip.setup_value("cash", cash, "cash")
	cash_chip.set_value_color(UiThemeBuilder.semantic("money" if cash >= 0.0 else "danger"))
	token_chip.setup_value("tokens", token_rate, "tokens")
	token_chip.tooltip_text = "Throughput: tokens the rig produces per second."
	heat_chip.setup("heat", "%d%%" % int(round(heat_ratio * 100.0)))
	heat_chip.set_value_color(UiThemeBuilder.semantic(_heat_role(heat_ratio)))
	heat_chip.tooltip_text = "Heat %d of %d. The rig throttles hot and catches fire at the top." % [
		int(round(heat)), int(round(capacity)),
	]
	power_chip.setup("power", "%.1f kW" % (watts / 1000.0))
	power_chip.set_value_color(UiThemeBuilder.semantic("energy"))
	power_chip.tooltip_text = "%d W draw. Power is metered every prompt and makes the heat." % int(round(watts))
	rep_chip.setup_value("reputation", reputation, "plain")
	rep_chip.tooltip_text = _reputation_tooltip(reputation)
	_pulse_changed_chips(cash, token_rate, reputation)
	_refresh_round_chip()
	_refresh_ascension_goal()
	_refresh_props()


## The investor's terms, on screen at all times rather than behind a tab the
## player has to already know about: what he wants, and how much of it is done.
## The contract is live from round one, so this is never a checklist of things
## still to unlock — it is always the burn itself.
func _refresh_ascension_goal() -> void:
	var summary: Dictionary = Simulation.ascension_summary()
	var contract: Dictionary = Dictionary(summary.get("contract", {}))
	if contract.is_empty() or Simulation.phase == Simulation.Phase.RUN_END:
		ascension_goal.visible = false
		return
	ascension_goal.visible = true
	goal_name.text = str(contract.get("name", "The contract"))
	var progress: Dictionary = Dictionary(summary.get("progress", {}))
	var burned: float = float(progress.get("tokens_burned", 0.0))
	var total: float = maxf(1.0, float(progress.get("total_burn", contract.get("total_burn", 1.0))))
	var rounds_left: int = int(progress.get("rounds_remaining", Simulation.rounds_remaining()))
	var role: String = "danger" if rounds_left <= 3 else (
		"warning" if rounds_left <= 6 else "perk"
	)
	goal_kicker.text = "CONTRACT · %d ROUND(S) LEFT" % rounds_left
	goal_kicker.add_theme_color_override("font_color", UiThemeBuilder.semantic(role))
	goal_bar.max_value = total
	goal_bar.value = clampf(burned, 0.0, total)
	goal_bar.add_theme_stylebox_override(
		"fill", UiThemeBuilder.progress_fill(UiThemeBuilder.semantic(role))
	)
	goal_count.text = "%s / %s" % [
		NumberFormat.format(burned), NumberFormat.format(total),
	]


## The round the deadline stops being background reading and starts being the
## thing the player is running out of time for.
const ASCENSION_WARNING_ROUND := 9
## How near the deadline the investor rings to remind the player it exists.
const INVESTOR_FINAL_CALL_ROUNDS := 3

## The investor introduces himself once per run, not once per load.
var _intro_call_shown: bool = false
## Which of his set-piece calls this run has already heard.
var _investor_beats: Dictionary = {}


## A round has no prompt budget any more, so the chip counts up rather than down:
## "R3 · 5p" is the third round, five prompts spent on it so far. What limits a
## round is each contract's own deadline, which the job cards and board show.
func _refresh_round_chip() -> void:
	var state := Simulation.run_state
	var round_number: int = int(state.calendar.get("round", 1))
	var prompts_used: int = Simulation.prompts_used_this_round()
	var deadline: int = round_number + Simulation.rounds_remaining() - 1
	round_chip.setup("deadline", "R%d/%d · %dp" % [round_number, deadline, prompts_used])
	var lines: PackedStringArray = []
	lines.append("Round %d of %d" % [round_number, deadline])
	lines.append("%d prompt(s) spent this round" % prompts_used)
	lines.append("A round runs until every contract you took resolves, then the bills land.")
	var urgency: String = _ascension_urgency_line(round_number)
	if urgency != "":
		lines.append(urgency)
	var slots: int = Simulation.job_slots()
	if slots > 1:
		lines.append("%d machines: %d contracts advance per prompt" % [slots, slots])
	else:
		lines.append("One machine: one contract advances per prompt. Buy another to work in parallel.")
	round_chip.tooltip_text = "\n".join(lines)
	var remaining: int = Simulation.rounds_remaining()
	round_chip.set_value_color(
		UiThemeBuilder.semantic("danger") if remaining <= 2
		else (UiThemeBuilder.semantic("warning") if urgency != "" else UiThemeBuilder.color("white"))
	)


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


## Reputation is three things at once, so the chip says all three rather than
## leaving the player to infer them from a bare number.
func _reputation_tooltip(reputation: float) -> String:
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
	return "\n".join(lines)


## A number that moved because of something the player did should be seen
## moving, not just found changed on the next glance.
func _pulse_changed_chips(cash: float, token_rate: float, reputation: float) -> void:
	if not _hud_values.is_empty():
		if absf(cash - float(_hud_values["cash"])) > 0.5:
			cash_chip.pulse(UiThemeBuilder.semantic("money"))
		if absf(token_rate - float(_hud_values["tokens"])) > 0.5:
			token_chip.pulse(UiThemeBuilder.semantic("compute"))
		if absf(reputation - float(_hud_values["reputation"])) > 0.5:
			rep_chip.pulse(UiThemeBuilder.semantic("perk"))
	_hud_values = {"cash": cash, "tokens": token_rate, "reputation": reputation}
