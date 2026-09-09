class_name BurnDirector
extends Node

## Runs a batch on the cabinet. The director owns the burn in flight — whether
## one is running, whether a kill or a skip has been asked for, how many stages
## have closed — and plays the spectacle across the instruments it was handed:
## the drum spins, the dock and strip light, the feed prints, the heat nudges.
##
## The deck (the commit button, the switches, the lever, the lamps) is not its
## business: the cabinet listens for `burn_started` / `burn_finished` and
## re-labels those itself. Timings and EventBus traffic are unchanged from
## when this lived in the cabinet.
##
## A Node child of the cabinet: its timers come from the cabinet's tree and a
## playback in flight dies with the machine it was playing on.

## How finely a beat's hold is sliced so a kill or skip lands within a frame or two.
const HOLD_SLICE := 0.05

## A batch has begun; the deck should latch busy.
signal burn_started
## A batch has finished (committed or failed) and the instruments have settled.
signal burn_finished(ok: bool)
## A pipeline stage closed during playback; `stages` is the running count.
signal stage_completed(stages: int)
## The simulation changed under the director (the round opened); the shell
## should redraw.
signal refresh_requested

# Spectacle surfaces
var _feed: BurnFeed = null
var _drum: MultiplierDrum = null
var _heat: HeatMeter = null
var _dock: ModuleDock = null
var _tab_run: TabRun = null
var _callouts: BurnCallouts = null

## A beat has to multiply the drum by at least this much to earn a callout on
## the glass; the feed and the drum still report the smaller moves.
const CALLOUT_MIN_RATIO := 1.10

# The batch in flight
var _burning: bool = false
var _kill_requested: bool = false
var _skip_requested: bool = false
var _stages_completed: int = 0
var _proc_depth: int = 0


## The instruments the spectacle plays on.
func _init(
	feed: BurnFeed,
	drum: MultiplierDrum,
	heat: HeatMeter,
	dock: ModuleDock,
	tab_run: TabRun,
	callouts: BurnCallouts = null
) -> void:
	name = "BurnDirector"
	_feed = feed
	_drum = drum
	_heat = heat
	_dock = dock
	_tab_run = tab_run
	_callouts = callouts


func is_burning() -> bool:
	return _burning


func stages_completed() -> int:
	return _stages_completed


func kill_requested() -> bool:
	return _kill_requested


func skip_requested() -> bool:
	return _skip_requested


## Whether the CRT's SKIP has anything to do: a playback is running and has
## neither been killed nor already skipped.
func is_skippable() -> bool:
	return _burning and not _kill_requested and not _skip_requested


## Commits the next batch: opens the round if it has to, plays the spectacle,
## commits the burn, then plays what the burn did. Under YOLO it keeps going.
func request_burn() -> void:
	if _burning:
		return
	if not Simulation.is_work_running() and Simulation.can_start_work():
		Simulation.start_work()
		refresh_requested.emit()
	if not Simulation.can_burn():
		return
	var preview: Dictionary = Simulation.preview_burn()
	if not preview.get("ok", false):
		_feed.set_live(false, str(preview.get("reason", "nothing to burn")))
		return
	UiSound.play("burn")
	_burning = true
	_kill_requested = false
	_skip_requested = false
	_stages_completed = 0
	_proc_depth = 0
	burn_started.emit()
	_tab_run.set_burning(true)
	_feed.clear()
	_feed.set_live(true, "burn in progress", 1.0)
	await _animate_batch(preview)
	var committed_job: Dictionary = Simulation.focused_job()
	var before: Dictionary = _consequence_snapshot(committed_job)
	var stage_limit: int = (
		-1 if Simulation.work_policy() == WorkSession.POLICY_YOLO
		else (_stages_completed if _kill_requested else -1)
	)
	var result: Dictionary = Simulation.burn_batch(stage_limit)
	var after: Dictionary = _consequence_snapshot(committed_job)
	if result.get("ok", false):
		var committed_burn: Dictionary = Dictionary(result.get("burn", {}))
		await _animate_mastery(BurnSpectacle.compile_mastery(committed_burn))
		await _animate_consequences(BurnSpectacle.compile_consequences(before, after))
	_burning = false
	_tab_run.set_burning(false)
	_dock.light_step(-1)
	var ok: bool = bool(result.get("ok", false))
	_feed.set_live(false, "batch committed" if ok else "batch failed")
	burn_finished.emit(ok)
	if Simulation.work_policy() == WorkSession.POLICY_YOLO and Simulation.can_burn():
		call_deferred("request_burn")


