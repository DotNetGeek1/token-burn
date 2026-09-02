extends TestCase

## Achievements are the second thing that outlives a run, and the first thing
## that changes what a *later* run is allowed to buy. These cover the promise
## end to end: a run that does something notable earns the award, the award
## survives a restart, and the module it unlocks goes from unreachable to
## reachable in the Market.
##
## Every test here runs against a scratch profile. The suite must never touch
## the profile the developer is playing.

const SCRATCH_PROFILE := "user://profile_achievements_test.json"
## The award for losing in the very first round, and the module it hands over.
const WIPEOUT := "ach.round_one_wipeout"
const WIPEOUT_MODULE := "op.stack_overflow"
const FULL_BOARD := "ach.full_board"
const THERMAL_EVENT := "ach.thermal_event"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var restore_path: String = MetaProgress.profile_path
	var restore_enabled: bool = MetaProgress.enabled
	MetaProgress.enabled = true

	_test_the_catalog_is_coherent()
	_test_a_first_round_collapse_earns_the_wtf_award()
	_test_an_award_is_only_ever_earned_once()
	_test_awards_survive_a_restart()
	_test_a_gated_module_is_unreachable_until_its_award_is_earned()
	_test_lifetime_counters_accumulate_across_runs()
	_test_a_disabled_meta_layer_earns_nothing()
	_test_maximum_pipeline_reads_the_fullest_workflow()
	_test_a_fatal_heat_prompt_earns_thermal_event()
	_test_victory_gates_unlock_in_order()
	_test_hard_victories_unlock_hard_gated_modules()
	_test_achievement_and_victory_gates_and_together()
	_test_draw_pool_respects_victory_gates()
	_test_repurposed_awards_hand_over_new_modules()
	_test_telemetry_achievements_unlock_their_modules()

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


func _test_the_catalog_is_coherent() -> void:
	assert_true(ContentDatabase.achievements.size() >= 20, "The cabinet ships a full set of awards")
	var seen: Dictionary = {}
	var rewarded_modules: Dictionary = {}
	for achievement in ContentDatabase.achievements:
		var id: String = str(achievement.get("id", ""))
		assert_true(id.begins_with("ach."), "Achievement id is namespaced: %s" % id)
		assert_false(seen.has(id), "Achievement id %s is unique" % id)
		seen[id] = true
		assert_true(str(achievement.get("name", "")) != "", "%s has a name" % id)
		assert_true(str(achievement.get("hint", "")) != "", "%s tells the player how to earn it" % id)
		assert_true(str(achievement.get("description", "")) != "", "%s has flavour" % id)
		assert_true(
			str(achievement.get("category", "")) in ["milestone", "disaster", "secret"],
			"%s sits in a known category" % id
		)
		var condition: Dictionary = Dictionary(achievement.get("condition", {}))
		assert_true(
			str(condition.get("trigger", "")) in [
				AchievementSystem.TRIGGER_TICK, AchievementSystem.TRIGGER_RUN_END,
			],
			"%s is checked at a moment the game actually reaches" % id
		)
		assert_true(Array(condition.get("checks", [])).size() > 0, "%s can be earned at all" % id)
		var reward: Dictionary = Dictionary(achievement.get("reward", {}))
		if str(reward.get("type", "none")) != "unlock_module":
			continue
		var module_id: String = str(reward.get("module_id", ""))
		assert_true(ContentDatabase.get_module(module_id) != null, "%s unlocks a real module" % id)
		assert_false(rewarded_modules.has(module_id), "%s is unlocked by exactly one award" % module_id)
		rewarded_modules[module_id] = id

	# A module gated behind an award has to be the module that award hands over,
	# or it is content nobody can ever reach.
	for module in ContentDatabase.modules:
		if module.unlock_achievement == "":
			continue
		assert_true(
			seen.has(module.unlock_achievement),
			"%s is gated behind a real award" % module.id
		)
		assert_eq(
			str(rewarded_modules.get(module.id, "")),
			module.unlock_achievement,
			"%s is handed over by the award that gates it" % module.id
		)


