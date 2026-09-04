class_name BurnCabinet
extends Control

## The Burn Cabinet: the whole game on one machine. A layered chassis with the
## wide CRT in the middle, the telemetry rail beside it, the lever on the left,
## the command deck under the glass and the workflow backplane across the
## bottom. Every screen the game used to walk the player to — contracts, the
## market, the perk rack, the pipeline — is a tab on the central glass now, and
## the button under it relabels itself to whatever that tab commits: BURN,
## ACCEPT, PURCHASE, FIT.
##
## This scene is the coordinator: it builds the instruments, wires them up and
## keeps the deck honest. Geometry belongs to `CabinetLayout` — the coarse
## regions come from `presentation/cabinet_layout_profiles.json`, chosen by the
## window's shape, and the kit's 9-slice frames dress those regions; nothing
## reads geometry off a picture. The idle readings belong to `CabinetReadouts`,
## the paperwork and title to `CabinetFlow`, the batch in flight to
## `BurnDirector`.
##
## The tree, on the responsive shell:
##
##     BurnCabinet
##     ├── Backdrop
##     ├── ChassisArt (cover-crop, decorative only)
##     ├── SafeArea
##     │   ├── MaintenanceWall          (hidden until the maintenance camera)
##     │   ├── OperationGrid
##     │   │   ├── AbortRail            (AbortLever)
##     │   │   ├── MainColumn
##     │   │   │   ├── CrtFrame         (CabinetScreen in the bezel's opening)
##     │   │   │   ├── CommandDeck      (Override, CommitButton, Cooldown, LEDs)
##     │   │   │   └── WorkflowBackplane (WorkflowKeys header, ModuleDock grid)
##     │   │   └── TelemetryRail        (MultiplierDrum, HeatMeter, SystemStatus, BurnFeed)
##     │   └── MaintenanceLayer         (menu, system mounts, caption; hidden by default)
##     └── OverlayRoot
##
## Two camera states: `operation` (the grid fills the safe area) and
## `maintenance` (the grid zoomed out over the wall, the MaintenanceLayer up).
## System back walks: blocking paper → maintenance → a non-run tab → the run
## tab, and from the run tab opens maintenance; it never leaves the cabinet.
##
## This scene answers for the `main_ui` group: the router's calls, the
## round-end paperwork (debrief → bills → angels), the title screen in front of
## a cold start.

# The parts that are not instruments
var _layout_profile: CabinetLayout = null
var _readouts: CabinetReadouts = null
var _flow: CabinetFlow = null
var _director: BurnDirector = null

# Chassis
var _backdrop: ColorRect = null
var _chassis: TextureRect = null
var _safe_area: Control = null
var _grid: Control = null
var _abort_rail: Control = null
var _main_column: Control = null
var _crt_frame: CabinetFrame = null
var _command_deck: CabinetFrame = null
var _backplane: CabinetFrame = null
var _telemetry: CabinetFrame = null
var _telemetry_stack: BoxContainer = null
var _backplane_header: Control = null
var _dock_grid: Vector2i = Vector2i.ZERO
var _maintenance: MaintenanceLayer = null
var _settings_sheet: MaintenanceSettingsSheet = null
var _records_sheet: MaintenanceRecordsSheet = null
## Where the player was when maintenance opened, so Resume lands back there.
var _resume_tab: String = ""
## The install reveal in flight: `{id, old, new}` from the Market's
## `system_upgraded` until the camera is back in operation.
var _reveal: Dictionary = {}

# Mounted instruments
var _lever: AbortLever = null
var _workflow_keys: WorkflowKeys = null
var _screen: CabinetScreen = null
var _drum: MultiplierDrum = null
var _heat: HeatMeter = null
var _feed: BurnFeed = null
var _status: SystemStatus = null
var _override: DeckSwitch = null
var _cooldown: DeckSwitch = null
var _led_left: Panel = null
var _led_right: Panel = null
var _commit_button: CommitButton = null
var _dock: ModuleDock = null

# Tabs
var _tab_run: TabRun = null
var _tab_contracts: TabContracts = null
var _tab_modules: TabModules = null
var _tab_market: TabMarket = null
var _tab_perks: TabPerks = null

# Paper on top of the machine (owned by the flow)
var _overlay_root: Control = null
## The angel table lives on the flow now; playtests still reach it here.
var _angel_investors: Control:
	get:
		return _flow.angel_investors if _flow != null else null


func _ready() -> void:
	var resuming: bool = SceneRouter.booted
	SceneRouter.booted = true
	UiThemeBuilder.apply(self)
	add_to_group("main_ui")
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_profile = CabinetLayout.new()
	_build_instruments()
	_build_shell()
	_build_tabs()
	_build_director()
	_build_overlays()
	_connect_events()
	get_viewport().size_changed.connect(_layout)
	_layout()
	if resuming:
		_flow.title_active = false
	else:
		if ContentDatabase.jobs.is_empty():
			ContentDatabase.reload()
		if SaveManager.has_save():
			Simulation.load_saved_run()
		else:
			Simulation.start_run()
		_flow.ensure_title_screen()
	_screen.show_tab(_home_tab())
	refresh_all()
	_flow.sync_overlay_input()
	for entry in SceneRouter.take_pending_flow():
		_flow.replay_pending(entry)


