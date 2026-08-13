extends TestCase


func run() -> void:
	_test_first_reroll_cost_band()
	_test_local_tag_affinity_band()


func _sim() -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(5150)
	return sim


func _test_first_reroll_cost_band() -> void:
	var sim: Node = _sim()
	sim.run_state.build["draft_state"] = {"sequence": 1, "rerolls": 0}
	var ratio: float = BatchRunner.angel_reroll_cost_ratio(sim)
	assert_true(ratio >= 0.05, "First reroll is not trivially cheap")
	assert_true(ratio <= 0.35, "First reroll is not punishingly expensive")
	sim.free()


func _test_local_tag_affinity_band() -> void:
	var neutral: float = BatchRunner.draft_tag_hit_rate(9000, "local", 40, [])
	var committed: float = BatchRunner.draft_tag_hit_rate(9000, "local", 40, ["local"])
	assert_true(committed >= neutral, "Tag affinity never reduces matching offers")
	assert_true(committed >= 0.12, "A committed archetype still sees local cards often enough")