## ^C: the batch stops after the stage now playing. Not under YOLO.
func request_kill() -> void:
	if not _burning or Simulation.work_policy() == WorkSession.POLICY_YOLO:
		return
	_kill_requested = true
	_feed.push("^C KILLED AFTER %d STAGE(S)" % _stages_completed, CabinetStyle.RED)
	_tab_run.show_beat_status("KILLED", CabinetStyle.RED)


## Fast-forwards the playback to its result.
func request_skip() -> void:
	if not _burning or _kill_requested:
		return
	_skip_requested = true


# --- Playback ----------------------------------------------------------------

func _animate_batch(preview: Dictionary) -> void:
	var job: Dictionary = Simulation.focused_job()
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var burned_before: float = maxf(0.0, requirement - maxf(0.0, float(job.get("tokens_remaining", 0.0))))
	var beats: Array = preview.get("spectacle", [])
	if beats.is_empty() and FeatureFlags.is_enabled("burn_spectacle_enabled"):
		beats = BurnSpectacle.compile(preview, [])
	_begin_batch_readout(preview, beats)
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
			stage_completed.emit(_stages_completed)


## The drum starts the batch on the workflow's own multiplier — where the first
## beat picks up — instead of the projected total it rests on between burns, so
## the stages are seen to build the number rather than the drum falling to meet
## them. The feed names the start so the climb has a floor to be read against.
func _begin_batch_readout(preview: Dictionary, beats: Array) -> void:
	if beats.is_empty() or not beats[0] is Dictionary:
		return
	var start: float = float(Dictionary(beats[0]).get("multiplier_before", 1.0))
	var workflow_name: String = str(preview.get("workflow_name", "")).strip_edges().to_upper()
	var label: String = "%s START" % workflow_name if workflow_name != "" else "START"
	_drum.begin_batch(start, label)
	_feed.push("%s  ×%.2f" % [label, start], CabinetStyle.PHOSPHOR_DIM)
	_update_feed_readout(start, 0.0)


## The feed's ledger at the drum's reading `multiplier`: the rig's rate through
## it, and the run's burn with this batch's `batch_tokens` so far on top, held
## against the contract the investor set. The run's own total only moves when
## the batch commits, so the batch is added by hand for the figure to climb
## with the beats.
func _update_feed_readout(multiplier: float, batch_tokens: float) -> void:
	var rig: float = maxf(0.0, float(Simulation.run_state.compute.get("token_rate", 0.0)))
	var progress: Dictionary = Simulation.investor_progress()
	var burned: float = float(progress.get("tokens_burned", 0.0)) + maxf(0.0, batch_tokens)
	_feed.set_readout(rig * maxf(0.0, multiplier), burned, float(progress.get("total_burn", 0.0)))


