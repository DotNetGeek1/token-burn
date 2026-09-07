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
const KIND_MASTERY := "mastery"
## A contract demand met or ignored, when its verdict moves the output
## multiplier. The board applies these after the last stage, so without a beat
## of their own the drum fell into SHIPPED with nothing on the feed to say why.
const KIND_DEMAND := "demand"

## Below this the drum is treated as having fallen on a beat.
const FALL_EPSILON := 0.0005

const CONSEQUENCE_SCOPE := "scope"
const CONSEQUENCE_BUG := "bug"
const CONSEQUENCE_HEAT := "heat"
const CONSEQUENCE_DEADLINE := "deadline"

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
	# The drum's reading is threaded through every beat so each one starts
	# exactly where the last left it: a stage's `before` snapshot is taken after
	# its own stage_resolved perks have already moved the batch, so reading the
	# snapshots alone leaves silent gaps between stages.
	var running: float = _starting_multiplier(burn)
	var previous: Dictionary = {}
	for stage in stages:
		if not stage is Dictionary:
			continue
		var stage_beats: Array = _stage_beats(burn, stage, board_traces, running, previous)
		if not stage_beats.is_empty():
			running = float(Dictionary(stage_beats[stage_beats.size() - 1]).get("multiplier_after", running))
		beats.append_array(stage_beats)
		previous = stage
	beats.append_array(_closing_beats(burn, board_traces, running))
	_cap_holds(beats)
	return beats


## Where the drum starts a batch: the workflow's own trained OUTPUT multiplier,
## which is what the first stage's `before` snapshot carries. Not the projected
## total the drum rests on between burns — starting there is what made a
## repeat burn look like it began by falling.
static func _starting_multiplier(burn: Dictionary) -> float:
	for stage in burn.get("stages", []):
		if stage is Dictionary:
			var before: Dictionary = Dictionary(stage).get("before", {})
			return float(before.get("output_mult", before.get("progress_mult", 1.0)))
	return float(burn.get("output_mult", burn.get("progress_mult", 1.0)))


## Mirrors `BoardSystem._scaled_multiplier`: a multiplier applied at partial
## strength keeps its direction but shrinks its distance from 1.
static func _scaled_multiplier(value: float, strength: float) -> float:
	return maxf(0.0, 1.0 + (value - 1.0) * strength)


## What one fold of `fields` at `strength` does to the combined OUTPUT reading.
static func _fold_ratio(fields: Dictionary, strength: float) -> float:
	return (
		_scaled_multiplier(float(fields.get("progress_mult", 1.0)), strength)
		* _scaled_multiplier(float(fields.get("token_mult", 1.0)), strength)
	)


## The share of a stage's jump that its repeat of the stage above produced,
## reconstructed from the resolved stage fields the same way the board folds
## them, so AGAIN! can own its own movement of the drum.
static func _repeat_ratio(stage: Dictionary, previous: Dictionary) -> float:
	if previous.is_empty():
		return 1.0
	var repeat: float = maxf(0.0, float(stage.get("repeated_previous", 0.0)))
	var count: int = maxi(0, int(stage.get("repeat_count", 0)))
	if repeat <= 0.0 or count <= 0:
		return 1.0
	var strength: float = (
		repeat
		* maxf(0.0, float(stage.get("repeat_strength", 1.0)))
		* maxf(0.0, float(stage.get("multiplier", 1.0)))
	)
	var once: float = _fold_ratio(Dictionary(previous.get("stage", {})), strength)
	var ratio: float = 1.0
	for _fork in range(count):
		ratio *= once
	return ratio


## Completion mastery exists only after the authoritative burn commits, while
## the stage spectacle is previewed before commit. Compile these closing beats
## separately so the board can present the real result without replaying stages.
static func compile_mastery(burn: Dictionary) -> Array:
	return _mastery_beats(
		burn,
		float(burn.get("output_mult", burn.get("progress_mult", 1.0))),
		float(burn.get("progress_tokens", 0.0))
	)


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


