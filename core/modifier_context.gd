class_name ModifierContext
extends RefCounted

## Mutable bag of values under negotiation during effect resolution.

var event_name: String = ""
var run_state: RunState = null
var job: Dictionary = {}
var values: Dictionary = {}
var parameters: Dictionary = {}
var tags: PackedStringArray = []
var messages: Array[String] = []
var rng: DeterministicRng = null
## Per-dispatch facts that live nowhere in run state, such as which pipeline
## slot is resolving. Exposed to expressions as `$key`.
var extras: Dictionary = {}


func _init(p_event_name: String = "", p_run_state: RunState = null) -> void:
	event_name = p_event_name
	run_state = p_run_state


func set_value(key: String, value: Variant) -> void:
	values[key] = value


func get_value(key: String, default: Variant = null) -> Variant:
	if values.has(key):
		return values[key]
	if key.begins_with("job.") and job.size() > 0:
		var part: String = key.substr(4)
		if job.has(part):
			return job[part]
	if run_state != null:
		var from_state = run_state.get_value_at_path(key)
		if from_state != null:
			return from_state
	return default


func to_eval_context() -> Dictionary:
	var context: Dictionary = {
		"event_name": event_name,
		"job": job,
		"values": values,
		"parameters": parameters,
		"tags": Array(tags),
		"run_state": run_state.to_dict() if run_state != null else {},
	}
	for key in extras.keys():
		# Reserved context keys win, so extras can never shadow the job or state.
		if not context.has(key):
			context[key] = extras[key]
	return context
