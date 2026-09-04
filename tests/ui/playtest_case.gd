class_name PlaytestCase
extends TestCase

## Async persona base. The fast suite's `TestCase.run` is synchronous and never
## sees a tree; a playtest has to `await` the shell, so the runner calls this
## `play(harness)` instead and tallies `get_results()` after it comes back.
## Named `play` rather than `run` because TestCase.run is synchronous and
## GDScript will not resolve an awaited override with a different signature.
##
## Personas `await harness.boot(seed)` and then drive `harness.driver`.

const ROUND_FLOW_DEADLINE_MSEC := 20000
const BURN_DEADLINE_MSEC := 30000


func play(harness: UiHarness) -> void:
	pass


## Spins frames until `predicate` returns true or `timeout_msec` passes.
## Returns whether it was met.
func wait_until(harness: UiHarness, predicate: Callable, timeout_msec: int = 4000) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		if not harness.is_inside_tree():
			return false
		await harness.get_tree().process_frame
	return bool(predicate.call())


## Waits for the cabinet's maintenance camera to finish moving either way.
func settle_camera(harness: UiHarness) -> void:
	var shell: Node = harness.current_scene()
	if shell == null or not shell.has_method("maintenance_layer"):
		await harness.settle()
		return
	var layer: Variant = shell.maintenance_layer()
	if layer == null:
		await harness.settle()
		return
	await wait_until(harness, func() -> bool: return not bool(layer.is_transitioning()))
	await harness.settle()


## Dismiss the investor phone if it is ringing over the cabinet.
func dismiss_investor(harness: UiHarness) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while SceneRouter.investor_busy() and Time.get_ticks_msec() < deadline:
		var skip: Control = harness.driver.command("GOT IT")
		if skip == null:
			skip = harness.driver.command("GO ON")
		if skip == null:
			skip = harness.driver.command("SKIP")
		if skip != null:
			await harness.driver.press(skip)
		else:
			SceneRouter.hide_investor()
			await harness.settle()
			return
	if SceneRouter.investor_busy():
		SceneRouter.hide_investor()
		await harness.settle()


## Takes the first offer on the wire through the glass: the CONTRACTS tab,
## a card on the ON THE WIRE shelf, and the commit button reading ACCEPT.
func accept_first_job(harness: UiHarness) -> String:
	await dismiss_investor(harness)
	if SceneRouter.current != SceneRouter.DESK:
		await harness.go_desk()
	var shell: Node = harness.current_scene()
	if shell != null and shell.has_method("switch_tab"):
		shell.switch_tab("contracts")
		await harness.settle()
	harness.driver.audit_screen("contracts", "desk")
	var tile: Control = harness.driver.first_tile()
	assert_true(tile != null, "The CONTRACTS tab has a contract card on the wire")
	if tile == null:
		return ""
	await harness.driver.press(tile)
	var job_id: String = ""
	if tile is ContractCard:
		job_id = str(Dictionary(tile.job()).get("id", ""))
	elif tile is CabinetTile:
		job_id = str(tile.meta)
	await harness.driver.press_command("ACCEPT")
	await harness.settle()
	return job_id


func burn_until_session_over(harness: UiHarness) -> void:
	await dismiss_investor(harness)
	if SceneRouter.current != SceneRouter.DESK:
		await harness.go_desk()
	var shell: Node = harness.current_scene()
	if shell != null and shell.has_method("switch_tab"):
		shell.switch_tab("board")
		await harness.settle()
	# One real click proves BURN is on the glass and hittable. The rest of
	# the session is the batch runner's own loop: each UI burn waits out the
	# spectacle, and a twelve-round campaign cannot afford that.
	var burn: Control = harness.driver.command("BURN")
	if burn != null:
		await harness.driver.press(burn)
	if Simulation.can_start_work():
		Simulation.start_work()
	if Simulation.phase == Simulation.Phase.IN_ROUND or Simulation.is_work_running():
		Simulation.auto_arrange_board()
		var safety: int = 0
		while Simulation.phase == Simulation.Phase.IN_ROUND and safety < 200:
			safety += 1
			var preview: Dictionary = Simulation.preview_burn()
			var capacity: float = maxf(1.0, float(Simulation.run_state.compute.get("heat_capacity", 100.0)))
			var heat: float = float(Simulation.run_state.compute.get("heat", 0.0))
			var projected: float = heat + float(preview.get("total_heat", 0.0))
			if projected >= capacity and float(Simulation.preview_cool().get("total_heat", 0.0)) < 0.0:
				if bool(Simulation.cool_hardware().get("ok", false)):
					continue
			if JobSystem.is_ready(Simulation.focused_job()):
				if Simulation.ship_focused_job():
					continue
			if not bool(Simulation.burn_batch().get("ok", false)):
				break
	await harness.settle()