func _test_a_first_round_collapse_earns_the_wtf_award() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(7001)
	assert_false(MetaProgress.has_achievement(WIPEOUT), "A fresh profile has earned nothing")
	sim._end_run(false)
	assert_true(MetaProgress.has_achievement(WIPEOUT), "Collapsing in round one is, in fact, an achievement")
	sim.free()


func _test_an_award_is_only_ever_earned_once() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(7002)
	sim._end_run(false)
	assert_true(MetaProgress.has_achievement(WIPEOUT), "Earned on the first collapse")
	var earned_at: int = int(MetaProgress.achievements()[WIPEOUT])
	var count_before: int = MetaProgress.achievement_count()

	sim.start_run(7003)
	sim._end_run(false)
	assert_eq(MetaProgress.achievement_count(), count_before, "A second collapse adds nothing new")
	assert_eq(int(MetaProgress.achievements()[WIPEOUT]), earned_at, "And does not restamp the original")
	sim.free()


func _test_awards_survive_a_restart() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(7004)
	sim._end_run(false)
	sim.free()

	# Same file, read from scratch: what a player gets when they reopen the game.
	MetaProgress._loaded = false
	MetaProgress._ensure_loaded()
	assert_true(MetaProgress.has_achievement(WIPEOUT), "The award round-trips through JSON")
	assert_almost_eq(MetaProgress.lifetime_stat("runs"), 1.0, 0.01, "So do the lifetime counters")
	assert_almost_eq(MetaProgress.lifetime_stat("losses"), 1.0, 0.01, "Including the unflattering ones")


func _test_a_gated_module_is_unreachable_until_its_award_is_earned() -> void:
	_fresh_profile()
	assert_false(MetaProgress.has_achievement(WIPEOUT), "Starting from nothing earned")
	assert_false(
		_can_draw(WIPEOUT_MODULE),
		"A gated module is not Market-eligible before its award"
	)
	assert_false(
		_in_list(ContentDatabase.unlocked_modules(), WIPEOUT_MODULE),
		"And is not counted as unlocked"
	)

	MetaProgress.grant_achievement(WIPEOUT)
	assert_true(
		_can_draw(WIPEOUT_MODULE),
		"Earning the award makes it Market-eligible in every run from then on"
	)
	assert_true(
		_in_list(ContentDatabase.unlocked_modules(), WIPEOUT_MODULE),
		"And the gallery can show it as reachable"
	)


func _test_lifetime_counters_accumulate_across_runs() -> void:
	_fresh_profile()
	for seed_value in [7010, 7011, 7012]:
		var sim: Node = _sim()
		sim.start_run(seed_value)
		sim._end_run(false)
		sim.free()
	assert_almost_eq(MetaProgress.lifetime_stat("runs"), 3.0, 0.01, "Every finished run is counted once")
	assert_almost_eq(MetaProgress.lifetime_stat("losses"), 3.0, 0.01, "And every collapse with it")


func _test_a_disabled_meta_layer_earns_nothing() -> void:
	_fresh_profile()
	MetaProgress.enabled = false
	var sim: Node = _sim()
	sim.start_run(7020)
	sim._end_run(false)
	assert_eq(MetaProgress.achievement_count(), 0, "With the meta layer off nothing is banked")
	assert_almost_eq(MetaProgress.lifetime_stat("runs"), 0.0, 0.01, "Not even the run count")
	sim.free()
	MetaProgress.enabled = true


