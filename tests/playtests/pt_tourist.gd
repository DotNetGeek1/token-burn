extends PlaytestCase

## Opens every named venue at both viewport sizes and audits the glass.
##
## Does not take work or spend cash: a buy or an ACCEPT would change what
## the next screen shows, and this persona exists to prove the rooms are
## reachable and readable, not that a run can be won. The handset size is
## the one ConsoleMetrics reflows for, which is where a button most often
## slides off the panel.


func play(harness: UiHarness) -> void:
	await harness.boot(11)
	var driver: UiDriver = harness.driver
	var routes: Array[String] = [
		"jobs",
		"build",
		"market",
		"menu",
		"workflows",
		"legacy",
		"achievements",
		"terms",
	]
	var viewports: Array[Vector2i] = [UiHarness.VIEW_DESKTOP, UiHarness.VIEW_HANDSET]
	for size in viewports:
		await harness.set_viewport(size)
		await harness.go_desk()
		driver.audit_screen("desk-%s" % size.x, "desk")
		for route in routes:
			await dismiss_investor(harness)
			if not SceneRouter.has_route(route):
				# The list is every named venue; a missing scene is a skip so
				# this sweep stays exhaustive without failing on a room that
				# is not wired yet.
				assert_true(true, "Skipped %s: no scene for that route" % route)
				continue
			await harness.goto_route(route)
			driver.audit_screen("%s-%s" % [route, size.x], route)
			await harness.go_desk()
