extends TestCase

## Nested stage replay: repeating a recursion stage also replays that stage's
## own echoes, at multiplicative branch strength.

const CanonicalTest := preload("res://tests/simulation_tests/test_canonical_builds.gd")

const TWO_LEVEL := ["op.overclock", "op.pair_programmer", "op.the_intern"]
const DEEP_CHAIN := [
	"op.overclock", "op.pair_programmer", "op.the_intern", "op.crunch_mode", "op.self_consistency",
]
const DENSITY_CHAIN := ["op.overclock", "op.pair_programmer", "op.the_intern", "op.crunch_mode"]
const SET_CHAIN := ["op.overclock", "op.crunch_mode", "op.self_consistency"]
const FORK_CHAIN := ["op.overclock", "op.pair_programmer", "op.fractal_split"]
const DEJA_CHAIN := ["op.overclock", "op.cheap_model", "op.the_intern"]

## The old one-hop fold only echoed Overclock through Pair (×1.6), then copied
## later stages' own bags. Nested Overclock hops never landed. That flat product
## is obsolete; keep it as the "we beat this" baseline.
const FLAT_ONE_HOP_TOKEN_MULT := 3.2


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_two_level_overclock_pair_intern()
	_test_deep_chain_uses_recursion_density()
	_test_rubber_duck_adds_before_nested_product()
	_test_deja_vu_floors_without_adding()
	_test_recursion_density_applies_once_per_hop()
	_test_set_wins_over_rubber_duck_add()
	_test_repeat_count_forks_independently()
	_test_replay_guards_depth_and_cycles()
	_test_preview_matches_commit_without_stats()


func _test_two_level_overclock_pair_intern() -> void:
	var build := CanonicalTest.Build.new(TWO_LEVEL)
	var result: Dictionary = build.burn()
	assert_almost_eq(
		float(result.get("token_mult", 0.0)), 3.968, 0.0001,
		"Intern replaying Pair also replays Overclock at 40% of 60%"
	)
	assert_true(
		float(result.get("token_mult", 0.0)) > FLAT_ONE_HOP_TOKEN_MULT,
		"Nested replay beats the obsolete flat one-hop product of 3.2"
	)
	assert_eq(
		int(build.state.statistics.get("stage_repeats", 0)), 3,
		"Pair's echo plus Intern's two-deep tree is three replay folds"
	)


func _test_deep_chain_uses_recursion_density() -> void:
	var build := CanonicalTest.Build.new(DEEP_CHAIN)
	var synergy_names: Array = []
	for synergy in build.perk_system.active_synergies(build.state, ContentDatabase):
		synergy_names.append(str(synergy.get("name", "")))
	assert_true("Recursion Density" in synergy_names, "Four recursion modules activate Recursion Density")
	var result: Dictionary = build.burn()
	var expected: float = _overclock_product([0.6 * 1.15, 0.4 * 1.15, 1.8 * 1.15, 0.6 * 1.15])
	assert_almost_eq(
		float(result.get("token_mult", 0.0)), expected, 0.0001,
		"Natural deep-chain tokens use Density once per hop"
	)
	assert_true(
		float(result.get("token_mult", 0.0)) > FLAT_ONE_HOP_TOKEN_MULT,
		"Deep nested Overclock hops beat the obsolete flat 3.2"
	)
	assert_eq(
		int(build.state.statistics.get("stage_repeats", 0)), 10,
		"A five-stage recursion line records ten replay folds"
	)
	for module_id in ["op.pair_programmer", "op.the_intern", "op.crunch_mode", "op.self_consistency"]:
		assert_almost_eq(
			float(_stage_named(result, module_id).get("repeat_strength", 1.0)), 1.15, 0.001,
			"%s carries Recursion Density on repeat_strength" % module_id
		)


func _test_rubber_duck_adds_before_nested_product() -> void:
	var build := CanonicalTest.Build.new(TWO_LEVEL, ["perk.rubber_duck"])
	# Rubber Duck itself is tagged recursion, so Density would also complete.
	# This case is the add, not the synergy.
	var result: Dictionary = build.burn_with_subscriptions(build.subscriptions_without_synergies())
	assert_almost_eq(
		float(_stage_named(result, "op.pair_programmer").get("repeated_previous", 0.0)), 0.9, 0.001,
		"Rubber Duck adds +0.3 on Pair's authored 60%"
	)
	assert_almost_eq(
		float(_stage_named(result, "op.the_intern").get("repeated_previous", 0.0)), 0.7, 0.001,
		"And +0.3 on Intern's authored 40%"
	)
	assert_almost_eq(
		float(result.get("token_mult", 0.0)), 6.194, 0.0001,
		"Nested Overclock is 0.7 × 0.9, so 2 × 1.9 × 1.63"
	)