# --- Building ----------------------------------------------------------------

## The instruments, unparented: each shell mounts them where its layout says.
func _build_instruments() -> void:
	_lever = AbortLever.new()
	_lever.name = "AbortLever"
	_lever.pulled.connect(_on_lever_pulled)

	_workflow_keys = WorkflowKeys.new()
	_workflow_keys.name = "WorkflowKeys"
	_workflow_keys.workflow_selected.connect(func(_index: int) -> void: refresh_all())

	_screen = CabinetScreen.new()
	_screen.name = "CabinetScreen"
	_screen.tab_changed.connect(_on_tab_changed)
	_screen.action_changed.connect(_refresh_deck)
	_screen.skip_pressed.connect(on_skip)
	_screen.maintenance_pressed.connect(enter_maintenance)

	_drum = MultiplierDrum.new()
	_drum.name = "MultiplierDrum"
	_heat = HeatMeter.new()
	_heat.name = "HeatMeter"
	_feed = BurnFeed.new()
	_feed.name = "BurnFeed"
	_status = SystemStatus.new()
	_status.name = "SystemStatus"

	_override = DeckSwitch.new()
	_override.name = "Override"
	_override.pressed.connect(_on_boost)
	_cooldown = DeckSwitch.new()
	_cooldown.name = "Cooldown"
	_cooldown.pressed.connect(_on_cool)
	_led_left = _led()
	_led_left.name = "LedLeft"
	_led_right = _led()
	_led_right.name = "LedRight"

	_commit_button = CommitButton.new()
	_commit_button.name = "CommitButton"
	# `committed`, not `pressed`: a danger action fires when its hold completes,
	# and the release after that must not fire it again.
	_commit_button.committed.connect(_on_commit_pressed)

	_dock = ModuleDock.new()
	_dock.name = "ModuleDock"
	_dock.bay_pressed.connect(_on_bay_pressed)
	_dock.bay_dropped.connect(_on_bay_dropped)

	_readouts = CabinetReadouts.new(_drum, _heat, _feed, _status, _screen)


## The responsive shell: backdrop, chassis art, then the safe area with the
## operation grid and its framed regions. Every region is a `CabinetFrame` (a
## kit 9-slice around a content Control) sized by the layout profile.
func _build_shell() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(0.015, 0.012, 0.010)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	_chassis = TextureRect.new()
	_chassis.name = "ChassisArt"
	_chassis.texture = AssetCatalog.cabinet_v2_texture("chassis")
	_chassis.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chassis.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_chassis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chassis.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chassis.visible = _chassis.texture != null
	add_child(_chassis)

	_safe_area = Control.new()
	_safe_area.name = "SafeArea"
	_safe_area.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_safe_area)
	_grid = Control.new()
	_grid.name = "OperationGrid"
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe_area.add_child(_grid)
	# The maintenance camera: its wall goes *behind* the grid so the machine
	# shrinks over it; the layer itself sits above the grid and eats input
	# while it is up.
	_maintenance = MaintenanceLayer.new(_layout_profile)
	_safe_area.add_child(_maintenance)
	_safe_area.add_child(_maintenance.wall())
	_safe_area.move_child(_maintenance.wall(), 0)
	_maintenance.menu_pressed.connect(_on_maintenance_menu)
	_maintenance.closed.connect(_on_maintenance_closed)

	_abort_rail = Control.new()
	_abort_rail.name = "AbortRail"
	_abort_rail.mouse_filter = Control.MOUSE_FILTER_PASS
	_grid.add_child(_abort_rail)
	_lever.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lever.set_tuning(_layout_profile.lever_tuning())
	_abort_rail.add_child(_lever)

	_main_column = Control.new()
	_main_column.name = "MainColumn"
	_main_column.mouse_filter = Control.MOUSE_FILTER_PASS
	_main_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid.add_child(_main_column)

	_crt_frame = CabinetFrame.new("crt_bezel", _layout_profile)
	_crt_frame.name = "CrtFrame"
	_main_column.add_child(_crt_frame)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crt_frame.content.add_child(_screen)

	_command_deck = CabinetFrame.new("deck_plate", _layout_profile)
	_command_deck.name = "CommandDeck"
	_main_column.add_child(_command_deck)
	for control in [_override, _led_left, _commit_button, _led_right, _cooldown]:
		_command_deck.content.add_child(control)
	_command_deck.content.resized.connect(_layout_deck)

	_backplane = CabinetFrame.new("backplane_rail", _layout_profile)
	_backplane.name = "WorkflowBackplane"
	_main_column.add_child(_backplane)
	_backplane_header = Control.new()
	_backplane_header.name = "Header"
	_backplane_header.mouse_filter = Control.MOUSE_FILTER_PASS
	_backplane.content.add_child(_backplane_header)
	_workflow_keys.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backplane_header.add_child(_workflow_keys)
	_dock.set_tuning(_layout_profile.dock_tuning())
	_backplane.content.add_child(_dock)
	_backplane.content.resized.connect(_layout_backplane)

	_telemetry = CabinetFrame.new("telemetry_frame", _layout_profile)
	_telemetry.name = "TelemetryRail"
	_grid.add_child(_telemetry)
	_telemetry_stack = BoxContainer.new()
	_telemetry_stack.name = "TelemetryStack"
	_telemetry_stack.vertical = true
	_telemetry_stack.mouse_filter = Control.MOUSE_FILTER_PASS
	_telemetry_stack.add_theme_constant_override("separation", 4)
	_telemetry_stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_telemetry.content.add_child(_telemetry_stack)
	# Each instrument sits in a plain slot Control, so the stack shares the rail
	# by ratio rather than by the instruments' own minimum sizes: a status
	# panel with nine rows must not push the feed off the frame.
	for entry in [[_drum, 1.0], [_heat, 0.8], [_status, 1.7], [_feed, 1.7]]:
		var instrument: Control = entry[0]
		var slot := Control.new()
		slot.name = "%sSlot" % instrument.name
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		slot.clip_contents = true
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.size_flags_stretch_ratio = float(entry[1])
		instrument.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slot.add_child(instrument)
		_telemetry_stack.add_child(slot)
	_feed.visibility_changed.connect(_on_feed_visibility)
	_on_feed_visibility()


