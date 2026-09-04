extends PlaytestCase

## The Burn Cabinet at every window it has to work in. The gameplay
## instruments — the CRT, the module dock, the commit button — must be on the
## glass, finite, touchable and inside the viewport at each size. Decorative
## metal may crop; these may not.
##
## Instruments are found by class or by their public surface (`set_action` on
## the commit button), never by the shell's private member names: the shell is
## mid-refactor and a rename must not take this persona down with it.

const VIEWPORTS: Array[Vector2i] = [
	Vector2i(1600, 900),
	Vector2i(1280, 720),
	Vector2i(1024, 768),
	Vector2i(960, 540),
	Vector2i(854, 480),
]

## The layout profile and dock grid the responsive shell must pick at each
## window (spec/03_LAYOUT_AND_RESPONSIVE_SPEC.md): ten bays in a row on a wide
## window, five by two on a compact or tablet one.
const EXPECTED_PROFILE := {
	Vector2i(1600, 900): {"profile": "wide", "grid": Vector2i(10, 1)},
	Vector2i(1280, 720): {"profile": "wide", "grid": Vector2i(10, 1)},
	Vector2i(1024, 768): {"profile": "tablet", "grid": Vector2i(5, 2)},
	Vector2i(960, 540): {"profile": "compact", "grid": Vector2i(5, 2)},
	Vector2i(854, 480): {"profile": "compact", "grid": Vector2i(5, 2)},
}

## The responsive shell has to give the CRT at least this much of the viewport
## (spec/08_ACCEPTANCE_TESTS.md). The measured ratios are printed as well.
const TARGET_CRT_WIDTH_RATIO := 0.65
const TARGET_CRT_HEIGHT_RATIO := 0.50
const ENFORCE_CRT_TARGETS := true

## Minimum touch target, in viewport pixels (WCAG 2.5.5 / spec 03): 48 on
## every window, 44 allowed only on the 854x480 handset.
const MIN_TOUCH := 48.0
const MIN_TOUCH_HANDSET := 44.0
const HANDSET := Vector2i(854, 480)
const ENFORCE_MIN_TOUCH := true
## Sub-pixel tolerance on the viewport edge.
const CLIP_SLOP := 1.0


func play(harness: UiHarness) -> void:
	await harness.boot(97)
	var shell: Node = harness.current_scene()
	assert_true(
		shell != null and shell.is_in_group("main_ui"),
		"The cabinet shell is the current scene after boot"
	)
	if shell == null:
		return
	for viewport_size in VIEWPORTS:
		await harness.set_viewport(viewport_size)
		await harness.settle()
		var label := "%dx%d" % [viewport_size.x, viewport_size.y]
		var view: Rect2 = shell.get_viewport().get_visible_rect()
		assert_true(
			absf(view.size.x - float(viewport_size.x)) <= CLIP_SLOP
			and absf(view.size.y - float(viewport_size.y)) <= CLIP_SLOP,
			"%s viewport took the requested size (got %s)" % [label, view.size]
		)
		_assert_profile(shell, viewport_size, label)
		_assert_crt(shell, view, label)
		_assert_dock(shell, viewport_size, label)
		_assert_commit_button(shell, viewport_size, label)
		_assert_no_clipping(shell, view, label)
		harness.capture("cabinet-%s" % label)
	await harness.set_viewport(UiHarness.VIEW_DESKTOP)


# --- Profile -----------------------------------------------------------------

## The shell picks its layout profile from the window.
func _assert_profile(shell: Node, viewport_size: Vector2i, label: String) -> void:
	if not shell.has_method("layout_profile_name") or not shell.has_method("dock_grid"):
		assert_true(false, "%s the shell exposes layout_profile_name() and dock_grid()" % label)
		return
	var expected: Dictionary = EXPECTED_PROFILE.get(viewport_size, {})
	var profile: String = str(shell.call("layout_profile_name"))
	var grid: Vector2i = shell.call("dock_grid")
	assert_eq(profile, str(expected.get("profile", "")), "%s layout profile" % label)
	assert_eq(grid, expected.get("grid", Vector2i.ZERO), "%s dock grid (columns x rows)" % label)
	if shell.has_method("safe_area_rect"):
		var safe: Rect2 = shell.call("safe_area_rect")
		assert_true(
			safe.size.x > 0.0 and safe.size.y > 0.0 and safe.position.x >= 0.0 and safe.position.y >= 0.0,
			"%s safe area is a positive rect inside the window (got %s)" % [label, safe]
		)


