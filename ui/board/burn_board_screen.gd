extends Control

## The Burn Board: the work screen.
##
## The rig *is* the screen. Batch output streams down its terminal, heat swings
## its needle, quality and deadline are instruments bolted to its case, and it
## smokes, catches fire and sets off a beacon as the hardware is pushed. The
## pipeline composition and the round log are printed on the terminal too, so
## nothing about the work is reported in a list beside the machine.
##
## Bolted to the bottom of the rig is its keyboard: BURN is the enter key, the
## surges and the vent are caps beside it, and JOB, EDIT and DELIVER sit in a
## function row above. Arranging modules into slots happens in the dedicated
## pipeline editor, which has room for an explicit selection model.
##
## The contract has no plate of its own. A panel of prose above the machine was the
## single biggest thing on a phone screen and it described work the machine was
## already reporting, so the brief is printed on the terminal as the job is loaded
## and the whole brief opens on the JOB key. What is left is two parts of one
## assembly — the bay and the deck it stands on — sharing a single outline, so the
## board reads as a machine on a desk rather than as a header, a picture and a form.

const DETAIL_SHEET := preload("res://ui/common/detail_sheet.tscn")

const STAGE_SECONDS := 0.45

## Prompts left at which the deadline stops reading as time in hand.
const DEADLINE_WARNING_PROMPTS := 3
const DEADLINE_DANGER_PROMPTS := 1

const STRIPS := "Panel/VBox/Strips/StripVBox"

@onready var panel: PanelContainer = $Panel
## Holds the strips that only some runs ever see. Hidden as a whole when they all
## are, or its inset would leave a band of nothing above the machine.
@onready var strips: MarginContainer = $Panel/VBox/Strips
@onready var ascension_tracker: PanelContainer = get_node(STRIPS + "/AscensionTracker")
@onready var ascension_burn_bar: ResourceBar = get_node(
	STRIPS + "/AscensionTracker/AscensionMargin/AscensionVBox/AscensionBurnBar"
)
@onready var ascension_status_label: Label = get_node(
	STRIPS + "/AscensionTracker/AscensionMargin/AscensionVBox/AscensionStatusLabel"
)
@onready var rig: BurnRig = $Panel/VBox/Machine/Rig
@onready var deck: KeyboardDeck = $Panel/VBox/Machine/Deck
@onready var job_key: GameButton = deck.job_key
@onready var edit_key: GameButton = deck.edit_key
@onready var deliver_key: GameButton = deck.deliver_key
@onready var burn_key: GameButton = deck.burn_key
@onready var cool_key: GameButton = deck.cool_key
@onready var kill_key: GameButton = deck.kill_key
@onready var boost_key: GameButton = deck.boost_key
@onready var cloud_key: GameButton = deck.cloud_key
@onready var focus_row: HBoxContainer = get_node(STRIPS + "/FocusRow")
@onready var workflow_row: HBoxContainer = get_node(STRIPS + "/WorkflowRow")

var _burning: bool = false
var _kill_requested: bool = false
var _stages_completed: int = 0
var _detail_sheet: DetailSheet = null
## Job the rig terminal is currently reporting on, so the banner is reprinted
## when the player moves the pipeline to a different contract rather than on
## every refresh.
var _terminal_job_id: String = ""
var _terminal_booted: bool = false
## Composition the terminal last printed, so a rearranged pipeline reprints its
## listing while an unchanged one does not spam the log on every refresh.
var _terminal_pipeline: String = ""
## Verdict the terminal last printed on the contract's demands, for the same
## reason: a demand that has just been answered is news, an unchanged one is not.
var _terminal_demands: String = ""
## How much of `Simulation.round_log` has already reached the terminal. Only the
## new tail is pushed, so cooling and events read as output arriving.
var _log_cursor: int = 0
var _danger_vignette: DangerVignette = null


func _ready() -> void:
	add_to_group("ui_refresh")
	_style_console()
	_danger_vignette = DangerVignette.mount(self)
	_detail_sheet = DETAIL_SHEET.instantiate()
	add_child(_detail_sheet)
	burn_key.pressed.connect(_on_burn)
	cool_key.pressed.connect(_on_cool)
	kill_key.pressed.connect(_on_kill)
	boost_key.pressed.connect(_on_boost)
	cloud_key.pressed.connect(_on_cloud)
	deliver_key.pressed.connect(_on_deliver)
	edit_key.pressed.connect(_on_edit_pipeline)
	job_key.pressed.connect(_on_job_details)
	Simulation.work_tick_completed.connect(refresh)
	Simulation.work_session_finished.connect(func(_result): refresh())
	EventBus.operation_acquired.connect(func(_id): refresh())
	refresh()


