extends TestCase


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_hardware_upgrade()
	_test_double_purchase()
	_test_round_end_choice()
	_test_headless_no_autosave()
	_test_market_purchase()
	_test_mixed_job_finalization()
	_test_multi_job_tick_counts_once()


func _make_sim() -> Node:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	return sim


func _test_hardware_upgrade() -> void:
	var sim := _make_sim()
	sim.start_run(100)
	sim.run_state.economy["cash"] = 5000.0
	var rate_before: float = float(sim.run_state.compute.get("token_rate", 0.0))
	assert_true(sim.buy_upgrade("upgrade.custom_desktop"), "Hardware upgrade purchases")
	sim._compute_system.recalculate(sim.run_state, sim.effect_resolver, sim._collect_subscriptions(), sim.rng)
	var rate_after: float = float(sim.run_state.compute.get("token_rate", 0.0))
	assert_true(rate_after > rate_before, "Hardware upgrade increases token rate")
	sim.free()


func _test_double_purchase() -> void:
	var sim := _make_sim()
	sim.start_run(101)
	var cash_before: float = float(sim.run_state.economy.get("cash", 0.0))
	assert_true(sim.buy_upgrade("upgrade.portable_ac"), "First purchase succeeds")
	var cash_after_first: float = float(sim.run_state.economy.get("cash", 0.0))
	assert_false(sim.buy_upgrade("upgrade.portable_ac"), "Second purchase rejected")
	assert_eq(sim.run_state.economy.get("cash", 0.0), cash_after_first, "Cash not deducted twice")
	assert_true(cash_after_first < cash_before, "First purchase cost cash")
	sim.free()


func _test_round_end_choice() -> void:
	var sim := _make_sim()
	sim.start_run(102)
	sim.run_state.business["job_queue"] = [{
		"id": "job.product_descriptions",
		"name": "Test",
		"token_requirement": 1.0,
		"tokens_remaining": 1.0,
		"deadline_prompts": 99,
		"prompts_remaining": 99,
		"reward": 500.0,
		"quality_threshold": 0.0,
		"quality": 0.0,
		"revision_risk": 0.0,
		"bug_chance": 0.0,
	}]
	sim.start_work_sync()
	assert_true(sim.phase == sim.Phase.ANGEL_ROUND, "Resolving the round's work opens the angel phase")
	assert_true(sim.pending_choices.size() > 0, "Angel choices are presented after the bills clear")
	sim.free()


func _test_headless_no_autosave() -> void:
	SaveManager.delete_save()
	var sim := _make_sim()
	sim.autosave_enabled = false
	sim.start_run(103)
	if sim.run_state.business.get("job_offers", []).size() > 0:
		sim.accept_job(str(sim.run_state.business["job_offers"][0].get("id", "")))
		sim.start_work_sync()
	assert_false(SaveManager.has_save(), "Headless sim does not autosave")
	sim.free()


func _test_market_purchase() -> void:
	var sim := _make_sim()
	sim.start_run(104)
	sim.run_state.economy["cash"] = 10000.0
	assert_true(sim.can_buy_upgrade("upgrade.portable_ac"), "Can buy during round prep")
	assert_true(sim.buy_upgrade("upgrade.portable_ac"), "Market purchase succeeds in ROUND_PREP")
	sim.free()


func _test_mixed_job_finalization() -> void:
	var sim := _make_sim()
	sim.start_run(105)
	sim.run_state.economy["cash"] = 0.0
	sim.run_state.business["active_jobs"] = [
		{"id": "done", "name": "Done", "tokens_remaining": 0.0, "token_requirement": 100.0, "reward": 1000.0, "quality": 80.0, "quality_threshold": 50.0},
		{"id": "fail", "name": "Fail", "tokens_remaining": 50.0, "token_requirement": 100.0, "reward": 1000.0, "quality": 10.0, "quality_threshold": 50.0},
	]
	sim.phase = sim.Phase.IN_ROUND
	sim._end_session("collapsed")
	var cash: float = float(sim.run_state.economy.get("cash", 0.0))
	assert_true(cash >= 900.0, "Completed job in mixed batch paid in full")
	sim.free()


func _test_multi_job_tick_counts_once() -> void:
	var sim := _make_sim()
	sim.start_run(106)
	sim.run_state.economy["cash"] = 10000.0
	sim.run_state.compute["token_rate"] = 100.0
	var small := {
		"id": "small", "name": "Small", "token_requirement": 10.0, "tokens_remaining": 10.0,
		"deadline_prompts": 99, "prompts_remaining": 99, "reward": 500.0,
		"quality": 0.0, "quality_threshold": 0.0, "revision_risk": 0.0, "bug_chance": 0.0,
	}
	var big := {
		"id": "big", "name": "Big", "token_requirement": 1e15, "tokens_remaining": 1e15,
		"deadline_prompts": 99, "prompts_remaining": 99, "reward": 500.0,
		"quality": 0.0, "quality_threshold": 0.0, "revision_risk": 0.0, "bug_chance": 0.0,
	}
	var failing := {
		"id": "late", "name": "Late", "token_requirement": 1e15, "tokens_remaining": 1e15,
		"deadline_prompts": 1, "prompts_remaining": 0, "reward": 500.0,
		"quality": 0.0, "quality_threshold": 0.0, "revision_risk": 0.0, "bug_chance": 0.0,
	}
	sim.run_state.business["active_jobs"] = [small, big, failing]
	sim.phase = sim.Phase.IN_ROUND
	var result: Dictionary = sim._job_system.run_production_tick(
		sim.run_state, sim.rng, sim.effect_resolver, sim._collect_subscriptions(),
		sim.tuning, sim._compute_system, sim._heat_system, sim._economy_system
	)
	assert_true(bool(result.get("ok", false)), "Multi-job tick runs")
	assert_eq(result.get("completed_count", -1), 1, "One job completed mid-tick")
	assert_eq(result.get("failed_count", -1), 1, "One job failed mid-tick")
	assert_false(bool(result.get("all_resolved", true)), "The round is not resolved while a contract continues")
	sim.free()
