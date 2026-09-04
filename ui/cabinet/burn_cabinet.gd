class_name BurnCabinet
extends Control

## The Burn Cabinet: the whole game on one machine. One painted chassis with the
## wide CRT in the middle, the live feed to its right, the lever on the left, the
## big red button under the glass and the module dock across the bottom. Every
## screen the game used to walk the player to — contracts, the market, the perk
## rack, the pipeline — is a tab on the central glass now, and the button under
## it relabels itself to whatever that tab commits: BURN, ACCEPT, PURCHASE, FIT.
##
## This scene answers for the `main_ui` group the way `ui/main.gd` did: the same
## router calls, the same round-end paperwork (debrief → bills → angels), the
## same title screen in front of a cold start.

const ANGEL_INVESTORS := preload("res://ui/screens/angel_investors.tscn")
const RUN_END := preload("res://ui/screens/run_end.tscn")
const ROUND_DEBRIEF := preload("res://ui/screens/session_summary.tscn")
const BILLS_SCREEN := preload("res://ui/screens/month_statement.tscn")
const BURN_LAB := preload("res://ui/debug/burn_lab.tscn")
const TITLE_SCREEN := preload("res://ui/title/title_screen.tscn")
const BurnSpectacle := preload("res://presentation/burn_spectacle.gd")

## The plate is authored at 16:9; anything else letterboxes around it.
const PLATE_ASPECT := 16.0 / 9.0
const HOLD_SLICE := 0.05
const DEADLINE_WARNING_PROMPTS := 3
const DEADLINE_DANGER_PROMPTS := 1

# Chassis
var _plate_texture: Texture2D = null
var _plate: TextureRect = null
var _plate_rect: Rect2 = Rect2()
var _backdrop: ColorRect = null
var _dock_panel: TextureRect = null

# Mounted instruments
var _lever: AbortLever = null
var _workflow_keys: WorkflowKeys = null
var _screen: CabinetScreen = null
var _drum: MultiplierDrum = null
var _heat: HeatMeter = null
var _next_action: CabinetWell = null
var _feed: BurnFeed = null
var _status: SystemStatus = null
var _override: DeckSwitch = null
var _cooldown: DeckSwitch = null
var _led_left: Panel = null
var _led_right: Panel = null
var _burn_button: BurnButton = null
var _dock: ModuleDock = null
var _round_line: Label = null
## Clipping frames over the painted wells, by region key.
var _wells: Dictionary = {}
## Node2D mounts for wells painted off square, by region key: a Control can
## turn but not shear, so the mount carries the skew that fits the glass.
var _mounts: Dictionary = {}

# Tabs
var _tab_run: TabRun = null
var _tab_contracts: TabContracts = null
var _tab_modules: TabModules = null
var _tab_market: TabMarket = null
var _tab_perks: TabPerks = null

# Paper on top of the machine
var _overlay_root: Control = null
var _sheet: ConsoleSheet = null
var _angel_investors: Control = null
var _run_end: Control = null
var _round_debrief: Control = null
var _bills_screen: Control = null
var _burn_lab: Control = null
var _help: HelpOverlay = null
var _title_screen: Control = null
var _title_active: bool = true
var _pending_statement: Dictionary = {}
var _last_angel_phase: bool = false
var _intro_call_shown: bool = false

# The batch in flight
var _burning: bool = false
var _kill_requested: bool = false
var _skip_requested: bool = false
var _stages_completed: int = 0
var _proc_depth: int = 0


func _ready() -> void:
	var resuming: bool = SceneRouter.booted
	SceneRouter.booted = true
	UiThemeBuilder.apply(self)
	add_to_group("main_ui")
	mouse_filter = Control.MOUSE_FILTER_STOP
	_plate_texture = AssetCatalog.cabinet_art()
	_build_chassis()
	_build_instruments()
	_build_tabs()
	_build_overlays()
	_connect_events()
	get_viewport().size_changed.connect(_layout)
	_layout()
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
	_screen.show_tab(_home_tab())
	refresh_all()
	_sync_overlay_input()
	for entry in SceneRouter.take_pending_flow():
		_replay_pending(entry)


# --- Building ----------------------------------------------------------------

func _build_chassis() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.015, 0.012, 0.010)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	_plate = TextureRect.new()
	_plate.texture = _plate_texture
	_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_plate.stretch_mode = TextureRect.STRETCH_SCALE
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)
	# The plate's own dock is painted in perspective; this front-on panel of
	# rectangular sockets is laid over it so the cartridges sit square.
	_dock_panel = TextureRect.new()
	_dock_panel.texture = AssetCatalog.cabinet_texture("dock_panel")
	_dock_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dock_panel.stretch_mode = TextureRect.STRETCH_SCALE
	_dock_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock_panel.visible = _dock_panel.texture != null
	add_child(_dock_panel)


func _build_instruments() -> void:
	_lever = AbortLever.new()
	_lever.pulled.connect(_on_lever_pulled)
	add_child(_lever)

	_workflow_keys = WorkflowKeys.new()
	_workflow_keys.workflow_selected.connect(func(_index: int) -> void: refresh_all())
	add_child(_workflow_keys)

	_screen = CabinetScreen.new()
	_screen.tab_changed.connect(_on_tab_changed)
	_screen.action_changed.connect(_refresh_deck)
	_well(_screen, "screen")

	_drum = MultiplierDrum.new()
	_well(_drum, "multiplier")
	_heat = HeatMeter.new()
	_well(_heat, "heat")
	_next_action = CabinetWell.new()
	_next_action.set_caption("NEXT ACTION")
	_well(_next_action, "next_action")
	_feed = BurnFeed.new()
	_well(_feed, "feed")
	_status = SystemStatus.new()
	_well(_status, "status")

	_override = DeckSwitch.new()
	_override.pressed.connect(_on_boost)
	add_child(_override)
	_cooldown = DeckSwitch.new()
	_cooldown.pressed.connect(_on_cool)
	add_child(_cooldown)
	_led_left = _led()
	add_child(_led_left)
	_led_right = _led()
	add_child(_led_right)

	_burn_button = BurnButton.new()
	_burn_button.pressed.connect(_on_primary)
	add_child(_burn_button)

	_dock = ModuleDock.new()
	_dock.bay_pressed.connect(_on_bay_pressed)
	_dock.bay_dropped.connect(_on_bay_dropped)
	add_child(_dock)

	_round_line = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.AMBER_DIM)
	_round_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_round_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_round_line)


