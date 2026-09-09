extends TestCase

## The Investor Target each level is played for. There is exactly one, it is
## live from the first prompt of the level, and its deadline is counted on the
## run's continuous calendar.
##
## Completing a target is a level-up inside the run; completing the final one
## is the end of the game. Reaching the deadline without it ends the run. Most
## of the tests below exist to keep those statements true — the bug they guard
## against is a run that survived an ending in either direction.

const SCRATCH_PROFILE := "user://profile_test_investor_targets.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var restore_path: String = MetaProgress.profile_path
	var restore_enabled: bool = MetaProgress.enabled

	_test_a_fresh_run_is_already_under_its_contract()
	_test_the_target_belongs_to_the_run_s_level()
	_test_progress_counts_from_the_first_prompt()
	_test_the_quality_bar_gates_completion()
	_test_a_real_final_job_decides_the_quality_bar()
	_test_the_year_running_out_ends_the_run()
	_test_a_finished_contract_beats_the_deadline_to_it()
	_test_there_is_no_overtime_left_to_fall_into()
	_test_beating_the_contract_wins_the_run()
	_test_a_victory_save_is_run_end_not_the_next_round()
	_test_the_winning_round_is_on_the_investor()
	_test_a_deadline_round_win_is_not_stamped_as_expired()
	_test_the_investor_pays_more_for_finishing_early()
	_test_beating_a_target_is_a_level_up_not_the_ending()
	_test_taking_the_next_target_carries_the_whole_business()
	_test_no_ladder_state_is_left_in_the_run()
	_test_a_won_run_can_carry_on_into_endless()
	_test_run_score_reports_lifetime_tokens()
	_test_contract_state_survives_a_save_round_trip()
	_test_a_save_mid_final_burn_becomes_the_run_s_contract()

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


## Stands a run up at the scale a room used to mean, without playing the levels
## below it: the room's Infrastructure Tier, and the Investor Level whose
## target that room used to own (tier n is level n + 1).
func _run_in(sim: Node, location: String) -> void:
	var tier: int = InfrastructureSystem.tier_for_room(location)
	sim.apply_infrastructure_tier(sim.run_state, tier)
	sim.investor_progression().activate_level(sim.run_state, tier + 1, ContentDatabase)


## A met target deals the investor's perk table, and the company cannot move
## on until it is answered. Walks away from it so the tests here can get on
## with the move.
func _settle_investor_draft(sim: Node) -> void:
	if sim.investor_draft_pending():
		sim.decline_offers()


## Skips straight to "the burn requirement is met", which is what the prompt
## evaluator actually checks.
func _meet_requirement(sim: Node, contract_id: String) -> Dictionary:
	var contract: Dictionary = ContentDatabase.get_investor_target(contract_id)
	sim.run_state.statistics["lifetime_tokens"] = (
		float(sim.run_state.investor.get("baseline_tokens", 0.0))
		+ float(contract.get("total_burn", 0.0)) + 1.0
	)
	sim.run_state.investor["quality_sum"] = 100.0
	sim.run_state.investor["quality_count"] = 1
	return contract


## The redesign in one test: nothing is qualified for and nothing is opted into.
func _test_a_fresh_run_is_already_under_its_contract() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5001)
	assert_true(sim.investor_active(), "A fresh run is already playing for its contract")
	assert_eq(
		str(sim.run_state.investor.get("contract_id", "")), "ascension.first_scale_up",
		"Which is the bedroom's"
	)
	var progress: Dictionary = sim.investor_progress()
	assert_almost_eq(float(progress.get("tokens_burned", -1.0)), 0.0, 0.01, "Nothing burned yet")
	assert_eq(int(progress.get("deadline_round", 0)), 12, "And the whole year to do it in")
	assert_eq(int(progress.get("rounds_remaining", 0)), 12, "All of which is still ahead")
	sim.free()


func _test_the_target_belongs_to_the_run_s_level() -> void:
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
		assert_eq(
			str(sim.investor_target().get("id", "")), str(pair[1]),
			"%s's scale is played for the target its level owns" % str(pair[0])
		)
		assert_eq(
			str(sim.run_state.investor.get("contract_id", "")), str(pair[1]),
			"And it is live from the start"
		)
		sim.free()


