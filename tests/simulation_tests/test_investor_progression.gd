extends TestCase

## The investor's ladder as a whole: a run is under target 1 from its first
## prompt, ordinary work does not move the level, meeting the target moves it
## exactly once, each target is bigger than the last, the perk draft is dealt
## once and gates the move, and every deadline is counted on the run's one
## continuous calendar rather than a calendar that restarts per level.

const SCRATCH_PROFILE := "user://profile_test_investor_progression.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var restore_path: String = MetaProgress.profile_path
	var restore_enabled: bool = MetaProgress.enabled

	_test_a_run_starts_at_level_one_under_target_one()
	_test_a_normal_job_does_not_advance_the_level()
	_test_meeting_the_target_advances_exactly_once()
	_test_each_target_is_harder_than_the_last()
	_test_the_draft_is_dealt_once_and_gates_the_move()
	_test_the_deadline_is_counted_on_the_continuous_calendar()

	if FileAccess.file_exists(SCRATCH_PROFILE):
		DirAccess.remove_absolute(SCRATCH_PROFILE)
	MetaProgress.profile_path = restore_path
	MetaProgress.enabled = restore_enabled
	MetaProgress._loaded = false


func _fresh_profile() -> void:
	MetaProgress.enabled = true
	MetaProgress.use_scratch_profile(SCRATCH_PROFILE)


func _sim() -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	return sim


## Meets the live target's burn requirement and delivers the prompt that
## checks it, which is how a target is actually met.
func _meet_target(sim: Node) -> void:
	var target: Dictionary = sim.investor_target()
	sim.run_state.statistics["lifetime_tokens"] = (
		float(sim.run_state.investor.get("baseline_tokens", 0.0))
		+ float(target.get("total_burn", 0.0)) + 1.0
	)
	sim.run_state.investor["quality_sum"] = 100.0
	sim.run_state.investor["quality_count"] = 1
	sim.debug_finish_prompt({"ok": true, "messages": []})


## A trivial contract on the queue: one token, no quality bar, a generous
## deadline, so one work session settles it.
func _queue_trivial_job(sim: Node) -> void:
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


func _test_a_run_starts_at_level_one_under_target_one() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9101)
	assert_eq(sim.investor_level(), InvestorProgression.FIRST_LEVEL, "A fresh run is at Investor Level 1")
	assert_eq(int(sim.run_state.investor.get("targets_completed", -1)), 0, "With no targets behind it")
	assert_true(sim.investor_active(), "And already under a live target")
	var target: Dictionary = sim.investor_target()
	assert_eq(int(target.get("level", 0)), 1, "Which is the level 1 target")
	assert_eq(
		str(target.get("id", "")),
		str(InvestorProgression.authored_target_for_level(1, ContentDatabase).get("id", "")),
		"The authored one for that level"
	)
	assert_eq(
		str(sim.run_state.investor.get("contract_id", "")), str(target.get("id", "")),
		"Named in the run state"
	)
	assert_false(bool(target.get("final", false)), "The first target is not the game's end")
	assert_almost_eq(
		float(sim.run_state.investor.get("baseline_tokens", 0.0)), 0.0, 0.01,
		"Measured from a run that has burned nothing"
	)
	assert_eq(
		int(sim.run_state.investor.get("deadline_round", 0)),
		InvestorProgression.deadline_rounds_for(target),
		"With its deadline the target's own length from round one"
	)
	sim.free()


func _test_a_normal_job_does_not_advance_the_level() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9102)
	sim.run_state.economy["cash"] = 50000.0
	var target_before: String = str(sim.run_state.investor.get("contract_id", ""))
	var baseline_before: float = float(sim.run_state.investor.get("baseline_tokens", 0.0))
	var deadline_before: int = int(sim.run_state.investor.get("deadline_round", 0))
	for _round in range(3):
		_queue_trivial_job(sim)
		sim.start_work_sync()
		assert_eq(sim.phase, sim.Phase.ROUND_PREP, "A settled round goes to the next prep")
		assert_eq(sim.investor_level(), 1, "Delivering a contract does not move the Investor Level")
		assert_eq(int(sim.run_state.investor.get("targets_completed", 0)), 0, "Nor counts a target")
		assert_false(bool(sim.run_state.flags.get("target_complete", false)), "Nor flags one met")
		assert_false(bool(sim.run_state.flags.get("victory", false)), "Nor wins anything")
	assert_true(sim.investor_active(), "The target is still live")
	assert_eq(str(sim.run_state.investor.get("contract_id", "")), target_before, "And still the same one")
	assert_almost_eq(
		float(sim.run_state.investor.get("baseline_tokens", 0.0)), baseline_before, 0.01,
		"Measured from the same baseline"
	)
	assert_eq(int(sim.run_state.investor.get("deadline_round", 0)), deadline_before, "Against the same deadline")
	assert_eq(int(sim.run_state.calendar.get("round", 0)), 4, "Three rounds have passed on the calendar")
	sim.free()