## Seats a readout in a painted well. The well is a clipping frame cut to the
## glass, so a readout whose contents want more room than the glass gives is
## cropped at the bezel instead of growing out over the plate.
func _well(readout: Control, key: String) -> Control:
	var well := Control.new()
	well.name = "%sWell" % key.to_pascal_case()
	well.clip_contents = true
	well.mouse_filter = Control.MOUSE_FILTER_PASS
	readout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.add_child(readout)
	if AssetCatalog.cabinet_quad(key).size() == 3:
		var mount := Node2D.new()
		mount.name = "%sMount" % key.to_pascal_case()
		mount.add_child(well)
		add_child(mount)
		_mounts[key] = mount
	else:
		add_child(well)
	_wells[key] = well
	return well


func _led() -> Panel:
	var led := Panel.new()
	led.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_led(led, CabinetStyle.GREY, false)
	return led


## The plate paints the lamp domes; this is the light in them. Unlit is a smoked
## wash over the painted dome, lit is the colour with a small halo.
func _set_led(led: Panel, color: Color, lit: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color.r, color.g, color.b, 0.85) if lit else Color(0.0, 0.0, 0.0, 0.45)
	box.set_corner_radius_all(64)
	box.anti_aliasing = true
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
	_screen.add_door("MENU", func() -> void: SceneRouter.open_menu())


func _build_overlays() -> void:
	_overlay_root = Control.new()
	_overlay_root.name = "OverlayRoot"
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay_root)
	_sheet = ConsoleSheet.new()
	_overlay_root.add_child(_sheet)
	_angel_investors = ANGEL_INVESTORS.instantiate()
	_run_end = RUN_END.instantiate()
	_round_debrief = ROUND_DEBRIEF.instantiate()
	_bills_screen = BILLS_SCREEN.instantiate()
	_burn_lab = BURN_LAB.instantiate()
	_help = HelpOverlay.new()
	for overlay in [_angel_investors, _round_debrief, _bills_screen, _run_end, _burn_lab, _help]:
		if overlay == null:
			push_error("BurnCabinet: failed to instantiate an overlay")
			continue
		_overlay_root.add_child(overlay)
	_round_debrief.continue_pressed.connect(_on_debrief_continue)
	_bills_screen.continue_pressed.connect(_on_bills_continue)


func _connect_events() -> void:
	EventBus.run_started.connect(refresh_all)
	EventBus.run_started.connect(func() -> void: _intro_call_shown = false)
	Simulation.work_session_finished.connect(_on_work_session_finished)
	Simulation.round_statement_ready.connect(_on_bills_ready)
	EventBus.round_started.connect(refresh_all)
	EventBus.reward_calculated.connect(func(_a): refresh_all())
	EventBus.perk_acquired.connect(func(_a): refresh_all())
	EventBus.upgrade_purchased.connect(func(_a): refresh_all())
	EventBus.hardware_sold.connect(func(_a): refresh_all())
	EventBus.run_ended.connect(func(_victory): refresh_all())
	EventBus.run_ended.connect(_on_run_ended_call)
	EventBus.tokens_consumed.connect(func(_amount): _refresh_status())
	EventBus.bill_due.connect(func(_type, _amount): _refresh_status())


# --- Layout ------------------------------------------------------------------

## The plate is fitted to the window at its own aspect and everything is placed
## against it as a fraction, so the readouts stay in their wells at any size.
func _layout() -> void:
	var view: Vector2 = size
	if view.x <= 0.0 or view.y <= 0.0:
		view = get_viewport().get_visible_rect().size
	var plate_size: Vector2 = view
	if view.x / view.y > PLATE_ASPECT:
		plate_size = Vector2(view.y * PLATE_ASPECT, view.y)
	else:
		plate_size = Vector2(view.x, view.x / PLATE_ASPECT)
	_plate_rect = Rect2((view - plate_size) * 0.5, plate_size)
	_plate.position = _plate_rect.position
	_plate.size = _plate_rect.size
	_lever.layout(_plate_rect, _plate_texture)
	_place(_dock_panel, "dock_panel")
	_dock.layout(_plate_rect)
	_place(_workflow_keys, "workflow_keys")
	for key in _wells:
		var well: Control = _wells[key]
		if _mounts.has(key):
			_mount_well(well, _mounts[key], AssetCatalog.cabinet_quad(key))
		else:
			_place(well, key)
	_place(_override, "override_plate")
	_place(_cooldown, "cooldown_plate")
	_place(_led_left, "led_left")
	_place(_led_right, "led_right")
	_place(_burn_button, "burn_button")
	_place(_round_line, "header")
	# The header is painted; the round line sits in the strip under it.
	_round_line.position.y = _plate_rect.position.y + _plate_rect.size.y * 0.075
	_round_line.size.y = _plate_rect.size.y * 0.025
	_round_line.add_theme_font_size_override("font_size", clampi(int(_plate_rect.size.y * 0.016), 7, 12))


func _place(control: Control, key: String) -> void:
	var region: Rect2 = AssetCatalog.cabinet_region(key)
	if region.size.x <= 0.0:
		control.visible = false
		return
	CabinetStyle.fit(control, _plate_rect, region)


