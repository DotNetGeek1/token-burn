extends Control

## Office home screen: the diorama fills the window (drawn by Main) and this
## screen keeps only a bottom control panel over it, so the room stays the
## centre of the screen. Boost/Cloud are armed before the round starts, not
## during it.

const BREAKDOWN_SHEET := preload("res://ui/common/effect_breakdown_sheet.tscn")
const RiskQuips := preload("res://ui/common/risk_quips.gd")

const STATUS_BOX_PATH := "Bottom/StatusPanel/Margin/StatusBox"

@onready var status_panel: PanelContainer = $Bottom/StatusPanel
@onready var status_title: Label = get_node("%s/StatusTitle" % STATUS_BOX_PATH)
@onready var status_body: Label = get_node("%s/StatusBody" % STATUS_BOX_PATH)
@onready var token_rate_label: Label = get_node("%s/InfoRow/TokenRateLabel" % STATUS_BOX_PATH)
@onready var reward_label: Label = get_node("%s/InfoRow/RewardLabel" % STATUS_BOX_PATH)
@onready var risk_label: Label = get_node("%s/RiskLabel" % STATUS_BOX_PATH)
@onready var costs_label: Label = get_node("%s/CostsLabel" % STATUS_BOX_PATH)
@onready var round_bar: ResourceBar = get_node("%s/RoundBar" % STATUS_BOX_PATH)
@onready var token_bar: ResourceBar = get_node("%s/TokenBar" % STATUS_BOX_PATH)
@onready var quality_bar: ResourceBar = get_node("%s/QualityBar" % STATUS_BOX_PATH)
@onready var deadline_bar: ResourceBar = get_node("%s/DeadlineBar" % STATUS_BOX_PATH)
@onready var heat_row: HBoxContainer = get_node("%s/HeatRow" % STATUS_BOX_PATH)
@onready var heat_gauge: HeatGauge = get_node("%s/HeatRow/HeatGauge" % STATUS_BOX_PATH)
@onready var heat_bar: ResourceBar = get_node("%s/HeatRow/HeatBar" % STATUS_BOX_PATH)
@onready var actions: HBoxContainer = get_node("%s/Actions" % STATUS_BOX_PATH)
@onready var choose_contract_button: GameButton = get_node("%s/ChooseContractButton" % STATUS_BOX_PATH)
@onready var start_work_button: GameButton = get_node("%s/Actions/StartWorkButton" % STATUS_BOX_PATH)
@onready var boost_button: GameButton = get_node("%s/Actions/BoostButton" % STATUS_BOX_PATH)
@onready var cloud_button: GameButton = get_node("%s/Actions/CloudButton" % STATUS_BOX_PATH)

var _breakdown_sheet: EffectBreakdownSheet = null
## Mirrors the board's alarm, so a rig cooking itself is visible from home.
var _danger_vignette: DangerVignette = null


func _ready() -> void:
	add_to_group("ui_refresh")
	_danger_vignette = DangerVignette.mount(self)
	_breakdown_sheet = BREAKDOWN_SHEET.instantiate()
	add_child(_breakdown_sheet)
	status_panel.add_theme_stylebox_override("panel", UiThemeBuilder.panel_style(
		UiThemeBuilder.color("bg_panel"), UiThemeBuilder.color("stroke_dim")
	))
	choose_contract_button.pressed.connect(func(): get_tree().call_group("main_ui", "switch_tab", "jobs"))
	start_work_button.pressed.connect(_on_start_work)
	boost_button.toggled.connect(func(pressed: bool): Simulation.set_queued_boost(pressed))
	cloud_button.toggled.connect(func(pressed: bool): Simulation.set_queued_cloud(pressed))
	Simulation.work_tick_completed.connect(refresh)
	Simulation.work_session_finished.connect(func(_result): refresh())
	EventBus.run_started.connect(refresh)
	EventBus.job_accepted.connect(func(_id): refresh())
	_wire_breakdown_taps()
	refresh()


