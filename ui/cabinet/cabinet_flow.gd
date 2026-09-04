class_name CabinetFlow
extends Node

## The paper on top of the machine, and when it comes out. The flow owns the
## round-end paperwork (debrief → bills → angels), the run-end verdict, the
## title screen in front of a cold start, the investor's calls, the RUN tab's
## sheets (the contract brief, ship-or-abandon, YOLO) and the pending-flow
## entries the router hands over when it walks the player home. It also owns
## the cabinet's answer to "is anything blocking input?".
##
## The cabinet keeps thin forwarding methods for the `main_ui` group API; this
## is where they land. Signals go back up: the flow asks the cabinet to redraw
## (`refresh_requested`), to burn (`burn_requested`) and tells it the title has
## been dismissed (`title_started`) rather than reaching into the glass itself.
##
## A Node child of the cabinet rather than a RefCounted: it listens to autoload
## signals, and a node's connections die with its parent, so a cabinet that is
## freed cannot leave a flow behind still answering for paper that is gone.

const ANGEL_INVESTORS := preload("res://ui/screens/angel_investors.tscn")
const RUN_END := preload("res://ui/screens/run_end.tscn")
const ROUND_DEBRIEF := preload("res://ui/screens/session_summary.tscn")
const BILLS_SCREEN := preload("res://ui/screens/month_statement.tscn")
const BURN_LAB := preload("res://ui/debug/burn_lab.tscn")
const TITLE_SCREEN := preload("res://ui/title/title_screen.tscn")

const ASCENSION_WARNING_ROUND := 9
const INVESTOR_FINAL_CALL_ROUNDS := 3
const DEADLINE_WARNING_PROMPTS := 3
const DEADLINE_DANGER_PROMPTS := 1

## The shell should redraw everything (a report closed, an angel was taken…).
signal refresh_requested
## The player pressed START on the title; the shell should open its home tab.
signal title_started
## A sheet was confirmed that wants the machine to burn (YOLO).
signal burn_requested

var _cabinet: Control = null
var _overlay_root: Control = null

# Paper on top of the machine
var sheet: ConsoleSheet = null
var angel_investors: Control = null
var run_end: Control = null
var round_debrief: Control = null
var bills_screen: Control = null
var burn_lab: Control = null
var help: HelpOverlay = null
var title_screen: Control = null

var title_active: bool = true
var _pending_statement: Dictionary = {}
var _last_angel_phase: bool = false
var _intro_call_shown: bool = false


## `cabinet` is the shell the paper sits on; `overlay_root` is the layer that
## holds it (already a child of the cabinet, above the instruments).
func _init(cabinet: Control, overlay_root: Control) -> void:
	name = "Flow"
	_cabinet = cabinet
	_overlay_root = overlay_root


# --- Building ----------------------------------------------------------------

## Instantiates the overlays into the overlay root.
func build() -> void:
	sheet = ConsoleSheet.new()
	_overlay_root.add_child(sheet)
	angel_investors = ANGEL_INVESTORS.instantiate()
	run_end = RUN_END.instantiate()
	round_debrief = ROUND_DEBRIEF.instantiate()
	bills_screen = BILLS_SCREEN.instantiate()
	burn_lab = BURN_LAB.instantiate()
	help = HelpOverlay.new()
	for overlay in [angel_investors, round_debrief, bills_screen, run_end, burn_lab, help]:
		if overlay == null:
			push_error("BurnCabinet: failed to instantiate an overlay")
			continue
		_overlay_root.add_child(overlay)
	round_debrief.continue_pressed.connect(_on_debrief_continue)
	bills_screen.continue_pressed.connect(_on_bills_continue)


## Wires the simulation signals that bring the paperwork out. Called by the
## cabinet after its own redraw hooks, so a redraw lands before the paper does.
func connect_events() -> void:
	EventBus.run_started.connect(func() -> void: _intro_call_shown = false)
	Simulation.work_session_finished.connect(_on_work_session_finished)
	Simulation.round_statement_ready.connect(_on_bills_ready)
	EventBus.run_ended.connect(_on_run_ended_call)


# --- What the shell asks ------------------------------------------------------