## Names what changed after the previewed batch committed. These are structured
## presentation records so the Burn Board never has to reverse-engineer prose
## from the round log to explain scope, bugs, heat or time pressure.
static func compile_consequences(before: Dictionary, after: Dictionary) -> Array:
	var beats: Array = []
	var requirement_before: float = maxf(1.0, float(before.get("requirement", 1.0)))
	var requirement_after: float = maxf(1.0, float(after.get("requirement", requirement_before)))
	var remaining_before: float = maxf(0.0, float(before.get("remaining", requirement_before)))
	var remaining_after: float = maxf(0.0, float(after.get("remaining", requirement_after)))
	var completed_before: float = maxf(0.0, requirement_before - remaining_before)
	var completed_after: float = maxf(0.0, requirement_after - remaining_after)
	var progress_before: float = completed_before / requirement_before
	var progress_after: float = completed_after / requirement_after
	var scope_added: float = maxf(0.0, requirement_after - requirement_before)
	if scope_added > 0.0:
		beats.append({
			"kind": CONSEQUENCE_SCOPE,
			"headline": "SCOPE +%s" % NumberFormat.format(scope_added),
			"detail": "%s > %s  WORK KEPT %s" % [
				_format_percent(progress_before),
				_format_percent(progress_after),
				NumberFormat.format(minf(completed_before, completed_after)),
			],
			"role": "warning",
			"hold": LOUD_HOLD,
			"amount": scope_added,
			"progress_before": progress_before,
			"progress_after": progress_after,
			"completed_before": completed_before,
			"completed_after": completed_after,
		})

	var known_added: int = maxi(0, int(after.get("known_bugs", 0)) - int(before.get("known_bugs", 0)))
	var hidden_added: int = maxi(0, int(after.get("hidden_bugs", 0)) - int(before.get("hidden_bugs", 0)))
	if known_added > 0 or hidden_added > 0:
		var bug_parts := PackedStringArray()
		if known_added > 0:
			bug_parts.append("BUG +%d" % known_added)
		if hidden_added > 0:
			bug_parts.append("HIDDEN +%d" % hidden_added)
		beats.append({
			"kind": CONSEQUENCE_BUG,
			"headline": "  ".join(bug_parts),
			"detail": "SHIP RISK %s" % str(after.get("risk", "ELEVATED")),
			"role": "danger",
			"hold": LOUD_HOLD,
			"known_added": known_added,
			"hidden_added": hidden_added,
		})

	var throttled_before: bool = bool(before.get("throttled", false))
	var throttled_after: bool = bool(after.get("throttled", false))
	if throttled_before != throttled_after:
		beats.append({
			"kind": CONSEQUENCE_HEAT,
			"headline": "THROTTLE ×%.2f" % float(after.get("throttle_multiplier", 0.75)) if throttled_after else "THROTTLE CLEAR",
			"detail": "HEAT %d%%" % int(round(float(after.get("heat_ratio", 0.0)) * 100.0)),
			"role": "danger" if throttled_after else "success",
			"hold": LOUD_HOLD,
		})

	var prompts_before: int = int(before.get("prompts", 0))
	var prompts_after: int = int(after.get("prompts", prompts_before))
	if prompts_after < prompts_before and prompts_after <= 3:
		beats.append({
			"kind": CONSEQUENCE_DEADLINE,
			"headline": "DEADLINE %d" % prompts_after,
			"detail": "PROMPT%s LEFT" % ("" if prompts_after == 1 else "S"),
			"role": "danger" if prompts_after <= 1 else "warning",
			"hold": QUIET_HOLD,
		})
	return beats


static func _format_percent(ratio: float) -> String:
	return "%.1f%%" % (ratio * 100.0)


