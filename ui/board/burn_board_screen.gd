extends Control

const BurnSpectacle := preload("res://presentation/burn_spectacle.gd")

## The Burn Board: the work screen, printed on the evolving workstation.
##
## The workstation is the machine the operation is run from, so a burn is reported and
## driven from the same piece of glass as everything else: the contract's
## progress, quality, deadline and heat are printed rows, and BURN, COOL, the
## surges and DELIVER are command lines under them. There is no keyboard deck and
## no contract plate — a batch is started by typing on the machine, and the
## investor's terms live on the whiteboard.
##
## One shared control owns the artwork, live primary console, supporting screens,
## shake, glow, smoke, fire and beacon. There is no second rig hidden behind it.

## Slice used while waiting out a spectacle beat, so KILL / SKIP can land
## without finishing the rest of the hold.
const HOLD_SLICE := 0.05

## The heat a redline build has to be sitting at before a burn starts for its
## conditional modules to fire, called out on the meter so entering a burn hot
## reads as a decision rather than an accident.
const REDLINE_RATIO := 0.9

## Prompts left at which the deadline stops reading as time in hand.
const DEADLINE_WARNING_PROMPTS := 3
const DEADLINE_DANGER_PROMPTS := 1

@onready var rig: WorkstationRig = $Rig

var _laptop: WorkstationConsole = null
var _burning: bool = false
var _kill_requested: bool = false
var _skip_requested: bool = false
var _stages_completed: int = 0
var _proc_depth: int = 0
var _detail_sheet: ConsoleSheet = null
var _danger_vignette: DangerVignette = null


func _ready() -> void:
	add_to_group("ui_refresh")
	# The shell re-lays the room out whenever the operation moves premises.
	add_to_group("board_mounted")
	_danger_vignette = DangerVignette.mount(self)
	_detail_sheet = ConsoleSheet.new()
	_laptop = WorkstationConsole.new()
	_laptop.name = "PrimaryConsole"
	rig.mount_primary(_laptop)
	_laptop.setup("burn")
	_mount_sheet(_detail_sheet)
	relayout_on_board()
	Simulation.work_tick_completed.connect(refresh)
	Simulation.work_session_finished.connect(func(_result): refresh())
	EventBus.module_acquired.connect(func(_id): refresh())
	refresh()


# --- Mounting ----------------------------------------------------------------

## Anchors the complete workstation into the room's authored clear desk bay.
func relayout_on_board() -> void:
	if rig == null:
		return
	var dwelling: String = _board_dwelling()
	var column: Rect2 = AssetCatalog.board_region(dwelling, "work_column")
	var bay: Rect2 = AssetCatalog.board_workstation_bay(dwelling)
	var rect: Rect2 = AssetCatalog.board_rect_in_region(column, bay)
	if rect.size.x <= 0.0:
		rect = Rect2(0.10, 0.05, 0.80, 0.92)
	_anchor(rig, rect)


func _anchor(control: Control, rect: Rect2) -> void:
	control.anchor_left = rect.position.x
	control.anchor_top = rect.position.y
	control.anchor_right = rect.position.x + rect.size.x
	control.anchor_bottom = rect.position.y + rect.size.y
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


## The sheet is a window-sized modal, so it goes on the shell's overlay layer
## rather than inside this screen, which the room zoom can push off the window.
func _mount_sheet(sheet: Control) -> void:
	for node in get_tree().get_nodes_in_group("main_ui"):
		if node.has_method("mount_overlay"):
			node.mount_overlay(sheet)
			return
	add_child(sheet)


func _board_dwelling() -> String:
	for node in get_tree().get_nodes_in_group("main_ui"):
		if node.has_method("board_dwelling"):
			return str(node.call("board_dwelling"))
	return AssetCatalog.dwelling_for_build(Simulation.run_state.build)


# --- Refresh -----------------------------------------------------------------

