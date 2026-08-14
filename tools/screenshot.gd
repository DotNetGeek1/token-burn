extends Node

## Boots the game, walks it through the rooms and then through the venues, and
## writes a screenshot of each. Used to eyeball whether the readouts land on the
## furniture the artwork painted; not part of the game or the test suite.
##
## The walk cannot live on this node. Going anywhere is a real scene change now,
## and a scene change frees the current scene — which is this tool. So the driver
## is parented to the window root instead, where the router itself lives, and
## survives every switch it asks for.
##
##     godot tools/screenshot.tscn -- market jobs
##     godot tools/screenshot.tscn -- jobs phone
##
## `phone` shrinks the window until `ConsoleMetrics` calls for the reflow, which
## is the only way to see the layout a handset actually gets. Every venue has two
## and a shot of one of them proves nothing about the other.

## Enough in hand that the market's shelves are not uniformly out of reach, which
## tells you nothing about the layout.
const SHOP_FLOAT := 250000.0

## Narrow enough that a design pixel falls under the millimetre target on a
## desktop monitor, which puts the venues into console mode on the same machine
## the desktop shots were taken on.
const PHONE_SIZE := Vector2i(430, 900)

## More perks than the loadout can hold, so the build venue has both a full rack
## and a bench to show.
const PERK_STOCK := 6

## More modules than a starting pipeline has slots, for the same reason.
const MODULE_STOCK := 8

const ROOMS := ["bedroom", "garage", "moon_facility"]
const VENUES := ["market", "jobs", "build", "workflows", "menu", "legacy", "achievements", "terms"]