## The feed's slot leaves the stack with it, so a collapsed feed takes no room.
func _on_feed_visibility() -> void:
	var slot: Node = _feed.get_parent()
	if slot is Control and slot != _telemetry_stack:
		(slot as Control).visible = _feed.visible


func _led() -> Panel:
	var led := Panel.new()
	led.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_led(led, CabinetStyle.GREY, false)
	return led


## A lamp dome: unlit is a smoked wash, lit is the colour with a small halo.
func _set_led(led: Panel, color: Color, lit: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color.r, color.g, color.b, 0.85) if lit else Color(0.0, 0.0, 0.0, 0.45)
	box.set_corner_radius_all(64)
	box.anti_aliasing = true
	box.border_color = Color(0.0, 0.0, 0.0, 0.7)
	box.set_border_width_all(1)
	if lit:
		box.shadow_color = Color(color.r, color.g, color.b, 0.45)
		box.shadow_size = 4
	led.add_theme_stylebox_override("panel", box)


func _build_tabs() -> void:
	_tab_run = TabRun.new()
	_tab_contracts = TabContracts.new()
	_tab_modules = TabModules.new()
	_tab_market = TabMarket.new()
	_tab_perks = TabPerks.new()
	for tab in [_tab_run, _tab_contracts, _tab_modules, _tab_market, _tab_perks]:
		tab.shell = self
		_screen.add_tab(tab)
	# A system bought at the Market is installed on the machine: the cabinet
	# plays that, so the tab never has to know there is a machine.
	_tab_market.system_upgraded.connect(_on_system_upgraded)


## The director plays the batch across the feed, drum, heat, dock and the RUN
## tab's strip; the cabinet latches and releases the deck around it.
func _build_director() -> void:
	_director = BurnDirector.new(_feed, _drum, _heat, _dock, _tab_run)
	_director.burn_started.connect(_on_burn_started)
	_director.burn_finished.connect(_on_burn_finished)
	_director.refresh_requested.connect(refresh_all)
	add_child(_director)


func _build_overlays() -> void:
	_overlay_root = Control.new()
	_overlay_root.name = "OverlayRoot"
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay_root)
	_flow = CabinetFlow.new(self, _overlay_root)
	add_child(_flow)
	_flow.build()
	_flow.refresh_requested.connect(refresh_all)
	_flow.title_started.connect(_on_title_start)
	_flow.burn_requested.connect(func() -> void: _director.request_burn())
	# The maintenance sheets are paper like any other: on the overlay root, in
	# the flow's back chain, hidden by the title.
	_settings_sheet = MaintenanceSettingsSheet.new()
	_records_sheet = MaintenanceRecordsSheet.new()
	for sheet in [_settings_sheet, _records_sheet]:
		_overlay_root.add_child(sheet)
		_flow.register_overlay(sheet)


func _connect_events() -> void:
	EventBus.run_started.connect(refresh_all)
	EventBus.round_started.connect(refresh_all)
	EventBus.reward_calculated.connect(func(_a): refresh_all())
	EventBus.perk_acquired.connect(func(_a): refresh_all())
	EventBus.upgrade_purchased.connect(func(_a): refresh_all())
	EventBus.hardware_sold.connect(func(_a): refresh_all())
	EventBus.run_ended.connect(func(_victory): refresh_all())
	EventBus.tokens_consumed.connect(func(_amount): _readouts.refresh_status())
	EventBus.bill_due.connect(func(_type, _amount): _readouts.refresh_status())
	# After the redraw hooks, so a report lands on a freshly drawn machine.
	_flow.connect_events()


# --- Layout ------------------------------------------------------------------

