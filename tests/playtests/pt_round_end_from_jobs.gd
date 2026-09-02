extends PlaytestCase

## Round-end while standing in Jobs, then walk back to Jobs. The blank-screen
## bug was a dropped goto during the fade plus a stuck router curtain.


func play(harness: UiHarness) -> void:
	await harness.boot(19)
	await accept_first_job(harness)
	if Simulation.can_start_work():
		Simulation.start_work()
	await harness.goto_route("jobs")
	assert_true(SceneRouter.visible_route_ok(), "Jobs is visible before the session ends")
	# Finish the session while Jobs is the current route so the router must
	# walk home mid-venue, then let the player go back.
	if Simulation.phase == Simulation.Phase.IN_ROUND or Simulation.is_work_running():
		Simulation.auto_arrange_board()
		var safety: int = 0
		while Simulation.phase == Simulation.Phase.IN_ROUND and safety < 200:
			safety += 1
			if JobSystem.is_ready(Simulation.focused_job()):
				if Simulation.ship_focused_job():
					continue
			if not bool(Simulation.burn_batch().get("ok", false)):
				break
	else:
		await burn_until_session_over(harness)
	if SceneRouter.current != SceneRouter.DESK:
		await harness.go_desk()
	else:
		await harness.settle()
	await walk_round_flow(harness)
	assert_true(
		SceneRouter.visible_route_ok(),
		"Desk is visible after debrief/bills/angels"
	)
	await harness.goto_route("jobs")
	assert_true(harness.current_scene() != null, "Jobs remounted after round-end")
	assert_true(
		SceneRouter.visible_route_ok(),
		"Jobs is a visible venue after round-end, not a blank shell"
	)
	harness.driver.audit_screen("jobs-post-round", "jobs")
	await harness.go_desk()
	assert_true(SceneRouter.visible_route_ok(), "Desk returns visible after Jobs")
