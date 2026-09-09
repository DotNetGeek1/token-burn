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
	_test_stage_beats_show_combined_output()
	_test_committed_mastery_compiles_gain_share_and_loss()
	_test_beats_chain_without_gaps()
	_test_first_beat_starts_from_the_workflow_base()
	_test_a_falling_stage_is_marked_as_a_fall()
	_test_unmet_demand_drop_is_named_before_shipped()
	_test_met_demand_bonus_is_named()
	_test_closing_synergy_carries_its_own_jump()
	_test_again_owns_the_repeat_jump()
	_test_memoised_replays_match_the_walked_tree()


## A stage that runs the stage above it N times walks one replay tree, not N:
## the compile memoises the tree per (prior, strength) and folds it N times.
## The beats must come out bit-identical to walking the tree every time.
func _test_memoised_replays_match_the_walked_tree() -> void:
	var burn: Dictionary = _nested_repeat_fixture()
	BurnSpectacle.replay_walks = 0
	var beats: Array = BurnSpectacle.compile(burn, [])
	var walks: int = BurnSpectacle.replay_walks
	_assert_chained(beats, "nested repeat fixture")
	var forks: Array = _beats_of(BurnSpectacle.KIND_FORK, beats)
	assert_eq(forks.size(), 3, "Three forked stages compile to three AGAIN! beats")
	assert_eq(walks, 3, "Each forked stage walks its replay tree once, whatever its repeat count (got %d)" % walks)

	# The reference: the unmemoised loop, one walk per fork, multiplied in the
	# same order the compile folds them.
	var stages: Array = burn["stages"]
	var priors: Array = []
	var fork_index: int = 0
	for stage in stages:
		var count: int = int(stage.get("repeat_count", 0))
		if count > 0 and float(stage.get("repeated_previous", 0.0)) > 0.0 and not priors.is_empty():
			var strength: float = (
				float(stage.get("repeated_previous", 0.0))
				* float(stage.get("repeat_strength", 1.0))
				* float(stage.get("multiplier", 1.0))
			)
			var expected: float = 1.0
			for _fork in range(count):
				expected *= BurnSpectacle._replay_prior_ratio(priors, priors.size() - 1, strength)
			var fork: Dictionary = forks[fork_index]
			fork_index += 1
			# The compile lands AGAIN! on `own_after * ratio`; the same product
			# from the same operands must give the same bits.
			assert_eq(
				float(fork.get("multiplier_after", 0.0)),
				float(fork.get("multiplier_before", 0.0)) * expected,
				"AGAIN! ×%d on %s lands exactly where the walked tree puts it" % [count, str(stage.get("name", ""))]
			)
			assert_almost_eq(
				float(fork.get("ratio", 0.0)), expected, 1.0e-9,
				"And carries the walked ratio"
			)
			assert_eq(int(fork.get("repeat_count", 0)), count, "And names its repeat count")
		priors.append(stage)
	var again: Array = BurnSpectacle.compile(burn, [])
	assert_eq(again.size(), beats.size(), "A second compile is the same length")
	for i in range(beats.size()):
		assert_eq(
			float(Dictionary(again[i]).get("multiplier_after", -1.0)),
			float(Dictionary(beats[i]).get("multiplier_after", -2.0)),
			"Beat %d compiles to the same multiplier twice" % i
		)
	assert_true(float(forks[2].get("ratio", 0.0)) > 1.0, "The deepest fork still moves the drum")


