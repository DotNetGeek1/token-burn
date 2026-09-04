extends Node

## Headless playtest entry point.
##
## Must be launched as a scene rather than with `--script`: Godot does not
## register project autoloads (ContentDatabase, EventBus, Simulation,
## SceneRouter, MetaProgress) in `--script` mode, so the shell cannot boot.
##
## `change_scene` frees `current_scene`. This runner is that scene when Godot
## opens the .tscn, so `_ready` nulls the pointer at once. The node stays a
## root sibling, the harness hangs off it, and the router can rebuild the
## cabinet without taking the suite down with it.
##
##     godot --headless res://tests/run_playtests.tscn
##     godot res://tests/run_playtests.tscn -- --shots --scale=8

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("Token Burn — playtests")
	print("=".repeat(40))
	# Before anything the router might load: we are no longer the current
	# scene, so a scene change will not free this runner.
	get_tree().current_scene = null
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var shots: bool = false
	var scale: float = 12.0
	var filter: String = ""
	for arg in OS.get_cmdline_user_args():
		var text: String = str(arg)
		if text == "--shots":
			shots = true
		elif text.begins_with("--scale="):
			scale = float(text.trim_prefix("--scale="))
		elif text.begins_with("--filter="):
			filter = text.trim_prefix("--filter=")
	var harness := UiHarness.new()
	add_child(harness)
	harness.time_scale = scale
	harness.shots_enabled = shots
	harness.isolate()
	var scripts: Array[String] = _discover_playtests(filter)
	for path in scripts:
		print("  Running %s..." % path)
		# A persona whose script fails to parse comes back from load() as a
		# resource that cannot be instantiated; count it as a failed suite with
		# its path rather than crashing the runner on a null test.
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			_failed += 1
			push_error("  FAIL  could not load or parse %s" % path)
			continue
		var instance: Variant = script.new()
		if instance == null or not instance is PlaytestCase:
			_failed += 1
			push_error("  FAIL  %s is not a PlaytestCase" % path)
			continue
		var test: PlaytestCase = instance
		# Fresh driver per persona so asserts tally on that TestCase, not the
		# dummy the harness built for itself.
		harness.driver = UiDriver.new(harness, test)
		await test.play(harness)
		var results: Dictionary = test.get_results()
		_passed += int(results.get("passed", 0))
		_failed += int(results.get("failed", 0))
		for err in results.get("errors", []):
			push_error("  FAIL  %s" % err)
		print(
			"  Suite %s: %d passed, %d failed"
			% [path, results.get("passed", 0), results.get("failed", 0)]
		)
	print("=".repeat(40))
	print("Results: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(_failed)


func _discover_playtests(filter: String = "") -> Array[String]:
	var scripts: Array[String] = []
	var dir := DirAccess.open("res://tests/playtests")
	if dir == null:
		return scripts
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if (
			not dir.current_is_dir()
			and file_name.ends_with(".gd")
			and (filter == "" or filter in file_name)
		):
			scripts.append("res://tests/playtests/%s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	scripts.sort()
	return scripts
