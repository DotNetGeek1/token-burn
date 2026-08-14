class_name UiDriver
extends RefCounted

## Locates a control on the live shell, proves a player could press it, then
## presses it with a real mouse event. Failures go through the persona's
## TestCase so they count in the suite total.
##
## Reachability is the point: a button that exists but is off the panel, under
## the overlay scrim, or collapsed to zero height will pass a `find_child` and
## still be unusable. Hover is skipped under headless — the dummy display often
## reports no hovered control — but the rect still has to be on the glass.

const VIEWPORT_SLOP := 8.0
const MIN_HIT := 2.0

var _harness: UiHarness
var _case: TestCase


func _init(harness: UiHarness, test_case: TestCase) -> void:
	_harness = harness
	_case = test_case


## ConsoleTable.Row or VenueTile whose `.meta` matches. Returns the row itself
## or the tile; `press` resolves a tile to its inner surface button.
func row(meta) -> Control:
	var scene: Node = _scene()
	if scene == null:
		return null
	return _find_row(scene, meta)


func command(text: String) -> Control:
	var scene: Node = _scene()
	if scene == null:
		return null
	var wanted: String = _norm(text)
	if wanted == "":
		return null
	# Venues print a disabled key-hint row with the same verb as the real
	# action (jobs: ACCEPT). Prefer an enabled match so press() hits the
	# contract sheet, not the legend.
	var candidates: Array[Control] = []
	var by_menu: Control = _find_menu_row(scene, wanted)
	if by_menu != null:
		candidates.append(by_menu)
	var by_button: Control = _find_button_text(scene, wanted)
	if by_button != null:
		candidates.append(by_button)
	var by_action: Control = _find_action_row(scene, wanted)
	if by_action != null:
		candidates.append(by_action)
	var by_card: Control = _find_game_card(scene, wanted)
	if by_card != null:
		candidates.append(by_card)
	return _prefer_enabled(candidates)


func first_tile() -> Control:
	var all: Array = tiles()
	if all.is_empty():
		return null
	return all[0]


func tiles() -> Array:
	var found: Array = []
	var scene: Node = _scene()
	if scene == null:
		return found
	_collect_tiles(scene, found)
	return found


func press(control) -> void:
	if control == null or not control is Control:
		_case.assert_true(false, "press() was given no control")
		return
	var target: Control = _press_target(control)
	if not _assert_usable(target):
		return
	var centre: Vector2 = _centre(target)
	var viewport: Viewport = target.get_viewport()
	if viewport == null:
		_case.assert_true(false, "Control has no viewport: %s" % _describe(target))
		return
	var motion := InputEventMouseMotion.new()
	motion.position = centre
	motion.global_position = centre
	viewport.push_input(motion)
	await _harness.get_tree().process_frame
	# Headless dummy displays often have no hover target. Still require a
	# usable rect; only the hover assertion is skipped.
	if DisplayServer.get_name() != "headless":
		var hovered: Control = viewport.gui_get_hovered_control()
		_case.assert_true(
			_hover_hits(hovered, target),
			"Hover missed %s (got %s)" % [_describe(target), _describe(hovered)]
		)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = centre
	down.global_position = centre
	viewport.push_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = centre
	up.global_position = centre
	viewport.push_input(up)
	await _harness.settle()


func press_command(text: String) -> void:
	var found: Control = command(text)
	_case.assert_true(found != null, "No command matching '%s'" % text)
	if found == null:
		return
	await press(found)


func press_row(meta) -> void:
	var found: Control = row(meta)
	_case.assert_true(found != null, "No row matching meta %s" % str(meta))
	if found == null:
		return
	await press(found)


## Reachable enabled buttons, no poison label text, optional route check, and
## a screenshot when the suite was launched with `--shots`.
func audit_screen(audit_name: String, expected_route: String = "") -> void:
	var scene: Node = _scene()
	_case.assert_true(scene != null, "audit_screen(%s): no current scene" % audit_name)
	if scene != null:
		_audit_buttons(scene, audit_name)
		_audit_labels(scene, audit_name)
	if expected_route != "":
		_case.assert_eq(
			SceneRouter.current,
			expected_route,
			"audit_screen(%s): route" % audit_name
		)
	if _harness.shots_enabled:
		_harness.capture(audit_name)