## Six stages, three of them repeaters stacked so each replay tree nests the
## one below it: a fixture in the shape `resolve_burn` writes, not a real burn,
## so the counts are large enough to make the memo matter. The repeaters also
## cascade, which is the path where the compile has to reconstruct the fork's
## share of the jump rather than land it on the snapshot.
func _nested_repeat_fixture() -> Dictionary:
	var stages: Array = []
	var running: float = 1.0
	var specs := [
		{"name": "Prompt", "id": "op.prompt", "progress": 1.2, "repeat": 0.0, "count": 0},
		{"name": "Cheap Model", "id": "op.cheap_model", "progress": 1.8, "repeat": 0.0, "count": 0},
		{"name": "Echo", "id": "op.echo_chamber", "progress": 1.0, "repeat": 0.4, "count": 3},
		{"name": "Fractal", "id": "op.fractal_split", "progress": 0.85, "repeat": 0.5, "count": 4},
		{"name": "Overclock", "id": "op.overclock", "progress": 1.5, "repeat": 0.0, "count": 0},
		{"name": "Loop", "id": "op.autonomous_loop", "progress": 1.0, "repeat": 1.0, "count": 5},
	]
	for position in range(specs.size()):
		var spec: Dictionary = specs[position]
		var before: float = running
		var fields := {"progress_mult": float(spec["progress"]), "token_mult": 1.0}
		running *= float(spec["progress"])
		var count: int = int(spec["count"])
		var repeat: float = float(spec["repeat"])
		var forked: bool = repeat > 0.0 and count > 0 and position > 0
		if forked:
			var strength: float = repeat
			for _fork in range(count):
				running *= BurnSpectacle._replay_prior_ratio(stages, stages.size() - 1, strength)
			# The cascade's own share of the jump, on top of the replays.
			running *= 1.1
		stages.append({
			"name": spec["name"],
			"module_id": spec["id"],
			"slot_index": position,
			"position": position,
			"stage": fields,
			"multiplier": 1.0,
			"repeated_previous": repeat,
			"repeat_strength": 1.0,
			"repeat_count": count,
			"cascaded": forked,
			"cascade_depth": 1 if forked else 0,
			"dropped": false,
			"combos": [],
			"before": {"output_mult": before, "progress_mult": before, "token_mult": 1.0},
			"after": {"output_mult": running, "progress_mult": running, "token_mult": 1.0, "heat": 0.0},
		})
	return {
		"ok": true,
		"base_tokens": 1000.0,
		"stages": stages,
		"output_mult": running,
		"progress_mult": running,
		"token_mult": 1.0,
		"progress_tokens": 1000.0 * running,
		"demands": [],
	}


## The repeat's share of a stage's jump belongs to AGAIN!, not to the beat
## before it, so the drum is seen to move when the repeat fires.
func _test_again_owns_the_repeat_jump() -> void:
	var echo: Dictionary = _burn(["op.cheap_model", "op.echo_chamber"], 9309)
	var beats: Array = BurnSpectacle.compile(echo, [])
	var forks: Array = _beats_of(BurnSpectacle.KIND_FORK, beats)
	assert_eq(forks.size(), 1, "Echo Chamber forks once")
	var fork: Dictionary = forks[0]
	assert_almost_eq(float(fork.get("multiplier_before", 0.0)), 1.8, 0.001, "AGAIN! starts on Cheap Model's ×1.80")
	assert_almost_eq(float(fork.get("multiplier_after", 0.0)), 2.376, 0.001, "And climbs by the 40%% echo of it")
	assert_false(bool(fork.get("falls", true)), "Which is not a fall")
	var echo_stage_beats: int = 0
	for beat in _beats_of(BurnSpectacle.KIND_STAGE, beats):
		if str(Dictionary(beat).get("module_id", "")) == "op.echo_chamber":
			echo_stage_beats += 1
	assert_eq(echo_stage_beats, 0, "A repeater whose own fold does nothing is named by AGAIN! alone")

	var split: Dictionary = _burn(["op.prompt", "op.fractal_split"], 9310)
	var split_beats: Array = BurnSpectacle.compile(split, [])
	_assert_chained(split_beats, "fractal split")
	var split_stage: Dictionary = {}
	for beat in _beats_of(BurnSpectacle.KIND_STAGE, split_beats):
		if str(Dictionary(beat).get("module_id", "")) == "op.fractal_split":
			split_stage = beat
	assert_false(split_stage.is_empty(), "Fractal Split's own ×0.85 is its own beat")
	assert_true(bool(split_stage.get("falls", false)), "Marked as the fall it is")
	assert_almost_eq(float(split_stage.get("ratio", 0.0)), 0.85, 0.001, "By its authored ratio")
	var split_fork: Dictionary = _beats_of(BurnSpectacle.KIND_FORK, split_beats)[0]
	assert_true(
		float(split_fork.get("multiplier_after", 0.0)) > float(split_fork.get("multiplier_before", 1.0e9)),
		"And AGAIN! ×2 then climbs"
	)


## Every beat must pick up the multiplier exactly where the previous one left
## it. A gap is a drum that jumps (or drops) with nothing on the feed to say why.
func _assert_chained(beats: Array, context: String) -> void:
	assert_true(beats.size() > 0, "%s: compiles beats" % context)
	for i in range(1, beats.size()):
		var previous: Dictionary = beats[i - 1]
		var current: Dictionary = beats[i]
		assert_almost_eq(
			float(current.get("multiplier_before", -1.0)),
			float(previous.get("multiplier_after", -2.0)),
			0.0005,
			"%s: beat %d (%s) starts where %s ended" % [
				context, i, str(current.get("label", "")), str(previous.get("label", ""))
			]
		)
		var falls: bool = (
			float(current.get("multiplier_after", 0.0))
			< float(current.get("multiplier_before", 0.0)) - 0.0005
		)
		assert_eq(
			bool(current.get("falls", false)), falls,
			"%s: beat %d (%s) flags its fall honestly" % [context, i, str(current.get("label", ""))]
		)


