extends TestCase

## The endgame layer: every location has exactly one boss contract. Qualification
## gates the Final Burn, committing locks the run onto it, and every prompt is
## measured against its requirements until it completes or fails.
##
## Completing it wins the run and opens the next location. Failing it ends the
## run. There is no ladder inside a run any more, and most of the tests below
## exist to keep it that way — the bug they guard against is a run that survived
## an ending in either direction.

const SCRATCH_PROFILE := "user://profile_test_ascension.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var restore_path: String = MetaProgress.profile_path
	var restore_enabled: bool = MetaProgress.enabled

	_test_an_unqualified_build_has_no_boss_on_the_table()
	_test_qualification_reports_every_unmet_condition()
	_test_the_boss_offered_belongs_to_the_run_s_location()
	_test_committing_locks_in_the_contract()
	_test_completing_a_contract_meets_its_requirement()
	_test_falling_short_of_the_deadline_fails_the_contract()
	_test_the_year_running_out_does_not_end_the_run()
	_test_overtime_costs_climb_every_round()
	_test_committing_in_overtime_still_wins_the_run()
	_test_overtime_still_ends_when_the_business_collapses()
	_test_overtime_closes_out_an_operation_earning_millions()
	_test_endless_stays_off_while_the_meta_layer_is_disabled()
	_test_qualification_latches_once_cleared()
	_test_beating_the_boss_wins_the_run()
	_test_beating_the_boss_unlocks_the_next_location()
	_test_a_failed_contract_ends_the_run()
	_test_no_ladder_state_is_left_in_the_run()
	_test_replaying_a_completed_location_offers_its_boss_again()
	_test_a_won_run_can_carry_on_into_endless()
	_test_run_score_reports_lifetime_tokens()
	_test_ascension_state_survives_a_save_round_trip()
	_test_a_save_mid_ladder_keeps_its_contract_and_sheds_the_rungs()

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


## Clears the bars the run's own location asks for, without having to actually
## buy every upgrade in the chapter.
func _qualify(sim: Node) -> void:
	_qualify_state(sim.run_state)


func _qualify_state(run_state: RunState) -> void:
	var thresholds: Dictionary = AscensionSystem.new().qualification_thresholds(
		run_state, ContentDatabase
	)
	run_state.calendar["round"] = maxi(6, int(thresholds.get("earliest_round", 1)))
	run_state.economy["last_round_costs"] = 100.0
	run_state.economy["income"] = 500.0
	run_state.statistics["peak_token_rate"] = float(
		thresholds.get("min_peak_token_rate", 0.0)
	) * 1.25 + 1.0


## Puts a run in a location without playing the chapters below it.
func _run_in(sim: Node, location: String) -> void:
	sim.apply_run_location(sim.run_state, location)


func _boss_id(sim: Node) -> String:
	return str(sim.ascension_boss_contract().get("id", ""))


func _test_an_unqualified_build_has_no_boss_on_the_table() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5001)
	assert_true(
		sim.ascension_eligible_contracts().is_empty(),
		"A fresh run with stock hardware has not qualified for anything yet"
	)
	assert_false(bool(sim.ascension_qualification().get("qualified", false)), "Qualification starts false")
	assert_eq(
		_boss_id(sim), "ascension.first_scale_up",
		"But the bedroom's boss is already named, so the goal is never invisible"
	)
	sim.free()


