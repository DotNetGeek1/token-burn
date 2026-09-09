extends TestCase

## Run Perks: taken from the investor's draft, permanent for the run and only
## the run. One perk is followed through every boundary a run has — the move
## to the next target, an infrastructure purchase, the final victory and the
## Keep Burning tail — and then into a fresh run, where it is gone. The
## profile's Permanent Unlocks never see it.

const SCRATCH_PROFILE := "user://profile_test_run_perks_lifecycle.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var restore_path: String = MetaProgress.profile_path
	var restore_enabled: bool = MetaProgress.enabled

	_test_a_drafted_perk_lives_for_the_whole_run_and_no_longer()
	_test_run_perks_never_reach_the_profile()

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
## checks it.
func _meet_target(sim: Node) -> void:
	var target: Dictionary = sim.investor_target()
	sim.run_state.statistics["lifetime_tokens"] = (
		float(sim.run_state.investor.get("baseline_tokens", 0.0))
		+ float(target.get("total_burn", 0.0)) + 1.0
	)
	sim.run_state.investor["quality_sum"] = 100.0
	sim.run_state.investor["quality_count"] = 1
	sim.debug_finish_prompt({"ok": true, "messages": []})


## Takes the first card off the investor's table and returns its id.
func _take_first_card(sim: Node) -> String:
	assert_true(sim.investor_draft_pending(), "The investor's table is dealt")
	if sim.pending_choices.is_empty():
		return ""
	var perk_id: String = str(sim.pending_choices[0].get("id", ""))
	assert_true(sim.accept_offer("perk", perk_id), "%s is taken" % perk_id)
	return perk_id


func _owns(sim: Node, perk_id: String) -> bool:
	return perk_id in sim.owned_perk_ids() and perk_id in Array(sim.run_state.build.get("perks", []))


func _test_a_drafted_perk_lives_for_the_whole_run_and_no_longer() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9301)
	assert_true(sim.owned_perk_ids().is_empty(), "A fresh run owns no perks")

	# Level 1 met: the draft is the only way a perk enters the run.
	_meet_target(sim)
	var perk_id: String = _take_first_card(sim)
	assert_true(perk_id != "", "A perk was drafted")
	assert_true(_owns(sim, perk_id), "And is in the build")
	var subs_with_perk: int = sim.debug_collect_subscriptions().size()

	# 1. The move to the next target.
	assert_true(sim.continue_after_target(), "The company takes the next target")
	assert_eq(sim.investor_level(), 2, "At Investor Level 2")
	assert_true(_owns(sim, perk_id), "The perk survives the move to the next target")
	assert_eq(sim.debug_collect_subscriptions().size(), subs_with_perk, "And is still wired in")

	# 2. An infrastructure purchase.
	sim.run_state.economy["cash"] = InfrastructureSystem.cost_of_tier(1, ContentDatabase) + 1.0
	assert_true(bool(sim.purchase_infrastructure().get("ok", false)), "Tier 1 is bought")
	assert_true(_owns(sim, perk_id), "The perk survives an infrastructure purchase")
	assert_eq(sim.owned_perk_ids().size(), 1, "Alone: the purchase granted no perk of its own")

	# 3. The final victory. Stand at the final level and meet it.
	sim.apply_infrastructure_tier(sim.run_state, InfrastructureSystem.max_tier(ContentDatabase))
	sim.investor_progression().activate_level(
		sim.run_state, InvestorProgression.final_level(ContentDatabase), ContentDatabase
	)
	sim.run_state.economy["cash"] = 100000000.0
	_meet_target(sim)
	assert_true(sim.game_completed(), "The game is complete")
	assert_true(_owns(sim, perk_id), "The perk survives the final victory")
	var second: String = ""
	if sim.investor_draft_pending():
		second = _take_first_card(sim)
	assert_true(second != "" and second != perk_id, "The final target's draft adds a second perk")
	assert_true(_owns(sim, perk_id), "Without displacing the first")

	# 4. Keep Burning.
	assert_true(sim.continue_after_victory(), "The run carries on into Deep Burn")
	assert_true(sim.in_post_victory(), "Past its ending")
	assert_true(_owns(sim, perk_id), "The perk survives Keep Burning")
	assert_true(_owns(sim, second), "So does the second")
	assert_eq(sim.owned_perk_ids().size(), 2, "Two perks, exactly the two drafted")
	# And a round in the tail does not shed it.
	sim.run_state.calendar["round"] = 12
	sim.debug_end_round()
	assert_true(sim.phase != sim.Phase.RUN_END, "The tail goes on past the calendar")
	assert_true(_owns(sim, perk_id), "The perk is still there a round into the tail")

	# 5. A fresh run: gone.
	sim.start_run(9302)
	assert_eq(sim.investor_level(), 1, "A new run starts at Investor Level 1")
	assert_false(_owns(sim, perk_id), "The perk does not follow into a new run")
	assert_false(_owns(sim, second), "Nor does the second")
	assert_true(sim.owned_perk_ids().is_empty(), "The new run owns no perks at all")
	assert_true(
		Array(sim.run_state.build.get("perks", [])).is_empty(),
		"Not even quietly in build.perks"
	)
	sim.free()

	# Nor into a run started by a different Simulation on the same profile.
	var other: Node = _sim()
	other.start_run(9303)
	assert_false(perk_id in other.owned_perk_ids(), "A run on the same profile starts without it")
	other.free()


