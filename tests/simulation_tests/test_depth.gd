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
	_test_continue_after_depth_refuses_a_loss()
	_test_target_x5_is_unlimited()
	_test_later_prompt_does_not_recomplete()
	_test_depth_complete_settles_the_active_session()
	_test_depth_score_accrues_at_the_live_multiplier()


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
	assert_true(
		int(after.get("deadline_prompts", 0)) > int(before.get("deadline_prompts", 0)),
		"The deadline is sized from the depth-adjusted workload"
	)


func _test_scoreboard_names_depth() -> void:
	var state := RunState.new()
	state.statistics["lifetime_tokens"] = 1000.0
	state.statistics["depth_score"] = 2000.0
	state.statistics["depth_reached"] = 2
	state.depth["score_mult"] = 3.0
	var score: Dictionary = RunScore.compute(state, ContentDatabase)
	assert_eq(int(score.get("depth_reached", 0)), 2, "Depth reached is scored")
	assert_almost_eq(float(score.get("depth_score", 0.0)), 2000.0, 0.01, "Accrued depth score is what the debrief prints")
	var labels: Array = []
	for row in RunScore.rows(score):
		labels.append(str(row.get("label", "")))
	assert_true("Deep Burn depth" in labels, "The debrief names the depth")
	assert_true("Deep Burn score" in labels, "And prints the accrued depth score")


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
	assert_true(bool(done.get("newly_complete", false)), "The crossing is a one-shot transition")
	assert_eq(str(state.depth.get("status", "")), DepthSystem.STATUS_COMPLETE, "Status latches to complete")
	var again: Dictionary = depth.evaluate_prompt(state)
	assert_eq(str(again.get("outcome", "")), DepthSystem.STATUS_COMPLETE, "A later prompt still reports complete")
	assert_false(bool(again.get("newly_complete", true)), "A later prompt does not re-fire the crossing")
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


func _test_continue_after_depth_refuses_a_loss() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(9710)
	sim.run_state.flags["post_victory"] = true
	sim.run_state.flags["outcome"] = "collapsed"
	sim.run_state.flags["depth_complete"] = false
	sim.run_state.depth["level"] = 4
	sim.phase = sim.Phase.RUN_END
	assert_false(
		sim.continue_after_depth(),
		"A Deep Burn loss cannot be continued just because the run was already endless"
	)
	assert_eq(sim.phase, sim.Phase.RUN_END, "The failed run stays ended")
	sim.free()


func _test_target_x5_is_unlimited() -> void:
	var target := _affix_named("depth.target_x5")
	assert_false(target.is_empty(), "Target ×5 is authored")
	assert_true(bool(target.get("repeatable", false)), "Target ×5 stays repeatable")
	assert_eq(int(target.get("max_stacks", -1)), 0, "Zero stacks means the generic escalation never caps")
	var depth := DepthSystem.new()
	var state := RunState.new()
	state.build["dwelling"] = "moon_facility"
	state.depth["stacks"] = {
		"depth.target_x5": 20,
		"depth.thin_cooling": 5,
		"depth.hidden_bug": 5,
	}
	var picks: Array = depth.offer_picks(state, DeterministicRng.new(9707), ContentDatabase)
	var ids: Array = []
	for pick in picks:
		if pick is Dictionary:
			ids.append(str(pick.get("id", "")))
	assert_true("depth.target_x5" in ids, "After every thematic affix is capped, Target ×5 is still offered")


func _test_later_prompt_does_not_recomplete() -> void:
	var depth := DepthSystem.new()
	var state := _moon_at_depth(depth, 9708)
	state.statistics["lifetime_tokens"] = (
		float(state.depth.get("baseline_tokens", 0.0)) + float(state.depth.get("tokens_needed", 0.0))
	)
	assert_true(bool(depth.evaluate_prompt(state).get("newly_complete", false)), "First crossing fires")
	assert_false(
		bool(depth.evaluate_prompt(state).get("newly_complete", true)),
		"A complete depth does not cross again"
	)