## Runs the walk from outside the scene being photographed.
class Walker:
	extends Node

	var rooms: Array = []
	var venues: Array = []
	var phone: bool = false

	## Started from here rather than by the caller, because the caller adds this
	## deferred and nothing can be awaited until it is actually in the tree.
	func _ready() -> void:
		walk()

	func walk() -> void:
		if phone:
			DisplayServer.window_set_size(PHONE_SIZE)
			await _settle(0.4)
		SceneRouter.boot_into(SceneRouter.DESK)
		await _settle(1.2)
		get_tree().call_group("main_ui", "dismiss_title")
		get_tree().call_group("main_ui", "switch_tab", "office")
		await _settle(1.0)

		for room in rooms:
			Simulation.run_state.build["dwelling"] = str(room)
			get_tree().call_group("main_ui", "refresh_all")
			_hide_desk_overlays()
			# The room reveal fades the chrome out and back; wait it out.
			await _settle(2.0)
			_capture("room_%s" % str(room))

		await _capture_burn()
		await _capture_venues()
		get_tree().quit()

	## The burn console is the other half of the laptop, so it gets a shot of its
	## own. A contract has to be on the bench for it, because an idle board shows
	## none of the commands that made the console overflow in the first place.
	func _capture_burn() -> void:
		_take_contract()
		Simulation.start_work()
		get_tree().call_group("main_ui", "switch_tab", "board")
		get_tree().call_group("main_ui", "refresh_all")
		_hide_desk_overlays()
		await _settle(0.9)
		_capture("burn")

	## The venues are all shot from the state a player is in when they walk into
	## one: between rounds, with money to spend and one contract already taken, so
	## the market has reachable shelves and the job board has both of its shelves
	## stocked. The burn shot left the run mid-work, where every offer reads "BUSY"
	## and the shot says nothing about the layout.
	func _capture_venues() -> void:
		Simulation.start_run()
		Simulation.run_state.economy["cash"] = SHOP_FLOAT
		_take_contract()
		Simulation.ensure_job_offers()
		_stock_perks()
		_stock_modules()
		for venue in venues:
			if not SceneRouter.has_route(str(venue)):
				print("skipped %s — no scene" % str(venue))
				continue
			SceneRouter.goto(str(venue))
			# Long enough for the router's fade in and the venue's second layout
			# pass, which is the one that has real widths to measure against.
			await _settle(1.2)
			var suffix: String = "_phone" if phone else ""
			_capture("venue_%s%s" % [str(venue), suffix])
			# And again with something picked. Half of these screens is the sheet
			# that opens on a selection, and it carries the only button that does
			# anything — shooting only the resting state hid an accept row that
			# had been pushed off the side of the window.
			if await _select_first():
				_capture("venue_%s_detail%s" % [str(venue), suffix])
			SceneRouter.go_desk()
			await _settle(0.9)

	## Picks the first thing on the venue's board, if it has one that can be
	## picked. Returns whether anything was selected.
	func _select_first() -> bool:
		var venue: Node = get_tree().current_scene
		if venue == null or not venue.has_method("_on_tile_selected"):
			return false
		var board: VenueBoard = _find_board(venue)
		if board == null:
			return false
		for tile in board.find_children("*", "VenueTile", true, false):
			if not tile.is_visible_in_tree():
				continue
			var meta: Variant = tile.meta
			if meta == null:
				continue
			board.select(meta)
			venue._on_tile_selected(meta)
			await _settle(0.8)
			return true
		return false

	func _find_board(node: Node) -> VenueBoard:
		for child in node.get_children():
			if child is VenueBoard and child.is_visible_in_tree():
				return child
			var found: VenueBoard = _find_board(child)
			if found != null:
				return found
		return null

	## A fresh run owns no perks, and an empty build sheet says nothing about how
	## the build venue lays one out. Handed straight into the inventory rather than
	## drafted, because what is wanted is a populated screen and not a fair draw:
	## enough to fill the loadout and leave some on the bench, which is the state
	## where the swap wording appears.
	func _stock_perks() -> void:
		var inventory: Array = Simulation.run_state.build["perk_inventory"]
		for perk in ContentDatabase.perks:
			if inventory.size() >= PERK_STOCK:
				break
			if not (perk.id in inventory):
				inventory.append(perk.id)
		for perk_id in inventory:
			Simulation.equip_perk(str(perk_id))

	## Extra modules, handed over without placing them, so the workflow venue has a
	## bench under its pipeline. A starting run owns just enough to fill its slots,
	## which is the one state where the placing half of that screen is invisible.
	func _stock_modules() -> void:
		var owned: Array = Array(Simulation.run_state.build.get("modules", []))
		for module in ContentDatabase.modules:
			if owned.size() >= MODULE_STOCK:
				break
			if not (module.id in owned):
				owned.append(module.id)
		Simulation.run_state.build["modules"] = owned

	func _take_contract() -> void:
		Simulation.ensure_job_offers()
		var offers: Array = Simulation.run_state.business.get("job_offers", [])
		if offers.is_empty():
			return
		Simulation.accept_job(str(Dictionary(offers[0]).get("id", "")))

	## A save loaded mid-flow puts a debrief or an investor over the room, and the
	## room is the whole point of the shot.
	func _hide_desk_overlays() -> void:
		var shell: Node = get_tree().current_scene
		if shell == null:
			return
		var overlays: Node = shell.get_node_or_null("OverlayRoot")
		if overlays != null:
			overlays.visible = false

	func _settle(seconds: float) -> void:
		await get_tree().create_timer(seconds).timeout

	## Written through a globalised path rather than `res://`, which is not
	## writable outside the editor and fails without saying so.
	func _capture(name: String) -> void:
		var texture: ViewportTexture = get_viewport().get_texture()
		var image: Image = texture.get_image() if texture != null else null
		if image == null:
			push_warning("screenshot: no frame to capture for %s" % name)
			return
		var path: String = ProjectSettings.globalize_path(
			"res://tools/shots/shot_%s.png" % name
		)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var err: Error = image.save_png(path)
		if err != OK:
			push_warning("screenshot: could not write %s (%s)" % [path, err])
			return
		print("captured %s -> %s" % [name, path])


func _ready() -> void:
	var walker := Walker.new()
	walker.name = "ScreenshotWalker"
	walker.rooms = ROOMS
	walker.venues = VENUES
	var wanted: PackedStringArray = OS.get_cmdline_user_args()
	if wanted.size() > 0:
		# Named targets only, so a single venue can be re-shot in a couple of
		# seconds rather than after the whole tour.
		walker.rooms = []
		walker.venues = []
		for arg in wanted:
			if str(arg) == "phone":
				walker.phone = true
			elif ROOMS.has(str(arg)):
				walker.rooms.append(str(arg))
			else:
				walker.venues.append(str(arg))
	# Deferred because the window root is still setting up its own children while
	# this scene's _ready is running.
	get_tree().root.add_child.call_deferred(walker)