## The layout profile fits the safe area to the window and the coarse regions
## are placed against it; each region lays its own contents out from there.
func _layout() -> void:
	var view: Vector2 = size
	if view.x <= 0.0 or view.y <= 0.0:
		view = get_viewport().get_visible_rect().size
	_layout_profile.fit(view)
	var safe: Rect2 = _layout_profile.safe_rect()
	_safe_area.position = safe.position
	_safe_area.size = safe.size
	_fit_region(_abort_rail, "abort_rail")
	_fit_region(_crt_frame, "crt")
	_fit_region(_command_deck, "command_deck")
	_fit_region(_backplane, "backplane")
	_fit_region(_telemetry, "telemetry")
	_telemetry_stack.vertical = _layout_profile.telemetry_vertical()
	var grid := Vector2i(_layout_profile.dock_columns(), _layout_profile.dock_rows())
	if grid != _dock_grid:
		_dock_grid = grid
		_dock.set_grid(grid.x, grid.y)
	_layout_deck()
	_layout_backplane()
	if _maintenance != null:
		_maintenance.layout()


func _fit_region(control: Control, key: String) -> void:
	var rect: Rect2 = _layout_profile.region_rect_local(key)
	control.visible = rect.size.x > 0.0 and rect.size.y > 0.0
	control.position = rect.position
	control.size = rect.size


## The deck: the commit button centred at the housing's aspect, a switch either
## side with a lamp between, all sized from the deck's own height so the
## button clears the touch minimum at every supported window.
func _layout_deck() -> void:
	if _command_deck == null:
		return
	var area: Vector2 = _command_deck.content.size
	if area.x <= 0.0 or area.y <= 0.0:
		return
	var tuning: Dictionary = _layout_profile.deck_tuning()
	var pad: float = clampf(area.y * 0.05, 1.0, 6.0)
	var min_touch: float = _layout_profile.min_touch_px()
	var button_h: float = maxf(area.y - 2.0 * pad, minf(min_touch, area.y))
	var button_w: float = minf(area.x * float(tuning.get("commit_of_width", 0.34)), button_h * float(tuning.get("commit_aspect", 2.05)))
	button_w = maxf(button_w, min_touch)
	_commit_button.size = Vector2(button_w, button_h)
	_commit_button.position = Vector2((area.x - button_w) * 0.5, (area.y - button_h) * 0.5)
	var led: float = clampf(area.y * float(tuning.get("led_of_height", 0.22)), 8.0, 22.0)
	var gap: float = clampf(area.x * 0.012, 4.0, 16.0)
	var switch_w: float = minf(area.x * float(tuning.get("switch_of_width", 0.2)), (area.x - button_w) * 0.5 - 2.0 * gap - led - gap)
	var switch_h: float = area.y - 2.0 * pad
	_led_left.size = Vector2(led, led)
	_led_left.position = Vector2(_commit_button.position.x - gap - led, (area.y - led) * 0.5)
	_led_right.size = Vector2(led, led)
	_led_right.position = Vector2(_commit_button.position.x + button_w + gap, (area.y - led) * 0.5)
	_override.size = Vector2(switch_w, switch_h)
	_override.position = Vector2(_led_left.position.x - gap - switch_w, pad)
	_cooldown.size = Vector2(switch_w, switch_h)
	_cooldown.position = Vector2(_led_right.position.x + led + gap, pad)
	_override.visible = switch_w >= 40.0
	_cooldown.visible = switch_w >= 40.0


## The backplane: the workflow header along the top, the dock grid under it.
func _layout_backplane() -> void:
	if _backplane == null:
		return
	var area: Vector2 = _backplane.content.size
	if area.x <= 0.0 or area.y <= 0.0:
		return
	var tuning: Dictionary = _layout_profile.dock_tuning()
	var header_h: float = clampf(
		area.y * float(tuning.get("header_of_height", 0.18)),
		float(tuning.get("header_min_px", 20)),
		float(tuning.get("header_max_px", 34))
	)
	var gap: float = clampf(area.y * 0.03, 2.0, 8.0)
	_backplane_header.position = Vector2.ZERO
	_backplane_header.size = Vector2(area.x, header_h)
	_dock.position = Vector2(0.0, header_h + gap)
	_dock.size = Vector2(area.x, maxf(1.0, area.y - header_h - gap))


## Which layout profile the shell is on: wide, compact or tablet.
func layout_profile_name() -> String:
	return _layout_profile.profile_name()


## The dock grid the shell is showing, columns by rows.
func dock_grid() -> Vector2i:
	return _dock.grid()


## The safe area the interactive regions are laid out in, in viewport pixels.
func safe_area_rect() -> Rect2:
	return _layout_profile.safe_rect()


# --- Shell API (main_ui) ------------------------------------------------------

func refresh_all() -> void:
	if not is_inside_tree():
		return
	_workflow_keys.refresh()
	_dock.refresh()
	_screen.refresh()
	if not _is_burning():
		_readouts.refresh_idle()
	_readouts.refresh_status()
	_refresh_deck()
	# The mounts and the generation stencil follow the run's tiers, so a
	# system bought at the Market is on the wall the next time it is seen.
	if _maintenance != null:
		_maintenance.refresh()
	_flow.refresh()


