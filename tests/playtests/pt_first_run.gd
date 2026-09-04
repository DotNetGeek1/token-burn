extends PlaytestCase

## One month through the real shell: take the first offer, burn it, and walk
## the debrief → bills → angels chain by each overlay's own footer.
##
## Those overlays set dismiss_on_scrim false, so a click on the glass does
## nothing. The bug this guards is a player stuck on a report they cannot
## dismiss. It also leaves the run tab after settlement and comes back
## repeatedly: web used to blank the canvas when the settled desk render tree
## was destroyed, and the cabinet must stay the one live instance throughout.


func play(harness: UiHarness) -> void:
	await harness.boot(7)
	var driver: UiDriver = harness.driver

	driver.audit_screen("desk", "desk")
	var original_desk: Node = harness.current_scene()

	await accept_first_job(harness)
	var queued: Array = Simulation.run_state.business.get("job_queue", [])
	assert_true(not queued.is_empty(), "ACCEPT put a contract on the slate")
	# ACCEPT moves the glass to the run tab; that must not also fire a burn.
	assert_false(Simulation.is_work_running(), "ACCEPT takes the contract without opening the round")

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
		# settled round must not destroy the shell, and repeated tab changes
		# must keep producing a visible screen on the same cabinet instance.
		var shell: Node = harness.current_scene()
		for trip in 5:
			if shell != null and shell.has_method("switch_tab"):
				shell.switch_tab("contracts")
				await harness.settle()
			var glass: Node = harness.current_scene()
			assert_true(glass != null, "Post-round contracts tab mounted on trip %d" % trip)
			assert_true(
				glass is CanvasItem and (glass as CanvasItem).is_visible_in_tree(),
				"Post-round contracts tab is visible on trip %d" % trip
			)
			assert_eq(str(shell.current_tab()), "contracts", "The contracts tab is the one on the glass on trip %d" % trip)
			driver.audit_screen("contracts", "desk")
			if shell != null and shell.has_method("switch_tab"):
				shell.switch_tab("run")
				await harness.settle()
			assert_true(
				harness.current_scene() == original_desk,
				"Coming back to the run tab reuses the live cabinet instead of destroying it"
			)
			assert_true(
				original_desk is CanvasItem and (original_desk as CanvasItem).is_visible_in_tree(),
				"The cabinet is visible again after trip %d" % trip
			)
			driver.audit_screen("desk", "desk")
