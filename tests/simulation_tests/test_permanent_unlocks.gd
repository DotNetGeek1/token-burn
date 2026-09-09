extends TestCase

## Permanent Unlocks: what completing the game leaves behind. The final Investor
## Target banks picks and the profile's records; a pick spent on an unlock
## reaches every run from then on; nothing a run itself earned — perks, kit,
## cash — follows it into a fresh one. The two layers keep their own ids: the
## profile never holds a run perk and a run never holds an unlock id as a perk.

const SCRATCH_PROFILE := "user://profile_test_permanent_unlocks.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var restore_path: String = MetaProgress.profile_path
	var restore_enabled: bool = MetaProgress.enabled

	_test_completing_the_game_banks_picks_and_records()
	_test_an_unlock_survives_a_new_run_and_run_perks_do_not()
	_test_the_profile_and_the_run_keep_their_own_ids()
	_test_a_new_run_after_a_win_starts_from_nothing()
	_test_the_permanent_rig_arrives_on_every_fresh_run()

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


## Stands the run up at the top of the game — the highest Infrastructure Tier
## under the final Investor Level — and meets the final target on the next
## prompt, which is how the game is actually completed.
func _complete_the_game(sim: Node) -> Dictionary:
	sim.apply_infrastructure_tier(sim.run_state, InfrastructureSystem.max_tier(ContentDatabase))
	sim.investor_progression().activate_level(
		sim.run_state, InvestorProgression.final_level(ContentDatabase), ContentDatabase
	)
	# The top tier's bills are millions a round; the bankroll must survive them.
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


func _settle_investor_draft(sim: Node) -> void:
	if sim.investor_draft_pending():
		sim.decline_offers()


func _test_completing_the_game_banks_picks_and_records() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(8101)
	sim.run_state.calendar["round"] = 7
	sim.run_state.statistics["peak_prompt_tokens"] = 4.0e9
	sim.run_state.statistics["peak_cash"] = 1.0e6
	var target: Dictionary = _complete_the_game(sim)

	assert_eq(sim.phase, sim.Phase.RUN_END, "Meeting the final target ends the run on the verdict")
	assert_true(sim.game_completed(), "Token Burn is complete")
	assert_true(bool(target.get("final", false)), "The target met was the final one")
	assert_eq(MetaProgress.victories(), 1, "The profile counts the completed game")
	assert_eq(
		MetaProgress.pending_picks(), maxi(1, int(target.get("picks", 1))),
		"And banks the final target's Permanent Unlock picks"
	)
	assert_true(not sim.debrief_choices().is_empty(), "The verdict lays the picks out to spend")

	var records: Dictionary = MetaProgress.records()
	assert_eq(int(records.get("games_completed", 0)), 1, "The records sheet counts the game")
	var fastest: int = int(records.get("fastest_completion_rounds", 0))
	assert_true(fastest >= 7 and fastest <= 8, "And how many rounds it took (%d)" % fastest)
	assert_true(
		float(records.get("highest_single_batch", 0.0)) >= 4.0e9,
		"The biggest batch the run burned is a record"
	)
	assert_true(
		float(records.get("highest_profit", 0.0)) >= 1.0e6,
		"So is the most cash it ever held"
	)
	assert_eq(int(records.get("highest_depth", 0)), 0, "No Deep Burn yet, so no depth record")
	sim.free()


func _test_an_unlock_survives_a_new_run_and_run_perks_do_not() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(8102)
	_complete_the_game(sim)
	assert_true(sim.investor_draft_pending(), "The final target deals the investor's table")
	var offer: Dictionary = sim.pending_choices[0]
	var perk_id: String = str(offer.get("id", ""))
	assert_true(sim.accept_offer("perk", perk_id), "A perk is taken from it")
	assert_true(perk_id in sim.owned_perk_ids(), "And sits in the run")
	assert_true(MetaProgress.pending_picks() > 0, "The game left a pick to spend")
	assert_true(MetaProgress.spend_pick("unlock.parallel_lane"), "It buys a permanent workflow lane")
	assert_eq(MetaProgress.unlock_count("unlock.parallel_lane"), 1, "Which the profile now owns")
	sim.free()

	var next_run: Node = _sim()
	next_run.start_run(8103)
	assert_eq(
		int(next_run.run_state.build.get("meta_workflow_bonus", 0)), 1,
		"The Permanent Unlock reaches the next run"
	)
	assert_true(next_run.owned_perk_ids().is_empty(), "The perk the old run drafted does not")
	assert_false(perk_id in Array(next_run.run_state.build.get("perks", [])), "Not even quietly in build.perks")
	assert_eq(next_run.investor_level(), 1, "The new run starts at Investor Level 1")
	assert_false(next_run.game_completed(), "With the game ahead of it again")
	next_run.free()