func refresh() -> void:
	if _burning or _laptop == null:
		return
	var job: Dictionary = Simulation.focused_job()
	var working: bool = Simulation.phase == Simulation.Phase.IN_ROUND
	# Before the first BURN opens the session an accepted contract is only
	# queued, so the machine would otherwise sit on "idle" as if nothing was
	# selected. Show what is about to be worked instead.
	if job.is_empty() and not working:
		job = Simulation.queued_job_preview()

	_refresh_stage()
	_refresh_rig(job)
	_refresh_status(job, working)
	_refresh_readouts(job, working)
	_refresh_actions(job, working)


## Which machine is on the desk. Hardware bought mid-round changes the artwork on
## the board it was bought for, so the purchase is visible where the work happens.
func _refresh_stage() -> void:
	rig.set_stage(
		AssetCatalog.rig_stage_for_build(Simulation.run_state.build, Simulation.job_slots())
	)


## The visible workstation carries parallel lanes and all physical feedback.
func _refresh_rig(job: Dictionary) -> void:
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	rig.set_heat(
		float(Simulation.run_state.compute.get("heat", 0.0)),
		float(Simulation.run_state.compute.get("heat_capacity", 100.0)),
		float(heat_cfg.get("throttle_ratio", 0.8)),
		bool(Simulation.run_state.flags.get("fire_risk", false))
	)
	rig.set_job(job)
	rig.set_lanes(_supporting_lanes(job))
	rig.hide_meters()
	_danger_vignette.set_alarming(rig.alarm_active())


func _supporting_lanes(focused: Dictionary) -> Array:
	var lanes: Array = []
	var focused_id: String = str(focused.get("id", ""))
	for source in [
		Array(Simulation.run_state.business.get("active_jobs", [])),
		Array(Simulation.run_state.business.get("job_queue", [])),
	]:
		for candidate in source:
			if not candidate is Dictionary:
				continue
			var lane: Dictionary = candidate
			if focused_id != "" and str(lane.get("id", "")) == focused_id:
				continue
			lanes.append(lane)
	return lanes


func _refresh_status(job: Dictionary, working: bool) -> void:
	if job.is_empty():
		_laptop.set_status(
			"nothing on the bench",
			"Take a contract from the job board and it lands here."
		)
		return
	var contract_name: String = str(job.get("name", "contract"))
	var state: String = "ready to burn"
	if float(job.get("tokens_remaining", 0.0)) <= 0.0:
		state = "ready to deliver"
	elif working:
		state = "burning"
	var identity: Dictionary = JobPresentation.sector(job)
	# The contract's name is long enough on its own, so its state goes on the
	# line underneath with the client and the fee rather than beside it.
	_laptop.set_status(
		contract_name,
		"%s · %s · %s\n%s" % [
			state, str(identity["client"]),
			NumberFormat.format_cash(float(job.get("reward", 0.0))),
			_forecast_line(job, Simulation.phase == Simulation.Phase.IN_ROUND),
		]
	)