## Tokens burned in round one count. Under the old model they did not, because
## the contract only started measuring once it had been committed to.
func _test_progress_counts_from_the_first_prompt() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5002)
	var contract: Dictionary = ContentDatabase.get_investor_target("ascension.first_scale_up")
	var quarter: float = float(contract.get("total_burn", 0.0)) * 0.25
	sim.run_state.statistics["lifetime_tokens"] = quarter
	var result: Dictionary = InvestorProgression.new().evaluate_prompt(sim.run_state, ContentDatabase)
	assert_eq(str(result.get("outcome", "x")), "", "A quarter of the way is not a finish")
	assert_almost_eq(
		float(result.get("tokens_burned", 0.0)), quarter, 1.0,
		"But it is counted against the contract"
	)
	assert_almost_eq(
		float(sim.investor_progress().get("burn_ratio", 0.0)), 0.25, 0.01,
		"And reported as a quarter done"
	)
	sim.free()


func _test_the_quality_bar_gates_completion() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5003)
	var contract: Dictionary = ContentDatabase.get_investor_target("ascension.first_scale_up")
	sim.run_state.statistics["lifetime_tokens"] = float(contract.get("total_burn", 0.0)) + 1.0
	var ascension := InvestorProgression.new()
	# Everything shipped so far was under the bar, so the burn alone is not it.
	sim.run_state.investor["quality_sum"] = 1.0
	sim.run_state.investor["quality_count"] = 1
	assert_eq(
		str(ascension.evaluate_prompt(sim.run_state, ContentDatabase).get("outcome", "")), "",
		"The burn target alone does not complete a contract with a quality bar"
	)
	sim.run_state.investor["quality_sum"] = float(contract.get("quality_min", 0.0)) * 2.0
	assert_eq(
		str(ascension.evaluate_prompt(sim.run_state, ContentDatabase).get("outcome", "")), "completed",
		"Clearing the bar on average completes it"
	)
	sim.free()


## The original bug was the contract being judged before the job that finished
## it had been counted. These two cases drive that ordering with a real
## completed contract rather than a hand-set average, and pin down which
## quality is canonical: the one the client receives, after the known bugs the
## player chose to ship have come off it.
func _test_a_real_final_job_decides_the_quality_bar() -> void:
	var bar: float = float(
		ContentDatabase.get_investor_target("ascension.first_scale_up").get("quality_min", 0.0)
	)
	assert_true(bar > 0.0, "The bedroom's contract has a quality bar to test against")

	var clears: Node = _sim()
	clears.start_run(5041)
	_meet_burn_only(clears, "ascension.first_scale_up")
	clears.run_state.business["active_jobs"] = [_delivered_job(bar + 10.0, 0)]
	clears.debug_finish_prompt({"ok": true, "messages": []})
	assert_true(
		bool(clears.run_state.flags.get("victory", false)),
		"A finished contract delivered above the bar wins the run on the prompt that finished it"
	)
	clears.free()

	var misses: Node = _sim()
	misses.start_run(5042)
	_meet_burn_only(misses, "ascension.first_scale_up")
	# Same pipeline quality, but four known bugs went out with it — three
	# points each, which is what drops the delivery under the bar.
	misses.run_state.business["active_jobs"] = [_delivered_job(bar + 10.0, 4)]
	misses.debug_finish_prompt({"ok": true, "messages": []})
	assert_false(
		bool(misses.run_state.flags.get("victory", false)),
		"The same work shipped with known bugs does not clear the bar"
	)
	assert_almost_eq(
		float(misses.run_state.investor.get("quality_sum", 0.0)), bar - 2.0, 0.01,
		"Because the contract is judged on delivered quality, not what the pipeline produced"
	)
	misses.free()


