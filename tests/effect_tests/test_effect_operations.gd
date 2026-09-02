extends TestCase


func run() -> void:
	var resolver := EffectResolver.new()
	var state := RunState.new()

	_test_convert(resolver, state)
	_test_defer_cost(resolver, state)
	_test_borrow(resolver, state)
	_test_spawn_remove(resolver, state)
	_test_reroll(resolver, state)
	_test_repeat(resolver, state)
	_test_multi_job_writeback(resolver, state)
	_test_trace_query(resolver, state)
	_test_token_rate_rate_modifier(resolver, state)
	_test_spawn_limit(resolver, state)
	_test_works_on_my_machine_perk(resolver, state)
	_test_perk_parameters_isolated(resolver, state)


func _test_works_on_my_machine_perk(resolver: EffectResolver, state: RunState) -> void:
	var perk := ContentDatabase.get_perk("perk.works_on_my_machine")
	assert_true(perk != null, "Works on My Machine perk loads")
	var subs: Array = []
	for sub in perk.subscriptions:
		var copy: Dictionary = sub.duplicate(true)
		copy["source_id"] = perk.id
		copy["parameters"] = perk.parameters.duplicate(true)
		subs.append(copy)
	var mod_ctx := ModifierContext.new("compute.recalculate", state)
	mod_ctx.set_value("compute.local_rate", 100.0)
	resolver.begin_action("local.test")
	resolver.dispatch("compute.recalculate", mod_ctx, subs)
	assert_eq(
		float(mod_ctx.get_value("compute.local_rate", 0.0)),
		140.0,
		"Works on My Machine multiplies local rate on recalculate"
	)


func _test_perk_parameters_isolated(resolver: EffectResolver, state: RunState) -> void:
	var local := ContentDatabase.get_perk("perk.works_on_my_machine")
	var homelab := ContentDatabase.get_perk("perk.homelab_hero")
	assert_true(local != null and homelab != null, "Perks load for parameter isolation test")
	var subs: Array = []
	for perk in [local, homelab]:
		for sub in perk.subscriptions:
			if str(sub.get("event", "")) != "compute.recalculate":
				continue
			var copy: Dictionary = sub.duplicate(true)
			copy["source_id"] = perk.id
			copy["parameters"] = perk.parameters.duplicate(true)
			subs.append(copy)
	var mod_ctx := ModifierContext.new("compute.recalculate", state)
	mod_ctx.set_value("compute.local_rate", 100.0)
	resolver.begin_action("params.test")
	resolver.dispatch("compute.recalculate", mod_ctx, subs)
	assert_almost_eq(
		float(mod_ctx.get_value("compute.local_rate", 0.0)),
		100.0 * 1.4 * 1.15,
		0.01,
		"Each perk uses its own parameters when multiple match the same event"
	)


func _test_convert(resolver: EffectResolver, state: RunState) -> void:
	state.economy["cash"] = 1000.0
	state.business["reputation"] = 5.0
	var mod_ctx := ModifierContext.new("round.started", state)
	resolver.begin_action("convert.test")
	resolver.apply_effects(state, [{
		"operation": "convert",
		"from": "economy.cash",
		"target": "business.reputation",
		"value": 0.1,
		"consume": true,
	}], "convert.test")
	assert_almost_eq(float(state.business.get("reputation", 0.0)), 105.0, 0.001, "Convert transfers ratio to target")
	assert_almost_eq(float(state.economy.get("cash", 0.0)), 900.0, 0.001, "Convert consumes source when requested")


func _test_defer_cost(resolver: EffectResolver, state: RunState) -> void:
	state.economy["cash"] = 500.0
	state.economy["pending_bills"] = []
	var mod_ctx := ModifierContext.new("bill.due", state)
	mod_ctx.set_value("economy.cash", 500.0)
	var subs: Array = [{
		"event": "bill.due",
		"priority": 0,
		"conditions": [],
		"effects": [{
			"operation": "defer_cost",
			"target": "economy.cash",
			"value": 75.0,
			"prompts": 2,
		}],
	}]
	resolver.begin_action("defer.test")
	resolver.dispatch("bill.due", mod_ctx, subs)
	assert_eq(mod_ctx.get_value("economy.cash", 0.0), 500.0, "Defer cost does not change target now")
	var bills: Array = state.economy.get("pending_bills", [])
	assert_eq(bills.size(), 1, "Defer cost appends pending bill")
	assert_almost_eq(float(bills[0].get("amount", 0.0)), 75.0, 0.001, "Deferred amount recorded")


