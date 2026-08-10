extends Control

## The job board as the machine prints it: a table of contracts on the wire, and
## a pane underneath expanding whichever one is selected.
##
## The data is exactly what the card grid used to show — the same offers, the
## same ratings, the same accept call — but read as terminal output, so taking a
## contract is a line on a console rather than a tile on a shop front.

const RiskQuips := preload("res://ui/common/risk_quips.gd")

@onready var frame: ConsoleFrame = $Margin/Frame

var _ascend_row: ConsoleMenuRow = null
var _status: VBoxContainer = null
var _risk_line: Label = null
var _risk_warning: Label = null
var _table: ConsoleTable = null
var _detail: ConsoleDetail = null
var _offers: Dictionary = {}
var _selected_id: String = ""
var _round_cost_cache: float = 1.0


func _ready() -> void:
	add_to_group("ui_refresh")
	frame.setup("Job Board")
	_build_console()
	EventBus.run_started.connect(refresh)
	EventBus.round_started.connect(refresh)
	EventBus.job_accepted.connect(func(_id): refresh())
	Simulation.work_session_finished.connect(func(_result): refresh())
	refresh()


func _build_console() -> void:
	var content: VBoxContainer = frame.content()

	_ascend_row = ConsoleMenuRow.new()
	_ascend_row.index_label = "A"
	_ascend_row.visible = false
	_ascend_row.pressed.connect(_on_ascend_pressed)
	content.add_child(_ascend_row)
	_ascend_row.set_metrics(ConsoleStyle.FONT_SMALL, ConsoleTable.ROW_HEIGHT, ConsoleTable.PAD_H)

	_status = VBoxContainer.new()
	_status.add_theme_constant_override("separation", 2)
	content.add_child(_status)

	_risk_line = ConsoleStyle.label("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_status.add_child(_risk_line)
	_risk_warning = ConsoleStyle.paragraph("", ConsoleStyle.FONT_TINY, ConsoleStyle.DANGER)
	_status.add_child(_risk_warning)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	_table = ConsoleTable.new()
	_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table.row_selected.connect(_on_row_selected)
	scroll.add_child(_table)
	_table.set_columns([
		{"label": "id", "weight": 0.5},
		{"label": "client", "weight": 1.2},
		{"label": "contract", "weight": 2.6},
		{"label": "pmt", "weight": 0.6, "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"label": "qual", "weight": 0.6, "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"label": "pay", "weight": 0.9, "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"label": "risk", "weight": 0.8},
		{"label": "tok", "weight": 0.8},
		{"label": "status", "weight": 1.0},
	])

	_detail = ConsoleDetail.new()
	_detail.size_flags_vertical = Control.SIZE_SHRINK_END
	_detail.action_pressed.connect(_on_detail_action)
	content.add_child(_detail)
	_detail.clear("SELECT A CONTRACT")


func refresh() -> void:
	if Simulation.phase == Simulation.Phase.ROUND_PREP:
		Simulation.ensure_job_offers()
	var state := Simulation.run_state
	frame.set_context("DEMAND %d" % int(state.business.get("demand", 0.0)))
	_round_cost_cache = _round_costs()

	var offers: Array = state.business.get("job_offers", [])
	var queued: Array = state.business.get("job_queue", [])
	_offers.clear()
	_table.clear()
	_refresh_ascend_row()
	_refresh_status(offers, queued)

	var in_upgrade: bool = Simulation.phase == Simulation.Phase.ANGEL_ROUND
	var index: int = 1
	for offer in offers:
		_add_offer_row(offer, index, in_upgrade)
		index += 1
	for job in queued:
		_add_queued_row(job, index)
		index += 1
	if offers.is_empty() and queued.is_empty():
		_table.add_note(_empty_line(in_upgrade))

	# A refresh redraws every row, so the pane keeps its subject rather than
	# emptying itself under the player's hand.
	if _selected_id == "" or not _table.select_meta(_selected_id):
		_detail.clear("SELECT A CONTRACT")


func _add_offer_row(offer: Dictionary, index: int, in_upgrade: bool) -> void:
	var id: String = str(offer.get("id", ""))
	_offers[id] = offer
	var identity: Dictionary = JobPresentation.sector(offer)
	var status: String = "OPEN"
	if in_upgrade:
		status = "UPGRADE"
	elif not _can_accept(id):
		status = "AT CAPACITY" if Simulation.phase == Simulation.Phase.ROUND_PREP else "BUSY"
	_table.add_row([
		"[%02d]" % index,
		{"text": str(identity["client"]).to_upper(), "color": ConsoleStyle.PHOSPHOR_DIM},
		str(offer.get("name", "Job")),
		"%d" % int(offer.get("deadline_prompts", 0)),
		JobPresentation.quality_mark(float(offer.get("quality_threshold", 0.0))),
		{
			"text": NumberFormat.format_cash(float(offer.get("reward", 0.0))),
			"color": ConsoleStyle.PHOSPHOR,
		},
		{"dots": JobPresentation.risk_rating(offer), "color": ConsoleStyle.DANGER},
		{"dots": JobPresentation.token_rating(offer), "color": ConsoleStyle.PHOSPHOR},
		{
			"text": status,
			"color": ConsoleStyle.PHOSPHOR if status == "OPEN" else ConsoleStyle.PHOSPHOR_DIM,
		},
	], id)


## Contracts already on the slate stay listed so the board shows the whole round,
## but they are dim and carry no action.
func _add_queued_row(job: Dictionary, index: int) -> void:
	var identity: Dictionary = JobPresentation.sector(job)
	_table.add_row([
		"[%02d]" % index,
		{"text": str(identity["client"]).to_upper(), "color": ConsoleStyle.PHOSPHOR_DIM},
		{"text": str(job.get("name", "Job")), "color": ConsoleStyle.PHOSPHOR_DIM},
		"%d" % int(job.get("deadline_prompts", 0)),
		JobPresentation.quality_mark(float(job.get("quality_threshold", 0.0))),
		{
			"text": NumberFormat.format_cash(float(job.get("reward", 0.0))),
			"color": ConsoleStyle.PHOSPHOR_DIM,
		},
		{"dots": JobPresentation.risk_rating(job), "color": ConsoleStyle.PHOSPHOR_DIM},
		{"dots": JobPresentation.token_rating(job), "color": ConsoleStyle.PHOSPHOR_DIM},
		{"text": "TAKEN", "color": ConsoleStyle.PHOSPHOR_DIM},
	], null)


func _can_accept(offer_id: String) -> bool:
	if Simulation.phase != Simulation.Phase.ROUND_PREP:
		return false
	if Simulation.is_work_running():
		return false
	return Simulation.can_accept_offer(offer_id)


func _empty_line(in_upgrade: bool) -> String:
	if in_upgrade:
		return "AWAITING UPGRADE — CONTRACTS RESUME AFTER"
	if Simulation.is_work_running():
		return "ROUND UNDER WAY — OPEN THE WORK TAB"
	return "NO CONTRACTS ON THE WIRE — FINISH THE ROUND OR RAISE DEMAND"


# --- Status lines ------------------------------------------------------------

func _refresh_status(offers: Array, queued: Array) -> void:
	var state := Simulation.run_state
	var parts: PackedStringArray = [
		"ADS %s/DAY" % NumberFormat.format_cash(float(state.business.get("advertising", 0.0))),
	]
	var reputation: String = _reputation_line()
	if reputation != "":
		parts.append(reputation.to_upper())
	if not queued.is_empty():
		parts.append("%d ON THE SLATE" % queued.size())
	elif not offers.is_empty():
		parts.append("%d ON THE WIRE" % offers.size())
	_risk_line.text = " · ".join(parts)

	var warning: String = ""
	var info: Dictionary = Simulation.queue_load_info()
	var deadline: int = int(info.get("deadline_prompts", 0))
	if not queued.is_empty() and deadline > 0:
		var ratio: float = float(info.get("ratio", 0.0))
		_risk_line.text += " · LOAD %.1f/%d PROMPTS · %s" % [
			float(info.get("prompts_needed", 0.0)), deadline, RiskQuips.severity(ratio).to_upper(),
		]
		warning = RiskQuips.warning(ratio, int(info.get("jobs", 0)))
	_risk_warning.text = warning.to_upper()
	_risk_warning.visible = warning != ""


## Always on the board: the ascension contract is live from round one, so this is
## a running readout rather than an entry point to anything.
func _refresh_ascend_row() -> void:
	var summary: Dictionary = Simulation.ascension_summary()
	var contract: Dictionary = Dictionary(summary.get("contract", {}))
	if contract.is_empty():
		_ascend_row.visible = false
		return
	var progress: Dictionary = Dictionary(summary.get("progress", {}))
	var rounds_left: int = int(progress.get("rounds_remaining", 0))
	_ascend_row.visible = true
	_ascend_row.headline = str(contract.get("name", "The contract")).to_upper()
	_ascend_row.value_text = "%.0f%% BURNED · %d ROUND(S) LEFT" % [
		float(progress.get("burn_ratio", 0.0)) * 100.0, rounds_left,
	]
	_ascend_row.destructive = rounds_left <= 3


# --- Detail pane -------------------------------------------------------------

func _on_row_selected(meta: Variant) -> void:
	if meta == null:
		_selected_id = ""
		_detail.clear("CONTRACT ALREADY TAKEN")
		return
	_selected_id = str(meta)
	var offer: Dictionary = _offers.get(_selected_id, {})
	if offer.is_empty():
		_detail.clear("SELECT A CONTRACT")
		return
	var can_accept: bool = _can_accept(_selected_id)
	var identity: Dictionary = JobPresentation.sector(offer)
	_detail.show_detail(
		"%s — %s" % [str(identity["client"]).to_upper(), str(offer.get("name", "Job")).to_upper()],
		_detail_lines(offer),
		"[ ENTER ] ACCEPT CONTRACT" if can_accept else _blocked_action(),
		can_accept
	)


func _blocked_action() -> String:
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		return "[ -- ] CHOOSE YOUR UPGRADE FIRST"
	if Simulation.is_work_running():
		return "[ -- ] ROUND IN PROGRESS"
	return "[ -- ] AT CAPACITY"


func _detail_lines(offer: Dictionary) -> Array:
	var lines: Array = [
		{
			"stat": "Reward",
			"value": NumberFormat.format_cash(float(offer.get("reward", 0.0))),
		},
		{"stat": "Tokens", "value": NumberFormat.format(float(offer.get("token_requirement", 0.0)))},
		{
			"stat": "Quality target",
			"value": "%s / 10" % JobPresentation.quality_mark(
				float(offer.get("quality_threshold", 0.0))
			),
		},
		{"stat": "Deadline", "value": "%d prompts" % int(offer.get("deadline_prompts", 0))},
		{
			"stat": "Pays for",
			"value": "%.1f rounds of bills" % (
				float(offer.get("reward", 0.0)) / maxf(1.0, _round_cost_cache)
			),
		},
		{"text": _quality_stakes(float(offer.get("quality_threshold", 0.0)))},
	]
	if str(offer.get("description", "")) != "":
		lines.append({"text": str(offer.get("description", ""))})
	var demands: Array = JobPresentation.demands(offer)
	if not demands.is_empty():
		lines.append({"text": "This contract expects certain things from the workflow you put it through. Ignore them and it will cost you."})
		lines.append_array(demands)
	lines.append_array(JobPresentation.rules(offer))
	for warning in _capacity_warnings(offer):
		lines.append({"warn": warning})
	return lines


## What the bar is actually worth, read off the same curve the payout uses rather
## than restated here, so the sentence cannot drift from the maths.
func _quality_stakes(threshold: float) -> String:
	if threshold <= 0.0:
		return "This client is not marking the work."
	var under: float = JobSystem.quality_payout_multiplier(threshold * 0.5, threshold)
	var over: float = JobSystem.quality_payout_multiplier(threshold * 2.0, threshold)
	return (
		"Hit the bar and the fee is paid in full. Halfway to it pays %d%%, and work well over it pays up to %d%% — plus reputation, which opens bigger clients."
		% [int(round(under * 100.0)), int(round(over * 100.0))]
	)


## Warns when taking this contract on top of the queue would outrun throughput.
func _capacity_warnings(offer: Dictionary) -> Array:
	if Array(Simulation.run_state.business.get("job_queue", [])).is_empty():
		return []
	var info: Dictionary = Simulation.queue_load_info(offer)
	var ratio: float = float(info.get("ratio", 0.0))
	if ratio <= 1.0:
		return []
	if ratio > float(info.get("cap", 2.0)):
		return ["Queue full — this will not fit in the round"]
	return ["Queue at %.0f%% capacity" % (ratio * 100.0)]


## Reputation said in terms of what it is for: the fee it adds to every offer,
## and the client tier the next few points would open.
func _reputation_line() -> String:
	var state := Simulation.run_state
	var reputation: float = float(state.business.get("reputation", 0.0))
	if reputation <= -3.0:
		return "Below -5 the run is over"
	var parts: PackedStringArray = []
	var bonus: float = JobSystem.reputation_reward_multiplier(state, ContentDatabase) - 1.0
	if bonus > 0.005:
		parts.append("+%d%% fees" % int(round(bonus * 100.0)))
	var next_tier: Dictionary = JobSystem.next_reputation_tier(state, ContentDatabase)
	if not next_tier.is_empty():
		parts.append("tier %d at rep %d" % [
			int(next_tier["tier"]), int(ceil(float(next_tier["reputation"]))),
		])
	return " · ".join(parts)


## What a round costs to run, which is what a fee is worth measuring against.
func _round_costs() -> float:
	var costs: Dictionary = Simulation.cost_forecast()
	return maxf(1.0, float(costs.get("fixed_due", 0.0)))


# --- Actions -----------------------------------------------------------------

func _on_detail_action() -> void:
	if _selected_id == "":
		return
	_accept_job(_selected_id)


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _selected_id == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if _can_accept(_selected_id):
				_accept_job(_selected_id)
				get_viewport().set_input_as_handled()


func _accept_job(job_id: String) -> void:
	UiSound.play("accept")
	if Simulation.accept_job(job_id):
		_selected_id = ""
		get_tree().call_group("main_ui", "switch_tab", "work")
		get_tree().call_group("ui_refresh", "refresh")
		get_tree().call_group("main_ui", "refresh_all")


func _on_ascend_pressed() -> void:
	get_tree().call_group("main_ui", "open_ascension_select")