## The burn side of the contract met, with the quality average left empty so the
## job under test is the only thing deciding it.
func _meet_burn_only(sim: Node, contract_id: String) -> void:
	var contract: Dictionary = ContentDatabase.get_investor_target(contract_id)
	sim.run_state.statistics["lifetime_tokens"] = (
		float(sim.run_state.investor.get("baseline_tokens", 0.0))
		+ float(contract.get("total_burn", 0.0)) + 1.0
	)
	sim.run_state.investor["quality_sum"] = 0.0
	sim.run_state.investor["quality_count"] = 0


func _delivered_job(quality: float, known_bugs: int) -> Dictionary:
	return {
		"id": "job.final",
		"name": "Final Contract",
		"token_requirement": 1000.0,
		"tokens_remaining": 0.0,
		"shipped": true,
		"quality": quality,
		"known_bugs": known_bugs,
		"hidden_bugs": 0,
	}


## The reported bug, now the rule: the year is the deadline and running it out
## with the contract unfinished is how a run is lost.
func _test_the_year_running_out_ends_the_run() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5005)
	sim.run_state.economy["cash"] = 500000.0
	sim.run_state.calendar["round"] = 12
	sim.debug_end_round()
	assert_eq(sim.phase, sim.Phase.RUN_END, "Reaching the end of the year ends the run")
	assert_eq(
		str(sim.run_state.flags.get("outcome", "")), "contract_expired",
		"Named as the contract expiring rather than a generic collapse"
	)
	assert_false(bool(sim.run_state.flags.get("victory", false)), "As a loss")
	assert_eq(MetaProgress.pending_picks(), 0, "Nothing is banked for outlasting the calendar")
	assert_false(bool(sim.run_state.flags.get("target_complete", false)), "And no target is met by running out")
	sim.free()


## The deadline must not take a win back from a run that finished in time.
func _test_a_finished_contract_beats_the_deadline_to_it() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5006)
	sim.run_state.economy["cash"] = 500000.0
	sim.run_state.calendar["round"] = 12
	_meet_requirement(sim, "ascension.first_scale_up")
	sim.debug_finish_prompt({"ok": true, "messages": []})
	assert_true(bool(sim.run_state.flags.get("victory", false)), "Finishing in the last round still wins")
	assert_eq(str(sim.run_state.flags.get("outcome", "")), "ascended", "As an ascension")
	sim.free()


func _test_there_is_no_overtime_left_to_fall_into() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5011)
	sim.run_state.economy["cash"] = 5000000.0
	var rent_before: float = float(sim.run_state.economy.get("round_rent", 0.0))
	sim.run_state.calendar["round"] = 12
	sim.debug_end_round()
	assert_almost_eq(
		float(sim.run_state.economy.get("round_rent", 0.0)), rent_before, 0.01,
		"The year closing does not escalate the rent — it ends the run instead"
	)
	assert_eq(sim.phase, sim.Phase.RUN_END, "And the run is over")
	sim.free()


func _test_beating_the_contract_wins_the_run() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5020)
	var contract: Dictionary = _meet_requirement(sim, "ascension.first_scale_up")
	sim.debug_finish_prompt({"ok": true, "messages": []})

	assert_eq(sim.phase, sim.Phase.RUN_END, "Completing the contract ends the run")
	assert_true(bool(sim.run_state.flags.get("victory", false)), "As a victory")
	assert_eq(str(sim.run_state.flags.get("outcome", "")), "ascended", "Named as an ascension")
	assert_false(sim.investor_active(), "The contract is no longer running")
	assert_true(int(contract.get("picks", 0)) > 0, "The contract names a pick reward")
	assert_eq(
		MetaProgress.pending_picks(), 0,
		"But a target on the way up banks nothing permanent — only the final one pays picks"
	)
	assert_eq(
		MetaProgress.ascension_completions("ascension.first_scale_up"), 1,
		"The profile remembers which contract was completed"
	)
	sim.free()


