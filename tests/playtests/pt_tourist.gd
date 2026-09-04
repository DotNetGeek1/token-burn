extends PlaytestCase

## Opens every screen of the cabinet at both viewport sizes and audits the
## glass: the five CRT tabs from the strip, the maintenance view from the
## MAINT key, and the sheets its menu opens (settings, help, records).
##
## Does not take work or spend cash: a buy or an ACCEPT would change what
## the next screen shows, and this persona exists to prove the screens are
## reachable and readable, not that a run can be won. The handset size is
## the one the compact layout profile reflows for, which is where a button
## most often slides off the panel.

const SHEETS: Array[String] = ["settings", "help", "records"]


func play(harness: UiHarness) -> void:
	await harness.boot(11)
	var driver: UiDriver = harness.driver
	var viewports: Array[Vector2i] = [UiHarness.VIEW_DESKTOP, UiHarness.VIEW_HANDSET]
	for size in viewports:
		await harness.set_viewport(size)
		await harness.go_desk()
		driver.audit_screen("desk-%s" % size.x, "desk")
		# Use the actual tab strip on the cabinet's glass, not the shell API.
		# An overlay that covers the strip would pass direct navigation and
		# still leave the player stuck.
		var shell: Node = harness.current_scene()
		for tab_key in ["contracts", "modules", "market", "perks", "run"]:
			await dismiss_investor(harness)
			await driver.press_command(tab_key)
			assert_true(
				shell != null and shell.has_method("current_tab") and str(shell.current_tab()) == tab_key,
				"The %s tab comes up on the glass at %dpx" % [tab_key, size.x]
			)
			assert_eq(SceneRouter.current, "desk", "The %s tab stays on the cabinet at %dpx" % [tab_key, size.x])
			driver.audit_screen("%s-%s" % [tab_key, size.x], "desk")
		# The MAINT key opens the maintenance view on the cabinet itself; it
		# never leaves the desk route.
		await driver.press_command("maint")
		await settle_camera(harness)
		assert_true(
			shell != null and shell.has_method("is_maintenance") and bool(shell.is_maintenance()),
			"The MAINT key opens the maintenance view at %dpx" % size.x
		)
		assert_eq(SceneRouter.current, "desk", "Maintenance stays on the cabinet at %dpx" % size.x)
		driver.audit_screen("maintenance-%s" % size.x, "desk")
		# Every sheet off the maintenance menu opens over it, reads clean, and
		# closes back to it with system back.
		var layer: MaintenanceLayer = shell.maintenance_layer() if shell != null and shell.has_method("maintenance_layer") else null
		assert_true(layer != null, "The cabinet exposes its maintenance layer at %dpx" % size.x)
		for sheet in SHEETS:
			if layer == null:
				break
			var key: Button = layer.menu_key(sheet)
			assert_true(key != null and key.is_visible_in_tree(), "The %s key is on the maintenance menu at %dpx" % [sheet, size.x])
			if key == null:
				continue
			await driver.press(key)
			await harness.settle()
			assert_true(bool(shell.is_maintenance()), "%s opens over maintenance at %dpx, not instead of it" % [sheet, size.x])
			assert_eq(SceneRouter.current, "desk", "The %s sheet stays on the cabinet at %dpx" % [sheet, size.x])
			driver.audit_screen("%s-%s" % [sheet, size.x], "desk")
			shell.handle_system_back()
			await harness.settle()
			assert_true(bool(shell.is_maintenance()), "Back closes %s and leaves maintenance up at %dpx" % [sheet, size.x])
		await driver.press_command("resume")
		await settle_camera(harness)
		assert_true(
			shell != null and not bool(shell.is_maintenance()),
			"RESUME closes the maintenance view at %dpx" % size.x
		)
		await harness.go_desk()
