extends TestCase


func run() -> void:
	var resolver := EffectResolver.new()
	var state := RunState.new()

	_test_multiply_reward(resolver, state)
	_test_phase_ordering(resolver, state)
	_test_cap_operations(resolver, state)
	_test_finalize_writeback(resolver, state)


func _test_multiply_reward(resolver: EffectResolver, state: RunState) -> void:
	var mod_ctx := ModifierContext.new("reward.calculated", state)
	mod_ctx.job = {"reward": 100.0, "time_remaining_ratio": 0.04}
	mod_ctx.set_value("job.reward", 100.0)
	var subs: Array = [{
		"event": "reward.calculated",
		"priority": 0,
		"conditions": [{"left": "job.time_remaining_ratio", "operator": "<", "right": 0.05}],
		"effects": [{"operation": "multiply", "target": "job.reward", "value": 2.0}],
	}]
	resolver.begin_action("reward.test")
	resolver.dispatch("reward.calculated", mod_ctx, subs)
	assert_eq(mod_ctx.get_value("job.reward", 0.0), 200.0, "Multiply effect doubles reward")


func _test_phase_ordering(resolver: EffectResolver, state: RunState) -> void:
	var mod_ctx := ModifierContext.new("reward.calculated", state)
	mod_ctx.set_value("job.reward", 100.0)
	var subs: Array = [{
		"event": "reward.calculated",
		"priority": 0,
		"conditions": [],
		"effects": [
			{"operation": "add", "target": "job.reward", "value": 50.0},
			{"operation": "multiply", "target": "job.reward", "value": 2.0},
		],
	}]
	resolver.begin_action("phase.test")
	resolver.dispatch("reward.calculated", mod_ctx, subs)
	assert_eq(mod_ctx.get_value("job.reward", 0.0), 300.0, "Additive before multiplicative")


func _test_cap_operations(resolver: EffectResolver, state: RunState) -> void:
	var mod_ctx := ModifierContext.new("prompt.started", state)
	mod_ctx.set_value("compute.token_rate", 100.0)
	var subs: Array = [{
		"event": "prompt.started",
		"priority": 0,
		"conditions": [],
		"effects": [
			{"operation": "cap_min", "target": "compute.token_rate", "value": 150.0},
			{"operation": "cap_max", "target": "compute.token_rate", "value": 120.0},
		],
	}]
	resolver.begin_action("cap.test")
	resolver.dispatch("prompt.started", mod_ctx, subs)
	assert_eq(mod_ctx.get_value("compute.token_rate", 0.0), 120.0, "Caps apply in order")


func _test_finalize_writeback(resolver: EffectResolver, state: RunState) -> void:
	var mod_ctx := ModifierContext.new("prompt.started", state)
	mod_ctx.set_value("business.reputation", 25.0)
	var subs: Array = [{
		"event": "prompt.started",
		"priority": 0,
		"conditions": [],
		"effects": [{"operation": "set", "target": "business.reputation", "value": 25.0}],
	}]
	resolver.begin_action("finalize.test")
	resolver.dispatch("prompt.started", mod_ctx, subs)
	assert_eq(state.business.get("reputation", 0.0), 25.0, "Finalize writes to run state")