func assert_overlay_visible(fragment) -> void:
	var found: Control = _harness.overlay(str(fragment))
	_case.assert_true(
		found != null and found.is_visible_in_tree(),
		"Overlay '%s' should be visible" % str(fragment)
	)


func assert_overlay_hidden(fragment) -> void:
	var found: Control = _harness.overlay(str(fragment))
	_case.assert_true(
		found == null or not found.is_visible_in_tree(),
		"Overlay '%s' should be hidden" % str(fragment)
	)


## Room-mode venues put a tap-catcher over a panel that is across the room.
## A press there means "let me read this", not the row underneath.
func lean_if_needed(panel_or_tile) -> void:
	var target: Node = panel_or_tile
	if target != null and not target.has_method("far_off"):
		var parent: Node = target.get_parent()
		while parent != null:
			if parent.has_method("far_off"):
				target = parent
				break
			parent = parent.get_parent()
	if target != null and target.has_method("far_off") and target.far_off():
		await press(target)


func _scene() -> Node:
	return _harness.current_scene()


func _press_target(control: Control) -> Control:
	# VenueTile / VenuePanel take the press on an inner surface button. The
	# panel's own filter may be STOP, but the thing that receives the click
	# is the child.
	if control is VenueTile or control is VenuePanel:
		for child in control.get_children():
			if child is Button and child.is_visible_in_tree():
				return child
	return control


func _assert_usable(control: Control) -> bool:
	var ok: bool = true
	if not control.is_visible_in_tree():
		_case.assert_true(false, "Not visible: %s" % _describe(control))
		ok = false
	var rect: Rect2 = control.get_global_rect()
	if rect.size.x <= MIN_HIT or rect.size.y <= MIN_HIT:
		_case.assert_true(false, "Hit area too small (%s): %s" % [rect.size, _describe(control)])
		ok = false
	if not _centre_in_viewport(control, 0.0):
		_case.assert_true(false, "Centre off the viewport: %s" % _describe(control))
		ok = false
	if control is BaseButton and control.disabled:
		_case.assert_true(false, "Disabled: %s" % _describe(control))
		ok = false
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		_case.assert_true(false, "mouse_filter IGNORE: %s" % _describe(control))
		ok = false
	return ok


func _audit_buttons(root: Node, audit_name: String) -> void:
	if root is CanvasItem and not root.is_visible_in_tree():
		return
	if root is BaseButton and root.is_visible_in_tree():
		var button: BaseButton = root
		if (
			not button.disabled
			and button.mouse_filter != Control.MOUSE_FILTER_IGNORE
		):
			var rect: Rect2 = button.get_global_rect()
			if rect.size.x > MIN_HIT and rect.size.y > MIN_HIT:
				# A tile below the fold of a VenueBoard is supposed to be
				# scrolled to, not on the glass already.
				_case.assert_true(
					_centre_in_viewport(button, VIEWPORT_SLOP) or _inside_scroll(button),
					"%s: button centre off-screen: %s" % [audit_name, _describe(button)]
				)
	for child in root.get_children():
		_audit_buttons(child, audit_name)


func _audit_labels(root: Node, audit_name: String) -> void:
	if root is CanvasItem and not root.is_visible_in_tree():
		return
	if root is Label and root.is_visible_in_tree():
		var text: String = str(root.text)
		if _is_poison_text(text):
			_case.assert_true(
				false,
				"%s: poison label '%s' on %s" % [audit_name, text, _describe(root)]
			)
	for child in root.get_children():
		_audit_labels(child, audit_name)


func _is_poison_text(text: String) -> bool:
	var lowered: String = text.strip_edges().to_lower()
	if lowered in ["null", "nan", "inf", "-nan", "-inf"]:
		return true
	# Old MSVC 1.#INF / 1.#IND formatting that only shows up in the UI.
	return lowered.contains("1.#")


