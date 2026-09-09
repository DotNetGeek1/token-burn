extends TestCase

## Meta-progression is the only state that outlives a run, so these cover what a
## player is promised across runs: only completing the whole game banks picks,
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

	_test_only_completing_the_game_banks_picks()
	_test_a_loss_banks_nothing()
	_test_an_extra_slot_widens_the_next_run()
	_test_the_slot_cap_holds()
	_test_a_starting_module_arrives_owned()
	_test_the_permanent_rig_is_not_refundable()
	_test_the_profile_survives_a_restart()
	_test_a_disabled_meta_layer_leaves_a_run_alone()
	_test_difficulty_choice_carries_into_a_new_run()
	_test_endless_stays_locked_without_a_final_target()
	_test_endless_keeps_the_run_going_past_round_twelve()
	_test_a_legacy_rank_reads_its_total_not_its_stack()
	_test_old_silicon_speeds_the_rig_up()
	_test_recurring_revenue_pays_the_retainer_not_the_contract()
	_test_a_hard_gated_rank_waits_for_a_hard_win()
	_test_sound_settings_default_on_and_persist()
	_test_retired_cloud_unlocks_return_their_picks()
	_test_a_v7_profile_drops_locations_and_seeds_records()
	_test_run_records_only_move_up()

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


## Permanence is the reward for finishing the whole game. A target
## cleared on the way up banks nothing; the summit banks its contract's picks,
## and the debrief lays out every area still open to spend them on.
func _test_only_completing_the_game_banks_picks() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9001)
	sim._end_run(true)
	assert_eq(MetaProgress.victories(), 0, "A target on the way up is not the end of the game")
	assert_eq(MetaProgress.pending_picks(), 0, "So it banks nothing permanent")
	assert_true(sim.debrief_choices().is_empty(), "And there is nothing to spend")
	sim.free()

	_fresh_profile()
	var summit: Node = _sim()
	summit.start_run(9001)
	# The final target is the last authored Investor Level, not a room.
	summit.investor_progression().activate_level(
		summit.run_state, InvestorProgression.final_level(ContentDatabase), ContentDatabase
	)
	var picks: int = maxi(1, int(summit.investor_target().get("picks", 1)))
	summit._end_run(true)
	assert_eq(MetaProgress.victories(), 1, "Completing the final target is the victory")
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


## "One More Pipeline Slot" is overflow allowance, not a wider backplane: the
## next run opens exactly as wide as its rail, and may bolt one stage on.
func _test_an_extra_slot_widens_the_next_run() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(9003)
	var slots_before: int = sim.board_slots().size()
	var safe_before: int = sim.supported_capacity()
	var allowance_before: int = sim.overflow_allowance()
	assert_false(sim.can_append_overflow(), "A bedroom run with nothing unlocked cannot bolt a stage on")

	MetaProgress.bank_victory()
	assert_true(MetaProgress.spend_pick("unlock.extra_slot"), "An extra slot can be kept")

	sim.start_run(9003)
	assert_eq(sim.supported_capacity(), safe_before, "Safe capacity is still the backplane's")
	assert_eq(sim.board_slots().size(), slots_before, "The next run opens no wider than its rail")
	assert_eq(sim.overflow_allowance(), allowance_before + 1, "But it may bolt one more overflow stage on")
	assert_eq(
		int(sim.workflow_capacity_debug().get("legacy_bonus", 0)), 1,
		"The debug breakdown attributes it to the permanent unlock"
	)
	assert_true(sim.can_append_overflow(), "And + STAGE is live from the first round")
	assert_eq(sim.append_overflow_stage(), slots_before, "The stage lands at the end of the pipeline")
	assert_eq(sim.board_slots().size(), slots_before + 1, "Exactly one stage was added")
	assert_true(
		sim.filled_slot_count() >= slots_before,
		"And the pipeline it opens with is at least as long as before"
	)
	sim.free()


