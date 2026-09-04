extends PlaytestCase

## Android pause / system-back / resume contract, driven through SceneRouter
## notifications the same way the OS would.


func play(harness: UiHarness) -> void:
	await harness.boot(41)
	await _pause_autosaves_mid_burn(harness)
	await _system_back_from_venue(harness)
	await _system_back_steps_out_of_lean(harness)
	await _system_back_closes_desk_overlay(harness)
	await _system_back_returns_to_run_tab(harness)
	await _system_back_opens_menu_from_desk(harness)
	await _resume_recovers_blank_shell(harness)


func _pause_autosaves_mid_burn(harness: UiHarness) -> void:
	await accept_first_job(harness)
	if Simulation.can_start_work():
		Simulation.start_work()
	assert_true(Simulation.is_work_running(), "A burn is in flight before pause")
	Simulation.autosave_enabled = true
	SaveManager.delete_save()
	var cash: float = float(Simulation.run_state.economy.get("cash", 0.0))
	var round_number: int = int(Simulation.run_state.calendar.get("round", 0))
	SceneRouter.notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	assert_true(SaveManager.has_save(), "Pause writes a save mid-burn")
	var data: Dictionary = SaveManager.load_run()
	assert_eq(str(data.get("phase", "")), "IN_ROUND", "Pause save is in-round")
	assert_eq(
		int(Dictionary(data.get("run_state", {})).get("calendar", {}).get("round", 0)),
		round_number,
		"Pause save keeps the live round"
	)
	assert_almost_eq(
		float(Dictionary(data.get("run_state", {})).get("economy", {}).get("cash", -1.0)),
		cash,
		0.01,
		"Pause save keeps the live cash"
	)
	Simulation.autosave_enabled = false


func _system_back_from_venue(harness: UiHarness) -> void:
	if SceneRouter.current != SceneRouter.DESK:
		await harness.go_desk()
	await harness.goto_route("jobs")
	assert_eq(SceneRouter.current, "jobs", "Jobs is the current route")
	SceneRouter.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _wait_for_route(harness, SceneRouter.DESK)
	assert_eq(SceneRouter.current, SceneRouter.DESK, "System back leaves Jobs for the desk")
	assert_true(SceneRouter.visible_route_ok(), "Desk is visible after system back")


func _system_back_steps_out_of_lean(harness: UiHarness) -> void:
	await harness.goto_route("jobs")
	var venue: Node = harness.current_scene()
	assert_true(venue != null and venue.has_method("handle_system_back"), "Jobs is a venue")
	venue._leaning_on = "board"
	SceneRouter.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await harness.settle()
	assert_eq(SceneRouter.current, "jobs", "System back while leant in stays on Jobs")
	assert_eq(str(venue._leaning_on), "", "System back clears the lean-in")
	await harness.go_desk()


func _system_back_closes_desk_overlay(harness: UiHarness) -> void:
	if SceneRouter.current != SceneRouter.DESK:
		await harness.go_desk()
	var shell: Node = harness.current_scene()
	assert_true(shell != null and shell.has_method("open_help"), "Desk can open help")
	shell.open_help()
	await harness.settle()
	var help: Control = harness.overlay("help")
	assert_true(help != null and help.visible, "Help is open")
	SceneRouter.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await harness.settle()
	assert_true(help == null or not help.visible, "System back closes help")
	assert_eq(SceneRouter.current, SceneRouter.DESK, "Closing help stays on the desk")


func _system_back_returns_to_run_tab(harness: UiHarness) -> void:
	if SceneRouter.current != SceneRouter.DESK:
		await harness.go_desk()
	# The cabinet has no room zoom; the equivalent depth is a tab other than
	# the run. System back comes home to the run tab before it opens the menu.
	var shell: Node = harness.current_scene()
	assert_true(shell != null and shell.has_method("current_tab"), "Cabinet reports its tab")
	shell.switch_tab("market")
	await harness.settle()
	assert_eq(str(shell.current_tab()), "market", "Cabinet is showing the market tab")
	SceneRouter.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await harness.settle()
	assert_eq(str(shell.current_tab()), "run", "System back returns to the run tab")
	assert_eq(SceneRouter.current, SceneRouter.DESK, "Coming home to the run tab stays on the desk")


func _system_back_opens_menu_from_desk(harness: UiHarness) -> void:
	if SceneRouter.current != SceneRouter.DESK:
		await harness.go_desk()
	SceneRouter.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _wait_for_route(harness, "menu")
	assert_eq(SceneRouter.current, "menu", "System back from a bare desk opens the menu")
	await harness.go_desk()


func _resume_recovers_blank_shell(harness: UiHarness) -> void:
	if SceneRouter.current != SceneRouter.DESK:
		await harness.go_desk()
	var screen: Node = harness.current_scene()
	assert_true(screen is CanvasItem, "Desk is a CanvasItem")
	(screen as CanvasItem).visible = false
	assert_false(SceneRouter.visible_route_ok(), "Hidden desk is a blank shell")
	SceneRouter.notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	await harness.settle()
	assert_true(SceneRouter.visible_route_ok(), "Resume remounts a visible route")


func _wait_for_route(harness: UiHarness, route: String) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while SceneRouter.current != route and Time.get_ticks_msec() < deadline:
		await harness.get_tree().process_frame
	for _frame in 4:
		await harness.get_tree().process_frame
