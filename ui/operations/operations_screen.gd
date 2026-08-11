extends Control

## The desk with nothing burning on it, printed on the laptop standing in the
## room.
##
## Accepting a contract lands on the burn board and the deck owns BOOST / CLOUD
## / START, so this is only what the operation looks like between sessions (or
## when the player peeks back at the room while one is running). It is drawn
## into the laptop screen the artwork painted rather than in a card floated over
## the picture, so the status of the business is something in the room.

const BREAKDOWN_SHEET := preload("res://ui/common/effect_breakdown_sheet.tscn")

var _laptop: LaptopScreen = null
var _breakdown_sheet: EffectBreakdownSheet = null
var _danger_vignette: DangerVignette = null


func _ready() -> void:
	add_to_group("ui_refresh")
	# The shell re-lays the room out whenever the operation moves premises, and
	# the laptop is a piece of that room's furniture.
	add_to_group("board_mounted")
	_danger_vignette = DangerVignette.mount(self)
	_laptop = LaptopScreen.new()
	_laptop.name = "Laptop"
	add_child(_laptop)
	_laptop.setup("desk")
	ConsoleNav.mount(_laptop, self)
	_breakdown_sheet = BREAKDOWN_SHEET.instantiate()
	add_child(_breakdown_sheet)
	relayout_on_board()
	Simulation.work_tick_completed.connect(refresh)
	Simulation.work_session_finished.connect(func(_result): refresh())
	EventBus.run_started.connect(refresh)
	EventBus.job_accepted.connect(func(_id): refresh())
	refresh()


## Anchors the console onto the blank screen of the laptop in the current room.
## Both rects are fractions of the window and this screen fills the work column,
## so the laptop rect is rebased onto the column it is mounted in.
func relayout_on_board() -> void:
	if _laptop == null:
		return
	var dwelling: String = _board_dwelling()
	var column: Rect2 = AssetCatalog.board_region(dwelling, "work_column")
	var screen: Rect2 = AssetCatalog.board_laptop_screen(dwelling)
	var rect: Rect2 = AssetCatalog.board_rect_in_region(column, screen)
	if rect.size.x <= 0.0:
		# A room with no laptop authored still has to show its status, so the
		# console takes the lower half of the column.
		rect = Rect2(0.18, 0.45, 0.64, 0.45)
	_laptop.anchor_left = rect.position.x
	_laptop.anchor_top = rect.position.y
	_laptop.anchor_right = rect.position.x + rect.size.x
	_laptop.anchor_bottom = rect.position.y + rect.size.y
	_laptop.offset_left = 0.0
	_laptop.offset_top = 0.0
	_laptop.offset_right = 0.0
	_laptop.offset_bottom = 0.0


func _board_dwelling() -> String:
	for node in get_tree().get_nodes_in_group("main_ui"):
		if node.has_method("board_dwelling"):
			return str(node.call("board_dwelling"))
	return AssetCatalog.dwelling_for_build(Simulation.run_state.build)


func refresh() -> void:
	if _laptop == null:
		return
	var queued: Array = Simulation.run_state.business.get("job_queue", [])
	var active_jobs: Array = Simulation.run_state.business.get("active_jobs", [])
	var working: bool = Simulation.is_work_running()
	var has_active: bool = working or active_jobs.size() > 0

	_danger_vignette.set_alarming(false)
	_refresh_readouts()
	ConsoleNav.refresh(_laptop)

	if has_active:
		_laptop.set_status("burn in progress", "%d contract(s) running. Work happens on the deck." % maxi(
			active_jobs.size(), queued.size()
		))
		_laptop.set_actions([{
			"headline": "OPEN BOARD", "value": "back to the deck", "pressed": _on_open_board,
		}])
		return

	if queued.size() > 0:
		_laptop.set_status("%d contract(s) ready" % queued.size(), "%s\nOpen the board and burn." % _queued_names(queued))
		_laptop.set_actions([{
			"headline": "OPEN BOARD", "value": "burn these contracts", "pressed": _on_open_board,
		}])
		return

	_laptop.set_status("desk is idle", "Take contracts from the job board. Accepting one opens the burn board.")
	_laptop.set_actions([{
		"headline": "CHOOSE A CONTRACT", "value": "job board", "pressed": _on_choose_contract,
	}])