## The checklist is the whole point of the overlay, so each bar has to report
## itself rather than collapsing into one "not yet".
func _test_qualification_reports_every_unmet_condition() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5002)
	sim.run_state.calendar["round"] = 1
	sim.run_state.economy["last_round_costs"] = 100.0
	sim.run_state.economy["income"] = 10.0
	sim.run_state.statistics["peak_token_rate"] = 0.0
	var q: Dictionary = sim.ascension_qualification()
	assert_false(bool(q.get("round_ok", true)), "Round one is too early")
	assert_false(bool(q.get("peak_ok", true)), "A rig that has burned nothing has no peak rate")
	assert_false(bool(q.get("income_ok", true)), "And income does not cover the costs")
	var summary: Dictionary = sim.ascension_summary()
	assert_eq(int(summary.get("requirements_met", -1)), 0, "So nothing on the checklist is met")
	assert_eq(int(summary.get("requirements_total", 0)), 3, "Out of three bars")

	_qualify(sim)
	var later: Dictionary = sim.ascension_summary()
	assert_eq(int(later.get("requirements_met", 0)), 3, "Clearing all three clears the checklist")
	assert_true(bool(later.get("qualified", false)), "And the run qualifies")
	sim.free()


func _test_the_boss_offered_belongs_to_the_run_s_location() -> void:
	_fresh_profile()
	for pair in [
		["bedroom", "ascension.first_scale_up"],
		["garage", "ascension.million_token_operator"],
		["office_unit", "ascension.regional_provider"],
		["warehouse", "ascension.datacentre_magnate"],
		["datacentre_campus", "ascension.national_backbone"],
		["private_power_grid", "ascension.the_monopoly"],
		["moon_facility", "ascension.final_prompt"],
	]:
		var sim: Node = _sim()
		sim.start_run(5100)
		_run_in(sim, str(pair[0]))
		_qualify(sim)
		var eligible: Array = sim.ascension_eligible_contracts()
		assert_eq(eligible.size(), 1, "%s offers exactly one boss" % str(pair[0]))
		assert_eq(str(eligible[0].get("id", "")), str(pair[1]), "And it is the one that chapter owns")
		sim.free()


func _test_committing_locks_in_the_contract() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5003)
	_qualify(sim)
	assert_true(
		sim.commit_ascension_contract("ascension.million_token_operator") == false,
		"Another location's boss cannot be reached for"
	)
	assert_true(sim.commit_ascension_contract("ascension.first_scale_up"), "The location's boss can be committed to")
	assert_true(sim.ascension_active(), "The Final Burn is now underway")
	assert_false(
		sim.commit_ascension_contract("ascension.first_scale_up"),
		"A second commitment cannot be made on top of the first"
	)
	sim.free()


## Committing has to be earned: the overlay can be opened at any time, but the
## button behind it only works once the bars are clear.
func _test_completing_a_contract_meets_its_requirement() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5004)
	assert_false(
		sim.commit_ascension_contract("ascension.first_scale_up"),
		"An unqualified build cannot commit"
	)
	_qualify(sim)
	assert_true(sim.commit_ascension_contract("ascension.first_scale_up"), "Committed")
	_meet_requirement(sim, "ascension.first_scale_up")

	var result: Dictionary = AscensionSystem.new().evaluate_prompt(sim.run_state, ContentDatabase)
	assert_eq(str(result.get("outcome", "")), "completed", "The contract completes once the burn and quality bars clear")
	sim.free()


## Skips straight to "the burn requirement is met", which is what the prompt
## evaluator actually checks — the throughput and heat rolled up to now.
func _meet_requirement(sim: Node, contract_id: String) -> Dictionary:
	var contract: Dictionary = ContentDatabase.get_ascension_contract(contract_id)
	sim.run_state.statistics["lifetime_tokens"] = (
		float(sim.run_state.ascension.get("baseline_tokens", 0.0))
		+ float(contract.get("total_burn", 0.0)) + 1.0
	)
	sim.run_state.ascension["quality_sum"] = 100.0
	sim.run_state.ascension["quality_count"] = 1
	sim.run_state.compute["prompt_rate"] = float(contract.get("min_prompt_rate", 0.0)) * 2.0
	sim.run_state.compute["heat"] = 0.0
	return contract


