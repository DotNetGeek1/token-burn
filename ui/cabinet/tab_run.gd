class_name TabRun
extends CabinetTab

## The default screen: the contract on the bench as a paper tag and the figures
## that decide whether to press BURN. The workflow itself is not drawn here:
## the dock under the glass is the workflow, and the batch lights its bays as
## it runs, so a second strip on the glass only said the same thing smaller.

## Width over height of the drawn job card; the card is cut to the glass's
## height so the paper, and the ink on it, grow with the screen.
const CARD_ASPECT := 770.0 / 1321.0
const CARD_MIN_WIDTH := 120.0
const CARD_MAX_WIDTH := 300.0

var _card: ContractCard = null
var _stats: Dictionary = {}
var _keys: HBoxContainer = null
var _burn_keys: HBoxContainer = null
var _lit: int = -1
var _burning: bool = false


func tab_key() -> String:
	return "run"


func _ready() -> void:
	super._ready()
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(row)

	_card = ContractCard.new()
	_card.size_flags_horizontal = Control.SIZE_FILL
	_card.size_flags_stretch_ratio = 0.0
	_card.custom_minimum_size = Vector2(CARD_MIN_WIDTH, 0)
	_card.pressed.connect(func() -> void: shell.call("on_job_details"))
	_card.page_pressed.connect(func() -> void: shell.call("on_focus_next"))
	row.add_child(_card)
	resized.connect(_fit_card)
	_fit_card()

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_theme_constant_override("separation", 3)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	# The figures scroll when the glass is short (a handset canvas is ~300
	# tall), so the keys under them — BRIEF, SHIP IT — always stay on the glass
	# instead of being the part that falls off the bottom.
	var figures := ScrollContainer.new()
	figures.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	figures.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	figures.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(figures)
	var grid := GridContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	figures.add_child(grid)
	# QUALITY sits in the first row beside STATUS: whether the bar is cleared
	# is the figure that decides between SHIP IT and one more batch.
	for key in ["status", "quality", "value", "step", "synergy", "heat", "risk", "expires", "next"]:
		var cell: Dictionary = stat_cell({
			"status": "STATUS", "quality": "QUALITY VS BAR", "step": "CURRENT STEP", "value": "EST. VALUE",
			"synergy": "SYNERGY", "heat": "HEAT AFTER BURN", "risk": "BUG RISK", "expires": "CONTRACT EXPIRES",
			"next": "NEXT BATCH",
		}[key])
		cell["value"].name = "%sValue" % key.capitalize()
		grid.add_child(cell["cell"])
		_stats[key] = cell["value"]

	_keys = HBoxContainer.new()
	_keys.mouse_filter = Control.MOUSE_FILTER_PASS
	_keys.add_theme_constant_override("separation", 4)
	column.add_child(_keys)
	_burn_keys = HBoxContainer.new()
	_burn_keys.mouse_filter = Control.MOUSE_FILTER_PASS
	_burn_keys.add_theme_constant_override("separation", 4)
	_burn_keys.visible = false
	column.add_child(_burn_keys)
	# The batch's controls are not keys on this tab: the lever kills (a held
	# pull, since it throws work away) and SKIP sits in the CRT's corner.
	var burning_note: Label = CabinetStyle.mono("BATCH RUNNING — HOLD THE LEVER TO KILL AFTER THIS STAGE · SKIP SHOWS THE RESULT", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
	burning_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_burn_keys.add_child(burning_note)


## The card is as wide as its full height allows, so the paper is never the
## small fixed tag it would be at a bare minimum width on a big screen.
func _fit_card() -> void:
	if _card == null:
		return
	_card.custom_minimum_size.x = clampf(size.y * CARD_ASPECT, CARD_MIN_WIDTH, CARD_MAX_WIDTH)


func refresh() -> void:
	if shell == null or _burning:
		return
	var job: Dictionary = Simulation.focused_job()
	var working: bool = Simulation.phase == Simulation.Phase.IN_ROUND
	if job.is_empty() and not working:
		job = Simulation.queued_job_preview()
	var lanes: Array = _lanes()
	var lane_index: int = 0
	for index in range(lanes.size()):
		if str(Dictionary(lanes[index]).get("id", "")) == str(job.get("id", "")):
			lane_index = index
	_card.set_job(job, lane_index, maxi(1, lanes.size()))
	var preview: Dictionary = Simulation.preview_next_burn()
	_refresh_stats(job, working, preview)
	_refresh_keys(job, working)


func _lanes() -> Array:
	var lanes: Array = []
	for candidate in Array(Simulation.run_state.business.get("active_jobs", [])):
		if candidate is Dictionary and float(candidate.get("tokens_remaining", 0.0)) > 0.0:
			lanes.append(candidate)
	return lanes


func _refresh_stats(job: Dictionary, working: bool, preview: Dictionary) -> void:
	var status: String = "NO CONTRACT"
	var status_color: Color = CabinetStyle.PHOSPHOR_DIM
	if not job.is_empty():
		if JobSystem.is_ready(job):
			status = "READY TO SHIP"
			status_color = CabinetStyle.AMBER
		elif float(job.get("tokens_remaining", 0.0)) <= 0.0:
			status = "READY TO DELIVER"
			status_color = CabinetStyle.AMBER
		elif working:
			status = "ACTIVE"
			status_color = CabinetStyle.PHOSPHOR
		else:
			status = "QUEUED"
			status_color = CabinetStyle.PHOSPHOR
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		status = "AWAITING UPGRADE"
		status_color = CabinetStyle.AMBER
	_stat("status", status, status_color)
	var stage_count: int = int(preview.get("stage_count", Array(preview.get("stages", [])).size()))
	_stat("step", "%d / %d" % [maxi(0, _lit + 1), maxi(stage_count, Simulation.board_slots().size())], CabinetStyle.PHOSPHOR)
	if job.is_empty():
		_stat("quality", "—", CabinetStyle.PHOSPHOR_DIM)
		_stat("value", "—", CabinetStyle.PHOSPHOR_DIM)
		_stat("risk", "—", CabinetStyle.PHOSPHOR_DIM)
		_stat("expires", "—", CabinetStyle.PHOSPHOR_DIM)
	else:
		var verdict: Dictionary = CabinetStyle.quality_readout(job)
		_stat("quality", str(verdict["text"]), verdict["color"])
		var projected: float = float(job.get("reward", 0.0)) * JobSystem.projected_payout_multiplier(job)
		_stat("value", NumberFormat.format_cash(projected), CabinetStyle.PHOSPHOR)
		var risk: String = JobSystem.production_risk_class(job)
		_stat("risk", risk, CabinetStyle.risk_color(risk))
		var prompts: int = maxi(0, int(job.get("prompts_remaining", 0)))
		_stat("expires", "%d PROMPT%s" % [prompts, "" if prompts == 1 else "S"], CabinetStyle.RED if prompts <= 1 else (CabinetStyle.AMBER if prompts <= 3 else CabinetStyle.PHOSPHOR))
	var combos: int = 0
	for stage in Array(preview.get("stages", [])):
		if stage is Dictionary and not Array(stage.get("combos", [])).is_empty():
			combos += 1
	if preview.get("ok", false):
		var out: float = float(preview.get("output_mult", 1.0))
		_stat("synergy", "%d COMBO%s · ×%.2f" % [combos, "" if combos == 1 else "S", out], CabinetStyle.AMBER if combos > 0 else CabinetStyle.PHOSPHOR)
		var capacity: float = maxf(1.0, float(preview.get("heat_capacity", 100.0)))
		var before: float = float(preview.get("heat_before", 0.0)) / capacity
		var after: float = float(preview.get("heat_ratio_after", before))
		var heat_label: String = str(preview.get("heat_state_label", ""))
		_stat("heat", "%d%% → %d%%%s" % [int(round(before * 100.0)), int(round(after * 100.0)), (" " + heat_label.to_upper()) if heat_label != "" else ""], CabinetStyle.RED if after >= 0.9 else (CabinetStyle.AMBER if after >= 0.8 else CabinetStyle.PHOSPHOR))
		var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
		_stat("next", "%s BT · +%s%%" % [
			NumberFormat.format(float(preview.get("tokens", 0.0))),
			NumberFormat.format(float(preview.get("progress_tokens", 0.0)) / requirement * 100.0),
		], CabinetStyle.PHOSPHOR)
	else:
		_stat("synergy", "—", CabinetStyle.PHOSPHOR_DIM)
		_stat("heat", "—", CabinetStyle.PHOSPHOR_DIM)
		_stat("next", str(preview.get("reason", "—")).to_upper(), CabinetStyle.PHOSPHOR_DIM)


func _stat(key: String, text: String, color: Color) -> void:
	var label: Label = _stats[key]
	label.text = text
	label.add_theme_color_override("font_color", color)


## The value Label of one figure in the grid (`status`, `quality`, `value`,
## `step`, `synergy`, `heat`, `risk`, `expires`, `next`), for the playtests.
func stat_label(key: String) -> Label:
	return _stats.get(key)


## The job card on the bench.
func card() -> ContractCard:
	return _card


## The lesser commands under the figures: the brief, delivering, YOLO, the
## full editor. BURN, COOL and BOOST live on the deck below the glass.
func _refresh_keys(job: Dictionary, working: bool) -> void:
	for child in _keys.get_children():
		_keys.remove_child(child)
		child.queue_free()
	if not job.is_empty():
		_add_key("BRIEF", CabinetStyle.PHOSPHOR, func() -> void: shell.call("on_job_details"))
		if working and Simulation.work_policy() != WorkSession.POLICY_YOLO:
			var complete: bool = float(job.get("tokens_remaining", 0.0)) <= 0.0
			var ready: bool = JobSystem.is_ready(job)
			_add_key("SHIP IT" if ready or complete else "DELIVER", CabinetStyle.AMBER if ready or complete else CabinetStyle.RED, func() -> void: shell.call("on_deliver"))
	if Simulation.yolo_unlocked() and (working or Simulation.can_start_work()) and Simulation.work_policy() != WorkSession.POLICY_YOLO:
		_add_key("YOLO", CabinetStyle.RED, func() -> void: shell.call("on_yolo"))
	var matches: Array = Simulation.workflow_matches(job) if not job.is_empty() else []
	if matches.size() >= 2:
		_add_key("ROUTE", CabinetStyle.PHOSPHOR, func() -> void: shell.call("on_cycle_workflow"))


func _add_key(text: String, accent: Color, pressed: Callable) -> void:
	var key: Button = CabinetStyle.key(text, accent, CabinetStyle.FONT_TINY)
	key.pressed.connect(pressed)
	_keys.add_child(key)


## The stage the batch is on, for the CURRENT STEP figure; the dock lights the
## bay itself. -1 puts the figure back to rest.
func light_step(slot_index: int) -> void:
	_lit = slot_index
	_stat("step", "%d / %d" % [maxi(0, _lit + 1), Simulation.board_slots().size()], CabinetStyle.AMBER if _lit >= 0 else CabinetStyle.PHOSPHOR)


func set_burning(burning: bool) -> void:
	_burning = burning
	_burn_keys.visible = burning
	_keys.visible = not burning
	if not burning:
		_lit = -1


## The figures the batch is reporting as it runs.
func show_beat_status(status: String, color: Color = CabinetStyle.PHOSPHOR) -> void:
	_stat("status", status.to_upper(), color)
