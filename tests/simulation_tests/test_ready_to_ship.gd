extends TestCase

## 100% is READY, not delivered. Leftover prompts polish and farm overkill.
## The deadline ships whatever is on the desk.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	FeatureFlags.reload()
	_test_completing_tokens_leaves_the_job_ready()
	_test_a_ready_job_can_burn_again()
	_test_shipping_cashes_out()
	_test_deadline_auto_ships()
	_test_scope_creep_can_reopen_ready_work()


func _open_ready_job() -> Dictionary:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(9701)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(not offers.is_empty(), "A fresh run has work on the board")
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work()
	var job: Dictionary = sim.focused_job()
	job["token_requirement"] = 10.0
	job["tokens_remaining"] = 10.0
	job["prompts_remaining"] = 6
	job["deadline_prompts"] = 6
	return {"sim": sim, "job": job}


func _test_completing_tokens_leaves_the_job_ready() -> void:
	var pack: Dictionary = _open_ready_job()
	var sim: Node = pack["sim"]
	var result: Dictionary = sim.burn_batch()
	assert_true(result.get("ok", false), "The completing burn lands")
	assert_true(JobSystem.is_ready(sim.focused_job()), "The contract is ready, not cashed out")
	assert_false(JobSystem.is_shipped(sim.focused_job()), "And it has not shipped yet")
	assert_eq(sim.phase, sim.Phase.IN_ROUND, "The round stays open")
	sim.free()


func _test_a_ready_job_can_burn_again() -> void:
	var pack: Dictionary = _open_ready_job()
	var sim: Node = pack["sim"]
	sim.burn_batch()
	var quality_before: float = float(sim.focused_job().get("quality", 0.0))
	var overkill_before: float = float(sim.run_state.statistics.get("lifetime_overkill", 0.0))
	var polish: Dictionary = sim.burn_batch()
	assert_true(polish.get("ok", false), "A ready contract can still burn")
	assert_true(
		float(sim.focused_job().get("quality", 0.0)) >= quality_before,
		"Polish can still move quality"
	)
	assert_true(
		float(sim.run_state.statistics.get("lifetime_overkill", 0.0)) >= overkill_before,
		"Extra throughput after 100% is overkill"
	)
	sim.free()


func _test_shipping_cashes_out() -> void:
	var pack: Dictionary = _open_ready_job()
	var sim: Node = pack["sim"]
	sim.burn_batch()
	assert_true(sim.ship_focused_job(), "SHIP IT cashes out a ready contract")
	assert_true(sim.phase != sim.Phase.IN_ROUND, "Shipping the last contract closes the round")
	sim.free()


func _test_deadline_auto_ships() -> void:
	var pack: Dictionary = _open_ready_job()
	var sim: Node = pack["sim"]
	var job: Dictionary = pack["job"]
	job["tokens_remaining"] = 5.0
	job["prompts_remaining"] = 1
	sim.cool_hardware()
	assert_true(JobSystem.is_shipped(job), "The deadline ships whatever is there")
	assert_true(bool(job.get("shipped_unfinished", false)), "Including unfinished work")
	sim.free()


func _test_scope_creep_can_reopen_ready_work() -> void:
	var job := {
		"id": "job.ready",
		"name": "Ready",
		"tokens_remaining": 0.0,
		"token_requirement": 100.0,
		"prompts_remaining": 3,
		"deadline_prompts": 4,
		"revision_risk": 1.0,
		"scope_creep_pct": 0.10,
		"bug_chance": 0.0,
		"shipped": false,
	}
	var messages: Array[String] = []
	JobSystem.new()._roll_job_risks(
		RunState.new(), job, DeterministicRng.new(11), messages
	)
	assert_true(
		float(job.get("tokens_remaining", 0.0)) > 0.0,
		"Scope creep can reopen a ready contract"
	)
	assert_false(JobSystem.is_ready(job), "And it is no longer ready")
