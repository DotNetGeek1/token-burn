extends TestCase


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var job_system := JobSystem.new()
	var state := RunState.new()
	var job_def: JobDefinition = ContentDatabase.get_job("job.product_descriptions")
	assert_true(job_def != null, "Test job exists")

	var round1: Dictionary = job_system._scale_job(job_def, 1, ContentDatabase, {}, state)
	var round6: Dictionary = job_system._scale_job(job_def, 6, ContentDatabase, {}, state)
	assert_true(float(round6.get("token_requirement", 0.0)) > float(round1.get("token_requirement", 0.0)), "Token requirement grows by round")

	var tier: int = job_system._player_max_job_tier(state, 1, ContentDatabase)
	assert_eq(tier, 0, "Round 1 unlocks tier 0")
	tier = job_system._player_max_job_tier(state, 6, ContentDatabase)
	assert_true(tier >= 2, "Round 6 unlocks higher tiers")

	state.business["reputation"] = 24.0
	tier = job_system._player_max_job_tier(state, 1, ContentDatabase)
	assert_true(tier >= 2, "High reputation unlocks bigger contracts early")
	state.business["reputation"] = 28.0
	state.build["upgrade_levels"] = {"upgrade.sales_investment": 2}
	tier = job_system._player_max_job_tier(state, 1, ContentDatabase)
	assert_true(tier >= 3, "Sales investment lowers the rep needed for higher tiers")

	var queued: Dictionary = round1.duplicate(true)
	state.business["job_queue"] = [queued]
	var requirement_before: float = float(state.business["job_queue"][0].get("token_requirement", 0.0))
	job_system.refresh_contract_board(state, DeterministicRng.new(1), ContentDatabase, {})
	var requirement_after: float = float(state.business["job_queue"][0].get("token_requirement", 0.0))
	assert_eq(requirement_before, requirement_after, "Accepted contracts are not rescaled")

	state.build["hardware"] = ["used_laptop", "custom_desktop", "gpu_rack"]
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.run_state = state
	sim._compute_system.recalculate(state, sim.effect_resolver, sim._collect_subscriptions(), sim.rng)
	var upgraded_rate: float = float(state.compute.get("token_rate", 0.0))
	var scaled: Dictionary = job_system._scale_job(job_def, 4, ContentDatabase, {}, state)
	var min_prompts: float = float(ContentDatabase.balance.get("job_scaling", {}).get("min_work_prompts", 6))
	assert_true(
		float(scaled.get("token_requirement", 0.0)) >= upgraded_rate * min_prompts,
		"Offers scale to current token rate"
	)
	sim.free()
