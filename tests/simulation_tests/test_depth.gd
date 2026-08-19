extends TestCase

## Wave 4.B: beating the moon unlocks a voluntary Deep Burn ladder. No new room.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_reset_clears_depth()
	_test_only_the_last_chapter_can_begin()
	_test_picking_an_affix_stacks()
	_test_jobs_grow_by_the_depth_multiplier()
	_test_scoreboard_names_depth()
	_test_depth_one_completes_into_depth_two()
	_test_choose_affix_refuses_ids_that_were_not_offered()
	_test_affixes_stack_when_authored_repeatable()
	_test_continue_after_depth_resumes_without_victory()


func _test_reset_clears_depth() -> void:
	var state := RunState.new()
	state.depth["level"] = 99
	state.depth["affixes"] = ["depth.target_x5", "depth.thin_cooling"]
	state.depth["stacks"] = {"depth.target_x5": 4}
	state.depth["status"] = DepthSystem.STATUS_COMPLETE
	state.depth["score_mult"] = 64.0
	state.depth["requirement_mult"] = 250.0
	state.depth["tokens_needed"] = 1e30
	state.depth["baseline_tokens"] = 1e20
	state.depth["pending_picks"] = [{"id": "depth.hidden_bug"}]
	state.reset()
	assert_eq(state.depth, state._default_depth(), "reset() restores the whole depth dictionary")


func _test_only_the_last_chapter_can_begin() -> void:
	var depth := DepthSystem.new()
	var bedroom := RunState.new()
	bedroom.build["dwelling"] = "bedroom"
	assert_false(depth.can_begin(bedroom), "The bedroom cannot open Deep Burn")
	var moon := RunState.new()
	moon.build["dwelling"] = "moon_facility"
	assert_true(depth.can_begin(moon), "The moon can")


func _test_picking_an_affix_stacks() -> void:
	var depth := DepthSystem.new()
	var state := RunState.new()
	state.build["dwelling"] = "moon_facility"
	var picks: Array = depth.offer_picks(state, DeterministicRng.new(9701), ContentDatabase)
	assert_eq(picks.size(), 3, "Deep Burn offers three affixes")
	var first_id: String = str(Dictionary(picks[0]).get("id", ""))
	assert_true(depth.choose_affix(state, first_id, ContentDatabase), "The first pick lands")
	assert_eq(int(state.depth.get("level", 0)), 1, "Depth advances to 1")
	assert_eq(str(state.depth.get("status", "")), DepthSystem.STATUS_ACTIVE, "The depth is live")
	assert_true(first_id in Array(state.depth.get("affixes", [])), "The affix is recorded")
	assert_eq(int(Dictionary(state.depth.get("stacks", {})).get(first_id, 0)), 1, "The first stack is counted")
	assert_true(
		float(state.depth.get("requirement_mult", 1.0)) > 1.0,
		"The next workload is larger"
	)
	assert_true(float(state.depth.get("tokens_needed", 0.0)) > 0.0, "A burn target is set")
	assert_false(DepthSystem.is_complete(state), "The target is not already met")
	assert_eq(int(state.statistics.get("depth_reached", 0)), 1, "Statistics remember the depth")
	if first_id == "depth.thin_cooling":
		assert_true(
			_has_status(state, "status.depth.thin_cooling"),
			"Thin Cooling hangs a status on the build"
		)


func _test_jobs_grow_by_the_depth_multiplier() -> void:
	var job_system := JobSystem.new()
	var job_def: JobDefinition = ContentDatabase.get_job("job.product_descriptions")
	var plain := RunState.new()
	var deep := RunState.new()
	deep.depth["requirement_mult"] = 3.0
	var before: Dictionary = job_system._scale_job(job_def, 1, ContentDatabase, {}, plain)
	var after: Dictionary = job_system._scale_job(job_def, 1, ContentDatabase, {}, deep)
	assert_almost_eq(
		float(after.get("token_requirement", 0.0)),
		float(before.get("token_requirement", 0.0)) * 3.0,
		1.0,
		"Depth multiplies the authored requirement rather than live-scaling the rig"
	)


func _test_scoreboard_names_depth() -> void:
	var state := RunState.new()
	state.statistics["lifetime_tokens"] = 1000.0
	state.statistics["depth_reached"] = 2
	state.depth["score_mult"] = 3.0
	var score: Dictionary = RunScore.compute(state, ContentDatabase)
	assert_eq(int(score.get("depth_reached", 0)), 2, "Depth reached is scored")
	assert_eq(int(score.get("depth_score", 0)), 2000, "Score mult is applied as extra score")
	var labels: Array = []
	for row in RunScore.rows(score):
		labels.append(str(row.get("label", "")))
	assert_true("Deep Burn depth" in labels, "The debrief names the depth")


