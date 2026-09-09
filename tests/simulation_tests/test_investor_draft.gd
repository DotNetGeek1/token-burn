extends TestCase

## The investor's perk draft: dealt once when a level's target is met, answered
## from the verdict screen, and the only way a perk enters a run.

const SCRATCH_PROFILE := "user://profile_test_investor_draft.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_victory_deals_the_investor_draft_once()
	_test_the_draft_blocks_the_move_until_answered()
	_test_taking_a_perk_resolves_the_draft()
	_test_declining_resolves_the_draft()
	_test_final_target_victory_still_deals()
	_test_a_won_run_saved_mid_draft_resumes_it()
	_test_a_legacy_angel_save_still_resolves()
	_test_campaign_perk_pacing()


func _fresh_profile() -> void:
	MetaProgress.enabled = true
	MetaProgress.use_scratch_profile(SCRATCH_PROFILE)


func _cleanup_profile() -> void:
	if FileAccess.file_exists(SCRATCH_PROFILE):
		DirAccess.remove_absolute(SCRATCH_PROFILE)
	MetaProgress._loaded = false


func _sim() -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	return sim


## Stands a run up at the scale a room used to mean: its Infrastructure Tier,
## under the Investor Level whose target that room used to own.
func _run_in(sim: Node, location: String) -> void:
	var tier: int = InfrastructureSystem.tier_for_room(location)
	sim.apply_infrastructure_tier(sim.run_state, tier)
	sim.investor_progression().activate_level(sim.run_state, tier + 1, ContentDatabase)


## Meets the live contract's burn requirement and delivers the prompt that
## checks it, which is how a target is actually met.
func _meet_target(sim: Node) -> void:
	var contract: Dictionary = ContentDatabase.get_investor_target(
		str(sim.run_state.investor.get("contract_id", ""))
	)
	sim.run_state.statistics["lifetime_tokens"] = (
		float(sim.run_state.investor.get("baseline_tokens", 0.0))
		+ float(contract.get("total_burn", 0.0)) + 1.0
	)
	sim.run_state.investor["quality_sum"] = 100.0
	sim.run_state.investor["quality_count"] = 1
	sim.debug_finish_prompt({"ok": true, "messages": []})


func _test_victory_deals_the_investor_draft_once() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(6101)
	var sequence_before: int = int(
		Dictionary(sim.run_state.build.get("draft_state", {})).get("sequence", 0)
	)
	_meet_target(sim)
	assert_eq(sim.phase, sim.Phase.RUN_END, "The target is met")
	assert_true(sim.investor_draft_pending(), "And the investor's table is on the desk")
	assert_eq(sim.draft_kind(), sim.DRAFT_INVESTOR, "Titled for the investor")
	assert_eq(sim.draft_picks_remaining(), 1, "Worth exactly one pick")
	assert_eq(
		sim.pending_choices.size(), MetaProgress.draft_option_count(),
		"Dealt to the profile's draft size"
	)
	for offer in sim.pending_choices:
		assert_eq(str(offer.get("type", "")), "perk", "Every card is a perk")
		assert_almost_eq(float(offer.get("cost", 0.0)), 0.0, 0.001, "And free")
		assert_true(
			sim.can_acquire_perk(str(offer.get("id", ""))),
			"%s can actually be taken" % str(offer.get("id", ""))
		)
	assert_eq(
		int(Dictionary(sim.run_state.build.get("draft_state", {})).get("sequence", 0)),
		sequence_before + 1,
		"Exactly one table was dealt"
	)
	assert_false(
		bool(sim.run_state.flags.get("investor_draft_resolved", true)),
		"The draft is flagged as waiting"
	)
	sim.free()
	_cleanup_profile()