## Every screen of the game is a tab of the glass; the old desk-tab and route
## names still land on the right one. Anything else goes to the router.
func switch_tab(tab_name: String) -> void:
	match tab_name:
		"work", "board", "office", "run":
			_screen.show_tab("run")
		"jobs", "contracts":
			_screen.show_tab("contracts")
		"market":
			_screen.show_tab("market")
		"build", "perks":
			_screen.show_tab("perks")
		"modules", "workflows":
			_screen.show_tab("modules")
		"more", "menu", "maintenance":
			enter_maintenance()
		_:
			if not SceneRouter.goto(tab_name):
				_screen.show_tab("run")
	refresh_all()


## Which screen the central glass is showing: run, contracts, modules, market, perks.
func current_tab() -> String:
	return _screen.active_key()


## System back, and `ui_cancel`: blocking paper closes; maintenance resumes; a
## tab that is not the run comes home to it; the run tab opens maintenance.
## The cabinet never hands back to the router's lobby.
func handle_system_back() -> void:
	if _flow.title_active:
		return
	if _flow.close_top_overlay():
		return
	if is_maintenance():
		exit_maintenance()
		return
	if _screen.active_key() != "run":
		_screen.show_tab("run")
		refresh_all()
		return
	enter_maintenance()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	if _flow.title_active or SceneRouter.investor_busy():
		return
	handle_system_back()
	get_viewport().set_input_as_handled()


# --- Camera: operation / maintenance ------------------------------------------

## "operation" while the machine fills the safe area, "maintenance" while it is
## zoomed out over the wall with the menu and the system mounts up.
func camera_state() -> String:
	return "maintenance" if is_maintenance() else "operation"


func is_maintenance() -> bool:
	return _maintenance != null and _maintenance.is_open()


func maintenance_layer() -> MaintenanceLayer:
	return _maintenance


## Zooms out to the maintenance view. A no-op under the title, mid-transition,
## or while paper is up (close that first).
func enter_maintenance() -> void:
	if _maintenance == null or _flow.title_active or is_maintenance() or _maintenance.is_transitioning():
		return
	_commit_button.release_focus()
	_resume_tab = _screen.active_key()
	_maintenance.open(_grid)


## Back to operation, on whatever tab the player left.
func exit_maintenance() -> void:
	if _maintenance == null or not is_maintenance():
		return
	_maintenance.close()


func _on_maintenance_closed() -> void:
	if _resume_tab != "" and _screen.has_tab(_resume_tab) and _screen.active_key() != _resume_tab:
		_screen.show_tab(_resume_tab)
	_resume_tab = ""
	var revealed: Dictionary = _reveal
	_reveal = {}
	# A close during the opening move leaves the reveal's one-shot armed.
	if _maintenance.opened.is_connected(_start_reveal):
		_maintenance.opened.disconnect(_start_reveal)
	refresh_all()
	if not revealed.is_empty():
		# The generation is ambient: it is said once on the glass, and the
		# next reading of the round line takes the hint back. No number moves.
		var generation: Dictionary = Simulation.cabinet_generation()
		_screen.set_hint("GEN %d · %s" % [int(generation.get("index", 0)) + 1, str(generation.get("name", ""))], CabinetStyle.AMBER)


# --- Install reveal ----------------------------------------------------------

## The Market sold a tier. The save is already on disk (the simulation
## autosaves inside `upgrade_cabinet_system`, before the tab emits); what is
## left is the spectacle: lock the deck, zoom out to maintenance wearing the
## old part, swap it with the flicker once the camera has settled, and come
## back to the Market on the same shelf, row and scroll. Any press on the
## layer, `skip_install`, or system back jumps to the end; reduced motion
## crossfades. Under the title or mid-move there is no reveal — the shelf and
## the mounts have already refreshed.
func _on_system_upgraded(system_id: String, old_tier: int, new_tier: int) -> void:
	if _maintenance == null or _flow.title_active or _is_burning():
		return
	if not _reveal.is_empty() or _maintenance.is_transitioning():
		# A second sale during a reveal: the mounts already show it; the
		# camera is not restarted for it.
		return
	_reveal = {"id": system_id, "old": old_tier, "new": new_tier}
	if is_maintenance():
		_start_reveal()
		return
	_maintenance.hold_tier(system_id, old_tier)
	_maintenance.opened.connect(_start_reveal, CONNECT_ONE_SHOT)
	enter_maintenance()
	if not is_maintenance():
		# The camera would not open (paper up, say): no reveal, nothing held.
		if _maintenance.opened.is_connected(_start_reveal):
			_maintenance.opened.disconnect(_start_reveal)
		_reveal = {}
		_maintenance.refresh()


func _start_reveal() -> void:
	if _reveal.is_empty() or _maintenance == null or not is_maintenance():
		_reveal = {}
		return
	_maintenance.show_install(
		str(_reveal["id"]), int(_reveal["old"]), int(_reveal["new"]), _on_reveal_done
	)


func _on_reveal_done() -> void:
	# `_reveal` is cleared when the camera lands, so the hint reads once.
	exit_maintenance()


## Whether an install reveal is running (camera moving or the tile swapping).
func is_revealing() -> bool:
	return not _reveal.is_empty()


func _on_maintenance_menu(action: String) -> void:
	match action:
		"resume":
			exit_maintenance()
		"settings":
			_settings_sheet.open()
		"help":
			_flow.open_help()
		"records":
			_records_sheet.open()
		"quit":
			save_and_quit()