## One beat on the cabinet: the drum spins, the stage's bay and strip cell light,
## the feed prints a line, the heat bar nudges. A beat that drops the drum is
## printed red with the ratio it cost, so an ignored demand or a quality stage's
## output price is read as a cost rather than the multiplier misbehaving.
func _present_beat(beat: Dictionary, job: Dictionary, requirement: float, burned_before: float) -> void:
	var kind: String = str(beat.get("kind", BurnSpectacle.KIND_STAGE))
	var loud: bool = bool(beat.get("loud", false))
	var label: String = str(beat.get("label", "")).to_upper()
	var after: float = float(beat.get("multiplier_after", beat.get("progress_mult", 1.0)))
	var falls: bool = bool(beat.get("falls", false))
	var slot: int = int(beat.get("slot_index", -1))
	if slot >= 0:
		_dock.light_step(slot)
		_tab_run.light_step(slot)
	if kind == BurnSpectacle.KIND_FINAL:
		_drum.show_beat(after, label, falls)
		_feed.push("%s  %s BT" % [label, NumberFormat.format(float(beat.get("tokens", 0.0)))], CabinetStyle.AMBER)
		_tab_run.show_beat_status(label, CabinetStyle.AMBER)
	elif kind == BurnSpectacle.KIND_MASTERY:
		_feed.push("WORKFLOW TRAINED  %s" % label, CabinetStyle.AMBER)
		_tab_run.show_beat_status("WORKFLOW TRAINED", CabinetStyle.AMBER)
	elif falls:
		_drum.show_beat(after, label, true)
		_feed.push("%s  ▼ ×%.2f" % [label, float(beat.get("ratio", 1.0))], CabinetStyle.RED)
		_tab_run.show_beat_status(label, CabinetStyle.RED)
	else:
		_drum.show_beat(after, label)
		_feed.push("%s  +%s" % [label, NumberFormat.format(float(beat.get("tokens_added", 0.0)))], CabinetStyle.AMBER if loud else CabinetStyle.PHOSPHOR)
		_tab_run.show_beat_status(label if loud else "BURNING", CabinetStyle.AMBER if loud else CabinetStyle.PHOSPHOR)
	_feed.set_live(true, "burn in progress", after)
	_update_feed_readout(after, float(beat.get("tokens", 0.0)))
	if not job.is_empty():
		var burned: float = burned_before + float(beat.get("tokens", 0.0))
		_feed.push("TOKENS %s / %s" % [NumberFormat.format(minf(burned, requirement)), NumberFormat.format(requirement)], CabinetStyle.PHOSPHOR_DIM)
	if loud:
		UiSound.play("combo" if kind != BurnSpectacle.KIND_FINAL else "complete")
		_proc_depth += 1
	else:
		UiSound.play_proc(_proc_depth)
	_pulse_beat_heat(beat)
	_callout_beat(beat, kind, after, falls)


## The glass-sized version of a beat that multiplied the drum: the ratio it
## applied and the tokens-per-minute it bought. AGAIN! is named as such, with
## how many times it ran the stage above; anything else is its ratio. The rate
## is the rig's rate through the drum's new reading — the same figure the
## TOKENS readout prints between batches, so the two agree.
func _callout_beat(beat: Dictionary, kind: String, after: float, falls: bool) -> void:
	if _callouts == null or falls:
		return
	if kind == BurnSpectacle.KIND_FINAL or kind == BurnSpectacle.KIND_MASTERY:
		return
	var ratio: float = float(beat.get("ratio", 1.0))
	var again: bool = kind == BurnSpectacle.KIND_FORK
	if ratio < CALLOUT_MIN_RATIO and not again:
		return
	var rig: float = maxf(0.0, float(Simulation.run_state.compute.get("token_rate", 0.0)))
	var rate: String = "%s TOKENS/MIN" % NumberFormat.format_compact(rig * maxf(0.0, after))
	var headline: String
	if again:
		headline = "AGAIN! ×%d" % maxi(1, int(beat.get("repeat_count", 1)))
	else:
		headline = "×%s" % _ratio_text(ratio)
	var color: Color = CabinetStyle.AMBER
	if kind == BurnSpectacle.KIND_COMBO or kind == BurnSpectacle.KIND_SYNERGY:
		color = CabinetStyle.PHOSPHOR
	elif again or kind == BurnSpectacle.KIND_CASCADE:
		color = CabinetStyle.WHITE
	_callouts.flash(headline, rate, color)