## Lays a well over glass the plate painted off square. `corners` are the
## glass's top-left, top-right and bottom-left as plate fractions; the well is
## sized to the glass's edges and the mount's transform maps its rectangle onto
## that parallelogram, so the top edge follows the bezel's top and the bottom
## edge follows the bottom instead of one corner lifting clear of the frame.
func _mount_well(well: Control, mount: Node2D, corners: PackedVector2Array) -> void:
	var top_left: Vector2 = _plate_rect.position + corners[0] * _plate_rect.size
	var top_right: Vector2 = _plate_rect.position + corners[1] * _plate_rect.size
	var bottom_left: Vector2 = _plate_rect.position + corners[2] * _plate_rect.size
	var across: Vector2 = top_right - top_left
	var down: Vector2 = bottom_left - top_left
	var width: float = maxf(across.length(), 1.0)
	var height: float = maxf(down.length(), 1.0)
	well.position = Vector2.ZERO
	well.size = Vector2(width, height)
	mount.transform = Transform2D(across / width, down / height, top_left)


# --- Shell API (main_ui) ------------------------------------------------------

func refresh_all() -> void:
	if not is_inside_tree():
		return
	_workflow_keys.refresh()
	_dock.refresh()
	_screen.refresh()
	_refresh_readouts()
	_refresh_status()
	_refresh_deck()
	if _title_active:
		_sync_overlay_input()
		return
	var report_open: bool = _round_debrief.visible or _bills_screen.visible
	var in_angel: bool = Simulation.phase == Simulation.Phase.ANGEL_ROUND
	if in_angel and not _last_angel_phase and not report_open:
		_angel_investors.show_choices()
	if not (in_angel and report_open):
		_last_angel_phase = in_angel
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


## The old desk had tabs by name and the venues had routes; both land on a tab of
## the glass now. Anything that is still a place of its own goes to the router.
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
		"more", "menu":
			SceneRouter.open_menu()
		_:
			if not SceneRouter.goto(tab_name):
				_screen.show_tab("run")
	refresh_all()


## Which screen the central glass is showing: run, contracts, modules, market, perks.
func current_tab() -> String:
	return _screen.active_key()


func handle_system_back() -> void:
	if _title_active:
		return
	for overlay in [_sheet, _help, _round_debrief, _bills_screen, _angel_investors, _run_end, _burn_lab]:
		if overlay != null and overlay.visible:
			if overlay.has_method("close"):
				overlay.close()
			elif overlay.has_method("hide_overlay"):
				overlay.hide_overlay()
			return
	if _screen.active_key() != "run":
		_screen.show_tab("run")
		refresh_all()
		return
	SceneRouter.open_menu()


func open_title() -> void:
	_ensure_title_screen()
	_title_active = true
	get_tree().call_group("flow_overlay", "hide_overlay")
	_title_screen.open()
	_sync_overlay_input()


func dismiss_title() -> void:
	if _title_screen != null:
		_title_screen.visible = false
	_title_active = false
	refresh_all()


func open_help() -> void:
	if _help != null:
		_help.open_help(false)


func open_burn_lab() -> void:
	if _burn_lab != null and FeatureFlags.is_enabled("burn_lab_enabled"):
		_burn_lab.open()


func replay_work_session(result: Dictionary) -> void:
	if not result.is_empty():
		_on_work_session_finished(result)


func replay_statement(statement: Dictionary) -> void:
	if not statement.is_empty():
		_on_bills_ready(statement)


func mount_overlay(control: Control) -> void:
	_overlay_root.add_child(control)


func sync_overlay_input() -> void:
	_sync_overlay_input()


func investor_says(trigger: String, context: Dictionary = {}) -> void:
	SceneRouter.investor_says(trigger, context)


func open_investor_terms() -> void:
	SceneRouter.investor_says("terms")


## The old room had a zoom; the cabinet has none. Kept so a caller that still
## asks for one gets a quiet answer rather than a missing method.
func focus_room(_key: String, _target_rect: Rect2 = Rect2()) -> void:
	pass


func focus_control(_key: String, _control: Control) -> void:
	pass


func clear_room_focus() -> void:
	pass


func room_focused_on(_key: String) -> bool:
	return false


func board_dwelling() -> String:
	return str(Simulation.run_state.build.get("dwelling", AssetCatalog.DEFAULT_DWELLING))


func _sync_overlay_input() -> void:
	var blocking := false
	for child in _overlay_root.get_children():
		if child is CanvasItem and child.visible:
			blocking = true
			break
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP if blocking else Control.MOUSE_FILTER_IGNORE


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


# --- Title -------------------------------------------------------------------

func _ensure_title_screen() -> void:
	if _title_screen != null:
		return
	_title_screen = TITLE_SCREEN.instantiate()
	add_child(_title_screen)
	move_child(_title_screen, _overlay_root.get_index())
	_title_screen.start_requested.connect(_on_title_start)


func _on_title_start() -> void:
	_title_active = false
	_screen.show_tab(_home_tab())
	refresh_all()
	_maybe_open_intro_call()
	if not MetaProgress.seen_onboarding() and _help != null:
		_help.open_help(true)


## Where the glass opens: the bench when there is work, the wire when there is
## not. Between rounds with nothing taken, the contracts are the only move.
func _home_tab() -> String:
	if Simulation.is_work_running() or Simulation.run_state.has_pending_work():
		return "run"
	if Simulation.phase == Simulation.Phase.ROUND_PREP:
		return "contracts"
	return "run"


# --- Readouts ----------------------------------------------------------------

