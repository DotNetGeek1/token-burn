extends Node

## Where the game is, and the only thing that knows how to change it.
##
## Every screen that is not the desk — the market, the job board, the build
## sheet, the workflows, the records — is a scene in its own right now rather
## than a slab sliding over the room. They used to swap with `change_scene`,
## which on web frees the whole current world while WebGL still has buffers
## bound and kills the canvas. Screens are children of a host this autoload
## owns, so the tree root never tears down. A swap fades, tears the old tree
## down, then mounts the new one — never both live at once, which overflowed
## the message queue. This also owns everything that has to outlive the screen
## it was started from: the fade over the seam, the phone the investor rings
## on, the award splash, and any round-end report that lands while the player
## is out of the room.

## Emitted once the new scene is mounted, for anything tracking where the player
## is rather than driving where they go.
signal route_changed(route: String)

## The desk, with the room and the machine in it. Every other route is somewhere
## the player has gone to and can come back from.
const DESK := "desk"

const ROUTES := {
	DESK: "res://ui/main.tscn",
	"market": "res://ui/venues/venue_market.tscn",
	"jobs": "res://ui/venues/venue_jobs.tscn",
	"build": "res://ui/venues/venue_build.tscn",
	"workflows": "res://ui/venues/venue_workflows.tscn",
	"menu": "res://ui/venues/venue_menu.tscn",
	"legacy": "res://ui/venues/venue_legacy.tscn",
	"achievements": "res://ui/venues/venue_achievements.tscn",
	"terms": "res://ui/venues/venue_terms.tscn",
}

## Out fast and in slower: leaving is a decision the player already made, and
## arriving somewhere is the half worth watching.
const FADE_OUT_SECONDS := 0.14
const FADE_IN_SECONDS := 0.22

## Layers above every scene. The fade sits over the investor and the splash so a
## switch is a clean cut rather than a card hanging in the middle of it.
const LAYER_OVERLAY := 90
const LAYER_FADE := 110

## How far back `back()` can walk. The desk is always the floor of the stack, so
## this only caps venue-to-venue chains.
const MAX_DEPTH := 8

const INVESTOR_CALL := preload("res://ui/screens/investor_call.tscn")

## Whether the shell has booted once already. `main.tscn` reads this to tell a
## cold start (load the save, show the title) from coming back off a venue.
var booted: bool = false
var current: String = DESK

var _stack: Array[String] = []
var _switching: bool = false
## Reports that arrived while the player was somewhere the shell could not show
## them. Drained by `main.tscn` once it is back on screen.
var _pending_flow: Array[Dictionary] = []
var _theme: Theme = null
var _fade: ColorRect = null
var _overlay_host: Control = null
var _investor_call: Control = null
var _splash: AchievementSplash = null
## Lives under `/root` so Controls get a full viewport the way `current_scene`
## used to. Never freed. The visible screen is its only child.
var _screen_host: Node = null
var _screen: Node = null


func _ready() -> void:
	_theme = UiThemeBuilder.build()
	_build_layers()
	UiSound.attach(self)
	_connect_flow()
	call_deferred("_adopt_boot_scene")


## The screen the player is looking at. Playtests and the screenshot tool ask
## this rather than `SceneTree.current_scene`, which is no longer swapped.
func current_screen() -> Node:
	if _screen != null and is_instance_valid(_screen):
		return _screen
	if is_inside_tree():
		return get_tree().current_scene
	return null


# --- The layers that outlive a scene -----------------------------------------

func _build_layers() -> void:
	var overlay_layer := CanvasLayer.new()
	overlay_layer.name = "RouterOverlayLayer"
	overlay_layer.layer = LAYER_OVERLAY
	add_child(overlay_layer)

	# A Control parented straight to a CanvasLayer has no Control above it to
	# take a rect from, so it is sized against the window by hand. Everything
	# mounted here anchors to this instead of to the viewport.
	_overlay_host = Control.new()
	_overlay_host.name = "RouterOverlays"
	_overlay_host.theme = _theme
	_overlay_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(_overlay_host)

	_investor_call = INVESTOR_CALL.instantiate()
	_overlay_host.add_child(_investor_call)
	_splash = AchievementSplash.mount(_overlay_host)

	var fade_layer := CanvasLayer.new()
	fade_layer.name = "RouterFadeLayer"
	fade_layer.layer = LAYER_FADE
	add_child(fade_layer)

	_fade = ColorRect.new()
	_fade.name = "RouterFade"
	_fade.color = UiThemeBuilder.color("bg")
	_fade.modulate.a = 0.0
	_fade.visible = false
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade)

	get_viewport().size_changed.connect(_size_layers)
	_size_layers()


## Only the two nodes parented straight to a CanvasLayer are sized here. What is
## mounted inside the host anchors to it in the ordinary way, and writing a size
## over anchors is what the engine warns about.
func _size_layers() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	for control in [_overlay_host, _fade]:
		if control == null:
			continue
		control.position = Vector2.ZERO
		control.size = view