## "2", "1.5", "2.25": as short as the ratio allows, never "2.00".
static func _ratio_text(ratio: float) -> String:
	if is_equal_approx(ratio, round(ratio)):
		return str(int(round(ratio)))
	if is_equal_approx(ratio * 10.0, round(ratio * 10.0)):
		return "%.1f" % ratio
	return "%.2f" % ratio


func _pulse_beat_heat(beat: Dictionary) -> void:
	if absf(float(beat.get("heat", 0.0))) <= 0.5:
		return
	var capacity: float = maxf(1.0, float(Simulation.run_state.compute.get("heat_capacity", 100.0)))
	var projected: float = maxf(0.0, float(Simulation.run_state.compute.get("heat", 0.0)) + float(beat.get("heat", 0.0))) / capacity
	var throttle: float = float(HeatSystem.heat_config().get("throttle_ratio", 0.8))
	var state: String = HeatSystem.heat_state(projected, HeatSystem.work_tier(Simulation.run_state))
	_heat.set_heat(projected, throttle, HeatSystem.heat_state_label(state))


func _consequence_snapshot(job: Dictionary) -> Dictionary:
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	var capacity: float = maxf(1.0, float(Simulation.run_state.compute.get("heat_capacity", 100.0)))
	var throttled: bool = false
	for entry in Simulation.run_state.compute.get("rate_modifiers", []):
		if entry is Dictionary and str(entry.get("source", "")) == "heat_throttle":
			throttled = true
	return {
		"requirement": float(job.get("token_requirement", 0.0)),
		"remaining": float(job.get("tokens_remaining", 0.0)),
		"known_bugs": int(job.get("known_bugs", 0)),
		"hidden_bugs": int(job.get("hidden_bugs", 0)),
		"risk": JobSystem.production_risk_class(job),
		"prompts": int(job.get("prompts_remaining", 0)),
		"heat_ratio": float(Simulation.run_state.compute.get("heat", 0.0)) / capacity,
		"throttled": throttled,
		"throttle_multiplier": float(heat_cfg.get("throttle_multiplier", 0.75)),
	}


func _animate_consequences(beats: Array) -> void:
	for raw in beats:
		if not raw is Dictionary:
			continue
		var beat: Dictionary = raw
		var role: String = str(beat.get("role", "warning"))
		var color: Color = CabinetStyle.RED if role == "danger" else (CabinetStyle.AMBER if role == "warning" else CabinetStyle.PHOSPHOR)
		_feed.push("%s  %s" % [str(beat.get("headline", "RESULT")).to_upper(), str(beat.get("detail", ""))], color)
		_tab_run.show_beat_status(str(beat.get("headline", "RESULT")), color)
		if role == "danger":
			UiSound.play("alarm")
		if str(beat.get("kind", "")) == BurnSpectacle.CONSEQUENCE_BUG and _callouts != null:
			# The bugs the batch wrote, over the job's count once they are on it.
			var added: int = int(beat.get("known_added", 0)) + int(beat.get("hidden_added", 0))
			var job: Dictionary = Simulation.focused_job()
			var total: int = int(job.get("known_bugs", 0)) + int(job.get("hidden_bugs", 0))
			_callouts.flash_bugs(added, maxi(total, added))
		await get_tree().create_timer(float(beat.get("hold", 0.35))).timeout


func _animate_mastery(beats: Array) -> void:
	for raw in beats:
		if not raw is Dictionary or Dictionary(raw).is_empty():
			continue
		var beat: Dictionary = raw
		_present_beat(beat, {}, 1.0, 0.0)
		await get_tree().create_timer(float(beat.get("hold", BurnSpectacle.LOUD_HOLD))).timeout


func _fast_forward(beats: Array, current: Dictionary, job: Dictionary, requirement: float, burned_before: float) -> void:
	var last: Dictionary = current
	for beat in beats:
		if beat is Dictionary:
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
