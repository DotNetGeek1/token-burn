extends TestCase

## Wave 3: a warehouse cascade is a BoardSystem fold, not a new resolver verb.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_recursive_compiler_can_cascade()
	_test_cascade_is_flagged_on_the_stage()
	_test_new_modules_resolve()


func _test_recursive_compiler_can_cascade() -> void:
	var hit := false
	var last_tokens: float = 0.0
	for seed_value in range(48):
		var result: Dictionary = _burn(["op.prompt", "op.recursive_compiler"], seed_value + 9300)
		if int(result.get("ok", 0)) == 0 and not bool(result.get("ok", false)):
			continue
		if _stage_cascaded(result, "op.recursive_compiler"):
			hit = true
			last_tokens = float(result.get("progress_tokens", 0.0))
			break
	assert_true(hit, "Recursive Compiler eventually replays the stage above it")
	assert_true(last_tokens > 0.0, "A cascaded burn still produces tokens")


func _test_cascade_is_flagged_on_the_stage() -> void:
	for seed_value in range(48):
		var result: Dictionary = _burn(["op.prompt", "op.recursive_compiler"], seed_value + 9400)
		if not _stage_cascaded(result, "op.recursive_compiler"):
			continue
		var stage: Dictionary = _stage_named(result, "op.recursive_compiler")
		assert_true(bool(stage.get("cascaded", false)), "The resolving stage is marked cascaded")
		return
	assert_true(false, "Needed a cascaded resolve to inspect the stage flag")


func _test_new_modules_resolve() -> void:
	for module_id in [
		"op.recursive_compiler", "op.memory_leak", "op.thermal_lottery", "op.dead_mans_switch",
	]:
		var result: Dictionary = _burn(["op.prompt", module_id], 9500)
		assert_true(result.get("ok", false), "%s resolves in a pipeline" % module_id)
	assert_true(ContentDatabase.get_perk("perk.redline_rider") != null, "Redline Rider exists")


func _burn(module_ids: Array, seed_value: int) -> Dictionary:
	var board := BoardSystem.new()
	var resolver := EffectResolver.new()
	var state := RunState.new()
	board.ensure_board(state, ContentDatabase)
	state.build["modules"] = module_ids.duplicate()
	state.build["hardware"] = ["garage_datacentre"]
	var slots: Array = board.slots(state)
	for i in range(slots.size()):
		slots[i] = str(module_ids[i]) if i < module_ids.size() else ""
	var job := {
		"id": "job.test",
		"name": "Cascade",
		"token_requirement": 10000.0,
		"tokens_remaining": 10000.0,
		"quality": 0.0,
		"quality_threshold": 0.0,
		"known_bugs": 0,
		"hidden_bugs": 0,
		"blocked_slots": 0,
		"board_rules": [],
		"tags": [],
	}
	return board.resolve_burn(
		state, job, 1000.0, DeterministicRng.new(seed_value), resolver, [], -1
	)


func _stage_named(result: Dictionary, module_id: String) -> Dictionary:
	for stage in result.get("stages", []):
		if stage is Dictionary and str(stage.get("module_id", "")) == module_id:
			return stage
	return {}


func _stage_cascaded(result: Dictionary, module_id: String) -> bool:
	return bool(_stage_named(result, module_id).get("cascaded", false))
