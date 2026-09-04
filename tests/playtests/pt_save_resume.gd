extends PlaytestCase

## Save & Quit from the maintenance menu mid-run, then resume through the
## title's CONTINUE. The rebuilt shell has to show the same round and the
## same cash — a continue that silently starts a new game, or one that loads
## the developer's real save, is the failure this guards. Isolation already
## pointed SaveManager at the scratch file; this persona turns autosave back
## on so SAVE & QUIT writes there itself.


const SEED := 17


func play(harness: UiHarness) -> void:
	await harness.boot(SEED)
	var driver: UiDriver = harness.driver

	Simulation.autosave_enabled = true
	await accept_first_job(harness)
	Simulation.start_work()
	assert_true(Simulation.is_work_running(), "The saved run has an active burn session")

	await dismiss_investor(harness)
	var shell: Node = harness.current_scene()
	assert_true(shell != null and shell.has_method("enter_maintenance"), "The cabinet is up")
	if shell == null:
		return
	await driver.press_command("maint")
	await settle_camera(harness)
	assert_true(bool(shell.is_maintenance()), "MAINT opens the maintenance menu")
	driver.audit_screen("maintenance", "desk")
	var layer: MaintenanceLayer = shell.maintenance_layer()
	var quit_key: Button = layer.menu_key("quit") if layer != null else null
	assert_true(quit_key != null and quit_key.is_visible_in_tree(), "The menu carries SAVE & QUIT")
	if quit_key == null:
		return
	await driver.press(quit_key)
	await _wait_title_shown(harness)

	assert_true(SaveManager.has_save(), "SAVE & QUIT wrote the scratch save")
	# What CONTINUE has to bring back is what SAVE & QUIT wrote, read from the
	# file itself: the live run keeps ticking (power is metered) right up to
	# the moment the save lands.
	var saved: Dictionary = SaveManager.load_run()
	var saved_state: Dictionary = Dictionary(saved.get("run_state", {}))
	var saved_round: int = int(Dictionary(saved_state.get("calendar", {})).get("round", 0))
	var saved_cash: float = float(Dictionary(saved_state.get("economy", {})).get("cash", -1.0))
	assert_eq(str(saved.get("phase", "")), "IN_ROUND", "SAVE & QUIT wrote the run mid-round")
	assert_true(saved_round >= 1, "The save carries a round")
	assert_eq(SceneRouter.current, SceneRouter.DESK, "SAVE & QUIT never leaves the cabinet route")
	assert_false(bool(shell.is_maintenance()), "The title comes down over a closed maintenance view")
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
		"CONTINUE returns a run with pending work directly to the burn button"
	)
	if shell.has_method("current_tab"):
		assert_eq(str(shell.current_tab()), "run", "CONTINUE lands on the run tab")
		# The other screens are tabs on the same glass; going out to one and
		# back must not lose the pending work behind the button.
		shell.switch_tab("market")
		await harness.settle()
		assert_true(driver.command("BUY") != null, "The resumed operation still offers the market")
		shell.switch_tab("run")
		await harness.settle()
		assert_true(driver.command("BURN") != null, "Coming back to the run tab reaches the burn button")
	driver.audit_screen("desk", "desk")


func _wait_title_shown(harness: UiHarness) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if _title_visible(harness):
			break
		await harness.get_tree().process_frame
	# Title's cursor blink is a looping tween; settle() would sit on the
	# deadline. Frames are enough for the menu to print.
	for _frame in 8:
		await harness.get_tree().process_frame


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