func _refresh_readouts() -> void:
	if _burning:
		return
	var preview: Dictionary = Simulation.preview_next_burn()
	var boosted: bool = Simulation.boost_engaged() or Simulation.queued_boost
	var workflow: Dictionary = Simulation.active_workflow()
	if preview.get("ok", false):
		_drum.set_projection(
			float(preview.get("output_mult", 1.0)),
			float(preview.get("quality_mult", 1.0)),
			float(preview.get("thermal_mult", 1.0)),
			boosted
		)
	else:
		_drum.set_projection(
			float(workflow.get("output_mult", 1.0)),
			float(workflow.get("quality_mult", 1.0)),
			float(workflow.get("thermal_mult", 1.0)),
			boosted
		)
	var capacity: float = maxf(1.0, float(Simulation.run_state.compute.get("heat_capacity", 100.0)))
	var ratio: float = float(Simulation.run_state.compute.get("heat", 0.0)) / capacity
	var throttle: float = float(HeatSystem.heat_config().get("throttle_ratio", 0.8))
	var state: String = HeatSystem.heat_state(ratio, HeatSystem.work_tier(Simulation.run_state))
	var projected: float = float(preview.get("heat_ratio_after", -1.0)) if preview.get("ok", false) else -1.0
	_heat.set_heat(ratio, throttle, HeatSystem.heat_state_label(state), projected)
	var next: Dictionary = _next_action_line(preview)
	_next_action.set_body(str(next["text"]), next["color"])
	var round_number: int = int(Simulation.run_state.calendar.get("round", 1))
	_round_line.text = "ROUND %d · %s" % [round_number, _phase_word()]
	if not Simulation.is_work_running():
		_feed.set_live(false, "no run active" if Simulation.phase != Simulation.Phase.IN_ROUND else "between prompts")
	else:
		_feed.set_live(false, "prompt %d · ready" % (Simulation.prompts_used_this_round() + 1))
	_screen.set_hint("R%d · %s" % [round_number, _phase_word()])


func _phase_word() -> String:
	match Simulation.phase:
		Simulation.Phase.ROUND_PREP:
			return "PREP"
		Simulation.Phase.IN_ROUND:
			return "IN ROUND"
		Simulation.Phase.ROUND_END:
			return "ROUND END"
		Simulation.Phase.ANGEL_ROUND:
			return "ANGELS"
		Simulation.Phase.RUN_END:
			return "RUN OVER"
	return "IDLE"


## What the machine wants pressed next, printed in the small well under the heat.
func _next_action_line(preview: Dictionary) -> Dictionary:
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		return {"text": "PICK AN ANGEL OFFER", "color": CabinetStyle.AMBER}
	if Simulation.phase == Simulation.Phase.RUN_END:
		return {"text": "THE RUN IS OVER", "color": CabinetStyle.RED}
	var job: Dictionary = Simulation.focused_job()
	if job.is_empty():
		job = Simulation.queued_job_preview()
	if job.is_empty():
		if Simulation.phase == Simulation.Phase.ROUND_PREP:
			return {"text": "TAKE A CONTRACT\nOFF THE WIRE", "color": CabinetStyle.PHOSPHOR}
		return {"text": "NOTHING ON THE BENCH", "color": CabinetStyle.PHOSPHOR_DIM}
	if JobSystem.is_ready(job) or float(job.get("tokens_remaining", 0.0)) <= 0.0:
		return {"text": "PULL TO SHIP\nOR BURN AGAIN", "color": CabinetStyle.AMBER}
	if Simulation.filled_slot_count() <= 0:
		return {"text": "SEAT A MODULE\nIN THE DOCK", "color": CabinetStyle.AMBER}
	if preview.get("ok", false):
		var state: String = str(preview.get("heat_state", ""))
		if state == HeatSystem.HEAT_FIRE or state == HeatSystem.HEAT_CATASTROPHE or bool(preview.get("crosses_catastrophe", false)):
			return {"text": "COOL FIRST —\nNEXT BURN IS LETHAL", "color": CabinetStyle.RED}
		if state in [HeatSystem.HEAT_THROTTLE, HeatSystem.HEAT_UNSTABLE, HeatSystem.HEAT_REDLINE, HeatSystem.HEAT_FIRE_RISK]:
			return {"text": "PRESS BURN\nHEAT IS %s" % HeatSystem.heat_state_label(state).to_upper(), "color": CabinetStyle.AMBER}
		if not Simulation.is_work_running():
			return {"text": "PRESS BURN TO\nOPEN THE ROUND", "color": CabinetStyle.PHOSPHOR}
		return {"text": "PRESS BURN TO\nCOMMIT BATCH", "color": CabinetStyle.PHOSPHOR}
	return {"text": str(preview.get("reason", "—")).to_upper(), "color": CabinetStyle.PHOSPHOR_DIM}


## The narrow panel on the right: the ledger and the workflows' earned
## multipliers, which is what "system status" means on this machine.
func _refresh_status() -> void:
	var state := Simulation.run_state
	var round_number: int = int(state.calendar.get("round", 1))
	var deadline: int = round_number + Simulation.rounds_remaining() - 1
	var cash: float = float(state.economy.get("cash", 0.0))
	var entries: Array = [
		{"key": "CREDITS", "value": NumberFormat.format_cash(cash), "color": CabinetStyle.RED if cash < 0.0 else CabinetStyle.PHOSPHOR},
		{"key": "REP", "value": str(int(state.business.get("reputation", 0.0)))},
		{"key": "ROUND", "value": "%d/%d" % [round_number, deadline], "color": CabinetStyle.RED if Simulation.rounds_remaining() <= 2 else CabinetStyle.PHOSPHOR},
		# "/prompt" is too long for the narrow glass; the key says what the rate is per.
		{"key": "TOK/PROMPT", "value": NumberFormat.format_token_rate(float(state.compute.get("token_rate", 0.0))).replace("/prompt", "")},
	]
	var costs: Dictionary = Simulation.cost_forecast()
	entries.append({"key": "BILLS", "value": NumberFormat.format_cash(float(costs.get("fixed_due", 0.0))), "color": CabinetStyle.AMBER if float(costs.get("fixed_due", 0.0)) > cash else CabinetStyle.PHOSPHOR_DIM})
	entries.append({"key": "WORKFLOWS"})
	var active: int = Simulation.active_workflow_index()
	var index: int = 0
	for raw in Simulation.workflows():
		var workflow: Dictionary = raw
		entries.append({
			"key": "%d %s" % [index + 1, str(workflow.get("name", "")).left(6).to_upper()],
			"value": "×%.2f" % float(workflow.get("output_mult", 1.0)),
			"color": CabinetStyle.AMBER if index == active else CabinetStyle.PHOSPHOR,
		})
		index += 1
	_status.set_entries(entries)


