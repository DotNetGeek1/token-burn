extends PlaytestCase

## Unlock visibility for the module expansion: Legacy explains why a card is
## still gated, and a banked victory that crosses 1/2/3/5 (or Hard 1/3) prints
## the newly Market-eligible names on the run report.


func play(harness: UiHarness) -> void:
	await harness.boot(91)
	# Boot isolates onto the shared playtest profile. Wipe it again so a prior
	# persona cannot leave victories that open every module.
	MetaProgress.use_scratch_profile(UiHarness.SCRATCH_PROFILE)
	assert_eq(MetaProgress.victories(), 0, "Playtest profile starts with no wins")

	await _legacy_modules_shelf(harness)
	await _run_end_victory_notice(harness)


func _legacy_modules_shelf(harness: UiHarness) -> void:
	await harness.goto_route("legacy")
	var venue: Node = harness.current_scene()
	assert_true(venue != null and venue.has_method("venue_key"), "Legacy venue is open")
	assert_eq(str(venue.venue_key()), "legacy", "The Legacy route lands on the archive")

	assert_true(venue._counter_rows.has("modules"), "Legacy exposes a Modules shelf")
	venue._on_counter_pressed("modules")
	await harness.settle()

	assert_eq(venue._shelf, "modules", "Modules shelf is selected")
	assert_eq(
		venue._shelf_size("modules"),
		ContentDatabase.modules.size(),
		"Modules shelf lists the whole catalogue"
	)

	var locked_module: ModuleDefinition = null
	for module in ContentDatabase.modules:
		if not ContentDatabase.module_is_unlocked(module):
			locked_module = module
			break
	assert_true(locked_module != null, "A fresh profile still has locked modules")
	var entry: Dictionary = venue._module_entry(locked_module)
	assert_eq(str(entry.get("status", "")), "LOCKED", "Locked modules print LOCKED")
	var spec: String = str(entry.get("spec", ""))
	assert_true(
		spec.contains("Win ")
		or spec.contains("Hard")
		or spec.contains("achievement")
		or spec.contains("Requires "),
		"Locked module cards print a combined unmet requirement"
	)
	assert_eq(str(entry.get("unit", "")), "rarity", "Module cards keep rarity on the figure line")

	var locked_tile: VenueTile = null
	for tile in venue._board._tiles:
		if not tile.visible:
			continue
		if str(tile._status.text).contains("LOCKED"):
			locked_tile = tile
			break
	assert_true(locked_tile != null, "The Modules board renders at least one locked tile")
	harness.driver.audit_screen("legacy-modules", "legacy")
	await harness.go_desk()


func _run_end_victory_notice(harness: UiHarness) -> void:
	MetaProgress.use_scratch_profile(UiHarness.SCRATCH_PROFILE)
	assert_eq(MetaProgress.victories(), 0, "Scratch profile starts with no wins")
	MetaProgress.bank_victory(0, "normal")
	assert_eq(MetaProgress.victories(), 1, "Banked the first win for the notice")

	var unlocked: Array[ModuleDefinition] = ContentDatabase.modules_unlocked_at_victory_counts(
		MetaProgress.victories(), MetaProgress.victories_on("hard")
	)
	assert_true(not unlocked.is_empty(), "First victory unlocks at least one module")

	Simulation.debug_end_run(true, "ascended")
	await harness.go_desk()
	await ensure_run_end_overlay(harness)
	await _wait_for_run_end(harness)

	var overlay: Control = harness.overlay("run_end")
	assert_true(overlay != null and overlay.visible, "Run report is up after a win")
	# Force the victory note path even if the shell treated this as a mid-campaign
	# chapter clear with no earned-pick flag.
	overlay._earned_this_run = true
	overlay.refresh()
	await harness.settle()

	var note: String = str(overlay._statement._note.text)
	assert_true(
		note.contains("NEW MODULES CAN APPEAR IN THE MARKET"),
		"Victory note announces modules unlocked for the Market"
	)
	assert_true(
		note.contains(unlocked[0].name),
		"Victory note names at least one newly unlocked module"
	)
	harness.driver.audit_screen("run-end-module-unlock")

	if harness.driver.command("TITLE SCREEN") != null:
		var title_row: Control = harness.driver.command("TITLE SCREEN")
		if title_row is BaseButton and title_row.disabled:
			if harness.driver.command("NEW RUN") != null:
				await harness.driver.press_command("NEW RUN")
		else:
			await harness.driver.press_command("TITLE SCREEN")
	elif harness.driver.command("NEW RUN") != null:
		await harness.driver.press_command("NEW RUN")


func _wait_for_run_end(harness: UiHarness) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		await dismiss_investor(harness)
		if _overlay_up(harness, "month_statement"):
			await harness.driver.press_command("CONTINUE")
			continue
		if _overlay_up(harness, "session_summary"):
			await harness.driver.press_command("CONTINUE")
			continue
		if _overlay_up(harness, "run_end"):
			return
		await harness.settle()
	harness.driver.assert_overlay_visible("run_end")