## Settling a target win used to autosave the next round while the overlay still
## said the company was closed. Continue from title then loaded that live
## snapshot. The primary save has to be RUN_END until the player takes the next
## target — and the outcome has to be ascended, so the verdict cannot fall
## through to COMPANY CLOSED.
func _test_a_victory_save_is_run_end_not_the_next_round() -> void:
	_fresh_profile()
	const SCRATCH_SAVE := "user://save_test_victory_run_end.json"
	SaveManager.use_scratch(SCRATCH_SAVE)
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = true
	sim.start_run(5043)
	_meet_requirement(sim, "ascension.first_scale_up")
	sim.debug_finish_prompt({"ok": true, "messages": []})
	assert_eq(sim.phase, sim.Phase.RUN_END, "The level's target is complete")
	assert_true(bool(sim.run_state.flags.get("victory", false)), "As a victory")
	assert_eq(
		str(sim.run_state.flags.get("outcome", "")), "ascended",
		"Named as an ascension, so the Run Report cannot default to COMPANY CLOSED"
	)
	var data: Dictionary = SaveManager.load_run()
	assert_false(data.is_empty(), "Victory wrote a save")
	assert_eq(
		str(data.get("phase", "")), "RUN_END",
		"The primary save is the verdict, not the next round the settle had already opened"
	)
	assert_eq(
		str(Dictionary(data.get("run_state", {})).get("flags", {}).get("outcome", "")),
		"ascended",
		"And the saved flags agree"
	)
	# Two writes would demote a live next-round to .bak. Continue would load
	# that snapshot if the RUN_END write never landed.
	assert_false(
		FileAccess.file_exists(SCRATCH_SAVE + ".bak"),
		"Victory writes RUN_END once; a live next-round must not sit as the backup"
	)
	SaveManager.delete_save()
	SaveManager.restore_default()
	sim.free()


## The reported bug: a contract completed by a company that could not cover that
## round's rent was billed anyway on the way out, which left an eviction notice
## in the run state behind the victory screen and collapsed the company on its
## first prompt at the next level. The winning round is the investor's to pay.
func _test_the_winning_round_is_on_the_investor() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5032)
	# Broke, and already one missed rent into an eviction.
	sim.run_state.economy["cash"] = 0.0
	sim.run_state.economy["rent_unpaid_streak"] = 1
	var rent: float = float(sim.run_state.economy.get("round_rent", 0.0))
	_meet_requirement(sim, "ascension.first_scale_up")
	sim.debug_finish_prompt({"ok": true, "messages": []})

	assert_true(bool(sim.run_state.flags.get("victory", false)), "Finishing broke still meets the target")
	assert_eq(
		int(sim.run_state.economy.get("rent_unpaid_streak", -1)), 1,
		"The winning round's bills are waived, so no new arrears are owed on it; the run is continuous, so the old ones stand"
	)
	assert_eq(
		str(sim.run_state.flags.get("loss_reason", "")), "",
		"And no loss reason is left sitting behind the victory"
	)
	assert_true(
		float(sim.run_state.economy.get("cash", 0.0)) >= rent,
		"The investor's cheque is paid rather than swallowed by rent"
	)

	_settle_investor_draft(sim)
	assert_true(sim.continue_after_target(), "The company takes the next target")
	assert_true(sim.phase != sim.Phase.RUN_END, "Alive, not collapsed on arrival")
	assert_eq(
		int(sim.run_state.economy.get("rent_unpaid_streak", -1)), 1,
		"The rent record carries over: the next target does not wipe the arrears"
	)
	assert_eq(str(sim.run_state.flags.get("loss_reason", "")), "", "And nothing left to be evicted for")
	sim.free()


## Winning in the last round of the year used to run the deadline check on the way
## out of the same round and stamp "the year ran out" onto a completed contract.
func _test_a_deadline_round_win_is_not_stamped_as_expired() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5033)
	sim.run_state.economy["cash"] = 0.0
	sim.run_state.calendar["round"] = 12
	_meet_requirement(sim, "ascension.first_scale_up")
	sim.debug_finish_prompt({"ok": true, "messages": []})

	assert_true(bool(sim.run_state.flags.get("victory", false)), "The last round is still a round to win in")
	assert_eq(str(sim.run_state.flags.get("outcome", "")), "ascended", "Recorded as an ascension")
	assert_eq(str(sim.run_state.flags.get("loss_reason", "")), "", "With no expiry written over it")
	assert_eq(
		str(sim.run_state.investor.get("status", "")), "completed",
		"And the contract stays completed rather than being failed on its deadline"
	)
	sim.free()