# --- The deck: BURN, OVERRIDE, COOLDOWN, the LEDs ---------------------------

## The button under the glass commits whatever the active tab is for.
func _refresh_deck() -> void:
	if _burning:
		return
	var key: String = _screen.active_key()
	if key == "run" or key == "":
		_refresh_run_deck()
	else:
		var tab: CabinetTab = _screen.active_tab()
		var action: Dictionary = tab.primary_action() if tab != null else {}
		_burn_button.set_action(str(action.get("label", "—")), bool(action.get("enabled", false)), str(action.get("sub", "")))
		_set_led(_led_right, CabinetStyle.PHOSPHOR, bool(action.get("enabled", false)))
		_set_led(_led_left, CabinetStyle.RED, bool(action.get("danger", false)))
	_refresh_switches()
	_refresh_lever()


func _refresh_run_deck() -> void:
	var preview: Dictionary = Simulation.preview_next_burn()
	var can_open: bool = Simulation.can_start_work()
	var job: Dictionary = Simulation.focused_job()
	if job.is_empty():
		job = Simulation.queued_job_preview()
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		_burn_button.set_action("BURN", false, "awaiting upgrade")
	elif Simulation.phase == Simulation.Phase.RUN_END:
		_burn_button.set_action("BURN", false, "run over")
	elif job.is_empty():
		_burn_button.set_action("BURN", false, "take a contract first")
	elif not (Simulation.can_burn() or can_open):
		_burn_button.set_action("BURN", false, str(preview.get("reason", "nothing to burn")).to_lower())
	elif not preview.get("ok", false):
		_burn_button.set_action("BURN", false, str(preview.get("reason", "nothing to burn")).to_lower())
	else:
		var ready: bool = JobSystem.is_ready(job)
		var costs: PackedStringArray = []
		var capacity: float = maxf(1.0, float(preview.get("heat_capacity", 100.0)))
		var before: float = float(preview.get("heat_before", 0.0)) / capacity
		var after: float = float(preview.get("heat_ratio_after", before))
		costs.append("heat %d%% → %d%%" % [int(round(before * 100.0)), int(round(after * 100.0))])
		if float(preview.get("cost", 0.0)) > 0.0:
			costs.append(NumberFormat.format_cash(float(preview.get("cost", 0.0))))
		if not Simulation.is_work_running():
			costs.append("opens the round")
		_burn_button.set_action("BURN AGAIN" if ready else "BURN", true, " · ".join(costs))
	var lethal: bool = _projected_lethal(preview)
	var warning: bool = _projected_warning(preview)
	_set_led(_led_left, CabinetStyle.RED if lethal else CabinetStyle.AMBER, lethal or warning)
	_set_led(_led_right, CabinetStyle.PHOSPHOR, _burn_button.is_enabled())


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
	var armable: bool = (working or Simulation.can_start_work()) and Simulation.phase != Simulation.Phase.ANGEL_ROUND
	var boosted: bool = Simulation.boost_engaged() or Simulation.queued_boost
	_override.set_readings("OVERRIDE", "SAFE", "RISKY", 1 if boosted else 0, armable and not _burning)
	_override.tooltip_text = "BOOST: one batch at ×1.35 output, for a slug of heat." if armable else "Boost arms once there is a contract on the bench."
	var can_cool: bool = working and not Simulation.focused_job().is_empty() and Simulation.work_policy() != WorkSession.POLICY_YOLO and not _burning
	var hint: String = "READY"
	if can_cool:
		var cool: Dictionary = Simulation.preview_cool()
		if cool.get("ok", false):
			var delta: float = float(cool.get("total_heat", 0.0))
			hint = "NO CHANGE" if absf(delta) < 0.5 else "%+d HEAT" % int(round(delta))
	_cooldown.set_readings("COOLDOWN", "VENT", hint, 0 if can_cool else 1, can_cool)
	_cooldown.tooltip_text = "Spend the prompt venting heat instead of burning." if can_cool else "Cooling is a prompt spent mid-round."


func _refresh_lever() -> void:
	if _burning:
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


## The red button. On RUN it burns; elsewhere it does what the tab says.
func _on_primary() -> void:
	if _burning:
		_on_skip()
		return
	if _title_active or not _burn_button.is_enabled():
		return
	var key: String = _screen.active_key()
	if key == "run":
		_on_burn()
		return
	var tab: CabinetTab = _screen.active_tab()
	if tab == null:
		return
	var action: Dictionary = tab.primary_action()
	if bool(action.get("enabled", false)) and action.get("pressed") is Callable and Callable(action["pressed"]).is_valid():
		Callable(action["pressed"]).call()
	_refresh_deck()


# --- The dock ----------------------------------------------------------------

## A bay press: seats the armed cartridge, else swaps with the picked bay, else
## picks it. The MODULES tab follows whichever bay is picked.
func _on_bay_pressed(slot: int) -> void:
	if _burning:
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
	if _burning or Simulation.is_work_running():
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