func _queued_names(queued: Array) -> String:
	var names: PackedStringArray = []
	for job in queued:
		names.append(str(job.get("name", "Job")))
	return ", ".join(names)


func _refresh_readouts() -> void:
	var costs: Dictionary = Simulation.cost_forecast()
	_laptop.set_stat("rate", "token rate", NumberFormat.format_token_rate(
		float(Simulation.run_state.compute.get("token_rate", 0.0))
	), ConsoleStyle.PHOSPHOR)
	_laptop.set_stat("burned", "burned this round", NumberFormat.format_cash(
		float(costs.get("operating_so_far", 0.0))
	), ConsoleStyle.WARNING)
	_laptop.set_stat("due", "due at round end", NumberFormat.format_cash(
		float(costs.get("fixed_due", 0.0))
	), ConsoleStyle.DANGER)
	var round_number: int = int(Simulation.run_state.calendar.get("round", 1))
	var prompts_used: int = int(costs.get("prompts_used", 0))
	_laptop.set_meter(
		"round",
		"round %d/%d" % [round_number, Simulation.ROUNDS_PER_RUN],
		float(round_number) / float(maxi(1, Simulation.ROUNDS_PER_RUN)),
		"%d prompt(s)" % prompts_used
	)
	_wire_breakdown_taps()


## Wired once the rows exist, because the rows are created by the first refresh
## rather than by the scene.
func _wire_breakdown_taps() -> void:
	_wire_tap(_laptop.stat_row("rate"), func() -> void:
		_show_breakdown("Token Rate", "compute.token_rate", "")
	)
	for key in ["burned", "due", "round"]:
		_wire_tap(_laptop.stat_row(key), _show_cost_breakdown)


func _wire_tap(control: Control, handler: Callable) -> void:
	if control == null or control.has_meta("tap_wired"):
		return
	control.set_meta("tap_wired", true)
	control.mouse_filter = Control.MOUSE_FILTER_PASS
	var tap := TapGesture.new()
	control.gui_input.connect(func(event: InputEvent) -> void:
		if tap.feed(event):
			handler.call()
	)


func _show_cost_breakdown() -> void:
	if _breakdown_sheet == null:
		return
	var costs: Dictionary = Simulation.cost_forecast()
	var lines: PackedStringArray = []
	lines.append("Due when this round ends")
	lines.append("  Rent: %s" % NumberFormat.format_cash(float(costs.get("rent", 0.0))))
	if float(costs.get("recurring", 0.0)) > 0.0:
		lines.append("  Subscriptions: %s" % NumberFormat.format_cash(float(costs.get("recurring", 0.0))))
	if float(costs.get("cloud_bill", 0.0)) > 0.0:
		lines.append("  Cloud bill so far: %s" % NumberFormat.format_cash(float(costs.get("cloud_bill", 0.0))))
	lines.append("")
	lines.append("Paid as you work")
	lines.append("  Power: %s per prompt (%dW draw)" % [
		NumberFormat.format_cash(float(costs.get("power_per_prompt", 0.0))),
		int(costs.get("power_draw", 0.0)),
	])
	if float(costs.get("cloud_per_prompt", 0.0)) > 0.0:
		lines.append("  Cloud: %s per prompt" % NumberFormat.format_cash(float(costs.get("cloud_per_prompt", 0.0))))
	lines.append("  Burned so far this round: %s" % NumberFormat.format_cash(float(costs.get("operating_so_far", 0.0))))
	_breakdown_sheet.show_content("Running Costs", "\n".join(lines))


func _show_breakdown(title: String, target_path: String, chain_id: String) -> void:
	if _breakdown_sheet == null:
		return
	_breakdown_sheet.show_breakdown(title, target_path, chain_id)


func _on_choose_contract() -> void:
	get_tree().call_group("main_ui", "switch_tab", "jobs")


func _on_open_board() -> void:
	get_tree().call_group("main_ui", "switch_tab", "board")