func _test_borrow(resolver: EffectResolver, state: RunState) -> void:
	state.economy["cash"] = 100.0
	state.economy["debt"] = 0.0
	var mod_ctx := ModifierContext.new("round.started", state)
	mod_ctx.set_value("economy.cash", 100.0)
	var subs: Array = [{
		"event": "round.started",
		"priority": 0,
		"conditions": [],
		"effects": [{"operation": "borrow", "target": "economy.cash", "value": 250.0}],
	}]
	resolver.begin_action("borrow.test")
	resolver.dispatch("round.started", mod_ctx, subs)
	assert_eq(mod_ctx.get_value("economy.cash", 0.0), 350.0, "Borrow increases target")
	assert_eq(state.economy.get("debt", 0.0), 250.0, "Borrow increases debt")


func _test_spawn_remove(resolver: EffectResolver, state: RunState) -> void:
	state.build["status_effects"] = []
	var mod_ctx := ModifierContext.new("perk.acquired", state)
	var subs: Array = [{
		"event": "perk.acquired",
		"priority": 0,
		"conditions": [],
		"effects": [
			{
				"operation": "spawn",
				"target": "build.status_effects",
				"value": 2,
				"template": {"id": "agent.temp", "rounds": 3},
			},
			{
				"operation": "remove",
				"target": "build.status_effects",
				"value": 1,
			},
		],
	}]
	resolver.begin_action("spawn.test")
	resolver.dispatch("perk.acquired", mod_ctx, subs)
	var effects: Array = state.build.get("status_effects", [])
	assert_eq(effects.size(), 1, "Spawn then remove leaves one entity")


func _test_reroll(resolver: EffectResolver, state: RunState) -> void:
	var mod_ctx := ModifierContext.new("job.offered", state)
	mod_ctx.rng = DeterministicRng.new(99)
	mod_ctx.set_value("job.reward", 100.0)
	var subs: Array = [{
		"event": "job.offered",
		"priority": 0,
		"conditions": [],
		"effects": [{
			"operation": "reroll",
			"target": "job.reward",
			"value": {"min": 80.0, "max": 120.0},
		}],
	}]
	resolver.begin_action("reroll.test")
	resolver.dispatch("job.offered", mod_ctx, subs)
	var reward: float = float(mod_ctx.get_value("job.reward", 0.0))
	assert_true(reward >= 80.0 and reward <= 120.0, "Reroll picks in numeric range")

	var mod_ctx_b := ModifierContext.new("job.offered", state)
	mod_ctx_b.rng = DeterministicRng.new(99)
	mod_ctx_b.set_value("job.reward", 100.0)
	resolver.begin_action("reroll.test.b")
	resolver.dispatch("job.offered", mod_ctx_b, subs)
	assert_eq(
		float(mod_ctx_b.get_value("job.reward", 0.0)),
		reward,
		"Reroll is deterministic for fixed seed"
	)


func _test_repeat(resolver: EffectResolver, state: RunState) -> void:
	var mod_ctx := ModifierContext.new("reward.calculated", state)
	mod_ctx.set_value("job.reward", 10.0)
	var subs: Array = [{
		"event": "reward.calculated",
		"priority": 0,
		"conditions": [],
		"effects": [{
			"operation": "repeat",
			"target": "job.reward",
			"value": 3,
			"effects": [{"operation": "add", "target": "job.reward", "value": 5.0}],
		}],
	}]
	resolver.begin_action("repeat.test")
	resolver.dispatch("reward.calculated", mod_ctx, subs)
	assert_eq(mod_ctx.get_value("job.reward", 0.0), 25.0, "Repeat runs nested add effects")


