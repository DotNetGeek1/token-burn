extends Node

## Dev tool: boots the main UI, waits a few frames, saves a screenshot, and
## quits. Pass the output path as a user arg:
##   godot --path . res://tools/screenshot_runner.tscn -- --out=user://shot.png

const MAIN_SCENE := "res://ui/main.tscn"


func _ready() -> void:
	var out_path: String = "user://screenshot.png"
	var tab: String = ""
	# Particles and looping tweens run on real time, so shots of the rig need a
	# wall-clock settle before the capture or they land on an empty first frame.
	var settle_seconds: float = 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--tab="):
			tab = arg.trim_prefix("--tab=")
		elif arg.begins_with("--settle="):
			settle_seconds = float(arg.trim_prefix("--settle="))
	Simulation.autosave_enabled = false
	# Stash any real save so screenshots always show a fresh run, then
	# restore it on the way out.
	var stashed := false
	if FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.rename_absolute(SaveManager.SAVE_PATH, SaveManager.SAVE_PATH + ".stash")
		stashed = true
	var main: Control = load(MAIN_SCENE).instantiate()
	add_child(main)
	# The title screen now covers the shell at boot, so every shot except the
	# title's own has to press past it.
	if tab != "title":
		main.dismiss_title()
	if tab == "session":
		# Play one round end to end so the debrief screen shows. Burning is
		# interactive, so this drives it synchronously rather than waiting on a
		# player who is not here. Force the debrief forward and keep bills closed.
		var offers: Array = Simulation.run_state.business.get("job_offers", [])
		if not offers.is_empty():
			Simulation.accept_job(str(offers[0].get("id", "")))
			Simulation.start_work_sync()
		for _f in range(5):
			await get_tree().process_frame
		main._bills_screen.hide()
		main._angel_investors.hide_overlay()
		var summary: Dictionary = Simulation.last_session_summary
		if not summary.is_empty():
			main._round_debrief.show_summary(summary)
	elif tab == "statement":
		# Every round ends in the bills now, so working one contract to
		# resolution is all it takes to open the statement.
		var offers: Array = Simulation.run_state.business.get("job_offers", [])
		if not offers.is_empty():
			Simulation.accept_job(str(offers[0].get("id", "")))
			Simulation.start_work_sync()
		for _f in range(5):
			await get_tree().process_frame
		main._round_debrief.hide()
		main._on_debrief_continue()
		Simulation.decline_offers()
	elif tab == "angel":
		# Angels only call once the round's bills have cleared, so this works the
		# round to resolution and clears debrief + bills. Burning is interactive,
		# so this drives it synchronously rather than waiting on a player who is
		# not here.
		var offers: Array = Simulation.run_state.business.get("job_offers", [])
		if not offers.is_empty():
			Simulation.accept_job(str(offers[0].get("id", "")))
			Simulation.start_work_sync()
		for _f in range(5):
			await get_tree().process_frame
		main._round_debrief.hide()
		main._on_debrief_continue()
		for _f in range(3):
			await get_tree().process_frame
		if main._bills_screen.visible:
			main._bills_screen.hide()
			main._on_bills_continue()
		# Whether a round ends with anything on offer depends on the draw, and
		# a shot of the table is no use when the table is empty.
		if Simulation.pending_choices.is_empty():
			Simulation.phase = Simulation.Phase.ANGEL_ROUND
			Simulation._present_angel_offers()
		main._angel_investors.show_choices()
	elif tab == "debrief":
		# Force a victory so the debrief has a pick to spend.
		MetaProgress.reset_profile()
		Simulation.run_state.calendar["round"] = 12
		Simulation._end_run(true)
		main.refresh_all()
		# Winning also puts him on the phone about it; the shot wanted here is
		# the report underneath the handset.
		main._investor_call.hide_overlay()
	elif tab == "garage":
		# The second room, which the campaign reaches by buying the property.
		# Written onto the run rather than bought, because the shop route also
		# needs the cash and the right order, and the point of the shot is the
		# room the shell has to re-register itself against.
		Simulation.run_state.build["dwelling"] = "garage"
		main.refresh_all()
		settle_seconds = maxf(settle_seconds, 1.6)
	elif tab == "call":
		# The handset held up over the room. He types his lines out at reading
		# speed, so the shot has to wait for the paragraph to finish arriving.
		main.investor_says("terms")
		settle_seconds = maxf(settle_seconds, 1.2)
	elif tab == "achievements":
		# A scratch profile rather than the developer's own, with a couple of
		# awards earned so the shot shows both states side by side.
		MetaProgress.use_scratch_profile("user://profile_screenshot.json")
		for achievement_id in ["ach.round_one_wipeout", "ach.first_contract", "ach.nothing_ventured"]:
			MetaProgress.grant_achievement(achievement_id)
		main.open_achievements()
	elif tab == "workflows":
		# The editor is only meaningful mid-run, and the second workflow is
		# granted outright so the shot shows the tabs rather than a single one.
		var offers: Array = Simulation.run_state.business.get("job_offers", [])
		for offer in offers:
			if Simulation.accept_job(str(offer.get("id", ""))):
				break
		Simulation.start_work()
		Simulation.run_state.build["workflow_capacity"] = 2
		Simulation.create_workflow("The Careful One")
		Simulation.set_active_workflow(0)
		main.open_pipeline_editor()
		main.refresh_all()
	elif tab == "assign":
		# The work screen with a choice of pipeline to route the contract
		# through, which only appears once a run owns more than one.
		var offers: Array = Simulation.run_state.business.get("job_offers", [])
		for offer in offers:
			if Simulation.accept_job(str(offer.get("id", ""))):
				break
		Simulation.start_work()
		Simulation.run_state.build["workflow_capacity"] = 2
		Simulation.create_workflow("The Careful One")
		main.switch_tab("board")
		main.refresh_all()
	elif tab == "achievement_splash":
		MetaProgress.use_scratch_profile("user://profile_screenshot.json")
		main._on_achievement_unlocked("ach.round_one_wipeout")
		# The splash drops in, punches its icon and throws sparks over about a
		# second of wall clock, so the shot has to wait for the celebration
		# rather than catch the frame the card was still above the screen.
		settle_seconds = maxf(settle_seconds, 0.9)
	elif tab.begins_with("queued") or tab.begins_with("risky"):
		# Accept contracts so round-load feedback is visible. "risky" takes a
		# second contract to push the round over throughput capacity.
		var wanted: int = 2 if tab.begins_with("risky") else 1
		for _n in range(wanted):
			var offers: Array = Simulation.run_state.business.get("job_offers", [])
			for offer in offers:
				if Simulation.accept_job(str(offer.get("id", ""))):
					break
		main.switch_tab("office" if tab.ends_with("office") else "jobs")
		main.refresh_all()
	elif tab == "surged" or tab == "deliver" or tab == "burning" or tab == "jobsheet":
		# Deck states that need a live contract plus something the player did to
		# it: "surged" arms both one-batch surges so the deck's lamps are lit,
		# "deliver" opens the ship-or-abandon sheet, "jobsheet" opens the brief.
		var offers: Array = Simulation.run_state.business.get("job_offers", [])
		for offer in offers:
			if Simulation.accept_job(str(offer.get("id", ""))):
				break
		Simulation.start_work()
		main.switch_tab("board")
		main.refresh_all()
		for _f in range(3):
			await get_tree().process_frame
		var board: Control = main._screen_cache["board"]
		if tab == "surged":
			Simulation.boost()
			# Bursting needs an account, which a fresh run does not have.
			Simulation.run_state.build["upgrades"].append(Simulation.CLOUD_ACCOUNT_UPGRADE)
			Simulation.cloud_burst()
			main.refresh_all()
		elif tab == "deliver":
			board._on_deliver()
		elif tab == "jobsheet":
			board._on_job_details()
		else:
			# Deliberately not awaited: the batch animation has to still be
			# running when the capture happens, which is the only time the kill
			# key is on the deck.
			board._on_burn()
	elif tab.begins_with("rig"):
		# The workstation art is chosen from the hardware the run owns, so each tier
		# needs its own shot: "rig3" is two machines, "rig4" a rack, "rig5" a
		# datacentre. Written straight onto the run rather than bought, because the
		# shop route also needs a dwelling, the cash and the right order. Two
		# contracts are taken so the extra monitors have lanes to report.
		var fleet: Array = ["used_laptop", "custom_desktop"]
		if tab == "rig4":
			fleet.append("gpu_rack")
		elif tab == "rig5":
			fleet.append("garage_datacentre")
		Simulation.run_state.build["hardware"] = fleet
		# Queued directly rather than through `accept_job`, which refuses a second
		# contract whose combined throughput a fresh run cannot promise. The point
		# of the shot is the second lane, so the slate is stacked on purpose.
		var offers: Array = Array(Simulation.run_state.business.get("job_offers", []))
		for index in range(mini(2, offers.size())):
			Simulation.run_state.business["job_queue"].append(offers[index].duplicate(true))
		Simulation.start_work()
		main.switch_tab("board")
		main.refresh_all()
	elif tab == "hot" or tab == "working":
		# Puts a live contract on the bench so the board is in its working state.
		# "hot" also drives heat past the throttle line, which is the only way to
		# see the rig smoking, on fire and sounding its beacon.
		var offers: Array = Simulation.run_state.business.get("job_offers", [])
		for offer in offers:
			if Simulation.accept_job(str(offer.get("id", ""))):
				break
		Simulation.start_work()
		if tab == "hot":
			var capacity: float = float(Simulation.run_state.compute.get("heat_capacity", 100.0))
			Simulation.run_state.compute["heat"] = capacity * 0.97
			Simulation.run_state.flags["fire_risk"] = true
		main.switch_tab("board")
		main.refresh_all()
	elif tab == "market_hardware" or tab == "market_stocked":
		# The Market opens on the property ladder, so the hardware counter — with
		# the installed list and the floor-space readout — needs pressing to.
		# "market_stocked" also fills a garage, so the sell actions and the
		# owned-count pricing are on screen rather than only reachable by play.
		if tab == "market_stocked":
			Simulation.run_state.economy["cash"] = 200000.0
			for upgrade_id in [
				"upgrade.garage", "upgrade.custom_desktop", "upgrade.custom_desktop",
				"upgrade.second_gpu", "upgrade.laptop_ram",
			]:
				Simulation.buy_upgrade(upgrade_id)
		main.switch_tab("market")
		main.refresh_all()
		for _f in range(3):
			await get_tree().process_frame
		main._screen_cache["market"]._on_tab_pressed("hardware")
	elif tab != "":
		main.switch_tab(tab)
	for _i in range(20):
		await get_tree().process_frame
	if settle_seconds > 0.0:
		await get_tree().create_timer(settle_seconds).timeout
	# Count-up animations advance per frame, and this tool runs uncapped, so
	# jump them to their final value instead of waiting an unknown number of
	# frames for a number that would otherwise be caught mid-tween.
	_settle_numbers(main)
	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(out_path)
	if stashed:
		DirAccess.rename_absolute(SaveManager.SAVE_PATH + ".stash", SaveManager.SAVE_PATH)
	print("Saved screenshot to %s" % out_path)
	get_tree().quit()


func _settle_numbers(node: Node) -> void:
	if node is NumberLabel:
		node.skip_animation()
	for child in node.get_children():
		_settle_numbers(child)