## Save & Quit: the run is autosaved (it already is after every decision, but
## the player asked, so it is written now) and the cabinet's own title comes
## down over the machine. Never an OS quit: the web build has nowhere to go.
func save_and_quit() -> void:
	if Simulation.phase != Simulation.Phase.RUN_END:
		Simulation.autosave_now()
	if is_maintenance():
		_maintenance.close()
	_flow.open_title()


func open_title() -> void:
	_flow.open_title()


func dismiss_title() -> void:
	_flow.dismiss_title()


func open_help() -> void:
	_flow.open_help()


## The records sheet (career figures, unlocks, trophies) as paper over whatever
## is up — the title asks for it the same way it asks for help.
func open_records() -> void:
	if _records_sheet != null:
		_records_sheet.open()


func open_burn_lab() -> void:
	_flow.open_burn_lab()


func replay_work_session(result: Dictionary) -> void:
	_flow.replay_work_session(result)


func replay_statement(statement: Dictionary) -> void:
	_flow.replay_statement(statement)


func mount_overlay(control: Control) -> void:
	_flow.mount_overlay(control)


func sync_overlay_input() -> void:
	_flow.sync_overlay_input()


func investor_says(trigger: String, context: Dictionary = {}) -> void:
	SceneRouter.investor_says(trigger, context)


func open_investor_terms() -> void:
	SceneRouter.investor_says("terms")


## The old room's zoom, kept under its old names: the cabinet's one "room" is
## the maintenance view. Any key is that view.
func focus_room(_key: String, _target_rect: Rect2 = Rect2()) -> void:
	enter_maintenance()


func focus_control(_key: String, _control: Control) -> void:
	enter_maintenance()


func clear_room_focus() -> void:
	exit_maintenance()


func room_focused_on(_key: String) -> bool:
	return is_maintenance()


func board_dwelling() -> String:
	return str(Simulation.run_state.build.get("dwelling", AssetCatalog.DEFAULT_DWELLING))


func _on_title_start() -> void:
	_screen.show_tab(_home_tab())
	refresh_all()


## Where the glass opens: the bench when there is work, the wire when there is
## not. Between rounds with nothing taken, the contracts are the only move.
func _home_tab() -> String:
	if Simulation.is_work_running() or Simulation.run_state.has_pending_work():
		return "run"
	if Simulation.phase == Simulation.Phase.ROUND_PREP:
		return "contracts"
	return "run"


func _is_burning() -> bool:
	return _director != null and _director.is_burning()


# --- The deck: COMMIT, OVERRIDE, COOLDOWN, the LEDs -------------------------

## The button under the glass commits whatever the active tab is for.
func _refresh_deck() -> void:
	_screen.set_skippable(_director != null and _director.is_skippable())
	if _is_burning():
		_commit_button.set_busy(true)
		return
	_commit_button.set_busy(false)
	var key: String = _screen.active_key()
	if key == "run" or key == "":
		_refresh_run_deck()
	else:
		var tab: CabinetTab = _screen.active_tab()
		var action: Dictionary = CabinetTab.normalize_action(tab.primary_action() if tab != null else {})
		_commit_button.set_state(action)
		_set_led(_led_right, CabinetStyle.PHOSPHOR, bool(action.get("enabled", false)))
		_set_led(_led_left, CabinetStyle.RED, str(action.get("tone", "")) == CabinetTab.TONE_DANGER)
	_refresh_switches()
	_refresh_lever()


func _refresh_run_deck() -> void:
	var preview: Dictionary = Simulation.preview_next_burn()
	var can_open: bool = Simulation.can_start_work()
	var job: Dictionary = Simulation.focused_job()
	if job.is_empty():
		job = Simulation.queued_job_preview()
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		_commit_button.set_action("BURN", false, "AWAITING UPGRADE")
	elif Simulation.phase == Simulation.Phase.RUN_END:
		_commit_button.set_action("BURN", false, "RUN OVER")
	elif job.is_empty():
		_commit_button.set_action("BURN", false, CabinetTab.BLOCK_TAKE_CONTRACT)
	elif not (Simulation.can_burn() or can_open):
		_commit_button.set_action("BURN", false, _burn_blocker(preview))
	elif not preview.get("ok", false):
		_commit_button.set_action("BURN", false, _burn_blocker(preview))
	else:
		var ready: bool = JobSystem.is_ready(job)
		var costs: PackedStringArray = []
		var capacity: float = maxf(1.0, float(preview.get("heat_capacity", 100.0)))
		var before: float = float(preview.get("heat_before", 0.0)) / capacity
		var after: float = float(preview.get("heat_ratio_after", before))
		costs.append("HEAT %d%% → %d%%" % [int(round(before * 100.0)), int(round(after * 100.0))])
		if float(preview.get("cost", 0.0)) > 0.0:
			costs.append(NumberFormat.format_cash(float(preview.get("cost", 0.0))))
		if not Simulation.is_work_running():
			costs.append("OPENS THE ROUND")
		_commit_button.set_action("BURN AGAIN" if ready else "BURN", true, " · ".join(costs))
	var lethal: bool = _projected_lethal(preview)
	var warning: bool = _projected_warning(preview)
	_set_led(_led_left, CabinetStyle.RED if lethal else CabinetStyle.AMBER, lethal or warning)
	_set_led(_led_right, CabinetStyle.PHOSPHOR, _commit_button.is_enabled())