func _test_the_draft_blocks_the_move_until_answered() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(6102)
	_meet_target(sim)
	assert_true(sim.investor_draft_pending(), "The table is dealt")
	assert_false(sim.continue_after_target(), "The company cannot move with it unanswered")
	assert_false(sim.continue_after_victory(), "Nor carry on")
	assert_eq(sim.phase, sim.Phase.RUN_END, "The verdict stays up")
	assert_eq(RoomProgression.room_for(sim.run_state), "bedroom", "Still in the bedroom")
	sim.decline_offers()
	assert_false(sim.investor_draft_pending(), "Declining answers it")
	assert_true(sim.continue_after_target(), "And now the company moves")
	assert_eq(sim.investor_level(), 2, "Up to Investor Level 2")
	assert_eq(sim.phase, sim.Phase.ROUND_PREP, "At round prep — no angel round follows the move")
	assert_true(sim.pending_choices.is_empty(), "With nothing left on the table")
	assert_eq(sim.draft_kind(), "", "And no draft open")
	sim.free()
	_cleanup_profile()


func _test_taking_a_perk_resolves_the_draft() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(6103)
	_meet_target(sim)
	var offer: Dictionary = sim.pending_choices[0]
	var perk_id: String = str(offer.get("id", ""))
	var taken_before: int = int(sim.run_state.statistics.get("angel_offers_taken", 0))
	assert_false(sim.accept_offer("perk", "perk.not_on_the_table"), "A card not dealt is refused")
	assert_true(sim.investor_draft_pending(), "And the table stays open")
	assert_true(sim.accept_offer("perk", perk_id), "Taking a dealt card succeeds")
	assert_true(perk_id in sim.owned_perk_ids(), "The perk is owned")
	assert_false(sim.investor_draft_pending(), "The draft is resolved")
	assert_true(sim.pending_choices.is_empty(), "The rest of the table is cleared")
	assert_true(
		bool(sim.run_state.flags.get("investor_draft_resolved", false)),
		"And flagged as such"
	)
	assert_eq(
		int(sim.run_state.statistics.get("angel_offers_taken", 0)), taken_before + 1,
		"The take is counted"
	)
	assert_eq(sim.phase, sim.Phase.RUN_END, "The verdict is still up for the move")
	assert_true(sim.continue_after_target(), "Which now goes through")
	assert_true(perk_id in sim.owned_perk_ids(), "The perk comes along")
	assert_false(
		bool(sim.run_state.flags.get("investor_draft_resolved", true)),
		"The new level starts with the flag cleared for its own target"
	)
	sim.free()
	_cleanup_profile()


func _test_declining_resolves_the_draft() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(6104)
	_meet_target(sim)
	var declined_before: int = int(sim.run_state.statistics.get("angel_offers_declined", 0))
	sim.decline_offers()
	assert_true(sim.owned_perk_ids().is_empty(), "Nothing was taken")
	assert_false(sim.investor_draft_pending(), "The draft is over")
	assert_eq(
		int(sim.run_state.statistics.get("angel_offers_declined", 0)), declined_before + 1,
		"The refusal is counted"
	)
	sim.decline_offers()
	assert_eq(
		int(sim.run_state.statistics.get("angel_offers_declined", 0)), declined_before + 1,
		"Declining an empty desk does nothing"
	)
	sim.free()
	_cleanup_profile()


func _test_final_target_victory_still_deals() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(6105)
	_run_in(sim, "moon_facility")
	sim.run_state.economy["cash"] = 100000000.0
	_meet_target(sim)
	assert_eq(sim.phase, sim.Phase.RUN_END, "The game is beaten")
	assert_true(sim.game_completed(), "With nowhere further up: the game is complete")
	assert_true(sim.investor_draft_pending(), "The investor still deals for the last goal")
	assert_false(sim.continue_after_victory(), "The endless tail waits on the answer")
	var offer: Dictionary = sim.pending_choices[0]
	assert_true(sim.accept_offer("perk", str(offer.get("id", ""))), "A card is taken")
	assert_true(sim.continue_after_victory(), "Then the run can carry on")
	assert_true(str(offer.get("id", "")) in sim.owned_perk_ids(), "With the perk in the build")
	sim.free()
	_cleanup_profile()