## The console owns the only frame on this screen. The board panel behind it drops
## its own border and fill so the office backdrop reads as the desk the machine is
## standing on; the bay and the deck bring their own case colour.
func _style_console() -> void:
	var bare := StyleBoxFlat.new()
	bare.bg_color = Color(0, 0, 0, 0)
	panel.add_theme_stylebox_override("panel", bare)


func refresh() -> void:
	if _burning:
		return
	var job: Dictionary = Simulation.focused_job()
	var working: bool = Simulation.phase == Simulation.Phase.IN_ROUND

	_refresh_stage()
	_refresh_ascension_tracker()
	_refresh_bars(job)
	_refresh_terminal(job, working)
	_refresh_pipeline_listing()
	_refresh_demands(job)
	_refresh_round_log()
	_refresh_lanes(job)
	_refresh_forecast(job)
	_refresh_actions(job, working)
	_refresh_focus_row(job)
	_refresh_workflow_row(job)
	strips.visible = (
		ascension_tracker.visible or focus_row.visible or workflow_row.visible
	)


## Which machine is on the desk. Hardware bought mid-round changes the artwork on
## the board it was bought for, so the purchase is visible where the work happens.
func _refresh_stage() -> void:
	rig.set_stage(
		AssetCatalog.rig_stage_for_build(Simulation.run_state.build, Simulation.job_slots())
	)


## The other machines' contracts, on the other monitors the artwork was drawn with.
## The focused contract owns the terminal, so these are the lanes beside it.
func _refresh_lanes(job: Dictionary) -> void:
	var focused: String = str(job.get("id", ""))
	var others: Array = []
	for lane in Simulation.burn_lanes():
		if str(lane.get("id", "")) != focused:
			others.append(lane)
	rig.set_lanes(others)


## The verdict on the pipeline this contract is being worked through, printed on
## the terminal so an unmet demand is visible before the burn rather than in the
## log afterwards. Names only: the reasoning is long enough to need the sheet, and
## a terminal that scrolls its own explanation away is no better than a panel.
func _refresh_demands(job: Dictionary) -> void:
	var lines: Array = []
	for rule in Array(job.get("board_rules", [])):
		if rule is Dictionary and str(rule.get("label", "")) != "":
			lines.append(["· %s" % str(rule["label"]).to_lower(), "grey"])
	for demand in Simulation.job_demands(job):
		var met: bool = bool(demand.get("met", false))
		lines.append([
			"%s %s" % ["✓" if met else "✗", str(demand.get("name", "demand")).to_lower()],
			"success" if met else "warning",
		])
	var known: int = int(job.get("known_bugs", 0))
	if known > 0:
		lines.append(["! %d known bug(s) on delivery" % known, "danger"])
	var signature: String = "|".join(lines.map(func(line: Array) -> String: return str(line[0])))
	if signature == _terminal_demands:
		return
	_terminal_demands = signature
	for line in lines:
		rig.push_line(str(line[0]), str(line[1]))


## The Final Burn keeps ordinary contracts flowing, so the requirement
## tracker sits above them as its own always-visible strip instead of
## replacing the job bars.
func _refresh_ascension_tracker() -> void:
	if not Simulation.ascension_active():
		ascension_tracker.visible = false
		return
	var progress: Dictionary = Simulation.ascension_progress()
	if progress.is_empty():
		ascension_tracker.visible = false
		return
	ascension_tracker.visible = true
	var contract: Dictionary = progress.get("contract", {})
	var burned: float = float(progress.get("tokens_burned", 0.0))
	var total: float = maxf(1.0, float(progress.get("total_burn", 1.0)))
	ascension_burn_bar.setup(
		"FINAL BURN · %s" % str(contract.get("name", "Ascension Contract")).to_upper(),
		burned,
		total,
		"tokens",
		"%s / %s tokens" % [NumberFormat.format(burned), NumberFormat.format(total)]
	)
	var violations: int = int(progress.get("violations", 0))
	var max_violations: int = int(progress.get("max_failed_burns", 0))
	var prompts_left: int = int(progress.get("prompts_remaining", 0))
	ascension_status_label.text = "%d prompt(s) left · %d/%d violation(s) tolerated · %s" % [
		maxi(0, prompts_left),
		violations,
		max_violations,
		"the finish line" if bool(progress.get("is_final", false)) else "a level-up, not the end",
	]
	ascension_status_label.add_theme_color_override(
		"font_color",
		UiThemeBuilder.semantic("danger" if violations >= max_violations else "warning")
	)