func _test_maximum_pipeline_reads_the_fullest_workflow() -> void:
	_fresh_profile()
	var state := RunState.new()
	state.build["board"] = {"slot_count": 8, "active_workflow": 0}
	state.build["workflows"] = [
		{
			"id": "workflow.1", "name": "First half",
			"slots": ["op.prompt", "op.prompt", "op.prompt", "op.prompt", "", "", "", ""],
		},
		{
			"id": "workflow.2", "name": "Second half",
			"slots": ["", "", "", "", "op.prompt", "op.prompt", "op.prompt", "op.prompt"],
		},
	]
	AchievementSystem.new().evaluate_tick(state, ContentDatabase)
	assert_false(
		MetaProgress.has_achievement(FULL_BOARD),
		"Two half-filled workflows do not add up to Maximum Pipeline"
	)
	state.build["workflows"] = [{
		"id": "workflow.1", "name": "Full",
		"slots": [
			"op.prompt", "op.prompt", "op.prompt", "op.prompt",
			"op.prompt", "op.prompt", "op.prompt", "op.prompt",
		],
	}]
	AchievementSystem.new().evaluate_tick(state, ContentDatabase)
	assert_true(
		MetaProgress.has_achievement(FULL_BOARD),
		"One workflow with all eight slots filled earns Maximum Pipeline"
	)
	assert_true(_can_draw("op.crunch_mode"), "Maximum Pipeline unlocks Crunch Mode")


func _test_a_fatal_heat_prompt_earns_thermal_event() -> void:
	_fresh_profile()
	var sim: Node = _sim()
	sim.start_run(7021)
	sim.run_state.flags["fire_risk"] = true
	sim.run_state.compute["heat"] = float(sim.run_state.compute.get("heat_capacity", 100.0))
	sim._finish_prompt({"ok": true, "messages": []})
	assert_eq(sim.phase, sim.Phase.RUN_END, "Full heat ends the run as a hardware fire")
	assert_true(
		MetaProgress.has_achievement(THERMAL_EVENT),
		"The run-end award sees the peak recorded by the fatal prompt"
	)
	assert_true(
		_can_draw("op.thermal_throttle"),
		"Thermal Event now unlocks Emergency Throttle"
	)
	sim.free()


func _test_victory_gates_unlock_in_order() -> void:
	_fresh_profile()
	assert_false(_can_draw("op.requirements_doc"), "Fresh profiles cannot draft V1 modules")
	assert_false(_can_draw("op.constraint_solver"), "Fresh profiles cannot draft V2 modules")
	assert_false(_can_draw("op.memory_palace"), "Fresh profiles cannot draft V3 modules")
	assert_false(_can_draw("op.formal_verification"), "Fresh profiles cannot draft V5 modules")
	assert_true(_can_draw("op.system_prompt"), "OPEN expansion modules remain draftable")

	MetaProgress.bank_victory(0, "normal")
	assert_true(_can_draw("op.requirements_doc"), "One victory unlocks V1")
	assert_false(_can_draw("op.constraint_solver"), "V2 stays locked after one victory")

	MetaProgress.bank_victory(0, "normal")
	assert_true(_can_draw("op.constraint_solver"), "Two victories unlock V2")
	assert_false(_can_draw("op.memory_palace"), "V3 stays locked after two victories")

	MetaProgress.bank_victory(0, "normal")
	assert_true(_can_draw("op.memory_palace"), "Three victories unlock V3")
	assert_false(_can_draw("op.formal_verification"), "V5 stays locked after three victories")

	MetaProgress.bank_victory(0, "normal")
	MetaProgress.bank_victory(0, "normal")
	assert_true(_can_draw("op.formal_verification"), "Five victories unlock V5")


func _test_hard_victories_unlock_hard_gated_modules() -> void:
	_fresh_profile()
	assert_false(_can_draw("op.autonomous_loop"), "Fresh profiles cannot draft H1 modules")
	assert_false(_can_draw("op.benchmark_daemon"), "Fresh profiles cannot draft H3 modules")
	MetaProgress.bank_victory(0, "hard")
	assert_eq(MetaProgress.victories(), 1, "A Hard win still counts as a total victory")
	assert_true(_can_draw("op.autonomous_loop"), "One Hard victory unlocks H1")
	assert_false(_can_draw("op.benchmark_daemon"), "H3 stays locked after one Hard victory")
	MetaProgress.bank_victory(0, "hard")
	MetaProgress.bank_victory(0, "hard")
	assert_true(_can_draw("op.benchmark_daemon"), "Three Hard victories unlock H3")


