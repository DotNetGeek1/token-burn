extends TestCase

## The endgame layer: qualification gates the Final Burn, committing to a
## contract locks the run onto it, and every prompt is measured against the
## contract's requirements until it completes, fails, or the clock runs out.
##
## Contracts are a three-rung ladder. Tiers 1 and 2 are level-ups that hand the
## run back with reward picks to spend on it; only a Tier 3 contract wins, and even
## then the run can be carried on. The tests below are mostly about that
## distinction, because the bug they exist for is a run that ended on rung one.

const SCRATCH_PROFILE := "user://profile_test_ascension.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var restore_path: String = MetaProgress.profile_path
	var restore_enabled: bool = MetaProgress.enabled

	_test_an_unqualified_build_has_no_eligible_contracts()
	_test_qualifying_opens_eligible_contracts()
	_test_committing_locks_in_the_contract()
	_test_completing_a_contract_meets_its_requirement()
	_test_falling_short_of_the_deadline_fails_the_contract()
	_test_the_year_running_out_does_not_end_the_run()
	_test_overtime_costs_climb_every_round()
	_test_committing_in_overtime_still_climbs_a_rung()
	_test_overtime_still_ends_when_the_business_collapses()
	_test_overtime_closes_out_an_operation_earning_millions()
	_test_endless_stays_off_while_the_meta_layer_is_disabled()
	_test_qualification_latches_once_cleared()
	_test_a_rung_hands_the_run_back()
	_test_the_ladder_is_climbed_one_rung_at_a_time()
	_test_a_rung_pays_its_picks_into_this_run()
	_test_only_the_top_rung_ends_the_run()
	_test_a_won_run_can_carry_on_into_endless()
	_test_run_score_reports_lifetime_tokens()
	_test_ascension_state_survives_a_save_round_trip()

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


func _test_an_unqualified_build_has_no_eligible_contracts() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5001)
	assert_true(
		sim.ascension_eligible_contracts().is_empty(),
		"A fresh run with stock hardware has not qualified for anything yet"
	)
	assert_false(bool(sim.ascension_qualification().get("qualified", false)), "Qualification starts false")
	sim.free()


## Qualification only needs the three thresholds met; it does not require
## actually buying every upgrade in the game.
func _qualify(sim: Node) -> void:
	sim.run_state.calendar["round"] = 6
	sim.run_state.economy["last_round_costs"] = 100.0
	sim.run_state.economy["income"] = 500.0
	sim.run_state.statistics["peak_token_rate"] = 25000000.0
	sim.run_state.build["hardware"] = ["used_laptop", "gpu_rack"]


func _test_qualifying_opens_eligible_contracts() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5002)
	_qualify(sim)
	var qualification: Dictionary = sim.ascension_qualification()
	assert_true(bool(qualification.get("qualified", false)), "Income, peak rate, and tier all clear their bars")
	var eligible: Array = sim.ascension_eligible_contracts()
	assert_true(eligible.size() > 0, "Tier 1 contracts open up once qualified")
	for contract in eligible:
		assert_true(int(contract.get("required_infrastructure_tier", 0)) <= 1, "Tier 1 hardware only reaches Tier 1 contracts")
	assert_eq(int(sim.ascension_ladder().get("rung", 0)), 1, "A run that has climbed nothing starts on rung one")
	sim.free()


func _test_committing_locks_in_the_contract() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5003)
	_qualify(sim)
	assert_true(sim.commit_ascension_contract("ascension.first_scale_up"), "An eligible contract can be committed to")
	assert_true(sim.ascension_active(), "The Final Burn is now underway")
	assert_false(
		sim.commit_ascension_contract("ascension.million_token_operator"),
		"A second contract cannot be committed to on top of the first"
	)
	sim.free()


func _test_completing_a_contract_meets_its_requirement() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5004)
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


## Puts the run on a rung it has not actually climbed, so a test about the tier
## above does not have to play the two below it first.
func _stand_on_rung(sim: Node, rung: int) -> void:
	sim.run_state.ascension["highest_tier_completed"] = rung - 1


