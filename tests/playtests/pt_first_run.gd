extends PlaytestCase

## One month through the real shell: take the first offer, burn it, and walk
## the debrief → bills → angels chain by each overlay's own footer.
##
## Those overlays set dismiss_on_scrim false, so a click on the glass does
## nothing. The bug this guards is a player stuck on a report they cannot
## dismiss. Winning the campaign is a different persona; this one stops
## once the first month has closed.


func play(harness: UiHarness) -> void:
	await harness.boot(7)
	var driver: UiDriver = harness.driver

	driver.audit_screen("desk", "desk")

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
