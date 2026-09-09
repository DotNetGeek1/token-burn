extends PlaytestCase

## "At one point I had to click on everything twice for it to register."
##
## Every pointer press reaches the cabinet twice: the project turns mouse
## clicks into touches (`emulate_touch_from_mouse`), so a click is a screen
## touch and a mouse button, and a release is both again. The driver's `press`
## pushes straight into the viewport and never sees the twin, so this persona
## goes through `Input.parse_input_event` — the same door a real mouse uses —
## and counts what each surface does per click:
##
##   - a contract card fires `pressed` once per click, including on the blank
##     pager strip at its foot (which used to swallow the press);
##   - a press that drags off the card fires nothing, and the plain click after
##     it fires once (no half-armed gesture needing a second tap);
##   - the commit button commits once per click;
##   - the investor's backdrop advances one line per tap, and hanging up on it
##     does not let the press fall through to the button underneath.


func play(harness: UiHarness) -> void:
	await harness.boot(23)
	await dismiss_investor(harness)
	var shell: Node = harness.current_scene()
	assert_true(shell != null and shell.has_method("switch_tab"), "The cabinet is up")
	if shell == null:
		return
	assert_true(
		Input.is_emulating_touch_from_mouse(),
		"The project emulates touch from mouse, so every click arrives twice"
	)
	await _card_taps(harness, shell)
	await _commit_click(harness, shell)
	await _investor_backdrop(harness, shell)


# --- Cards -------------------------------------------------------------------

func _card_taps(harness: UiHarness, shell: Node) -> void:
	shell.switch_tab("contracts")
	await harness.settle()
	var card: ContractCard = _first_card(shell)
	assert_true(card != null, "The CONTRACTS tab has a contract card on the wire")
	if card == null:
		return
	var counter: Array[int] = [0]
	card.pressed.connect(func() -> void: counter[0] += 1)
	var rect: Rect2 = card.get_global_rect()
	var centre: Vector2 = rect.get_center()

	await _click(harness, centre)
	assert_eq(counter[0], 1, "One click on a card fires `pressed` once (not twice, not zero)")
	await _click(harness, centre)
	assert_eq(counter[0], 2, "A second click fires once more")

	# Press on the card, drag well past the slop, let go off it: a scroll, not
	# a tap. The plain click after must not need a second attempt.
	await _click(harness, centre, centre + Vector2(rect.size.x * 1.5, 0.0))
	assert_eq(counter[0], 2, "A press dragged off the card is a scroll, not a tap")
	await _click(harness, centre)
	assert_eq(counter[0], 3, "The click after a cancelled press registers first time")

	# The pager strip at the foot of the card: blank on an offer, it used to be
	# a MOUSE_FILTER_STOP Label that ate the press without doing anything.
	var foot := Vector2(centre.x, rect.position.y + rect.size.y * 0.93)
	await _click(harness, foot)
	assert_eq(counter[0], 4, "A click on the blank pager strip at the card's foot is a card press")


# --- Commit button -----------------------------------------------------------

func _commit_click(harness: UiHarness, shell: Node) -> void:
	shell.switch_tab("contracts")
	await harness.settle()
	var card: ContractCard = _first_card(shell)
	var button: CommitButton = _find_commit_button(shell)
	assert_true(button != null, "The cabinet has its commit button")
	if card == null or button == null:
		return
	await _click(harness, card.get_global_rect().get_center())
	await harness.settle()
	if not button.is_enabled():
		print("    ACCEPT not armed (%s); commit click not exercised" % str(button.action().get("sub", "")))
		return
	var slate_before: int = Array(Simulation.run_state.business.get("job_queue", [])).size()
	var commits: Array[int] = [0]
	button.committed.connect(func() -> void: commits[0] += 1)
	await _click(harness, button.get_global_rect().get_center())
	await harness.settle()
	assert_eq(commits[0], 1, "One click on ACCEPT commits once")
	assert_eq(
		Array(Simulation.run_state.business.get("job_queue", [])).size(), slate_before + 1,
		"The click put exactly one contract on the slate"
	)


# --- The phone ---------------------------------------------------------------

