extends Node

## Headless test entry point.
##
## Must be launched as a scene rather than with `--script`: Godot does not
## register project autoloads (ContentDatabase, EventBus, Simulation) in
## `--script` mode, so the systems under test fail to compile there.
##
##     godot --headless res://tests/run_tests.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("Token Burn — test runner")
	print("=".repeat(40))
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	# The suite must measure the game, not whatever the developer has unlocked,
	# and must never write to their profile. Tests that want the meta layer turn
	# it back on for themselves.
	MetaProgress.enabled = false
	for path in _discover_test_scripts():
		_run_test_script(path)
	_run_legacy_tests()
	_run_batch("random", 12)
	# The builder plays the game the way the design assumes one is played: it
	# buys cooling before the machine that needs it and takes the work it can
	# actually deliver. Set in the bedroom, which is chapter one and therefore
	# the campaign gate: if a build there cannot beat First Scale-Up, nobody ever
	# reaches the garage and the campaign has no first step.
	var bedroom: Dictionary = _run_batch("builder", 8, "bedroom")
	_assert(
		float(bedroom.get("ascended_rate", 0.0)) > 0.0,
		"A building policy can beat the bedroom's contract inside the year"
	)
	# The garage is the chapter after it, played with the hardware the bedroom
	# was won with, so the sweep starts it the way the campaign would.
	var garage: Dictionary = _run_batch("builder", 8, "garage")
	_assert(
		float(garage.get("max_burn_ratio", 0.0)) > 0.5,
		"And the garage's is within reach of the best run in the garage"
	)
	print("=".repeat(40))
	print("Results: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(_failed)


## One policy sweep, reported as an outcome histogram plus how far the sample got
## against its contract: a win rate alone cannot tell a chapter that is priced
## slightly out of reach from one that is priced absurdly out of reach.
func _run_batch(policy: String, count: int, location: String = "bedroom") -> Dictionary:
	var summary: Dictionary = BatchRunner.new().run(count, policy, location)
	print("Batch [%s in %s] %d runs — ascended %.0f%%, expired %.0f%%, burn %.0f%% avg / %.0f%% best, avg peak %s, avg burned %s, outcomes: %s" % [
		policy,
		location,
		count,
		float(summary.get("ascended_rate", 0.0)) * 100.0,
		float(summary.get("expired_rate", 0.0)) * 100.0,
		float(summary.get("avg_burn_ratio", 0.0)) * 100.0,
		float(summary.get("max_burn_ratio", 0.0)) * 100.0,
		NumberFormat.format_token_rate(float(summary.get("avg_peak_token_rate", 0.0))),
		NumberFormat.format(float(summary.get("avg_lifetime_tokens", 0.0))),
		BatchRunner.describe_outcomes(summary),
	])
	_assert(
		int(summary.get("invalid_number_count", 0)) == 0,
		"Batch [%s] produced no NaN or infinite values" % policy
	)
	# A run that never terminates is a real failure mode, so it fails the suite
	# rather than being averaged away.
	_assert(int(summary.get("stuck_count", 0)) == 0, "Batch [%s] left no run unresolved" % policy)
	return summary


func _discover_test_scripts() -> Array[String]:
	var scripts: Array[String] = []
	var dirs: Array[String] = [
		"res://tests/effect_tests",
		"res://tests/simulation_tests",
		"res://tests/combo_tests",
		"res://tests/content_validation",
		"res://tests/regression_tests",
		"res://tests/architecture_tests",
	]
	for dir_path in dirs:
		_collect_scripts(dir_path, scripts)
	scripts.sort()
	return scripts


func _collect_scripts(dir_path: String, scripts: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".gd") and file_name != "test_case.gd":
			scripts.append("%s/%s" % [dir_path, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()


func _run_test_script(path: String) -> void:
	# Announced before it runs, so a suite that hangs or crashes names itself.
	print("  Running %s..." % path)
	# A script that fails to parse still comes back from load() as a resource,
	# just one that cannot be instantiated. That has to fail the suite loudly
	# with its path, not slip through as "nothing to run".
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		_failed += 1
		push_error("  FAIL  could not load or parse %s" % path)
		return
	var test: Variant = script.new()
	if test == null or not test is TestCase:
		_failed += 1
		push_error("  FAIL  %s is not a TestCase" % path)
		return
	test.run()
	var results: Dictionary = test.get_results()
	_passed += int(results.get("passed", 0))
	_failed += int(results.get("failed", 0))
	for err in results.get("errors", []):
		push_error("  FAIL  %s" % err)
	print("  Suite %s: %d passed, %d failed" % [path, results.get("passed", 0), results.get("failed", 0)])


func _run_legacy_tests() -> void:
	_assert(RunState.new().calendar.get("round") == 1, "RunState default round is 1")
	_assert(RunState.new().calendar.get("prompt") == 1, "RunState default prompt is 1")
	var rng_a := DeterministicRng.new(42)
	var rng_b := DeterministicRng.new(42)
	_assert(rng_a.next_int() == rng_b.next_int(), "DeterministicRng same seed")
	_assert(EffectOps.operation_from_string("multiply") == EffectOps.Operation.MULTIPLY, "EffectOps parse")


func _assert(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % test_name)
	else:
		_failed += 1
		push_error("  FAIL  %s" % test_name)
