extends TestCase

## Deep Burn is the endless mode: completing the final Investor Target offers
## KEEP BURNING, the whole company carries on as it stood, and the Deep Burn
## ladder escalates the need off the final target — depth after depth — for as
## long as the run survives. The profile remembers how deep it got.

const SCRATCH_PROFILE := "user://profile_test_endless_deep_burn.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var restore_path: String = MetaProgress.profile_path
	var restore_enabled: bool = MetaProgress.enabled

	_test_completing_the_game_allows_keep_burning()
	_test_keep_burning_retains_the_whole_company()
	_test_deep_burn_targets_escalate_off_the_final_target()
	_test_a_second_depth_completes()
	_test_a_run_lost_in_deep_burn_keeps_its_depth_record()

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


## Stands the run up at the top of the game and meets the final target on the
## next prompt.
func _complete_the_game(sim: Node) -> Dictionary:
	sim.apply_infrastructure_tier(sim.run_state, InfrastructureSystem.max_tier(ContentDatabase))
	sim.investor_progression().activate_level(
		sim.run_state, InvestorProgression.final_level(ContentDatabase), ContentDatabase
	)
	sim.run_state.economy["cash"] = 100000000.0
	var target: Dictionary = sim.investor_target()
	sim.run_state.statistics["lifetime_tokens"] = (
		float(sim.run_state.investor.get("baseline_tokens", 0.0))
		+ float(target.get("total_burn", 0.0)) + 1.0
	)
	sim.run_state.investor["quality_sum"] = 100.0
	sim.run_state.investor["quality_count"] = 1
	sim.debug_finish_prompt({"ok": true, "messages": []})
	return target


## KEEP BURNING from the verdict: the investor's table answered, then on.
func _keep_burning(sim: Node) -> void:
	if sim.investor_draft_pending():
		sim.decline_offers()
	assert_true(sim.continue_after_victory(), "KEEP BURNING carries the completed game on")


## Opens the next depth by taking the first affix on the table.
func _begin_next_depth(sim: Node) -> Dictionary:
	var picks: Array = sim.offer_depth_picks()
	assert_eq(picks.size(), 3, "Deep Burn deals three affixes")
	var chosen: Dictionary = Dictionary(picks[0])
	assert_true(bool(sim.choose_depth_affix(str(chosen.get("id", ""))).get("ok", false)), "The affix lands")
	return chosen


## Burns exactly the depth's need so the next prompt evaluation completes it.
func _meet_depth_need(sim: Node) -> Dictionary:
	sim.run_state.statistics["lifetime_tokens"] = (
		float(sim.run_state.depth.get("baseline_tokens", 0.0))
		+ float(sim.run_state.depth.get("tokens_needed", 0.0))
	)
	return sim.depth_system().evaluate_prompt(sim.run_state)


func _test_completing_the_game_allows_keep_burning() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(8201)
	_complete_the_game(sim)
	assert_eq(sim.phase, sim.Phase.RUN_END, "The final target ends the run on the verdict")
	assert_true(sim.game_completed(), "With the game complete")
	assert_false(sim.continue_after_target(), "There is no next target to take")
	assert_true(sim.investor_draft_pending(), "The final target still deals the investor's table")
	assert_false(sim.continue_after_victory(), "Which has to be answered before burning on")
	sim.decline_offers()
	assert_true(sim.continue_after_victory(), "Then KEEP BURNING is open")
	assert_true(sim.phase != sim.Phase.RUN_END, "And the run is back in play")
	assert_true(sim.in_post_victory(), "Flagged as a run past its ending")
	assert_true(sim.game_completed(), "The game stays complete")
	assert_true(sim.can_begin_depth(), "So Deep Burn can begin")
	assert_false(sim.continue_after_victory(), "There is only one ending to carry on from")
	sim.free()


func _test_keep_burning_retains_the_whole_company() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(8202)
	sim.run_state.business["reputation"] = 23.0
	_complete_the_game(sim)
	var offer: Dictionary = sim.pending_choices[0]
	assert_true(sim.accept_offer("perk", str(offer.get("id", ""))), "The final table's card is taken")
	var modules_before: int = Array(sim.run_state.build.get("modules", [])).size()
	var cash_before: float = float(sim.run_state.economy.get("cash", 0.0))
	var tokens_before: float = float(sim.run_state.statistics.get("lifetime_tokens", 0.0))
	var round_before: int = int(sim.run_state.calendar.get("round", 0))
	var tier_before: int = sim.infrastructure_tier()
	var level_before: int = sim.investor_level()
	var perks_before: Array = Array(sim.run_state.build.get("perks", [])).duplicate()
	_keep_burning(sim)
	assert_almost_eq(float(sim.run_state.economy.get("cash", 0.0)), cash_before, 0.01, "Cash is kept")
	assert_almost_eq(
		float(sim.run_state.statistics.get("lifetime_tokens", 0.0)), tokens_before, 0.01,
		"Everything burned is still on the board"
	)
	assert_eq(int(sim.run_state.calendar.get("round", 0)), round_before, "The calendar does not reset")
	assert_eq(sim.infrastructure_tier(), tier_before, "The machine's scale is kept")
	assert_eq(sim.investor_level(), level_before, "So is the Investor Level")
	assert_eq(Array(sim.run_state.build.get("perks", [])), perks_before, "Every perk, including the final table's, is kept")
	assert_true(str(offer.get("id", "")) in sim.owned_perk_ids(), "The last card drafted is in the build")
	assert_almost_eq(float(sim.run_state.business.get("reputation", 0.0)), 23.0, 0.01, "Reputation is kept")
	assert_eq(Array(sim.run_state.build.get("modules", [])).size(), modules_before, "Modules are kept")
	assert_true(
		not Array(sim.run_state.business.get("job_offers", [])).is_empty(),
		"And there is work on the desk to burn on with"
	)
	sim.free()