## Run perks and Permanent Unlocks are separate ledgers: drafting, carrying and
## losing a perk never writes to the profile's unlocks, and an unlock bought
## with a pick never turns up as a perk.
func _test_run_perks_never_reach_the_profile() -> void:
	_fresh_profile()
	# A profile that already owns an unlock, so there is something to disturb.
	MetaProgress.bank_victory(1)
	assert_true(MetaProgress.spend_pick("unlock.parallel_lane"), "The profile owns a permanent lane")
	var unlocks_before: Dictionary = Dictionary(MetaProgress._profile.get("unlocks", {})).duplicate(true)
	assert_false(unlocks_before.is_empty(), "There is an unlock to compare against")

	var sim: Node = _sim()
	sim.start_run(9304)
	assert_eq(
		int(sim.run_state.build.get("meta_workflow_bonus", 0)), 1,
		"The unlock reaches the run as a number"
	)
	assert_true(sim.owned_perk_ids().is_empty(), "And not as a perk")
	_meet_target(sim)
	var perk_id: String = _take_first_card(sim)
	assert_eq(
		Dictionary(MetaProgress._profile.get("unlocks", {})), unlocks_before,
		"Drafting a perk writes nothing to the profile's unlocks"
	)
	assert_eq(MetaProgress.unlock_count(perk_id), 0, "The perk is not an unlock the profile counts")
	assert_true(sim.continue_after_target(), "The company moves on")
	sim.run_state.economy["cash"] = InfrastructureSystem.cost_of_tier(1, ContentDatabase) + 1.0
	assert_true(bool(sim.purchase_infrastructure().get("ok", false)), "And buys a tier")
	assert_eq(
		Dictionary(MetaProgress._profile.get("unlocks", {})), unlocks_before,
		"Carrying it through a move and a purchase writes nothing either"
	)
	for unlock_id in Dictionary(MetaProgress._profile.get("unlocks", {})).keys():
		assert_true(str(unlock_id).begins_with("unlock."), "%s in the profile is an unlock id" % str(unlock_id))
		assert_true(ContentDatabase.get_perk(str(unlock_id)) == null, "%s is not a run perk" % str(unlock_id))
	for owned in sim.owned_perk_ids():
		assert_false(str(owned).begins_with("unlock."), "%s in the run is not an unlock id" % str(owned))
		assert_true(ContentDatabase.get_perk(str(owned)) != null, "%s is a real perk" % str(owned))
	sim.free()

	var next_run: Node = _sim()
	next_run.start_run(9305)
	assert_eq(
		Dictionary(MetaProgress._profile.get("unlocks", {})), unlocks_before,
		"Losing the perk on a new run writes nothing to the profile"
	)
	assert_eq(int(next_run.run_state.build.get("meta_workflow_bonus", 0)), 1, "While the unlock is still applied")
	assert_false(perk_id in next_run.owned_perk_ids(), "And the perk is gone")
	next_run.free()