func on_job_details() -> void:
	if _burning:
		return
	var job: Dictionary = Simulation.focused_job()
	if job.is_empty():
		job = Simulation.queued_job_preview()
	if job.is_empty():
		return
	var identity: Dictionary = JobPresentation.sector(job)
	var rows: Array = [{"text": str(job.get("description", ""))}]
	for rule in Array(job.get("board_rules", [])):
		if rule is Dictionary and str(rule.get("label", "")) != "":
			rows.append({"rule": str(rule["label"]), "text": str(rule.get("detail", ""))})
	for demand in Simulation.job_demands(job):
		rows.append({
			"rule": str(demand.get("name", "Demand")),
			"text": str(demand.get("note", "")),
			"role": "success" if bool(demand.get("met", false)) else "warning",
		})
	var prompts_left: int = maxi(0, int(job.get("prompts_remaining", 0)))
	var deadline_role: String = "neutral"
	if prompts_left <= DEADLINE_DANGER_PROMPTS:
		deadline_role = "danger"
	elif prompts_left <= DEADLINE_WARNING_PROMPTS:
		deadline_role = "warning"
	rows.append_array([
		{"stat": "Reward", "value": NumberFormat.format_cash(float(job.get("reward", 0.0))), "role": "money"},
		{"stat": "Tokens", "value": "%s BT" % NumberFormat.format(float(job.get("token_requirement", 0.0)))},
		{"stat": "Progress", "value": "%d%%" % _done_percent(job)},
		{
			"stat": "Quality",
			"value": "%s ×%.2f" % [
				JobPresentation.quality_against_bar(float(job.get("quality", 0.0)), float(job.get("quality_threshold", 0.0))),
				JobSystem.quality_payout_multiplier(float(job.get("quality", 0.0)), float(job.get("quality_threshold", 0.0))),
			],
			"role": "energy",
		},
		{"stat": "Prompts left", "value": str(prompts_left), "role": deadline_role},
		{"stat": "Known bugs", "value": str(int(job.get("known_bugs", 0)))},
	])
	_clear_sheet_handlers()
	_sheet.show_detail(str(job.get("name", "Contract")), "%s · %s" % [str(identity["label"]), str(identity["client"])], rows, [], "", identity["color"])


## Moves the bench to the next contract in flight.
func on_focus_next() -> void:
	if _burning:
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


func on_route_workflow() -> void:
	if _burning:
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


func on_yolo() -> void:
	if _burning:
		return
	_clear_sheet_handlers()
	_sheet.show_detail(
		"YOLO MODE",
		"The software says not to",
		[
			{"text": "Cooling disabled. Process kill disabled. Manual delivery disabled."},
			{"text": "The pipeline will run until contracts resolve, a depth completes, or the company ceases to exist."},
			{"stat": "Deep Burn", "value": "×1.25 score", "role": "energy"},
		],
		[],
		"DO IT",
		UiThemeBuilder.semantic("danger")
	)
	_sheet.action_confirmed.connect(func() -> void:
		Simulation.set_work_policy(WorkSession.POLICY_YOLO)
		if not Simulation.is_work_running() and Simulation.can_start_work():
			Simulation.start_work()
		refresh_all()
		if Simulation.can_burn():
			_on_burn()
	)


## Both ways a contract can end, on one sheet: ship as-is, or walk away.
func on_deliver() -> void:
	if _burning:
		return
	var job: Dictionary = Simulation.focused_job()
	if job.is_empty():
		return
	var done_pct: int = _done_percent(job)
	var complete: bool = float(job.get("tokens_remaining", 0.0)) <= 0.0
	var ship_preview: Dictionary = job.duplicate(true)
	if not complete:
		ship_preview["shipped_unfinished"] = true
		ship_preview["shipped_progress"] = float(done_pct) / 100.0
	var pay: float = JobSystem.projected_payout_multiplier(ship_preview)
	var projected_cash: float = float(job.get("reward", 0.0)) * pay
	if complete:
		projected_cash *= 1.0 + JobSystem.early_delivery_bonus(job)
	var rows: Array = [
		{"text": "The contract is finished. Hidden bugs are still rolled on delivery." if complete
			else "Shipping now delivers the contract as-is. Hidden bugs may surface and reputation can take a hit."},
		{"stat": "Progress", "value": "%d%%" % done_pct},
		{"stat": "Projected", "value": NumberFormat.format_cash(projected_cash), "role": "money"},
		{"stat": "Quality pay", "value": "×%.2f" % pay, "role": "energy"},
		{"stat": "Known bugs", "value": "%d  (−%d delivery quality)" % [int(job.get("known_bugs", 0)), int(JobSystem.known_bug_quality_penalty(job))]},
		{"stat": "Bug risk", "value": JobSystem.production_risk_class(job)},
		{"stat": "Prompts left", "value": str(int(job.get("prompts_remaining", 0)))},
	]
	var early_bonus: float = JobSystem.early_delivery_bonus(job)
	if complete and early_bonus > 0.0:
		rows.append({"stat": "Early bonus", "value": "+%d%%" % int(round(early_bonus * 100.0)), "role": "money"})
	rows.append({"text": "Abandoning costs no fee, but takes the reputation hit of a missed contract."})
	_clear_sheet_handlers()
	_sheet.show_detail(
		str(job.get("name", "Contract")),
		"Deliver or walk away",
		rows,
		[],
		"SHIP IT" if complete else "SHIP AT %d%%" % done_pct,
		UiThemeBuilder.semantic("money" if complete else "warning"),
		"ABANDON"
	)
	_sheet.action_confirmed.connect(func() -> void:
		Simulation.ship_focused_job()
		refresh_all()
	)
	_sheet.secondary_confirmed.connect(func() -> void:
		Simulation.abandon_focused_job()
		refresh_all()
	)


func on_kill() -> void:
	_on_kill()


func on_skip() -> void:
	_on_skip()


func _done_percent(job: Dictionary) -> int:
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var remaining: float = maxf(0.0, float(job.get("tokens_remaining", 0.0)))
	return int(round((1.0 - remaining / requirement) * 100.0))


func _clear_sheet_handlers() -> void:
	for signal_ref in [_sheet.action_confirmed, _sheet.secondary_confirmed]:
		for connection in signal_ref.get_connections():
			signal_ref.disconnect(connection["callable"])


# --- Lever, boost, cool ------------------------------------------------------

func _on_lever_pulled() -> void:
	if _burning:
		_on_kill()
		return
	var job: Dictionary = Simulation.focused_job()
	if Simulation.is_work_running() and not job.is_empty() and Simulation.work_policy() != WorkSession.POLICY_YOLO:
		on_deliver()