func _test_meeting_the_target_advances_exactly_once() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9103)
	var advanced: Array = []
	var on_advanced := func(level: int) -> void: advanced.append(level)
	EventBus.investor_level_advanced.connect(on_advanced)
	var completed: Array = []
	var on_completed := func(level: int, final: bool) -> void: completed.append([level, final])
	EventBus.investor_target_completed.connect(on_completed)

	_meet_target(sim)
	assert_eq(sim.phase, sim.Phase.RUN_END, "Meeting the target closes the level on the verdict")
	assert_true(bool(sim.run_state.flags.get("target_complete", false)), "Flagged as a target met")
	assert_eq(sim.investor_level(), 1, "The level itself waits for the player to take the next target")
	assert_eq(int(sim.run_state.investor.get("targets_completed", 0)), 0, "As does the count")
	assert_eq(completed, [[1, false]], "The target-completed event fires once, for level 1, not final")
	assert_true(advanced.is_empty(), "Nothing has advanced yet")

	sim.decline_offers()
	assert_true(sim.continue_after_target(), "Taking the next target goes through")
	assert_eq(sim.investor_level(), 2, "The Investor Level is 2")
	assert_eq(int(sim.run_state.investor.get("targets_completed", 0)), 1, "One target behind it")
	assert_eq(int(sim.investor_target().get("level", 0)), 2, "Under the level 2 target")
	assert_eq(str(sim.run_state.investor.get("status", "")), InvestorProgression.STATUS_ACTIVE, "Which is live")
	assert_eq(advanced, [2], "The level-advanced event fired exactly once")
	assert_false(bool(sim.run_state.flags.get("target_complete", false)), "The met flag is cleared")
	assert_false(bool(sim.run_state.flags.get("victory", false)), "So is the victory")

	assert_false(sim.continue_after_target(), "Advancing again on a live run is refused")
	assert_eq(sim.investor_level(), 2, "The level does not move a second time")
	assert_eq(int(sim.run_state.investor.get("targets_completed", 0)), 1, "Nor the count")
	assert_eq(advanced, [2], "And no second event")
	EventBus.investor_level_advanced.disconnect(on_advanced)
	EventBus.investor_target_completed.disconnect(on_completed)
	sim.free()


## Every authored level asks for more burn than the one before it, and the
## generated tail past the final target keeps climbing.
func _test_each_target_is_harder_than_the_last() -> void:
	var final_level: int = InvestorProgression.final_level(ContentDatabase)
	assert_true(final_level >= 2, "There is more than one target to compare")
	for level in range(2, final_level + 1):
		var previous: Dictionary = InvestorProgression.target_for_level(level - 1, ContentDatabase)
		var current: Dictionary = InvestorProgression.target_for_level(level, ContentDatabase)
		assert_true(
			float(current.get("total_burn", 0.0)) > float(previous.get("total_burn", 0.0)),
			"Target %d asks for more burn (%s) than target %d (%s)" % [
				level, str(current.get("total_burn", 0.0)), level - 1, str(previous.get("total_burn", 0.0)),
			]
		)
	for level in range(final_level + 1, final_level + 4):
		var previous: Dictionary = InvestorProgression.target_for_level(level - 1, ContentDatabase)
		var current: Dictionary = InvestorProgression.target_for_level(level, ContentDatabase)
		assert_true(bool(current.get("generated", false)), "Level %d past the final is generated" % level)
		assert_true(
			float(current.get("total_burn", 0.0)) > float(previous.get("total_burn", 0.0)),
			"And generated target %d still asks for more than the one before" % level
		)

	# The same is true of a run walking up: the target it lands on after a
	# win is bigger than the one it just met.
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9104)
	var met: Dictionary = sim.investor_target()
	_meet_target(sim)
	sim.decline_offers()
	assert_true(sim.continue_after_target(), "The company takes the next target")
	var next: Dictionary = sim.investor_target()
	assert_true(
		float(next.get("total_burn", 0.0)) > float(met.get("total_burn", 0.0)),
		"The next target's burn is larger than the one just met"
	)
	assert_almost_eq(
		float(sim.investor_progress().get("tokens_burned", -1.0)), 0.0, 1.0,
		"And it is measured from zero, not pre-paid by the old level's burn"
	)
	sim.free()