## The investor pays on delivery, and pays by how much of the year was left. The
## figure scales off the tier's rent so it keeps pace with the scale instead of
## needing a hand-written number per level.
func _test_the_investor_pays_more_for_finishing_early() -> void:
	_fresh_profile()
	var early: Node = _sim()
	early.start_run(5034)
	var rent: float = float(early.run_state.economy.get("round_rent", 0.0))
	assert_true(rent > 0.0, "The bedroom charges rent to scale the bonus against")
	_meet_requirement(early, "ascension.first_scale_up")
	early.debug_finish_prompt({"ok": true, "messages": []})
	var early_bonus: float = float(early.run_state.statistics.get("ascension_bonus", 0.0))
	assert_almost_eq(
		early_bonus, rent * 12.0, 0.01,
		"Delivered in round one: the round itself plus the eleven rounds to spare"
	)
	early.free()

	var late: Node = _sim()
	late.start_run(5035)
	late.run_state.calendar["round"] = 12
	_meet_requirement(late, "ascension.first_scale_up")
	late.debug_finish_prompt({"ok": true, "messages": []})
	var late_bonus: float = float(late.run_state.statistics.get("ascension_bonus", 0.0))
	assert_almost_eq(late_bonus, rent, 0.01, "Delivered on the deadline: one round's rent")
	assert_true(late_bonus < early_bonus, "So speed is what the bonus rewards")
	late.free()


func _test_beating_a_target_is_a_level_up_not_the_ending() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5024)
	_meet_requirement(sim, "ascension.first_scale_up")
	sim.debug_finish_prompt({"ok": true, "messages": []})

	assert_true(bool(sim.run_state.flags.get("target_complete", false)), "The target is flagged as met")
	assert_false(sim.game_completed(), "Which the verdict screen can tell is a level-up, not the ending")
	assert_false(bool(sim.investor_target().get("final", false)), "The first target is not the final one")
	assert_eq(sim.investor_level(), 1, "The level does not move until the player takes the next target")
	assert_eq(MetaProgress.victories(), 0, "The profile records no completed game")
	assert_false(
		sim.continue_after_victory(),
		"A win on the way up is a level-up, not the ending, so there is no Deep Burn tail"
	)
	sim.free()

	# The next level is this run's continuation, through continue_after_target.
	# A run started fresh is a fresh game and goes back to the start.
	var next_run: Node = _sim()
	next_run.start_run(5028)
	assert_eq(next_run.investor_level(), 1, "A fresh run starts back at Investor Level 1")
	assert_eq(next_run.infrastructure_tier(), 0, "On the starting rig")
	assert_eq(
		str(next_run.run_state.investor.get("contract_id", "")), "ascension.first_scale_up",
		"Under the first target, stated before the first prompt"
	)
	next_run.free()


