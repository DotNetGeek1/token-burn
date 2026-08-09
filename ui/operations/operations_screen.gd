extends Control

## Idle desk status. Accepting a contract lands on the burn board, and the deck
## owns BOOST / CLOUD / START — this screen is only what the office looks like
## when there is nothing to burn yet (or when the player peeks back at the room
## while a session is already running).

const BREAKDOWN_SHEET := preload("res://ui/common/effect_breakdown_sheet.tscn")

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
	start_work_button.pressed.connect(_on_open_board)
	# Pre-burn arming and the session start live on the deck now.
	boost_button.visible = false
	cloud_button.visible = false
	token_bar.visible = false
	quality_bar.visible = false
	deadline_bar.visible = false
	heat_row.visible = false
	reward_label.visible = false
	risk_label.visible = false
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

	_danger_vignette.set_alarming(false)
	_refresh_costs()
	token_rate_label.text = "Token rate · %s" % NumberFormat.format_token_rate(
		float(Simulation.run_state.compute.get("token_rate", 0.0))
	)

	if working or has_active:
		status_title.text = "On the burn board"
		status_body.text = "%d contract(s) in progress. Work happens on the deck." % maxi(
			active_jobs.size(), queued.size()
		)
		choose_contract_button.visible = false
		actions.visible = true
		start_work_button.set_lines("OPEN BOARD", "Back to the deck")
		return

	if has_jobs:
		status_title.text = "%d contract(s) ready" % queued.size()
		var names: PackedStringArray = []
		for job in queued:
			names.append(str(job.get("name", "Job")))
		status_body.text = "%s\nOpen WORK and burn — the deck starts the session." % ", ".join(names)
		choose_contract_button.visible = false
		actions.visible = true
		start_work_button.set_lines("OPEN BOARD", "Burn these contracts")
		return

	status_title.text = "Desk is idle"
	status_body.text = "Take contracts from the job board. Accepting one opens the burn board."
	choose_contract_button.visible = true
	actions.visible = false


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
	_breakdown_sheet.show_content("Running Costs", "\n".join(lines))


func _wire_breakdown_taps() -> void:
	_make_tappable(token_rate_label, "Token Rate", "compute.token_rate", "")
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


func _on_open_board() -> void:
	get_tree().call_group("main_ui", "switch_tab", "board")