func _test_depth_complete_settles_the_active_session() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(9709)
	sim.run_state.ascension["status"] = AscensionSystem.STATUS_COMPLETED
	sim.run_state.flags["post_victory"] = true
	sim.run_state.economy["cash"] = 1e15
	var depth: DepthSystem = sim.depth_system()
	var opening: Array = depth.offer_picks(sim.run_state, DeterministicRng.new(9709), ContentDatabase)
	assert_true(not opening.is_empty(), "Depth 1 can be opened")
	assert_true(
		depth.choose_affix(sim.run_state, str(Dictionary(opening[0]).get("id", "")), ContentDatabase),
		"Depth 1 starts"
	)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(not offers.is_empty(), "A desk is waiting")
	assert_true(sim.accept_job(str(Dictionary(offers[0]).get("id", ""))), "A Depth 1 contract is taken")
	sim.start_work()
	var job: Dictionary = sim.focused_job()
	assert_true(not job.is_empty(), "The contract is on the machine")
	job["token_requirement"] = 1e12
	job["tokens_remaining"] = 1e12
	sim.run_state.depth["baseline_tokens"] = float(sim.run_state.statistics.get("lifetime_tokens", 0.0))
	sim.run_state.depth["tokens_needed"] = 1.0
	sim.run_state.depth["status"] = DepthSystem.STATUS_ACTIVE
	var failed_before: int = int(sim.run_state.statistics.get("failed_jobs", 0))
	var result: Dictionary = sim.burn_batch()
	assert_true(result.get("ok", false), "The completing burn lands")
	assert_eq(sim.phase, sim.Phase.IN_ROUND, "Crossing the target does not close the desk")
	assert_true(
		not Array(sim.run_state.business.get("active_jobs", [])).is_empty(),
		"Live contracts stay on the machine"
	)
	assert_true(
		float(sim.focused_job().get("tokens_remaining", 0.0)) > 0.0,
		"The unfinished contract is not force-failed"
	)
	assert_true(
		bool(sim.run_state.flags.get("depth_complete_pending", false)),
		"The crossing is latched until the session ends normally"
	)
	assert_false(bool(sim.run_state.flags.get("depth_complete", true)), "DEPTH COMPLETE waits")
	assert_eq(str(sim.run_state.depth.get("status", "")), DepthSystem.STATUS_COMPLETE, "The depth latched")
	assert_eq(
		int(sim.run_state.statistics.get("failed_jobs", -1)), failed_before,
		"Crossing the target is not a reputation of failed contracts"
	)
	assert_true(sim.can_burn(), "The session stays burnable after the crossing")
	assert_true(sim.ship_focused_job(), "The current contract can still be delivered")
	assert_eq(sim.phase, sim.Phase.RUN_END, "DEPTH COMPLETE opens after a normal settle")
	assert_true(
		Array(sim.run_state.business.get("active_jobs", [])).is_empty(),
		"The live desk is settled before the overlay"
	)
	assert_true(sim.focused_job().is_empty(), "Nothing remains focused")
	assert_true(bool(sim.run_state.flags.get("depth_complete", false)), "The overlay flag is set")
	assert_eq(
		int(sim.run_state.statistics.get("failed_jobs", -1)), failed_before,
		"A finished contract is not counted as a depth-forced failure"
	)
	var picks: Array = sim.offer_depth_picks()
	assert_true(not picks.is_empty(), "The next affix draft is available")
	var next_id: String = str(Dictionary(picks[0]).get("id", ""))
	var req_before: float = float(sim.run_state.depth.get("requirement_mult", 1.0))
	assert_true(bool(sim.choose_depth_affix(next_id).get("ok", false)), "The next affix lands")
	assert_eq(int(sim.run_state.depth.get("level", 0)), 2, "Depth advances to 2")
	assert_eq(str(sim.run_state.depth.get("status", "")), DepthSystem.STATUS_ACTIVE, "Depth 2 is live")
	assert_true(
		float(sim.run_state.depth.get("requirement_mult", 1.0)) > req_before,
		"Depth 2 measures a larger contract"
	)
	assert_true(sim.continue_after_depth(), "Continue leaves the overlay")
	assert_eq(sim.phase, sim.Phase.ROUND_PREP, "Play resumes at a fresh desk")
	assert_true(
		Array(sim.run_state.business.get("active_jobs", [])).is_empty(),
		"No Depth 1 contract survives the boundary"
	)
	var next_offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(not next_offers.is_empty(), "Fresh Depth N+1 work is generated")
	assert_true(sim.accept_job(str(Dictionary(next_offers[0]).get("id", ""))), "The new contract can be taken")
	assert_true(sim.can_start_work(), "A new session can open")
	sim.start_work()
	assert_true(sim.can_burn(), "Burn remains possible after the depth boundary")
	sim.free()


func _test_depth_score_accrues_at_the_live_multiplier() -> void:
	var state := RunState.new()
	state.depth["level"] = 1
	state.depth["score_mult"] = 3.0
	state.statistics["lifetime_tokens"] = 1e20
	DepthSystem.record_tokens(state, 1000.0)
	assert_almost_eq(
		float(state.statistics.get("depth_score", 0.0)), 2000.0, 0.01,
		"Only tokens burned during Deep Burn earn the live multiplier"
	)
	state.depth["score_mult"] = 6.0
	DepthSystem.record_tokens(state, 1000.0)
	assert_almost_eq(
		float(state.statistics.get("depth_score", 0.0)), 7000.0, 0.01,
		"A later stack does not rewrite earlier burns"
	)
	var score: Dictionary = RunScore.compute(state, ContentDatabase)
	assert_almost_eq(
		float(score.get("depth_score", 0.0)), 7000.0, 0.01,
		"Campaign tokens burned before Deep Burn are not multiplied in"
	)


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