func _refresh_bars(job: Dictionary) -> void:
	var has_job: bool = not job.is_empty()
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	var heat: float = float(Simulation.run_state.compute.get("heat", 0.0))
	var capacity: float = float(Simulation.run_state.compute.get("heat_capacity", 100.0))
	var throttle: float = float(heat_cfg.get("throttle_ratio", 0.8))
	rig.set_heat(
		heat,
		capacity,
		throttle,
		bool(Simulation.run_state.flags.get("fire_risk", false))
	)
	rig.set_job(job)
	_danger_vignette.set_alarming(rig.alarm_active())
	if not has_job:
		rig.hide_meters()
		return
	var quality: float = float(job.get("quality", 0.0))
	var threshold: float = float(job.get("quality_threshold", 1.0))
	rig.set_meters(
		quality,
		maxf(1.0, threshold),
		int(job.get("prompts_remaining", 0)),
		int(job.get("deadline_prompts", 1)),
		# Raw against target, because that is what fits in the instrument's engraved
		# window. The fee the polish is currently earning — which keeps climbing past
		# the threshold rather than stopping — is on the JOB sheet, where there is
		# room to print it.
		"%d/%d" % [int(round(quality)), int(round(threshold))]
	)


## The pipeline is printed on the terminal rather than listed beside it, which is
## what the machine would actually show and what frees the board of a scrolling
## list. Reprinted only when the composition changes.
func _refresh_pipeline_listing() -> void:
	var board_slots: Array = Simulation.board_slots()
	var signature: String = "|".join(board_slots.map(func(entry) -> String: return str(entry)))
	if signature == _terminal_pipeline:
		return
	_terminal_pipeline = signature
	rig.push_line(
		"$ pipeline · %d/%d modules" % [
			Simulation.filled_slot_count(), board_slots.size(),
		],
		"grey"
	)
	for index in range(board_slots.size()):
		var module: String = str(board_slots[index])
		if module == "":
			rig.push_line("  [%d] --" % (index + 1), "grey")
		else:
			rig.push_line("  [%d] %s" % [index + 1, module.to_lower()], "compute")


## Pushes only round-log entries the terminal has not seen. Cooling and events
## are printed by the simulation into that log, so this is how they reach the
## machine now the separate log label is gone.
func _refresh_round_log() -> void:
	var entries: Array = Simulation.round_log
	# A fresh run restarts the log, so a shorter log means "start over" rather
	# than "nothing new".
	if entries.size() < _log_cursor:
		_log_cursor = 0
	while _log_cursor < entries.size():
		rig.push_line("· %s" % str(entries[_log_cursor]), "grey")
		_log_cursor += 1


## Reprints the terminal banner when the pipeline moves to a different contract.
## Between those moments the terminal belongs to the burn animation, so refreshes
## must not wipe what a batch just reported.
##
## The banner is also the contract header now that the plate is gone: what the job
## needs, what it pays and who it is for, in the three lines a machine loading a
## job would print. The prose behind it is on the JOB key.
func _refresh_terminal(job: Dictionary, working: bool) -> void:
	var job_id: String = str(job.get("id", ""))
	if _terminal_booted and job_id == _terminal_job_id:
		return
	_terminal_booted = true
	_terminal_job_id = job_id
	if job.is_empty():
		rig.boot(
			"idle",
			"waiting for work" if working else "no round running"
		)
		if not working:
			rig.push_line("take a contract, then start work", "grey")
	else:
		rig.boot(
			str(job.get("name", "contract")).to_lower(),
			"%s BT · %s · due %dp" % [
				NumberFormat.format(float(job.get("token_requirement", 0.0))),
				NumberFormat.format_cash(float(job.get("reward", 0.0))),
				maxi(0, int(job.get("prompts_remaining", 0))),
			]
		)
		var identity: Dictionary = JobPresentation.sector(job)
		rig.push_line(
			"for %s · %s" % [
				str(identity["client"]).to_lower(), str(identity["label"]).to_lower()
			],
			"grey"
		)
	rig.flush_lines()
	# The banner wiped the screen, so the listing and the verdict have to print
	# again underneath it, and the log resumes from here rather than replaying the
	# round's history.
	_terminal_pipeline = ""
	_terminal_demands = ""
	_log_cursor = Simulation.round_log.size()