func _investor_backdrop(harness: UiHarness, shell: Node) -> void:
	var button: CommitButton = _find_commit_button(shell)
	shell.switch_tab("contracts")
	await harness.settle()
	# Pick a card so ACCEPT is armed underneath the phone: the hang-up tap
	# lands right on it, and must not press it.
	var card: ContractCard = _first_card(shell)
	if card != null:
		await _click(harness, card.get_global_rect().get_center())
		await harness.settle()
	SceneRouter.investor_says("terms")
	await harness.settle()
	assert_true(SceneRouter.investor_busy(), "The investor picks up")
	var phone: Node = _find_phone(harness.get_tree().root)
	assert_true(phone != null, "The phone scene is in the tree")
	if phone == null or not SceneRouter.investor_busy():
		return
	var progress: Label = phone.get_node("Phone/Margin/Columns/VBox/Progress")
	var lines: int = int(str(progress.text).get_slice("/", 1).strip_edges())
	# Tap on the backdrop over something that would act if pressed — the
	# commit button, or a card if the handset covers the button at this
	# window — and count what it does. Each tap while the line is fully typed
	# moves exactly one line on, and leaves the next line typing: the twin
	# press used to land as a second tap and finish it on the spot.
	var handset: Rect2 = (phone.get_node("Phone") as Control).get_global_rect()
	var underneath: Control = null
	for candidate in [button, card]:
		if candidate != null and not handset.intersects((candidate as Control).get_global_rect()):
			underneath = candidate
			break
	var presses: Array[int] = [0]
	var target: Vector2 = Vector2(handset.position.x * 0.5, handset.position.y * 0.5)
	if underneath == null:
		print("    the handset covers the button and the card here; leak-through not exercised")
	else:
		target = underneath.get_global_rect().get_center()
		if underneath is CommitButton:
			(underneath as CommitButton).committed.connect(func() -> void: presses[0] += 1)
		else:
			(underneath as ContractCard).pressed.connect(func() -> void: presses[0] += 1)
	for index in range(lines):
		phone.call("_finish_typing")
		await harness.settle()
		assert_eq(
			str(progress.text), "%d / %d" % [index + 1, lines],
			"Before tap %d the phone is on line %d" % [index + 1, index + 1]
		)
		await _click(harness, target)
		if index + 1 < lines:
			assert_true(SceneRouter.investor_busy(), "Tap %d does not hang up early" % (index + 1))
			assert_eq(
				str(progress.text), "%d / %d" % [index + 2, lines],
				"Tap %d on the backdrop advances exactly one line" % (index + 1)
			)
			assert_true(
				bool(phone.get("_typing")),
				"Tap %d leaves the next line typing: the press's twin does not count as a second tap" % (index + 1)
			)
		await harness.settle()
	assert_false(SceneRouter.investor_busy(), "The last tap hangs up")
	if underneath != null:
		assert_eq(
			presses[0], 0,
			"Hanging up on the backdrop does not press the %s underneath"
			% ("button" if underneath is CommitButton else "card")
		)
	if SceneRouter.investor_busy():
		SceneRouter.hide_investor()
		await harness.settle()


# --- Real-pipeline input -----------------------------------------------------

## One left click through `Input`, so the engine emulates the touch twin the
## way it does for a player. `at` and `release_at` are canvas coordinates
## (`get_global_rect` space); a differing `release_at` drags between them
## with the button held, which also emulates the screen drag.
func _click(harness: UiHarness, at: Vector2, release_at: Vector2 = Vector2.INF) -> void:
	if release_at == Vector2.INF:
		release_at = at
	var viewport: Viewport = harness.get_tree().root
	var to_window: Transform2D = viewport.get_final_transform()
	var press_pos: Vector2 = to_window * at
	var release_pos: Vector2 = to_window * release_at
	var motion := InputEventMouseMotion.new()
	motion.position = press_pos
	motion.global_position = press_pos
	Input.parse_input_event(motion)
	await _frames(harness, 2)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	down.position = press_pos
	down.global_position = press_pos
	Input.parse_input_event(down)
	await _frames(harness, 2)
	if release_pos != press_pos:
		var steps: int = 5
		for step in range(1, steps + 1):
			var here: Vector2 = press_pos.lerp(release_pos, float(step) / float(steps))
			var drag := InputEventMouseMotion.new()
			drag.button_mask = MOUSE_BUTTON_MASK_LEFT
			drag.position = here
			drag.global_position = here
			drag.relative = (release_pos - press_pos) / float(steps)
			Input.parse_input_event(drag)
			await _frames(harness, 1)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = release_pos
	up.global_position = release_pos
	Input.parse_input_event(up)
	await _frames(harness, 3)


func _frames(harness: UiHarness, count: int) -> void:
	for _index in range(count):
		await harness.get_tree().process_frame


# --- Locators ----------------------------------------------------------------

func _first_card(root: Node) -> ContractCard:
	return _find_first(root, func(node: Node) -> bool:
		return node is ContractCard and (node as Control).is_visible_in_tree()
	) as ContractCard


func _find_commit_button(root: Node) -> CommitButton:
	return _find_first(root, func(node: Node) -> bool: return node is CommitButton) as CommitButton


func _find_phone(root: Node) -> Node:
	return _find_first(root, func(node: Node) -> bool:
		return node.has_method("call_player") and node.has_node("Phone/Margin/Columns/VBox/Progress")
	)


func _find_first(node: Node, predicate: Callable) -> Node:
	if node == null:
		return null
	if bool(predicate.call(node)):
		return node
	for child in node.get_children():
		var found: Node = _find_first(child, predicate)
		if found != null:
			return found
	return null
