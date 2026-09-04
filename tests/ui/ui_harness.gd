class_name UiHarness
extends Node

## Boots the real shell for a playtest and keeps the runner alive across it.
##
## Going anywhere is a `change_scene` now, and that frees `current_scene`. The
## playtest runner nulls that pointer in its own `_ready` so this node — a child
## of the runner, not of the desk — survives every rebuild of the cabinet.
## Isolation is a scratch profile and autosave off: a playtest must never write
## the developer's real `profile.json` or savegame.

const SCRATCH_PROFILE := "user://playtest_profile.json"
const SCRATCH_SAVE := "user://playtest_save.json"
const SHOTS_DIR := "res://build/playtests"

## The supported desktop floor and the landscape handset target. Compact desktop
## remains available for defensive fallback checks, but is not a release target.
const VIEW_DESKTOP := Vector2i(1920, 1080)
const VIEW_COMPACT_DESKTOP := Vector2i(1280, 720)
const VIEW_HANDSET := Vector2i(854, 480)

## Fade out plus fade in, plus a little for the scene's first layout pass.
## Under `time_scale` 12 this is a few frames of wall clock.
const ROUTE_SETTLE_SECONDS := 0.4

## Wall-clock cap so a hung tween fails the persona instead of the suite.
const SETTLE_DEADLINE_MSEC := 8000

var driver: UiDriver
var time_scale: float = 12.0
var shots_enabled: bool = false


func _ready() -> void:
	# A dummy case so locators can run before the runner binds a persona.
	# Each persona replaces this so failures tally on the right TestCase.
	if driver == null:
		driver = UiDriver.new(self, TestCase.new())


## Points meta at a throwaway file and stops the sim writing a save. Campaign
## personas need the meta layer on; isolation is the file, not a disable.
func isolate() -> void:
	MetaProgress.enabled = true
	MetaProgress.use_scratch_profile(SCRATCH_PROFILE)
	SaveManager.use_scratch(SCRATCH_SAVE)
	Simulation.autosave_enabled = false
	Engine.time_scale = time_scale


func reset_profile() -> void:
	MetaProgress.use_scratch_profile(SCRATCH_PROFILE)


## Fresh run, desk on screen, title and investor out of the way. Also the
## teardown between personas: `queue_free` cannot reset a scene the router owns,
## so the next seed boots the desk again and the scratch file is wiped first.
func boot(seed: int = 1) -> void:
	isolate()
	# Headless Godot opens a 64×64 window; canvas stretch then makes a square
	# 1280×1280 viewport. Size it before the desk mounts so layout is real.
	await set_viewport(VIEW_DESKTOP)
	# The desk's first mount starts a run and shows the title unless the
	# router has already booted. Mark it first so our seed is the one that
	# survives, not a second start_run() with no argument.
	SceneRouter.booted = true
	Simulation.start_run(seed)
	SceneRouter.boot_into(SceneRouter.DESK)
	await _wait_for_route(SceneRouter.DESK)
	var shell: Node = current_scene()
	if shell != null and shell.has_method("dismiss_title"):
		shell.dismiss_title()
	SceneRouter.hide_investor()
	await _wait_investor_idle()
	await settle()


func goto_route(route: String) -> void:
	# Desk-on-desk is a no-op in the router and never emits route_changed, so
	# waiting for the signal would sit on the deadline for nothing.
	if route == SceneRouter.current and route == SceneRouter.DESK:
		await settle()
		return
	SceneRouter.goto(route)
	await _wait_for_route(route)


## Shows one tab of the cabinet's glass (`run`, `contracts`, `modules`,
## `market`, `perks`; the old desk-tab and route names are accepted too) and
## waits for the shell to redraw it.
func goto_tab(tab_name: String) -> void:
	if SceneRouter.current != SceneRouter.DESK:
		await go_desk()
	SceneRouter.open_desk_tab(tab_name)
	await settle()


func go_desk() -> void:
	if SceneRouter.current == SceneRouter.DESK:
		await settle()
		return
	SceneRouter.go_desk()
	await _wait_for_route(SceneRouter.DESK)


func set_viewport(size: Vector2i) -> void:
	get_window().size = size
	get_tree().root.content_scale_size = size
	await settle()
	# Every console screen recomputes from the new millimetre scale; a screen
	# that is already up has to be told, or the audit measures the old layout.
	get_tree().call_group("console_screens", "fit_console")
	var scene: Node = current_scene()
	if scene != null and scene.has_method("refresh"):
		scene.refresh()
	get_tree().call_group("main_ui", "refresh_all")
	await settle()


