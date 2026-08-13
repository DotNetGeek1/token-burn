extends Control

## The Burn Board: the work screen, printed on the laptop standing on the desk.
##
## The laptop is the machine the operation is run from, so a burn is reported and
## driven from the same piece of glass as everything else: the contract's
## progress, quality, deadline and heat are printed rows, and BURN, COOL, the
## surges and DELIVER are command lines under them. There is no keyboard deck and
## no contract plate — a batch is started by typing on the machine, and the
## investor's terms live on the whiteboard.
##
## The rig art stays behind the laptop as dressing. It is what makes a burn feel
## like hardware being worked: the tower glows, the case shakes, smoke and fire
## come off it as the heat climbs and the beacon spins when it is about to cook
## itself. Its own screen and instruments are hidden — there is one screen in
## this room and the laptop is it.

## How long each pipeline stage holds on the console during a batch. Long
## enough to read the stage's own line before the next one prints over it —
## the batch is the show, not a loading bar.
const STAGE_SECONDS := 0.9

## Prompts left at which the deadline stops reading as time in hand.
const DEADLINE_WARNING_PROMPTS := 3
const DEADLINE_DANGER_PROMPTS := 1

## How far the rig art spreads past the laptop, as a fraction of the window. The
## machine has to read as standing on the same desk rather than as a picture
## pinned behind the screen.
const RIG_BLEED := Vector2(0.10, 0.06)

@onready var rig: BurnRig = $Rig

var _laptop: LaptopScreen = null
var _burning: bool = false
var _kill_requested: bool = false
var _stages_completed: int = 0
var _detail_sheet: ConsoleSheet = null
var _danger_vignette: DangerVignette = null


func _ready() -> void:
	add_to_group("ui_refresh")
	# The shell re-lays the room out whenever the operation moves premises, and
	# both the laptop and the machine behind it are furniture in that room.
	add_to_group("board_mounted")
	_danger_vignette = DangerVignette.mount(self)
	_detail_sheet = ConsoleSheet.new()
	_laptop = LaptopScreen.new()
	_laptop.name = "Laptop"
	add_child(_laptop)
	_laptop.setup("burn")
	_mount_sheet(_detail_sheet)
	# The rig is scenery here, so it gives up every readout it used to own.
	rig.set_dressing_only(true)
	rig.set_lanes([])
	relayout_on_board()
	Simulation.work_tick_completed.connect(refresh)
	Simulation.work_session_finished.connect(func(_result): refresh())
	EventBus.operation_acquired.connect(func(_id): refresh())
	refresh()


# --- Mounting ----------------------------------------------------------------

## Anchors the console onto the blank screen of the laptop in the current room,
## and stands the rig art on the desk behind it.
func relayout_on_board() -> void:
	if _laptop == null:
		return
	var dwelling: String = _board_dwelling()
	var column: Rect2 = AssetCatalog.board_region(dwelling, "work_column")
	var screen: Rect2 = AssetCatalog.board_laptop_screen(dwelling)
	var glass: Rect2 = AssetCatalog.board_rect_in_region(column, screen)
	if glass.size.x <= 0.0:
		glass = Rect2(0.30, 0.30, 0.40, 0.45)
	_anchor(_laptop, glass)
	_anchor(rig, Rect2(
		maxf(0.0, glass.position.x - RIG_BLEED.x),
		maxf(0.0, glass.position.y - RIG_BLEED.y),
		minf(1.0, glass.size.x + RIG_BLEED.x * 2.0),
		minf(1.0, glass.size.y + RIG_BLEED.y)
	))


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


## Heat is the only reading the rig still takes, because heat is what makes it
## smoke, catch fire and set off its beacon.
func _refresh_rig(job: Dictionary) -> void:
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	rig.set_heat(
		float(Simulation.run_state.compute.get("heat", 0.0)),
		float(Simulation.run_state.compute.get("heat_capacity", 100.0)),
		float(heat_cfg.get("throttle_ratio", 0.8)),
		bool(Simulation.run_state.flags.get("fire_risk", false))
	)
	rig.set_job(job)
	rig.hide_meters()
	_danger_vignette.set_alarming(rig.alarm_active())


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
	_laptop.set_meter("heat", "heat", heat_ratio, "%d%%" % int(round(heat_ratio * 100.0)))
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
	if not working:
		return "press burn to start the round"
	var preview: Dictionary = Simulation.preview_burn()
	if not preview.get("ok", false):
		return str(preview.get("reason", "this pipeline produces nothing"))
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var parts: PackedStringArray = [
		"%s BT ×%.2f +%d%%" % [
			NumberFormat.format(float(preview.get("tokens", 0.0))),
			float(preview.get("progress_mult", 1.0)),
			int(round(float(preview.get("progress_tokens", 0.0)) / requirement * 100.0)),
		],
	]
	if int(preview.get("bugs_added", 0)) > 0:
		parts.append("+%db" % int(preview.get("bugs_added", 0)))
	if Simulation.boost_engaged():
		parts.append("boost")
	if Simulation.cloud_engaged():
		parts.append("cloud")
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
		rows.append({
			"headline": "BURN", "value": _burn_hint(can_open), "pressed": _on_burn,
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
			Simulation.filled_slot_count(), Simulation.owned_operations().size(),
		],
		"pressed": _on_edit_pipeline,
	})
	rows.append_array(_focus_rows(job))
	rows.append_array(_workflow_rows(job))
	_laptop.set_actions(rows)


