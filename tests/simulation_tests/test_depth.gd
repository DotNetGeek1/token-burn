extends TestCase

## Wave 4.B: beating the moon unlocks a voluntary Deep Burn ladder. No new room.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_only_the_last_chapter_can_begin()
	_test_picking_an_affix_stacks()
	_test_jobs_grow_by_the_depth_multiplier()
	_test_scoreboard_names_depth()


func _test_only_the_last_chapter_can_begin() -> void:
	var depth := DepthSystem.new()
	var bedroom := RunState.new()
	bedroom.build["dwelling"] = "bedroom"
	assert_false(depth.can_begin(bedroom), "The bedroom cannot open Deep Burn")
	var moon := RunState.new()
	moon.build["dwelling"] = "moon_facility"
	assert_true(depth.can_begin(moon), "The moon can")


func _test_picking_an_affix_stacks() -> void:
	var depth := DepthSystem.new()
	var state := RunState.new()
	state.build["dwelling"] = "moon_facility"
	var picks: Array = depth.offer_picks(state, DeterministicRng.new(9701), ContentDatabase)
	assert_eq(picks.size(), 3, "Deep Burn offers three affixes")
	var first_id: String = str(Dictionary(picks[0]).get("id", ""))
	assert_true(depth.choose_affix(state, first_id, ContentDatabase), "The first pick lands")
	assert_eq(int(state.depth.get("level", 0)), 1, "Depth advances to 1")
	assert_true(first_id in Array(state.depth.get("affixes", [])), "The affix is recorded")
	assert_true(
		float(state.depth.get("requirement_mult", 1.0)) > 1.0,
		"The next workload is larger"
	)
	assert_eq(int(state.statistics.get("depth_reached", 0)), 1, "Statistics remember the depth")
	if first_id == "depth.thin_cooling":
		assert_true(
			_has_status(state, "status.depth.thin_cooling"),
			"Thin Cooling hangs a status on the build"
		)


func _test_jobs_grow_by_the_depth_multiplier() -> void:
	var job_system := JobSystem.new()
	var job_def: JobDefinition = ContentDatabase.get_job("job.product_descriptions")
	var plain := RunState.new()
	var deep := RunState.new()
	deep.depth["requirement_mult"] = 3.0
	var before: Dictionary = job_system._scale_job(job_def, 1, ContentDatabase, {}, plain)
	var after: Dictionary = job_system._scale_job(job_def, 1, ContentDatabase, {}, deep)
	assert_almost_eq(
		float(after.get("token_requirement", 0.0)),
		float(before.get("token_requirement", 0.0)) * 3.0,
		1.0,
		"Depth multiplies the authored requirement rather than live-scaling the rig"
	)


func _test_scoreboard_names_depth() -> void:
	var state := RunState.new()
	state.statistics["lifetime_tokens"] = 1000.0
	state.statistics["depth_reached"] = 2
	state.depth["score_mult"] = 3.0
	var score: Dictionary = RunScore.compute(state, ContentDatabase)
	assert_eq(int(score.get("depth_reached", 0)), 2, "Depth reached is scored")
	assert_eq(int(score.get("depth_score", 0)), 2000, "Score mult is applied as extra score")
	var labels: Array = []
	for row in RunScore.rows(score):
		labels.append(str(row.get("label", "")))
	assert_true("Deep Burn depth" in labels, "The debrief names the depth")


func _has_status(state: RunState, status_id: String) -> bool:
	for status in Array(state.build.get("status_effects", [])):
		if status is Dictionary and str(status.get("id", "")) == status_id:
			return true
	return false
