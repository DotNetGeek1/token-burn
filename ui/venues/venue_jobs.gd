extends VenueScene

## The job board: a back office with the contracts pinned up on the wall.
##
## Same wire, same offers, same accept call as the printed table, read as a board
## in a room instead. The office writes the state of the business up the left —
## what demand is, what reputation is worth, how loaded the slate already is —
## the contracts themselves are cards on the big board, including the action
## that accepts them without opening a separate detail surface.
##
## What the table could never do is set the fee large. A contract is taken or left
## on its fee against what it will cost to deliver, and on a board there is room
## to put that number where the eye lands first.

## The two shelves the board keeps: what could still be taken, and what already
## has been. The slate is listed rather than hidden because the load warning is
## about the slate, and a warning about work you cannot see is a riddle.
const WIRE := "wire"
const SLATE := "slate"

const RiskQuips := preload("res://ui/common/risk_quips.gd")

var _kicker: Label = null
var _index_lines: VBoxContainer = null
var _warning: Label = null
var _counters: VBoxContainer = null
var _board_panel: VenuePanel = null
var _board: VenueBoard = null
var _notice: Label = null
var _counter_rows: Dictionary = {}
var _active: String = WIRE
var _round_cost_cache: float = 1.0


func venue_key() -> String:
	return "jobs"


func _hint_entries() -> Array:
	return []


func _build_venue() -> void:
	_build_index()
	_build_board()
	_build_notice()
	EventBus.run_started.connect(refresh)
	EventBus.round_started.connect(refresh)
	EventBus.job_accepted.connect(func(_id: String) -> void: refresh())
	Simulation.work_session_finished.connect(func(_result: Dictionary) -> void: refresh())


## The left-hand panel: the state of the business as a client would see it, then
## which of the two shelves is on the board.
func _build_index() -> void:
	var panel: VenuePanel = add_panel("index", "Job Board", {
		"console_order": 10, "console_min": 190.0,
	})
	var content: VBoxContainer = panel.content()

	_kicker = ConsoleStyle.label(
		"CONTRACTS ON THE WIRE", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	content.add_child(_kicker)

	_index_lines = VBoxContainer.new()
	_index_lines.add_theme_constant_override("separation", 2)
	content.add_child(_index_lines)

	_warning = ConsoleStyle.paragraph("", ConsoleStyle.FONT_TINY, ConsoleStyle.DANGER)
	_warning.visible = false
	content.add_child(_warning)

	content.add_child(ConsoleStyle.rule(0.22))

	_counters = VBoxContainer.new()
	_counters.add_theme_constant_override("separation", 0)
	_counters.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_counters)


func _build_board() -> void:
	_board_panel = add_panel("board", "On the wire", {
		# A shorter floor than the market's shelf: the wire carries two or three
		# contracts where the shop carries a dozen, so a taller minimum is a hole
		# under the last card rather than room for more.
		"console_order": 20, "console_min": 200.0, "grow": true,
	})
	_board = VenueBoard.new()
	_board.tile_action.connect(_on_job_action)
	_board_panel.content().add_child(_board)