## One stage's beats, walking the drum from `incoming` (what it reads as the
## stage begins) to the stage's `after` snapshot. The stage's own fold (its
## name, or its combos) moves the drum first; AGAIN! then takes the share its
## repeat of the stage above produced; a cascade takes whatever is left. Perk
## procs fired on this stage sit on the value already reached. Nothing here
## re-derives the maths — the endpoints are the board's own snapshots — only
## the split between beats is reconstructed.
static func _stage_beats(
	burn: Dictionary, stage: Dictionary, traces: Array, incoming: float, previous: Dictionary
) -> Array:
	var beats: Array = []
	var after: Dictionary = stage.get("after", {})
	var target: float = float(after.get("output_mult", after.get("progress_mult", 1.0)))
	var base_tokens: float = float(burn.get("base_tokens", 0.0))
	var target_tokens: float = _running_tokens(burn, after)
	var tokens_before: float = maxf(0.0, base_tokens * incoming)
	var combos: Array = stage.get("combos", [])
	var dropped: bool = bool(stage.get("dropped", false))
	var forked: bool = (
		not dropped
		and float(stage.get("repeated_previous", 0.0)) > 0.0
		and int(stage.get("repeat_count", 0)) > 0
		and int(stage.get("position", 0)) > 0
	)
	var cascaded: bool = bool(stage.get("cascaded", false))
	var procs: Array = _named_procs(
		_traces_for_chain(traces, "board.stage.%d.%s" % [
			int(stage.get("slot_index", 0)), str(stage.get("module_id", "")),
		]),
		str(stage.get("module_id", ""))
	)
	# Where the drum sits after the stage's own fold, before any repeat or
	# cascade. Reconstructed forwards from the resolved fields when there is a
	# fork or cascade to split the jump with; otherwise it is simply the target.
	var own_after: float = target
	var fork_after: float = target
	if forked or cascaded:
		own_after = incoming * _fold_ratio(Dictionary(stage.get("stage", {})), float(stage.get("multiplier", 1.0)))
		fork_after = own_after * _repeat_ratio(stage, previous) if forked else own_after
		if not cascaded:
			# No cascade to absorb stage_folded effects: AGAIN! lands on the target.
			fork_after = target
	var own_tokens: float = maxf(0.0, base_tokens * own_after)
	var fork_tokens: float = maxf(0.0, base_tokens * fork_after)
	var reached: float = incoming
	var reached_tokens: float = tokens_before
	if dropped:
		beats.append(_beat(
			KIND_FAULT, "DROPPED", true, target, target_tokens, stage, incoming, tokens_before
		))
		reached = target
		reached_tokens = target_tokens
	for combo in combos:
		var combo_name: String = str(combo.get("name", "")).strip_edges()
		if combo_name == "":
			continue
		beats.append(_beat(
			KIND_COMBO, combo_name.to_upper(), true, own_after, own_tokens, stage,
			reached, reached_tokens
		))
		reached = own_after
		reached_tokens = own_tokens
	# A repeater or cascader whose own fold does nothing to the drum is named by
	# its AGAIN!/CASCADE beat alone; otherwise the stage's own move gets a beat.
	var own_moves: bool = absf(own_after - incoming) > FALL_EPSILON
	if beats.is_empty() and (own_moves or not (forked or cascaded)):
		var before_mult: float = maxf(0.01, incoming)
		var jump: float = absf(own_after / before_mult - 1.0)
		var loud: bool = jump >= LOUD_MULT_JUMP
		var stage_label: String = str(stage.get("name", "stage")).to_upper()
		# A repeater in the first bay has nothing above it to run again: say so,
		# or the player waits for an AGAIN! that never comes.
		if (
			not dropped
			and int(stage.get("position", 0)) == 0
			and float(stage.get("repeated_previous", 0.0)) > 0.0
			and int(stage.get("repeat_count", 0)) > 0
		):
			stage_label += "  NOTHING ABOVE TO REPEAT"
		beats.append(_beat(
			KIND_STAGE,
			stage_label,
			loud,
			own_after,
			own_tokens,
			stage,
			reached,
			reached_tokens
		))
		reached = own_after
		reached_tokens = own_tokens
	if forked:
		beats.append(_beat(
			KIND_FORK, "AGAIN! ×%d" % int(stage.get("repeat_count", 1)),
			true, fork_after, fork_tokens, stage, reached, reached_tokens
		))
		reached = fork_after
		reached_tokens = fork_tokens
	if cascaded:
		beats.append(_beat(
			KIND_CASCADE, "CASCADE", true, target, target_tokens, stage, reached, reached_tokens
		))
		reached = target
		reached_tokens = target_tokens
	# Whatever the snapshots hold that the split above did not reach (a
	# stage_folded effect on a forked stage, say) belongs to the last beat
	# that moved the drum, so the chain still ends on the board's number.
	if absf(reached - target) > FALL_EPSILON and not beats.is_empty():
		var last: Dictionary = beats[beats.size() - 1]
		_retarget(last, target, target_tokens)
		reached = target
		reached_tokens = target_tokens
	for proc in procs:
		beats.append(_beat(
			str(proc.get("kind", KIND_PERK)),
			str(proc.get("label", "")),
			true,
			reached,
			reached_tokens,
			stage
		))
	beats[beats.size() - 1]["closes_stage"] = true
	return beats


