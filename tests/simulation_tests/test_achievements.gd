extends TestCase

## Achievements are the second thing that outlives a run, and the first thing
## that changes what a *later* run is allowed to draft. These cover the promise
## end to end: a run that does something notable earns the award, the award
## survives a restart, and the module it unlocks goes from unreachable to
## reachable in the angel draft.
##
## Every test here runs against a scratch profile. The suite must never touch
## the profile the developer is playing.

const SCRATCH_PROFILE := "user://profile_achievements_test.json"
## The award for losing in the very first round, and the module it hands over.
const WIPEOUT := "ach.round_one_wipeout"
const WIPEOUT_MODULE := "op.stack_overflow"


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
		var operation_id: String = str(reward.get("operation_id", ""))
		assert_true(ContentDatabase.get_operation(operation_id) != null, "%s unlocks a real module" % id)
		assert_false(rewarded_modules.has(operation_id), "%s is unlocked by exactly one award" % operation_id)
		rewarded_modules[operation_id] = id

	# A module gated behind an award has to be the module that award hands over,
	# or it is content nobody can ever reach.
	for operation in ContentDatabase.operations:
		if operation.unlock_achievement == "":
			continue
		assert_true(
			seen.has(operation.unlock_achievement),
			"%s is gated behind a real award" % operation.id
		)
		assert_eq(
			str(rewarded_modules.get(operation.id, "")),
			operation.unlock_achievement,
			"%s is handed over by the award that gates it" % operation.id
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
		"A gated module is not in the draft pool before its award"
	)
	assert_false(
		_in_list(ContentDatabase.unlocked_operations(), WIPEOUT_MODULE),
		"And is not counted as unlocked"
	)

	MetaProgress.grant_achievement(WIPEOUT)
	assert_true(
		_can_draw(WIPEOUT_MODULE),
		"Earning the award puts it in the pool for every run from then on"
	)
	assert_true(
		_in_list(ContentDatabase.unlocked_operations(), WIPEOUT_MODULE),
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


## Whether the module can turn up in an angel draft at all. Drawing two at a
## time from a pool of dozens will not reliably surface one module, so this asks
## the pool rather than gambling on the roll.
func _can_draw(operation_id: String) -> bool:
	var operation: OperationDefinition = ContentDatabase.get_operation(operation_id)
	return operation != null and ContentDatabase.operation_is_unlocked(operation)


func _in_list(operations: Array, operation_id: String) -> bool:
	for operation in operations:
		if operation.id == operation_id:
			return true
	return false