## Everything the player used to read off instruments bolted to the machine, now
## printed as rows: how much of the contract is burned, how good it is, how long
## is left, how hot the rig is, and what the next batch would do.
func _refresh_readouts(job: Dictionary, working: bool) -> void:
	var heat: float = float(Simulation.run_state.compute.get("heat", 0.0))
	var capacity: float = maxf(1.0, float(Simulation.run_state.compute.get("heat_capacity", 100.0)))
	var heat_ratio: float = heat / capacity
	if job.is_empty():
		_laptop.set_meter("tokens", "burn", 0.0, "no contract")
		_laptop.set_stat("quality", "qual", "--", ConsoleStyle.PHOSPHOR_DIM)
		_laptop.set_stat("time", "time", "--", ConsoleStyle.PHOSPHOR_DIM)
	else:
		var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
		var remaining: float = maxf(0.0, float(job.get("tokens_remaining", 0.0)))
		var burned: float = requirement - remaining
		_laptop.set_meter("tokens", "burn", burned / requirement, "%s / %s" % [
			NumberFormat.format(burned), NumberFormat.format(requirement),
		])
		var quality: float = float(job.get("quality", 0.0))
		var threshold: float = maxf(1.0, float(job.get("quality_threshold", 1.0)))
		var known: int = int(job.get("known_bugs", 0))
		# Bugs share the quality row: they are the same judgement about the same
		# work, and the glass has no line to spare for a number that is usually
		# zero.
		var quality_text: String = "%s of %s" % [
			JobPresentation.quality_mark(quality), JobPresentation.quality_mark(threshold),
		]
		if known > 0:
			quality_text += " · %d bug(s)" % known
		_laptop.set_stat("quality", "qual", quality_text, (
			ConsoleStyle.DANGER if known > 0
			else (ConsoleStyle.PHOSPHOR if quality >= threshold else ConsoleStyle.WARNING)
		))
		var prompts_left: int = maxi(0, int(job.get("prompts_remaining", 0)))
		_laptop.set_stat("time", "time", "%d prompt(s)" % prompts_left, _deadline_color(prompts_left))
	# Redline modules read the rig as a burn starts, not the heat that burn goes
	# on to make, so the player needs to see when they are already in the band
	# those modules are waiting for.
	var heat_text: String = "%d%%" % int(round(heat_ratio * 100.0))
	if heat_ratio >= REDLINE_RATIO:
		heat_text += " redlined"
	_laptop.set_meter("heat", "heat", heat_ratio, heat_text)
	# Cloud bursts are bought a batch at a time out of the same account the rent
	# comes out of, so what is left in it belongs on the deck where the spending
	# happens rather than only on the wall behind the laptop.
	var cash: float = float(Simulation.run_state.economy.get("cash", 0.0))
	_laptop.set_stat(
		"cash",
		"bank",
		NumberFormat.format_cash(cash),
		ConsoleStyle.DANGER if cash < 0.0 else ConsoleStyle.PHOSPHOR
	)
	var keys: Array = ["tokens", "quality", "time", "heat", "cash"]
	keys.append_array(_refresh_lane_rows(job))
	_laptop.prune_stats(keys)


func _deadline_color(prompts_left: int) -> Color:
	if prompts_left <= DEADLINE_DANGER_PROMPTS:
		return ConsoleStyle.DANGER
	if prompts_left <= DEADLINE_WARNING_PROMPTS:
		return ConsoleStyle.WARNING
	return ConsoleStyle.PHOSPHOR


## What the next burn would do, resolved without causing it.
func _forecast_line(job: Dictionary, working: bool) -> String:
	if job.is_empty():
		return "--"
	var preview: Dictionary = Simulation.preview_next_burn()
	if not preview.get("ok", false):
		return str(preview.get("reason", "this pipeline produces nothing"))
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var parts: PackedStringArray = [
		"%s BT ×%.2f +%s%%" % [
			NumberFormat.format(float(preview.get("tokens", 0.0))),
			float(preview.get("progress_mult", 1.0)),
			NumberFormat.format(
				float(preview.get("progress_tokens", 0.0)) / requirement * 100.0
			),
		],
	]
	if int(preview.get("bugs_added", 0)) > 0:
		parts.append("+%db" % int(preview.get("bugs_added", 0)))
	if Simulation.boost_engaged():
		parts.append("boost")
	if Simulation.cloud_engaged():
		parts.append("cloud")
	parts.append(_projected_heat_text(preview))
	return " ".join(parts)


## One row per other machine on the floor. With a single machine there are no
## other lanes and the rows are dropped rather than printed as blanks.
func _refresh_lane_rows(job: Dictionary) -> Array:
	var focused: String = str(job.get("id", ""))
	var keys: Array = []
	var index: int = 1
	for lane in Simulation.burn_lanes():
		if str(lane.get("id", "")) == focused:
			continue
		index += 1
		var key: String = "lane_%d" % index
		keys.append(key)
		var remaining: float = maxf(0.0, float(lane.get("tokens_remaining", 0.0)))
		_laptop.set_stat(
			key,
			"lane %d · %s" % [index, str(lane.get("name", "contract")).to_lower()],
			"%s BT left" % NumberFormat.format(remaining),
			ConsoleStyle.PHOSPHOR_DIM
		)
	return keys


# --- Commands ----------------------------------------------------------------

