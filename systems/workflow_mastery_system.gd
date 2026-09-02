class_name WorkflowMasterySystem
extends RefCounted

## Persistent training on a named workflow. Perks write scratch gains on
## `workflow.mastery_evaluated`; this system applies them once per contract.

const EVENT_EVALUATED := "workflow.mastery_evaluated"
const COOL_RATIO := 0.70
const REDLINE_RATIO := 0.85


static func evaluate(
	run_state: RunState,
	job: Dictionary,
	burn: Dictionary,
	remaining_before: float,
	effect_resolver: EffectResolver,
	subscriptions: Array,
	rng: DeterministicRng,
	mode: int
) -> Dictionary:
	var report := {
		"ok": false,
		"applied": false,
		"one_shot": false,
		"clean": false,
		"cool": false,
		"output_gain": 0.0,
		"quality_gain": 0.0,
		"thermal_gain": 0.0,
		"propagated": false,
		"stripped": false,
		"stripped_output": 0.0,
		"stripped_quality": 0.0,
	}
	if remaining_before <= 0.0:
		return report
	if float(job.get("tokens_remaining", 0.0)) > 0.0:
		return report
	if bool(job.get("mastery_evaluated", false)):
		return report
	if mode != ResolveMode.COMMIT:
		return report
	var workflow: Dictionary = BoardSystem.new().workflow_for_job(run_state, job)
	if workflow.is_empty():
		return report
	job["mastery_evaluated"] = true
	BoardSystem.normalize_workflow_fields(workflow)
	var bugs_created: int = int(job.get("bugs_created", 0)) + int(job.get("hidden_bugs_created", 0))
	var one_shot: bool = int(job.get("burn_count", 0)) <= 1
	var clean: bool = bugs_created <= 0
	var cool: bool = float(job.get("peak_heat_ratio", 0.0)) <= COOL_RATIO
	var overkill_ratio: float = float(burn.get("overkill_ratio", job.get("overkill_ratio", 0.0)))
	var start_heat_ratio: float = float(burn.get("start_heat_ratio", 0.0))
	var hot: bool = start_heat_ratio >= REDLINE_RATIO
	_record_completion_telemetry(
		run_state, clean, one_shot, cool, hot, overkill_ratio
	)
	var extras := {
		"one_shot": one_shot,
		"clean": clean,
		"cool": cool,
		"start_heat_ratio": start_heat_ratio,
		"overkill_ratio": overkill_ratio,
		"bugs_created": bugs_created,
		"workflow_id": str(workflow.get("id", "")),
		"workflow_name": str(workflow.get("name", "")),
	}
	var mod_ctx := ModifierContext.new(EVENT_EVALUATED, run_state)
	mod_ctx.rng = rng.derive("workflow.mastery.%s" % str(job.get("id", "")))
	mod_ctx.job = job
	mod_ctx.extras = extras
	mod_ctx.set_value("mastery.output_gain", 0.0)
	mod_ctx.set_value("mastery.quality_gain", 0.0)
	mod_ctx.set_value("mastery.thermal_gain", 0.0)
	mod_ctx.set_value("mastery.gain_mult", 1.0)
	mod_ctx.set_value("mastery.output_gain_mult", 1.0)
	mod_ctx.set_value("mastery.quality_gain_mult", 1.0)
	mod_ctx.set_value("mastery.thermal_gain_mult", 1.0)
	mod_ctx.set_value("mastery.propagate_ratio", 0.0)
	mod_ctx.set_value("mastery.silo", 0.0)
	mod_ctx.set_value("mastery.strip_output", 0.0)
	mod_ctx.set_value("mastery.strip_quality", 0.0)
	var event_subs: Array = subscriptions.duplicate()
	event_subs.append_array(_module_completion_subscriptions(workflow, burn))
	effect_resolver.begin_action("workflow.mastery.%s" % str(job.get("id", "")))
	effect_resolver.dispatch(EVENT_EVALUATED, mod_ctx, event_subs)
	var gain_mult: float = maxf(0.0, float(mod_ctx.get_value("mastery.gain_mult", 1.0)))
	var output_gain: float = float(mod_ctx.get_value("mastery.output_gain", 0.0)) * gain_mult * maxf(
		0.0, float(mod_ctx.get_value("mastery.output_gain_mult", 1.0))
	)
	var quality_gain: float = float(mod_ctx.get_value("mastery.quality_gain", 0.0)) * gain_mult * maxf(
		0.0, float(mod_ctx.get_value("mastery.quality_gain_mult", 1.0))
	)
	var thermal_gain: float = float(mod_ctx.get_value("mastery.thermal_gain", 0.0)) * gain_mult * maxf(
		0.0, float(mod_ctx.get_value("mastery.thermal_gain_mult", 1.0))
	)
	var silo: bool = float(mod_ctx.get_value("mastery.silo", 0.0)) > 0.0
	var propagate_ratio: float = 0.0 if silo else maxf(0.0, float(mod_ctx.get_value("mastery.propagate_ratio", 0.0)))
	var stripped_output: float = 0.0
	var stripped_quality: float = 0.0
	if float(mod_ctx.get_value("mastery.strip_output", 0.0)) > 0.0:
		stripped_output = _strip_latest_gain(workflow, "output")
	if float(mod_ctx.get_value("mastery.strip_quality", 0.0)) > 0.0:
		stripped_quality = _strip_latest_gain(workflow, "quality")
	var stripped: bool = stripped_output > 0.0 or stripped_quality > 0.0
	_apply_gain(workflow, "output", output_gain)
	_apply_gain(workflow, "quality", quality_gain)
	_apply_gain(workflow, "thermal", thermal_gain)
	var propagated: bool = false
	if propagate_ratio > 0.0 and (output_gain != 0.0 or quality_gain != 0.0 or thermal_gain != 0.0):
		for other in Array(run_state.build.get("workflows", [])):
			if not other is Dictionary:
				continue
			if str(other.get("id", "")) == str(workflow.get("id", "")):
				continue
			BoardSystem.normalize_workflow_fields(other)
			_apply_gain(other, "output", output_gain * propagate_ratio)
			_apply_gain(other, "quality", quality_gain * propagate_ratio)
			_apply_gain(other, "thermal", thermal_gain * propagate_ratio)
			propagated = true
	_write_workflow_back(run_state, workflow)
	report["ok"] = true
	report["applied"] = output_gain != 0.0 or quality_gain != 0.0 or thermal_gain != 0.0 or stripped
	report["one_shot"] = one_shot
	report["clean"] = clean
	report["cool"] = cool
	report["output_gain"] = output_gain
	report["quality_gain"] = quality_gain
	report["thermal_gain"] = thermal_gain
	report["propagated"] = propagated
	report["stripped"] = stripped
	report["stripped_output"] = stripped_output
	report["stripped_quality"] = stripped_quality
	report["workflow_id"] = str(workflow.get("id", ""))
	report["workflow_name"] = str(workflow.get("name", ""))
	burn["mastery"] = report
	job["mastery_report"] = report.duplicate(true)
	return report


