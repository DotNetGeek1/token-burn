extends Node

## Boots the Burn Cabinet, walks it through every CRT tab and the maintenance
## view, and writes a screenshot of each. Used to eyeball the shell at a
## window size; not part of the game or the test suite.
##
## The walk cannot live on this node: the router adopts the boot scene and
## hosts the cabinet under its own screen host, so the driver is parented to
## the window root instead, where the router itself lives.
##
##     godot tools/screenshot.tscn -- market maintenance
##     godot tools/screenshot.tscn -- run phone
##
## `phone` shrinks the window to a landscape handset, which is the compact
## layout profile; every tab has two layouts and a shot of one proves nothing
## about the other.

## Enough in hand that the market's shelves are not uniformly out of reach, which
## tells you nothing about the layout.
const SHOP_FLOAT := 250000.0

## The landscape handset target.
const PHONE_SIZE := Vector2i(854, 480)

## More perks than the loadout can hold, so the perks tab has both a full rack
## and a bench to show.
const PERK_STOCK := 6

## More modules than a starting pipeline has slots, for the same reason.
const MODULE_STOCK := 8

const TABS := ["run", "contracts", "modules", "market", "perks"]
const STOPS := TABS + ["maintenance", "settings", "records"]


## Runs the walk from outside the scene being photographed.
class Walker:
	extends Node

	var stops: Array = []
	var phone: bool = false

	## Started from here rather than by the caller, because the caller adds this
	## deferred and nothing can be awaited until it is actually in the tree.
	func _ready() -> void:
		walk()

	func walk() -> void:
		if phone:
			DisplayServer.window_set_size(PHONE_SIZE)
			await _settle(0.4)
		SceneRouter.booted = true
		Simulation.start_run()
		Simulation.run_state.economy["cash"] = SHOP_FLOAT
		_take_contract()
		Simulation.ensure_job_offers()
		_stock_perks()
		_stock_modules()
		SceneRouter.boot_into(SceneRouter.DESK)
		await _settle(1.2)
		get_tree().call_group("main_ui", "dismiss_title")
		SceneRouter.hide_investor()
		await _settle(0.6)
		var suffix: String = "_phone" if phone else ""
		for stop in stops:
			var shell: Node = SceneRouter.current_screen()
			if shell == null:
				break
			match str(stop):
				"maintenance":
					shell.call("enter_maintenance")
					await _settle(1.2)
					_capture("maintenance%s" % suffix)
					shell.call("exit_maintenance")
					await _settle(1.0)
				"settings", "records":
					shell.call("enter_maintenance")
					await _settle(1.0)
					var layer: Node = shell.call("maintenance_layer")
					if layer != null:
						layer.emit_signal("menu_pressed", str(stop))
					await _settle(0.6)
					_capture("%s%s" % [str(stop), suffix])
					shell.call("handle_system_back")
					await _settle(0.3)
					shell.call("exit_maintenance")
					await _settle(1.0)
				_:
					shell.call("switch_tab", str(stop))
					get_tree().call_group("main_ui", "refresh_all")
					await _settle(0.9)
					_capture("tab_%s%s" % [str(stop), suffix])
		get_tree().quit()

	## A fresh run owns no perks, and an empty rack says nothing about how the
	## perks tab lays one out. Handed straight into the inventory rather than
	## drafted, because what is wanted is a populated screen and not a fair draw.
	func _stock_perks() -> void:
		var inventory: Array = Simulation.run_state.build["perk_inventory"]
		for perk in ContentDatabase.perks:
			if inventory.size() >= PERK_STOCK:
				break
			if not (perk.id in inventory):
				inventory.append(perk.id)
		for perk_id in inventory:
			Simulation.equip_perk(str(perk_id))

	## Extra modules, handed over without placing them, so the modules tab has a
	## bin under its dock.
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
	# The router adopts whatever scene Godot booted into only when it is the
	# cabinet; this tool is not, so it gets out of the way the same way the
	# playtest runner does.
	get_tree().current_scene = null
	Simulation.autosave_enabled = false
	var walker := Walker.new()
	walker.name = "ScreenshotWalker"
	walker.stops = STOPS
	var wanted: PackedStringArray = OS.get_cmdline_user_args()
	if wanted.size() > 0:
		# Named targets only, so a single stop can be re-shot in a couple of
		# seconds rather than after the whole tour.
		walker.stops = []
		for arg in wanted:
			if str(arg) == "phone":
				walker.phone = true
			elif STOPS.has(str(arg)):
				walker.stops.append(str(arg))
		if walker.stops.is_empty():
			walker.stops = STOPS
	# Deferred because the window root is still setting up its own children while
	# this scene's _ready is running.
	get_tree().root.add_child.call_deferred(walker)
