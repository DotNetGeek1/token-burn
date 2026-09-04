extends PlaytestCase

## Round-end while the CONTRACTS tab is up, then go back to it. The
## blank-screen bug this descends from was a dropped route change during the
## fade plus a stuck router curtain; on the cabinet the equivalent failure is
## the round-end paperwork landing while another tab is on the glass and the
## shell coming back blank, or on the wrong tab, once it is dismissed.


func play(harness: UiHarness) -> void:
	await harness.boot(19)
	await accept_first_job(harness)
	if Simulation.can_start_work():
		Simulation.start_work()
	var shell: Node = harness.current_scene()
	assert_true(shell != null and shell.has_method("switch_tab"), "The cabinet is up")
	if shell == null:
		return
	shell.switch_tab("contracts")
	await harness.settle()
	assert_eq(str(shell.current_tab()), "contracts", "The contracts tab is up before the session ends")
	assert_true(SceneRouter.visible_route_ok(), "The cabinet is visible before the session ends")
	# Finish the session while the contracts tab is the one on the glass, so
	# the debrief has to land over a tab that is not the run.
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
	await harness.settle()
	await walk_round_flow(harness)
	assert_true(
		SceneRouter.visible_route_ok(),
		"The cabinet is visible after debrief/bills/angels"
	)
	assert_eq(SceneRouter.current, SceneRouter.DESK, "Round-end never leaves the cabinet route")
	shell.switch_tab("contracts")
	await harness.settle()
	assert_eq(str(shell.current_tab()), "contracts", "The contracts tab comes back after round-end")
	assert_true(
		SceneRouter.visible_route_ok(),
		"The contracts tab is a visible screen after round-end, not a blank shell"
	)
	harness.driver.audit_screen("contracts-post-round", "desk")
	shell.switch_tab("run")
	await harness.settle()
	assert_true(SceneRouter.visible_route_ok(), "The run tab returns visible after the contracts tab")
