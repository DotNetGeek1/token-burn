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

const BurnSpectacle := preload("res://presentation/burn_spectacle.gd")

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

# The batch in flight
var _burning: bool = false
var _kill_requested: bool = false
var _skip_requested: bool = false
var _stages_completed: int = 0
var _proc_depth: int = 0


## The instruments the spectacle plays on.
func _init(feed: BurnFeed, drum: MultiplierDrum, heat: HeatMeter, dock: ModuleDock, tab_run: TabRun) -> void:
	name = "BurnDirector"
	_feed = feed
	_drum = drum
	_heat = heat
	_dock = dock
	_tab_run = tab_run


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


## One beat on the cabinet: the drum spins, the stage's bay and strip cell light,
## the feed prints a line, the heat bar nudges.
func _present_beat(beat: Dictionary, job: Dictionary, requirement: float, burned_before: float) -> void:
	var kind: String = str(beat.get("kind", BurnSpectacle.KIND_STAGE))
	var loud: bool = bool(beat.get("loud", false))
	var label: String = str(beat.get("label", "")).to_upper()
	var after: float = float(beat.get("multiplier_after", beat.get("progress_mult", 1.0)))
	var slot: int = int(beat.get("slot_index", -1))
	if slot >= 0:
		_dock.light_step(slot)
		_tab_run.light_step(slot)
	if kind == BurnSpectacle.KIND_FINAL:
		_drum.show_beat(after, label)
		_feed.push("%s  %s BT" % [label, NumberFormat.format(float(beat.get("tokens", 0.0)))], CabinetStyle.AMBER)
		_tab_run.show_beat_status(label, CabinetStyle.AMBER)
	elif kind == BurnSpectacle.KIND_MASTERY:
		_feed.push("WORKFLOW TRAINED  %s" % label, CabinetStyle.AMBER)
		_tab_run.show_beat_status("WORKFLOW TRAINED", CabinetStyle.AMBER)
	else:
		_drum.show_beat(after, label)
		_feed.push("%s  +%s" % [label, NumberFormat.format(float(beat.get("tokens_added", 0.0)))], CabinetStyle.AMBER if loud else CabinetStyle.PHOSPHOR)
		_tab_run.show_beat_status(label if loud else "BURNING", CabinetStyle.AMBER if loud else CabinetStyle.PHOSPHOR)
	_feed.set_live(true, "burn in progress", after)
	if not job.is_empty():
		var burned: float = burned_before + float(beat.get("tokens", 0.0))
		_feed.push("PROGRESS %s / %s" % [NumberFormat.format(minf(burned, requirement)), NumberFormat.format(requirement)], CabinetStyle.PHOSPHOR_DIM)
	if loud:
		UiSound.play("combo" if kind != BurnSpectacle.KIND_FINAL else "complete")
		_proc_depth += 1
	else:
		UiSound.play_proc(_proc_depth)
	_pulse_beat_heat(beat)


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
