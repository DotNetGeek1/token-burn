extends Node

## Where the game is, and the only thing that knows how to change it.
##
## Every screen that is not the desk — the market, the job board, the build
## sheet, the workflows, the records — is a scene in its own right now rather
## than a slab sliding over the room. They used to swap with `change_scene`,
## which on web frees the whole current world while WebGL still has buffers
## bound and kills the canvas. Screens are children of a host this autoload
## owns, so the tree root never tears down. Normal navigation keeps each routed
## screen alive once mounted and only hides/disables it; the web renderer never
## has to destroy the live desk or venue render tree during a route change.
## This also owns everything that has to outlive the screen it was started from:
## the fade over the seam, the phone the investor rings on, the award splash,
## and any round-end report that lands while the player is out of the room.

## Emitted once the new scene is mounted, for anything tracking where the player
## is rather than driving where they go.
signal route_changed(route: String)

## The desk, with the room and the machine in it. Every other route is somewhere
## the player has gone to and can come back from.
const DESK := "desk"

## The desk is the Burn Cabinet now. The old room (`ui/main.tscn`) is kept on
## disk and reachable by its own route while the cabinet is proven out.
const ROUTES := {
	DESK: "res://ui/cabinet/burn_cabinet.tscn",
	"room": "res://ui/main.tscn",
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
## A goto that arrives while a fade is running is kept, not dropped. Dropping
## it is how a round-end walk-home plus a player tap left the fade up and the
## next venue never mounted.
var _queued_route: String = ""
## Reports that arrived while the desk genuinely did not exist (primarily tools
## booting directly into a venue). In the normal game the cached desk remains
## connected to the simulation and receives these itself while hidden.
var _pending_flow: Array[Dictionary] = []
var _theme: Theme = null
var _fade: ColorRect = null
var _overlay_host: Control = null
var _investor_call: Control = null
var _splash: AchievementSplash = null
## Lives under `/root` so Controls get a full viewport the way `current_scene`
## used to. Never freed. Cached routed screens are all children; exactly one is
## visible and processing at a time.
var _screen_host: Node = null
var _screen: Node = null
var _screen_cache: Dictionary = {}


func _ready() -> void:
	_theme = UiThemeBuilder.build()
	_build_layers()
	UiSound.attach(self)
	_connect_flow()
	call_deferred("_adopt_boot_scene")


func _notification(what: int) -> void:
	match what:
		MainLoop.NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if Simulation != null and Simulation.has_method("autosave_now"):
				Simulation.autosave_now()
		NOTIFICATION_APPLICATION_FOCUS_IN, MainLoop.NOTIFICATION_APPLICATION_RESUMED:
			UiSound.resume()
			if not visible_route_ok():
				_recover_visible_route()
			_ask_shell("refresh_all")
		NOTIFICATION_WM_GO_BACK_REQUEST:
			handle_system_back()


## The screen the player is looking at. Playtests and the screenshot tool ask
## this rather than `SceneTree.current_scene`, which points at the persistent host.
func current_screen() -> Node:
	if _screen != null and is_instance_valid(_screen):
		return _screen
	if is_inside_tree():
		return get_tree().current_scene
	return null


func is_switching() -> bool:
	return _switching


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
	if not has_route(route):
		return false
	if _switching:
		_queued_route = route
		return true
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
## because the desk is the project's main scene. Tools/tests need a genuinely
## fresh screen graph, so this is the one path allowed to clear the route cache.
func boot_into(route: String) -> void:
	if not has_route(route):
		return
	_stack.clear()
	_clear_screen_cache()
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
		_reset_fade()
		_drain_queued_route()
		return
	await _fade_to(1.0, FADE_OUT_SECONDS)
	if not is_inside_tree():
		_switching = false
		_reset_fade()
		return
	_suspend_screen(_screen)
	var incoming: Node = _cached_screen(route)
	if incoming == null:
		incoming = packed.instantiate()
		_screen_cache[route] = incoming
	_mount_screen(incoming)
	current = route
	_activate_screen(route, incoming)
	route_changed.emit(route)
	await _fade_to(0.0, FADE_IN_SECONDS)
	_switching = false
	_assert_visible_route(route)
	_drain_queued_route()


func _cached_screen(route: String) -> Node:
	var cached: Variant = _screen_cache.get(route, null)
	if cached is Node and is_instance_valid(cached):
		return cached
	_screen_cache.erase(route)
	return null


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
	_screen_cache[DESK] = boot
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
	if screen is CanvasItem:
		(screen as CanvasItem).visible = true
	screen.process_mode = Node.PROCESS_MODE_INHERIT
	_screen = screen
	if is_inside_tree() and get_tree().current_scene != _screen_host:
		get_tree().current_scene = _screen_host


## Normal route changes deliberately do not free render-bearing screens. On the
## web Compatibility renderer, repeatedly destroying the desk after a round can
## leave a blank canvas without a useful console error. Hiding the root stops
## drawing it and disabling processing makes the cache cheap while preserving
## all render resources for the next visit.
func _suspend_screen(screen: Node) -> void:
	if screen == null or not is_instance_valid(screen):
		return
	if screen.has_method("route_deactivated"):
		screen.call("route_deactivated")
	if screen is CanvasItem:
		(screen as CanvasItem).visible = false
	screen.process_mode = Node.PROCESS_MODE_DISABLED


func _activate_screen(route: String, screen: Node) -> void:
	if screen == null or not is_instance_valid(screen):
		return
	if screen.has_method("route_activated"):
		screen.call("route_activated")
	elif route == DESK:
		_ask_shell("refresh_all")
	elif screen.has_method("refresh"):
		screen.call("refresh")
	# A direct-to-venue tool can still produce reports before a desk has ever
	# existed. Once the desk is active, replay that exceptional backlog.
	if route == DESK and not _pending_flow.is_empty():
		var queued: Array[Dictionary] = _pending_flow.duplicate()
		_pending_flow.clear()
		for entry in queued:
			_replay(entry)


## Test/screenshot booting is allowed to throw away cached screens because it is
## outside normal gameplay navigation. This keeps persona isolation intact while
## the shipped web loop never tears down a route mid-session.
func _clear_screen_cache() -> void:
	for cached in _screen_cache.values():
		if cached is Node and is_instance_valid(cached):
			(cached as Node).queue_free()
	_screen_cache.clear()
	_screen = null


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
		_reset_fade()


func _reset_fade() -> void:
	if _fade == null or not is_instance_valid(_fade):
		return
	_fade.modulate.a = 0.0
	_fade.visible = false
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _drain_queued_route() -> void:
	if _queued_route == "":
		return
	var next: String = _queued_route
	_queued_route = ""
	if next != current:
		goto(next)


## Android system back matches the visible back contract: overlays first, then
## a venue lean-in, then the venue stack, then the desk's own back policy.
func handle_system_back() -> void:
	if _switching:
		return
	if investor_busy():
		hide_investor()
		return
	if current != DESK:
		if _screen != null and is_instance_valid(_screen) and _screen.has_method("handle_system_back"):
			_screen.call("handle_system_back")
		else:
			back()
		return
	_ask_shell("handle_system_back")


## Resume after a fade stuck up, a hidden screen, or a missing cache: drop the
## curtain, remount whatever is still cached (desk if the current route is gone),
## and let the shell re-sync overlays to Simulation.phase.
func _recover_visible_route() -> void:
	_reset_fade()
	_switching = false
	_queued_route = ""
	var route: String = current if has_route(current) else DESK
	var incoming: Node = _cached_screen(route)
	if incoming == null and route != DESK:
		route = DESK
		incoming = _cached_screen(DESK)
	if incoming == null:
		var packed: Variant = load(str(ROUTES[DESK]))
		if packed is PackedScene:
			incoming = packed.instantiate()
			_screen_cache[DESK] = incoming
			route = DESK
	if incoming == null:
		push_error("SceneRouter: could not recover a visible route")
		return
	current = route
	_mount_screen(incoming)
	_activate_screen(route, incoming)
	_assert_visible_route("resume-recover")


func visible_route_ok() -> bool:
	if _fade != null and is_instance_valid(_fade) and _fade.visible and _fade.modulate.a > 0.5:
		return false
	if _screen == null or not is_instance_valid(_screen):
		return false
	if _screen is CanvasItem and not (_screen as CanvasItem).is_visible_in_tree():
		return false
	return true


func _assert_visible_route(context: String) -> void:
	if visible_route_ok():
		return
	push_error("SceneRouter: blank shell after %s (route=%s)" % [context, current])


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

## A cached desk remains connected to the simulation while hidden, so in normal
## gameplay it has already received the debrief/bills signals by the time the
## router walks home. Pending copies are only required when no desk exists yet.
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
	if _cached_screen(DESK) == null:
		_pending_flow.append({"kind": "session", "result": result.duplicate(true)})
	goto(DESK)


func _on_round_statement_ready(statement: Dictionary) -> void:
	if current == DESK:
		return
	if _cached_screen(DESK) == null:
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