static func _retarget(beat: Dictionary, multiplier_after: float, tokens: float) -> void:
	var before: float = float(beat.get("multiplier_before", multiplier_after))
	beat["multiplier_after"] = multiplier_after
	beat["progress_mult"] = multiplier_after
	beat["tokens"] = tokens
	beat["tokens_added"] = maxf(0.0, tokens - float(beat.get("tokens_before", tokens)))
	beat["ratio"] = multiplier_after / before if before > 0.0 else 1.0
	beat["falls"] = multiplier_after < before - FALL_EPSILON


## Everything after the last stage, chained so the drum never moves without a
## beat that owns the move. The board applies contract demands, then the
## finalizing/finished perk events, then ships; the closing beats walk the
## multiplier the same way from `running` (what the drum reads after the last
## stage): demands take their authored ratios, the first named proc takes
## whatever remains, and SHIPPED lands on the burn's real total.
static func _closing_beats(burn: Dictionary, traces: Array, running: float) -> Array:
	var beats: Array = []
	var final_mult: float = float(burn.get("output_mult", burn.get("progress_mult", 1.0)))
	var final_tokens: float = maxf(0.0, float(burn.get("progress_tokens", 0.0)))
	var base_tokens: float = maxf(0.0, float(burn.get("base_tokens", 0.0)))
	var running_tokens: float = base_tokens * running if base_tokens > 0.0 else final_tokens
	for demand in Array(burn.get("demands", [])):
		if not demand is Dictionary:
			continue
		var ratio: float = float(Dictionary(demand.get("effects", {})).get("progress_mult", 1.0))
		if absf(ratio - 1.0) < FALL_EPSILON:
			continue
		var met: bool = bool(demand.get("met", false))
		var after: float = running * maxf(0.0, ratio)
		var after_tokens: float = base_tokens * after if base_tokens > 0.0 else final_tokens
		beats.append(_beat(
			KIND_DEMAND,
			"%s %s" % [str(demand.get("name", "DEMAND")).to_upper(), "MET" if met else "IGNORED"],
			true, after, after_tokens, {}, running, running_tokens
		))
		running = after
		running_tokens = after_tokens
	if float(burn.get("quality_converted", 0.0)) > 0.0:
		beats.append(_beat(
			KIND_CONVERT, _convert_label(burn), true, running, running_tokens, {}
		))
	# Perks and synergies that fire on the batch events move the multiplier
	# without an authored ratio in the burn: the first of them takes the whole
	# remaining jump so the drum climbs (or falls) on a named beat.
	for event_name in ["board.batch_finalizing", "board.batch_finished"]:
		for proc in _named_procs(_traces_for_chain(traces, event_name), ""):
			beats.append(_beat(
				str(proc.get("kind", KIND_PERK)),
				str(proc.get("label", "")),
				true,
				final_mult,
				final_tokens,
				{},
				running,
				running_tokens
			))
			running = final_mult
			running_tokens = final_tokens
	# Verdict beats do not move the drum, so they sit on whatever it reads now.
	beats.append_array(_consequence_beats(burn, running, running_tokens))
	beats.append_array(_mastery_beats(burn, running, running_tokens))
	# Anything still unaccounted for lands on SHIPPED itself, visibly, rather
	# than being folded into a beat that claims the drum did not move.
	beats.append(_beat(KIND_FINAL, FINAL_LABEL, true, final_mult, final_tokens, {}, running, running_tokens))
	if not beats.is_empty():
		beats[beats.size() - 1]["hold"] = FINALE_HOLD
	return beats