func _test_falling_short_of_the_deadline_fails_the_contract() -> void:
	_fresh_profile()
	var ascension := AscensionSystem.new()
	var run_state := RunState.new()
	run_state.reset()
	_qualify_state(run_state)
	assert_true(ascension.commit(run_state, "ascension.first_scale_up", ContentDatabase), "Committed")
	var contract: Dictionary = ContentDatabase.get_ascension_contract("ascension.first_scale_up")
	var deadline: int = int(contract.get("deadline_prompts", 12))
	run_state.compute["prompt_rate"] = float(contract.get("min_prompt_rate", 0.0)) * 2.0
	var outcome: String = ""
	for _i in range(deadline + 2):
		var result: Dictionary = ascension.evaluate_prompt(run_state, ContentDatabase)
		outcome = str(result.get("outcome", ""))
		if outcome != "":
			break
	assert_eq(outcome, "failed", "Running out the clock without the burn requirement fails the contract")


## The reported bug: the player got past round twelve with no contract and the
## game simply stopped, with nothing having said one was needed. The calendar is
## no longer an ending — it hands the run to overtime instead.
func _test_the_year_running_out_does_not_end_the_run() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5005)
	sim.run_state.economy["cash"] = 500000.0
	sim.run_state.calendar["round"] = 12
	var rent_before: float = float(sim.run_state.economy.get("round_rent", 0.0))
	sim._end_round()
	assert_true(sim.phase != sim.Phase.RUN_END, "Reaching the end of the year does not end the run")
	assert_eq(str(sim.run_state.flags.get("outcome", "")), "", "Nothing has been decided yet")
	assert_true(sim.in_overtime(), "The run is in overtime")
	assert_eq(int(sim.run_state.statistics.get("overtime_rounds", 0)), 1, "One overtime round is on the clock")
	assert_eq(int(sim.run_state.calendar.get("round", 0)), 13, "And play carries on into a thirteenth round")
	assert_true(
		float(sim.run_state.economy.get("round_rent", 0.0)) > rent_before,
		"Overtime immediately costs more than the year did"
	)
	assert_eq(MetaProgress.pending_picks(), 0, "Nothing is banked for outlasting the calendar")
	sim.free()


## Overtime has to be pressure, not a plateau, or a stalled run never resolves.
func _test_overtime_costs_climb_every_round() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5011)
	sim.run_state.economy["cash"] = 5000000.0
	sim.run_state.calendar["round"] = 12
	var rents: Array[float] = []
	for _i in range(3):
		sim._end_round()
		if sim.phase == sim.Phase.RUN_END:
			break
		rents.append(float(sim.run_state.economy.get("round_rent", 0.0)))
	assert_true(rents.size() >= 3, "Three overtime rounds are playable")
	for i in range(1, rents.size()):
		assert_true(rents[i] > rents[i - 1], "Rent climbs again on overtime round %d" % (i + 1))
	sim.free()


## Overtime is not a dead end: committing there still counts, and clearing the
## boss in it wins the run rather than leaving it stranded.
func _test_committing_in_overtime_still_wins_the_run() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5012)
	sim.run_state.economy["cash"] = 500000.0
	sim.run_state.calendar["round"] = 12
	sim._end_round()
	assert_true(sim.in_overtime(), "In overtime")
	_qualify(sim)
	sim.run_state.calendar["round"] = 13
	assert_true(
		sim.commit_ascension_contract("ascension.first_scale_up"),
		"A contract can still be committed to after the year has run out"
	)
	_meet_requirement(sim, "ascension.first_scale_up")
	sim._finish_prompt({"ok": true, "messages": []})
	assert_eq(sim.phase, sim.Phase.RUN_END, "Finishing it in overtime still wins the run")
	assert_true(bool(sim.run_state.flags.get("victory", false)), "As a victory")
	sim.free()


## The other way out. Overtime must terminate on its own, or a run that never
## reaches for a contract simply never finishes.
func _test_overtime_still_ends_when_the_business_collapses() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5013)
	sim.run_state.economy["cash"] = 500000.0
	sim.run_state.calendar["round"] = 12
	sim._end_round()
	assert_true(sim.in_overtime(), "In overtime")
	sim.run_state.economy["cash"] = -50000.0
	sim._end_round()
	assert_eq(sim.phase, sim.Phase.RUN_END, "Overtime ends the run when the bills finally win")
	assert_false(bool(sim.run_state.flags.get("victory", false)), "And it ends as a loss, not an ending")
	sim.free()