func _test_the_profile_and_the_run_keep_their_own_ids() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(8104)
	_complete_the_game(sim)
	var offer: Dictionary = sim.pending_choices[0]
	assert_true(sim.accept_offer("perk", str(offer.get("id", ""))), "A run perk is drafted")
	MetaProgress.spend_pick("unlock.client_retainer")
	sim.free()

	var perk_ids: Array = []
	for perk in ContentDatabase.perks:
		perk_ids.append(str(perk.id))
	var owned_unlocks: Dictionary = Dictionary(MetaProgress._profile.get("unlocks", {}))
	assert_true(not owned_unlocks.is_empty(), "The profile owns an unlock")
	for unlock_id in owned_unlocks.keys():
		assert_true(str(unlock_id).begins_with("unlock."), "%s is an unlock id" % str(unlock_id))
		assert_false(str(unlock_id) in perk_ids, "%s is not a run perk" % str(unlock_id))
		assert_false(MetaProgress.get_unlock(str(unlock_id)).is_empty(), "%s is in the catalog" % str(unlock_id))

	var next_run: Node = _sim()
	next_run.start_run(8105)
	for perk_id in Array(next_run.run_state.build.get("perks", [])):
		assert_false(str(perk_id).begins_with("unlock."), "%s in build.perks is not an unlock id" % str(perk_id))
	for flag_id in Array(next_run.run_state.build.get("meta_unlocks", [])):
		assert_true(str(flag_id).begins_with("unlock."), "%s in build.meta_unlocks is an unlock id" % str(flag_id))
	assert_true(
		float(next_run.run_state.economy.get("passive_income_per_round", 0.0)) > 0.0,
		"The retainer reaches the run as a number, not as an id in its perks"
	)
	next_run.free()


## A "New Run" is a fresh game from nothing. Nothing a finished run bought —
## kit, cash, modules — follows into a run started fresh; only the profile's
## Permanent Unlocks do.
func _test_a_new_run_after_a_win_starts_from_nothing() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(8110)
	sim.run_state.economy["cash"] = 5000000.0
	assert_true(bool(sim.upgrade_cabinet_system("compute").get("ok", false)), "The run buys a compute upgrade")
	_complete_the_game(sim)
	assert_true(sim.game_completed(), "And completes the game")
	sim.free()

	var next_run: Node = _sim()
	next_run.start_run(8111)
	assert_eq(next_run.infrastructure_tier(), 0, "A new run is a new game, on the starting rig")
	assert_eq(next_run.investor_level(), 1, "Under the first target")
	assert_eq(
		int(Dictionary(next_run.run_state.build.get("cabinet_systems", {})).get("compute", 1)), 1,
		"Nothing the old run bought comes along"
	)
	assert_true(
		float(next_run.run_state.economy.get("cash", 0.0)) < 5000000.0,
		"And neither does its bank balance"
	)
	next_run.free()


## The one way hardware crosses runs: the permanent starting-rig ladder, bought
## with picks earned by completing the game. Each pick racks the next rung on
## every fresh run — as far as the tier's floor allows — and a rung the
## starting rig had no space for arrives with the first bigger tier.
func _test_the_permanent_rig_arrives_on_every_fresh_run() -> void:
	_fresh_profile()
	MetaProgress.bank_victory(2)
	assert_true(MetaProgress.spend_pick("unlock.starting_rig"), "The first pick buys the desktop")
	assert_true(MetaProgress.spend_pick("unlock.starting_rig"), "The second buys the GPU rack")

	var sim: Node = _sim()
	sim.start_run(8112)
	var hardware: Array = Array(sim.run_state.build.get("hardware", []))
	assert_false(
		"custom_desktop" in hardware,
		"The starting rig cannot cool the permanent desktop, so it stays in storage"
	)
	assert_false("gpu_rack" in hardware, "And the rack waits for a tier that can cool it")

	# Tier 1 can take the desktop. The rack still cooks there. Winning the
	# target does not change the scale; buying does.
	var target: Dictionary = sim.investor_target()
	sim.run_state.economy["cash"] = 5000000.0
	sim.run_state.statistics["lifetime_tokens"] = float(target.get("total_burn", 0.0)) + 1.0
	sim.run_state.investor["quality_sum"] = 100.0
	sim.run_state.investor["quality_count"] = 1
	sim.debug_finish_prompt({"ok": true, "messages": []})
	_settle_investor_draft(sim)
	assert_true(sim.continue_after_target(), "The win takes the company to the next target")
	assert_eq(sim.infrastructure_tier(), 0, "Without changing the machine's scale")
	sim.run_state.economy["cash"] = 1e12
	assert_true(bool(sim.purchase_infrastructure().get("ok", false)), "Tier 1 is bought in the Market")
	hardware = Array(sim.run_state.build.get("hardware", []))
	assert_true(
		int(UpgradeSystem.upgrade_counts(sim.run_state).get("upgrade.custom_desktop", 0)) > 0,
		"Tier 1 inherits earned compute capacity"
	)
	assert_false("gpu_rack" in hardware, "The rack still cooks at tier 1")

	# Tier 3 is the first that can hold a rack without a separate cooler.
	# Standing there racks the rung tier 1 had to leave boxed.
	sim.apply_infrastructure_tier(sim.run_state, 3)
	sim._install_permanent_rig()
	assert_true(
		int(UpgradeSystem.upgrade_counts(sim.run_state).get("upgrade.gpu_rack", 0)) > 0,
		"Where the earned GPU rack is finally racked"
	)
	sim.free()

	# The ladder has a top: once every rung is owned it stops being offered.
	MetaProgress.bank_victory(3)
	assert_true(MetaProgress.spend_pick("unlock.starting_rig"), "The third pick buys the cluster")
	assert_true(MetaProgress.spend_pick("unlock.starting_rig"), "The fourth buys the garage datacentre")
	assert_true(MetaProgress.spend_pick("unlock.starting_rig"), "The fifth buys the compute warehouse")
	assert_false(MetaProgress.is_available("unlock.starting_rig"), "And there is no sixth rung to sell")
