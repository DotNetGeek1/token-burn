extends TestCase

## The burn already resolves combos, forks and synergies. These tests check that
## the spectacle log names those events without changing the batch maths.

const BurnBoardTest := preload("res://tests/simulation_tests/test_burn_board.gd")
const CanonicalTest := preload("res://tests/simulation_tests/test_canonical_builds.gd")
const BurnSpectacle := preload("res://presentation/burn_spectacle.gd")


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_combo_subscriptions_carry_the_combo_name()
	_test_read_the_docs_is_a_loud_combo_beat()
	_test_echo_chamber_is_a_fork_beat()
	_test_vibe_coding_lands_as_a_named_beat()
	_test_a_quiet_stage_stays_quiet()
	_test_compiler_does_not_rewrite_the_burn()
	_test_preview_does_not_touch_the_live_resolver()
	_test_warm_cache_is_a_named_beat()
	_test_ordinary_stages_are_faster_than_the_old_crawl()
	_test_duration_follows_capped_holds()
	_test_a_repeat_is_its_own_beat()
	_test_scope_consequence_explains_backward_progress()
	_test_spectacle_flag_disables_preview_beats()
	_test_clearing_the_bar_is_a_loud_beat()
	_test_rising_bug_risk_is_a_loud_beat()


func _beats_of(kind: String, beats: Array) -> Array:
	var matched: Array = []
	for beat in beats:
		if str(beat.get("kind", "")) == kind:
			matched.append(beat)
	return matched


func _labels(beats: Array) -> PackedStringArray:
	var labels := PackedStringArray()
	for beat in beats:
		labels.append(str(beat.get("label", "")))
	return labels


func _test_combo_subscriptions_carry_the_combo_name() -> void:
	var prompt: ModuleDefinition = ContentDatabase.get_module("op.prompt")
	var found := false
	for sub in prompt.to_subscriptions("board.stage_resolved"):
		if str(sub.get("combo_name", "")) != "Read the Docs":
			continue
		found = true
		assert_eq(str(sub.get("source_id", "")), "op.prompt", "ChainGuard still sees the module")
		assert_eq(str(sub.get("source_kind", "")), "combo", "And the subscription is marked as a combo")
	assert_true(found, "Read the Docs is stamped on the combo subscription")


func _test_read_the_docs_is_a_loud_combo_beat() -> void:
	var harness := BurnBoardTest.Harness.new(8101)
	harness.pipeline(["op.prompt_library", "op.prompt"])
	var burn: Dictionary = harness.burn()
	assert_true(burn.get("ok", false), "The combo pipeline resolves")
	var prompt_stage: Dictionary = {}
	for stage in burn.get("stages", []):
		if str(stage.get("module_id", "")) == "op.prompt":
			prompt_stage = stage
			break
	assert_eq(
		Array(prompt_stage.get("combos", [])).size(), 1,
		"The stage records the live combo"
	)
	assert_eq(
		str(Dictionary(Array(prompt_stage.get("combos", [{}]))[0]).get("name", "")),
		"Read the Docs",
		"By the name the editor already prints"
	)
	var traces: Array = harness.resolver.get_trace()
	var combo_trace := false
	for entry in traces:
		if str(Dictionary(entry.get("metadata", {})).get("combo_name", "")) == "Read the Docs":
			combo_trace = true
			break
	assert_true(combo_trace, "The resolver trace carries the combo name")
	var tokens_before: float = float(burn.get("tokens", 0.0))
	var progress_before: float = float(burn.get("progress_mult", 1.0))
	var beats: Array = BurnSpectacle.compile(burn, traces)
	assert_eq(float(burn.get("tokens", 0.0)), tokens_before, "Compile leaves tokens alone")
	assert_eq(float(burn.get("progress_mult", 1.0)), progress_before, "And the multiplier")
	var combos: Array = _beats_of(BurnSpectacle.KIND_COMBO, beats)
	assert_true(combos.size() > 0, "Read the Docs becomes a combo beat")
	assert_eq(str(combos[0].get("label", "")), "READ THE DOCS", "Named for the slam")
	assert_true(bool(combos[0].get("loud", false)), "And it holds")
	assert_true(
		float(combos[0].get("progress_mult", 1.0)) > 1.0,
		"The ticker has already climbed"
	)


func _test_echo_chamber_is_a_fork_beat() -> void:
	var harness := BurnBoardTest.Harness.new(8102)
	harness.pipeline(["op.cheap_model", "op.echo_chamber"])
	var burn: Dictionary = harness.burn()
	var beats: Array = BurnSpectacle.compile(burn, harness.resolver.get_trace())
	var forks: Array = _beats_of(BurnSpectacle.KIND_FORK, beats)
	assert_true(forks.size() > 0, "Echoing the stage above is a fork beat")
	assert_true(str(forks[0].get("label", "")).begins_with("AGAIN! ×"), "Named as another pass")
	assert_true(bool(forks[0].get("loud", false)), "And it is loud")


