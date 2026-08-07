class_name EventSystem
extends RefCounted


func maybe_trigger(
	run_state: RunState,
	rng: DeterministicRng,
	content_db: Node,
	effect_resolver: EffectResolver,
	tuning: Dictionary
) -> EventDefinition:
	if rng.next_float() > 0.65 * float(tuning.get("event_probability_multiplier", 1.0)):
		return null
	var pool: Array = []
	for event in content_db.events:
		if event.trigger_event != "round.ended":
			continue
		var eval_ctx: Dictionary = {"run_state": run_state.to_dict()}
		var all_pass := true
		for condition in event.conditions:
			if condition is Dictionary and not ExpressionEvaluator.new().evaluate_condition(condition, eval_ctx):
				all_pass = false
				break
		if all_pass:
			pool.append({"item": event, "weight": event.weight})
	if pool.is_empty():
		return null
	var picked = rng.weighted_pick(pool, "weight")
	if picked == null:
		return null
	var event: EventDefinition = picked["item"]
	effect_resolver.apply_effects(run_state, event.effects, "event.%s" % event.id)
	return event
