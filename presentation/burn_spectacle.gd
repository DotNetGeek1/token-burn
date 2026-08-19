class_name BurnSpectacle
extends RefCounted

## Turns a resolved burn into the beats the Burn Board plays. The simulation
## already decided what happened; this only names it and times it.
##
## Quiet stages fly past. Named combos, perks, forks and fat multiplier jumps
## hold long enough to read. A batch is capped so a long pipeline never outlasts
## the old fixed 0.9s-per-stage walk.

const QUIET_HOLD := 0.18
const LOUD_HOLD := 0.55
const FINALE_HOLD := 0.5
const MIN_QUIET_HOLD := 0.05
const MIN_LOUD_HOLD := 0.2
const MAX_SECONDS := 5.0
const LOUD_MULT_JUMP := 0.10

const KIND_STAGE := "stage"
const KIND_COMBO := "combo"
const KIND_PERK := "perk"
const KIND_SYNERGY := "synergy"
const KIND_FORK := "fork"
const KIND_REPEAT := "repeat"
const KIND_CASCADE := "cascade"
const KIND_FAULT := "fault"
const KIND_CONVERT := "convert"
const KIND_QUALITY_GATE := "quality_gate"
const KIND_BUG_RISK := "bug_risk"
const KIND_FINAL := "final"

const FORK_LABEL := "RECURSIVE FORK"
const CONVERT_LABEL := "QUALITY BURN"
const FINAL_LABEL := "SHIPPED"

const BOARD_EVENTS := [
	"board.stage_resolved",
	"board.batch_started",
	"board.batch_finalizing",
	"board.batch_finished",
]


## Read-only: `burn` is not written. `traces` may be empty; stages and authored
## combos are enough for the core cascade, and traces add perk/synergy names.
static func compile(burn: Dictionary, traces: Array = []) -> Array:
	var beats: Array = []
	if not burn.get("ok", false):
		return beats
	var board_traces: Array = _board_traces(traces)
	var stages: Array = burn.get("stages", [])
	for stage in stages:
		if not stage is Dictionary:
			continue
		beats.append_array(_stage_beats(burn, stage, board_traces))
	beats.append_array(_closing_beats(burn, board_traces))
	_cap_holds(beats)
	return beats


## Older board code and incoming tests called `build`. Compile is the live path.
static func build(preview: Dictionary, traces: Array = [], _board_slots: Array = []) -> Array:
	return compile(preview, traces)


static func total_duration_ms(beats: Array) -> int:
	var total: int = 0
	for beat in beats:
		if not beat is Dictionary:
			continue
		total += int(round(float(beat.get("hold", QUIET_HOLD)) * 1000.0))
	return total


static func _stage_beats(burn: Dictionary, stage: Dictionary, traces: Array) -> Array:
	var beats: Array = []
	var after: Dictionary = stage.get("after", {})
	var before: Dictionary = stage.get("before", {})
	var progress_mult: float = float(after.get("progress_mult", 1.0))
	var tokens: float = _running_tokens(burn, after)
	var combos: Array = stage.get("combos", [])
	var forked: bool = (
		float(stage.get("repeated_previous", 0.0)) > 0.0
		and int(stage.get("repeat_count", 0)) > 0
		and int(stage.get("position", 0)) > 0
	)
	var procs: Array = _named_procs(
		_traces_for_chain(traces, "board.stage.%d.%s" % [
			int(stage.get("slot_index", 0)), str(stage.get("module_id", "")),
		]),
		str(stage.get("module_id", ""))
	)
	if bool(stage.get("dropped", false)):
		beats.append(_beat(KIND_FAULT, "DROPPED", true, progress_mult, tokens, stage))
	if not combos.is_empty():
		for combo in combos:
			var combo_name: String = str(combo.get("name", "")).strip_edges()
			if combo_name == "":
				continue
			beats.append(_beat(
				KIND_COMBO, combo_name.to_upper(), true, progress_mult, tokens, stage
			))
	if forked:
		beats.append(_beat(KIND_FORK, FORK_LABEL, true, progress_mult, tokens, stage))
	if bool(stage.get("cascaded", false)):
		beats.append(_beat(KIND_CASCADE, "CASCADE", true, progress_mult, tokens, stage))
	for proc in procs:
		beats.append(_beat(
			str(proc.get("kind", KIND_PERK)),
			str(proc.get("label", "")),
			true,
			progress_mult,
			tokens,
			stage
		))
	if beats.is_empty():
		var before_mult: float = maxf(0.01, float(before.get("progress_mult", 1.0)))
		var jump: float = absf(progress_mult / before_mult - 1.0)
		var loud: bool = jump >= LOUD_MULT_JUMP
		beats.append(_beat(
			KIND_STAGE,
			str(stage.get("name", "stage")).to_upper(),
			loud,
			progress_mult,
			tokens,
			stage
		))
	if not beats.is_empty():
		beats[beats.size() - 1]["closes_stage"] = true
	return beats