func _find_row(node: Node, meta) -> Control:
	if node is CanvasItem and not node.is_visible_in_tree():
		return null
	if node is ConsoleTable.Row and _meta_matches(node.meta, meta):
		return node
	if node is VenueTile and _meta_matches(node.meta, meta):
		return node
	for child in node.get_children():
		var found: Control = _find_row(child, meta)
		if found != null:
			return found
	return null


func _find_menu_row(node: Node, wanted: String) -> Control:
	if node is CanvasItem and not node.is_visible_in_tree():
		return null
	if node is ConsoleMenuRow and _norm(node.headline) == wanted:
		return node
	for child in node.get_children():
		var found: Control = _find_menu_row(child, wanted)
		if found != null:
			return found
	return null


func _find_button_text(node: Node, wanted: String) -> Control:
	if node is CanvasItem and not node.is_visible_in_tree():
		return null
	if node is Button and not node is ConsoleMenuRow and _norm(node.text) == wanted:
		return node
	for child in node.get_children():
		var found: Control = _find_button_text(child, wanted)
		if found != null:
			return found
	return null


func _find_action_row(node: Node, wanted: String) -> Control:
	if node is CanvasItem and not node.is_visible_in_tree():
		return null
	# ActionRow prints its verb on an inner Label, not Button.text. Skip
	# ConsoleMenuRow — those are matched by headline, and their index labels
	# would otherwise steal a contains match.
	if node is Button and not node is ConsoleMenuRow:
		if _button_label_contains(node, wanted):
			return node
	for child in node.get_children():
		var found: Control = _find_action_row(child, wanted)
		if found != null:
			return found
	return null


func _find_game_card(node: Node, wanted: String) -> Control:
	if node is CanvasItem and not node.is_visible_in_tree():
		return null
	if node is GameCard:
		var title: Label = node.get_node_or_null("Margin/VBox/HeaderRow/TitleLabel")
		if title != null and _norm(title.text) == wanted:
			var action: Control = node.get_node_or_null("Margin/VBox/ActionButton")
			if action != null and action.visible:
				return action
			return node
	for child in node.get_children():
		var found: Control = _find_game_card(child, wanted)
		if found != null:
			return found
	return null


func _collect_tiles(node: Node, found: Array) -> void:
	if node is CanvasItem and not node.is_visible_in_tree():
		return
	if node is VenueTile:
		found.append(node)
		return
	for child in node.get_children():
		_collect_tiles(child, found)


func _button_label_contains(button: Button, wanted: String) -> bool:
	for child in button.get_children():
		if _label_contains(child, wanted):
			return true
	return false


func _label_contains(node: Node, wanted: String) -> bool:
	if node is Label and _norm(node.text).contains(wanted):
		return true
	for child in node.get_children():
		if _label_contains(child, wanted):
			return true
	return false


func _meta_matches(actual, wanted) -> bool:
	return actual == wanted or str(actual) == str(wanted)


func _prefer_enabled(candidates: Array[Control]) -> Control:
	for control in candidates:
		if control is BaseButton and control.disabled:
			continue
		return control
	if candidates.is_empty():
		return null
	return candidates[0]


func _norm(text: String) -> String:
	return text.strip_edges().to_lower()


func _centre(control: Control) -> Vector2:
	return control.get_global_rect().get_center()


func _inside_scroll(node: Node) -> bool:
	var parent: Node = node.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false


func _centre_in_viewport(control: Control, slop: float) -> bool:
	var viewport: Viewport = control.get_viewport()
	if viewport == null:
		return false
	var view: Rect2 = viewport.get_visible_rect()
	if slop > 0.0:
		view = view.grow(slop)
	return view.has_point(_centre(control))


func _hover_hits(hovered: Control, target: Control) -> bool:
	if hovered == null or target == null:
		return false
	if hovered == target:
		return true
	return target.is_ancestor_of(hovered) or hovered.is_ancestor_of(target)


func _describe(node: Node) -> String:
	if node == null:
		return "<null>"
	var rect: String = ""
	if node is Control:
		rect = " %s" % str(node.get_global_rect())
	if node.is_inside_tree():
		return "%s %s%s" % [node.get_class(), node.get_path(), rect]
	return "%s %s%s" % [node.get_class(), node.name, rect]