## The paperwork half of a redraw, after the instruments have been refreshed:
## brings out the angels, the verdict and the investor when the phase calls for
## them, and settles whether the paper is blocking the machine.
func refresh() -> void:
	if title_active:
		sync_overlay_input()
		return
	var report_open: bool = round_debrief.visible or bills_screen.visible
	var in_angel: bool = Simulation.phase == Simulation.Phase.ANGEL_ROUND
	if in_angel and not _last_angel_phase and not report_open:
		angel_investors.show_choices()
	if not (in_angel and report_open):
		_last_angel_phase = in_angel
	if Simulation.phase == Simulation.Phase.RUN_END and not bills_screen.visible and _pending_statement.is_empty():
		_clear_stage_for(run_end)
		run_end.show_from_state(
			bool(Simulation.run_state.flags.get("victory", false)),
			str(Simulation.run_state.flags.get("loss_reason", ""))
		)
	elif run_end != null and run_end.visible:
		run_end.hide_overlay()
	if Simulation.phase == Simulation.Phase.ROUND_PREP:
		_maybe_call_ascension_beat()
	sync_overlay_input()


## The overlay root only eats input while some paper is showing.
func sync_overlay_input() -> void:
	var blocking := false
	for child in _overlay_root.get_children():
		if child is CanvasItem and child.visible:
			blocking = true
			break
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP if blocking else Control.MOUSE_FILTER_IGNORE


## Paper the cabinet mounts itself (the maintenance sheets) and wants in the
## back chain and the blocking check, ahead of the flow's own.
var _registered: Array[Control] = []


func register_overlay(overlay: Control) -> void:
	if overlay != null and not (overlay in _registered):
		_registered.append(overlay)


## Every piece of paper the flow answers for, topmost first.
func _overlays() -> Array:
	var all: Array = []
	all.append_array(_registered)
	all.append_array([sheet, help, round_debrief, bills_screen, angel_investors, run_end, burn_lab])
	return all


## Whether any paper is up and blocking the machine.
func overlay_blocking() -> bool:
	for overlay in _overlays():
		if overlay != null and overlay.visible:
			return true
	return false


## Closes the topmost piece of paper for a system back. True when one was open.
func close_top_overlay() -> bool:
	for overlay in _overlays():
		if overlay != null and overlay.visible:
			if overlay.has_method("close"):
				overlay.close()
			elif overlay.has_method("hide_overlay"):
				overlay.hide_overlay()
			return true
	return false


func mount_overlay(control: Control) -> void:
	_overlay_root.add_child(control)


func open_help() -> void:
	if help != null:
		help.open_help(false)


func open_burn_lab() -> void:
	if burn_lab != null and FeatureFlags.is_enabled("burn_lab_enabled"):
		burn_lab.open()


func replay_work_session(result: Dictionary) -> void:
	if not result.is_empty():
		_on_work_session_finished(result)


func replay_statement(statement: Dictionary) -> void:
	if not statement.is_empty():
		_on_bills_ready(statement)


## An entry the router queued while the player was away from the desk.
func replay_pending(entry: Dictionary) -> void:
	match str(entry.get("kind", "")):
		"tab":
			_cabinet.call("switch_tab", str(entry.get("tab", "work")))
		"title":
			open_title()
		"burn_lab":
			open_burn_lab()
		"session":
			replay_work_session(Dictionary(entry.get("result", {})))
		"statement":
			replay_statement(Dictionary(entry.get("statement", {})))


# --- Title -------------------------------------------------------------------

## The title sits between the instruments and the overlay root, so paper that
## is already out stays above it.
func ensure_title_screen() -> void:
	if title_screen != null:
		return
	title_screen = TITLE_SCREEN.instantiate()
	_cabinet.add_child(title_screen)
	_cabinet.move_child(title_screen, _overlay_root.get_index())
	title_screen.start_requested.connect(_on_title_start)


func open_title() -> void:
	ensure_title_screen()
	title_active = true
	get_tree().call_group("flow_overlay", "hide_overlay")
	title_screen.open()
	sync_overlay_input()


func dismiss_title() -> void:
	if title_screen != null:
		title_screen.visible = false
	title_active = false
	refresh_requested.emit()


func _on_title_start() -> void:
	title_active = false
	title_started.emit()
	_maybe_open_intro_call()
	if not MetaProgress.seen_onboarding() and help != null:
		help.open_help(true)


# --- The RUN tab's sheets -----------------------------------------------------

## The contract brief: description, board rules, demands and the numbers.
func show_job_details() -> void:
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
	sheet.show_detail(str(job.get("name", "Contract")), "%s · %s" % [str(identity["label"]), str(identity["client"])], rows, [], "", identity["color"])