func _test_multi_job_writeback(resolver: EffectResolver, state: RunState) -> void:
	state.business["active_jobs"] = [
		{"id": "job.a", "reward": 100.0, "quality": 10.0},
		{"id": "job.b", "reward": 200.0, "quality": 20.0},
	]
	var mod_ctx := ModifierContext.new("quality.calculated", state)
	mod_ctx.job = {"id": "job.b", "reward": 200.0, "quality": 20.0}
	mod_ctx.set_value("job.quality", 55.0)
	var subs: Array = [{
		"event": "quality.calculated",
		"priority": 0,
		"conditions": [],
		"effects": [{"operation": "set", "target": "job.quality", "value": 55.0}],
	}]
	resolver.begin_action("multi.test")
	resolver.dispatch("quality.calculated", mod_ctx, subs)
	var jobs: Array = state.business.get("active_jobs", [])
	assert_eq(float(jobs[0].get("quality", 0.0)), 10.0, "Other job unchanged")
	assert_eq(float(jobs[1].get("quality", 0.0)), 55.0, "Matching job id writeback")


func _test_trace_query(resolver: EffectResolver, state: RunState) -> void:
	var mod_ctx := ModifierContext.new("reward.calculated", state)
	mod_ctx.set_value("job.reward", 100.0)
	var subs: Array = [{
		"event": "reward.calculated",
		"priority": 0,
		"source_id": "perk.ship_it",
		"conditions": [],
		"effects": [
			{"operation": "add", "target": "job.reward", "value": 50.0},
			{"operation": "multiply", "target": "job.reward", "value": 2.0},
		],
	}]
	resolver.begin_action("trace.test")
	resolver.dispatch("reward.calculated", mod_ctx, subs)
	var breakdown: Dictionary = resolver.query_trace_breakdown("job.reward", "trace.test")
	assert_eq(breakdown.get("base_value"), 100.0, "Trace breakdown base value")
	assert_eq(breakdown.get("final_value"), 300.0, "Trace breakdown final value")
	var entries: Array = breakdown.get("entries", [])
	assert_eq(entries.size(), 2, "Trace breakdown entry count")
	assert_true(breakdown.get("totals_by_operation", {}).has("add"), "Trace groups by operation")


func _test_token_rate_rate_modifier(resolver: EffectResolver, state: RunState) -> void:
	state.compute["rate_modifiers"] = []
	resolver.apply_effects(state, [{
		"operation": "multiply",
		"target": "compute.token_rate",
		"value": 1.5,
	}], "direct.test")
	var modifiers: Array = state.compute.get("rate_modifiers", [])
	assert_eq(modifiers.size(), 1, "Token rate multiply registers rate modifier")
	assert_almost_eq(float(modifiers[0].get("multiplier", 0.0)), 1.5, 0.001, "Rate modifier multiplier stored")
	var breakdown: Dictionary = resolver.query_trace_breakdown("compute.token_rate", "direct.test")
	assert_true(breakdown.get("entries", [{}])[0].get("metadata", {}).get("rate_modifier", false), "Trace marks rate modifier")


func _test_spawn_limit(resolver: EffectResolver, state: RunState) -> void:
	state.build["status_effects"] = []
	var mod_ctx := ModifierContext.new("perk.acquired", state)
	var subs: Array = [{
		"event": "perk.acquired",
		"priority": 0,
		"conditions": [],
		"effects": [{
			"operation": "spawn",
			"target": "build.status_effects",
			"value": EffectOps.MAX_SPAWNED_ENTITIES + 1,
			"template": {"id": "overflow"},
		}],
	}]
	resolver.begin_action("spawn.limit")
	resolver.dispatch("perk.acquired", mod_ctx, subs)
	assert_true(resolver.get_guard().terminated, "Spawn limit terminates chain")
	assert_eq(state.build.get("status_effects", []).size(), 0, "Blocked spawn writes nothing")