## The command lines under the readouts. Rebuilt every refresh, because which
## commands the machine will accept is exactly what changes as a round runs.
func _refresh_actions(job: Dictionary, working: bool) -> void:
	var rows: Array = []
	var can_open: bool = Simulation.can_start_work()
	if Simulation.can_burn() or can_open:
		var burn_preview: Dictionary = Simulation.preview_next_burn()
		var projected_kill: bool = _projected_heat_is_lethal(burn_preview)
		rows.append({
			"headline": "BURN",
			"value": _burn_hint(can_open),
			"warning": _projected_heat_is_warning(burn_preview) and not projected_kill,
			"destructive": projected_kill,
			"pressed": _on_burn,
		})
	if working and not job.is_empty():
		rows.append({"headline": "COOL", "value": _cool_hint(), "pressed": _on_cool})
	var armable: bool = working or can_open
	var boosted: bool = Simulation.boost_engaged() or Simulation.queued_boost
	if armable:
		rows.append({
			"headline": "BOOST",
			"value": "engaged" if boosted else "one batch",
			"pressed": _on_boost,
		})
	if FeatureFlags.is_enabled("cloud_compute_enabled") and armable:
		var owned: bool = Simulation.cloud_enabled()
		rows.append({
			"headline": "CLOUD BURST",
			"value": (
				"engaged" if Simulation.cloud_engaged() or Simulation.queued_cloud
				else (NumberFormat.format_cash(Simulation.cloud_burst_cost()) if owned else "no account")
			),
			"pressed": _on_cloud,
		})
	if not job.is_empty():
		var complete: bool = float(job.get("tokens_remaining", 0.0)) <= 0.0
		if working:
			rows.append({
				"headline": "DELIVER",
				"value": "ready" if complete else "at %d%%" % _done_percent(job),
				"destructive": not complete,
				"pressed": _on_deliver,
			})
		rows.append({"headline": "JOB", "value": "the brief", "pressed": _on_job_details})
	rows.append({
		"headline": "EDIT PIPELINE",
		# Terse on purpose: the commands print two across, and "3 of 3 placed"
		# is wider than half a laptop.
		"value": "%d/%d" % [
			Simulation.filled_slot_count(), Simulation.owned_modules().size(),
		],
		"pressed": _on_edit_pipeline,
	})
	rows.append_array(_focus_rows(job))
	rows.append_array(_workflow_rows(job))
	_laptop.set_actions(rows)


func _burn_hint(can_open: bool) -> String:
	var preview: Dictionary = Simulation.preview_next_burn()
	if not preview.get("ok", false):
		return "start the round" if can_open else ""
	var costs: PackedStringArray = []
	costs.append(_projected_heat_text(preview))
	if float(preview.get("cost", 0.0)) > 0.0:
		costs.append(NumberFormat.format_cash(float(preview.get("cost", 0.0))))
	return " \u00b7 ".join(costs)


## The exact next-burn heat projection is visible even before a session starts.
func _projected_heat_text(preview: Dictionary) -> String:
	var capacity: float = maxf(1.0, float(preview.get("heat_capacity", 100.0)))
	var before_ratio: float = float(preview.get("heat_before", 0.0)) / capacity
	var after_ratio: float = float(preview.get("heat_ratio_after", before_ratio))
	var text: String = "HEAT %d%% \u2192 %d%%" % [
		int(round(before_ratio * 100.0)), int(round(after_ratio * 100.0)),
	]
	var label: String = str(preview.get("heat_state_label", ""))
	if label == "":
		label = HeatSystem.heat_state_label(str(preview.get("heat_state", "")))
	if label != "":
		return "%s \u00b7 %s" % [text, label]
	return text


func _projected_heat_is_lethal(preview: Dictionary) -> bool:
	var state: String = str(preview.get("heat_state", ""))
	return (
		state == HeatSystem.HEAT_FIRE
		or state == HeatSystem.HEAT_CATASTROPHE
		or bool(preview.get("crosses_catastrophe", preview.get("crosses_fire", false)))
	)


func _projected_heat_is_warning(preview: Dictionary) -> bool:
	var state: String = str(preview.get("heat_state", ""))
	return state in [
		HeatSystem.HEAT_THROTTLE,
		HeatSystem.HEAT_UNSTABLE,
		HeatSystem.HEAT_REDLINE,
		HeatSystem.HEAT_FIRE_RISK,
	]