func _test_deep_burn_targets_escalate_off_the_final_target() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(8203)
	_complete_the_game(sim)
	_keep_burning(sim)
	var final_burn: float = float(InvestorProgression.final_target(ContentDatabase).get("total_burn", 0.0))
	assert_true(final_burn > 0.0, "The final target names a burn to escalate from")
	assert_eq(int(sim.run_state.depth.get("level", 0)), 0, "No depth is open yet")

	var chosen: Dictionary = _begin_next_depth(sim)
	assert_eq(int(sim.run_state.depth.get("level", 0)), 1, "Depth 1 opens")
	assert_eq(str(sim.run_state.depth.get("status", "")), DepthSystem.STATUS_ACTIVE, "And is live")
	var expected_mult: float = DepthSystem.growth_for(1, ContentDatabase) * float(chosen.get("requirement_mult", 1.0))
	assert_almost_eq(
		float(sim.run_state.depth.get("requirement_mult", 0.0)), expected_mult, 1e-6,
		"Depth 1's requirement is the authored growth times the affix's own multiplier"
	)
	assert_almost_eq(
		float(sim.run_state.depth.get("tokens_needed", 0.0)), final_burn * expected_mult, 1.0,
		"The Deep Burn target is the final target's burn, escalated"
	)
	assert_true(float(sim.run_state.depth.get("tokens_needed", 0.0)) > final_burn, "So it is harder than the game was")
	assert_almost_eq(
		float(sim.run_state.depth.get("baseline_tokens", -1.0)),
		float(sim.run_state.statistics.get("lifetime_tokens", 0.0)), 0.01,
		"Measured from the tokens already burned"
	)
	var progress: Dictionary = sim.depth_progress()
	assert_eq(int(progress.get("level", 0)), 1, "Progress reports the depth")
	assert_almost_eq(float(progress.get("tokens_needed", 0.0)), float(sim.run_state.depth.get("tokens_needed", 0.0)), 1.0, "And its need")
	sim.free()


func _test_a_second_depth_completes() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(8204)
	_complete_the_game(sim)
	_keep_burning(sim)
	_begin_next_depth(sim)
	var need_one: float = float(sim.run_state.depth.get("tokens_needed", 0.0))
	var first: Dictionary = _meet_depth_need(sim)
	assert_eq(str(first.get("outcome", "")), DepthSystem.STATUS_COMPLETE, "Depth 1 completes at its need")
	assert_true(bool(first.get("newly_complete", false)), "As a one-shot crossing")
	assert_true(sim.depth_is_complete(), "The facade agrees")

	_begin_next_depth(sim)
	assert_eq(int(sim.run_state.depth.get("level", 0)), 2, "Depth 2 opens")
	assert_eq(str(sim.run_state.depth.get("status", "")), DepthSystem.STATUS_ACTIVE, "And is live")
	var need_two: float = float(sim.run_state.depth.get("tokens_needed", 0.0))
	assert_true(need_two > need_one, "Depth 2 asks for more than Depth 1 did")
	assert_false(sim.depth_is_complete(), "It starts incomplete")
	var second: Dictionary = _meet_depth_need(sim)
	assert_eq(str(second.get("outcome", "")), DepthSystem.STATUS_COMPLETE, "Depth 2 completes at its need")
	assert_true(bool(second.get("newly_complete", false)), "Also as a fresh crossing")
	assert_eq(int(sim.run_state.statistics.get("depth_reached", 0)), 2, "The run remembers reaching Depth 2")
	assert_true(sim.game_completed(), "The game stays complete throughout")
	assert_true(sim.in_post_victory(), "And the run stays past its ending")
	var picks: Array = sim.offer_depth_picks()
	assert_eq(picks.size(), 3, "Depth 3 is on offer: the ladder does not end")
	sim.free()


func _test_a_run_lost_in_deep_burn_keeps_its_depth_record() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(8205)
	_complete_the_game(sim)
	assert_eq(int(MetaProgress.records().get("highest_depth", -1)), 0, "No depth is on record at completion")
	_keep_burning(sim)
	_begin_next_depth(sim)
	_meet_depth_need(sim)
	_begin_next_depth(sim)
	assert_eq(int(sim.run_state.depth.get("level", 0)), 2, "The run is at Depth 2")
	sim._end_run(false)
	assert_eq(sim.phase, sim.Phase.RUN_END, "The Deep Burn run ends like any other")
	assert_eq(int(MetaProgress.records().get("highest_depth", -1)), 2, "The profile records how deep it went")
	assert_eq(MetaProgress.victories(), 1, "Losing afterwards does not undo the completed game")
	assert_almost_eq(
		float(MetaProgress.records().get("highest_multiplier", 0.0)),
		float(sim.run_state.depth.get("score_mult", 1.0)), 1e-6,
		"And the Deep Burn multiplier it reached"
	)
	sim.free()