# --- Instruments -------------------------------------------------------------

func _assert_crt(shell: Node, view: Rect2, label: String) -> void:
	var screen: Control = _find_screen(shell)
	assert_true(screen != null, "%s the CRT (CabinetScreen) is mounted" % label)
	if screen == null:
		return
	assert_true(screen.is_visible_in_tree(), "%s the CRT is visible" % label)
	var crt: Rect2 = _bounds(screen)
	assert_true(
		crt.size.is_finite() and crt.size.x > 1.0 and crt.size.y > 1.0,
		"%s the CRT has a finite positive size (got %s)" % [label, crt.size]
	)
	if crt.size.x <= 0.0 or crt.size.y <= 0.0 or view.size.x <= 0.0 or view.size.y <= 0.0:
		return
	var width_ratio: float = crt.size.x / view.size.x
	var height_ratio: float = crt.size.y / view.size.y
	var width_ok: bool = width_ratio > 0.0 and (not ENFORCE_CRT_TARGETS or width_ratio >= TARGET_CRT_WIDTH_RATIO)
	var height_ok: bool = height_ratio > 0.0 and (not ENFORCE_CRT_TARGETS or height_ratio >= TARGET_CRT_HEIGHT_RATIO)
	assert_true(
		width_ok,
		"%s CRT width ratio %.3f of viewport (target >= %.2f, enforced=%s)"
		% [label, width_ratio, TARGET_CRT_WIDTH_RATIO, ENFORCE_CRT_TARGETS]
	)
	assert_true(
		height_ok,
		"%s CRT height ratio %.3f of viewport (target >= %.2f, enforced=%s)"
		% [label, height_ratio, TARGET_CRT_HEIGHT_RATIO, ENFORCE_CRT_TARGETS]
	)
	print("    %s CRT %s -> %.1f%% x %.1f%% of viewport" % [label, crt.size, width_ratio * 100.0, height_ratio * 100.0])


func _assert_dock(shell: Node, viewport_size: Vector2i, label: String) -> void:
	var dock: Control = _find_dock(shell)
	assert_true(dock != null, "%s the module dock is mounted" % label)
	if dock == null:
		return
	assert_true(dock.is_visible_in_tree(), "%s the module dock is visible" % label)
	var shown: int = 0
	var live_bays: int = 0
	var bay_rects: Array[Rect2] = []
	for bay in dock.get_children():
		if bay is Control and bay.is_visible_in_tree() and bay.has_method("show_slot"):
			shown += 1
			bay_rects.append(_bounds(bay))
			if not bool(bay.get("covered")):
				live_bays += 1
	assert_true(live_bays > 0, "%s the dock shows at least one live bay (got %d)" % [label, live_bays])
	var expected: Dictionary = EXPECTED_PROFILE.get(viewport_size, {})
	if expected.has("grid"):
		var grid: Vector2i = expected["grid"]
		assert_eq(shown, grid.x * grid.y, "%s the dock shows a full %dx%d grid of bays" % [label, grid.x, grid.y])
		var rows: Dictionary = {}
		for rect in bay_rects:
			var row_key: int = int(round(rect.position.y))
			rows[row_key] = int(rows.get(row_key, 0)) + 1
		assert_eq(rows.size(), grid.y, "%s bays sit on %d row(s)" % [label, grid.y])
		for row_key in rows:
			assert_eq(int(rows[row_key]), grid.x, "%s each bay row holds %d bays" % [label, grid.x])
	for index in range(bay_rects.size()):
		for other in range(index + 1, bay_rects.size()):
			assert_false(
				bay_rects[index].intersects(bay_rects[other]),
				"%s bays %d and %d do not overlap" % [label, index + 1, other + 1]
			)


func _assert_commit_button(shell: Node, viewport_size: Vector2i, label: String) -> void:
	var button: Control = _find_commit_button(shell)
	assert_true(button != null, "%s the commit button is mounted" % label)
	if button == null:
		return
	assert_true(button.is_visible_in_tree(), "%s the commit button is visible" % label)
	var bounds: Rect2 = _bounds(button)
	var minimum: float = MIN_TOUCH_HANDSET if viewport_size == HANDSET else MIN_TOUCH
	var touchable: bool = bounds.size.x >= minimum and bounds.size.y >= minimum
	assert_true(
		bounds.size.x > 0.0 and bounds.size.y > 0.0 and (touchable or not ENFORCE_MIN_TOUCH),
		"%s the commit button meets the %dpx touch minimum (got %s, enforced=%s)"
		% [label, int(minimum), bounds.size, ENFORCE_MIN_TOUCH]
	)
	if not touchable:
		print("    %s commit button %s is under the %dpx touch minimum" % [label, bounds.size, int(minimum)])