func _cool_hint() -> String:
	var preview: Dictionary = Simulation.preview_cool()
	if not preview.get("ok", false):
		return ""
	var delta: float = float(preview.get("total_heat", 0.0))
	if absf(delta) < 0.5:
		return "no change"
	return "%+d heat" % int(round(delta))


## Moving the pipeline onto a different contract between prompts. Only printed
## when there is more than one contract it could be on.
func _focus_rows(job: Dictionary) -> Array:
	var rows: Array = []
	var candidates: Array = []
	for candidate in Simulation.run_state.business.get("active_jobs", []):
		if not candidate is Dictionary:
			continue
		if float(candidate.get("tokens_remaining", 0.0)) <= 0.0:
			continue
		if int(candidate.get("prompts_remaining", 0)) < 0:
			continue
		candidates.append(candidate)
	if candidates.size() < 2:
		return rows
	for candidate in candidates:
		var job_id: String = str(candidate.get("id", ""))
		if job_id == str(job.get("id", "")):
			continue
		rows.append({
			"headline": "FOCUS %s" % str(candidate.get("name", "contract")).to_upper(),
			"value": "%dp left" % maxi(0, int(candidate.get("prompts_remaining", 0))),
			"pressed": _on_focus.bind(job_id),
		})
	return rows


func _on_focus(job_id: String) -> void:
	if Simulation.focus_job(job_id):
		refresh()


## Routing the focused contract through a different workflow. Only printed once
## the run owns more than one, since with a single pipeline there is no choice.
func _workflow_rows(job: Dictionary) -> Array:
	var rows: Array = []
	if job.is_empty():
		return rows
	var matches: Array = Simulation.workflow_matches(job)
	if matches.size() < 2:
		return rows
	var assigned_id: String = str(job.get("workflow_id", ""))
	var job_id: String = str(job.get("id", ""))
	for match_report in matches:
		var workflow_id: String = str(match_report.get("workflow_id", ""))
		if workflow_id == assigned_id:
			continue
		rows.append({
			"headline": "USE %s" % str(match_report.get("name", "workflow")).to_upper(),
			"value": JobPresentation.match_summary(match_report).to_lower(),
			"pressed": _on_assign_workflow.bind(job_id, workflow_id),
		})
	return rows


func _on_assign_workflow(job_id: String, workflow_id: String) -> void:
	if Simulation.assign_workflow(job_id, workflow_id):
		refresh()


func _done_percent(job: Dictionary) -> int:
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var remaining: float = maxf(0.0, float(job.get("tokens_remaining", 0.0)))
	return int(round((1.0 - remaining / requirement) * 100.0))


# --- Arranging ---------------------------------------------------------------

func _on_edit_pipeline() -> void:
	if _burning:
		return
	SceneRouter.open_workflows()


## The brief, in full. The console prints the facts a decision needs every
## prompt; this is the prose, the rules and the reasoning behind each demand,
## which is read once when the contract lands and then not again.
func _on_job_details() -> void:
	if _burning:
		return
	var job: Dictionary = Simulation.focused_job()
	if job.is_empty():
		# The brief is readable before the session opens too.
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
		{
			"stat": "Reward",
			"value": NumberFormat.format_cash(float(job.get("reward", 0.0))),
			"role": "money",
		},
		{
			"stat": "Tokens",
			"value": "%s BT" % NumberFormat.format(
				float(job.get("token_requirement", 0.0))
			),
		},
		{"stat": "Progress", "value": "%d%%" % _done_percent(job)},
		{
			"stat": "Quality",
			"value": "%s ×%.2f" % [
				JobPresentation.quality_against_bar(
					float(job.get("quality", 0.0)),
					float(job.get("quality_threshold", 0.0))
				),
				JobSystem.quality_payout_multiplier(
					float(job.get("quality", 0.0)),
					float(job.get("quality_threshold", 0.0))
				),
			],
			"role": "energy",
		},
		{"stat": "Prompts left", "value": str(prompts_left), "role": deadline_role},
		{"stat": "Known bugs", "value": str(int(job.get("known_bugs", 0)))},
	])
	_detail_sheet.show_detail(
		str(job.get("name", "Contract")),
		"%s · %s" % [str(identity["label"]), str(identity["client"])],
		rows,
		[],
		"",
		identity["color"]
	)
	# The sheet is shared with DELIVER, so last opening's decision has to go
	# before this one is shown as a read-only brief.
	_clear_sheet_handlers()