func refresh() -> void:
	var queued: Array = Simulation.run_state.business.get("job_queue", [])
	var active_jobs: Array = Simulation.run_state.business.get("active_jobs", [])
	var working: bool = Simulation.is_work_running()
	var has_queue: bool = queued.size() > 0
	var has_active: bool = active_jobs.size() > 0
	var has_jobs: bool = has_queue or has_active

	token_bar.visible = has_jobs
	quality_bar.visible = has_jobs
	deadline_bar.visible = has_jobs
	heat_row.visible = has_jobs
	reward_label.visible = has_jobs
	actions.visible = has_jobs
	# With nothing queued the panel offers exactly one thing to do.
	choose_contract_button.visible = not has_jobs

	start_work_button.disabled = not Simulation.can_start_work() and not working
	if working:
		start_work_button.set_lines("BURN BOARD", "The round is under way")
	elif has_active:
		start_work_button.set_lines("RESUME WORK", "Contracts still open")
	else:
		start_work_button.set_lines("START WORK", "Work this round's contracts")
	# Armed here, they fire on the round's first batch. Once the board is open
	# it owns them, so they read as status rather than controls.
	var cloud_owned: bool = Simulation.cloud_enabled()
	boost_button.disabled = working
	cloud_button.disabled = working or not cloud_owned
	cloud_button.visible = FeatureFlags.is_enabled("cloud_compute_enabled")
	if working:
		boost_button.set_pressed_no_signal(Simulation.boost_engaged())
		cloud_button.set_pressed_no_signal(Simulation.cloud_engaged())
	else:
		boost_button.set_pressed_no_signal(Simulation.queued_boost)
		cloud_button.set_pressed_no_signal(Simulation.queued_cloud)
	# While the session runs these read as status, so the sub-line says what is
	# happening rather than what pressing would do.
	if working:
		boost_button.set_lines("BOOST", "ENGAGED" if Simulation.boost_engaged() else "idle")
		cloud_button.set_lines("CLOUD", "RENTED" if Simulation.cloud_engaged() else "idle")
	else:
		boost_button.set_lines("BOOST", "ARMED" if Simulation.queued_boost else "+35% / +12 heat")
		if not cloud_owned:
			cloud_button.set_lines("CLOUD", "LOCKED")
		else:
			cloud_button.set_lines("CLOUD", "ARMED" if Simulation.queued_cloud else "Rent capacity")

	_refresh_risk_line(has_queue and not working)
	_refresh_costs()
	_danger_vignette.set_alarming(has_jobs and _heat_ratio() >= HeatGauge.DANGER_RATIO)

	if has_active:
		_show_active_jobs(active_jobs)
	elif has_queue:
		_show_queued_jobs(queued)
	else:
		status_title.text = "No contracts taken"
		status_body.text = "Take contracts from the job board to fill this round, then start work."
		token_rate_label.text = "Token rate · %s" % NumberFormat.format_token_rate(float(Simulation.run_state.compute.get("token_rate", 0.0)))


func _heat_ratio() -> float:
	var capacity: float = float(Simulation.run_state.compute.get("heat_capacity", 100.0))
	return float(Simulation.run_state.compute.get("heat", 0.0)) / maxf(1.0, capacity)


## Repeats the job board's capacity warning here, so a round with more work than
## its deadlines allow is obvious before the player commits to START WORK.
func _refresh_risk_line(show_risk: bool) -> void:
	if not show_risk:
		risk_label.visible = false
		return
	var info: Dictionary = Simulation.queue_load_info()
	var warning: String = RiskQuips.warning(float(info.get("ratio", 0.0)), int(info.get("jobs", 0)))
	risk_label.text = warning
	risk_label.visible = warning != ""


