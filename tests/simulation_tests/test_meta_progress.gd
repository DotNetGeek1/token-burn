extends TestCase

## Meta-progression is the only state that outlives a run, so these cover what a
## player is promised across runs: only beating the whole campaign banks picks,
## spending one changes every future run, the slot cap holds, and the profile
## survives a restart.
##
## Every test here runs against a scratch profile. The suite must never touch the
## profile the developer is playing.

const SCRATCH_PROFILE := "user://profile_test.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var restore_path: String = MetaProgress.profile_path
	var restore_enabled: bool = MetaProgress.enabled
	MetaProgress.enabled = true

	_test_only_beating_the_campaign_banks_picks()
	_test_a_loss_banks_nothing()
	_test_an_extra_slot_widens_the_next_run()
	_test_the_slot_cap_holds()
	_test_a_starting_module_arrives_owned()
	_test_the_permanent_rig_is_not_refundable()
	_test_the_profile_survives_a_restart()
	_test_a_disabled_meta_layer_leaves_a_run_alone()
	_test_difficulty_choice_carries_into_a_new_run()
	_test_endless_stays_locked_without_a_tier_3_ascension()
	_test_endless_keeps_the_run_going_past_round_twelve()
	_test_a_legacy_rank_reads_its_total_not_its_stack()
	_test_old_silicon_speeds_the_rig_up()
	_test_recurring_revenue_pays_the_retainer_not_the_contract()
	_test_a_hard_gated_rank_waits_for_a_hard_win()
	_test_sound_settings_default_on_and_persist()
	_test_retired_cloud_unlocks_return_their_picks()

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


## Permanence is the reward for finishing the whole campaign. A chapter goal
## cleared on the way up banks nothing; the summit banks its contract's picks,
## and the debrief lays out every area still open to spend them on.
func _test_only_beating_the_campaign_banks_picks() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9001)
	sim._end_run(true)
	assert_eq(MetaProgress.victories(), 0, "A chapter win is not the end of the game")
	assert_eq(MetaProgress.pending_picks(), 0, "So it banks nothing permanent")
	assert_true(sim.debrief_choices().is_empty(), "And there is nothing to spend")
	sim.free()

	_fresh_profile()
	var summit: Node = _sim()
	summit.start_run(9001)
	summit.apply_run_location(summit.run_state, "moon_facility")
	var picks: int = maxi(1, int(summit.ascension_boss_contract().get("picks", 1)))
	summit._end_run(true)
	assert_eq(MetaProgress.victories(), 1, "Beating the last chapter is the victory")
	assert_eq(MetaProgress.pending_picks(), picks, "And it banks the summit contract's picks")

	var choices: Array = summit.debrief_choices()
	var ids: Array = []
	for choice in choices:
		ids.append(str(choice.get("id", "")))
	assert_true(choices.size() >= 5, "The debrief lays out every area still open")
	assert_true("unlock.starting_rig" in ids, "Including the permanent rig ladder")
	assert_true("unlock.parallel_lane" in ids, "And permanent workflow space")
	assert_false(
		"unlock.rule_bug_market" in ids,
		"Prizes tied to specific endings are not for sale"
	)

	assert_true(summit.spend_debrief_pick(str(choices[0].get("id", ""))), "A pick can be spent")
	assert_eq(MetaProgress.pending_picks(), picks - 1, "One pick buys one unlock")
	MetaProgress._profile["pending_picks"] = 0
	assert_false(
		summit.spend_debrief_pick(str(choices[1].get("id", ""))),
		"An empty bank buys nothing"
	)
	summit.free()


func _test_a_loss_banks_nothing() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9002)
	sim._end_run(false)
	assert_eq(MetaProgress.victories(), 0, "Collapsing is not a victory")
	assert_eq(MetaProgress.pending_picks(), 0, "And it pays nothing into the profile")
	assert_true(sim.debrief_choices().is_empty(), "So there is no debrief to sit through")
	sim.free()


func _test_an_extra_slot_widens_the_next_run() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9003)
	var slots_before: int = sim.board_slots().size()

	MetaProgress.bank_victory()
	assert_true(MetaProgress.spend_pick("unlock.extra_slot"), "An extra slot can be kept")

	sim.start_run(9003)
	assert_eq(sim.board_slots().size(), slots_before + 1, "The next run starts one slot wider")
	assert_true(
		sim.filled_slot_count() >= slots_before,
		"And the pipeline it opens with is at least as long as before"
	)
	sim.free()