func _test_deja_vu_floors_without_adding() -> void:
	var build := CanonicalTest.Build.new(DEJA_CHAIN, ["perk.stage_deja_vu"])
	var result: Dictionary = build.burn()
	assert_almost_eq(
		float(_stage_named(result, "op.cheap_model").get("repeated_previous", 0.0)), 0.35, 0.001,
		"Déjà Vu floors Cheap Model at 35%, it does not add 35%"
	)
	assert_almost_eq(
		float(result.get("token_mult", 0.0)), 2.0 * 1.35 * 1.14, 0.0001,
		"Intern's nested Overclock is 0.4 × 0.35"
	)


func _test_recursion_density_applies_once_per_hop() -> void:
	var with_density := CanonicalTest.Build.new(DENSITY_CHAIN)
	var with_burn: Dictionary = with_density.burn()
	var without := CanonicalTest.Build.new(DENSITY_CHAIN)
	var without_burn: Dictionary = without.burn_with_subscriptions(without.subscriptions_without_synergies())
	for module_id in ["op.pair_programmer", "op.the_intern", "op.crunch_mode"]:
		assert_almost_eq(
			float(_stage_named(with_burn, module_id).get("repeat_strength", 1.0)), 1.15, 0.001,
			"%s is scaled by Recursion Density" % module_id
		)
		assert_almost_eq(
			float(_stage_named(without_burn, module_id).get("repeat_strength", 1.0)), 1.0, 0.001,
			"%s is unboosted without the synergy" % module_id
		)
	var expected_with: float = _overclock_product([0.6 * 1.15, 0.4 * 1.15, 1.8 * 1.15])
	var expected_without: float = _overclock_product([0.6, 0.4, 1.8])
	assert_almost_eq(
		float(with_burn.get("token_mult", 0.0)), expected_with, 0.0001,
		"Density multiplies each hop's already-resolved repeat_strength once"
	)
	assert_almost_eq(
		float(without_burn.get("token_mult", 0.0)), expected_without, 0.0001,
		"The same pipeline without Density keeps authored echoes"
	)
	var squared_intern: float = (
		_scaled(2.0, 1.0)
		* _scaled(2.0, 0.6 * 1.15)
		* _scaled(2.0, 0.4 * 1.15 * 1.15 * 0.6 * 1.15)
		* _scaled(2.0, 1.8 * 1.15 * 0.4 * 1.15 * 1.15 * 0.6 * 1.15)
	)
	assert_true(
		absf(float(with_burn.get("token_mult", 0.0)) - squared_intern) > 0.01,
		"A second Density pass on a single hop would square 1.15 and miss the batch"
	)


func _test_set_wins_over_rubber_duck_add() -> void:
	var build := CanonicalTest.Build.new(SET_CHAIN, ["perk.rubber_duck"])
	var result: Dictionary = build.burn()
	var self_c: Dictionary = _stage_named(result, "op.self_consistency")
	var crunch: Dictionary = _stage_named(result, "op.crunch_mode")
	assert_almost_eq(
		float(self_c.get("repeated_previous", 0.0)), 0.6, 0.001,
		"Self-Consistency set(0.6) wins; Rubber Duck does not make it 0.9"
	)
	assert_true(
		float(crunch.get("repeated_previous", 0.0)) > 1.8,
		"Crunch still receives the Rubber Duck add"
	)
	var hop_crunch: float = (
		float(crunch.get("repeated_previous", 0.0)) * float(crunch.get("repeat_strength", 1.0))
	)
	var hop_self: float = (
		float(self_c.get("repeated_previous", 0.0)) * float(self_c.get("repeat_strength", 1.0))
	)
	assert_almost_eq(
		float(result.get("token_mult", 0.0)),
		_scaled(2.0, 1.0) * _scaled(2.0, hop_crunch) * _scaled(2.0, hop_self * hop_crunch),
		0.0001,
		"Nested Overclock uses Self-Consistency's 0.6, not Crunch's duck-boosted echo"
	)