## Running costs are two numbers the player needs at once: what this round has
## already burned through metered power, and the fixed lump waiting at the end of
## it. There is no projected total any more — a round is as long as its contracts
## need, so the only honest forecast is "this much is already owed".
func _refresh_costs() -> void:
	var costs: Dictionary = Simulation.cost_forecast()
	costs_label.text = "Running costs · %s burned · %s due at round end" % [
		NumberFormat.format_cash(float(costs.get("operating_so_far", 0.0))),
		NumberFormat.format_cash(float(costs.get("fixed_due", 0.0))),
	]
	var round_number: int = int(Simulation.run_state.calendar.get("round", 1))
	var prompts_used: int = int(costs.get("prompts_used", 0))
	round_bar.setup(
		"Round · tap costs for breakdown",
		float(mini(round_number, Simulation.ROUNDS_PER_RUN)),
		float(Simulation.ROUNDS_PER_RUN),
		"deadline",
		"round %d · %d prompt(s) spent" % [round_number, prompts_used]
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
	lines.append("")
	lines.append("Rent is the same whatever the round costs to work, so a long round")
	lines.append("only costs more in metered power. Bills land once every contract on")
	lines.append("this round's slate has resolved.")
	_breakdown_sheet.show_content("Running Costs", "\n".join(lines))


func _show_queued_jobs(queued: Array) -> void:
	status_title.text = "%d contract(s) ready" % queued.size()
	var names: PackedStringArray = []
	for job in queued:
		names.append(str(job.get("name", "Job")))
	status_body.text = ", ".join(names)
	_show_aggregate_bars(queued)
	token_rate_label.text = "Token rate · %s" % NumberFormat.format_token_rate(float(Simulation.run_state.compute.get("token_rate", 0.0)))


func _show_active_jobs(active_jobs: Array) -> void:
	var in_progress: Array = []
	var completed: int = 0
	var failed: int = 0
	var names: PackedStringArray = []
	for job in active_jobs:
		names.append(str(job.get("name", "Job")))
		if float(job.get("tokens_remaining", 0.0)) <= 0.0:
			completed += 1
		elif int(job.get("prompts_remaining", 0)) < 0:
			failed += 1
		else:
			in_progress.append(job)
	var working: bool = Simulation.is_work_running()
	status_title.text = "Processing %d contract(s)" % active_jobs.size() if working else "%d contract(s) in progress" % active_jobs.size()
	var status_parts: PackedStringArray = []
	if in_progress.size() > 0:
		status_parts.append("%d active" % in_progress.size())
	if completed > 0:
		status_parts.append("%d done" % completed)
	if failed > 0:
		status_parts.append("%d missed deadline" % failed)
	status_body.text = ", ".join(names)
	if status_parts.size() > 0:
		status_body.text += "\n" + ", ".join(status_parts)
	var bar_jobs: Array = in_progress if not in_progress.is_empty() else active_jobs
	_show_aggregate_bars(bar_jobs)
	token_rate_label.text = "Token rate · %s" % NumberFormat.format_token_rate(float(Simulation.run_state.compute.get("token_rate", 0.0)))


func _show_aggregate_bars(jobs: Array) -> void:
	var tokens_done: float = 0.0
	var tokens_total: float = 0.0
	var quality_total: float = 0.0
	var quality_threshold: float = 0.0
	var deadline_done: float = 0.0
	var deadline_total: float = 0.0
	var reward_total: float = 0.0
	for job in jobs:
		var requirement: float = float(job.get("token_requirement", 1.0))
		var remaining: float = float(job.get("tokens_remaining", requirement))
		tokens_done += requirement - remaining
		tokens_total += requirement
		quality_total += float(job.get("quality", 0.0))
		quality_threshold += float(job.get("quality_threshold", 0.0))
		# Contracts not started yet have no prompts_remaining: treat them as
		# untouched so the deadline bar does not read as fully consumed.
		var deadline_prompts: float = float(job.get("deadline_prompts", 1))
		deadline_done += deadline_prompts - float(job.get("prompts_remaining", deadline_prompts))
		deadline_total += deadline_prompts
		reward_total += float(job.get("reward", 0.0))
	var job_count: float = maxf(1.0, float(jobs.size()))
	token_bar.setup("Tokens", tokens_done, tokens_total, "tokens")
	quality_bar.setup("Quality · tap for breakdown", quality_total / job_count, quality_threshold / job_count, "quality")
	deadline_bar.setup("Deadline", deadline_done, deadline_total, "deadline")
	var heat: float = float(Simulation.run_state.compute.get("heat", 0.0))
	var heat_capacity: float = float(Simulation.run_state.compute.get("heat_capacity", 100.0))
	heat_bar.setup("Heat · tap for breakdown", heat, heat_capacity, "heat")
	heat_gauge.setup(heat, heat_capacity)
	reward_label.text = "Reward · %s" % NumberFormat.format_cash(reward_total)


func _wire_breakdown_taps() -> void:
	_make_tappable(token_rate_label, "Token Rate", "compute.token_rate", "")
	_make_tappable(reward_label, "Job Reward", "job.reward", "")
	_make_tappable(quality_bar, "Quality", "job.quality", _quality_chain_id())
	_make_tappable(heat_bar, "Heat", "compute.heat", "")
	_wire_tap(costs_label, _show_cost_breakdown)
	_wire_tap(round_bar, _show_cost_breakdown)


func _make_tappable(control: Control, title: String, target_path: String, chain_id: String) -> void:
	_wire_tap(control, func() -> void: _show_breakdown(title, target_path, chain_id))


func _wire_tap(control: Control, handler: Callable) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_PASS
	if control.custom_minimum_size.y < 44:
		control.custom_minimum_size.y = 44
	for child in control.get_children():
		_set_mouse_ignore_recursive(child)
	var tap := TapGesture.new()
	control.gui_input.connect(func(event: InputEvent) -> void:
		if tap.feed(event):
			handler.call()
	)


func _set_mouse_ignore_recursive(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_mouse_ignore_recursive(child)


func _show_breakdown(title: String, target_path: String, chain_id: String) -> void:
	if _breakdown_sheet == null:
		return
	_breakdown_sheet.show_breakdown(title, target_path, chain_id)


func _primary_job_id() -> String:
	var active_jobs: Array = Simulation.run_state.business.get("active_jobs", [])
	if not active_jobs.is_empty():
		return str(active_jobs[0].get("id", ""))
	var queued: Array = Simulation.run_state.business.get("job_queue", [])
	if not queued.is_empty():
		return str(queued[0].get("id", ""))
	return ""


func _quality_chain_id() -> String:
	var job_id: String = _primary_job_id()
	return "quality.%s" % job_id if job_id != "" else ""


func _on_start_work() -> void:
	# A session already open just needs the board bringing forward.
	if Simulation.is_work_running():
		get_tree().call_group("main_ui", "switch_tab", "board")
		return
	if not Simulation.can_start_work():
		return
	start_work_button.disabled = true
	Simulation.start_work()