func _test_beats_chain_without_gaps() -> void:
	var pipelines := [
		["op.prompt", "op.cheap_model"],
		["op.cheap_model", "op.echo_chamber"],
		["op.prompt", "op.fractal_split"],
		["op.prompt", "op.cheap_model", "op.unit_tests"],
		["op.overclock", "op.rubber_duck", "op.token_cache"],
	]
	for pipe in pipelines:
		var burn: Dictionary = _burn(pipe, 9301)
		_assert_chained(BurnSpectacle.compile(burn, Array(burn.get("trace", []))), str(pipe))
	var demanding: Dictionary = _burn(
		["op.prompt", "op.cheap_model", "op.unit_tests"], 9302,
		["demand.throughput", "demand.cooling"]
	)
	var beats: Array = BurnSpectacle.compile(demanding, Array(demanding.get("trace", [])))
	_assert_chained(beats, "unmet demands")
	var last: Dictionary = beats[beats.size() - 1]
	assert_almost_eq(
		float(last.get("multiplier_after", 0.0)),
		float(demanding.get("output_mult", -1.0)),
		0.0005,
		"The chain ends on the burn's real output multiplier"
	)


func _test_first_beat_starts_from_the_workflow_base() -> void:
	var plain: Dictionary = _burn(["op.prompt", "op.cheap_model"], 9303)
	var beats: Array = BurnSpectacle.compile(plain, [])
	assert_almost_eq(
		float(Dictionary(beats[0]).get("multiplier_before", 0.0)), 1.0, 0.0005,
		"An untrained workflow's first beat starts the drum at ×1.00"
	)
	assert_true(
		float(Dictionary(beats[0]).get("multiplier_before", 0.0))
		< float(plain.get("output_mult", 0.0)),
		"So the drum climbs from the base rather than falling from the projected total"
	)
	var trained: Dictionary = _burn(["op.prompt", "op.cheap_model"], 9303, [], 1.3)
	var trained_beats: Array = BurnSpectacle.compile(trained, [])
	assert_almost_eq(
		float(Dictionary(trained_beats[0]).get("multiplier_before", 0.0)), 1.3, 0.0005,
		"A trained workflow's first beat starts from its earned OUTPUT multiplier"
	)


func _test_a_falling_stage_is_marked_as_a_fall() -> void:
	var burn: Dictionary = _burn(["op.prompt", "op.cheap_model", "op.unit_tests"], 9304)
	var beats: Array = BurnSpectacle.compile(burn, Array(burn.get("trace", [])))
	var falling: Array = []
	for beat in beats:
		if bool(Dictionary(beat).get("falls", false)):
			falling.append(beat)
	assert_eq(falling.size(), 1, "Unit Tests' ×0.85 output cost is the one falling beat")
	var fall: Dictionary = falling[0]
	assert_eq(str(fall.get("module_id", "")), "op.unit_tests", "And it is pinned on the stage that cost it")
	assert_almost_eq(float(fall.get("ratio", 0.0)), 0.85, 0.001, "The beat carries the ratio the drum fell by")


func _test_unmet_demand_drop_is_named_before_shipped() -> void:
	var burn: Dictionary = _burn(
		["op.prompt", "op.cheap_model"], 9305, ["demand.throughput", "demand.cooling"]
	)
	var beats: Array = BurnSpectacle.compile(burn, [])
	var demands: Array = _beats_of(BurnSpectacle.KIND_DEMAND, beats)
	assert_eq(demands.size(), 2, "Each ignored demand that taxes output is its own beat")
	var scale: Dictionary = demands[0]
	assert_true("ABSURD SCALE" in str(scale.get("label", "")), "Named for the contract's demand")
	assert_true("IGNORED" in str(scale.get("label", "")), "And says it was ignored")
	assert_true(bool(scale.get("falls", false)), "Marked as a fall")
	assert_almost_eq(float(scale.get("ratio", 0.0)), 0.6, 0.001, "Carrying the ×0.60 it costs")
	assert_true(bool(scale.get("loud", false)), "Loud enough to read")
	var stages: Array = _beats_of(BurnSpectacle.KIND_STAGE, beats)
	var last_stage: Dictionary = stages[stages.size() - 1]
	assert_almost_eq(
		float(scale.get("multiplier_before", 0.0)),
		float(last_stage.get("multiplier_after", -1.0)),
		0.0005,
		"The drop starts from where the last stage left the drum"
	)
	var final: Array = _beats_of(BurnSpectacle.KIND_FINAL, beats)
	assert_eq(final.size(), 1, "One SHIPPED beat")
	assert_almost_eq(
		float(Dictionary(final[0]).get("multiplier_before", 0.0)),
		float(Dictionary(final[0]).get("multiplier_after", -1.0)),
		0.0005,
		"SHIPPED no longer hides the drop inside itself"
	)
	assert_true(
		int(beats.find(scale)) < int(beats.find(final[0])),
		"The demand beat plays before SHIPPED"
	)