static func _mastery_beats(burn: Dictionary, progress_mult: float, tokens: float) -> Array:
	var beats: Array = []
	var reports: Array = []
	var direct: Dictionary = Dictionary(burn.get("mastery", {}))
	if bool(direct.get("applied", false)):
		reports.append(direct)
	var seen: Dictionary = {}
	if not direct.is_empty():
		seen[str(direct.get("workflow_id", ""))] = true
	for lane in Array(burn.get("lanes", [])):
		if not lane is Dictionary:
			continue
		var lane_mastery: Dictionary = Dictionary(lane.get("mastery", {}))
		var workflow_id: String = str(lane_mastery.get("workflow_id", ""))
		if not bool(lane_mastery.get("applied", false)) or seen.has(workflow_id):
			continue
		seen[workflow_id] = true
		reports.append(lane_mastery)
	for mastery in reports:
		beats.append(_mastery_beat(Dictionary(mastery), progress_mult, tokens))
	return beats


static func _mastery_beat(
	mastery: Dictionary, progress_mult: float, tokens: float
) -> Dictionary:
	var parts: PackedStringArray = []
	if float(mastery.get("output_gain", 0.0)) != 0.0:
		parts.append("OUT%+.2f" % float(mastery.get("output_gain", 0.0)))
	if float(mastery.get("quality_gain", 0.0)) != 0.0:
		parts.append("Q%+.2f" % float(mastery.get("quality_gain", 0.0)))
	if float(mastery.get("thermal_gain", 0.0)) != 0.0:
		parts.append("T%+.2f" % float(mastery.get("thermal_gain", 0.0)))
	if bool(mastery.get("stripped", false)):
		parts.append("STACK LOST")
	if bool(mastery.get("propagated", false)):
		parts.append("SHARED")
	if parts.is_empty():
		return {}
	return _beat(
		KIND_MASTERY,
		"%s  %s" % [str(mastery.get("workflow_name", "WORKFLOW")).to_upper(), " ".join(parts)],
		true,
		progress_mult,
		tokens,
		{}
	)


static func _beat(
	kind: String,
	label: String,
	loud: bool,
	progress_mult: float,
	tokens: float,
	stage: Dictionary,
	multiplier_before: float = -1.0,
	tokens_before: float = -1.0
) -> Dictionary:
	if multiplier_before < 0.0:
		multiplier_before = progress_mult
	if tokens_before < 0.0:
		tokens_before = tokens
	var ratio: float = progress_mult / multiplier_before if multiplier_before > 0.0 else 1.0
	return {
		"kind": kind,
		"label": label,
		"loud": loud,
		"multiplier_before": multiplier_before,
		"multiplier_after": progress_mult,
		## What this beat multiplied the drum by, and whether that was a drop.
		## A drop is intentional — a quality stage's output cost, an ignored
		## demand — but the feed has to say so or it reads as a glitch.
		"ratio": ratio,
		"falls": progress_mult < multiplier_before - FALL_EPSILON,
		"tokens_before": tokens_before,
		"tokens_added": maxf(0.0, tokens - tokens_before),
		"progress_mult": progress_mult,
		"tokens": tokens,
		"repeat_count": int(stage.get("repeat_count", 0)),
		"cascade_depth": int(stage.get("cascade_depth", 0)),
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