# --- Burning -----------------------------------------------------------------

func _on_burn() -> void:
	if _burning:
		return
	# The first press of the round is what opens the session: taking a contract
	# puts you at the machine, and the machine is started by using it.
	if not Simulation.is_work_running() and Simulation.can_start_work():
		Simulation.start_work()
		refresh()
	if not Simulation.can_burn():
		return
	var preview: Dictionary = Simulation.preview_burn()
	if not preview.get("ok", false):
		_laptop.set_status("nothing to burn", str(preview.get("reason", "")))
		return
	UiSound.play("burn")
	_burning = true
	_kill_requested = false
	_skip_requested = false
	_stages_completed = 0
	_proc_depth = 0
	# KILL aborts the remaining stages. SKIP (and tapping the headline) keeps
	# the full batch and just drops the rest of the show.
	_laptop.set_actions([
		{
			"headline": "KILL", "value": "stop the batch", "destructive": true,
			"pressed": _on_kill,
		},
		{"headline": "SKIP", "value": "see the result", "pressed": _on_skip},
	])
	_laptop.set_status_pressed(_on_skip)
	await _animate_batch(preview)
	_laptop.set_status_pressed(Callable())
	var stage_limit: int = _stages_completed if _kill_requested else -1
	_burning = false
	Simulation.burn_batch(stage_limit)
	refresh()


## Walks the batch as a cascade of beats. Ordinary stages fly past; named
## combos, perks and forks hold. KILL discards the current stage; SKIP lands
## the whole batch immediately.
func _animate_batch(preview: Dictionary) -> void:
	var job: Dictionary = Simulation.focused_job()
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var burned_before: float = maxf(
		0.0, requirement - maxf(0.0, float(job.get("tokens_remaining", 0.0)))
	)
	var beats: Array = preview.get("spectacle", [])
	if beats.is_empty():
		beats = BurnSpectacle.compile(preview, [])
	_laptop.set_status("×1.00", "burning")
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


func _present_beat(beat: Dictionary, job: Dictionary, requirement: float, burned_before: float) -> void:
	var kind: String = str(beat.get("kind", BurnSpectacle.KIND_STAGE))
	var loud: bool = bool(beat.get("loud", false))
	var progress_mult: float = float(beat.get("progress_mult", 1.0))
	var label: String = str(beat.get("label", "")).to_upper()
	if kind == BurnSpectacle.KIND_FINAL:
		_laptop.set_status(
			"%s BT" % NumberFormat.format(float(beat.get("tokens", 0.0))),
			label
		)
	else:
		_laptop.set_status("×%.2f" % progress_mult, label.to_lower())
	if not job.is_empty():
		var burned: float = burned_before + float(beat.get("tokens", 0.0))
		_laptop.set_meter("tokens", "burn", clampf(burned / requirement, 0.0, 1.0), "%s / %s" % [
			NumberFormat.format(minf(burned, requirement)), NumberFormat.format(requirement),
		])
	var shake: float = 10.0 if loud else 4.0
	rig.shake(shake)
	if loud:
		rig.flash_screen("energy")
		rig.push_line(label, "energy")
		UiSound.play("combo" if kind != BurnSpectacle.KIND_FINAL else "complete")
	else:
		UiSound.play_proc(_proc_depth)
	if loud:
		_proc_depth += 1
	_pulse_beat_heat(beat)


func _fast_forward(
	beats: Array, current: Dictionary, job: Dictionary, requirement: float, burned_before: float
) -> void:
	var last: Dictionary = current
	for beat in beats:
		if not beat is Dictionary:
			continue
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


func _pulse_beat_heat(beat: Dictionary) -> void:
	if absf(float(beat.get("heat", 0.0))) <= 0.5:
		return
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	var projected: float = maxf(
		0.0,
		float(Simulation.run_state.compute.get("heat", 0.0)) + float(beat.get("heat", 0.0))
	)
	rig.set_heat(
		projected,
		float(Simulation.run_state.compute.get("heat_capacity", 100.0)),
		float(heat_cfg.get("throttle_ratio", 0.8)),
		bool(Simulation.run_state.flags.get("fire_risk", false))
	)