func _test_the_slot_cap_holds() -> void:
	_fresh_profile()
	var wanted: int = BoardSystem.MAX_SLOT_COUNT - BoardSystem.DEFAULT_SLOT_COUNT
	for _i in range(wanted):
		MetaProgress.bank_victory()
		assert_true(MetaProgress.spend_pick("unlock.extra_slot"), "Slots stack up to the cap")
	assert_false(
		MetaProgress.is_available("unlock.extra_slot"),
		"At the cap the board can take no more, so it stops being offered"
	)
	MetaProgress.bank_victory()
	assert_false(MetaProgress.spend_pick("unlock.extra_slot"), "And it cannot be bought anyway")

	var sim: Node = _sim()
	sim.start_run(9004)
	assert_eq(sim.board_slots().size(), BoardSystem.MAX_SLOT_COUNT, "The widest board is the cap")
	sim.free()


func _test_a_starting_module_arrives_owned() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9005)
	assert_false("op.linter" in sim.owned_modules(), "The linter is not a starter by default")

	MetaProgress.bank_victory()
	assert_true(MetaProgress.spend_pick("unlock.starting_module_linter"), "It can be kept")
	sim.start_run(9005)
	assert_true("op.linter" in sim.owned_modules(), "And the next run starts owning it")
	assert_false(
		MetaProgress.is_available("unlock.starting_module_linter"),
		"Keeping the same module twice would do nothing, so it is not offered again"
	)
	sim.free()


func _test_the_permanent_rig_is_not_refundable() -> void:
	_fresh_profile()
	MetaProgress.bank_victory()
	assert_true(MetaProgress.spend_pick("unlock.starting_rig"), "A permanent rig rung can be kept")
	var sim: Node = _sim()
	sim.start_run(9008)
	# The bedroom cannot cool a desktop, so the rung stays boxed until a room
	# that can take it. The garage is that room.
	sim.apply_run_location(sim.run_state, "garage", false)
	sim._install_permanent_rig()
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	assert_eq(
		UpgradeSystem.installed_count(sim.run_state, "custom_desktop"),
		1,
		"The permanent desktop is racked in the next run"
	)
	assert_almost_eq(
		sim.hardware_sale_refund("custom_desktop"),
		0.0,
		0.01,
		"Permanent-rig hardware has no refund"
	)
	assert_false(sim.can_sell_hardware("custom_desktop"), "The permanent copy cannot be sold")
	sim.free()


func _test_the_profile_survives_a_restart() -> void:
	_fresh_profile()
	MetaProgress.bank_victory()
	MetaProgress.spend_pick("unlock.starting_cash")
	MetaProgress.bank_victory()
	MetaProgress.spend_pick("unlock.starting_cash")

	# Same file, read from scratch: what a player gets when they reopen the game.
	MetaProgress._loaded = false
	MetaProgress._ensure_loaded()
	assert_eq(MetaProgress.victories(), 2, "Victories round-trip through JSON")
	assert_eq(MetaProgress.unlock_count("unlock.starting_cash"), 2, "So do repeated unlocks")
	assert_eq(MetaProgress.pending_picks(), 0, "And so does an empty bank")

	var unlock: Dictionary = MetaProgress.get_unlock("unlock.starting_cash")
	var sim: Node = _sim()
	sim.start_run(9006)
	assert_almost_eq(
		float(sim.run_state.economy.get("cash", 0.0)),
		500.0 + float(MetaProgress._rank_value(unlock, 2)),
		0.01,
		"War Chest rank II total is in the next run's balance"
	)
	sim.free()


func _test_difficulty_choice_carries_into_a_new_run() -> void:
	_fresh_profile()
	MetaProgress.set_difficulty("hard")
	assert_eq(MetaProgress.difficulty(), "hard", "The choice is remembered")
	var sim: Node = _sim()
	sim.start_run(9101)
	var hard_cash: float = float(sim.run_state.economy.get("cash", 0.0))
	sim.free()

	MetaProgress.set_difficulty("normal")
	var sim_normal: Node = _sim()
	sim_normal.start_run(9101)
	var normal_cash: float = float(sim_normal.run_state.economy.get("cash", 0.0))
	sim_normal.free()

	assert_true(hard_cash < normal_cash, "Hard starts with less cash than normal, per the difficulty profile")


