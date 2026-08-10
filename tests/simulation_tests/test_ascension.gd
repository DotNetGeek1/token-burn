extends TestCase

## The contract each location is played for. There is exactly one, it is live
## from the first prompt of the run, and the year is its deadline.
##
## Completing it wins the run and opens the next location. Reaching the end of
## the year without it ends the run. Most of the tests below exist to keep those
## two statements true — the bug they guard against is a run that survived an
## ending in either direction.

const SCRATCH_PROFILE := "user://profile_test_ascension.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var restore_path: String = MetaProgress.profile_path
	var restore_enabled: bool = MetaProgress.enabled

	_test_a_fresh_run_is_already_under_its_contract()
	_test_the_contract_belongs_to_the_run_s_location()
	_test_progress_counts_from_the_first_prompt()
	_test_the_quality_bar_gates_completion()
	_test_the_year_running_out_ends_the_run()
	_test_a_finished_contract_beats_the_deadline_to_it()
	_test_there_is_no_overtime_left_to_fall_into()
	_test_beating_the_contract_wins_the_run()
	_test_beating_the_contract_unlocks_the_next_location()
	_test_advancing_to_the_next_chapter_carries_the_whole_business()
	_test_no_ladder_state_is_left_in_the_run()
	_test_replaying_a_completed_location_sets_its_contract_again()
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


## Puts a run in a location without playing the chapters below it. The contract
## follows the location, so it has to be re-activated afterwards.
func _run_in(sim: Node, location: String) -> void:
	sim.apply_run_location(sim.run_state, location)
	AscensionSystem.new().activate(sim.run_state, ContentDatabase)


## Skips straight to "the burn requirement is met", which is what the prompt
## evaluator actually checks.
func _meet_requirement(sim: Node, contract_id: String) -> Dictionary:
	var contract: Dictionary = ContentDatabase.get_ascension_contract(contract_id)
	sim.run_state.statistics["lifetime_tokens"] = (
		float(sim.run_state.ascension.get("baseline_tokens", 0.0))
		+ float(contract.get("total_burn", 0.0)) + 1.0
	)
	sim.run_state.ascension["quality_sum"] = 100.0
	sim.run_state.ascension["quality_count"] = 1
	return contract


## The redesign in one test: nothing is qualified for and nothing is opted into.
func _test_a_fresh_run_is_already_under_its_contract() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5001)
	assert_true(sim.ascension_active(), "A fresh run is already playing for its contract")
	assert_eq(
		str(sim.run_state.ascension.get("contract_id", "")), "ascension.first_scale_up",
		"Which is the bedroom's"
	)
	var progress: Dictionary = sim.ascension_progress()
	assert_almost_eq(float(progress.get("tokens_burned", -1.0)), 0.0, 0.01, "Nothing burned yet")
	assert_eq(int(progress.get("deadline_round", 0)), 12, "And the whole year to do it in")
	assert_eq(int(progress.get("rounds_remaining", 0)), 12, "All of which is still ahead")
	sim.free()


func _test_the_contract_belongs_to_the_run_s_location() -> void:
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
			str(sim.ascension_boss_contract().get("id", "")), str(pair[1]),
			"%s is played for the contract that chapter owns" % str(pair[0])
		)
		assert_eq(
			str(sim.run_state.ascension.get("contract_id", "")), str(pair[1]),
			"And it is live from the start"
		)
		sim.free()


## Tokens burned in round one count. Under the old model they did not, because
## the contract only started measuring once it had been committed to.
func _test_progress_counts_from_the_first_prompt() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5002)
	var contract: Dictionary = ContentDatabase.get_ascension_contract("ascension.first_scale_up")
	var quarter: float = float(contract.get("total_burn", 0.0)) * 0.25
	sim.run_state.statistics["lifetime_tokens"] = quarter
	var result: Dictionary = AscensionSystem.new().evaluate_prompt(sim.run_state, ContentDatabase)
	assert_eq(str(result.get("outcome", "x")), "", "A quarter of the way is not a finish")
	assert_almost_eq(
		float(result.get("tokens_burned", 0.0)), quarter, 1.0,
		"But it is counted against the contract"
	)
	assert_almost_eq(
		float(sim.ascension_progress().get("burn_ratio", 0.0)), 0.25, 0.01,
		"And reported as a quarter done"
	)
	sim.free()