## Why BURN is off, in the deck's plain words. A machine too hot to burn says
## COOL FIRST; anything else prints the simulation's own reason.
func _burn_blocker(preview: Dictionary) -> String:
	var reason: String = str(preview.get("reason", "")).strip_edges()
	var state: String = str(preview.get("heat_state", ""))
	if state == HeatSystem.HEAT_FIRE or state == HeatSystem.HEAT_CATASTROPHE or reason.to_lower().contains("heat") or reason.to_lower().contains("hot"):
		return CabinetTab.BLOCK_COOL_FIRST
	return reason.to_upper() if reason != "" else "NOTHING TO BURN"


func _projected_lethal(preview: Dictionary) -> bool:
	var state: String = str(preview.get("heat_state", ""))
	return state == HeatSystem.HEAT_FIRE or state == HeatSystem.HEAT_CATASTROPHE \
		or bool(preview.get("crosses_catastrophe", preview.get("crosses_fire", false)))


func _projected_warning(preview: Dictionary) -> bool:
	return str(preview.get("heat_state", "")) in [
		HeatSystem.HEAT_THROTTLE, HeatSystem.HEAT_UNSTABLE, HeatSystem.HEAT_REDLINE, HeatSystem.HEAT_FIRE_RISK,
	]


func _refresh_switches() -> void:
	var working: bool = Simulation.is_work_running()
	var burning: bool = _is_burning()
	var armable: bool = (working or Simulation.can_start_work()) and Simulation.phase != Simulation.Phase.ANGEL_ROUND
	var boosted: bool = Simulation.boost_engaged() or Simulation.queued_boost
	_override.set_readings("OVERRIDE", "SAFE", "RISKY", 1 if boosted else 0, armable and not burning)
	_override.tooltip_text = "BOOST: one batch at ×1.35 output, for a slug of heat." if armable else "Boost arms once there is a contract on the bench."
	var can_cool: bool = working and not Simulation.focused_job().is_empty() and Simulation.work_policy() != WorkSession.POLICY_YOLO and not burning
	var hint: String = "READY"
	if can_cool:
		var cool: Dictionary = Simulation.preview_cool()
		if cool.get("ok", false):
			var delta: float = float(cool.get("total_heat", 0.0))
			hint = "NO CHANGE" if absf(delta) < 0.5 else "%+d HEAT" % int(round(delta))
	_cooldown.set_readings("COOLDOWN", "VENT", hint, 0 if can_cool else 1, can_cool)
	_cooldown.tooltip_text = "Spend the prompt venting heat instead of burning." if can_cool else "Cooling is a prompt spent mid-round."


func _refresh_lever() -> void:
	if _is_burning():
		_lever.set_armed("KILL" if Simulation.work_policy() != WorkSession.POLICY_YOLO else "")
		return
	var job: Dictionary = Simulation.focused_job()
	if Simulation.is_work_running() and not job.is_empty() and Simulation.work_policy() != WorkSession.POLICY_YOLO:
		_lever.set_armed("ABANDON")
	else:
		_lever.set_armed("")


func _on_tab_changed(key: String) -> void:
	_refresh_deck()
	if key == "modules":
		_tab_modules.set_dock_slot(_dock.selected_slot())


## The commit button. On RUN it burns; elsewhere it does what the tab says.
## While a batch is in flight it is latched and does nothing — skipping the
## playback is the CRT's SKIP key, not this button.
func _on_commit_pressed() -> void:
	if _is_burning() or _flow.title_active or is_maintenance() or not _commit_button.is_enabled():
		return
	# A tab's action already ran its own `pressed` callable when the button
	# committed (`set_state` carries it), and may have moved the glass to the
	# run tab on its way (ACCEPT does): the deck only has to read the new
	# state, never burn on top of it.
	if _commit_button.last_commit_delegated():
		_refresh_deck()
		return
	if _screen.active_key() == "run":
		_director.request_burn()
		return
	_refresh_deck()


# --- The batch in flight -----------------------------------------------------

## The director has taken the machine: latch the deck until it hands it back.
func _on_burn_started() -> void:
	_commit_button.set_busy(true)
	_commit_button.flash()
	_screen.set_skippable(_director.is_skippable())
	_refresh_lever()
	_override.set_readings("OVERRIDE", "SAFE", "RISKY", 1 if Simulation.boost_engaged() else 0, false)
	_cooldown.set_readings("COOLDOWN", "VENT", "BUSY", 1, false)


func _on_burn_finished(_ok: bool) -> void:
	_commit_button.set_busy(false)
	_screen.set_skippable(false)
	refresh_all()


# --- The dock ----------------------------------------------------------------