## Debrief → bills → angels, each dismissed by its own footer. These overlays
## set dismiss_on_scrim false, so the driver must not shortcut via close().
func walk_round_flow(harness: UiHarness) -> void:
	var deadline: int = Time.get_ticks_msec() + ROUND_FLOW_DEADLINE_MSEC
	var saw_debrief: bool = false
	var saw_bills: bool = false
	while Time.get_ticks_msec() < deadline:
		await dismiss_investor(harness)
		if Simulation.phase == Simulation.Phase.RUN_END:
			return
		if _overlay_up(harness, "session_summary"):
			saw_debrief = true
			harness.driver.assert_overlay_visible("session_summary")
			await harness.driver.press_command("CONTINUE")
			continue
		if _overlay_up(harness, "month_statement"):
			saw_bills = true
			assert_true(saw_debrief, "Bills arrived after the debrief")
			harness.driver.assert_overlay_visible("month_statement")
			await harness.driver.press_command("CONTINUE")
			continue
		if _overlay_up(harness, "angel_investors"):
			assert_true(saw_bills or saw_debrief, "Angels arrived after the round reports")
			harness.driver.assert_overlay_visible("angel_investors")
			var take: Control = harness.driver.command("TAKE IT")
			if take != null:
				await harness.driver.press(take)
			else:
				await harness.driver.press_command("TAKE NOTHING")
			continue
		if Simulation.phase == Simulation.Phase.ROUND_PREP:
			return
		if Simulation.phase == Simulation.Phase.IN_ROUND:
			return
		await harness.settle()
	assert_true(
		Simulation.phase == Simulation.Phase.ROUND_PREP
		or Simulation.phase == Simulation.Phase.RUN_END,
		"Round flow stalled in phase %s" % Simulation.phase
	)


func _overlay_up(harness: UiHarness, fragment: String) -> bool:
	var found: Control = harness.overlay(fragment)
	return found != null and found.is_visible_in_tree()


## The desk shows the verdict from refresh_all when phase is RUN_END. A win
## or loss that landed while the shell was mid-swap can miss that call, so
## this asks again and, if the node is sitting there hidden, opens it the
## same way main.gd would.
func ensure_run_end_overlay(harness: UiHarness) -> void:
	if SceneRouter.current != SceneRouter.DESK:
		await harness.go_desk()
	if harness.is_inside_tree():
		harness.get_tree().call_group("main_ui", "refresh_all")
	await harness.settle()
	if _overlay_up(harness, "run_end"):
		return
	var hidden: Control = _find_named_overlay(harness.current_scene(), "run_end")
	if hidden == null and harness.is_inside_tree():
		for node in harness.get_tree().get_nodes_in_group("flow_overlay"):
			if node is Control and _overlay_script_matches(node, "run_end"):
				hidden = node
				break
	if hidden != null and hidden.has_method("show_from_state"):
		hidden.show_from_state(
			bool(Simulation.run_state.flags.get("victory", false)),
			str(Simulation.run_state.flags.get("loss_reason", ""))
		)
		await harness.settle()


func _overlay_script_matches(node: Node, needle: String) -> bool:
	var script: Script = node.get_script()
	var path: String = str(script.resource_path).to_lower() if script != null else ""
	var name_text: String = str(node.name).to_lower().replace("_", "")
	return path.contains(needle) or name_text.contains(needle.replace("_", ""))


func _find_named_overlay(node: Node, needle: String) -> Control:
	if node == null:
		return null
	if node is Control and _overlay_script_matches(node, needle):
		return node
	for child in node.get_children():
		var found: Control = _find_named_overlay(child, needle)
		if found != null:
			return found
	return null
