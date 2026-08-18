extends TestCase

## Wave 0.B: a burn is a list of events, not a fixed-time crawl of arithmetic.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_warm_cache_is_a_named_beat()
	_test_ordinary_stages_are_faster_than_the_old_crawl()
	_test_a_repeat_is_its_own_beat()


func _test_warm_cache_is_a_named_beat() -> void:
	var preview: Dictionary = _burn(["op.token_cache", "op.foundation_model"], 9101)
	var beats: Array = BurnSpectacle.build(
		preview, Array(preview.get("trace", [])), _slots(["op.token_cache", "op.foundation_model"])
	)
	assert_true(_has_kind(beats, "combo"), "Warm Cache produces a combo beat")
	assert_true(
		_has_label(beats, "WARM CACHE"),
		"And the beat is named after the authored combo"
	)


func _test_ordinary_stages_are_faster_than_the_old_crawl() -> void:
	var preview: Dictionary = _burn(["op.prompt", "op.cheap_model"], 9102)
	var beats: Array = BurnSpectacle.build(preview, [], ["op.prompt", "op.cheap_model"])
	var stages: int = Array(preview.get("stages", [])).size()
	assert_true(stages >= 2, "The starter pair still has two stages")
	assert_true(
		BurnSpectacle.total_duration_ms(beats) < stages * 900,
		"Spectacle time is shorter than the old %.1fs-per-stage crawl" % 0.9
	)


func _test_a_repeat_is_its_own_beat() -> void:
	var preview: Dictionary = _burn(["op.prompt", "op.fractal_split"], 9103)
	var beats: Array = BurnSpectacle.build(preview, [], ["op.prompt", "op.fractal_split"])
	assert_true(
		_has_kind(beats, "repeat"),
		"A recursive fork is printed as its own beat, not folded into the stage line"
	)


func _burn(module_ids: Array, seed_value: int) -> Dictionary:
	var board := BoardSystem.new()
	var resolver := EffectResolver.new()
	var state := RunState.new()
	board.ensure_board(state, ContentDatabase)
	state.build["modules"] = module_ids.duplicate()
	var slots: Array = board.slots(state)
	for i in range(slots.size()):
		slots[i] = str(module_ids[i]) if i < module_ids.size() else ""
	var job := {
		"id": "job.test",
		"name": "Spectacle",
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
	var result: Dictionary = board.resolve_burn(
		state, job, 1000.0, DeterministicRng.new(seed_value), resolver, [], -1
	)
	result["trace"] = resolver.get_trace()
	return result


func _slots(module_ids: Array) -> Array:
	return module_ids.duplicate()


func _has_kind(beats: Array, kind: String) -> bool:
	for beat in beats:
		if beat is Dictionary and str(beat.get("kind", "")) == kind:
			return true
	return false


func _has_label(beats: Array, label: String) -> bool:
	for beat in beats:
		if beat is Dictionary and str(beat.get("label", "")) == label:
			return true
	return false