## Escalating rent alone cannot close out a big operation: rent starts in the
## hundreds and a late-game rig earns millions a round, so a multiplier on the
## small number never catches up and overtime runs for ever. The levy is charged
## against earnings for exactly this reason.
func _test_overtime_closes_out_an_operation_earning_millions() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5015)
	const EARNED_PER_ROUND := 1000000.0
	sim.run_state.economy["cash"] = EARNED_PER_ROUND * 3.0
	sim.run_state.calendar["round"] = 12
	var rounds: int = 0
	while sim.phase != sim.Phase.RUN_END and rounds < 40:
		rounds += 1
		# Stands in for a round's work: the money comes in, the bills follow.
		sim.run_state.economy["cash"] = float(sim.run_state.economy.get("cash", 0.0)) + EARNED_PER_ROUND
		sim.run_state.economy["income"] = float(sim.run_state.economy.get("income", 0.0)) + EARNED_PER_ROUND
		sim._end_round()
	assert_eq(sim.phase, sim.Phase.RUN_END, "Overtime ends a run earning millions a round, not just a poor one")
	assert_false(bool(sim.run_state.flags.get("victory", false)), "And it ends as a loss")
	assert_true(
		int(sim.run_state.statistics.get("overtime_rounds", 0)) <= 12,
		"Within a dozen overtime rounds rather than indefinitely (took %d)" % int(
			sim.run_state.statistics.get("overtime_rounds", 0)
		)
	)
	sim.free()


## Endless mode is a profile unlock, and a run measured with the meta layer off
## must not silently inherit it: doing so replaced overtime's hard deadline with
## endless mode's gentle one and left batch runs that never terminated.
func _test_endless_stays_off_while_the_meta_layer_is_disabled() -> void:
	_fresh_profile()
	MetaProgress.set_endless_enabled(true)
	MetaProgress.enabled = false
	assert_false(MetaProgress.endless_enabled(), "Endless reads as off with the meta layer disabled")
	var sim: Node = _sim()
	sim.start_run(5016)
	sim.run_state.economy["cash"] = 500000.0
	sim.run_state.calendar["round"] = 12
	sim._end_round()
	assert_true(sim.in_overtime(), "So the end of the year goes into overtime rather than endless mode")
	sim.free()


## The way into the endgame must not blink out again because one round's income
## dipped under the bar.
func _test_qualification_latches_once_cleared() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5014)
	_qualify(sim)
	assert_true(bool(sim.ascension_qualification().get("qualified", false)), "The build qualifies")
	sim.run_state.economy["income"] = 0.0
	var later: Dictionary = sim.ascension_qualification()
	assert_false(bool(later.get("income_ok", true)), "A bad round is still reported as a bad round")
	assert_true(bool(later.get("qualified", false)), "But qualification, once cleared, stays cleared")
	assert_true(sim.ascension_eligible_contracts().size() > 0, "And the boss stays on the table")
	sim.free()


## The redesign in one test: there is no rung any more, so the first contract a
## run completes is the last thing it does.
func _test_beating_the_boss_wins_the_run() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5020)
	_qualify(sim)
	assert_true(sim.commit_ascension_contract("ascension.first_scale_up"), "Committed to the bedroom's boss")
	var contract: Dictionary = _meet_requirement(sim, "ascension.first_scale_up")
	sim._finish_prompt({"ok": true, "messages": []})

	assert_eq(sim.phase, sim.Phase.RUN_END, "Completing the boss ends the run")
	assert_true(bool(sim.run_state.flags.get("victory", false)), "As a victory")
	assert_eq(str(sim.run_state.flags.get("outcome", "")), "ascended", "Named as an ascension")
	assert_false(sim.ascension_active(), "The Final Burn is over")
	assert_eq(
		MetaProgress.pending_picks(), int(contract.get("picks", 1)),
		"And it banks its picks for the next run"
	)
	assert_eq(
		MetaProgress.ascension_completions("ascension.first_scale_up"), 1,
		"The profile remembers which contract was completed"
	)
	sim.free()