func _on_kill() -> void:
	_kill_requested = true
	_laptop.set_status(
		"killed", "^C after %d stage(s). The rest of the batch is discarded." % _stages_completed
	)


func _on_skip() -> void:
	if not _burning or _kill_requested:
		return
	_skip_requested = true


func _on_boost() -> void:
	if _burning:
		return
	if Simulation.boost():
		refresh()
		return
	# The session has not opened yet — queue it, so the first prompt gets the
	# surge the moment BURN starts the round.
	if Simulation.can_start_work() and not Simulation.queued_boost:
		Simulation.set_queued_boost(true)
		refresh()


func _on_cloud() -> void:
	if _burning:
		return
	if Simulation.cloud_burst():
		refresh()
		return
	if Simulation.can_start_work() and Simulation.cloud_enabled() and not Simulation.queued_cloud:
		Simulation.set_queued_cloud(true)
		refresh()


func _on_cool() -> void:
	if _burning:
		return
	Simulation.cool_hardware()
	refresh()


## Both ways a contract can end, on one sheet. A finished contract is a formality
## and could have shipped on the tap, but routing it through the same sheet means
## the reward and the bug count are on screen when the decision is made, and
## walking away stops being a single unguarded tap.
func _on_deliver() -> void:
	if _burning:
		return
	var job: Dictionary = Simulation.focused_job()
	if job.is_empty():
		return
	var done_pct: int = _done_percent(job)
	var complete: bool = float(job.get("tokens_remaining", 0.0)) <= 0.0
	var rows: Array = [
		{
			"text": (
				"The contract is finished. Hidden bugs are still rolled on delivery."
				if complete
				else "Shipping now delivers the contract as-is. Hidden bugs may surface and reputation can take a hit."
			),
		},
		{"stat": "Progress", "value": "%d%%" % done_pct},
		{"stat": "Reward", "value": NumberFormat.format_cash(float(job.get("reward", 0.0)))},
		{
			"stat": "Quality pay",
			# Shipping unfinished scales the delivered quality down with the
			# progress, so the sheet quotes what delivering now would actually
			# earn rather than what the meter reads.
			"value": "×%.2f" % JobSystem.quality_payout_multiplier(
				float(job.get("quality", 0.0)) * (1.0 if complete else float(done_pct) / 100.0),
				float(job.get("quality_threshold", 0.0))
			),
			"role": "energy",
		},
		{"stat": "Known bugs", "value": str(int(job.get("known_bugs", 0)))},
		{"stat": "Prompts left", "value": str(int(job.get("prompts_remaining", 0)))},
	]
	var early_bonus: float = JobSystem.early_delivery_bonus(job)
	if complete and early_bonus > 0.0:
		rows.append({
			"stat": "Early bonus",
			"value": "+%d%%" % int(round(early_bonus * 100.0)),
			"role": "money",
		})
	rows.append({"text": "Abandoning costs no fee, but takes the reputation hit of a missed contract."})
	_detail_sheet.show_detail(
		str(job.get("name", "Contract")),
		"Deliver or walk away",
		rows,
		[],
		"SHIP IT" if complete else "SHIP AT %d%%" % done_pct,
		UiThemeBuilder.semantic("money" if complete else "warning"),
		"ABANDON"
	)
	_clear_sheet_handlers()
	_detail_sheet.action_confirmed.connect(func() -> void:
		Simulation.ship_focused_job()
		refresh()
	)
	_detail_sheet.secondary_confirmed.connect(func() -> void:
		Simulation.abandon_focused_job()
		refresh()
	)


## The sheet is reused for every contract, so last contract's handlers have to go
## before this one's are attached.
func _clear_sheet_handlers() -> void:
	for signal_ref in [_detail_sheet.action_confirmed, _detail_sheet.secondary_confirmed]:
		for connection in signal_ref.get_connections():
			signal_ref.disconnect(connection["callable"])