## Infrastructure tier 5, which is what every Tier 3 contract asks for.
func _own_the_top_of_the_ladder(sim: Node) -> void:
	sim.run_state.build["hardware"] = ["used_laptop", "industrial_campus"]
	sim.run_state.build["dwelling"] = "private_power_grid"


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


func _qualify_state(run_state: RunState) -> void:
	run_state.calendar["round"] = 6
	run_state.economy["last_round_costs"] = 100.0
	run_state.economy["income"] = 500.0
	run_state.statistics["peak_token_rate"] = 25000000.0
	run_state.build["hardware"] = ["used_laptop", "gpu_rack"]


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


## Overtime is not a dead end: committing there still counts, and clearing a rung
## in it moves the run up the ladder rather than leaving it stranded.
func _test_committing_in_overtime_still_climbs_a_rung() -> void:
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
	assert_eq(
		int(sim.ascension_ladder().get("highest_tier_completed", 0)),
		1,
		"Finishing it in overtime still climbs the rung"
	)
	assert_true(sim.phase != sim.Phase.RUN_END, "And does not end the run, even in overtime")
	assert_true(sim.in_overtime(), "Overtime keeps its grip until the top rung is done")
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


## The Job Board's way into the endgame must not blink out again because one
## round's income dipped under the bar.
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
	assert_true(sim.ascension_eligible_contracts().size() > 0, "And the contracts stay on the table")
	sim.free()


## The reported bug in one test: a Tier 1 contract used to end the whole game, so
## a first-time player's reward for reaching the endgame was being thrown out of
## it. A rung hands the run back instead.
func _test_a_rung_hands_the_run_back() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5020)
	_qualify(sim)
	assert_true(sim.commit_ascension_contract("ascension.first_scale_up"), "Committed to rung one")
	var contract: Dictionary = _meet_requirement(sim, "ascension.first_scale_up")
	sim._finish_prompt({"ok": true, "messages": []})

	assert_true(sim.phase != sim.Phase.RUN_END, "Clearing a Tier 1 contract does not end the run")
	assert_false(bool(sim.run_state.flags.get("victory", false)), "And is not a victory")
	assert_eq(str(sim.run_state.flags.get("outcome", "")), "", "Nothing has been decided yet")
	assert_false(sim.ascension_active(), "The Final Burn is over, so nothing is underway")
	assert_eq(int(sim.ascension_ladder().get("highest_tier_completed", 0)), 1, "Rung one is behind it")
	assert_eq(int(sim.ascension_ladder().get("rung", 0)), 2, "And rung two is the one to climb next")
	assert_eq(MetaProgress.pending_picks(), 0, "A rung banks nothing for the next run")
	assert_eq(
		int(sim.ascension_ladder().get("pending_picks", 0)),
		int(contract.get("picks", 1)),
		"It owes this run the contract's picks instead"
	)
	assert_eq(
		MetaProgress.ascension_completions("ascension.first_scale_up"),
		0,
		"And the profile records nothing: the run is still going"
	)
	sim.free()


func _test_the_ladder_is_climbed_one_rung_at_a_time() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5021)
	_qualify(sim)
	# Infrastructure for a Tier 2 contract, so only the rung gate can be refusing.
	sim.run_state.build["hardware"] = ["used_laptop", "gpu_rack", "garage_datacentre"]
	for contract in sim.ascension_eligible_contracts():
		assert_eq(int(contract.get("tier", 0)), 1, "Only rung one is on the table to begin with")
	assert_false(
		sim.commit_ascension_contract("ascension.datacentre_magnate"),
		"A Tier 2 contract cannot be reached over the top of rung one"
	)

	assert_true(sim.commit_ascension_contract("ascension.first_scale_up"), "Committed to rung one")
	_meet_requirement(sim, "ascension.first_scale_up")
	sim._finish_prompt({"ok": true, "messages": []})
	var eligible: Array = sim.ascension_eligible_contracts()
	assert_true(eligible.size() > 0, "Clearing rung one opens rung two")
	for contract in eligible:
		assert_eq(int(contract.get("tier", 0)), 2, "And rung two is all that is on the table now")
		assert_true(
			str(contract.get("id", "")) != "ascension.first_scale_up",
			"A contract already completed is not offered again"
		)
	sim.free()


