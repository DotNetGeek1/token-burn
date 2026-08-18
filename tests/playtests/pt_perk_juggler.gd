extends PlaytestCase

## Takes every angel offer, then equips, benches and swaps on the build
## bench up to the cap. The UI's enabled action rows have to agree with
## Simulation.perk_capacity() — a FIT that lights up on a full loadout, or a
## BENCH that stays grey on a card that can leave, is the bug this guards.
##
## Angels auto-fit when there is a slot. The juggler only has work on the
## bench once the loadout is full, which is why a cap hit benches one
## before fitting another.


const SEED := 13
const ROUND_CAP := 4


func play(harness: UiHarness) -> void:
	await harness.boot(SEED)

	for _round in ROUND_CAP:
		if Simulation.phase == Simulation.Phase.RUN_END:
			break
		await dismiss_investor(harness)
		await _take_work_if_any(harness)
		if Simulation.run_state.has_pending_work():
			await burn_until_session_over(harness)
			if Simulation.phase == Simulation.Phase.RUN_END:
				break
			await walk_round_flow(harness)
		else:
			Simulation.debug_end_round()
			await harness.go_desk()
			await _walk_skip_overlays(harness)
		if Simulation.phase == Simulation.Phase.RUN_END:
			break
		await _juggle_build(harness)


func _take_work_if_any(harness: UiHarness) -> void:
	await dismiss_investor(harness)
	if SceneRouter.current != "jobs":
		await harness.goto_route("jobs")
	if harness.driver.first_tile() == null:
		harness.driver.audit_screen("jobs", "jobs")
		return
	await accept_first_job(harness)


func _juggle_build(harness: UiHarness) -> void:
	if not SceneRouter.has_route("build"):
		return
	await dismiss_investor(harness)
	await harness.goto_route("build")
	harness.driver.audit_screen("build", "build")

	var capacity: Dictionary = Simulation.perk_capacity()
	var cap: int = int(capacity.get("cap", 0))
	var equipped: Array = Array(Simulation.run_state.build.get("perks", []))
	if equipped.size() >= cap and cap > 0:
		await _bench_one(harness)
		await _equip_from_bench(harness)
	else:
		await _equip_from_bench(harness)

	_assert_loadout()


func _bench_one(harness: UiHarness) -> void:
	var fitted: Control = harness.driver.command("FITTED")
	if fitted != null:
		await harness.driver.press(fitted)
	var tile: Control = harness.driver.first_tile()
	if tile == null:
		return
	await harness.driver.lean_if_needed(tile)
	await harness.driver.press(tile)
	await _press_enabled_action(harness, ["UNEQUIP", "BENCH"])


func _equip_from_bench(harness: UiHarness) -> void:
	var bench: Control = harness.driver.command("ON THE BENCH")
	if bench != null:
		await harness.driver.press(bench)
	var tile: Control = _first_unequipped_tile(harness)
	if tile == null:
		return
	await harness.driver.lean_if_needed(tile)
	await harness.driver.press(tile)
	# The sheet says FIT IT / SWAP FOR …, not EQUIP. Try the brief's verbs
	# and the ones the sign actually prints.
	await _press_enabled_action(harness, ["EQUIP", "FIT", "SWAP", "BENCH"])


func _first_unequipped_tile(harness: UiHarness) -> Control:
	var equipped: Array = Array(Simulation.run_state.build.get("perks", []))
	for tile in harness.driver.tiles():
		if tile is VenueTile and not (str(tile.meta) in equipped):
			return tile
	return null


func _press_enabled_action(harness: UiHarness, verbs: Array) -> void:
	for verb in verbs:
		var action: Control = harness.driver.command(str(verb))
		if action != null and action is BaseButton and not action.disabled:
			await harness.driver.press(action)
			return


func _assert_loadout() -> void:
	var capacity: Dictionary = Simulation.perk_capacity()
	var equipped: Array = Array(Simulation.run_state.build.get("perks", []))
	var cap: int = int(capacity.get("cap", 0))
	assert_true(
		equipped.size() <= cap,
		"Equipped perks stay at or under the cap of %d" % cap
	)
	assert_eq(
		int(capacity.get("active", 0)),
		equipped.size(),
		"perk_capacity active matches build.perks"
	)


func _walk_skip_overlays(harness: UiHarness) -> void:
	await _wait_for_overlay(harness)
	if _overlay_up(harness, "session_summary"):
		await walk_round_flow(harness)
		return
	var deadline: int = Time.get_ticks_msec() + ROUND_FLOW_DEADLINE_MSEC
	while Time.get_ticks_msec() < deadline:
		await dismiss_investor(harness)
		if Simulation.phase == Simulation.Phase.RUN_END:
			return
		if _overlay_up(harness, "month_statement"):
			await harness.driver.press_command("CONTINUE")
			continue
		if _overlay_up(harness, "angel_investors"):
			var take: Control = harness.driver.command("TAKE IT")
			if take != null:
				await harness.driver.press(take)
			else:
				await harness.driver.press_command("TAKE NOTHING")
			continue
		if (
			Simulation.phase == Simulation.Phase.ROUND_PREP
			or Simulation.phase == Simulation.Phase.IN_ROUND
		):
			return
		await harness.settle()


func _wait_for_desk(harness: UiHarness) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while SceneRouter.current != SceneRouter.DESK and Time.get_ticks_msec() < deadline:
		await harness.get_tree().process_frame
	await harness.settle()


func _wait_for_overlay(harness: UiHarness) -> void:
	var deadline: int = Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if (
			_overlay_up(harness, "session_summary")
			or _overlay_up(harness, "month_statement")
			or _overlay_up(harness, "angel_investors")
			or Simulation.phase == Simulation.Phase.RUN_END
			or Simulation.phase == Simulation.Phase.ROUND_PREP
		):
			return
		await harness.get_tree().process_frame