func current_scene() -> Node:
	if not is_inside_tree():
		return null
	var screen: Node = SceneRouter.current_screen()
	if screen != null:
		return screen
	return get_tree().current_scene


## Pump a few frames plus the route fade budget. Tweens from create_tween()
## are RefCounted, not Node children, so there is nothing honest to walk.
func settle(min_frames := 2) -> void:
	if not is_inside_tree():
		return
	for _frame in mini(24, maxi(min_frames, 8)):
		await get_tree().process_frame


func capture(shot_name: String) -> void:
	if not shots_enabled:
		return
	if DisplayServer.get_name() == "headless":
		return
	if not is_inside_tree():
		return
	var texture: ViewportTexture = get_viewport().get_texture()
	var image: Image = texture.get_image() if texture != null else null
	if image == null:
		push_warning("playtest: no frame to capture for %s" % shot_name)
		return
	# globalize: `res://` is not writable outside the editor and fails quiet.
	var safe: String = shot_name.replace("/", "_").replace("\\", "_")
	var path: String = ProjectSettings.globalize_path("%s/%s.png" % [SHOTS_DIR, safe])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: Error = image.save_png(path)
	if err != OK:
		push_warning("playtest: could not write %s (%s)" % [path, err])
		return
	print("captured %s -> %s" % [safe, path])


## Visible ConsoleOverlay whose node name or script path contains the fragment
## (session_summary, month_statement, angel_investors, run_end).
func overlay(name_fragment: String) -> Control:
	var needle: String = name_fragment.to_lower()
	var scene: Node = current_scene()
	if scene != null:
		var on_scene: Control = _find_overlay(scene, needle)
		if on_scene != null:
			return on_scene
	# The investor lives on the router, not on the desk.
	return _find_overlay(SceneRouter, needle)


func visible_overlays() -> Array:
	var found: Array = []
	if not is_inside_tree():
		return found
	for node in get_tree().get_nodes_in_group("flow_overlay"):
		if node is CanvasItem and node.is_visible_in_tree():
			found.append(node)
	return found


func _wait_for_route(route: String) -> void:
	var arrived: bool = SceneRouter.current == route
	var on_changed := func(arrived_route: String) -> void:
		if arrived_route == route:
			arrived = true
	SceneRouter.route_changed.connect(on_changed)
	var deadline: int = Time.get_ticks_msec() + SETTLE_DEADLINE_MSEC
	while Time.get_ticks_msec() < deadline:
		if arrived or SceneRouter.current == route:
			break
		await get_tree().process_frame
	if SceneRouter.route_changed.is_connected(on_changed):
		SceneRouter.route_changed.disconnect(on_changed)
	while SceneRouter.is_switching() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	# A few frames after the signal: the swap is deferred to end-of-frame and
	# the new scene needs a layout pass before anything on it has a real rect.
	# Frames, not a SceneTreeTimer: a timer can sit forever if the tree is
	# mid-change_scene and not processing idle callbacks.
	for _frame in 8:
		await get_tree().process_frame
	await settle()


func _wait_investor_idle() -> void:
	var deadline: int = Time.get_ticks_msec() + SETTLE_DEADLINE_MSEC
	while SceneRouter.investor_busy() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _find_overlay(node: Node, needle: String) -> Control:
	if node == null:
		return null
	if node is Control and _overlay_matches(node, needle):
		if node.is_visible_in_tree():
			return node
	# Hidden overlays are skipped, not their siblings. A closed run_end
	# must not hide the bills sitting next to it.
	var hidden: bool = node is CanvasItem and not node.is_visible_in_tree()
	if hidden and node is Control and _overlay_matches(node, needle):
		return null
	if hidden:
		return null
	for child in node.get_children():
		var found: Control = _find_overlay(child, needle)
		if found != null:
			return found
	return null


func _overlay_matches(node: Node, needle: String) -> bool:
	var compact: String = needle.replace("_", "")
	if str(node.name).to_lower().contains(needle) or str(node.name).to_lower().contains(compact):
		return true
	var script: Script = node.get_script()
	if script != null:
		var path: String = str(script.resource_path).to_lower()
		if path.contains(needle) or path.contains(compact):
			return true
	return false