func _burn_hint(can_open: bool) -> String:
	if can_open and not Simulation.is_work_running():
		return "start the round"
	var preview: Dictionary = Simulation.preview_burn()
	if not preview.get("ok", false):
		return ""
	var costs: PackedStringArray = []
	var total_heat: float = float(preview.get("total_heat", preview.get("heat", 0.0)))
	if absf(total_heat) >= 0.5:
		costs.append("heat %+d" % int(round(total_heat)))
	if float(preview.get("cost", 0.0)) > 0.0:
		costs.append(NumberFormat.format_cash(float(preview.get("cost", 0.0))))
	return " · ".join(costs)


## COOL vents a share of current heat, but the ambient gain from powered-on
## hardware lands the same prompt regardless — so the row shows the net result,
## or a big vent on a hot rig with weak cooling can look like it did nothing.
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
	_stages_completed = 0
	# KILL takes the whole command list for the duration of the batch, so the
	# only thing the player can do mid-burn is stop it.
	_laptop.set_actions([{
		"headline": "KILL", "value": "stop the batch", "destructive": true,
		"pressed": _on_kill,
	}])
	await _animate_batch(preview)
	var stage_limit: int = _stages_completed if _kill_requested else -1
	_burning = false
	Simulation.burn_batch(stage_limit)
	refresh()


## Walks the batch down the pipeline one stage at a time, showing what each
## stage added. This is also the window in which KILL can land.
func _animate_batch(preview: Dictionary) -> void:
	var stages: Array = preview.get("stages", [])
	var job: Dictionary = Simulation.focused_job()
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var intensity: float = float(preview.get("progress_tokens", 0.0)) / requirement
	_laptop.set_status(
		"burning %s BT" % NumberFormat.format(float(preview.get("tokens", 0.0))),
		"%d stage(s) down the pipeline." % stages.size()
	)
	for stage in stages:
		if _kill_requested:
			return
		# The batch is reported a stage at a time: a line on the console, and a
		# thump on the machine behind it.
		_laptop.set_status(
			"burning %s BT" % NumberFormat.format(float(preview.get("tokens", 0.0))),
			"%s: %s" % [str(stage.get("name", "stage")).to_lower(), _stage_summary(stage)]
		)
		rig.shake(4.0 + intensity * 6.0)
		_pulse_stage_heat(stage)
		await get_tree().create_timer(STAGE_SECONDS).timeout
		# Counted after the wait, so a kill during a stage discards that stage.
		if _kill_requested:
			return
		_stages_completed += 1


## Heat moves during a burn, so the rig smokes as each stage lands instead of
## only reacting once the batch is committed.
func _pulse_stage_heat(stage: Dictionary) -> void:
	var before: Dictionary = stage.get("before", {})
	var after: Dictionary = stage.get("after", {})
	if absf(float(after.get("heat", 0.0)) - float(before.get("heat", 0.0))) <= 0.5:
		return
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	# The batch is still being animated, so none of its heat has reached the rig
	# yet: this shows where the rig will be once the stages so far land.
	var projected: float = maxf(
		0.0,
		float(Simulation.run_state.compute.get("heat", 0.0)) + float(after.get("heat", 0.0))
	)
	rig.set_heat(
		projected,
		float(Simulation.run_state.compute.get("heat_capacity", 100.0)),
		float(heat_cfg.get("throttle_ratio", 0.8)),
		bool(Simulation.run_state.flags.get("fire_risk", false))
	)


func _stage_summary(stage: Dictionary) -> String:
	var before: Dictionary = stage.get("before", {})
	var after: Dictionary = stage.get("after", {})
	var parts: PackedStringArray = []
	var progress_delta: float = float(after.get("progress_mult", 1.0)) / maxf(0.01, float(before.get("progress_mult", 1.0)))
	if absf(progress_delta - 1.0) > 0.01:
		parts.append("×%.2f progress" % progress_delta)
	var quality_delta: float = float(after.get("quality", 0.0)) - float(before.get("quality", 0.0))
	if absf(quality_delta) > 0.5:
		parts.append("%s%s quality" % [
			"+" if quality_delta > 0.0 else "-",
			JobPresentation.quality_mark(absf(quality_delta)),
		])
	var bug_delta: float = float(after.get("known_bugs", 0.0)) - float(before.get("known_bugs", 0.0))
	if absf(bug_delta) > 0.4:
		parts.append("%+d bug(s)" % int(round(bug_delta)))
	var heat_delta: float = float(after.get("heat", 0.0)) - float(before.get("heat", 0.0))
	if absf(heat_delta) > 0.5:
		parts.append("%+d heat" % int(round(heat_delta)))
	if float(stage.get("repeated_previous", 0.0)) > 0.0:
		parts.append("repeated the stage above")
	if parts.is_empty():
		return "no change"
	return ", ".join(parts)


func _on_kill() -> void:
	_kill_requested = true
	_laptop.set_status(
		"killed", "^C after %d stage(s). The rest of the batch is discarded." % _stages_completed
	)


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