## The investor's target is the end of a level, not the end of the game. Taking
## the next one continues the same business in the same room on the same
## calendar: cash, perks, modules, upgrades and reputation all carry — only the
## target it is measured against grows.
func _test_taking_the_next_target_carries_the_whole_business() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5030)
	sim.run_state.economy["cash"] = 987654.0
	sim.run_state.business["reputation"] = 17.0
	sim.run_state.build["perks"] = ["perk.test_marker"]
	sim.run_state.build["modules"] = [{"id": "op.test_marker"}]
	_meet_requirement(sim, "ascension.first_scale_up")
	sim.debug_finish_prompt({"ok": true, "messages": []})
	assert_eq(sim.phase, sim.Phase.RUN_END, "The level's target is complete")

	var hardware_before: Array = Array(sim.run_state.build.get("hardware", [])).duplicate()
	var lifetime_before: float = float(sim.run_state.statistics.get("lifetime_tokens", 0.0))
	# Sampled after the victory settled its bills: what the company actually
	# holds walking out of the bedroom is what must walk into the garage.
	var cash_before: float = float(sim.run_state.economy.get("cash", 0.0))
	assert_true(sim.investor_draft_pending(), "The goal deals the investor's perk table first")
	assert_false(
		sim.continue_after_target(),
		"The company cannot move while the investor's table is unanswered"
	)
	var cash_at_verdict: float = float(sim.run_state.economy.get("cash", 0.0))
	var round_before: int = int(sim.run_state.calendar.get("round", 0))
	_settle_investor_draft(sim)
	assert_true(sim.continue_after_target(), "And the company takes the next target")
	assert_eq(sim.investor_level(), 2, "Up one Investor Level")
	assert_eq(RoomProgression.room_for(sim.run_state), "bedroom", "In the same room: scale is bought, not awarded")
	assert_eq(sim.infrastructure_tier(), 0, "So the Infrastructure Tier has not moved")
	assert_eq(sim.phase, sim.Phase.ROUND_PREP, "Back in play at round prep")
	assert_eq(int(sim.run_state.calendar.get("round", 0)), round_before, "On the same calendar: the round does not reset")
	assert_almost_eq(
		float(sim.run_state.economy.get("cash", 0.0)), cash_before, 0.01,
		"Cash carries forward untouched"
	)
	assert_almost_eq(
		float(sim.run_state.economy.get("cash", 0.0)), cash_at_verdict, 0.01,
		"Taking the next target costs nothing: scale is bought in the Market, not on the way up"
	)
	assert_almost_eq(
		float(sim.run_state.business.get("reputation", 0.0)), 17.0, 0.01,
		"Reputation carries"
	)
	assert_true("perk.test_marker" in Array(sim.run_state.build.get("perks", [])), "Perks carry")
	assert_eq(
		Array(sim.run_state.build.get("modules", [])).size(), 1,
		"Modules carry"
	)
	assert_eq(
		Array(sim.run_state.build.get("hardware", [])), hardware_before,
		"The rig carries as-is"
	)
	assert_almost_eq(
		float(sim.run_state.statistics.get("lifetime_tokens", 0.0)), lifetime_before, 0.01,
		"Lifetime burn is not reset"
	)
	assert_true(sim.investor_active(), "The next level's target is live immediately")
	assert_eq(
		str(sim.run_state.investor.get("contract_id", "")), "ascension.million_token_operator",
		"And it is level two's bigger one"
	)
	assert_almost_eq(
		float(sim.investor_progress().get("tokens_burned", -1.0)), 0.0, 1.0,
		"Measured from zero: the old level's burn does not pre-pay the new target"
	)
	assert_eq(
		int(sim.investor_progress().get("deadline_round", 0)),
		round_before + InvestorProgression.deadline_rounds_for(sim.investor_target()) - 1,
		"With its deadline counted from the round it went live on"
	)
	assert_false(
		sim.continue_after_target(),
		"Advancing is a one-shot on the win, not something a live run can repeat"
	)
	sim.free()

	# The final target has nowhere further to move; its continuation is Deep
	# Burn, and advancing must refuse rather than wrap around.
	var summit: Node = _sim()
	summit.start_run(5031)
	_run_in(summit, "moon_facility")
	summit.run_state.economy["cash"] = 100000000.0
	var final_contract: Dictionary = _meet_requirement(summit, "ascension.final_prompt")
	summit.debug_finish_prompt({"ok": true, "messages": []})
	assert_eq(summit.phase, summit.Phase.RUN_END, "The last target is complete")
	assert_true(summit.game_completed(), "And the game with it")
	assert_false(summit.continue_after_target(), "There is no target above the final one")
	assert_eq(
		MetaProgress.pending_picks(), int(final_contract.get("picks", 0)),
		"Beating the game is what banks the permanent picks"
	)
	summit.free()


func _test_no_ladder_state_is_left_in_the_run() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5026)
	for stale in [
		"completed_ids", "highest_tier_completed", "pending_picks",
		"committed_round", "prompts_remaining", "violations",
	]:
		assert_false(
			sim.run_state.investor.has(stale),
			"A run carries no opt-in state: %s is gone" % stale
		)
	assert_false(sim.run_state.flags.has("overtime"), "And no overtime flag")
	assert_false(sim.run_state.flags.has("ascension_qualified"), "And nothing to qualify for")
	sim.free()