func _test_achievement_and_victory_gates_and_together() -> void:
	_fresh_profile()
	var module := ModuleDefinition.new()
	module.id = "op.synthetic_and_gate"
	module.unlock_achievement = WIPEOUT
	module.min_victories = 1
	assert_false(
		ContentDatabase.module_is_unlocked(module),
		"Missing achievement keeps a combined gate closed"
	)
	MetaProgress.grant_achievement(WIPEOUT)
	assert_false(
		ContentDatabase.module_is_unlocked(module),
		"Missing victories keep a combined gate closed"
	)
	MetaProgress.bank_victory(0, "normal")
	assert_true(
		ContentDatabase.module_is_unlocked(module),
		"Achievement and victories AND together"
	)


func _test_draw_pool_respects_victory_gates() -> void:
	_fresh_profile()
	var state := RunState.new()
	state.reset()
	var offers: Array = ContentDatabase.draw_market_modules(DeterministicRng.new(88), state, 24)
	for module in offers:
		assert_true(module is ModuleDefinition, "Market draw returns module definitions")
		assert_true(
			ContentDatabase.module_is_unlocked(module),
			"Market stock never includes locked modules"
		)
		assert_eq(int(module.min_victories), 0, "Fresh Market pool stays at OPEN victory gates")
		assert_eq(int(module.min_hard_victories), 0, "Fresh Market pool stays at OPEN Hard gates")


func _test_repurposed_awards_hand_over_new_modules() -> void:
	_fresh_profile()
	assert_false(_can_draw("op.judge_model"), "Judge Model starts locked behind Spotless")
	MetaProgress.grant_achievement("ach.spotless")
	assert_true(_can_draw("op.judge_model"), "Spotless unlocks Judge Model")
	assert_false(_can_draw("op.thermal_throttle"), "Emergency Throttle starts locked")
	MetaProgress.grant_achievement(THERMAL_EVENT)
	assert_true(_can_draw("op.thermal_throttle"), "Thermal Event unlocks Emergency Throttle")


func _test_telemetry_achievements_unlock_their_modules() -> void:
	_fresh_profile()
	var cases: Array = [
		["ach.property_owner", "op.property_tests", {"clean_completions": 3}],
		["ach.fuzzed_prod", "op.fuzz_tester", {"hidden_bugs_created": 8}],
		["ach.golden_reference", "op.golden_dataset", {"clean_one_shot_completions": 3}],
		["ach.cold_operator", "op.heat_pipe", {"cool_completions": 4}],
		["ach.code_review", "op.reviewer_agent", {"bugs_fixed": 10}],
		["ach.watch_this", "op.watchdog_agent", {"hidden_bugs_revealed": 10}],
	]
	for entry in cases:
		_fresh_profile()
		var achievement_id: String = str(entry[0])
		var module_id: String = str(entry[1])
		var stats: Dictionary = Dictionary(entry[2])
		assert_false(_can_draw(module_id), "%s starts locked" % module_id)
		var state := RunState.new()
		state.reset()
		for key in stats.keys():
			state.statistics[str(key)] = stats[key]
		AchievementSystem.new().evaluate_tick(state, ContentDatabase)
		AchievementSystem.new().evaluate_run_end(state, {}, ContentDatabase)
		assert_true(
			MetaProgress.has_achievement(achievement_id),
			"%s unlocks from its telemetry" % achievement_id
		)
		assert_true(_can_draw(module_id), "%s becomes Market-eligible after its award" % module_id)


## Whether the module can turn up in the Market at all. Drawing a short shelf
## from a pool of dozens will not reliably surface one module, so this asks
## the unlock gate rather than gambling on the roll.
func _can_draw(module_id: String) -> bool:
	var module: ModuleDefinition = ContentDatabase.get_module(module_id)
	return module != null and ContentDatabase.module_is_unlocked(module)


func _in_list(modules: Array, module_id: String) -> bool:
	for module in modules:
		if module.id == module_id:
			return true
	return false