## A bay press: seats the armed cartridge, else swaps with the picked bay, else
## picks it. The MODULES tab follows whichever bay is picked.
func _on_bay_pressed(slot: int) -> void:
	if _is_burning():
		return
	var armed: String = _tab_modules.armed_module_id
	if armed != "":
		_tab_modules.seat(armed, slot)
		_dock.select_slot(slot)
		_tab_modules.set_dock_slot(slot)
		return
	var picked: int = _dock.selected_slot()
	if picked >= 0 and picked != slot and not Simulation.is_work_running():
		if Simulation.swap_slots(picked, slot):
			UiSound.play("accept")
			_dock.select_slot(-1)
			_tab_modules.set_dock_slot(-1)
			refresh_all()
			return
	UiSound.play("tap")
	_dock.select_slot(-1 if picked == slot else slot)
	_tab_modules.set_dock_slot(_dock.selected_slot())
	if _screen.active_key() != "modules" and _dock.selected_slot() >= 0:
		_screen.show_tab("modules")
	_refresh_deck()


func _on_bay_dropped(payload: Dictionary, slot: int) -> void:
	if _is_burning() or Simulation.is_work_running():
		UiSound.play("error")
		return
	match str(payload.get("kind", "")):
		"module":
			_tab_modules.seat(str(payload.get("module_id", "")), slot)
		"slot":
			var from: int = int(payload.get("slot_index", -1))
			if from >= 0 and from != slot and Simulation.swap_slots(from, slot):
				UiSound.play("accept")
				refresh_all()
	_dock.select_slot(slot)
	_tab_modules.set_dock_slot(slot)


func set_dock_armed(armed: bool) -> void:
	_dock.set_armed(armed)


# --- RUN tab callbacks -------------------------------------------------------

## The contract brief, on the flow's sheet.
func on_job_details() -> void:
	if _is_burning():
		return
	_flow.show_job_details()


## Moves the bench to the next contract in flight.
func on_focus_next() -> void:
	if _is_burning():
		return
	var lanes: Array = []
	for candidate in Array(Simulation.run_state.business.get("active_jobs", [])):
		if candidate is Dictionary and float(candidate.get("tokens_remaining", 0.0)) > 0.0 and int(candidate.get("prompts_remaining", 0)) >= 0:
			lanes.append(str(candidate.get("id", "")))
	if lanes.size() < 2:
		return
	var current: int = lanes.find(str(Simulation.focused_job().get("id", "")))
	var next_id: String = lanes[(current + 1) % lanes.size()]
	if Simulation.focus_job(next_id):
		UiSound.play("tap")
		refresh_all()


## The RUN tab's ROUTE key: hands the focused contract to the next workflow
## that can take it.
func on_cycle_workflow() -> void:
	if _is_burning():
		return
	var job: Dictionary = Simulation.focused_job()
	if job.is_empty():
		job = Simulation.queued_job_preview()
	if job.is_empty():
		return
	var matches: Array = Simulation.workflow_matches(job)
	if matches.size() < 2:
		return
	var assigned: String = str(job.get("workflow_id", ""))
	var current: int = 0
	for index in range(matches.size()):
		if str(Dictionary(matches[index]).get("workflow_id", "")) == assigned:
			current = index
	var next: Dictionary = matches[(current + 1) % matches.size()]
	if Simulation.assign_workflow(str(job.get("id", "")), str(next.get("workflow_id", ""))):
		UiSound.play("tap")
		refresh_all()


## The software says not to. Confirming sets YOLO and burns.
func on_yolo() -> void:
	if _is_burning():
		return
	_flow.show_yolo_sheet()


## Both ways a contract can end, on one sheet: ship as-is, or walk away.
func on_deliver() -> void:
	if _is_burning():
		return
	_flow.show_deliver_sheet()


func on_kill() -> void:
	_director.request_kill()
	_screen.set_skippable(_director.is_skippable())


## The CRT's SKIP: the playback jumps to its result. The commit stays busy
## until the batch has actually committed.
func on_skip() -> void:
	if not _director.is_skippable():
		return
	_director.request_skip()
	_screen.set_skippable(false)


# --- Lever, boost, cool ------------------------------------------------------

## A completed pull. Both armed actions are destructive, which is why the
## lever asked for a hold before it got here.
func _on_lever_pulled() -> void:
	if is_maintenance():
		return
	if _is_burning():
		_director.request_kill()
		_screen.set_skippable(_director.is_skippable())
		return
	var job: Dictionary = Simulation.focused_job()
	if Simulation.is_work_running() and not job.is_empty() and Simulation.work_policy() != WorkSession.POLICY_YOLO:
		on_deliver()


func _on_boost() -> void:
	if _is_burning() or _flow.title_active:
		return
	if Simulation.boost():
		UiSound.play("accept")
		refresh_all()
		return
	if Simulation.can_start_work():
		Simulation.set_queued_boost(not Simulation.queued_boost)
		UiSound.play("tap")
		refresh_all()


func _on_cool() -> void:
	if _is_burning() or _flow.title_active:
		return
	if not Simulation.is_work_running() or Simulation.focused_job().is_empty():
		UiSound.play("error")
		return
	var result: Dictionary = Simulation.cool_hardware()
	if result.get("ok", true):
		UiSound.play("tap")
		_feed.push("VENT %+d HEAT" % int(round(float(result.get("total_heat", 0.0)))), CabinetStyle.PHOSPHOR)
	refresh_all()