## A save written on the verdict screen with the table dealt comes back with
## the same table, and the answer still gates the move.
func _test_a_won_run_saved_mid_draft_resumes_it() -> void:
	_fresh_profile()
	const SCRATCH_SAVE := "user://save_test_investor_draft.json"
	SaveManager.use_scratch(SCRATCH_SAVE)
	var sim: Node = _sim()
	sim.autosave_enabled = true
	sim.start_run(6106)
	_meet_target(sim)
	assert_true(sim.investor_draft_pending(), "The table is dealt")
	var dealt: Array = []
	for offer in sim.pending_choices:
		dealt.append(str(offer.get("id", "")))
	sim.free()

	var sim2: Node = _sim()
	assert_true(sim2.load_saved_run(), "The verdict save loads")
	assert_eq(sim2.phase, sim2.Phase.RUN_END, "Back on the verdict")
	assert_true(sim2.investor_draft_pending(), "With the table still waiting")
	var loaded: Array = []
	for offer in sim2.pending_choices:
		loaded.append(str(offer.get("id", "")))
	assert_eq(loaded, dealt, "The same cards")
	assert_false(sim2.continue_after_target(), "And the move still waits on it")
	sim2.decline_offers()
	assert_true(sim2.continue_after_target(), "Until it is answered")
	SaveManager.delete_save()
	SaveManager.restore_default()
	sim2.free()
	_cleanup_profile()


## A save from before perks were permanent may still have a round-end angel
## table open. It resolves the old way — into the next round — and is never
## dealt again.
func _test_a_legacy_angel_save_still_resolves() -> void:
	var sim: Node = _sim()
	sim.start_run(6107)
	sim.debug_present_angel_offers()
	assert_eq(sim.phase, sim.Phase.ANGEL_ROUND, "The legacy table opens its own phase")
	assert_eq(sim.draft_kind(), sim.DRAFT_ANGEL, "Titled for the angel")
	assert_true(sim.pending_choices.size() > 0, "With cards on it")
	var offer: Dictionary = sim.pending_choices[0]
	assert_true(sim.accept_offer("perk", str(offer.get("id", ""))), "A card can be taken")
	assert_eq(sim.phase, sim.Phase.ROUND_PREP, "And play resumes at round prep")
	assert_true(str(offer.get("id", "")) in sim.owned_perk_ids(), "The perk is permanent like any other")
	sim.free()


## The campaign's perk pacing in one pass: no perks from settling rounds in the
## start, one draft per target met, and never more than seven at the end.
func _test_campaign_perk_pacing() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(6108)
	sim.run_state.economy["cash"] = 50000.0
	# Two settled early rounds: bills paid, nothing dealt.
	for _round in range(2):
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
		sim.start_work_sync()
		assert_eq(sim.phase, sim.Phase.ROUND_PREP, "A settled round goes to the next prep")
		assert_true(sim.owned_perk_ids().is_empty(), "A settled round hands out no perks")
		assert_true(sim.pending_choices.is_empty(), "And deals nothing")

	var targets: int = 0
	var final_level: int = InvestorProgression.final_level(ContentDatabase)
	while true:
		# Each level's bills are a different order of magnitude; keep the company
		# solvent so the pacing, not the bankroll, is what is measured.
		sim.run_state.economy["cash"] = maxf(
			float(sim.run_state.economy.get("cash", 0.0)), 100000000.0
		)
		_meet_target(sim)
		targets += 1
		assert_eq(sim.phase, sim.Phase.RUN_END, "Target %d is met" % targets)
		assert_true(sim.investor_draft_pending(), "Target %d deals a draft" % targets)
		var offer: Dictionary = sim.pending_choices[0]
		assert_true(
			sim.accept_offer("perk", str(offer.get("id", ""))),
			"Target %d's pick is taken" % targets
		)
		assert_eq(sim.owned_perk_ids().size(), targets, "One perk per target met")
		if sim.game_completed():
			break
		assert_true(sim.continue_after_target(), "On to target %d" % (targets + 1))
		assert_true(targets < 12, "The game has an end")
	assert_eq(targets, final_level, "Every target up to the final one was played")
	assert_true(
		sim.owned_perk_ids().size() <= 7,
		"At most seven perks at the end of the game (%d)" % sim.owned_perk_ids().size()
	)
	assert_eq(
		Array(sim.run_state.build.get("perks", [])).size(), sim.owned_perk_ids().size(),
		"And they all live in build.perks"
	)
	assert_false(sim.run_state.build.has("perk_inventory"), "With no bench anywhere")
	sim.free()
	_cleanup_profile()