func _test_the_draft_is_dealt_once_and_gates_the_move() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9105)
	var sequence_before: int = int(
		Dictionary(sim.run_state.build.get("draft_state", {})).get("sequence", 0)
	)
	_meet_target(sim)
	assert_true(sim.investor_draft_pending(), "Meeting the target deals the investor's perk table")
	assert_eq(sim.draft_kind(), sim.DRAFT_INVESTOR, "Titled for the investor")
	assert_eq(
		int(Dictionary(sim.run_state.build.get("draft_state", {})).get("sequence", 0)),
		sequence_before + 1,
		"Exactly one table was dealt"
	)
	var dealt: Array = []
	for offer in sim.pending_choices:
		dealt.append(str(offer.get("id", "")))
	assert_false(sim.continue_after_target(), "The company cannot move with the table unanswered")
	assert_eq(sim.phase, sim.Phase.RUN_END, "The verdict stays up")
	assert_eq(sim.investor_level(), 1, "And the level has not moved")
	var redealt: Array = []
	for offer in sim.pending_choices:
		redealt.append(str(offer.get("id", "")))
	assert_eq(redealt, dealt, "The refused move did not redeal the table")
	assert_eq(
		int(Dictionary(sim.run_state.build.get("draft_state", {})).get("sequence", 0)),
		sequence_before + 1,
		"Still exactly one table"
	)

	var perk_id: String = dealt[0]
	assert_true(sim.accept_offer("perk", perk_id), "A card is taken")
	assert_false(sim.investor_draft_pending(), "Which resolves the draft")
	assert_true(sim.continue_after_target(), "And now the move goes through")
	assert_eq(sim.investor_level(), 2, "Up to Investor Level 2")
	assert_true(perk_id in sim.owned_perk_ids(), "With the perk in the build")
	assert_true(sim.pending_choices.is_empty(), "And nothing left on the table")
	assert_eq(
		int(Dictionary(sim.run_state.build.get("draft_state", {})).get("sequence", 0)),
		sequence_before + 1,
		"The move dealt nothing more"
	)
	sim.free()


## The calendar is the run's, not the level's. A target met in round five is
## followed by a target due `deadline_rounds` from the round it went live on;
## nothing sets the round back to one.
func _test_the_deadline_is_counted_on_the_continuous_calendar() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9106)
	sim.run_state.economy["cash"] = 100000.0
	sim.run_state.calendar["round"] = 5
	_meet_target(sim)
	assert_eq(sim.phase, sim.Phase.RUN_END, "The target is met in round five")
	# Settling the winning round rolls the calendar into the next round's prep.
	var round_now: int = int(sim.run_state.calendar.get("round", 0))
	assert_eq(round_now, 6, "Settlement rolled the calendar to round six")

	sim.decline_offers()
	assert_true(sim.continue_after_target(), "The company takes the next target")
	assert_eq(int(sim.run_state.calendar.get("round", 0)), round_now, "The round is not reset by the move")
	assert_eq(int(sim.run_state.calendar.get("prompt", 0)), 1, "Only the prompt counter is fresh for the round")
	var target: Dictionary = sim.investor_target()
	var expected_deadline: int = round_now + InvestorProgression.deadline_rounds_for(target) - 1
	assert_eq(
		int(sim.run_state.investor.get("deadline_round", 0)), expected_deadline,
		"The new deadline is the current round plus the target's length, less one"
	)
	assert_eq(
		int(sim.investor_progress().get("deadline_round", 0)), expected_deadline,
		"And that is what the progress readout reports"
	)
	assert_eq(
		int(sim.investor_progress().get("rounds_remaining", 0)),
		InvestorProgression.deadline_rounds_for(target),
		"With the whole allowance still ahead"
	)
	assert_eq(sim.rounds_remaining(), InvestorProgression.deadline_rounds_for(target), "Which the run agrees with")
	assert_true(
		expected_deadline > InvestorProgression.deadline_rounds_for(target),
		"So the deadline sits past where a restarted calendar would put it"
	)
	sim.free()
