extends Node

## Temporary runner for the suites this change touches. Deleted after the run.


func _ready() -> void:
	print("Token Burn — focused suites")
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	MetaProgress.enabled = false
	var failed: int = 0
	for path in [
		"res://tests/regression_tests/test_critical_bugs.gd",
		"res://tests/simulation_tests/test_ascension.gd",
	]:
		print("  Running %s..." % path)
		var script: GDScript = load(path)
		var test: TestCase = script.new()
		test.run()
		var results: Dictionary = test.get_results()
		failed += int(results.get("failed", 0))
		for err in results.get("errors", []):
			push_error("  FAIL  %s" % err)
		print("  Suite %s: %d passed, %d failed" % [
			path, results.get("passed", 0), results.get("failed", 0),
		])
	get_tree().quit(failed)