func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	if (
		event is InputEventMouseButton
		or event is InputEventKey
		or event is InputEventScreenTouch
	):
		UiSound.unlock()


# --- Navigation --------------------------------------------------------------

func has_route(route: String) -> bool:
	if not ROUTES.has(route):
		return false
	return ResourceLoader.exists(str(ROUTES[route]))


## Sends the player to `route`. Returns false when the game has no such scene,
## so a caller with an older way of showing the same thing can fall back to it
## rather than leaving the press doing nothing.
func goto(route: String) -> bool:
	if _switching or not has_route(route):
		return false
	if route == current:
		# Asking for the screen you are already on is a request to leave it,
		# which is how the notes on the whiteboard behaved as panel tabs.
		if route == DESK:
			return true
		back()
		return true
	if route == DESK:
		_stack.clear()
	else:
		_stack.append(current)
		while _stack.size() > MAX_DEPTH:
			_stack.pop_front()
	_switch_to(route)
	return true


## Starts the router's world from outside it, for tools whose own scene is the
## one being replaced. The game itself never needs this: it boots into the desk
## because the desk is the project's main scene.
func boot_into(route: String) -> void:
	if not has_route(route):
		return
	_stack.clear()
	_switch_to(route)


## Back to wherever the player came from, or the desk if that is unknowable.
func back() -> void:
	if _switching:
		return
	var target: String = _stack.pop_back() if not _stack.is_empty() else DESK
	if not has_route(target):
		target = DESK
	if target == current:
		return
	_switch_to(target)


func go_desk() -> void:
	goto(DESK)


func _switch_to(route: String) -> void:
	_switching = true
	var packed: Variant = load(str(ROUTES[route]))
	if not packed is PackedScene:
		push_warning("SceneRouter: %s is not a scene" % ROUTES[route])
		_switching = false
		return
	await _fade_to(1.0, FADE_OUT_SECONDS)
	if not is_inside_tree():
		_switching = false
		return
	await _teardown_outgoing()
	if not is_inside_tree():
		_switching = false
		return
	var incoming: Node = packed.instantiate()
	_mount_screen(incoming)
	current = route
	_switching = false
	route_changed.emit(route)
	await _fade_to(0.0, FADE_IN_SECONDS)


func _ensure_host() -> void:
	if _screen_host != null and is_instance_valid(_screen_host):
		return
	if not is_inside_tree():
		return
	_screen_host = Node.new()
	_screen_host.name = "ScreenHost"
	get_tree().root.add_child(_screen_host)
	# Godot only allows current_scene to be a direct child of /root. The host
	# holds that pointer; the visible Control lives underneath it.
	get_tree().current_scene = _screen_host


## Pulls the project's boot scene into the host so the first goto does not have
## to `change_scene`. The playtest runner is a different .tscn and is left alone.
func _adopt_boot_scene() -> void:
	if not is_inside_tree():
		return
	var boot: Node = get_tree().current_scene
	if boot == null or not is_instance_valid(boot):
		return
	if boot == _screen_host:
		return
	if boot.scene_file_path != str(ROUTES[DESK]):
		return
	_ensure_host()
	get_tree().current_scene = _screen_host
	_mount_screen(boot)


func _mount_screen(screen: Node) -> void:
	_ensure_host()
	if _screen_host == null or screen == null:
		return
	if screen.get_parent() != _screen_host:
		if screen.get_parent() != null:
			screen.reparent(_screen_host)
		else:
			_screen_host.add_child(screen)
	if screen is Control:
		(screen as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen = screen
	if is_inside_tree() and get_tree().current_scene != _screen_host:
		get_tree().current_scene = _screen_host


## Hide, drain, then free the outgoing screen before the next one is even
## instantiated. Mounting both at once left debrief tweens and layout callbacks
## running against a tree that was already `queue_free`'d.
func _teardown_outgoing() -> void:
	var outgoing: Node = _screen
	if outgoing == null or not is_instance_valid(outgoing):
		return
	if outgoing == _screen_host:
		return
	_quiesce_node(outgoing)
	if is_inside_tree():
		await get_tree().process_frame
	if not is_instance_valid(outgoing):
		if _screen == outgoing:
			_screen = null
		return
	if _screen == outgoing:
		_screen = null
	outgoing.queue_free()
	if is_inside_tree():
		await get_tree().process_frame
	if is_instance_valid(outgoing) and is_inside_tree():
		await get_tree().process_frame


func _quiesce_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_stop_gpu_nodes(node)


func _stop_gpu_nodes(node: Node) -> void:
	if node is GPUParticles2D or node is GPUParticles3D:
		node.emitting = false
		node.visible = false
	elif node is CPUParticles2D or node is CPUParticles3D:
		node.emitting = false
	elif node is SubViewport:
		node.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for child in node.get_children():
		_stop_gpu_nodes(child)


func _fade_to(target: float, seconds: float) -> void:
	if not is_inside_tree() or not is_instance_valid(_fade):
		return
	_size_layers()
	_fade.visible = true
	# The curtain swallows presses while it is up, so a double tap on a nav row
	# cannot start a second switch into the first one's fade.
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP if target > 0.5 else Control.MOUSE_FILTER_IGNORE
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "modulate:a", target, seconds)
	await tween.finished
	if not is_instance_valid(_fade):
		return
	if target <= 0.01:
		_fade.visible = false
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