## The software says not to. Confirming sets YOLO and asks for a burn.
func show_yolo_sheet() -> void:
	_clear_sheet_handlers()
	sheet.show_detail(
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
	sheet.action_confirmed.connect(func() -> void:
		Simulation.set_work_policy(WorkSession.POLICY_YOLO)
		if not Simulation.is_work_running() and Simulation.can_start_work():
			Simulation.start_work()
		refresh_requested.emit()
		if Simulation.can_burn():
			burn_requested.emit()
	)


## Both ways a contract can end, on one sheet: ship as-is, or walk away.
func show_deliver_sheet() -> void:
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
	sheet.show_detail(
		str(job.get("name", "Contract")),
		"Deliver or walk away",
		rows,
		[],
		"SHIP IT" if complete else "SHIP AT %d%%" % done_pct,
		UiThemeBuilder.semantic("money" if complete else "warning"),
		"ABANDON"
	)
	sheet.action_confirmed.connect(func() -> void:
		Simulation.ship_focused_job()
		refresh_requested.emit()
	)
	sheet.secondary_confirmed.connect(func() -> void:
		Simulation.abandon_focused_job()
		refresh_requested.emit()
	)


func _done_percent(job: Dictionary) -> int:
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var remaining: float = maxf(0.0, float(job.get("tokens_remaining", 0.0)))
	return int(round((1.0 - remaining / requirement) * 100.0))


## The sheet is one piece of paper reused for every brief; the last brief's
## confirm handlers come off before the next one's go on.
func _clear_sheet_handlers() -> void:
	for signal_ref in [sheet.action_confirmed, sheet.secondary_confirmed]:
		for connection in signal_ref.get_connections():
			signal_ref.disconnect(connection["callable"])


# --- Round-end paperwork -----------------------------------------------------

func _on_work_session_finished(result: Dictionary) -> void:
	var summary: Dictionary = result.get("summary", {})
	if not summary.is_empty() and Simulation.phase != Simulation.Phase.RUN_END:
		angel_investors.hide_overlay()
		round_debrief.show_summary(summary)
	refresh_requested.emit()


func _on_debrief_continue() -> void:
	if not _pending_statement.is_empty():
		var statement: Dictionary = _pending_statement
		_pending_statement = {}
		bills_screen.show_statement(statement)
		refresh_requested.emit()
		return
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		angel_investors.show_choices()
		_last_angel_phase = true
	refresh_requested.emit()


func _on_bills_ready(statement: Dictionary) -> void:
	if statement.is_empty():
		return
	angel_investors.hide_overlay()
	if round_debrief.visible:
		_pending_statement = statement
		refresh_requested.emit()
		return
	bills_screen.show_statement(statement)
	refresh_requested.emit()


func _on_bills_continue() -> void:
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		angel_investors.show_choices()
		_last_angel_phase = true
	refresh_requested.emit()


func _clear_stage_for(verdict: Control) -> void:
	for overlay in get_tree().get_nodes_in_group("flow_overlay"):
		if overlay == verdict or SceneRouter.is_ancestor_of(overlay):
			continue
		if overlay is CanvasItem and overlay.visible and overlay.has_method("hide_overlay"):
			overlay.hide_overlay()


# --- The investor -----------------------------------------------------------

func _maybe_open_intro_call() -> void:
	if _intro_call_shown or title_active:
		return
	if int(Simulation.run_state.calendar.get("round", 1)) > 1 or Simulation.prompts_used_this_round() > 0:
		_intro_call_shown = true
		return
	_intro_call_shown = true
	SceneRouter.investor_says("run_intro")


func _maybe_call_ascension_beat() -> void:
	if title_active or SceneRouter.investor_busy():
		return
	var progress: Dictionary = Simulation.ascension_progress()
	if progress.is_empty():
		return
	var rounds_left: int = int(progress.get("rounds_remaining", 99))
	if rounds_left <= INVESTOR_FINAL_CALL_ROUNDS and not Simulation.run_state.investor_beat_heard("contract_final_call"):
		Simulation.run_state.mark_investor_beat("contract_final_call")
		SceneRouter.investor_says("contract_final_call", {"rounds_remaining": rounds_left})
		return
	if float(progress.get("burn_ratio", 0.0)) >= 0.5 and not Simulation.run_state.investor_beat_heard("contract_halfway"):
		Simulation.run_state.mark_investor_beat("contract_halfway")
		SceneRouter.investor_says("contract_halfway")


func _on_run_ended_call(victory: bool) -> void:
	if title_active:
		return
	SceneRouter.investor_says("ascension_complete" if victory else "run_lost")