## The card by the door, carrying the one contract that is not on the wire: the
## ascension deal, live from round one and counting down whether it is looked at
## or not. A press on it opens the terms.
func _build_notice() -> void:
	var panel: VenuePanel = add_panel("notice", "", {
		"console_order": 40, "console_min": 70.0,
	})
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(_on_ascend_pressed)
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(button)

	_notice = ConsoleStyle.paragraph("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.content().add_child(_notice)


# --- Refresh -----------------------------------------------------------------

func refresh() -> void:
	if _board == null:
		return
	# The wire is only restocked between rounds, and a player who walked in here
	# during prep should find it stocked rather than empty.
	if Simulation.phase == Simulation.Phase.ROUND_PREP:
		Simulation.ensure_job_offers()
	_round_cost_cache = _round_costs()
	var shelves: Dictionary = _shelves()
	if Array(shelves.get(_active, [])).is_empty():
		_active = WIRE if not Array(shelves[WIRE]).is_empty() else SLATE
	_refresh_index(shelves)
	_refresh_counters(shelves)
	_refresh_board(shelves)
	_refresh_notice()


func _shelves() -> Dictionary:
	var state := Simulation.run_state
	return {
		WIRE: Array(state.business.get("job_offers", [])),
		SLATE: Array(state.business.get("job_queue", [])),
	}


func _refresh_index(shelves: Dictionary) -> void:
	for child in _index_lines.get_children():
		_index_lines.remove_child(child)
		child.queue_free()
	var state := Simulation.run_state
	var lines: Array = [
		{"stat": "Demand", "value": "%d" % int(state.business.get("demand", 0.0))},
		{
			"stat": "Advertising",
			"value": "%s / day" % NumberFormat.format_cash(
				float(state.business.get("advertising", 0.0))
			),
		},
		{
			"stat": "Reputation",
			"value": _reputation_value(),
			"color": _reputation_color(),
		},
		{
			"stat": "Round costs",
			"value": NumberFormat.format_cash(_round_cost_cache),
			"color": ConsoleStyle.WARNING,
		},
	]
	var load_line: String = _load_value(shelves)
	if load_line != "":
		lines.append({"stat": "Slate load", "value": load_line})
	for entry in lines:
		var line: Control = ConsoleStyle.detail_line(
			entry, ConsoleMetrics.font_small(console_scale())
		)
		if line != null:
			_index_lines.add_child(line)
	var warning: String = _load_warning(shelves)
	_warning.text = warning.to_upper()
	_warning.visible = warning != ""


func _reputation_value() -> String:
	var state := Simulation.run_state
	var reputation: float = float(state.business.get("reputation", 0.0))
	var bonus: float = JobSystem.reputation_reward_multiplier(state, ContentDatabase) - 1.0
	if bonus > 0.005:
		return "%d · +%d%% fees" % [int(round(reputation)), int(round(bonus * 100.0))]
	return "%d" % int(round(reputation))


## Reputation is the one figure here that can end the run, so below zero it stops
## being a bonus and starts being a colour.
func _reputation_color() -> Color:
	var reputation: float = float(Simulation.run_state.business.get("reputation", 0.0))
	if reputation <= -3.0:
		return ConsoleStyle.DANGER
	if reputation < 0.0:
		return ConsoleStyle.WARNING
	return ConsoleStyle.PHOSPHOR


## How much work the slate is already carrying against the deadline it has to
## carry it in. The number that decides whether the next contract is a fee or a
## failure.
func _load_value(shelves: Dictionary) -> String:
	if Array(shelves.get(SLATE, [])).is_empty():
		return ""
	var info: Dictionary = Simulation.queue_load_info()
	var deadline: int = int(info.get("deadline_prompts", 0))
	if deadline <= 0:
		return ""
	return "%.1f / %d prompts" % [float(info.get("prompts_needed", 0.0)), deadline]


func _load_warning(shelves: Dictionary) -> String:
	if Array(shelves.get(SLATE, [])).is_empty():
		return ""
	var info: Dictionary = Simulation.queue_load_info()
	if int(info.get("deadline_prompts", 0)) <= 0:
		return ""
	return RiskQuips.warning(float(info.get("ratio", 0.0)), int(info.get("jobs", 0)))


func _refresh_counters(shelves: Dictionary) -> void:
	var wanted: Array[String] = []
	for key in [WIRE, SLATE]:
		if not Array(shelves.get(key, [])).is_empty():
			wanted.append(str(key))
	if wanted.is_empty():
		wanted.append(WIRE)
	if wanted != _counter_order():
		for child in _counters.get_children():
			_counters.remove_child(child)
			child.queue_free()
		_counter_rows.clear()
		var index: int = 1
		for key in wanted:
			var row := ConsoleMenuRow.new()
			row.index_label = str(index)
			row.headline = _counter_label(key)
			row.pressed.connect(_on_counter_pressed.bind(key))
			_counters.add_child(row)
			_counter_rows[key] = row
			index += 1
	for key in _counter_rows:
		var row: ConsoleMenuRow = _counter_rows[key]
		row.value_text = "%d" % Array(shelves.get(key, [])).size()
		row.set_selected(str(key) == _active)
	_layout_counter_rows()


func _counter_order() -> Array[String]:
	var keys: Array[String] = []
	for child in _counters.get_children():
		for key in _counter_rows:
			if _counter_rows[key] == child:
				keys.append(str(key))
	return keys


func _counter_label(key: String) -> String:
	return "ON THE SLATE" if key == SLATE else "ON THE WIRE"


func _on_counter_pressed(key: String) -> void:
	if _active == key:
		return
	_active = key
	_board.clear_selection()
	refresh()
	lean_on("board")


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if SceneRouter.investor_busy():
		return
	var slot: int = event.keycode - KEY_1
	var order: Array[String] = _counter_order()
	if slot < 0 or slot >= order.size():
		return
	_on_counter_pressed(order[slot])
	get_viewport().set_input_as_handled()


func _refresh_board(shelves: Dictionary) -> void:
	_board_panel.set_heading(_counter_label(_active).capitalize())
	var entries: Array = []
	var taken: bool = _active == SLATE
	for job in Array(shelves.get(_active, [])):
		entries.append(_job_entry(job, taken))
	var note: String = "" if not entries.is_empty() else _empty_line()
	_board.set_entries(entries, note)


func _refresh_notice() -> void:
	var summary: Dictionary = Simulation.ascension_summary()
	var contract: Dictionary = Dictionary(summary.get("contract", {}))
	if contract.is_empty():
		_notice.text = "NO DEAL ON THE TABLE"
		return
	var progress: Dictionary = Dictionary(summary.get("progress", {}))
	var rounds_left: int = int(progress.get("rounds_remaining", 0))
	_notice.text = "%s\n%.0f%% BURNED · %d ROUND(S) LEFT" % [
		str(contract.get("name", "The contract")).to_upper(),
		float(progress.get("burn_ratio", 0.0)) * 100.0,
		rounds_left,
	]
	_notice.add_theme_color_override(
		"font_color",
		ConsoleStyle.DANGER if rounds_left <= 3 else ConsoleStyle.PHOSPHOR_DIM
	)


func _empty_line() -> String:
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		return "AWAITING UPGRADE — CONTRACTS RESUME AFTER"
	if Simulation.is_work_running():
		return "ROUND UNDER WAY — THE WORK IS BACK AT THE DESK"
	return "NO CONTRACTS ON THE WIRE — FINISH THE ROUND OR RAISE DEMAND"


# --- Tiles -------------------------------------------------------------------

## A contract as a card: whose it is and what it is called, the fee set large,
## what delivering it will take, and what the fee is actually worth measured in
## rounds of bills — which is the only honest way to read a number like £4,000.
func _job_entry(job: Dictionary, taken: bool) -> Dictionary:
	var id: String = str(job.get("id", ""))
	var identity: Dictionary = JobPresentation.sector(job)
	var reward: float = float(job.get("reward", 0.0))
	var status: String = "TAKEN" if taken else _offer_status(id)
	return {
		"meta": id if not taken else null,
		"name": "%s — %s" % [str(identity["client"]), str(job.get("name", "Job"))],
		"figure": NumberFormat.format_cash(reward),
		"unit": "fee",
		"spec": _spec_line(job),
		"price": "%.1f rounds of bills" % (reward / maxf(1.0, _round_cost_cache)),
		"price_color": ConsoleStyle.PHOSPHOR_DIM,
		"status": status,
		"status_color": (
			ConsoleStyle.PHOSPHOR if status == "OPEN" else ConsoleStyle.PHOSPHOR_DIM
		),
		"figure_color": ConsoleStyle.PHOSPHOR if not taken else ConsoleStyle.PHOSPHOR_DIM,
		"icon": identity["icon"],
		"tooltip": str(job.get("description", "")),
		"action_text": "" if taken else "ACCEPT",
		"action_enabled": not taken and _can_accept(id),
		"action_tooltip": "" if taken else _accept_action_tooltip(id),
	}


## What it takes to deliver, in the order it bites: how much work, how good it
## has to be, and how long there is to do it.
func _spec_line(job: Dictionary) -> String:
	var parts: PackedStringArray = [
		"%s tokens" % NumberFormat.format(float(job.get("token_requirement", 0.0))),
	]
	var threshold: float = float(job.get("quality_threshold", 0.0))
	if threshold > 0.0:
		parts.append("bar %s" % JobPresentation.quality_mark(threshold))
	parts.append("%d prompts" % int(job.get("deadline_prompts", 0)))
	return " · ".join(parts)


func _offer_status(id: String) -> String:
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		return "UPGRADE FIRST"
	if _can_accept(id):
		return "OPEN"
	if Simulation.is_work_running():
		return "BUSY"
	return "AT CAPACITY"


func _can_accept(offer_id: String) -> bool:
	if offer_id == "":
		return false
	if Simulation.phase != Simulation.Phase.ROUND_PREP:
		return false
	if Simulation.is_work_running():
		return false
	return Simulation.can_accept_offer(offer_id)


# --- Card actions ------------------------------------------------------------

func _accept_action_tooltip(offer_id: String) -> String:
	if _can_accept(offer_id):
		return "Accept contract"
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		return "Choose your upgrade first."
	if Simulation.is_work_running():
		return "The current round is already in progress."
	return "The slate is at capacity."


func _detail_lines(offer: Dictionary) -> Array:
	var lines: Array = [
		{"stat": "Reward", "value": NumberFormat.format_cash(float(offer.get("reward", 0.0)))},
		{
			"stat": "Tokens",
			"value": NumberFormat.format(float(offer.get("token_requirement", 0.0))),
		},
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


## Warns when taking this contract on top of the slate would outrun throughput.
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


## What a round costs to run, which is what a fee is worth measuring against.
func _round_costs() -> float:
	var costs: Dictionary = Simulation.cost_forecast()
	return maxf(1.0, float(costs.get("fixed_due", 0.0)))


# --- Actions -----------------------------------------------------------------

func _on_job_action(meta: Variant) -> void:
	var job_id: String = str(meta)
	if _can_accept(job_id):
		_accept_job(job_id)


func _accept_job(job_id: String) -> void:
	UiSound.play("accept")
	if Simulation.accept_job(job_id):
		_board.clear_selection()
		refresh()
		get_tree().call_group("ui_refresh", "refresh")


func _on_ascend_pressed() -> void:
	UiSound.play("tap")
	SceneRouter.open_terms()


# --- Layout ------------------------------------------------------------------

func _on_venue_layout() -> void:
	var scale: float = console_scale()
	if _board != null:
		# Job cards carry a title, a fee, and a spec — four across squashes them.
		_board.set_console(console_mode(), 3)
		_board.set_metrics(scale, content_width("board"))
	_layout_counter_rows()
	var font_tiny: int = ConsoleMetrics.font_tiny(scale)
	if _kicker != null:
		_kicker.add_theme_font_size_override("font_size", font_tiny)
	if _warning != null:
		_warning.add_theme_font_size_override("font_size", font_tiny)
	if _notice != null:
		_notice.add_theme_font_size_override("font_size", font_tiny)
	for line in _index_lines.get_children():
		_apply_line_font(line, ConsoleMetrics.font_small(scale))


func _apply_line_font(line: Node, font_size: int) -> void:
	if line is Label:
		line.add_theme_font_size_override("font_size", font_size)
		return
	for child in line.get_children():
		_apply_line_font(child, font_size)


func _layout_counter_rows() -> void:
	var scale: float = console_scale()
	var font: int = ConsoleMetrics.font_small(scale)
	var height: int = ConsoleMetrics.row_height(scale)
	var pad: int = ConsoleMetrics.pad_h(scale)
	for key in _counter_rows:
		(_counter_rows[key] as ConsoleMenuRow).set_metrics(font, height, pad)