func _test_beating_the_boss_unlocks_the_next_location() -> void:
	_fresh_profile()
	assert_false(MetaProgress.is_location_unlocked("garage"), "The garage starts locked")
	var sim: Node = _sim()
	sim.start_run(5024)
	_qualify(sim)
	assert_true(sim.commit_ascension_contract("ascension.first_scale_up"), "Committed")
	_meet_requirement(sim, "ascension.first_scale_up")
	sim._finish_prompt({"ok": true, "messages": []})

	assert_true("bedroom" in MetaProgress.completed_locations(), "The bedroom is behind the player")
	assert_true(MetaProgress.is_location_unlocked("garage"), "And the garage is open")
	assert_eq(sim.next_location_unlocked(), "garage", "Which the verdict screen can name")
	sim.free()


func _test_a_failed_contract_ends_the_run() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5025)
	_qualify(sim)
	assert_true(sim.commit_ascension_contract("ascension.first_scale_up"), "Committed")
	var contract: Dictionary = ContentDatabase.get_ascension_contract("ascension.first_scale_up")
	sim.run_state.statistics["hidden_bugs_shipped"] = int(contract.get("max_hidden_bugs", 0)) + 1
	sim._finish_prompt({"ok": true, "messages": []})

	assert_eq(sim.phase, sim.Phase.RUN_END, "Failing the contract ends the run")
	assert_false(bool(sim.run_state.flags.get("victory", false)), "As a loss")
	assert_eq(str(sim.run_state.flags.get("outcome", "")), "ascension_failed", "Named as the contract failing")
	assert_false(MetaProgress.is_location_unlocked("garage"), "And nothing is unlocked by losing")
	sim.free()


func _test_no_ladder_state_is_left_in_the_run() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5026)
	for stale in ["completed_ids", "highest_tier_completed", "pending_picks"]:
		assert_false(
			sim.run_state.ascension.has(stale),
			"A run carries no ladder state: %s is gone" % stale
		)
	sim.free()


## Replaying a chapter already beaten is allowed, and its boss is still the way
## out of it — the campaign is the ladder, not the run.
func _test_replaying_a_completed_location_offers_its_boss_again() -> void:
	_fresh_profile()
	MetaProgress.complete_location("bedroom")
	var sim: Node = _sim()
	sim.start_run(5027)
	_run_in(sim, "bedroom")
	_qualify(sim)
	var eligible: Array = sim.ascension_eligible_contracts()
	assert_eq(eligible.size(), 1, "The bedroom still has its boss")
	assert_eq(str(eligible[0].get("id", "")), "ascension.first_scale_up", "And it is the same one")
	sim.free()