func _test_vibe_coding_lands_as_a_named_beat() -> void:
	var build := CanonicalTest.Build.new(
		["op.prompt", "op.stack_overflow"],
		["perk.vibe_check", "perk.bug_alchemy"],
		8103
	)
	var burn: Dictionary = build.burn()
	assert_true(
		float(burn.get("progress_mult", 1.0)) > 1.0,
		"The synergy actually moves this batch"
	)
	var beats: Array = BurnSpectacle.compile(burn, build.resolver.get_trace())
	var synergies: Array = _beats_of(BurnSpectacle.KIND_SYNERGY, beats)
	assert_true(
		"VIBE CODING" in _labels(synergies),
		"Vibe Coding slams after the stages: %s" % ", ".join(_labels(beats))
	)


func _test_a_quiet_stage_stays_quiet() -> void:
	var harness := BurnBoardTest.Harness.new(8104)
	harness.pipeline(["op.echo_chamber"])
	var burn: Dictionary = harness.burn()
	var beats: Array = BurnSpectacle.compile(burn, harness.resolver.get_trace())
	var stages: Array = _beats_of(BurnSpectacle.KIND_STAGE, beats)
	assert_true(stages.size() > 0, "A lone echo still prints as a stage")
	assert_false(bool(stages[0].get("loud", true)), "With nothing to fork it stays quiet")
	assert_eq(_beats_of(BurnSpectacle.KIND_FORK, beats).size(), 0, "And does not claim a fork")


func _test_compiler_does_not_rewrite_the_burn() -> void:
	var harness := BurnBoardTest.Harness.new(8105)
	harness.pipeline(["op.prompt", "op.cheap_model"])
	var burn: Dictionary = harness.burn()
	var snapshot: Dictionary = burn.duplicate(true)
	BurnSpectacle.compile(burn, harness.resolver.get_trace())
	assert_eq(
		float(burn.get("tokens", 0.0)), float(snapshot.get("tokens", 0.0)),
		"Tokens are unchanged"
	)
	assert_eq(
		float(burn.get("progress_mult", 1.0)), float(snapshot.get("progress_mult", 1.0)),
		"Progress is unchanged"
	)
	assert_eq(
		int(Array(burn.get("stages", [])).size()),
		int(Array(snapshot.get("stages", [])).size()),
		"The stage list is the same length"
	)


func _test_preview_does_not_touch_the_live_resolver() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(8106)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(offers.size() > 0, "A run opens with work to preview")
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work()
	var phase_before: int = sim.phase
	var prompt_before: int = int(sim.run_state.calendar.get("prompt", 0))
	var live_before: int = sim.effect_resolver.get_trace().size()
	var preview: Dictionary = sim.preview_burn()
	assert_true(preview.get("ok", false), "The board can preview a burn")
	assert_true(
		Array(preview.get("spectacle", [])).size() > 0,
		"The preview carries a spectacle log"
	)
	assert_eq(sim.phase, phase_before, "Previewing does not change the phase")
	assert_eq(
		int(sim.run_state.calendar.get("prompt", 0)), prompt_before,
		"And does not spend a prompt"
	)
	assert_eq(
		sim.effect_resolver.get_trace().size(), live_before,
		"The live resolver trace is untouched"
	)
	sim.free()


func _test_warm_cache_is_a_named_beat() -> void:
	var preview: Dictionary = _burn(["op.token_cache", "op.foundation_model"], 9101)
	var beats: Array = BurnSpectacle.compile(
		preview, Array(preview.get("trace", []))
	)
	assert_true(_beats_of(BurnSpectacle.KIND_COMBO, beats).size() > 0, "Warm Cache produces a combo beat")
	assert_true(
		"WARM CACHE" in _labels(beats),
		"And the beat is named after the authored combo"
	)


func _test_ordinary_stages_are_faster_than_the_old_crawl() -> void:
	var preview: Dictionary = _burn(["op.prompt", "op.cheap_model"], 9102)
	var beats: Array = BurnSpectacle.compile(preview, [])
	var stages: int = Array(preview.get("stages", [])).size()
	assert_true(stages >= 2, "The starter pair still has two stages")
	assert_true(
		BurnSpectacle.total_duration_ms(beats) < stages * 900,
		"Spectacle time is shorter than the old %.1fs-per-stage crawl" % 0.9
	)


func _test_duration_follows_capped_holds() -> void:
	var preview: Dictionary = _burn(
		["op.prompt", "op.cheap_model", "op.premium_model", "op.foundation_model"], 9104
	)
	var beats: Array = BurnSpectacle.compile(preview, [])
	assert_true(not beats.is_empty(), "A long pipeline still compiles beats")
	var from_holds: int = 0
	for beat in beats:
		if beat is Dictionary:
			from_holds += int(round(float(beat.get("hold", 0.0)) * 1000.0))
	assert_eq(
		BurnSpectacle.total_duration_ms(beats), from_holds,
		"Duration is the capped holds, not the original duration_ms"
	)
	assert_true(
		BurnSpectacle.total_duration_ms(beats) <= int(round(BurnSpectacle.MAX_SECONDS * 1000.0)) + 1,
		"A long pipeline stays inside the spectacle cap"
	)