## What the next burn would do, resolved without causing it. The rig's throughput
## readout carries it, since that is where the player is already looking.
func _refresh_forecast(job: Dictionary) -> void:
	if job.is_empty() or Simulation.phase != Simulation.Phase.IN_ROUND:
		rig.set_throughput("")
		return
	var preview: Dictionary = Simulation.preview_burn()
	if not preview.get("ok", false):
		rig.set_throughput(str(preview.get("reason", "This pipeline produces nothing.")))
		return
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	# Terse because this now lives on the monitor, where a sentence would not fit
	# and the full breakdown is already on the BURN button.
	var parts: PackedStringArray = [
		"next %s ×%.2f +%d%%" % [
			NumberFormat.format(float(preview.get("tokens", 0.0))),
			float(preview.get("progress_mult", 1.0)),
			int(round(float(preview.get("progress_tokens", 0.0)) / requirement * 100.0)),
		],
		"+%dq" % int(round(float(preview.get("quality", 0.0)))),
	]
	if int(preview.get("bugs_added", 0)) > 0:
		parts.append("+%db" % int(preview.get("bugs_added", 0)))
	# With more than one machine the batch is split, so the readout above is this
	# contract's share rather than the whole rig's output. Saying how many ways
	# stops that looking like the rig got slower.
	var lanes: int = int(preview.get("lane_count", 1))
	if lanes > 1:
		parts.append("1 of %d lanes" % lanes)
	if Simulation.boost_engaged():
		parts.append("boost")
	if Simulation.cloud_engaged():
		parts.append("cloud")
	rig.set_throughput(" ".join(parts))


func _refresh_actions(job: Dictionary, working: bool) -> void:
	_refresh_job_key(job, working)
	edit_key.disabled = not working
	# Named, because which pipeline this contract is being worked through is now
	# a choice, and editing the wrong one is a mistake worth preventing.
	var workflow: Dictionary = Simulation.workflow_for_job(job)
	edit_key.set_lines(
		str(workflow.get("name", "PIPELINE")).to_upper(),
		"%d OF %d PLACED" % [
			Simulation.filled_slot_count(),
			Simulation.owned_operations().size(),
		]
	)
	deck.set_burning(false)
	burn_key.disabled = not Simulation.can_burn()
	_refresh_burn_key()
	cool_key.disabled = not working or job.is_empty()
	_refresh_cool_key(working, job)

	# Both surges last exactly one batch. The deck's lamps carry that, which frees
	# each key's sub-line to keep saying what the surge costs.
	var boosted: bool = Simulation.boost_engaged()
	boost_key.disabled = not working or boosted
	boost_key.theme_type_variation = &"BoostButton" if boosted else &"SecondaryButton"
	var clouded: bool = Simulation.cloud_engaged()
	var cloud_owned: bool = Simulation.cloud_enabled()
	var can_afford_cloud: bool = Simulation.can_afford_cloud_burst()
	cloud_key.visible = FeatureFlags.is_enabled("cloud_compute_enabled")
	cloud_key.disabled = not working or clouded or not cloud_owned or not can_afford_cloud
	cloud_key.set_lines(
		"CLOUD BURST",
		NumberFormat.format_cash(Simulation.cloud_burst_cost()) if cloud_owned else "NO ACCOUNT"
	)
	cloud_key.theme_type_variation = &"PrimaryButton" if clouded else &"SecondaryButton"
	deck.set_indicators(boosted, clouded)
	_refresh_deliver_key(working, job)
	# Last, because the deck cuts each cap from the variation this pass just set.
	deck.restyle_keys()


