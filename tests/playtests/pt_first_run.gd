extends PlaytestCase

## One month through the real shell: take the first offer, burn it, and walk
## the debrief → bills → angels chain by each overlay's own footer.
##
## Those overlays set dismiss_on_scrim false, so a click on the glass does
## nothing. The bug this guards is a player stuck on a report they cannot
## dismiss. It also leaves the desk after settlement and comes back repeatedly:
## web used to blank the canvas when the settled desk render tree was destroyed.


func play(harness: UiHarness) -> void:
	await harness.boot(7)
	var driver: UiDriver = harness.driver

	driver.audit_screen("desk", "desk")
	var original_desk: Node = harness.current_scene()

	await accept_first_job(harness)
	var queued: Array = Simulation.run_state.business.get("job_queue", [])
	assert_true(not queued.is_empty(), "ACCEPT put a contract on the slate")

	await burn_until_session_over(harness)
	# The point of the persona: each report has to be dismissed by its own
	# footer row, in the order main.gd promises.
	await walk_round_flow(harness)

	assert_true(
		Simulation.phase == Simulation.Phase.ROUND_PREP
		or Simulation.phase == Simulation.Phase.RUN_END,
		"The first month closed into prep or the run ended"
	)
	if Simulation.phase == Simulation.Phase.ROUND_PREP:
		driver.audit_screen("desk", "desk")
		# Regression for the web-only blank canvas: the first navigation after a
		# settled round must not destroy the desk, and repeated route changes must
		# keep producing a visible current screen.
		for trip in 5:
			await harness.goto_route("jobs")
			var jobs: Node = harness.current_scene()
			assert_true(jobs != null, "Post-round Jobs route mounted on trip %d" % trip)
			assert_true(
				jobs is CanvasItem and (jobs as CanvasItem).is_visible_in_tree(),
				"Post-round Jobs route is visible on trip %d" % trip
			)
			driver.audit_screen("jobs", "jobs")
			await harness.go_desk()
			assert_true(
				harness.current_scene() == original_desk,
				"Returning from Jobs reuses the live desk instead of destroying it"
			)
			assert_true(
				original_desk is CanvasItem and (original_desk as CanvasItem).is_visible_in_tree(),
				"Cached desk is visible again after trip %d" % trip
			)
			driver.audit_screen("desk", "desk")
