extends Control

const TAB_SCENES := {
	"office": preload("res://ui/operations/operations_screen.tscn"),
	"board": preload("res://ui/board/burn_board_screen.tscn"),
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

## How far each tab dims the office diorama. The Office tab is looking at the room
## itself, so it barely tints it. The Burn Board has no panels left to keep readable
## — the machine stands in the room and its keys sit on the floor — so it only takes
## the room down far enough for green type to read against it. Every other tab is a
## stack of panels and needs the room well behind them.
const BACKDROP_SCRIM := {"office": 0.12, "board": 0.42}
const BACKDROP_SCRIM_DEFAULT := 0.72

const ANGEL_INVESTORS := preload("res://ui/screens/angel_investors.tscn")
const RUN_END := preload("res://ui/screens/run_end.tscn")
const ROUND_DEBRIEF := preload("res://ui/screens/session_summary.tscn")
const BILLS_SCREEN := preload("res://ui/screens/month_statement.tscn")
const BURN_LAB := preload("res://ui/debug/burn_lab.tscn")
const PIPELINE_EDITOR := preload("res://ui/board/pipeline_editor.tscn")
const ASCENSION_SELECT := preload("res://ui/screens/ascension_select.tscn")
const META_HUB := preload("res://ui/screens/meta_hub.tscn")
const ACHIEVEMENTS := preload("res://ui/screens/achievements_screen.tscn")
const TITLE_SCREEN := preload("res://ui/title/title_screen.tscn")

## Mirrors the status bar's margins, its wordmark-to-chips gap, and the
## wordmark's font size and outline in main.tscn.
const STATUS_BAR_MARGINS := 36.0
const STATUS_BAR_SEPARATION := 12.0
const LOGO_FONT_SIZE := 26
const LOGO_FONT_SIZE_MIN := 15
const LOGO_OUTLINE_ALLOWANCE := 10.0
const CHIP_FONT_SIZE := 34
const CHIP_FONT_SIZE_MIN := 24

@onready var background: ColorRect = $Background
@onready var scene_backdrop: TextureRect = $SceneBackdrop
@onready var scene_backdrop_next: TextureRect = $SceneBackdropNext
@onready var scrim: ColorRect = $Scrim
@onready var vbox: VBoxContainer = $VBox
@onready var status_bar: PanelContainer = $VBox/StatusBar
@onready var logo: Label = $VBox/StatusBar/Margin/StatusVBox/TopRow/Logo
@onready var stats_row: HBoxContainer = $VBox/StatusBar/Margin/StatusVBox/TopRow/StatsRow
@onready var cash_chip: StatChip = $VBox/StatusBar/Margin/StatusVBox/TopRow/StatsRow/CashChip
@onready var token_chip: StatChip = $VBox/StatusBar/Margin/StatusVBox/TopRow/StatsRow/TokenChip
@onready var rep_chip: StatChip = $VBox/StatusBar/Margin/StatusVBox/TopRow/StatsRow/RepChip
@onready var round_chip: StatChip = $VBox/StatusBar/Margin/StatusVBox/TopRow/StatsRow/RoundChip
@onready var ascension_row: Button = $VBox/StatusBar/Margin/StatusVBox/AscensionRow
@onready var ascension_bar: Control = $VBox/StatusBar/Margin/StatusVBox/AscensionBar
@onready var content_container: Control = $VBox/Body/ContentContainer
@onready var bottom_nav: PanelContainer = $VBox/BottomNav
@onready var nav_bar: HBoxContainer = $VBox/BottomNav/NavHBox
@onready var overlay_root: Control = $OverlayRoot

var _current_tab: String = "office"
var _fitting_status_bar: bool = false
var _chip_font_size: int = CHIP_FONT_SIZE
var _screen_cache: Dictionary = {}
var _angel_investors: Control = null
var _run_end: Control = null
var _round_debrief: Control = null
var _bills_screen: Control = null
var _burn_lab: Control = null
var _pipeline_editor: Control = null
var _ascension_select: Control = null
var _meta_hub: Control = null
var _achievements: Control = null
var _achievement_splash: AchievementSplash = null
var _last_angel_phase: bool = false
var _pending_statement: Dictionary = {}
var _market_badge: Label = null
var _backdrop_stage: int = -1
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
	# Stats float directly over the scene (matching the artwork's HUD style)
	# instead of sitting in an opaque bar.
	status_bar.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	bottom_nav.add_theme_stylebox_override("panel", UiThemeBuilder.nav_bar_style())
	logo.add_theme_color_override("font_color", UiThemeBuilder.color("red"))
	get_viewport().size_changed.connect(_layout_content_column)
	# Bigger numbers are a wider row. The chips only report their new width once
	# they have re-measured their text, so the fit follows that signal rather
	# than the code that set the text.
	stats_row.minimum_size_changed.connect(_fit_status_bar.bind(0.0))
	_layout_content_column()
	_apply_nav_icons()
	_connect_nav_buttons()
	_angel_investors = ANGEL_INVESTORS.instantiate()
	_run_end = RUN_END.instantiate()
	_round_debrief = ROUND_DEBRIEF.instantiate()
	_bills_screen = BILLS_SCREEN.instantiate()
	_burn_lab = BURN_LAB.instantiate()
	_pipeline_editor = PIPELINE_EDITOR.instantiate()
	_ascension_select = ASCENSION_SELECT.instantiate()
	_meta_hub = META_HUB.instantiate()
	_achievements = ACHIEVEMENTS.instantiate()
	overlay_root.add_child(_angel_investors)
	overlay_root.add_child(_round_debrief)
	overlay_root.add_child(_bills_screen)
	overlay_root.add_child(_run_end)
	overlay_root.add_child(_burn_lab)
	overlay_root.add_child(_pipeline_editor)
	overlay_root.add_child(_ascension_select)
	overlay_root.add_child(_meta_hub)
	overlay_root.add_child(_achievements)
	_achievement_splash = AchievementSplash.mount(self)
	_round_debrief.continue_pressed.connect(_on_debrief_continue)
	_bills_screen.continue_pressed.connect(_on_bills_continue)
	_switch_tab("office")
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


## Skips the front door. Used by the screenshot tool, which needs to land on a
## specific tab rather than press its way in.
func dismiss_title() -> void:
	if _title_screen != null:
		_title_screen.visible = false
	_title_active = false
	refresh_all()


## Returning to the front door from the More tab. The run stays loaded, so
## Continue picks it straight back up.
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


func _layout_content_column() -> void:
	# Clamp the app column to the design width and center it, so wide
	# (desktop/landscape) windows don't stretch the portrait layout edge
	# to edge or pin it to the left.
	var viewport_width: float = get_viewport_rect().size.x
	var column_width: float = minf(viewport_width, UiThemeBuilder.CONTENT_MAX_WIDTH)
	var safe_insets: Dictionary = _safe_area_insets()
	for column: Control in [vbox, overlay_root]:
		column.anchor_left = 0.5
		column.anchor_right = 0.5
		column.offset_left = -column_width / 2.0
		column.offset_right = column_width / 2.0
		column.offset_top = float(safe_insets.get("top", 0.0))
		column.offset_bottom = -float(safe_insets.get("bottom", 0.0))
	_fit_status_bar(column_width)


## The status row is the one place where the shell can be forced wider than the
## screen: the chips grow with the numbers in them, and the column is centred, so
## an overlong row pushes the whole app off both edges — clipping the wordmark,
## the round chip and the nav on a phone. The chips are the readout the player
## needs, so the wordmark is what gives: it shrinks to whatever space is left and
## steps aside entirely only when there is none.
func _fit_status_bar(column_width: float = 0.0) -> void:
	if logo == null or stats_row == null:
		return
	# Resizing the chips moves the row's minimum size, which is the signal that
	# calls this in the first place.
	if _fitting_status_bar:
		return
	_fitting_status_bar = true
	if column_width <= 0.0:
		# Not vbox.size.x: once the row has overflowed, the column has already
		# been stretched to fit it and would always look wide enough.
		column_width = minf(get_viewport_rect().size.x, UiThemeBuilder.CONTENT_MAX_WIDTH)
	var chips_budget: float = column_width - STATUS_BAR_MARGINS
	var chip_size: int = CHIP_FONT_SIZE
	while chip_size > CHIP_FONT_SIZE_MIN and _chips_width(chip_size) > chips_budget:
		chip_size -= 1
	_set_chip_font_size(chip_size)
	_fitting_status_bar = false
	var available: float = column_width - _chips_width(chip_size) \
		- STATUS_BAR_MARGINS - STATUS_BAR_SEPARATION - LOGO_OUTLINE_ALLOWANCE
	var font: Font = logo.get_theme_font("font")
	if font == null:
		logo.visible = available > 0.0
		return
	var size: int = LOGO_FONT_SIZE
	while size > LOGO_FONT_SIZE_MIN and _logo_width(font, size) > available:
		size -= 1
	logo.add_theme_font_size_override("font_size", size)
	logo.visible = _logo_width(font, size) <= available


func _logo_width(font: Font, font_size: int) -> float:
	return font.get_string_size(logo.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _chips_width(font_size: int) -> float:
	var chips: Array[StatChip] = [cash_chip, token_chip, rep_chip, round_chip]
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
	for chip: StatChip in [cash_chip, token_chip, rep_chip, round_chip]:
		chip.set_value_font_size(font_size)


func _safe_area_insets() -> Dictionary:
	# Only meaningful on handheld devices with notches/system bars.
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		return {}
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	var window_size: Vector2i = DisplayServer.window_get_size()
	var viewport_size: Vector2 = get_viewport_rect().size
	if window_size.y <= 0:
		return {}
	var scale: float = viewport_size.y / float(window_size.y)
	return {
		"top": float(safe_area.position.y) * scale,
		"bottom": float(window_size.y - safe_area.end.y) * scale,
	}


func _apply_nav_icons() -> void:
	for child in nav_bar.get_children():
		if child is Button:
			var nav_key: String = child.name.to_lower()
			var icon: Texture2D = AssetCatalog.nav_icon(str(NAV_ICON_KEYS.get(nav_key, nav_key)))
			if icon != null:
				child.icon = icon
			child.add_theme_constant_override("icon_max_width", 88)
			child.add_theme_constant_override("h_separation", 0)
			child.add_theme_font_size_override("font_size", 32)
	var market_button: Button = nav_bar.get_node_or_null("Market")
	if market_button != null and _market_badge == null:
		_market_badge = Label.new()
		_market_badge.text = "!"
		_market_badge.tooltip_text = "You can afford upgrades — spend your cash in the Market."
		_market_badge.add_theme_font_size_override("font_size", 30)
		_market_badge.add_theme_color_override("font_color", UiThemeBuilder.color("green"))
		_market_badge.add_theme_color_override("font_outline_color", UiThemeBuilder.color("bg"))
		_market_badge.add_theme_constant_override("outline_size", 6)
		_market_badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_market_badge.offset_left = 26.0
		_market_badge.offset_top = 2.0
		_market_badge.visible = false
		market_button.add_child(_market_badge)


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


func _connect_nav_buttons() -> void:
	for child in nav_bar.get_children():
		if child is Button:
			child.pressed.connect(_on_nav_pressed.bind(child.name.to_lower()))


func _connect_events() -> void:
	ascension_row.pressed.connect(open_ascension_select)
	EventBus.run_started.connect(refresh_all)
	EventBus.run_started.connect(_reset_ascension_prompts)
	Simulation.work_session_finished.connect(_on_work_session_finished)
	Simulation.round_statement_ready.connect(_on_bills_ready)
	EventBus.job_accepted.connect(func(_id): switch_tab("work"))
	# Work happens on the board, so starting the round goes straight there.
	EventBus.job_started.connect(func(_id): switch_tab("board"))
	EventBus.round_started.connect(refresh_all)
	EventBus.round_started.connect(_maybe_prompt_ascension)
	EventBus.reward_calculated.connect(func(_a): refresh_all())
	EventBus.perk_acquired.connect(func(_a): refresh_all())
	EventBus.upgrade_purchased.connect(func(_a): refresh_all())
	EventBus.run_ended.connect(func(_victory): refresh_all())
	# Burning and billing move cash mid-prompt. The HUD is the only place the
	# player watches it, so keep it honest without rebuilding every screen.
	EventBus.tokens_consumed.connect(func(_amount): _refresh_status_bar())
	EventBus.bill_due.connect(func(_type, _amount): _refresh_status_bar())
	EventBus.achievement_unlocked.connect(_on_achievement_unlocked)


## Awards can land in the middle of a burn, several at once, so the splash owns a
## queue of its own and this only has to hand them over.
func _on_achievement_unlocked(achievement_id: String) -> void:
	if _achievement_splash != null:
		_achievement_splash.enqueue(achievement_id)


func _on_nav_pressed(nav_key: String) -> void:
	UiSound.play("tap")
	_switch_tab(_tab_for_nav(nav_key))


## WORK is the home button: it opens the burn board while a round is live and
## the office otherwise, so the centre of the screen is always the run itself.
func _tab_for_nav(nav_key: String) -> String:
	match nav_key:
		"work":
			return "board" if Simulation.is_work_running() else "office"
		"more":
			return "menu"
		_:
			return nav_key


func switch_tab(tab_name: String) -> void:
	if TAB_TO_NAV.has(tab_name):
		_switch_tab(tab_name)
	else:
		_switch_tab(_tab_for_nav(tab_name))


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


func _switch_tab(tab_name: String) -> void:
	if not TAB_SCENES.has(tab_name):
		return
	_current_tab = tab_name
	for child in content_container.get_children():
		child.visible = false
	if not _screen_cache.has(tab_name):
		var screen: Control = TAB_SCENES[tab_name].instantiate()
		content_container.add_child(screen)
		_screen_cache[tab_name] = screen
	_screen_cache[tab_name].visible = true
	if _screen_cache[tab_name].has_method("refresh"):
		_screen_cache[tab_name].refresh()
	_update_backdrop()
	_update_nav_highlight()


func _update_backdrop() -> void:
	if not FeatureFlags.is_enabled("office_diorama_enabled"):
		scene_backdrop.visible = false
		scene_backdrop_next.visible = false
		scrim.visible = false
		return
	var stage: int = AssetCatalog.office_stage_for_build(Simulation.run_state.build)
	if stage != _backdrop_stage and not _stage_reveal_running:
		if _backdrop_stage < 0:
			_backdrop_stage = stage
			scene_backdrop.texture = _cropped_stage_texture(AssetCatalog.office_stage(stage))
		else:
			_reveal_stage(stage)
	scene_backdrop.visible = scene_backdrop.texture != null
	scrim.visible = scene_backdrop.visible
	var base: Color = UiThemeBuilder.color("bg")
	var alpha: float = float(BACKDROP_SCRIM.get(_current_tab, BACKDROP_SCRIM_DEFAULT))
	scrim.color = Color(base.r, base.g, base.b, alpha)


## Buying something that changes the room is the reward, so the UI steps out of
## the way, the new stage fades in, and then the chrome comes back.
func _reveal_stage(stage: int) -> void:
	_stage_reveal_running = true
	_backdrop_stage = stage
	scene_backdrop_next.texture = _cropped_stage_texture(AssetCatalog.office_stage(stage))
	scene_backdrop_next.visible = scene_backdrop_next.texture != null
	var base: Color = UiThemeBuilder.color("bg")
	var tween: Tween = create_tween()
	tween.tween_property(vbox, "modulate:a", 0.0, 0.22)
	tween.parallel().tween_property(scrim, "color", Color(base.r, base.g, base.b, 0.05), 0.22)
	tween.tween_property(scene_backdrop_next, "modulate:a", 1.0, 0.5)
	tween.tween_interval(0.5)
	tween.tween_property(vbox, "modulate:a", 1.0, 0.28)
	tween.tween_callback(_finish_stage_reveal)


func _finish_stage_reveal() -> void:
	scene_backdrop.texture = scene_backdrop_next.texture
	scene_backdrop.visible = scene_backdrop.texture != null
	scene_backdrop_next.modulate.a = 0.0
	scene_backdrop_next.visible = false
	_stage_reveal_running = false
	_update_backdrop()


func _cropped_stage_texture(texture: Texture2D) -> Texture2D:
	# The authored stage images are full mock screens with a fake HUD baked
	# in (stat chips, objectives, START button). Crop to the room itself so
	# the only HUD on screen is the real one.
	if texture == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	var size: Vector2 = texture.get_size()
	atlas.region = Rect2(size.x * 0.24, size.y * 0.08, size.x * 0.56, size.y * 0.89)
	return atlas


func _update_nav_highlight() -> void:
	var active_nav: String = str(TAB_TO_NAV.get(_current_tab, ""))
	for child in nav_bar.get_children():
		if child is Button:
			var nav_key: String = child.name.to_lower()
			var active: bool = nav_key == active_nav
			child.disabled = false
			# Dim only the icon for inactive tabs; the whole button used to get
			# modulated too, which stacked with the grey font color and made
			# inactive labels nearly unreadable.
			child.modulate = Color.WHITE
			child.add_theme_color_override(
				"icon_normal_color",
				Color.WHITE if active else Color(0.6, 0.6, 0.68)
			)
			child.add_theme_color_override(
				"font_color",
				UiThemeBuilder.color("blue") if active else Color(0.92, 0.92, 0.95)
			)
			var style: StyleBox = UiThemeBuilder.nav_tab_style(active)
			child.add_theme_stylebox_override("normal", style)
			child.add_theme_stylebox_override("hover", UiThemeBuilder.nav_tab_style(active))
			child.add_theme_stylebox_override("pressed", UiThemeBuilder.nav_tab_style(true))
			child.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var work_button: Button = nav_bar.get_node_or_null("Work")
	if work_button != null:
		work_button.text = "BURN" if Simulation.is_work_running() else "WORK"


func _on_work_session_finished(result: Dictionary) -> void:
	if _current_tab == "board":
		_switch_tab("office")
	var summary: Dictionary = result.get("summary", {})
	if not summary.is_empty() and Simulation.phase != Simulation.Phase.RUN_END:
		# The debrief gets the stage to itself; the angel draft reopens when the
		# player hits Continue.
		_angel_investors.visible = false
		_round_debrief.show_summary(summary)
	refresh_all()


## Debrief → Bills → Angels, always in that order: the player reads what the
## work earned before what the round cost, and only meets the angels once the
## rent has actually cleared.
func _on_debrief_continue() -> void:
	if not _pending_statement.is_empty():
		var statement: Dictionary = _pending_statement
		_pending_statement = {}
		_bills_screen.show_statement(statement)
		refresh_all()
		return
	# The angel overlay was held back while the debrief was open.
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
	# A run that ended on the bills shows its verdict once the player has read
	# the statement.
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		_angel_investors.show_choices()
		_last_angel_phase = true
	refresh_all()


func refresh_all() -> void:
	_refresh_status_bar()
	_update_backdrop()
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
	# A rung's reward draft is presented before the next round starts, so the
	# prompt for the rung above it has to wait for a clear screen rather than for
	# the next `round.started`.
	if Simulation.phase == Simulation.Phase.ROUND_PREP:
		_maybe_prompt_ascension()
	_sync_overlay_input()


func _refresh_status_bar() -> void:
	var state := Simulation.run_state
	var cash: float = float(state.economy.get("cash", 0.0))
	var token_rate: float = float(state.compute.get("token_rate", 0.0))
	var reputation: float = float(int(state.business.get("reputation", 0.0)))
	cash_chip.setup_value("cash", cash, "cash")
	cash_chip.set_value_color(UiThemeBuilder.semantic("money" if cash >= 0.0 else "danger"))
	token_chip.setup_value("tokens", token_rate, "tokens")
	rep_chip.setup_value("reputation", reputation, "plain")
	rep_chip.tooltip_text = _reputation_tooltip(reputation)
	_pulse_changed_chips(cash, token_rate, reputation)
	_refresh_round_chip()
	_refresh_ascension_tracker()


## The run's goal, on screen at all times rather than behind a tab the player has
## to already know about. It names the boss for this location, counts down the
## bars still to clear, says ASCENSION READY once they are, and turns into the
## Final Burn's progress once the contract is underway. Tapping it opens the
## overlay, which is the only place the commitment can actually be made.
func _refresh_ascension_tracker() -> void:
	var summary: Dictionary = Simulation.ascension_summary()
	var contract: Dictionary = Dictionary(summary.get("contract", {}))
	if contract.is_empty() or Simulation.phase == Simulation.Phase.RUN_END:
		ascension_row.visible = false
		ascension_bar.visible = false
		return
	ascension_row.visible = true
	var boss: String = str(contract.get("name", "Ascension Contract")).to_upper()
	var progress: Dictionary = Dictionary(summary.get("progress", {}))
	if bool(summary.get("committed", false)) and not progress.is_empty():
		var burned: float = float(progress.get("tokens_burned", 0.0))
		var total: float = maxf(1.0, float(progress.get("total_burn", 1.0)))
		ascension_row.text = "%s · FINAL BURN · %d PROMPT(S) LEFT" % [
			boss, int(progress.get("prompts_remaining", 0)),
		]
		ascension_row.add_theme_color_override("font_color", UiThemeBuilder.semantic("danger"))
		ascension_bar.visible = true
		ascension_bar.setup(
			boss, burned, total, "tokens",
			"%s / %s tokens" % [NumberFormat.format(burned), NumberFormat.format(total)]
		)
		return
	ascension_bar.visible = false
	if bool(summary.get("qualified", false)):
		ascension_row.text = "%s · ASCENSION READY" % boss
		ascension_row.add_theme_color_override("font_color", UiThemeBuilder.semantic("success"))
	else:
		ascension_row.text = "%s · %d / %d REQUIREMENTS" % [
			boss,
			int(summary.get("requirements_met", 0)),
			int(summary.get("requirements_total", 0)),
		]
		ascension_row.add_theme_color_override("font_color", UiThemeBuilder.semantic("warning"))


## The round the endgame stops being optional reading and starts being the
## thing the player is running out of time for.
const ASCENSION_WARNING_ROUND := 9
## The last round on which an unprompted player still has room to react before
## the year closes out into overtime.
const ASCENSION_PROMPT_ROUND := 11

## Opened at most once per run for each reason, because a screen that reopens
## every round is a screen the player learns to dismiss without reading. The
## always-visible tracker under the status bar carries the goal the rest of the
## time.
var _ascension_prompted_on_qualify: bool = false
var _ascension_prompted_late: bool = false


## A round has no prompt budget any more, so the chip counts up rather than down:
## "R3 · 5p" is the third round, five prompts spent on it so far. What limits a
## round is each contract's own deadline, which the job cards and board show.
func _refresh_round_chip() -> void:
	var state := Simulation.run_state
	var round_number: int = int(state.calendar.get("round", 1))
	var prompts_used: int = Simulation.prompts_used_this_round()
	var overtime: bool = Simulation.in_overtime()
	if overtime:
		round_chip.setup("deadline", "OT%d · %dp" % [
			int(state.statistics.get("overtime_rounds", 0)), prompts_used,
		])
	else:
		round_chip.setup("deadline", "R%d · %dp" % [round_number, prompts_used])
	var lines: PackedStringArray = []
	if overtime:
		lines.append("OVERTIME — round %d, %d past the end of the year" % [
			round_number, int(state.statistics.get("overtime_rounds", 0)),
		])
		lines.append("Rent and power climb every round until an Ascension Contract is completed.")
	else:
		lines.append("Round %d of %d" % [round_number, Simulation.ROUNDS_PER_RUN])
	lines.append("%d prompt(s) spent this round" % prompts_used)
	lines.append("A round runs until every contract you took resolves, then the bills land.")
	var urgency: String = _ascension_urgency_line(round_number, overtime)
	if urgency != "":
		lines.append(urgency)
	var slots: int = Simulation.job_slots()
	if slots > 1:
		lines.append("%d machines: %d contracts advance per prompt" % [slots, slots])
	else:
		lines.append("One machine: one contract advances per prompt. Buy another to work in parallel.")
	round_chip.tooltip_text = "\n".join(lines)
	round_chip.set_value_color(
		UiThemeBuilder.semantic("danger") if overtime
		else (UiThemeBuilder.semantic("warning") if urgency != "" else UiThemeBuilder.color("white"))
	)


## Says the quiet part out loud from round nine on: the year ending is not the
## finish line, and nothing here ends without a contract.
func _ascension_urgency_line(round_number: int, overtime: bool) -> String:
	if Simulation.ascension_active():
		return ""
	# A run that has already beaten the top rung is past being hurried.
	if Simulation.in_post_victory():
		return ""
	var boss: String = str(Simulation.ascension_boss_contract().get("name", "The Ascension Contract"))
	if overtime:
		return "%s is not committed. The Job Board is where you take it." % boss
	if round_number < ASCENSION_WARNING_ROUND:
		return ""
	return "%s not committed — %d round(s) left before overtime and rising costs." % [
		boss, Simulation.rounds_remaining(),
	]


## The endgame gets shown to the player rather than waited for: once the moment
## it becomes possible, and once more while there is still a round left to act
## on it. Both are one-time, and neither fires while a contract is underway.
func _reset_ascension_prompts() -> void:
	_ascension_prompted_on_qualify = false
	_ascension_prompted_late = false


func _maybe_prompt_ascension() -> void:
	if _title_active or Simulation.ascension_active():
		return
	if Simulation.phase == Simulation.Phase.RUN_END or Simulation.is_settling_victory():
		return
	# A draft or a report owns the screen until the player is done with it.
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		return
	if _round_debrief.visible or _bills_screen.visible or _run_end.visible:
		return
	var round_number: int = int(Simulation.run_state.calendar.get("round", 1))
	var qualified: bool = bool(Simulation.ascension_qualification().get("qualified", false))
	if qualified and not _ascension_prompted_on_qualify:
		_ascension_prompted_on_qualify = true
		open_ascension_select()
		return
	if round_number >= ASCENSION_PROMPT_ROUND and not _ascension_prompted_late:
		_ascension_prompted_late = true
		open_ascension_select()


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