## The picks a rung pays are spent on the run that earned them, which is the whole
## point of the redesign: the perks a draft hands over need rounds left to matter.
func _test_a_rung_pays_its_picks_into_this_run() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5022)
	_qualify(sim)
	sim.run_state.economy["cash"] = 500000.0
	assert_true(sim.commit_ascension_contract("ascension.first_scale_up"), "Committed to rung one")
	var contract: Dictionary = _meet_requirement(sim, "ascension.first_scale_up")
	sim._finish_prompt({"ok": true, "messages": []})

	# The round the rung was cleared in closes normally, and the reward comes after
	# the angels rather than instead of them.
	sim._end_round()
	if sim.phase == sim.Phase.ANGEL_ROUND and not sim.draft_is_ascension_reward():
		sim.decline_offers()
	assert_eq(sim.phase, sim.Phase.ANGEL_ROUND, "The rung's reward draft opens once the round closes")
	assert_true(sim.draft_is_ascension_reward(), "And it is the ascension reward, not another angel")
	assert_eq(
		sim.draft_picks_remaining(),
		int(contract.get("picks", 1)),
		"Worth exactly what the contract promised"
	)
	assert_true(sim.pending_choices.size() > 0, "With offers on the table")

	var offer: Dictionary = sim.pending_choices[0]
	assert_true(sim.accept_offer(str(offer.get("type", "")), str(offer.get("id", ""))), "A pick can be spent")
	assert_eq(sim.draft_picks_remaining(), 0, "Rung one was worth one pick, and it is spent")
	assert_eq(sim.phase, sim.Phase.ROUND_PREP, "Spending the last pick closes the draft")
	sim.free()


func _test_only_the_top_rung_ends_the_run() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5006)
	_qualify(sim)
	_stand_on_rung(sim, 3)
	_own_the_top_of_the_ladder(sim)
	assert_true(
		sim.commit_ascension_contract("ascension.final_prompt"),
		"The top rung is reachable once the two below it are done"
	)
	var contract: Dictionary = _meet_requirement(sim, "ascension.final_prompt")
	sim._finish_prompt({"ok": true, "messages": []})

	assert_eq(sim.phase, sim.Phase.RUN_END, "Only a Tier 3 contract ends the run")
	assert_true(bool(sim.run_state.flags.get("victory", false)), "As a victory")
	assert_eq(str(sim.run_state.flags.get("outcome", "")), "ascended", "Named as an ascension")
	assert_eq(
		MetaProgress.pending_picks(),
		int(contract.get("picks", 1)),
		"The finale banks its picks for the next run"
	)
	assert_eq(
		MetaProgress.ascension_completions("ascension.final_prompt"),
		1,
		"The profile remembers which contract was completed"
	)
	sim.free()


## Beating the game does not have to take the build away with it: the run carries
## on, past the calendar, under costs that climb every round.
func _test_a_won_run_can_carry_on_into_endless() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5023)
	_qualify(sim)
	_stand_on_rung(sim, 3)
	_own_the_top_of_the_ladder(sim)
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

	# The ladder outlives any one contract, so it has to survive a save even more
	# than the Final Burn does: losing it would put the run back on rung one with
	# the tier above already beaten.
	ascension.complete_rung(run_state, ContentDatabase.get_ascension_contract("ascension.first_scale_up"))
	var climbed := RunState.new()
	climbed.from_dict(run_state.to_dict())
	assert_eq(int(climbed.ascension.get("highest_tier_completed", 0)), 1, "The rung climbed survives a save")
	assert_true(
		"ascension.first_scale_up" in Array(climbed.ascension.get("completed_ids", [])),
		"So does which contract climbed it"
	)
	assert_eq(int(climbed.ascension.get("pending_picks", 0)), 1, "So do the picks it still owes the run")
	assert_true(
		ascension.commit(climbed, "ascension.first_scale_up", ContentDatabase) == false,
		"And a contract already completed cannot be committed to again"
	)
