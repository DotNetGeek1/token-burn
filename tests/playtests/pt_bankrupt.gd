extends PlaytestCase

## Refuses work until the bills bury the run. There is no skip-round button,
## so the persona ends each empty slate in the sim and lets rent land the
## way a player who sat on their hands would still be charged. The loss
## path has to reach TITLE SCREEN with every report overlay gone — a
## session_summary or run_end left standing over the title is a player
## stuck on a company that no longer exists.


const SEED := 3
const ROUND_CAP := 14


func play(harness: UiHarness) -> void:
	await harness.boot(SEED)
	var driver: UiDriver = harness.driver

	for _round in ROUND_CAP:
		if Simulation.phase == Simulation.Phase.RUN_END:
			break
		await dismiss_investor(harness)
		await harness.goto_tab("contracts")
		driver.audit_screen("contracts", "desk")
		assert_false(
			Simulation.run_state.has_queued_jobs(),
			"Refusing work left the slate empty"
		)
		assert_false(
			Simulation.run_state.has_pending_work(),
			"And nothing was already in flight"
		)
		Simulation.debug_end_round()
		# Bills and the verdict land over the run tab.
		await harness.goto_tab("run")
		await _dismiss_bills_and_decline_angels(harness)

	# Refusing work is the point of the loop. Eviction can take more rounds
	# than this cap if rent keeps clearing (passive income, a fat start).
	# The loss screen is what this persona then has to walk, so force it.
	if Simulation.phase != Simulation.Phase.RUN_END:
		Simulation.debug_end_run(false, "bills")
		await harness.go_desk()
	await ensure_run_end_overlay(harness)
	await _wait_for_run_end(harness)
	driver.assert_overlay_visible("run_end")
	if driver.command("TITLE SCREEN") != null:
		var title_row: Control = driver.command("TITLE SCREEN")
		if title_row is BaseButton and title_row.disabled:
			# Picks disable title; a loss should not have them. NEW RUN is
			# the other way off the report if title stayed grey.
			await driver.press_command("NEW RUN")
		else:
			await driver.press_command("TITLE SCREEN")
	else:
		await driver.press_command("NEW RUN")
	await _wait_for_title(harness)
	await dismiss_investor(harness)
	_assert_reports_cleared(harness)


func _dismiss_bills_and_decline_angels(harness: UiHarness) -> void:
	# A skip-round has no debrief. Taking an angel here would hand out cash
	# and delay the eviction this persona exists to reach.
	await _wait_for_overlay(harness)
	var deadline: int = Time.get_ticks_msec() + ROUND_FLOW_DEADLINE_MSEC
	while Time.get_ticks_msec() < deadline:
		await dismiss_investor(harness)
		if _overlay_up(harness, "month_statement"):
			await harness.driver.press_command("CONTINUE")
			continue
		if _overlay_up(harness, "session_summary"):
			await harness.driver.press_command("CONTINUE")
			continue
		if _overlay_up(harness, "angel_investors"):
			await harness.driver.press_command("TAKE NOTHING")
			continue
		if (
			Simulation.phase == Simulation.Phase.RUN_END
			or Simulation.phase == Simulation.Phase.ROUND_PREP
			or Simulation.phase == Simulation.Phase.IN_ROUND
		):
			return
		await harness.settle()


func _wait_for_run_end(harness: UiHarness) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		await dismiss_investor(harness)
		if _overlay_up(harness, "month_statement"):
			await harness.driver.press_command("CONTINUE")
			continue
		if _overlay_up(harness, "session_summary"):
			await harness.driver.press_command("CONTINUE")
			continue
		if _overlay_up(harness, "run_end"):
			return
		await harness.get_tree().process_frame
	harness.driver.assert_overlay_visible("run_end")


func _wait_for_title(harness: UiHarness) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if SceneRouter.current != SceneRouter.DESK:
			await harness.get_tree().process_frame
			continue
		if _title_visible(harness):
			return
		await harness.get_tree().process_frame


func _title_visible(harness: UiHarness) -> bool:
	if not harness.is_inside_tree():
		return false
	for node in harness.get_tree().get_nodes_in_group("title_screen"):
		if node is CanvasItem and node.is_visible_in_tree():
			return true
	return false


func _assert_reports_cleared(harness: UiHarness) -> void:
	for fragment in ["session_summary", "month_statement", "angel_investors", "run_end"]:
		harness.driver.assert_overlay_hidden(fragment)
	for overlay in harness.visible_overlays():
		if overlay is Node and overlay.is_in_group("title_screen"):
			continue
		var name_text: String = str(overlay.name).to_lower()
		var script: Script = overlay.get_script()
		var script_path: String = (
			str(script.resource_path).to_lower() if script != null else ""
		)
		assert_false(
			name_text.contains("session_summary")
			or name_text.contains("month_statement")
			or name_text.contains("angel_investors")
			or name_text.contains("run_end")
			or script_path.contains("session_summary")
			or script_path.contains("month_statement")
			or script_path.contains("angel_investors")
			or script_path.contains("run_end"),
			"A report overlay was still up after TITLE SCREEN"
		)


func _wait_for_desk(harness: UiHarness) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while SceneRouter.current != SceneRouter.DESK and Time.get_ticks_msec() < deadline:
		await harness.get_tree().process_frame
	await harness.settle()


func _wait_for_overlay(harness: UiHarness) -> void:
	var deadline: int = Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if (
			_overlay_up(harness, "session_summary")
			or _overlay_up(harness, "month_statement")
			or _overlay_up(harness, "angel_investors")
			or _overlay_up(harness, "run_end")
			or Simulation.phase == Simulation.Phase.RUN_END
			or Simulation.phase == Simulation.Phase.ROUND_PREP
		):
			return
		await harness.get_tree().process_frame
