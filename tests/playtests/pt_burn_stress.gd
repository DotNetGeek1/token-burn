extends PlaytestCase

## A long burn through the cabinet, and what it costs the scene tree.
##
## Thirteen stages — two pages of the wide dock — with repeaters stacked so
## the replay trees nest, a cascader, and a legendary loop that does both. The
## batch plays through the real director onto the real instruments, and the
## instruments must not churn the tree beat by beat: the dock lights its way
## along without redrawing every bay, the feed prints on a fixed pool of
## labels, and the callouts stay inside their pool. The frame times and the
## node count are printed so a regression has a number to be measured against.

const SEED := 7301
## Two repeaters over a real stage (Echo runs Cheap Model, Fractal runs Echo,
## which runs Cheap Model again), a cascader, two more repeaters further down,
## and coolers between them so the batch runs hot but does not set the rig on
## fire. Thirteen so the wide dock's ten bays have to turn a page.
const PIPELINE: Array[String] = [
	"op.prompt",
	"op.cheap_model",
	"op.echo_chamber",
	"op.fractal_split",
	"op.liquid_cooling",
	"op.token_cache",
	"op.premium_model",
	"op.recursive_compiler",
	"op.reviewer_agent",
	"op.pair_programmer",
	"op.fan_wall",
	"op.unit_tests",
	"op.rubber_duck",
]
## The node count is allowed to move by this much across a burn: the callout
## pool fills on its first use, and a glyph or two may still be fading.
const NODE_DELTA_ALLOWANCE := 40
## The contract's requirement, so one batch never ships it.
const HUGE_CONTRACT := 1.0e15