## The contract's key. Its legend carries the two numbers the plate used to read
## out, so the fee and the time left are still on screen without a panel; the brief
## itself is one tap away.
func _refresh_job_key(job: Dictionary, working: bool) -> void:
	job_key.disabled = job.is_empty()
	if job.is_empty():
		job_key.set_lines(
			"JOB", "NOTHING ON THE BENCH" if working else "NOT WORKING"
		)
		return
	job_key.set_lines("JOB", "%s · %dP" % [
		NumberFormat.format_cash(float(job.get("reward", 0.0))),
		maxi(0, int(job.get("prompts_remaining", 0))),
	])


## SHIP and ABANDON are both "this contract is over" decisions and each is pressed
## at most once per contract, so they share one function-row key that opens a sheet
## rather than two full-width caps that sit there all game.
func _refresh_deliver_key(working: bool, job: Dictionary) -> void:
	deliver_key.disabled = not working or job.is_empty()
	if job.is_empty():
		deliver_key.set_lines("DELIVER", "")
		deliver_key.theme_type_variation = &"SecondaryButton"
		return
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var remaining: float = maxf(0.0, float(job.get("tokens_remaining", 0.0)))
	var complete: bool = remaining <= 0.0
	deliver_key.set_lines(
		"DELIVER",
		"READY" if complete else "AT %d%%" % _done_percent(job)
	)
	# Delivering a finished contract is the payday, so it goes green; shipping an
	# unfinished one is a gamble and stays neutral.
	deliver_key.theme_type_variation = &"MoneyButton" if complete else &"SecondaryButton"


func _done_percent(job: Dictionary) -> int:
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var remaining: float = maxf(0.0, float(job.get("tokens_remaining", 0.0)))
	return int(round((1.0 - remaining / requirement) * 100.0))


## A game button should say what it costs, so the batch size sits on the headline
## and its consequences sit on the line underneath. The enter key is narrow and
## tall, so those consequences wrap onto their own line rather than running on.
func _refresh_burn_key() -> void:
	var preview: Dictionary = Simulation.preview_burn() if Simulation.can_burn() else {}
	if not preview.get("ok", false):
		burn_key.set_lines("BURN", "")
		return
	var consequences: PackedStringArray = [
		"%s BT" % NumberFormat.format(float(preview.get("tokens", 0.0))),
	]
	var total_heat: float = float(preview.get("total_heat", preview.get("heat", 0.0)))
	var costs: PackedStringArray = []
	if absf(total_heat) >= 0.5:
		costs.append("HEAT %+d" % int(round(total_heat)))
	if float(preview.get("cost", 0.0)) > 0.0:
		costs.append(NumberFormat.format_cash(float(preview.get("cost", 0.0))))
	if not costs.is_empty():
		consequences.append(" · ".join(costs))
	burn_key.set_lines("BURN", "\n".join(consequences))


## COOL vents a share of current heat, but the ambient gain from powered-on
## hardware lands the same prompt regardless — so the button has to show the
## net result, or a big vent on a hot rig with weak cooling can look like it
## did nothing (or made things worse).
func _refresh_cool_key(working: bool, job: Dictionary) -> void:
	if not working or job.is_empty():
		cool_key.set_lines("COOL", "")
		return
	var preview: Dictionary = Simulation.preview_cool()
	if not preview.get("ok", false):
		cool_key.set_lines("COOL", "")
		return
	var delta: float = float(preview.get("total_heat", 0.0))
	# Terse because this is a legend on a small keycap, not a sentence.
	if delta <= -0.5:
		cool_key.set_lines("COOL", "%d HEAT" % int(round(delta)))
	elif delta >= 0.5:
		cool_key.set_lines("COOL", "+%d HEAT" % int(round(delta)))
	else:
		cool_key.set_lines("COOL", "NO CHANGE")