func _test_the_quality_bar_gates_completion() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5003)
	var contract: Dictionary = ContentDatabase.get_ascension_contract("ascension.first_scale_up")
	sim.run_state.statistics["lifetime_tokens"] = float(contract.get("total_burn", 0.0)) + 1.0
	var ascension := AscensionSystem.new()
	# Everything shipped so far was under the bar, so the burn alone is not it.
	sim.run_state.ascension["quality_sum"] = 1.0
	sim.run_state.ascension["quality_count"] = 1
	assert_eq(
		str(ascension.evaluate_prompt(sim.run_state, ContentDatabase).get("outcome", "")), "",
		"The burn target alone does not complete a contract with a quality bar"
	)
	sim.run_state.ascension["quality_sum"] = float(contract.get("quality_min", 0.0)) * 2.0
	assert_eq(
		str(ascension.evaluate_prompt(sim.run_state, ContentDatabase).get("outcome", "")), "completed",
		"Clearing the bar on average completes it"
	)
	sim.free()


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
	assert_false(MetaProgress.is_location_unlocked("garage"), "And nothing is unlocked by running out")
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
	assert_false(sim.ascension_active(), "The contract is no longer running")
	assert_true(int(contract.get("picks", 0)) > 0, "The contract names a pick reward")
	assert_eq(
		MetaProgress.pending_picks(), 0,
		"But a chapter goal banks nothing permanent — only the final goal pays picks"
	)
	assert_eq(
		MetaProgress.ascension_completions("ascension.first_scale_up"), 1,
		"The profile remembers which contract was completed"
	)
	sim.free()


func _test_beating_the_contract_unlocks_the_next_location() -> void:
	_fresh_profile()
	assert_false(MetaProgress.is_location_unlocked("garage"), "The garage starts locked")
	var sim: Node = _sim()
	sim.start_run(5024)
	_meet_requirement(sim, "ascension.first_scale_up")
	sim.debug_finish_prompt({"ok": true, "messages": []})

	assert_true("bedroom" in MetaProgress.completed_locations(), "The bedroom is behind the player")
	assert_true(MetaProgress.is_location_unlocked("garage"), "And the garage is open")
	assert_eq(sim.next_location_unlocked(), "garage", "Which the verdict screen can name")
	assert_eq(
		MetaProgress.selected_location(), "bedroom",
		"The campaign selection stays put: the win continues in-run, not in the profile"
	)
	assert_false(
		sim.continue_after_victory(),
		"A mid-campaign win is a level-up, not the ending, so there is no endless tail"
	)
	sim.free()

	# The garage is this run's continuation, through advance_to_next_chapter.
	# A run started fresh is a fresh game and goes back to the start.
	var next_run: Node = _sim()
	next_run.start_run(5028)
	assert_eq(
		str(next_run.run_state.build.get("dwelling", "")), "bedroom",
		"A fresh run starts back in the bedroom"
	)
	assert_eq(
		str(next_run.run_state.ascension.get("contract_id", "")), "ascension.first_scale_up",
		"Under the bedroom's contract, stated before the first prompt"
	)
	next_run.free()