func _test_depth_one_completes_into_depth_two() -> void:
	var depth := DepthSystem.new()
	var state := _moon_at_depth(depth, 9702)
	var needed: float = float(state.depth.get("tokens_needed", 0.0))
	assert_true(needed > 0.0, "Depth 1 has a token target")
	state.statistics["lifetime_tokens"] = float(state.depth.get("baseline_tokens", 0.0)) + needed - 1.0
	var early: Dictionary = depth.evaluate_prompt(state)
	assert_eq(str(early.get("outcome", "")), DepthSystem.STATUS_ACTIVE, "Just short of the target stays live")
	assert_false(DepthSystem.is_complete(state), "The depth is not complete yet")
	state.statistics["lifetime_tokens"] = float(state.depth.get("baseline_tokens", 0.0)) + needed
	var done: Dictionary = depth.evaluate_prompt(state)
	assert_eq(str(done.get("outcome", "")), DepthSystem.STATUS_COMPLETE, "Hitting the target completes the depth")
	assert_eq(str(state.depth.get("status", "")), DepthSystem.STATUS_COMPLETE, "Status latches to complete")
	var again: Dictionary = depth.evaluate_prompt(state)
	assert_eq(str(again.get("outcome", "")), DepthSystem.STATUS_COMPLETE, "A later prompt does not re-fire")
	var picks: Array = depth.offer_picks(state, DeterministicRng.new(9703), ContentDatabase)
	assert_eq(picks.size(), 3, "Completing Depth 1 opens another three-affix draft")
	var next_id: String = str(Dictionary(picks[0]).get("id", ""))
	assert_true(depth.choose_affix(state, next_id, ContentDatabase), "The next pick lands")
	assert_eq(int(state.depth.get("level", 0)), 2, "Depth advances to 2")
	assert_eq(str(state.depth.get("status", "")), DepthSystem.STATUS_ACTIVE, "Depth 2 is live")
	assert_true(
		float(state.depth.get("tokens_needed", 0.0)) > needed,
		"The next target is larger than Depth 1"
	)
	assert_almost_eq(
		float(state.depth.get("baseline_tokens", -1.0)),
		float(state.statistics.get("lifetime_tokens", 0.0)),
		0.01,
		"The next depth measures from the tokens already burned"
	)
	assert_false(DepthSystem.is_complete(state), "Depth 2 starts incomplete")


func _test_choose_affix_refuses_ids_that_were_not_offered() -> void:
	var depth := DepthSystem.new()
	var state := RunState.new()
	state.build["dwelling"] = "moon_facility"
	depth.offer_picks(state, DeterministicRng.new(9704), ContentDatabase)
	assert_false(
		depth.choose_affix(state, "depth.not_a_real_affix", ContentDatabase),
		"An id that was not among the pending picks is refused"
	)


func _test_affixes_stack_when_authored_repeatable() -> void:
	var depth := DepthSystem.new()
	var state := RunState.new()
	state.build["dwelling"] = "moon_facility"
	var cooling := _affix_named("depth.thin_cooling")
	assert_false(cooling.is_empty(), "Thin Cooling is authored")
	assert_true(bool(cooling.get("repeatable", false)), "Thin Cooling is intentionally repeatable")
	state.depth["pending_picks"] = [cooling.duplicate(true)]
	assert_true(depth.choose_affix(state, "depth.thin_cooling", ContentDatabase), "First stack lands")
	state.depth["pending_picks"] = [cooling.duplicate(true)]
	assert_true(depth.choose_affix(state, "depth.thin_cooling", ContentDatabase), "Second stack lands")
	assert_eq(
		int(Dictionary(state.depth.get("stacks", {})).get("depth.thin_cooling", 0)),
		2,
		"Stacks are counted rather than arriving as a fallback side effect"
	)
	assert_true(_has_status(state, "status.depth.thin_cooling"), "The first status stays")
	assert_true(_has_status(state, "status.depth.thin_cooling.2"), "The second stack is a distinct status")


func _test_continue_after_depth_resumes_without_victory() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(9705)
	sim.run_state.build["dwelling"] = "moon_facility"
	sim.run_state.flags["post_victory"] = true
	sim.run_state.flags["post_victory_phase"] = "ROUND_PREP"
	sim.run_state.flags["outcome"] = "depth_complete"
	sim.run_state.flags["depth_complete"] = true
	sim.run_state.depth["level"] = 1
	sim.run_state.depth["status"] = DepthSystem.STATUS_COMPLETE
	sim.phase = sim.Phase.RUN_END
	assert_true(sim.continue_after_depth(), "A completed depth can resume without a chapter victory")
	assert_eq(sim.phase, sim.Phase.ROUND_PREP, "Play resumes at the remembered boundary")
	assert_false(bool(sim.run_state.flags.get("depth_complete", true)), "The complete flag is cleared")
	assert_eq(str(sim.run_state.flags.get("outcome", "x")), "", "The depth-complete outcome is cleared")
	sim.free()


func _moon_at_depth(depth: DepthSystem, seed_value: int) -> RunState:
	var state := RunState.new()
	state.build["dwelling"] = "moon_facility"
	var picks: Array = depth.offer_picks(state, DeterministicRng.new(seed_value), ContentDatabase)
	var first_id: String = str(Dictionary(picks[0]).get("id", ""))
	depth.choose_affix(state, first_id, ContentDatabase)
	return state


func _affix_named(affix_id: String) -> Dictionary:
	for affix in DepthSystem.affixes(ContentDatabase):
		if affix is Dictionary and str(affix.get("id", "")) == affix_id:
			return affix.duplicate(true)
	return {}


func _has_status(state: RunState, status_id: String) -> bool:
	for status in Array(state.build.get("status_effects", [])):
		if status is Dictionary and str(status.get("id", "")) == status_id:
			return true
	return false