## Lets the player move the pipeline onto a different contract between prompts.
## With more than one machine several contracts advance at once, so the row also
## says which ones a burn would touch — focus becomes a priority rather than the
## only thing making progress.
func _refresh_focus_row(job: Dictionary) -> void:
	for child in focus_row.get_children():
		child.queue_free()
	var candidates: Array = []
	for candidate in Simulation.run_state.business.get("active_jobs", []):
		if not candidate is Dictionary:
			continue
		if float(candidate.get("tokens_remaining", 0.0)) <= 0.0:
			continue
		if int(candidate.get("prompts_remaining", 0)) < 0:
			continue
		candidates.append(candidate)
	focus_row.visible = candidates.size() > 1
	if not focus_row.visible:
		return
	var burning_ids: Array = []
	for lane in Simulation.burn_lanes():
		burning_ids.append(str(lane.get("id", "")))
	for candidate in candidates:
		var button := GameButton.new()
		button.headline = str(candidate.get("name", "Contract")).to_upper()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var is_focused: bool = str(candidate.get("id", "")) == str(job.get("id", ""))
		var is_burning: bool = str(candidate.get("id", "")) in burning_ids
		if is_focused:
			button.sub_text = "ON THE BENCH · %dp LEFT" % maxi(0, int(candidate.get("prompts_remaining", 0)))
		elif is_burning:
			button.sub_text = "ALSO BURNING · %dp LEFT" % maxi(0, int(candidate.get("prompts_remaining", 0)))
		else:
			button.sub_text = "WAITING · %dp LEFT" % maxi(0, int(candidate.get("prompts_remaining", 0)))
		button.accent_key = "action" if is_focused else ("compute" if is_burning else "neutral")
		button.theme_type_variation = &"PrimaryButton" if is_focused else &"SecondaryButton"
		button.disabled = is_focused
		var job_id: String = str(candidate.get("id", ""))
		button.pressed.connect(func() -> void:
			if Simulation.focus_job(job_id):
				refresh()
		)
		focus_row.add_child(button)


## Routes the focused contract through a different workflow. Only shown once the
## run owns more than one, since with a single pipeline there is no choice to
## make. Each button says how well that workflow answers this contract.
func _refresh_workflow_row(job: Dictionary) -> void:
	for child in workflow_row.get_children():
		child.queue_free()
	var matches: Array = Simulation.workflow_matches(job) if not job.is_empty() else []
	workflow_row.visible = matches.size() > 1
	if not workflow_row.visible:
		return
	var assigned_id: String = str(job.get("workflow_id", ""))
	var job_id: String = str(job.get("id", ""))
	for match_report in matches:
		var workflow_id: String = str(match_report.get("workflow_id", ""))
		var is_assigned: bool = workflow_id == assigned_id
		var button := GameButton.new()
		button.headline = str(match_report.get("name", "Workflow")).to_upper()
		button.sub_text = JobPresentation.match_summary(match_report)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = is_assigned
		var answers_all: bool = bool(match_report.get("perfect", false))
		if is_assigned:
			button.accent_key = "action"
			button.theme_type_variation = &"PrimaryButton"
		else:
			button.accent_key = "success" if answers_all else "neutral"
			button.theme_type_variation = &"SecondaryButton"
		button.pressed.connect(func() -> void:
			if Simulation.assign_workflow(job_id, workflow_id):
				refresh()
		)
		workflow_row.add_child(button)


# --- Arranging ---------------------------------------------------------------

func _on_edit_pipeline() -> void:
	if _burning:
		return
	get_tree().call_group("main_ui", "open_pipeline_editor")