# --- Named destinations ------------------------------------------------------
#
# The screens ask for a place by name and do not care where it is. Every one of
# these is a venue now; what is left on the desk is the burn lab and the title,
# which are not places and so walk the player home first.

func open_market() -> void:
	goto("market")


func open_jobs() -> void:
	goto("jobs")


func open_build() -> void:
	goto("build")


func open_menu() -> void:
	goto("menu")


func open_workflows() -> void:
	goto("workflows")


func open_legacy() -> void:
	goto("legacy")


func open_achievements() -> void:
	goto("achievements")


func open_terms() -> void:
	goto("terms")


## The burn lab is a debug tool rather than a place, so it stays a modal on the
## desk and asking for it from a venue walks back to the desk first.
func open_burn_lab() -> void:
	_request_on_desk("burn_lab")


func open_title() -> void:
	_request_on_desk("title")


## Every route that is not the desk is somewhere the player went to look at
## something. Working — the machine, the contracts in flight — happens at the
## desk, so anything that starts work comes home.
func open_desk_tab(tab_name: String) -> void:
	if current == DESK:
		_ask_shell("switch_tab", tab_name)
		return
	_pending_flow.append({"kind": "tab", "tab": tab_name})
	goto(DESK)


func _ask_shell(method: String, argument: Variant = null) -> void:
	if not is_inside_tree():
		return
	if argument == null:
		get_tree().call_group("main_ui", method)
	else:
		get_tree().call_group("main_ui", method, argument)


## Queues something only the shell can show and heads for the desk. Doing it on
## the spot would call into a scene that is not on screen.
func _request_on_desk(kind: String) -> void:
	if current == DESK:
		_replay({"kind": kind})
		return
	_pending_flow.append({"kind": kind})
	goto(DESK)


# --- Reports that land while the player is out ------------------------------

## Work runs on while the player is reading the market, so the debrief and the
## bills can both come due in a scene that has no way to print them. They are
## kept here and replayed the moment the desk is back, because the signal that
## carried them will not fire twice.
func _connect_flow() -> void:
	Simulation.work_session_finished.connect(_on_work_session_finished)
	Simulation.round_statement_ready.connect(_on_round_statement_ready)
	EventBus.achievement_unlocked.connect(_on_achievement_unlocked)
	# Taking a contract and starting one are both done with the catalogue, so
	# they hand the window back to the desk.
	EventBus.job_accepted.connect(func(_id: String) -> void: open_desk_tab("work"))
	EventBus.job_started.connect(func(_id: String) -> void: open_desk_tab("board"))
	EventBus.run_ended.connect(_on_run_ended)


func _on_work_session_finished(result: Dictionary) -> void:
	if current == DESK:
		return
	_pending_flow.append({"kind": "session", "result": result.duplicate(true)})
	goto(DESK)


func _on_round_statement_ready(statement: Dictionary) -> void:
	if current == DESK:
		return
	_pending_flow.append({"kind": "statement", "statement": statement.duplicate(true)})
	goto(DESK)


func _on_run_ended(_victory: bool) -> void:
	if current != DESK:
		goto(DESK)


## Awards are the one report that does not need the shell: the splash lives up
## here, so it plays over a venue exactly as it plays over the room.
func _on_achievement_unlocked(achievement_id: String) -> void:
	if _splash != null:
		_splash.enqueue(achievement_id)


## Drained by the shell once it is mounted and has its overlays built.
func take_pending_flow() -> Array[Dictionary]:
	var queued: Array[Dictionary] = _pending_flow.duplicate()
	_pending_flow.clear()
	return queued


func _replay(entry: Dictionary) -> void:
	match str(entry.get("kind", "")):
		"tab":
			_ask_shell("switch_tab", str(entry.get("tab", "work")))
		"title":
			_ask_shell("open_title")
		"burn_lab":
			_ask_shell("open_burn_lab")
		"session":
			_ask_shell("replay_work_session", Dictionary(entry.get("result", {})))
		"statement":
			_ask_shell("replay_statement", Dictionary(entry.get("statement", {})))


# --- The investor -----------------------------------------------------------

## He interrupts anything, anywhere, because he is the only person in the game
## and his phone is not part of whatever screen the player happens to be on.
func investor_says(trigger: String, context: Dictionary = {}) -> void:
	if _investor_call == null:
		return
	_size_layers()
	_investor_call.call_player(trigger, context)


func investor_busy() -> bool:
	return _investor_call != null and _investor_call.visible


## Puts the phone down without the player pressing anything. For the screenshot
## tool, which wants the room underneath a beat he insists on being present for.
func hide_investor() -> void:
	if _investor_call != null:
		_investor_call.hide_overlay()
