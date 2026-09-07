extends "res://tests/playtests/pt_cabinet_viewports.gd"

## The Burn Cabinet on a phone. DisplayScale draws the canvas at a physical
## factor so 12 px type is legible, which leaves the shell a canvas around
## 650×300 design pixels; the `handset` layout profile has to lay the whole
## machine out on it with the CRT still dominant, the dock paged to four bays
## on the bottom row and the deck beside it tall enough to press.
##
## Every tab of the glass is opened at that size: whatever a tab prints has to
## stay on the glass (scrolling is fine, spilling over the bezel is not), and
## nothing may be typeset under the handset's own floor.

## The canvas the phone window comes out at through the factor.
const PHONE_CANVAS := Vector2(650.0, 300.0)
const EXPECTED_HANDSET := {"profile": "handset", "grid": Vector2i(4, 1)}
## Touch floor in canvas pixels: the profile's own 40, which is ~9 mm on the
## glass once the factor is applied.
const MIN_TOUCH_PHONE := 40.0
## The smallest type the glass may carry, in canvas pixels. Instruments that
## cut their own type to fit clamp at 8; anything under that is a bug.
const MIN_FONT_PX := 8
const TABS: Array[String] = ["run", "contracts", "modules", "market", "perks"]


func play(harness: UiHarness) -> void:
	await harness.boot(97)
	var shell: Node = harness.current_scene()
	assert_true(
		shell != null and shell.is_in_group("main_ui"),
		"The cabinet shell is the current scene after boot"
	)
	if shell == null:
		return
	await harness.set_handset_viewport()
	await harness.settle()
	var label := "phone"
	var view: Rect2 = shell.get_viewport().get_visible_rect()
	assert_true(
		absf(view.size.x - PHONE_CANVAS.x) <= 2.0 and absf(view.size.y - PHONE_CANVAS.y) <= 2.0,
		"%s canvas is the window over the factor (got %s, want %s)" % [label, view.size, PHONE_CANVAS]
	)
	assert_true(DisplayScale.is_handset(), "%s DisplayScale reports a handset at factor %.2f" % [label, DisplayScale.factor()])
	_assert_profile(shell, EXPECTED_HANDSET, label)
	_assert_crt(shell, view, label)
	_assert_dock(shell, EXPECTED_HANDSET, label)
	_assert_commit_button(shell, MIN_TOUCH_PHONE, label)
	_assert_no_clipping(shell, view, label)
	_assert_bays_touchable(shell, label)
	for tab in TABS:
		await harness.goto_tab(tab)
		await harness.settle()
		var tab_label := "%s/%s" % [label, tab]
		_assert_no_clipping(shell, view, tab_label)
		_assert_tab_on_glass(shell, tab_label)
		_assert_type_floor(shell, tab_label)
		harness.capture("cabinet-%s" % tab_label.replace("/", "-"))
	await harness.goto_tab("run")
	await harness.set_viewport(UiHarness.VIEW_DESKTOP)
	assert_false(DisplayScale.is_handset(), "the desktop window clears the handset factor")


## Every live bay is a touch target on the phone too.
func _assert_bays_touchable(shell: Node, label: String) -> void:
	var dock: Control = _find_dock(shell)
	if dock == null:
		return
	for bay in dock.get_children():
		if bay is Control and bay.is_visible_in_tree() and bay.has_method("show_slot") and not bool(bay.get("covered")):
			var bounds: Rect2 = _bounds(bay)
			assert_true(
				bounds.size.x >= MIN_TOUCH_PHONE * 0.8 and bounds.size.y >= MIN_TOUCH_PHONE * 0.6,
				"%s %s is a touch target (got %s)" % [label, _describe(bay), bounds.size]
			)


## The visible tab's controls stay inside the glass. Anything inside a
## ScrollContainer may run past its own edge; the scroll clips it.
func _assert_tab_on_glass(shell: Node, label: String) -> void:
	var screen: Control = _find_screen(shell)
	if screen == null:
		return
	var glass: Rect2 = _bounds(screen).grow(CLIP_SLOP)
	var tab: Control = _find_first(screen, func(node: Node) -> bool:
		return node is CabinetTab and (node as Control).is_visible_in_tree()
	) as Control
	assert_true(tab != null, "%s a tab is up on the glass" % label)
	if tab == null:
		return
	var offenders: Array[String] = []
	_collect_off_glass(tab, glass, false, offenders)
	assert_true(
		offenders.is_empty(),
		"%s everything the tab prints stays on the glass (off: %s)" % [label, ", ".join(offenders.slice(0, 6))]
	)


func _collect_off_glass(node: Node, glass: Rect2, in_scroll: bool, out: Array[String]) -> void:
	if node is Control and not (node as Control).is_visible_in_tree():
		return
	var scrolled: bool = in_scroll or node is ScrollContainer
	if node is Control and not scrolled and (node is Label or node is BaseButton):
		var bounds: Rect2 = _bounds(node)
		if bounds.size.x > 0.0 and bounds.size.y > 0.0 and not glass.encloses(bounds):
			var text: String = str(node.get("text")).left(24) if node.get("text") != null else ""
			out.append("%s '%s' %s" % [_describe(node), text, bounds])
	for child in node.get_children():
		_collect_off_glass(child, glass, scrolled, out)


## No label on the machine is typeset under the floor.
func _assert_type_floor(shell: Node, label: String) -> void:
	var small: Array[String] = []
	_collect_small_type(shell, small)
	assert_true(
		small.is_empty(),
		"%s no visible label is under %d px (found: %s)" % [label, MIN_FONT_PX, ", ".join(small.slice(0, 6))]
	)


func _collect_small_type(node: Node, out: Array[String]) -> void:
	if str(node.name) == "OverlayRoot":
		return
	if node is Control and not (node as Control).is_visible_in_tree():
		return
	if node is Label and (node as Label).text.strip_edges() != "":
		var px: int = (node as Label).get_theme_font_size("font_size")
		if px < MIN_FONT_PX:
			out.append("%s '%s' %dpx" % [_describe(node), (node as Label).text.left(18), px])
	for child in node.get_children():
		_collect_small_type(child, out)
