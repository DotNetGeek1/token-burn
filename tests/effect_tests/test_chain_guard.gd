extends TestCase


func run() -> void:
	var guard := ChainGuard.new("test")
	assert_true(guard.can_continue("prompt.started"), "Chain starts")
	for _i in range(EffectOps.MAX_SAME_EVENT_RECURSION):
		guard.record("prompt.started")
	assert_false(guard.can_continue("prompt.started"), "Same-event recursion capped")

	var resolver := EffectResolver.new()
	var state := RunState.new()
	var subs: Array = [{
		"event": "quality.calculated",
		"priority": 0,
		"conditions": [],
		"effects": [{"operation": "add", "target": "job.quality", "value": 1.0}],
		"source_id": "test.perk",
	}]
	for i in range(50):
		resolver.begin_action("tick_%d" % i)
		var mod_ctx := ModifierContext.new("quality.calculated", state)
		mod_ctx.job = {"quality": float(i)}
		mod_ctx.set_value("job.quality", float(i))
		resolver.dispatch("quality.calculated", mod_ctx, subs)
	var last_ctx := ModifierContext.new("quality.calculated", state)
	last_ctx.job = {"quality": 0.0}
	last_ctx.set_value("job.quality", 0.0)
	resolver.begin_action("final")
	resolver.dispatch("quality.calculated", last_ctx, subs)
	assert_eq(last_ctx.get_value("job.quality", 0.0), 1.0, "Chain guard resets per action")