## Run-level counters for achievements. Recorded once per mastery evaluation so
## a polish burn on an already-finished contract cannot inflate them.
static func _record_completion_telemetry(
	run_state: RunState,
	clean: bool,
	one_shot: bool,
	cool: bool,
	hot: bool,
	overkill_ratio: float
) -> void:
	var stats: Dictionary = run_state.statistics
	if clean:
		stats["clean_completions"] = int(stats.get("clean_completions", 0)) + 1
	if one_shot:
		stats["one_shot_completions"] = int(stats.get("one_shot_completions", 0)) + 1
	if clean and one_shot:
		stats["clean_one_shot_completions"] = int(stats.get("clean_one_shot_completions", 0)) + 1
	if cool:
		stats["cool_completions"] = int(stats.get("cool_completions", 0)) + 1
	if hot and one_shot:
		stats["hot_one_shot_completions"] = int(stats.get("hot_one_shot_completions", 0)) + 1
	if overkill_ratio >= 2.0:
		stats["overkill_2x_completions"] = int(stats.get("overkill_2x_completions", 0)) + 1


static func _module_completion_subscriptions(workflow: Dictionary, burn: Dictionary) -> Array:
	var extra: Array = []
	var reached: Array = Array(burn.get("reached_modules", []))
	if not burn.has("reached_modules"):
		reached = Array(workflow.get("slots", []))
	for module_id in reached:
		var module: ModuleDefinition = ContentDatabase.get_module(str(module_id))
		if module == null:
			continue
		extra.append_array(module.to_completion_subscriptions(EVENT_EVALUATED))
	return extra


static func _apply_gain(workflow: Dictionary, axis: String, amount: float) -> void:
	if amount == 0.0:
		return
	var key: String = "%s_mult" % axis
	workflow[key] = maxf(0.01, float(workflow.get(key, 1.0)) + amount)
	var ledger: Array = Array(workflow.get("gain_ledger", []))
	ledger.append({"axis": axis, "amount": amount})
	workflow["gain_ledger"] = ledger


static func _strip_latest_gain(workflow: Dictionary, axis: String) -> float:
	var ledger: Array = Array(workflow.get("gain_ledger", []))
	for i in range(ledger.size() - 1, -1, -1):
		var entry: Variant = ledger[i]
		if not entry is Dictionary:
			continue
		if str(entry.get("axis", "")) != axis:
			continue
		var amount: float = float(entry.get("amount", 0.0))
		if amount <= 0.0:
			continue
		var key: String = "%s_mult" % axis
		workflow[key] = maxf(0.01, float(workflow.get(key, 1.0)) - amount)
		ledger.remove_at(i)
		workflow["gain_ledger"] = ledger
		return amount
	return 0.0


static func _write_workflow_back(run_state: RunState, workflow: Dictionary) -> void:
	var workflows: Array = Array(run_state.build.get("workflows", []))
	for i in range(workflows.size()):
		if str(Dictionary(workflows[i]).get("id", "")) == str(workflow.get("id", "")):
			workflows[i] = workflow
			run_state.build["workflows"] = workflows
			return