func _test_repeat_count_forks_independently() -> void:
	var result: Dictionary = CanonicalTest.Build.new(FORK_CHAIN).burn()
	assert_almost_eq(
		float(result.get("token_mult", 0.0)), 5.66048, 0.00001,
		"Two 55% trees of Pair→Overclock are 3.2 × 1.33 × 1.33"
	)
	assert_true(
		absf(float(result.get("token_mult", 0.0)) - (3.2 * 1.66)) > 0.01,
		"Two forks must not collapse into one 166% fold"
	)


func _test_replay_guards_depth_and_cycles() -> void:
	var board := BoardSystem.new()
	var history: Array = []
	for i in range(40):
		var stage: Dictionary = BoardSystem.STAGE_DEFAULTS.duplicate(true)
		stage["repeat_previous"] = 1.0
		stage["repeat_strength"] = 1.0
		stage["repeat_count"] = 1.0
		history.append({
			"stage": stage,
			"module_id": "op.overclock",
			"index": i,
			"previous_history_index": i - 1,
			"dropped": false,
		})
	var long_folds: int = board._replay_history_entry(
		_empty_batch(), history, 39, 1.0, 1.0
	)
	assert_true(long_folds > 0, "A synthetic 100% chain still folds something")
	assert_true(
		long_folds <= EffectOps.MAX_TRIGGER_DEPTH,
		"Depth guard stops a 40-hop line at MAX_TRIGGER_DEPTH (got %d)" % long_folds
	)
	var cycle_stage: Dictionary = BoardSystem.STAGE_DEFAULTS.duplicate(true)
	cycle_stage["repeat_previous"] = 1.0
	cycle_stage["repeat_count"] = 1.0
	var cycle_history: Array = [{
		"stage": cycle_stage,
		"module_id": "op.overclock",
		"index": 0,
		"previous_history_index": 0,
		"dropped": false,
	}]
	var cycle_folds: int = board._replay_history_entry(
		_empty_batch(), cycle_history, 0, 1.0, 1.0
	)
	assert_eq(cycle_folds, 1, "A self-parent cycle folds once and stops")


func _test_preview_matches_commit_without_stats() -> void:
	var preview_build := CanonicalTest.Build.new(TWO_LEVEL, [], 8800)
	var repeats_before: int = int(preview_build.state.statistics.get("stage_repeats", 0))
	var preview: Dictionary = preview_build.burn(1000.0, ResolveMode.PREVIEW)
	assert_almost_eq(float(preview.get("token_mult", 0.0)), 3.968, 0.0001, "PREVIEW sees the nested product")
	assert_eq(
		int(preview_build.state.statistics.get("stage_repeats", 0)),
		repeats_before,
		"PREVIEW does not increment stage_repeats"
	)
	var commit_build := CanonicalTest.Build.new(TWO_LEVEL, [], 8800)
	var commit: Dictionary = commit_build.burn(1000.0, ResolveMode.COMMIT)
	assert_almost_eq(
		float(preview.get("token_mult", 0.0)),
		float(commit.get("token_mult", 0.0)),
		0.0001,
		"PREVIEW and COMMIT agree on token_mult for the same seed"
	)
	assert_eq(
		int(commit_build.state.statistics.get("stage_repeats", 0)), 3,
		"COMMIT still records the three replay folds"
	)


func _overclock_product(hops: Array) -> float:
	var product: float = _scaled(2.0, 1.0)
	var nest: float = 1.0
	for hop in hops:
		nest *= float(hop)
		product *= _scaled(2.0, nest)
	return product


func _scaled(value: float, strength: float) -> float:
	return 1.0 + (value - 1.0) * strength


func _stage_named(result: Dictionary, module_id: String) -> Dictionary:
	for stage in result.get("stages", []):
		if str(Dictionary(stage).get("module_id", "")) == module_id:
			return stage
	return {}


func _empty_batch() -> Dictionary:
	return {
		"tokens": 1000.0,
		"token_mult": 1.0,
		"progress_mult": 1.0,
		"quality_mult": 1.0,
		"thermal_mult": 1.0,
		"quality": 0.0,
		"heat": 0.0,
		"cost": 0.0,
		"hide_bugs": 0.0,
		"quality_to_progress": 0.0,
		"known_bugs": 0.0,
		"hidden_bugs": 0.0,
		"revealed": 0.0,
		"fixed": 0.0,
		"scope_tokens": 0.0,
		"quality_positive": 0.0,
		"quality_penalty": 0.0,
		"quality_flat": 0.0,
		"heat_positive": 0.0,
		"heat_cooling": 0.0,
		"heat_flat": 0.0,
		"heat_gen_mult": 1.0,
	}
