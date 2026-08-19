extends TestCase

## Wave 3: a warehouse cascade is a BoardSystem fold, not a new resolver verb.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_recursive_compiler_can_cascade()
	_test_cascade_is_flagged_on_the_stage()
	_test_new_modules_resolve()
	_test_cascade_can_chain()
	_test_cascade_queue_stops_at_the_guard()
	_test_cascade_names_the_source_and_the_replay()
	_test_dead_mans_switch_needs_to_have_run()


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


func _test_cascade_can_chain() -> void:
	var chained := false
	for seed_value in range(80):
		var state := RunState.new()
		var result: Dictionary = _burn(
			["op.prompt", "op.recursive_compiler", "op.recursive_compiler"],
			seed_value + 9800,
			state
		)
		if int(state.statistics.get("cascades_triggered", 0)) >= 2:
			chained = true
			var last: Dictionary = {}
			for stage in result.get("stages", []):
				if stage is Dictionary:
					last = stage
			assert_true(int(last.get("cascade_depth", 0)) >= 1, "The triggering stage records chain depth")
			break
	assert_true(chained, "A later cascade can re-enter the stage above it")


func _test_cascade_queue_stops_at_the_guard() -> void:
	var board := BoardSystem.new()
	var history: Array = []
	for i in range(20):
		history.append({
			"stage": BoardSystem.STAGE_DEFAULTS.duplicate(true),
			"module_id": "op.prompt",
			"index": i,
		})
	var queue: Array = []
	for i in range(20):
		queue.append({
			"hist": i,
			"depth": 1,
			"multiplier": 1.0,
			"cost_mult": 1.0,
			"source_id": "op.prompt",
		})
	var batch: Dictionary = {
		"tokens": 1000.0,
		"token_mult": 1.0,
		"progress_mult": 1.0,
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
	}
	var job := {
		"id": "job.chain",
		"name": "Chain",
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
	var triggered: int = board._drain_cascade_queue(
		queue, history, ChainGuard.new("board.cascade"), RunState.new(), job, batch,
		DeterministicRng.new(1), EffectResolver.new(), [], [], ResolveMode.COMMIT
	)
	assert_eq(
		triggered, EffectOps.MAX_SAME_EVENT_RECURSION,
		"A forced cascade queue stops at the ChainGuard cap"
	)


func _test_cascade_names_the_source_and_the_replay() -> void:
	var board := BoardSystem.new()
	var seen: Array = []
	var on_cascade := func(module_id: String) -> void:
		seen.append(module_id)
	EventBus.cascade_triggered.connect(on_cascade)
	var history: Array = [
		{
			"stage": BoardSystem.STAGE_DEFAULTS.duplicate(true),
			"module_id": "op.prompt",
			"index": 0,
		},
		{
			"stage": BoardSystem.STAGE_DEFAULTS.duplicate(true),
			"module_id": "op.recursive_compiler",
			"index": 1,
		},
	]
	var queue: Array = [{
		"hist": 0,
		"depth": 1,
		"multiplier": 1.0,
		"cost_mult": 1.0,
		"source_id": "op.recursive_compiler",
	}]
	var batch: Dictionary = {
		"tokens": 1000.0,
		"token_mult": 1.0,
		"progress_mult": 1.0,
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
	}
	var job := {
		"id": "job.cascade_meta",
		"name": "Cascade meta",
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
	board._drain_cascade_queue(
		queue, history, ChainGuard.new("board.cascade"), RunState.new(), job, batch,
		DeterministicRng.new(1), EffectResolver.new(), [], [], ResolveMode.COMMIT
	)
	EventBus.cascade_triggered.disconnect(on_cascade)
	assert_eq(seen.size(), 1, "One cascade is emitted")
	assert_eq(
		str(seen[0]), "op.recursive_compiler",
		"The typed signal names the module that caused the cascade, not the one being replayed"
	)


func _test_dead_mans_switch_needs_to_have_run() -> void:
	var reached: Dictionary = _dms_burn(["op.prompt", "op.dead_mans_switch"], 0, 1.0, -1)
	assert_true(
		float(reached.get("progress_mult", 1.0)) >= 9.0,
		"A reached Dead Man's Switch still pays the survive multiplier"
	)
	var blocked: Dictionary = _dms_burn(["op.dead_mans_switch", "op.prompt"], 1, 1.0, -1)
	assert_true(
		float(blocked.get("progress_mult", 1.0)) < 5.0,
		"A contract-blocked switch does not finalise"
	)
	var killed: Dictionary = _dms_burn(["op.prompt", "op.dead_mans_switch"], 0, 1.0, 1)
	assert_true(
		float(killed.get("progress_mult", 1.0)) < 5.0,
		"KILL PROCESS before the switch leaves it inert"
	)


func _dms_burn(module_ids: Array, blocked: int, heat_ratio: float, stage_limit: int) -> Dictionary:
	var board := BoardSystem.new()
	var state := RunState.new()
	board.ensure_board(state, ContentDatabase)
	state.build["modules"] = module_ids.duplicate()
	state.build["hardware"] = ["gpu_rack"]
	state.compute["heat"] = float(state.compute.get("heat_capacity", 100.0)) * heat_ratio
	var slots: Array = board.slots(state)
	for i in range(slots.size()):
		slots[i] = str(module_ids[i]) if i < module_ids.size() else ""
	var job := {
		"id": "job.dms",
		"name": "Switch",
		"token_requirement": 10000.0,
		"tokens_remaining": 10000.0,
		"quality": 0.0,
		"quality_threshold": 0.0,
		"known_bugs": 0,
		"hidden_bugs": 0,
		"blocked_slots": blocked,
		"board_rules": [],
		"tags": [],
	}
	return board.resolve_burn(
		state, job, 1000.0, DeterministicRng.new(1), EffectResolver.new(), [], stage_limit
	)


func _burn(module_ids: Array, seed_value: int, state: RunState = null) -> Dictionary:
	var board := BoardSystem.new()
	var resolver := EffectResolver.new()
	if state == null:
		state = RunState.new()
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