func _test_the_slot_cap_holds() -> void:
	_fresh_profile()
	var wanted: int = BoardSystem.MAX_META_OVERFLOW_BONUS
	for _i in range(wanted):
		MetaProgress.bank_victory()
		assert_true(MetaProgress.spend_pick("unlock.extra_slot"), "Slots stack up to the cap")
	assert_false(
		MetaProgress.is_available("unlock.extra_slot"),
		"At the cap the allowance can take no more, so it stops being offered"
	)
	MetaProgress.bank_victory()
	assert_false(MetaProgress.spend_pick("unlock.extra_slot"), "And it cannot be bought anyway")

	var sim: Node = _sim()
	sim.start_run(9004)
	assert_eq(sim.board_slots().size(), BoardSystem.DEFAULT_SLOT_COUNT, "The board still opens at its rail")
	assert_eq(sim.overflow_allowance(), wanted, "Every rank is one stage of allowance")
	assert_eq(
		sim.max_pipeline_length(), BoardSystem.DEFAULT_SLOT_COUNT + wanted,
		"The pipeline may reach rail plus allowance"
	)
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
	sim.apply_infrastructure_tier(sim.run_state, InfrastructureSystem.tier_for_room("garage"))
	sim._install_permanent_rig()
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	assert_eq(
		int(UpgradeSystem.upgrade_counts(sim.run_state).get("upgrade.custom_desktop", 0)),
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


func _test_endless_stays_locked_without_a_final_target() -> void:
	_fresh_profile()
	assert_false(MetaProgress.endless_unlocked(), "A fresh profile has not proven it can reach a real ending")
	MetaProgress.set_endless_enabled(true)
	assert_false(MetaProgress.endless_enabled(), "Toggling it on does nothing until it is actually unlocked")

	MetaProgress.record_ascension("ascension.the_monopoly")
	assert_true(MetaProgress.endless_unlocked(), "Completing a final-tier target unlocks it")
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
		"The next rung is held back until the game has been completed on Hard"
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


## Profile v8: rooms are not progression, so the campaign `locations` block is
## dropped on load, and the new records sheet is seeded from the victories the
## old profile already counted. Nothing else the profile held is lost.
func _test_a_v7_profile_drops_locations_and_seeds_records() -> void:
	_fresh_profile()
	var old_profile := {
		"version": 7,
		"victories": 3,
		"victories_by_difficulty": {"normal": 2, "hard": 1},
		"unlocks": {"unlock.client_retainer": 1},
		"pending_picks": 2,
		"achievements": {"ach.first_burn": 1700000000},
		"lifetime_stats": {"runs": 9.0},
		"difficulty": "hard",
		"locations": {"unlocked": ["bedroom", "garage", "office_unit"], "selected": "garage", "completed": ["bedroom", "garage"]},
	}
	var file := FileAccess.open(SCRATCH_PROFILE, FileAccess.WRITE)
	file.store_string(JSON.stringify(old_profile))
	file.close()
	MetaProgress._loaded = false
	MetaProgress._ensure_loaded()

	assert_false(MetaProgress._profile.has("locations"), "The campaign locations block is gone")
	assert_eq(int(MetaProgress._profile.get("version", 0)), MetaProgress.PROFILE_VERSION, "Brought up to the current version")
	var records: Dictionary = MetaProgress.records()
	assert_eq(int(records.get("games_completed", -1)), 3, "Every old victory was a completed game")
	assert_eq(int(records.get("highest_depth", -1)), 0, "No depth record is invented")
	assert_eq(int(records.get("fastest_completion_rounds", -1)), 0, "Nor a fastest completion")
	assert_eq(MetaProgress.unlock_count("unlock.client_retainer"), 1, "Its unlocks survive the migration")
	assert_eq(MetaProgress.pending_picks(), 2, "So do its banked picks")
	assert_eq(MetaProgress.victories(), 3, "And its victories")
	assert_eq(MetaProgress.victories_on("hard"), 1, "By difficulty too")
	assert_true(MetaProgress.has_achievement("ach.first_burn"), "And its achievements")
	assert_eq(MetaProgress.difficulty(), "hard", "And the difficulty it was set to")

	# Written back and read again, the migrated profile is stable.
	MetaProgress._loaded = false
	MetaProgress._ensure_loaded()
	assert_false(MetaProgress._profile.has("locations"), "Locations do not come back on a reload")
	assert_eq(int(MetaProgress.records().get("games_completed", -1)), 3, "The seeded record survives a reload")


## The records sheet takes the best of every run and never gives one back: a
## worse run later leaves every record where it was, and the fastest completion
## is only taken at the moment the game is completed.
func _test_run_records_only_move_up() -> void:
	_fresh_profile()
	var strong := RunState.new()
	strong.reset()
	strong.statistics["peak_prompt_tokens"] = 5.0e9
	strong.statistics["peak_cash"] = 250000.0
	strong.statistics["depth_reached"] = 3
	strong.depth["level"] = 3
	strong.depth["score_mult"] = 4.5
	strong.calendar["round"] = 9
	strong.flags["victory"] = true
	strong.flags["game_completed"] = true
	MetaProgress.record_run_records(strong)
	var records: Dictionary = MetaProgress.records()
	assert_almost_eq(float(records.get("highest_single_batch", 0.0)), 5.0e9, 1.0, "The biggest batch is recorded")
	assert_almost_eq(float(records.get("highest_profit", 0.0)), 250000.0, 0.01, "So is the richest run")
	assert_eq(int(records.get("highest_depth", 0)), 3, "And the deepest burn")
	assert_almost_eq(float(records.get("highest_multiplier", 0.0)), 4.5, 1e-6, "And the best multiplier")
	assert_eq(int(records.get("fastest_completion_rounds", 0)), 9, "And how fast the game was completed")

	var weak := RunState.new()
	weak.reset()
	weak.statistics["peak_prompt_tokens"] = 10.0
	weak.statistics["peak_cash"] = 100.0
	weak.calendar["round"] = 30
	weak.flags["victory"] = true
	weak.flags["game_completed"] = true
	MetaProgress.record_run_records(weak)
	records = MetaProgress.records()
	assert_almost_eq(float(records.get("highest_single_batch", 0.0)), 5.0e9, 1.0, "A smaller batch changes nothing")
	assert_almost_eq(float(records.get("highest_profit", 0.0)), 250000.0, 0.01, "Nor a poorer run")
	assert_eq(int(records.get("highest_depth", 0)), 3, "Nor a shallower one")
	assert_eq(int(records.get("fastest_completion_rounds", 0)), 9, "A slower completion does not replace the fastest")

	var quick := RunState.new()
	quick.reset()
	quick.calendar["round"] = 6
	quick.flags["victory"] = true
	quick.flags["game_completed"] = true
	MetaProgress.record_run_records(quick)
	assert_eq(int(MetaProgress.records().get("fastest_completion_rounds", 0)), 6, "A faster one does")

	# A run ending deep in Deep Burn, long after it completed the game, has
	# `post_victory` set: its round count is not a completion time.
	var deep := RunState.new()
	deep.reset()
	deep.calendar["round"] = 2
	deep.flags["victory"] = false
	deep.flags["game_completed"] = true
	deep.flags["post_victory"] = true
	deep.statistics["depth_reached"] = 7
	MetaProgress.record_run_records(deep)
	records = MetaProgress.records()
	assert_eq(int(records.get("fastest_completion_rounds", 0)), 6, "A post-victory ending is not a completion time")
	assert_eq(int(records.get("highest_depth", 0)), 7, "But its depth still counts")

	MetaProgress._loaded = false
	MetaProgress._ensure_loaded()
	assert_eq(int(MetaProgress.records().get("highest_depth", 0)), 7, "Records survive a reload")