func _on_boost() -> void:
	if _burning or _title_active:
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
	if _burning or _title_active:
		return
	if not Simulation.is_work_running() or Simulation.focused_job().is_empty():
		UiSound.play("error")
		return
	var result: Dictionary = Simulation.cool_hardware()
	if result.get("ok", true):
		UiSound.play("tap")
		_feed.push("VENT %+d HEAT" % int(round(float(result.get("total_heat", 0.0)))), CabinetStyle.PHOSPHOR)
	refresh_all()


# --- Burning -----------------------------------------------------------------

func _on_burn() -> void:
	if _burning:
		return
	if not Simulation.is_work_running() and Simulation.can_start_work():
		Simulation.start_work()
		refresh_all()
	if not Simulation.can_burn():
		return
	var preview: Dictionary = Simulation.preview_burn()
	if not preview.get("ok", false):
		_feed.set_live(false, str(preview.get("reason", "nothing to burn")))
		return
	UiSound.play("burn")
	_burning = true
	_kill_requested = false
	_skip_requested = false
	_stages_completed = 0
	_proc_depth = 0
	_burn_button.flash()
	_burn_button.set_action("SKIP", true, "see the result")
	_tab_run.set_burning(true)
	_refresh_lever()
	_override.set_readings("OVERRIDE", "SAFE", "RISKY", 1 if Simulation.boost_engaged() else 0, false)
	_cooldown.set_readings("COOLDOWN", "VENT", "BUSY", 1, false)
	_feed.clear()
	_feed.set_live(true, "burn in progress", 1.0)
	await _animate_batch(preview)
	var committed_job: Dictionary = Simulation.focused_job()
	var before: Dictionary = _consequence_snapshot(committed_job)
	var stage_limit: int = (
		-1 if Simulation.work_policy() == WorkSession.POLICY_YOLO
		else (_stages_completed if _kill_requested else -1)
	)
	var result: Dictionary = Simulation.burn_batch(stage_limit)
	var after: Dictionary = _consequence_snapshot(committed_job)
	if result.get("ok", false):
		var committed_burn: Dictionary = Dictionary(result.get("burn", {}))
		await _animate_mastery(BurnSpectacle.compile_mastery(committed_burn))
		await _animate_consequences(BurnSpectacle.compile_consequences(before, after))
	_burning = false
	_tab_run.set_burning(false)
	_dock.light_step(-1)
	_feed.set_live(false, "batch committed" if result.get("ok", false) else "batch failed")
	refresh_all()
	if Simulation.work_policy() == WorkSession.POLICY_YOLO and Simulation.can_burn():
		call_deferred("_on_burn")


func _animate_batch(preview: Dictionary) -> void:
	var job: Dictionary = Simulation.focused_job()
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var burned_before: float = maxf(0.0, requirement - maxf(0.0, float(job.get("tokens_remaining", 0.0))))
	var beats: Array = preview.get("spectacle", [])
	if beats.is_empty() and FeatureFlags.is_enabled("burn_spectacle_enabled"):
		beats = BurnSpectacle.compile(preview, [])
	for beat in beats:
		if not beat is Dictionary:
			continue
		if _kill_requested:
			return
		_present_beat(beat, job, requirement, burned_before)
		if _skip_requested:
			_fast_forward(beats, beat, job, requirement, burned_before)
			_stages_completed = int(preview.get("stage_count", preview.get("stages", []).size()))
			return
		await _hold_beat(float(beat.get("hold", BurnSpectacle.QUIET_HOLD)))
		if _kill_requested:
			return
		if _skip_requested:
			_fast_forward(beats, beat, job, requirement, burned_before)
			_stages_completed = int(preview.get("stage_count", preview.get("stages", []).size()))
			return
		if bool(beat.get("closes_stage", false)):
			_stages_completed += 1


## One beat on the cabinet: the drum spins, the stage's bay and strip cell light,
## the feed prints a line, the heat bar nudges.
func _present_beat(beat: Dictionary, job: Dictionary, requirement: float, burned_before: float) -> void:
	var kind: String = str(beat.get("kind", BurnSpectacle.KIND_STAGE))
	var loud: bool = bool(beat.get("loud", false))
	var label: String = str(beat.get("label", "")).to_upper()
	var after: float = float(beat.get("multiplier_after", beat.get("progress_mult", 1.0)))
	var slot: int = int(beat.get("slot_index", -1))
	if slot >= 0:
		_dock.light_step(slot)
		_tab_run.light_step(slot)
	if kind == BurnSpectacle.KIND_FINAL:
		_drum.show_beat(after, label)
		_feed.push("%s  %s BT" % [label, NumberFormat.format(float(beat.get("tokens", 0.0)))], CabinetStyle.AMBER)
		_tab_run.show_beat_status(label, CabinetStyle.AMBER)
	elif kind == BurnSpectacle.KIND_MASTERY:
		_feed.push("WORKFLOW TRAINED  %s" % label, CabinetStyle.AMBER)
		_tab_run.show_beat_status("WORKFLOW TRAINED", CabinetStyle.AMBER)
	else:
		_drum.show_beat(after, label)
		_feed.push("%s  +%s" % [label, NumberFormat.format(float(beat.get("tokens_added", 0.0)))], CabinetStyle.AMBER if loud else CabinetStyle.PHOSPHOR)
		_tab_run.show_beat_status(label if loud else "BURNING", CabinetStyle.AMBER if loud else CabinetStyle.PHOSPHOR)
	_feed.set_live(true, "burn in progress", after)
	if not job.is_empty():
		var burned: float = burned_before + float(beat.get("tokens", 0.0))
		_feed.push("PROGRESS %s / %s" % [NumberFormat.format(minf(burned, requirement)), NumberFormat.format(requirement)], CabinetStyle.PHOSPHOR_DIM)
	if loud:
		UiSound.play("combo" if kind != BurnSpectacle.KIND_FINAL else "complete")
		_proc_depth += 1
	else:
		UiSound.play_proc(_proc_depth)
	_pulse_beat_heat(beat)