static func _closing_beats(burn: Dictionary, traces: Array) -> Array:
	var beats: Array = []
	var progress_mult: float = float(burn.get("progress_mult", 1.0))
	var tokens: float = maxf(0.0, float(burn.get("progress_tokens", 0.0)))
	if float(burn.get("quality_converted", 0.0)) > 0.0:
		beats.append(_beat(
			KIND_CONVERT, _convert_label(burn), true, progress_mult, tokens, {}
		))
	for event_name in ["board.batch_finalizing", "board.batch_finished"]:
		for proc in _named_procs(_traces_for_chain(traces, event_name), ""):
			beats.append(_beat(
				str(proc.get("kind", KIND_PERK)),
				str(proc.get("label", "")),
				true,
				progress_mult,
				tokens,
				{}
			))
	beats.append_array(_consequence_beats(burn, progress_mult, tokens))
	beats.append(_beat(KIND_FINAL, FINAL_LABEL, true, progress_mult, tokens, {}))
	if not beats.is_empty():
		beats[beats.size() - 1]["hold"] = FINALE_HOLD
	return beats


static func _beat(
	kind: String,
	label: String,
	loud: bool,
	progress_mult: float,
	tokens: float,
	stage: Dictionary
) -> Dictionary:
	return {
		"kind": kind,
		"label": label,
		"loud": loud,
		"progress_mult": progress_mult,
		"tokens": tokens,
		"slot_index": int(stage.get("slot_index", -1)),
		"module_id": str(stage.get("module_id", "")),
		"stage_position": int(stage.get("position", -1)),
		"heat": float(Dictionary(stage.get("after", {})).get("heat", 0.0)),
		"hold": LOUD_HOLD if loud else QUIET_HOLD,
		"closes_stage": false,
	}


static func _running_tokens(burn: Dictionary, snapshot: Dictionary) -> float:
	var base: float = float(burn.get("base_tokens", 0.0))
	var token_mult: float = float(snapshot.get("token_mult", burn.get("token_mult", 1.0)))
	var progress_mult: float = float(snapshot.get("progress_mult", 1.0))
	return maxf(0.0, base * token_mult * progress_mult)


static func _board_traces(traces: Array) -> Array:
	var filtered: Array = []
	for entry in traces:
		if not entry is Dictionary:
			continue
		if str(entry.get("event_name", "")) in BOARD_EVENTS:
			filtered.append(entry)
	return filtered


static func _traces_for_chain(traces: Array, chain_id: String) -> Array:
	var matched: Array = []
	for entry in traces:
		if str(entry.get("chain_id", "")) == chain_id:
			matched.append(entry)
	return matched


## Perks, synergies and combo traces that are not the module's own slot effects.
static func _named_procs(traces: Array, module_id: String) -> Array:
	var procs: Array = []
	var seen: Dictionary = {}
	for entry in traces:
		var source_id: String = str(entry.get("source_id", ""))
		var metadata: Dictionary = Dictionary(entry.get("metadata", {}))
		var kind: String = _kind_for(source_id, metadata)
		if kind == KIND_COMBO:
			continue
		if kind != KIND_PERK and kind != KIND_SYNERGY:
			continue
		if module_id != "" and source_id == module_id:
			continue
		var key: String = "%s:%s" % [kind, source_id]
		if seen.has(key):
			continue
		seen[key] = true
		var label: String = _label_for(source_id, metadata)
		if label == "":
			continue
		procs.append({"kind": kind, "label": label, "source_id": source_id})
	return procs


