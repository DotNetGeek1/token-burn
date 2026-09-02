extends TestCase

## Executable layer rules. These scan source text; they are not a full
## import graph, but they catch the coupling that slowly collapses the facade.


func run() -> void:
	_systems_do_not_depend_on_ui()
	_definitions_do_not_depend_on_simulation_or_ui()
	_presentation_does_not_mutate_run_state()
	_release_overlay_disables_debug_surfaces()
	_ui_does_not_assign_run_state_fields()


func _systems_do_not_depend_on_ui() -> void:
	var hits: Array[String] = _scan_dir("res://systems", ["res://ui/"])
	assert_eq(hits.size(), 0, "systems/ must not reference ui/ (%s)" % ", ".join(hits))


func _definitions_do_not_depend_on_simulation_or_ui() -> void:
	var hits: Array[String] = _scan_dir("res://definitions", [
		"res://ui/",
		"res://core/simulation.gd",
	])
	assert_eq(hits.size(), 0, "definitions/ must not reference Simulation/UI (%s)" % ", ".join(hits))


func _presentation_does_not_mutate_run_state() -> void:
	var hits: Array[String] = _scan_dir("res://presentation", [
		"Simulation.run_state",
	])
	assert_eq(hits.size(), 0, "presentation/ must not touch RunState (%s)" % ", ".join(hits))


func _release_overlay_disables_debug_surfaces() -> void:
	var file := FileAccess.open("res://config/feature_flags.release.json", FileAccess.READ)
	assert_true(file != null, "Release overlay file exists")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	assert_true(parsed is Dictionary, "Release overlay is JSON")
	if parsed is Dictionary:
		assert_false(bool(parsed.get("burn_lab_enabled", true)), "Release overlay disables Burn Lab")
		assert_false(bool(parsed.get("analytics_enabled", true)), "Release overlay keeps analytics off")


func _ui_does_not_assign_run_state_fields() -> void:
	var hits: Array[String] = []
	for path in _gd_files("res://ui"):
		var text: String = FileAccess.get_file_as_string(path)
		if text.contains("Simulation.run_state."):
			# Allowed: reading. Forbidden: Simulation.run_state.section["x"] = ...
			for line in text.split("\n"):
				var stripped: String = line.strip_edges()
				if stripped.begins_with("#"):
					continue
				if stripped.contains("Simulation.run_state.") and (
					stripped.contains("] =") or stripped.contains("]=")
				):
					hits.append("%s: %s" % [path, stripped])
	assert_eq(hits.size(), 0, "UI must not assign Simulation.run_state fields (%s)" % ", ".join(hits))


func _scan_dir(dir_path: String, needles: Array) -> Array[String]:
	var hits: Array[String] = []
	for path in _gd_files(dir_path):
		var text: String = FileAccess.get_file_as_string(path)
		for needle in needles:
			if text.contains(str(needle)):
				hits.append("%s contains %s" % [path, needle])
	return hits


func _gd_files(dir_path: String) -> Array[String]:
	var files: Array[String] = []
	_collect(dir_path, files)
	return files


func _collect(dir_path: String, files: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var child: String = "%s/%s" % [dir_path, name]
		if dir.current_is_dir():
			_collect(child, files)
		elif name.ends_with(".gd"):
			files.append(child)
		name = dir.get_next()
	dir.list_dir_end()
