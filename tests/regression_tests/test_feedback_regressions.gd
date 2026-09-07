extends TestCase


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_offer_fit_uses_one_complete_workflow()
	_test_gold_master_counts_as_testing()
	_test_repeat_burns_start_the_drum_from_the_base()


## Player report: "the multipliers are not starting on repeat, and sometimes the
## multiplier goes down." Between burns the drum rests on the projected total,
## so a second burn used to begin by tweening *down* to the first stage and
## every drop inside the batch went unexplained. Every burn's spectacle has to
## start from the workflow's base and account for each step of the drum.
func _test_repeat_burns_start_the_drum_from_the_base() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(4242)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(offers.size() > 0, "A run opens with work")
	sim.accept_job(str(Dictionary(offers[0]).get("id", "")))
	sim.start_work()
	for prompt in range(3):
		var preview: Dictionary = sim.preview_burn()
		assert_true(preview.get("ok", false), "Prompt %d previews" % prompt)
		var beats: Array = Array(preview.get("spectacle", []))
		assert_true(beats.size() >= 2, "Prompt %d has a spectacle" % prompt)
		var base: float = float(Dictionary(sim.active_workflow()).get("output_mult", 1.0))
		assert_almost_eq(
			float(Dictionary(beats[0]).get("multiplier_before", -1.0)), base, 0.0005,
			"Prompt %d: the drum starts from the workflow's own ×%.2f, not last burn's total" % [prompt, base]
		)
		assert_almost_eq(
			float(Dictionary(beats[beats.size() - 1]).get("multiplier_after", -1.0)),
			float(preview.get("output_mult", -2.0)),
			0.0005,
			"Prompt %d: and ends on the projected total" % prompt
		)
		for i in range(1, beats.size()):
			var previous: Dictionary = beats[i - 1]
			var current: Dictionary = beats[i]
			assert_almost_eq(
				float(current.get("multiplier_before", -1.0)),
				float(previous.get("multiplier_after", -2.0)),
				0.0005,
				"Prompt %d: %s picks up where %s left the drum" % [
					prompt, str(current.get("label", "")), str(previous.get("label", ""))
				]
			)
			if float(current.get("multiplier_after", 0.0)) < float(current.get("multiplier_before", 0.0)) - 0.0005:
				assert_true(
					bool(current.get("falls", false)),
					"Prompt %d: %s admits the drum fell" % [prompt, str(current.get("label", ""))]
				)
		var result: Dictionary = sim.burn_batch()
		assert_true(result.get("ok", false), "Prompt %d commits" % prompt)
	sim.free()


func _test_offer_fit_uses_one_complete_workflow() -> void:
	var state := RunState.new()
	state.build["workflows"] = [
		{"id": "workflow.1", "name": "Tests", "slots": ["op.unit_tests", ""]},
		{"id": "workflow.2", "name": "Craft", "slots": ["op.large_context", ""]},
	]
	var split_offer: Dictionary = {
		"id": "job.marketplace.test",
		"definition_id": "job.marketplace",
		"demands": ["demand.testing", "demand.craft"],
		"reward": 100.0,
	}
	var jobs := JobSystem.new()
	jobs._classify_offers([split_offer], state, ContentDatabase)
	assert_eq(
		int(split_offer.get("unmet_demands", -1)),
		1,
		"Two workflows that solve opposite halves still leave one demand unmet"
	)
	assert_eq(
		str(split_offer.get("fit", "")),
		"stretch",
		"The board does not advertise the split build as bread and butter"
	)

	state.build["workflows"] = [{
		"id": "workflow.1",
		"name": "Complete",
		"slots": ["op.unit_tests", "op.large_context"],
	}]
	var complete_offer: Dictionary = split_offer.duplicate(true)
	complete_offer["reward"] = 100.0
	jobs._classify_offers([complete_offer], state, ContentDatabase)
	assert_eq(
		int(complete_offer.get("unmet_demands", -1)),
		0,
		"One workflow containing both capabilities satisfies the same contract"
	)
	assert_eq(str(complete_offer.get("fit", "")), "bread_and_butter", "Its fit label agrees")


func _test_gold_master_counts_as_testing() -> void:
	var board := BoardSystem.new()
	var capabilities: Dictionary = board.pipeline_capabilities(["op.gold_master"])
	assert_true(
		bool(capabilities.get(BoardSystem.CAPABILITY_FIX_BUGS, false)),
		"Gold Master's hidden-bug fix is a testing capability"
	)
	var report: Array = board.demand_report(
		{"demands": ["demand.testing"]}, ["op.gold_master"]
	)
	assert_eq(report.size(), 1, "The Testing demand is recognised")
	assert_true(bool(report[0].get("met", false)), "Gold Master satisfies the Testing demand")
