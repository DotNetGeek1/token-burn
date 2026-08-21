extends TestCase

## YOLO always burns and never cools. It cashes out once both delivery and
## quality are complete; AUTO still ships as soon as the token bar hits 100%.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	FeatureFlags.reload()
	_test_auto_ships_when_ready()
	_test_yolo_ships_when_ready_and_quality_met()
	_test_yolo_never_cools()
	_test_yolo_deadline_still_ships()
	_test_yolo_fire_still_ends_the_run()
	_test_yolo_multiplies_deep_burn_score()


func _sim() -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	return sim


func _test_auto_ships_when_ready() -> void:
	var sim: Node = _sim()
	sim.start_run(9801)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(not offers.is_empty(), "A fresh run has work")
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work()
	var job: Dictionary = sim.focused_job()
	job["token_requirement"] = 10.0
	job["tokens_remaining"] = 10.0
	job["prompts_remaining"] = 8
	sim.burn_batch()
	assert_true(JobSystem.is_ready(sim.focused_job()), "The completing burn left it ready")
	assert_true(sim._work._should_auto_ship(sim), "AUTO ships a ready contract")
	sim.free()


func _test_yolo_ships_when_ready_and_quality_met() -> void:
	var sim: Node = _sim()
	sim.start_run(9802)
	sim.set_work_policy(WorkSession.POLICY_YOLO)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work()
	var job: Dictionary = sim.focused_job()
	job["token_requirement"] = 10.0
	job["tokens_remaining"] = 10.0
	job["prompts_remaining"] = 8
	job["quality_threshold"] = 100.0
	job["bug_chance"] = 0.0
	job["revision_risk"] = 0.0
	sim.burn_batch()
	assert_true(JobSystem.is_ready(sim.focused_job()), "YOLO still hits READY")
	assert_false(sim._work._should_auto_ship(sim), "YOLO keeps burning while quality is short")
	job["quality_threshold"] = JobSystem.delivered_quality(job)
	sim.burn_batch()
	assert_true(JobSystem.is_shipped(job), "YOLO cashes out when progress and quality are met")
	assert_eq(sim.work_policy(), WorkSession.POLICY_MANUAL, "YOLO resets after the contract")
	sim.free()


func _test_yolo_never_cools() -> void:
	var sim: Node = _sim()
	sim.start_run(9803)
	sim.set_work_policy(WorkSession.POLICY_YOLO)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work()
	var capacity: float = maxf(1.0, float(sim.run_state.compute.get("heat_capacity", 100.0)))
	sim.run_state.compute["heat"] = capacity * 0.95
	var heat_before: float = float(sim.run_state.compute.get("heat", 0.0))
	var result: Dictionary = sim._work._execute_tick(sim)
	assert_true(result.get("ok", false), "YOLO still acts")
	assert_true(result.has("burn"), "YOLO burns instead of cooling")
	assert_false(result.has("vented"), "YOLO never spends a prompt on the fans")
	assert_true(
		float(sim.run_state.compute.get("heat", 0.0)) >= heat_before * 0.9,
		"YOLO does not vent at throttle"
	)
	sim.free()


func _test_yolo_deadline_still_ships() -> void:
	var sim: Node = _sim()
	sim.start_run(9804)
	sim.set_work_policy(WorkSession.POLICY_YOLO)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work()
	var job: Dictionary = sim.focused_job()
	job["token_requirement"] = 10.0
	job["tokens_remaining"] = 10.0
	job["prompts_remaining"] = 2
	job["deadline_prompts"] = 2
	job["quality_threshold"] = 100.0
	sim.burn_batch()
	assert_true(JobSystem.is_ready(sim.focused_job()), "The first burn left it ready")
	assert_false(JobSystem.is_shipped(sim.focused_job()), "YOLO does not cash out there")
	sim.burn_batch()
	assert_true(JobSystem.is_shipped(job), "The deadline still ships whatever is there")
	assert_eq(sim.work_policy(), WorkSession.POLICY_MANUAL, "A deadline also resets YOLO")
	sim.free()


func _test_yolo_fire_still_ends_the_run() -> void:
	var sim: Node = _sim()
	sim.start_run(9805)
	sim.set_work_policy(WorkSession.POLICY_YOLO)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work()
	var capacity: float = maxf(1.0, float(sim.run_state.compute.get("heat_capacity", 100.0)))
	var catastrophe: float = HeatSystem.catastrophe_ratio(HeatSystem.work_tier(sim.run_state))
	sim.run_state.compute["heat"] = capacity * catastrophe * 8.0
	sim.run_state.flags["fire_risk"] = true
	sim.burn_batch()
	assert_eq(
		str(sim.run_state.flags.get("loss_reason", "")),
		"Hardware fire",
		"YOLO still dies when the rig catches fire"
	)
	assert_eq(sim.phase, sim.Phase.RUN_END, "And the run is over")
	sim.free()


func _test_yolo_multiplies_deep_burn_score() -> void:
	var state := RunState.new()
	state.depth["level"] = 1
	state.depth["score_mult"] = 3.0
	state.flags["work_policy"] = "yolo"
	var before: float = float(state.statistics.get("depth_score", 0.0))
	DepthSystem.record_tokens(state, 100.0)
	var yolo_score: float = float(state.statistics.get("depth_score", 0.0)) - before
	state.statistics["depth_score"] = before
	state.flags["work_policy"] = "manual"
	DepthSystem.record_tokens(state, 100.0)
	var manual_score: float = float(state.statistics.get("depth_score", 0.0)) - before
	assert_almost_eq(yolo_score, manual_score * 1.25, 0.01, "YOLO is ×1.25 Deep Burn score")
	var score: Dictionary = RunScore.compute(state, ContentDatabase)
	state.flags["work_policy"] = "yolo"
	var yolo_board: Dictionary = RunScore.compute(state, ContentDatabase)
	assert_true(
		float(yolo_board.get("depth_score_mult", 1.0)) > float(score.get("depth_score_mult", 1.0)),
		"The debrief names the YOLO multiplier"
	)