func play(harness: UiHarness) -> void:
	await harness.boot(SEED)
	var shell: Node = harness.current_scene()
	assert_true(
		shell != null and shell.has_method("refresh_all") and shell.has_method("switch_tab"),
		"The cabinet shell is up"
	)
	if shell == null:
		return
	var dock: ModuleDock = _find_first(shell, func(node: Node) -> bool: return node is ModuleDock) as ModuleDock
	var feed: BurnFeed = _find_first(shell, func(node: Node) -> bool: return node is BurnFeed) as BurnFeed
	var director: BurnDirector = _find_first(shell, func(node: Node) -> bool: return node is BurnDirector) as BurnDirector
	var callouts: BurnCallouts = _find_first(shell, func(node: Node) -> bool: return node is BurnCallouts) as BurnCallouts
	var button: Control = _find_commit(shell)
	assert_true(dock != null, "The module dock is mounted")
	assert_true(feed != null, "The burn feed is mounted")
	assert_true(director != null, "The burn director is mounted")
	assert_true(button != null, "The commit button is mounted")
	if dock == null or feed == null or director == null or button == null:
		return

	_build_pipeline(shell)
	await harness.settle()
	var slots: Array = Simulation.board_slots()
	assert_true(slots.size() >= 12, "The pipeline has at least twelve stages (got %d)" % slots.size())
	assert_eq(slots.size(), PIPELINE.size(), "Every stage of the fixture is seated")
	var per_page: int = dock.bays_shown()
	var live: int = 0
	for bay in dock.bays():
		if not bay.covered:
			live += 1
	assert_eq(live, per_page, "The dock is full: every bay on the page is live")

	await _open_the_round(harness, shell)
	if not Simulation.can_burn():
		assert_true(false, "The round is open and the pipeline can burn")
		return
	var preview: Dictionary = Simulation.preview_burn()
	assert_true(bool(preview.get("ok", false)), "The pipeline previews a burn")
	var beats: Array = Array(preview.get("spectacle", []))
	var forks: int = 0
	var cascades: int = 0
	var deepest: int = 0
	for beat in beats:
		var kind: String = str(Dictionary(beat).get("kind", ""))
		if kind == BurnSpectacle.KIND_FORK:
			forks += 1
			deepest = maxi(deepest, int(Dictionary(beat).get("repeat_count", 0)))
		elif kind == BurnSpectacle.KIND_CASCADE:
			cascades += 1
	assert_true(forks >= 2, "The nested repeaters compile to AGAIN! beats (got %d)" % forks)
	print("    stress: %d beats, %d AGAIN! (deepest ×%d), %d cascade(s) over %d stages" % [
		beats.size(), forks, deepest, cascades, slots.size(),
	])
	var page_changes: int = _page_changes(beats, per_page, 0)

	# The instruments before the batch.
	shell.call("switch_tab", "run")
	shell.call("refresh_all")
	await harness.settle()
	var refresh_before: int = dock.refresh_count
	var nodes_before: int = harness.get_tree().get_node_count()
	assert_eq(feed.line_label_count(), BurnFeed.MAX_LINES, "The feed holds exactly MAX_LINES labels before the burn")
	assert_true(button.has_method("is_busy"), "The commit button reports busy")

	# Burn through the deck, and measure every frame until the machine is back.
	# The dock's redraws are read at the last stage the playback closes — the
	# lighting is over by then — and again when the director hands back the
	# machine, so a redraw the commit itself asks for is told apart from one
	# the lighting caused.
	var refresh_at_last_stage: Array[int] = [refresh_before]
	var refresh_at_finish: Array[int] = [refresh_before]
	director.stage_completed.connect(func(_stages: int) -> void: refresh_at_last_stage[0] = dock.refresh_count)
	director.burn_finished.connect(func(_ok: bool) -> void: refresh_at_finish[0] = dock.refresh_count)
	await harness.driver.press(button)
	var started: bool = await wait_until(harness, func() -> bool: return bool(button.call("is_busy")), 3000)
	assert_true(started, "Pressing BURN starts the batch")
	var frames: int = 0
	var worst_usec: int = 0
	var total_usec: int = 0
	var feed_steady: bool = true
	var callouts_bounded: bool = true
	var last: int = Time.get_ticks_usec()
	var deadline: int = Time.get_ticks_msec() + BURN_DEADLINE_MSEC
	while bool(button.call("is_busy")) and Time.get_ticks_msec() < deadline:
		await harness.get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		var frame: int = now - last
		last = now
		frames += 1
		total_usec += frame
		worst_usec = maxi(worst_usec, frame)
		if feed.line_label_count() != BurnFeed.MAX_LINES:
			feed_steady = false
		if callouts != null and (callouts.live_count() > BurnCallouts.MAX_LIVE or callouts.card_count() > BurnCallouts.MAX_LIVE):
			callouts_bounded = false
	assert_false(bool(button.call("is_busy")), "The burn plays out inside the deadline")
	await harness.settle()
	var refresh_delta: int = dock.refresh_count - refresh_before
	var nodes_after: int = harness.get_tree().get_node_count()
	var average_ms: float = (float(total_usec) / maxf(1.0, float(frames))) / 1000.0
	print("    stress: %d frames, max %.2f ms, avg %.2f ms; dock refreshes %d for %d page change(s); nodes %d -> %d (%+d)" % [
		frames, float(worst_usec) / 1000.0, average_ms, refresh_delta, page_changes,
		nodes_before, nodes_after, nodes_after - nodes_before,
	])

	var playback_delta: int = refresh_at_last_stage[0] - refresh_before
	var finish_delta: int = refresh_at_finish[0] - refresh_before
	print("    stress: dock refreshes %d through the stages, %d by the hand-back, %d in all" % [
		playback_delta, finish_delta, refresh_delta,
	])
	assert_true(frames > 0, "The batch took at least one frame to play")
	assert_true(
		playback_delta <= page_changes,
		"Lighting the way along the pipeline redraws the dock only when it turns the page (%d refreshes for %d page changes)" % [playback_delta, page_changes]
	)
	assert_true(
		refresh_delta <= page_changes + 1,
		"The whole burn redraws the dock at most once per page change plus the closing redraw (%d refreshes for %d page changes)" % [refresh_delta, page_changes]
	)
	assert_true(
		Simulation.is_work_running(),
		"The batch did not end the round (%s), so its redraws are the playback's own" % str(Simulation.run_state.flags.get("loss_reason", "shipped"))
	)
	assert_true(feed_steady, "The feed's line pool stays at MAX_LINES through every frame of the burn")
	assert_eq(feed.line_label_count(), BurnFeed.MAX_LINES, "The feed still holds exactly MAX_LINES labels after the burn")
	assert_true(callouts_bounded, "The callouts never hold more than MAX_LIVE cards")
	assert_true(
		absi(nodes_after - nodes_before) <= NODE_DELTA_ALLOWANCE,
		"The burn leaves the scene tree within %d nodes of where it found it (%+d)" % [NODE_DELTA_ALLOWANCE, nodes_after - nodes_before]
	)

	# A second burn on a warm cabinet: the pools are full, so nothing grows.
	if Simulation.can_burn() and not bool(button.call("is_busy")):
		var warm_before: int = harness.get_tree().get_node_count()
		var warm_refresh: int = dock.refresh_count
		await harness.driver.press(button)
		await wait_until(harness, func() -> bool: return bool(button.call("is_busy")), 3000)
		await wait_until(harness, func() -> bool: return not bool(button.call("is_busy")), BURN_DEADLINE_MSEC)
		await harness.settle()
		var warm_after: int = harness.get_tree().get_node_count()
		print("    stress: warm burn nodes %d -> %d (%+d), dock refreshes %d" % [
			warm_before, warm_after, warm_after - warm_before, dock.refresh_count - warm_refresh,
		])
		assert_true(
			warm_after <= warm_before + 8,
			"A second burn adds nothing lasting to the tree (%+d)" % (warm_after - warm_before)
		)
	await harness.settle()