## Every interactive instrument must sit inside the viewport. Decorative
## layers (the backdrop, the chassis art, the frames) are allowed to crop and
## are skipped; so is the overlay root, which is the full viewport by design.
## Nothing may overlap the CRT either: the glass is the one region everything
## else is arranged around.
func _assert_no_clipping(shell: Node, view: Rect2, label: String) -> void:
	var allowed: Rect2 = view.grow(CLIP_SLOP)
	var screen: Control = _find_screen(shell)
	var crt: Rect2 = _bounds(screen).grow(-CLIP_SLOP) if screen != null else Rect2()
	for instrument in _instruments(shell):
		var bounds: Rect2 = _bounds(instrument)
		if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
			continue
		assert_true(
			allowed.encloses(bounds),
			"%s %s stays inside the viewport (bounds %s, viewport %s)"
			% [label, _describe(instrument), bounds, view]
		)
		if screen != null and instrument != screen and not screen.is_ancestor_of(instrument):
			assert_false(
				crt.intersects(bounds),
				"%s %s does not overlap the CRT (bounds %s, CRT %s)"
				% [label, _describe(instrument), bounds, crt]
			)


# --- Locators ----------------------------------------------------------------

func _find_screen(root: Node) -> Control:
	return _find_first(root, func(node: Node) -> bool: return node is CabinetScreen) as Control


func _find_dock(root: Node) -> Control:
	return _find_first(root, func(node: Node) -> bool: return node is ModuleDock) as Control


## The commit control is the one Button on the machine that relabels itself
## through `set_action`; the class it carries is being renamed underneath us.
func _find_commit_button(root: Node) -> Control:
	return _find_first(root, func(node: Node) -> bool:
		return node is Button and node.has_method("set_action") and node.has_method("is_enabled")
	) as Control


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


## The shell's mounted instruments, wherever the tree puts them: the CRT, the
## live bays, the deck switches and lever, the telemetry panels and every
## visible button outside the CRT and the overlays. Anything inside a
## ScrollContainer is skipped: a shelf legitimately runs off its own edge.
func _instruments(shell: Node) -> Array[Control]:
	var found: Array[Control] = []
	_collect_instruments(shell, found, false)
	return found


func _collect_instruments(node: Node, out: Array[Control], in_scroll: bool) -> void:
	if str(node.name) == "OverlayRoot":
		return
	if node is Control and not (node as Control).is_visible_in_tree():
		return
	var scrolled: bool = in_scroll or node is ScrollContainer
	if node is Control and not scrolled and _is_instrument(node as Control):
		out.append(node)
	if node is CabinetScreen:
		# The glass is measured as one instrument; its tabs lay out inside it.
		return
	for child in node.get_children():
		_collect_instruments(child, out, scrolled)


func _is_instrument(control: Control) -> bool:
	if control is CabinetScreen or control is DeckSwitch or control is AbortLever:
		return true
	if control is MultiplierDrum or control is HeatMeter or control is SystemStatus:
		return true
	if control is ModuleBay:
		return not bool(control.get("covered"))
	if control is BaseButton:
		return true
	return false


## Screen-space bounding box of a control, honouring any Node2D skew mount
## above it: the four transformed corners, not `get_global_rect`, which does
## not bound a sheared rectangle.
func _bounds(control: Control) -> Rect2:
	var transform: Transform2D = control.get_global_transform()
	var corners := PackedVector2Array([
		Vector2.ZERO,
		Vector2(control.size.x, 0.0),
		control.size,
		Vector2(0.0, control.size.y),
	])
	var bounds := Rect2(transform * corners[0], Vector2.ZERO)
	for corner in corners:
		bounds = bounds.expand(transform * corner)
	return bounds


func _describe(node: Node) -> String:
	var script: Script = node.get_script()
	var kind: String = str(script.resource_path).get_file().get_basename() if script != null else node.get_class()
	return "%s(%s)" % [kind, node.name]