static func _kind_for(source_id: String, metadata: Dictionary) -> String:
	if str(metadata.get("source_kind", "")) == "combo" or str(metadata.get("combo_name", "")) != "":
		return KIND_COMBO
	if source_id.begins_with("synergy."):
		return KIND_SYNERGY
	if source_id.begins_with("perk."):
		return KIND_PERK
	return KIND_STAGE


static func _label_for(source_id: String, metadata: Dictionary) -> String:
	var combo_name: String = str(metadata.get("combo_name", "")).strip_edges()
	if combo_name != "":
		return combo_name.to_upper()
	if source_id.begins_with("synergy."):
		return source_id.substr("synergy.".length()).to_upper()
	if source_id.begins_with("perk."):
		var perk: PerkDefinition = ContentDatabase.get_perk(source_id)
		if perk != null and perk.name != "":
			return perk.name.to_upper()
	var module: ModuleDefinition = ContentDatabase.get_module(source_id)
	if module != null and module.name != "":
		return module.name.to_upper()
	return ""


static func _consequence_beats(burn: Dictionary, progress_mult: float, tokens: float) -> Array:
	if not FeatureFlags.is_enabled("quality_consequences_enabled"):
		return []
	var beats: Array = []
	var before_job := {
		"quality": float(burn.get("job_quality", 0.0)),
		"quality_threshold": float(burn.get("job_quality_threshold", 0.0)),
		"known_bugs": int(burn.get("job_known_bugs", 0)),
		"hidden_bugs": int(burn.get("job_hidden_bugs", 0)),
	}
	var after_job: Dictionary = JobSystem.preview_job_after_burn(before_job, burn)
	var threshold: float = float(before_job.get("quality_threshold", 0.0))
	var before_q: float = JobSystem.delivered_quality(before_job)
	var after_q: float = JobSystem.delivered_quality(after_job)
	if threshold > 0.0 and before_q < threshold and after_q >= threshold:
		beats.append(_beat(
			KIND_QUALITY_GATE,
			"CLIENT BAR CLEARED  PAY ×%.2f → ×%.2f" % [
				JobSystem.projected_payout_multiplier(before_job),
				JobSystem.projected_payout_multiplier(after_job),
			],
			true,
			progress_mult,
			tokens,
			{}
		))
	var before_risk: String = JobSystem.production_risk_class(before_job)
	var after_risk: String = JobSystem.production_risk_class(after_job)
	if after_risk != before_risk and after_risk in ["HIGH", "INSANE"]:
		beats.append(_beat(
			KIND_BUG_RISK,
			"SHIP RISK: %s" % after_risk,
			true,
			progress_mult,
			tokens,
			{}
		))
	return beats


static func _convert_label(burn: Dictionary) -> String:
	var last: String = ""
	for stage in burn.get("stages", []):
		if not stage is Dictionary:
			continue
		var fields: Dictionary = Dictionary(stage.get("stage", {}))
		if float(fields.get("quality_to_progress", 0.0)) > 0.0:
			last = str(stage.get("name", ""))
	if last != "":
		return last.to_upper()
	return CONVERT_LABEL


static func _cap_holds(beats: Array) -> void:
	var total: float = 0.0
	for beat in beats:
		total += float(beat.get("hold", 0.0))
	if total <= MAX_SECONDS:
		return
	var overflow: float = total - MAX_SECONDS
	overflow -= _shrink_holds(beats, false, overflow, MIN_QUIET_HOLD)
	if overflow > 0.001:
		_shrink_holds(beats, true, overflow, MIN_LOUD_HOLD)


static func _shrink_holds(beats: Array, loud: bool, overflow: float, floor_hold: float) -> float:
	var slack: float = 0.0
	for beat in beats:
		if bool(beat.get("loud", false)) != loud:
			continue
		slack += maxf(0.0, float(beat.get("hold", 0.0)) - floor_hold)
	if slack <= 0.0 or overflow <= 0.0:
		return 0.0
	var take: float = minf(overflow, slack)
	var ratio: float = take / slack
	for beat in beats:
		if bool(beat.get("loud", false)) != loud:
			continue
		var hold: float = float(beat.get("hold", 0.0))
		beat["hold"] = hold - (hold - floor_hold) * ratio
	return take