# --- The fixture ---------------------------------------------------------------

## Seats the whole pipeline: a full backplane so the dock's page is all live
## bays, the modules granted, the layout written to the fixture's length. The
## occupied overflow past the backplane is kept by the board's normalisation.
func _build_pipeline(shell: Node) -> void:
	CabinetSystems.set_tier(Simulation.run_state, "backplane", CabinetSystems.max_tier())
	var owned: Array = Array(Simulation.run_state.build.get("modules", []))
	for module_id in PIPELINE:
		if not (module_id in owned):
			owned.append(module_id)
	Simulation.run_state.build["modules"] = owned
	var layout: Array = Simulation.board_slots()
	layout.resize(PIPELINE.size())
	for index in range(PIPELINE.size()):
		layout[index] = PIPELINE[index]
	Simulation.debug_invalidate_subscriptions()
	shell.call("refresh_all")


## Takes the first contract on the wire and opens the round, through the
## simulation: the burn itself is what goes through the glass.
func _open_the_round(harness: UiHarness, shell: Node) -> void:
	await dismiss_investor(harness)
	if not Simulation.can_start_work() and not Simulation.is_work_running():
		for job in Array(Simulation.run_state.business.get("job_offers", [])):
			if Simulation.accept_job(str(Dictionary(job).get("id", ""))):
				break
	if Simulation.can_start_work():
		Simulation.start_work()
	# A contract this pipeline cannot finish in one batch: the measurement is
	# the playback, not the paperwork a shipped contract redraws the glass for.
	var job: Dictionary = Simulation.focused_job()
	if not job.is_empty():
		job["token_requirement"] = HUGE_CONTRACT
		job["tokens_remaining"] = HUGE_CONTRACT
	shell.call("refresh_all")
	await harness.settle()


## How many times the lit bay crosses a page boundary as the beats play, from
## the page the dock is on when the batch starts.
func _page_changes(beats: Array, per_page: int, start_page: int) -> int:
	var page: int = start_page
	var changes: int = 0
	for beat in beats:
		var slot: int = int(Dictionary(beat).get("slot_index", -1))
		if slot < 0:
			continue
		var target: int = slot / per_page
		if target != page:
			page = target
			changes += 1
	return changes


# --- Locators ----------------------------------------------------------------

func _find_commit(root: Node) -> Control:
	return _find_first(root, func(node: Node) -> bool:
		return node is Button and node.has_method("set_action") and node.has_method("is_busy")
	) as Control


func _find_first(node: Node, predicate: Callable) -> Node:
	if node == null:
		return null
	if bool(predicate.call(node)):
		return node
	for child in node.get_children():
		var found: Node = _find_first(child, predicate)
		if found != null:
			return found
	return null
