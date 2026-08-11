extends Node

## Boots the shell, walks it through a location, and writes a screenshot per
## room. Used to eyeball whether the readouts land on the furniture the artwork
## painted; not part of the game or the test suite.

const MAIN := preload("res://ui/main.tscn")


func _ready() -> void:
	var rooms: Array = ["bedroom", "garage", "moon_facility"]
	if OS.get_cmdline_user_args().size() > 0:
		rooms = OS.get_cmdline_user_args()
	var shell: Control = MAIN.instantiate()
	add_child(shell)
	await get_tree().process_frame
	shell.dismiss_title()
	shell.switch_tab("office")
	await get_tree().create_timer(1.0).timeout
	for room in rooms:
		Simulation.run_state.build["dwelling"] = str(room)
		shell.refresh_all()
		# A save loaded mid-flow puts a debrief or an investor over the room, and
		# the room is the whole point of the shot.
		var overlays: Node = shell.get_node_or_null("OverlayRoot")
		if overlays != null:
			overlays.visible = false
		await get_tree().create_timer(0.2).timeout
		# The room reveal fades the chrome out and back; wait it out.
		await get_tree().create_timer(1.8).timeout
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png("res://tools/shot_%s.png" % str(room))
		print("captured %s" % str(room))
	# The burn console is the other half of the laptop, so it gets a shot of its
	# own in whichever room the walk ended in. A contract has to be on the bench
	# for it, because an idle board shows none of the commands that made the
	# console overflow in the first place.
	Simulation.ensure_job_offers()
	var offers: Array = Simulation.run_state.business.get("job_offers", [])
	if not offers.is_empty():
		Simulation.accept_job(str(Dictionary(offers[0]).get("id", "")))
		Simulation.start_work()
	shell.switch_tab("board")
	shell.refresh_all()
	var overlay_root: Node = shell.get_node_or_null("OverlayRoot")
	if overlay_root != null:
		overlay_root.visible = false
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png("res://tools/shot_burn.png")
	print("captured burn")
	get_tree().quit()
