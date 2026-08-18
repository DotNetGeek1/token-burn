extends PlaytestCase

## Quits to title from the menu mid-run and resumes through CONTINUE. The
## rebuilt shell has to show the same round and the same cash — a continue
## that silently starts a new game, or one that loads the developer's real
## save, is the failure this guards. Isolation already pointed SaveManager
## at the scratch file; this persona turns autosave back on and writes
## there itself, because _autosave is private and isolate() had it off.


const SEED := 17
const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")


func play(harness: UiHarness) -> void:
	await harness.boot(SEED)
	var driver: UiDriver = harness.driver

	Simulation.autosave_enabled = true
	await accept_first_job(harness)
	Simulation.start_work()
	assert_true(Simulation.is_work_running(), "The saved run has an active burn session")

	var saved_round: int = int(Simulation.run_state.calendar.get("round", 1))
	var saved_cash: float = float(Simulation.run_state.economy.get("cash", 0.0))
	# Accepting a contract already autosaves when the flag is on. Write
	# explicitly anyway so the title's CONTINUE has something to read even
	# if that path did not fire.
	SaveManager.save_run(
		Simulation.run_state,
		"IN_ROUND",
		Simulation.run_seed,
		Simulation.pending_choices
	)
	assert_true(SaveManager.has_save(), "A scratch save exists before quitting")

	await dismiss_investor(harness)
	await harness.goto_route("menu")
	driver.audit_screen("menu", "menu")
	await driver.press_command("QUIT TO TITLE")
	await _wait_for_desk(harness)

	assert_true(SaveManager.has_save(), "QUIT TO TITLE left the scratch save")
	var continue_row: Control = await _wait_title_continue(harness)
	assert_true(continue_row != null, "Title shows CONTINUE when a save exists")
	if continue_row != null:
		await driver.press(continue_row)
	await _wait_title_gone(harness)

	assert_eq(
		int(Simulation.run_state.calendar.get("round", 0)),
		saved_round,
		"CONTINUE restored the same round"
	)
	assert_almost_eq(
		float(Simulation.run_state.economy.get("cash", 0.0)),
		saved_cash,
		0.01,
		"CONTINUE restored the same cash"
	)
	assert_true(
		driver.command("BURN") != null,
		"CONTINUE returns a run with pending work directly to the burn board"
	)
	var shell: Node = harness.current_scene()
	if shell != null:
		shell.switch_tab("office")
		await harness.settle()
		var open_board: Control = driver.command("OPEN BOARD")
		var console: WorkstationConsole = shell.find_child("PrimaryConsole", true, false)
		assert_true(open_board != null, "The resumed operation still offers OPEN BOARD")
		assert_true(console != null, "The resumed operation has a primary console")
		if open_board != null and console != null:
			assert_true(
				console._should_lean_in(true, true),
				"A compact mobile console captures the first tap while across the room"
			)
			var bay_zoom: float = ConsoleMetrics.focus_zoom(shell._focus_rect("workstation"))
			console._on_lean_in_pressed()
			await harness.settle()
			assert_true(
				shell.room_focused_on("workstation"),
				"The first mobile tap focuses the workstation"
			)
			assert_true(
				shell._focus_full_zoom > bay_zoom,
				"Mobile focus targets the smaller live glass instead of the whole bay"
			)
			assert_false(
				console._should_lean_in(true, true),
				"The lean-in catcher releases commands after the workstation is focused"
			)
			await driver.press(open_board)
			assert_true(driver.command("BURN") != null, "OPEN BOARD reaches the burn screen")
			shell.clear_room_focus()
			await harness.settle()
	driver.audit_screen("desk", "desk")


func _wait_title_continue(harness: UiHarness) -> Control:
	# Boot animation ignores clicks until _booted; any click skips it, but
	# the rows stay mouse_filter IGNORE until then, so press() would fail.
	# Wait until CONTINUE is actually hittable.
	var deadline: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		var row: Control = harness.driver.command("CONTINUE")
		if (
			row != null
			and row.mouse_filter != Control.MOUSE_FILTER_IGNORE
			and not (row is BaseButton and row.disabled)
		):
			return row
		await harness.get_tree().process_frame
	return harness.driver.command("CONTINUE")


func _wait_title_gone(harness: UiHarness) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if not _title_visible(harness):
			await harness.get_tree().process_frame
			await harness.get_tree().process_frame
			return
		await harness.get_tree().process_frame


func _title_visible(harness: UiHarness) -> bool:
	if not harness.is_inside_tree():
		return false
	for node in harness.get_tree().get_nodes_in_group("title_screen"):
		if node is CanvasItem and node.is_visible_in_tree():
			return true
	return false


func _wait_for_desk(harness: UiHarness) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while SceneRouter.current != SceneRouter.DESK and Time.get_ticks_msec() < deadline:
		await harness.get_tree().process_frame
	# Title's cursor blink is a looping tween; settle() would sit on the
	# deadline. Frames are enough for the desk to mount and the menu to print.
	for _frame in 8:
		await harness.get_tree().process_frame