## The angel's goal is the end of a chapter, not the end of the game. Advancing
## continues the same business in the next room: cash, perks, modules, upgrades
## and reputation all carry — only the contract it is measured against grows.
func _test_advancing_to_the_next_chapter_carries_the_whole_business() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(5030)
	sim.run_state.economy["cash"] = 987654.0
	sim.run_state.business["reputation"] = 17.0
	sim.run_state.build["perks"] = ["perk.test_marker"]
	sim.run_state.build["operations"] = [{"id": "op.test_marker"}]
	_meet_requirement(sim, "ascension.first_scale_up")
	sim.debug_finish_prompt({"ok": true, "messages": []})
	assert_eq(sim.phase, sim.Phase.RUN_END, "The chapter's contract is complete")

	var hardware_before: Array = Array(sim.run_state.build.get("hardware", [])).duplicate()
	var lifetime_before: float = float(sim.run_state.statistics.get("lifetime_tokens", 0.0))
	# Sampled after the victory settled its bills: what the company actually
	# holds walking out of the bedroom is what must walk into the garage.
	var cash_before: float = float(sim.run_state.economy.get("cash", 0.0))
	assert_true(sim.advance_to_next_chapter(), "And the company moves up a chapter")
	assert_eq(str(sim.run_state.build.get("dwelling", "")), "garage", "Into the garage")
	assert_true(
		sim.phase == sim.Phase.ROUND_PREP or sim.phase == sim.Phase.ANGEL_ROUND,
		"Back in play — round prep, or the draft the winning round earned"
	)
	assert_eq(int(sim.run_state.calendar.get("round", 0)), 1, "With a fresh year on the new contract")
	assert_true(
		float(sim.run_state.economy.get("cash", 0.0)) >= cash_before,
		"Cash carries forward (the stake is a floor, not a replacement)"
	)
	assert_almost_eq(
		float(sim.run_state.business.get("reputation", 0.0)), 17.0, 0.01,
		"Reputation carries"
	)
	assert_true("perk.test_marker" in Array(sim.run_state.build.get("perks", [])), "Perks carry")
	assert_eq(
		Array(sim.run_state.build.get("operations", [])).size(), 1,
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
	assert_true(sim.ascension_active(), "The next chapter's contract is live immediately")
	assert_eq(
		str(sim.run_state.ascension.get("contract_id", "")), "ascension.million_token_operator",
		"And it is the garage's bigger one"
	)
	assert_almost_eq(
		float(sim.ascension_progress().get("tokens_burned", -1.0)), 0.0, 1.0,
		"Measured from zero: the old chapter's burn does not pre-pay the new target"
	)
	assert_false(
		sim.advance_to_next_chapter(),
		"Advancing is a one-shot on the win, not something a live run can repeat"
	)
	sim.free()

	# The final chapter has nowhere further to move; its continuation is the
	# endless tail, and advancing must refuse rather than wrap around.
	var summit: Node = _sim()
	summit.start_run(5031)
	_run_in(summit, "moon_facility")
	summit.run_state.economy["cash"] = 100000000.0
	var final_contract: Dictionary = _meet_requirement(summit, "ascension.final_prompt")
	summit.debug_finish_prompt({"ok": true, "messages": []})
	assert_eq(summit.phase, summit.Phase.RUN_END, "The last contract is complete")
	assert_false(summit.advance_to_next_chapter(), "There is no chapter above the summit")
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
			sim.run_state.ascension.has(stale),
			"A run carries no opt-in state: %s is gone" % stale
		)
	assert_false(sim.run_state.flags.has("overtime"), "And no overtime flag")
	assert_false(sim.run_state.flags.has("ascension_qualified"), "And nothing to qualify for")
	sim.free()


## Replaying a chapter already beaten is allowed, and its contract is still the
## way out of it — the campaign is the ladder, not the run.
func _test_replaying_a_completed_location_sets_its_contract_again() -> void:
	_fresh_profile()
	MetaProgress.complete_location("bedroom")
	var sim: Node = _sim()
	sim.start_run(5027)
	_run_in(sim, "bedroom")
	assert_eq(
		str(sim.run_state.ascension.get("contract_id", "")), "ascension.first_scale_up",
		"The bedroom still plays for its own contract"
	)
	sim.free()


## Beating the game does not have to take the build away with it: the run carries
## on, past the calendar, under costs that climb every round. Only the last
## chapter offers this — everywhere else the continuation is the next location.
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
	var ascension := AscensionSystem.new()
	var run_state := RunState.new()
	run_state.reset()
	assert_true(ascension.activate(run_state, ContentDatabase), "The run is under its contract")
	run_state.ascension["tokens_burned"] = 12345.0

	var reloaded := RunState.new()
	reloaded.from_dict(run_state.to_dict())
	assert_eq(str(reloaded.ascension.get("status", "")), "active", "Which survives a save")
	assert_eq(str(reloaded.ascension.get("contract_id", "")), "ascension.first_scale_up", "So does which contract")
	assert_almost_eq(float(reloaded.ascension.get("tokens_burned", 0.0)), 12345.0, 0.01, "So does progress")
	assert_eq(int(reloaded.ascension.get("deadline_round", 0)), 12, "So does the deadline")


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
	assert_eq(str(run_state.ascension.get("status", "")), "active", "The contract carries on as the run's")
	assert_eq(
		str(run_state.ascension.get("contract_id", "")), "ascension.first_scale_up",
		"And it is still the same one"
	)
	assert_almost_eq(float(run_state.ascension.get("tokens_burned", 0.0)), 50.0, 0.01, "With its progress intact")
	assert_eq(int(run_state.ascension.get("deadline_round", 0)), 12, "And the year as its deadline")
	for stale in ["committed_round", "prompts_remaining", "violations"]:
		assert_false(run_state.ascension.has(stale), "The Final Burn field %s is gone" % stale)
	assert_false(run_state.flags.has("overtime"), "Overtime is gone with it")
	assert_false(run_state.flags.has("ascension_qualified"), "As is qualification")