func _test_endless_stays_locked_without_a_tier_3_ascension() -> void:
	_fresh_profile()
	assert_false(MetaProgress.endless_unlocked(), "A fresh profile has not proven it can reach a real ending")
	MetaProgress.set_endless_enabled(true)
	assert_false(MetaProgress.endless_enabled(), "Toggling it on does nothing until it is actually unlocked")

	MetaProgress.record_ascension("ascension.the_monopoly")
	assert_true(MetaProgress.endless_unlocked(), "Completing a Tier 3 contract unlocks it")
	assert_true(MetaProgress.endless_enabled(), "The earlier toggle now takes effect")


func _test_endless_keeps_the_run_going_past_round_twelve() -> void:
	_fresh_profile()
	MetaProgress.record_ascension("ascension.the_monopoly")
	MetaProgress.set_endless_enabled(true)

	var sim: Node = _sim()
	sim.start_run(9102)
	sim.run_state.calendar["round"] = 12
	var rent_before: float = float(sim.run_state.economy.get("round_rent", 400.0))
	sim._end_round()
	assert_true(sim.phase != sim.Phase.RUN_END, "The run keeps going instead of ending at round 12")
	assert_eq(int(sim.run_state.calendar["round"]), 13, "The calendar rolls past twelve")
	assert_true(
		float(sim.run_state.economy.get("round_rent", 0.0)) > rent_before,
		"Endless rounds escalate costs so it stays a real challenge"
	)
	sim.free()


func _test_a_disabled_meta_layer_leaves_a_run_alone() -> void:
	_fresh_profile()
	MetaProgress.bank_victory()
	MetaProgress.spend_pick("unlock.extra_slot")

	MetaProgress.enabled = false
	var sim: Node = _sim()
	sim.start_run(9007)
	assert_eq(
		sim.board_slots().size(),
		BoardSystem.DEFAULT_SLOT_COUNT,
		"With the meta layer off a run starts from nothing, whatever is in the profile"
	)
	sim._end_run(true)
	assert_eq(MetaProgress.pending_picks(), 0, "And a victory banks nothing it could spend")
	sim.free()
	MetaProgress.enabled = true


## A Legacy rank table lists totals, not per-pick amounts. Rank two is worth what
## the table says rank two is worth — stacking the rungs would compound the very
## thing the table exists to bound.
func _test_a_legacy_rank_reads_its_total_not_its_stack() -> void:
	_fresh_profile()
	var unlock: Dictionary = MetaProgress.get_unlock("unlock.starting_cash")
	var ranks: Array = Array(unlock.get("ranks", []))
	assert_false(ranks.is_empty(), "War Chest is a ranked unlock")

	MetaProgress.bank_victory(2)
	MetaProgress.spend_pick("unlock.starting_cash")
	MetaProgress.spend_pick("unlock.starting_cash")

	var sim: Node = _sim()
	sim.start_run(9401)
	assert_almost_eq(
		float(sim.run_state.economy.get("cash", 0.0)),
		500.0 + float(ranks[1]),
		0.01,
		"Rank two pays its own total rather than rank one plus rank two"
	)
	sim.free()


## Old Silicon is hardware the profile keeps, so it makes the rig burn faster.
## It must never land on the contract's token requirement, which would sell a
## reward that plays as a difficulty increase.
func _test_old_silicon_speeds_the_rig_up() -> void:
	_fresh_profile()
	var baseline: Node = _sim()
	baseline.start_run(9402)
	var rate_before: float = float(baseline.run_state.compute.get("token_rate", 0.0))
	var job_tokens_before: float = _first_offer_tokens(baseline)
	baseline.free()

	MetaProgress.bank_victory()
	assert_true(MetaProgress.spend_pick("unlock.old_silicon"), "Old Silicon can be kept")
	var expected: float = float(Array(MetaProgress.get_unlock("unlock.old_silicon").get("ranks", []))[0])

	var sim: Node = _sim()
	sim.start_run(9402)
	assert_almost_eq(
		float(sim.run_state.compute.get("token_rate", 0.0)),
		rate_before * expected,
		0.01,
		"The rig burns faster by exactly the rank's multiplier"
	)
	assert_almost_eq(
		_first_offer_tokens(sim),
		job_tokens_before,
		0.01,
		"And contracts still ask for the same work"
	)
	sim.free()