func _test_met_demand_bonus_is_named() -> void:
	var burn: Dictionary = _burn(["op.overclock", "op.cheap_model"], 9306, ["demand.throughput"])
	var beats: Array = BurnSpectacle.compile(burn, [])
	var demands: Array = _beats_of(BurnSpectacle.KIND_DEMAND, beats)
	assert_eq(demands.size(), 1, "A met demand that pays output is a beat too")
	assert_true("MET" in str(Dictionary(demands[0]).get("label", "")), "Named as met")
	assert_false(bool(Dictionary(demands[0]).get("falls", true)), "And it climbs")
	assert_almost_eq(float(Dictionary(demands[0]).get("ratio", 0.0)), 1.1, 0.001, "By its ×1.10")
	var quiet: Dictionary = _burn(["op.prompt", "op.unit_tests"], 9307, ["demand.testing"])
	assert_eq(
		_beats_of(BurnSpectacle.KIND_DEMAND, BurnSpectacle.compile(quiet, [])).size(), 0,
		"A demand that only moves quality does not print a multiplier beat"
	)


func _test_closing_synergy_carries_its_own_jump() -> void:
	var build := CanonicalTest.Build.new(
		["op.prompt", "op.stack_overflow"],
		["perk.vibe_check", "perk.bug_alchemy"],
		9308
	)
	var burn: Dictionary = build.burn()
	var beats: Array = BurnSpectacle.compile(burn, build.resolver.get_trace())
	_assert_chained(beats, "vibe coding")
	var synergies: Array = _beats_of(BurnSpectacle.KIND_SYNERGY, beats)
	assert_true(synergies.size() > 0, "Vibe Coding is a beat")
	assert_true(
		float(Dictionary(synergies[0]).get("multiplier_after", 0.0))
		> float(Dictionary(synergies[0]).get("multiplier_before", 1.0e9)),
		"And the drum climbs on it rather than on SHIPPED"
	)


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


func _test_stage_beats_show_combined_output() -> void:
	var harness := BurnBoardTest.Harness.new(9901)
	harness.pipeline(["op.overclock"])
	var burn: Dictionary = harness.burn()
	var beats: Array = BurnSpectacle.compile(burn, harness.resolver.get_trace())
	var stages: Array = _beats_of(BurnSpectacle.KIND_STAGE, beats)
	assert_true(not stages.is_empty(), "Overclock produces a stage beat")
	assert_almost_eq(
		float(Dictionary(stages[0]).get("multiplier_after", 0.0)),
		2.0,
		0.001,
		"Stage spectacle shows token_mult × progress_mult as combined OUTPUT"
	)


func _test_committed_mastery_compiles_gain_share_and_loss() -> void:
	var burn := {
		"ok": true,
		"output_mult": 1.4,
		"progress_tokens": 100.0,
		"mastery": {
			"applied": true,
			"workflow_id": "workflow.1",
			"workflow_name": "House Style",
			"output_gain": 0.08,
			"quality_gain": 0.0,
			"thermal_gain": 0.0,
			"propagated": true,
			"stripped": true,
		},
	}
	var beats: Array = BurnSpectacle.compile_mastery(burn)
	assert_eq(beats.size(), 1, "Committed mastery produces one closing beat")
	var label: String = str(Dictionary(beats[0]).get("label", ""))
	assert_true("OUT+0.08" in label, "The mastery gain is named")
	assert_true("SHARED" in label, "Propagation is named")
	assert_true("STACK LOST" in label, "Golden Path loss is named")


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
	assert_true(
		"NOTHING ABOVE TO REPEAT" in str(stages[0].get("label", "")),
		"But it says why the repeat never started"
	)


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


func _burn(
	module_ids: Array, seed_value: int, demands: Array = [], trained_output: float = 1.0
) -> Dictionary:
	var board := BoardSystem.new()
	var resolver := EffectResolver.new()
	var state := RunState.new()
	board.ensure_board(state, ContentDatabase)
	state.build["modules"] = module_ids.duplicate()
	var slots: Array = board.slots(state)
	for i in range(slots.size()):
		slots[i] = str(module_ids[i]) if i < module_ids.size() else ""
	if trained_output != 1.0:
		var workflows: Array = Array(state.build.get("workflows", []))
		if not workflows.is_empty():
			Dictionary(workflows[0])["output_mult"] = trained_output
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
		"demands": demands.duplicate(),
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