## Beating the game does not have to take the build away with it: the run carries
## on, past the calendar, under costs that climb every round.
func _test_a_won_run_can_carry_on_into_endless() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5023)
	_run_in(sim, "private_power_grid")
	_qualify(sim)
	sim.run_state.economy["cash"] = 5000000.0
	assert_true(sim.commit_ascension_contract("ascension.the_monopoly"), "Committed to a finale")
	_meet_requirement(sim, "ascension.the_monopoly")
	sim._finish_prompt({"ok": true, "messages": []})
	assert_eq(sim.phase, sim.Phase.RUN_END, "The run is won")

	var tokens_before: float = float(sim.run_state.statistics.get("lifetime_tokens", 0.0))
	assert_true(sim.continue_after_victory(), "And can be carried on")
	assert_true(sim.phase != sim.Phase.RUN_END, "Which puts it back into play")
	assert_true(sim.in_post_victory(), "Flagged as a run past its ending")
	assert_almost_eq(
		float(sim.run_state.statistics.get("lifetime_tokens", 0.0)), tokens_before, 0.01,
		"With everything it burned still on the board"
	)
	assert_false(sim.continue_after_victory(), "There is only one ending to carry on from")

	# Past the calendar a won run escalates like endless mode rather than being
	# put back under overtime's levy, which exists to force a finish it has had.
	sim.run_state.calendar["round"] = 12
	var rent_before: float = float(sim.run_state.economy.get("round_rent", 0.0))
	sim._end_round()
	assert_false(sim.in_overtime(), "A won run is not hurried into overtime")
	assert_true(
		float(sim.run_state.economy.get("round_rent", 0.0)) > rent_before,
		"But the bills still climb every round past the twelfth"
	)
	assert_true(
		int(sim.run_state.statistics.get("endless_rounds", 0)) > 0,
		"And the tail is counted as endless rounds"
	)
	sim.free()


func _test_run_score_reports_lifetime_tokens() -> void:
	_fresh_profile()
	var run_state := RunState.new()
	run_state.reset()
	run_state.statistics["lifetime_tokens"] = 42000000.0
	var score: Dictionary = RunScore.compute(run_state, ContentDatabase)
	assert_almost_eq(
		float(score.get("total_tokens_burned", 0.0)), 42000000.0, 0.01, "The score headline is lifetime tokens burned"
	)
	assert_true(
		RunScore.headline(score).begins_with("TOTAL TOKENS BURNED"),
		"The headline says what it is measuring"
	)


## A save mid Final Burn has to come back with the contract still committed,
## not silently reset to "nothing underway".
func _test_ascension_state_survives_a_save_round_trip() -> void:
	var ascension := AscensionSystem.new()
	var run_state := RunState.new()
	run_state.reset()
	_qualify_state(run_state)
	assert_true(ascension.commit(run_state, "ascension.first_scale_up", ContentDatabase), "Committed")
	run_state.ascension["tokens_burned"] = 12345.0
	run_state.ascension["violations"] = 2

	var reloaded := RunState.new()
	reloaded.from_dict(run_state.to_dict())
	assert_eq(str(reloaded.ascension.get("status", "")), "committed", "Commitment survives a save")
	assert_eq(str(reloaded.ascension.get("contract_id", "")), "ascension.first_scale_up", "So does which contract")
	assert_almost_eq(float(reloaded.ascension.get("tokens_burned", 0.0)), 12345.0, 0.01, "So does progress")
	assert_eq(int(reloaded.ascension.get("violations", 0)), 2, "So does the violation count")


## A save written part-way up the old ladder: the contract it was burning for is
## now the run's boss, and the rungs it had climbed have nowhere to go.
func _test_a_save_mid_ladder_keeps_its_contract_and_sheds_the_rungs() -> void:
	var run_state := RunState.new()
	run_state.reset()
	run_state.from_dict({
		"save_version": 10,
		"ascension": {
			"status": "committed",
			"contract_id": "ascension.first_scale_up",
			"committed_round": 5,
			"baseline_tokens": 100.0,
			"tokens_burned": 50.0,
			"prompts_remaining": 8,
			"violations": 1,
			"quality_sum": 40.0,
			"quality_count": 1,
			"completed_ids": ["ascension.first_scale_up"],
			"highest_tier_completed": 1,
			"pending_picks": 2,
		},
	})
	assert_eq(str(run_state.ascension.get("status", "")), "committed", "The contract stays committed")
	assert_eq(
		str(run_state.ascension.get("contract_id", "")), "ascension.first_scale_up",
		"And it is still the run's boss"
	)
	assert_eq(int(run_state.ascension.get("prompts_remaining", 0)), 8, "With its deadline where it was")
	for stale in ["completed_ids", "highest_tier_completed", "pending_picks"]:
		assert_false(run_state.ascension.has(stale), "The ladder field %s is gone" % stale)
