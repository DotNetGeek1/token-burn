extends TestCase

## Wave 4.A: finishing a contract with leftover burn is a jackpot, not the
## default late-game contract.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_completing_burn_records_overkill()
	_test_scoreboard_names_peak_overkill()


func _test_completing_burn_records_overkill() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(9601)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(not offers.is_empty(), "A fresh run has work on the board")
	assert_true(sim.accept_job(str(offers[0].get("id", ""))), "The contract is taken")
	sim.start_work()
	var job: Dictionary = sim.focused_job()
	assert_true(not job.is_empty(), "The accepted contract is on the machine")
	job["token_requirement"] = 10.0
	job["tokens_remaining"] = 10.0
	var result: Dictionary = sim.burn_batch()
	assert_true(result.get("ok", false), "The completing burn lands")
	assert_true(
		float(sim.run_state.statistics.get("peak_overkill", 0.0)) >= 1.25,
		"One-shotting leftover work records overkill"
	)
	assert_true(
		float(sim.run_state.statistics.get("lifetime_overkill", 0.0)) > 0.0,
		"And the overflow is summed"
	)
	sim.free()


func _test_scoreboard_names_peak_overkill() -> void:
	var state := RunState.new()
	state.statistics["lifetime_tokens"] = 1000.0
	state.statistics["peak_overkill"] = 4.12
	state.statistics["lifetime_overkill"] = 3.12
	var score: Dictionary = RunScore.compute(state, ContentDatabase)
	assert_almost_eq(float(score.get("peak_overkill", 0.0)), 4.12, 0.001, "Peak overkill is scored")
	assert_eq(int(score.get("overkill_score", 0)), 312, "Overflow becomes an overkill score")
	var labels: Array = []
	for row in RunScore.rows(score):
		labels.append(str(row.get("label", "")))
	assert_true("Peak overkill" in labels, "The debrief prints the jackpot")