func _test_spectacle_flag_disables_preview_beats() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(9105)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(offers.size() > 0, "A run opens with work to preview")
	sim.accept_job(str(Dictionary(offers[0]).get("id", "")))
	sim.start_work()
	FeatureFlags.set_enabled("burn_spectacle_enabled", false)
	var preview: Dictionary = sim.preview_burn()
	FeatureFlags.reload()
	assert_true(preview.get("ok", false), "The board can still preview a burn")
	assert_eq(
		Array(preview.get("spectacle", [])).size(), 0,
		"Turning the flag off strips the spectacle log"
	)
	sim.free()


func _test_a_repeat_is_its_own_beat() -> void:
	var preview: Dictionary = _burn(["op.prompt", "op.fractal_split"], 9103)
	var beats: Array = BurnSpectacle.compile(preview, [])
	var forks: Array = _beats_of(BurnSpectacle.KIND_FORK, beats)
	assert_true(
		forks.size() > 0,
		"A recursive fork is printed as its own beat, not folded into the stage line"
	)
	var repeat: Dictionary = forks[0]
	assert_true(int(repeat.get("repeat_count", 0)) > 0, "The beat carries its repeat count")
	assert_eq(
		str(repeat.get("label", "")),
		"AGAIN! ×%d" % int(repeat.get("repeat_count", 0)),
		"The player sees exactly how many times it ran again"
	)
	assert_true(repeat.has("multiplier_before"), "The beat carries the incoming multiplier")
	assert_true(repeat.has("multiplier_after"), "The beat carries the outgoing multiplier")
	assert_true(repeat.has("tokens_before"), "The beat carries the incoming token total")
	assert_true(float(repeat.get("tokens_added", -1.0)) >= 0.0, "The beat carries a nonnegative token gain")
	assert_almost_eq(
		float(repeat.get("multiplier_after", 0.0)),
		float(repeat.get("progress_mult", 0.0)),
		0.0001,
		"The compatibility multiplier still names the outgoing value"
	)


func _test_scope_consequence_explains_backward_progress() -> void:
	var before := {
		"requirement": 100.0,
		"remaining": 60.0,
		"known_bugs": 0,
		"hidden_bugs": 0,
		"prompts": 6,
	}
	var after := {
		"requirement": 110.0,
		"remaining": 70.0,
		"known_bugs": 0,
		"hidden_bugs": 0,
		"prompts": 6,
	}
	var consequences: Array = BurnSpectacle.compile_consequences(before, after)
	assert_eq(consequences.size(), 1, "Scope growth produces one focused explanation")
	var scope: Dictionary = consequences[0]
	assert_eq(str(scope.get("kind", "")), BurnSpectacle.CONSEQUENCE_SCOPE, "It is a scope event")
	assert_almost_eq(float(scope.get("amount", 0.0)), 10.0, 0.001, "The added work is named")
	assert_almost_eq(
		float(scope.get("completed_before", 0.0)),
		float(scope.get("completed_after", 0.0)),
		0.001,
		"Completed tokens are preserved"
	)
	assert_true(
		float(scope.get("progress_after", 1.0)) < float(scope.get("progress_before", 0.0)),
		"The lower percentage is explicitly attributable to the larger contract"
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


func _test_clearing_the_bar_is_a_loud_beat() -> void:
	var burn: Dictionary = _burn(["op.prompt", "op.unit_tests"], 9201)
	burn["job_quality"] = 58.0
	burn["job_quality_threshold"] = 60.0
	burn["quality"] = 12.0
	burn["job_known_bugs"] = 0
	burn["job_hidden_bugs"] = 0
	var beats: Array = BurnSpectacle.compile(burn, [])
	assert_true(
		_beats_of(BurnSpectacle.KIND_QUALITY_GATE, beats).size() > 0,
		"Crossing the client bar is a spectacle beat"
	)


func _test_rising_bug_risk_is_a_loud_beat() -> void:
	var burn: Dictionary = _burn(["op.prompt", "op.cheap_model"], 9202)
	burn["job_quality"] = 80.0
	burn["job_quality_threshold"] = 60.0
	burn["job_known_bugs"] = 0
	burn["job_hidden_bugs"] = 0
	burn["hidden_bugs"] = 2
	burn["ok"] = true
	var beats: Array = BurnSpectacle.compile(burn, [])
	assert_true(
		_beats_of(BurnSpectacle.KIND_BUG_RISK, beats).size() > 0,
		"A jump to high ship risk is printed"
	)
