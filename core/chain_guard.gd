class_name ChainGuard
extends RefCounted

static var _fallback_counter: int = 0

var chain_id: String = ""
var depth: int = 0
var effects_executed: int = 0
var event_counts: Dictionary = {}
var visited_effects: Array[String] = []
var spawned_entities: int = 0
var terminated: bool = false
var termination_reason: String = ""


func _init(p_chain_id: String = "") -> void:
	if p_chain_id != "":
		chain_id = p_chain_id
	else:
		_fallback_counter += 1
		chain_id = "chain_%d" % _fallback_counter


func can_continue(event_name: String, effect_id: String = "") -> bool:
	if terminated:
		return false
	if depth >= EffectOps.MAX_TRIGGER_DEPTH:
		_terminate("Trigger chain reached maximum depth (%d)." % EffectOps.MAX_TRIGGER_DEPTH)
		return false
	if effects_executed >= EffectOps.MAX_EFFECTS_PER_ACTION:
		_terminate("Effect limit reached (%d effects)." % EffectOps.MAX_EFFECTS_PER_ACTION)
		return false
	var count: int = int(event_counts.get(event_name, 0))
	if count >= EffectOps.MAX_SAME_EVENT_RECURSION:
		_terminate("Too many recursive '%s' events." % event_name)
		return false
	if effect_id != "" and effect_id in visited_effects:
		_terminate("Circular effect detected: %s" % effect_id)
		return false
	return true


func can_spawn(count: int = 1) -> bool:
	if terminated:
		return false
	if spawned_entities + count > EffectOps.MAX_SPAWNED_ENTITIES:
		_terminate(
			"Spawn limit reached (%d entities)." % EffectOps.MAX_SPAWNED_ENTITIES
		)
		return false
	return true


func record(event_name: String, effect_id: String = "") -> void:
	effects_executed += 1
	event_counts[event_name] = int(event_counts.get(event_name, 0)) + 1
	if effect_id != "":
		visited_effects.append(effect_id)


func record_spawn(count: int = 1) -> void:
	spawned_entities += count


func push_depth() -> void:
	depth += 1


func pop_depth() -> void:
	depth = maxi(0, depth - 1)


func _terminate(reason: String) -> void:
	terminated = true
	termination_reason = reason