## Beating the game does not have to take the build away with it: the run carries
## on, past the calendar, under costs that climb every round. Only the final
## target offers this — everywhere else the continuation is the next target.
func _test_a_won_run_can_carry_on_into_endless() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5023)
	_run_in(sim, "moon_facility")
	# Moon Facility rent is millions a round, so the tail needs a bankroll that
	# can survive the bills long enough to watch them climb.
	sim.run_state.economy["cash"] = 100000000.0
	_meet_requirement(sim, "ascension.final_prompt")
	sim.debug_finish_prompt({"ok": true, "messages": []})
	assert_eq(sim.phase, sim.Phase.RUN_END, "The run is won")

	var tokens_before: float = float(sim.run_state.statistics.get("lifetime_tokens", 0.0))
	assert_true(sim.investor_draft_pending(), "Even the last goal deals the investor's perk table")
	assert_false(sim.continue_after_victory(), "Which has to be answered before carrying on")
	_settle_investor_draft(sim)
	assert_true(sim.continue_after_victory(), "And can be carried on")
	assert_true(sim.phase != sim.Phase.RUN_END, "Which puts it back into play")
	assert_true(sim.in_post_victory(), "Flagged as a run past its ending")
	assert_almost_eq(
		float(sim.run_state.statistics.get("lifetime_tokens", 0.0)), tokens_before, 0.01,
		"With everything it burned still on the board"
	)
	assert_false(sim.continue_after_victory(), "There is only one ending to carry on from")

	# Past the calendar a won run escalates like endless mode rather than being
	# ended by a deadline it has already beaten.
	sim.run_state.calendar["round"] = 12
	var rent_before: float = float(sim.run_state.economy.get("round_rent", 0.0))
	sim.debug_end_round()
	assert_true(sim.phase != sim.Phase.RUN_END, "A won run is not ended again by the calendar")
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


func _test_contract_state_survives_a_save_round_trip() -> void:
	var ascension := InvestorProgression.new()
	var run_state := RunState.new()
	run_state.reset()
	assert_true(ascension.activate(run_state, ContentDatabase), "The run is under its contract")
	run_state.investor["tokens_burned"] = 12345.0

	var reloaded := RunState.new()
	reloaded.from_dict(run_state.to_dict())
	assert_eq(str(reloaded.investor.get("status", "")), "active", "Which survives a save")
	assert_eq(str(reloaded.investor.get("contract_id", "")), "ascension.first_scale_up", "So does which contract")
	assert_almost_eq(float(reloaded.investor.get("tokens_burned", 0.0)), 12345.0, 0.01, "So does progress")
	assert_eq(int(reloaded.investor.get("deadline_round", 0)), 12, "So does the deadline")


## A save written when a contract was something the player committed to part-way
## through: the contract it was burning for is now simply the run's contract, and
## the Final Burn's own bookkeeping has nowhere to go.
func _test_a_save_mid_final_burn_becomes_the_run_s_contract() -> void:
	var run_state := RunState.new()
	run_state.reset()
	run_state.from_dict({
		"save_version": 11,
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
		},
		"flags": {"overtime": true, "ascension_qualified": true},
	})
	assert_eq(str(run_state.investor.get("status", "")), "active", "The contract carries on as the run's")
	assert_eq(
		str(run_state.investor.get("contract_id", "")), "ascension.first_scale_up",
		"And it is still the same one"
	)
	assert_almost_eq(float(run_state.investor.get("tokens_burned", 0.0)), 50.0, 0.01, "With its progress intact")
	assert_eq(int(run_state.investor.get("deadline_round", 0)), 12, "And the year as its deadline")
	for stale in ["committed_round", "prompts_remaining", "violations"]:
		assert_false(run_state.investor.has(stale), "The Final Burn field %s is gone" % stale)
	assert_false(run_state.flags.has("overtime"), "Overtime is gone with it")
	assert_false(run_state.flags.has("ascension_qualified"), "As is qualification")