func _pulse_beat_heat(beat: Dictionary) -> void:
	if absf(float(beat.get("heat", 0.0))) <= 0.5:
		return
	var capacity: float = maxf(1.0, float(Simulation.run_state.compute.get("heat_capacity", 100.0)))
	var projected: float = maxf(0.0, float(Simulation.run_state.compute.get("heat", 0.0)) + float(beat.get("heat", 0.0))) / capacity
	var throttle: float = float(HeatSystem.heat_config().get("throttle_ratio", 0.8))
	var state: String = HeatSystem.heat_state(projected, HeatSystem.work_tier(Simulation.run_state))
	_heat.set_heat(projected, throttle, HeatSystem.heat_state_label(state))


func _consequence_snapshot(job: Dictionary) -> Dictionary:
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	var capacity: float = maxf(1.0, float(Simulation.run_state.compute.get("heat_capacity", 100.0)))
	var throttled: bool = false
	for entry in Simulation.run_state.compute.get("rate_modifiers", []):
		if entry is Dictionary and str(entry.get("source", "")) == "heat_throttle":
			throttled = true
	return {
		"requirement": float(job.get("token_requirement", 0.0)),
		"remaining": float(job.get("tokens_remaining", 0.0)),
		"known_bugs": int(job.get("known_bugs", 0)),
		"hidden_bugs": int(job.get("hidden_bugs", 0)),
		"risk": JobSystem.production_risk_class(job),
		"prompts": int(job.get("prompts_remaining", 0)),
		"heat_ratio": float(Simulation.run_state.compute.get("heat", 0.0)) / capacity,
		"throttled": throttled,
		"throttle_multiplier": float(heat_cfg.get("throttle_multiplier", 0.75)),
	}


func _animate_consequences(beats: Array) -> void:
	for raw in beats:
		if not raw is Dictionary:
			continue
		var beat: Dictionary = raw
		var role: String = str(beat.get("role", "warning"))
		var color: Color = CabinetStyle.RED if role == "danger" else (CabinetStyle.AMBER if role == "warning" else CabinetStyle.PHOSPHOR)
		_feed.push("%s  %s" % [str(beat.get("headline", "RESULT")).to_upper(), str(beat.get("detail", ""))], color)
		_tab_run.show_beat_status(str(beat.get("headline", "RESULT")), color)
		if role == "danger":
			UiSound.play("alarm")
		await get_tree().create_timer(float(beat.get("hold", 0.35))).timeout


func _animate_mastery(beats: Array) -> void:
	for raw in beats:
		if not raw is Dictionary or Dictionary(raw).is_empty():
			continue
		var beat: Dictionary = raw
		_present_beat(beat, {}, 1.0, 0.0)
		await get_tree().create_timer(float(beat.get("hold", BurnSpectacle.LOUD_HOLD))).timeout


func _fast_forward(beats: Array, current: Dictionary, job: Dictionary, requirement: float, burned_before: float) -> void:
	var last: Dictionary = current
	for beat in beats:
		if beat is Dictionary:
			last = beat
	if last != current:
		_present_beat(last, job, requirement, burned_before)


func _hold_beat(seconds: float) -> void:
	var remaining: float = maxf(0.0, seconds)
	while remaining > 0.0:
		if _kill_requested or _skip_requested:
			return
		var slice: float = minf(remaining, HOLD_SLICE)
		await get_tree().create_timer(slice).timeout
		remaining -= slice


func _on_kill() -> void:
	if not _burning or Simulation.work_policy() == WorkSession.POLICY_YOLO:
		return
	_kill_requested = true
	_feed.push("^C KILLED AFTER %d STAGE(S)" % _stages_completed, CabinetStyle.RED)
	_tab_run.show_beat_status("KILLED", CabinetStyle.RED)


func _on_skip() -> void:
	if not _burning or _kill_requested:
		return
	_skip_requested = true


# --- Round-end paperwork -----------------------------------------------------

func _on_work_session_finished(result: Dictionary) -> void:
	var summary: Dictionary = result.get("summary", {})
	if not summary.is_empty() and Simulation.phase != Simulation.Phase.RUN_END:
		_angel_investors.hide_overlay()
		_round_debrief.show_summary(summary)
	refresh_all()


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


func _clear_stage_for(verdict: Control) -> void:
	for overlay in get_tree().get_nodes_in_group("flow_overlay"):
		if overlay == verdict or SceneRouter.is_ancestor_of(overlay):
			continue
		if overlay is CanvasItem and overlay.visible and overlay.has_method("hide_overlay"):
			overlay.hide_overlay()


# --- The investor -----------------------------------------------------------

const ASCENSION_WARNING_ROUND := 9
const INVESTOR_FINAL_CALL_ROUNDS := 3


func _maybe_open_intro_call() -> void:
	if _intro_call_shown or _title_active:
		return
	if int(Simulation.run_state.calendar.get("round", 1)) > 1 or Simulation.prompts_used_this_round() > 0:
		_intro_call_shown = true
		return
	_intro_call_shown = true
	SceneRouter.investor_says("run_intro")


func _maybe_call_ascension_beat() -> void:
	if _title_active or SceneRouter.investor_busy():
		return
	var progress: Dictionary = Simulation.ascension_progress()
	if progress.is_empty():
		return
	var rounds_left: int = int(progress.get("rounds_remaining", 99))
	if rounds_left <= INVESTOR_FINAL_CALL_ROUNDS and not Simulation.run_state.investor_beat_heard("contract_final_call"):
		Simulation.run_state.mark_investor_beat("contract_final_call")
		investor_says("contract_final_call", {"rounds_remaining": rounds_left})
		return
	if float(progress.get("burn_ratio", 0.0)) >= 0.5 and not Simulation.run_state.investor_beat_heard("contract_halfway"):
		Simulation.run_state.mark_investor_beat("contract_halfway")
		investor_says("contract_halfway")


func _on_run_ended_call(victory: bool) -> void:
	if _title_active:
		return
	investor_says("ascension_complete" if victory else "run_lost")