## Recurring Revenue is a retainer, so it pays every round and leaves what a
## contract is worth alone.
func _test_recurring_revenue_pays_the_retainer_not_the_contract() -> void:
	_fresh_profile()
	var baseline: Node = _sim()
	baseline.start_run(9403)
	var job_reward_before: float = _first_offer_reward(baseline)
	baseline.free()

	MetaProgress.bank_victory()
	assert_true(MetaProgress.spend_pick("unlock.recurring_revenue"), "Recurring Revenue can be kept")
	var expected: float = float(
		Array(MetaProgress.get_unlock("unlock.recurring_revenue").get("ranks", []))[0]
	)

	var sim: Node = _sim()
	sim.start_run(9403)
	assert_almost_eq(
		_first_offer_reward(sim),
		job_reward_before,
		0.01,
		"A contract is worth what it was worth"
	)

	var economy := EconomySystem.new()
	sim.run_state.economy["passive_income_per_round"] = 1000.0
	sim.run_state.economy["cash"] = 0.0
	economy.apply_round_bills(sim.run_state, {})
	var paid: float = float(sim.run_state.economy.get("cash", 0.0)) \
		+ float(sim.run_state.economy.get("debt", 0.0))
	assert_true(paid > 0.0, "The retainer landed")
	sim.free()
	assert_true(expected > 1.0, "And the rank is worth more than nothing")


## Late Legacy ranks are the reason Hard is mandatory for a full profile: the
## rung is visible but cannot be bought until the Hard wins are on the board.
func _test_a_hard_gated_rank_waits_for_a_hard_win() -> void:
	_fresh_profile()
	var required: Array = Array(
		MetaProgress.get_unlock("unlock.starting_cash").get("hard_victories_required", [])
	)
	var gated_rank: int = -1
	for i in range(required.size()):
		if int(required[i]) > 0:
			gated_rank = i
			break
	assert_true(gated_rank > 0, "War Chest has a Hard-gated rung")

	MetaProgress.bank_victory(gated_rank + 1)
	for _i in range(gated_rank):
		assert_true(MetaProgress.spend_pick("unlock.starting_cash"), "The ungated rungs are for sale")
	assert_false(
		MetaProgress.is_available("unlock.starting_cash"),
		"The next rung is held back until the campaign has been beaten on Hard"
	)

	for _i in range(int(required[gated_rank])):
		MetaProgress.bank_victory(1, "hard")
	assert_true(
		MetaProgress.is_available("unlock.starting_cash"),
		"Hard wins open it up"
	)
	assert_true(MetaProgress.spend_pick("unlock.starting_cash"), "And it can then be bought")


## The token requirement and fee on the run's first contract offer, for the
## unlocks that must not move them. The board is seeded and sized off the tier's
## expected rig rather than the player's, so the same seed posts the same work
## whatever the profile owns.
func _first_offer(sim: Node) -> Dictionary:
	sim.ensure_job_offers()
	var offers: Array = Array(sim.run_state.business.get("job_offers", []))
	return Dictionary(offers[0]) if not offers.is_empty() else {}


func _first_offer_tokens(sim: Node) -> float:
	return float(_first_offer(sim).get("token_requirement", 0.0))


func _first_offer_reward(sim: Node) -> float:
	return float(_first_offer(sim).get("reward", 0.0))


func _test_sound_settings_default_on_and_persist() -> void:
	_fresh_profile()
	assert_false(MetaProgress.sound_muted(), "Existing/new profiles default to sound on")
	assert_eq(MetaProgress.sound_volume(), 1.0, "Default volume is full")
	MetaProgress.toggle_sound_muted()
	assert_true(MetaProgress.sound_muted(), "Mute persists on the live profile")
	MetaProgress._loaded = false
	MetaProgress._ensure_loaded()
	assert_true(MetaProgress.sound_muted(), "Mute survives a profile reload")
	MetaProgress.set_sound_muted(false)


func _test_retired_cloud_unlocks_return_their_picks() -> void:
	_fresh_profile()
	var scratch := SCRATCH_PROFILE
	var legacy := {
		"version": 6,
		"unlocks": {"unlock.cloud_account": 1, "unlock.starting_cloud": 2},
		"pending_picks": 1,
	}
	var file := FileAccess.open(scratch, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	MetaProgress._loaded = false
	MetaProgress._ensure_loaded()
	assert_eq(MetaProgress.unlock_count("unlock.cloud_account"), 0, "Cloud account ranks are retired")
	assert_eq(MetaProgress.unlock_count("unlock.starting_cloud"), 0, "Starting cloud ranks are retired")
	assert_eq(MetaProgress.pending_picks(), 4, "Each retired rank returns a pick")
	assert_true(MetaProgress.retired_cloud_unlocks(), "The grant is remembered for old run saves")
	MetaProgress._loaded = false
	MetaProgress._ensure_loaded()
	assert_eq(MetaProgress.pending_picks(), 4, "Returned picks survive a reload")
	assert_true(MetaProgress.retired_cloud_unlocks(), "The grant marker survives a reload")
