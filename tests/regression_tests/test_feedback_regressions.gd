extends TestCase


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_offer_fit_uses_one_complete_workflow()
	_test_gold_master_counts_as_testing()


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