## The brief, in full. The terminal prints the facts a decision needs every prompt;
## this is the prose, the rules and the reasoning behind each demand, which is read
## once when the contract lands and then not again.
func _on_job_details() -> void:
	if _burning:
		return
	var job: Dictionary = Simulation.focused_job()
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
			"value": "%d/%d ×%.2f" % [
				int(round(float(job.get("quality", 0.0)))),
				int(round(float(job.get("quality_threshold", 0.0)))),
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
	# The sheet is shared with DELIVER, so last opening's decision has to go before
	# this one is shown as a read-only brief.
	_clear_sheet_handlers()


# --- Burning -----------------------------------------------------------------

func _on_burn() -> void:
	if _burning or not Simulation.can_burn():
		return
	var preview: Dictionary = Simulation.preview_burn()
	if not preview.get("ok", false):
		rig.set_throughput(str(preview.get("reason", "")))
		return
	UiSound.play("burn")
	_burning = true
	_kill_requested = false
	_stages_completed = 0
	cool_key.disabled = true
	deliver_key.disabled = true
	# KILL takes the enter key's slot for the duration of the batch, so the big
	# cap under the thumb is always whatever the live action is.
	kill_key.disabled = false
	deck.set_burning(true)
	await _animate_batch(preview)
	deck.set_burning(false)
	var stage_limit: int = _stages_completed if _kill_requested else -1
	_burning = false
	Simulation.burn_batch(stage_limit)


## Walks the batch down the pipeline one stage at a time, showing what each
## stage added. This is also the window in which KILL PROCESS can land.
func _animate_batch(preview: Dictionary) -> void:
	var stages: Array = preview.get("stages", [])
	var job: Dictionary = Simulation.focused_job()
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var intensity: float = float(preview.get("progress_tokens", 0.0)) / requirement
	rig.push_line(
		"> burn %s BT · %d stage(s)" % [
			NumberFormat.format(float(preview.get("tokens", 0.0))), stages.size(),
		],
		"heat"
	)
	for stage in stages:
		if _kill_requested:
			return
		# The rig reports the batch as it happens: one typed line per stage, a
		# thump on the case, and the glass lighting up.
		rig.push_line(
			"  %s: %s" % [str(stage.get("name", "")).to_lower(), _stage_summary(stage)],
			_stage_role(stage)
		)
		rig.shake(4.0 + intensity * 6.0)
		rig.flash_screen(_stage_role(stage))
		_pulse_stage_bars(stage)
		await get_tree().create_timer(STAGE_SECONDS).timeout
		# Counted after the wait, so a kill during a stage discards that stage.
		if _kill_requested:
			return
		_stages_completed += 1
	rig.push_line("> batch complete", "success")


## Colours a stage's terminal line by what it did, so bugs and heat stand out from
## clean output without the player reading the numbers.
func _stage_role(stage: Dictionary) -> String:
	var before: Dictionary = stage.get("before", {})
	var after: Dictionary = stage.get("after", {})
	if float(after.get("known_bugs", 0.0)) - float(before.get("known_bugs", 0.0)) > 0.4:
		return "danger"
	if float(after.get("heat", 0.0)) - float(before.get("heat", 0.0)) > 0.5:
		return "heat"
	return "success"


## Heat and quality move during a burn, so the gauge and the quality meter react
## as each stage lands instead of only updating once the batch is committed.
func _pulse_stage_bars(stage: Dictionary) -> void:
	var before: Dictionary = stage.get("before", {})
	var after: Dictionary = stage.get("after", {})
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	if absf(float(after.get("heat", 0.0)) - float(before.get("heat", 0.0))) > 0.5:
		var capacity: float = float(Simulation.run_state.compute.get("heat_capacity", 100.0))
		var throttle: float = float(heat_cfg.get("throttle_ratio", 0.8))
		# The batch is still being animated, so none of its heat has reached the
		# rig yet: the needle shows where the rig will be once the stages so far
		# land. A cooling stage moves it back down, which is the whole point of
		# putting one in the pipeline.
		var projected: float = maxf(
			0.0,
			float(Simulation.run_state.compute.get("heat", 0.0)) + float(after.get("heat", 0.0))
		)
		rig.set_heat(
			projected,
			capacity,
			throttle,
			bool(Simulation.run_state.flags.get("fire_risk", false))
		)
	if float(after.get("quality", 0.0)) - float(before.get("quality", 0.0)) > 0.5:
		rig.pulse_quality()


func _stage_summary(stage: Dictionary) -> String:
	var before: Dictionary = stage.get("before", {})
	var after: Dictionary = stage.get("after", {})
	var parts: PackedStringArray = []
	var progress_delta: float = float(after.get("progress_mult", 1.0)) / maxf(0.01, float(before.get("progress_mult", 1.0)))
	if absf(progress_delta - 1.0) > 0.01:
		parts.append("×%.2f progress" % progress_delta)
	var quality_delta: float = float(after.get("quality", 0.0)) - float(before.get("quality", 0.0))
	if absf(quality_delta) > 0.5:
		parts.append("%+d quality" % int(round(quality_delta)))
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
	kill_key.disabled = true
	rig.push_line("^C killed after %d stage(s)" % _stages_completed, "danger")


func _on_boost() -> void:
	if _burning:
		return
	if Simulation.boost():
		refresh()


func _on_cloud() -> void:
	if _burning:
		return
	if Simulation.cloud_burst():
		refresh()


func _on_cool() -> void:
	if _burning:
		return
	Simulation.cool_hardware()


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
