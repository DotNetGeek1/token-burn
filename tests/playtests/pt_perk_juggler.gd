extends PlaytestCase

## Takes every angel offer, then fits, benches and swaps on the PERKS tab up
## to the cap. The commit button has to agree with Simulation.perk_capacity()
## — a FIT that lights up on a full rack, or a BENCH that stays grey on a card
## that can leave, is the bug this guards.
##
## Angels auto-fit when there is a slot. The juggler only has work on the
## bench once the rack is full, which is why a cap hit benches one before
## fitting another.


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
		await _juggle_perks(harness)


func _take_work_if_any(harness: UiHarness) -> void:
	await dismiss_investor(harness)
	if Array(Simulation.run_state.business.get("job_offers", [])).is_empty():
		return
	await accept_first_job(harness)


## The PERKS tab: pick a card, read the commit. FIT on a bench card, BENCH on
## a fitted one, each enabled exactly when the simulation says so.
func _juggle_perks(harness: UiHarness) -> void:
	await dismiss_investor(harness)
	var shell: Node = harness.current_scene()
	if shell == null or not shell.has_method("switch_tab"):
		return
	shell.switch_tab("perks")
	await harness.settle()
	harness.driver.audit_screen("perks", "desk")
	var tab: Node = _perks_tab(shell)
	assert_true(tab != null and tab.has_method("select_perk"), "The PERKS tab is up and exposes select_perk")
	if tab == null:
		return

	var capacity: Dictionary = Simulation.perk_capacity()
	var cap: int = int(capacity.get("cap", 0))
	var fitted: Array = Array(Simulation.run_state.build.get("perks", []))
	if fitted.size() >= cap and cap > 0:
		await _bench_one(harness, shell, tab)
		await _fit_from_bench(harness, shell, tab)
	else:
		await _fit_from_bench(harness, shell, tab)

	_assert_loadout()
	shell.switch_tab("run")
	await harness.settle()


func _bench_one(harness: UiHarness, shell: Node, tab: Node) -> void:
	var fitted: Array = Array(Simulation.run_state.build.get("perks", []))
	if fitted.is_empty():
		return
	var perk_id: String = str(fitted[0])
	assert_true(bool(tab.call("select_perk", perk_id)), "A fitted perk can be picked on the rack")
	shell.refresh_all()
	await harness.settle()
	await _commit_agrees(harness, "BENCH", Simulation.can_bench_perk(perk_id))


func _fit_from_bench(harness: UiHarness, shell: Node, tab: Node) -> void:
	var fitted: Array = Array(Simulation.run_state.build.get("perks", []))
	var bench: String = ""
	for perk_id in Array(Simulation.run_state.build.get("perk_inventory", [])):
		if not (str(perk_id) in fitted):
			bench = str(perk_id)
			break
	if bench == "":
		return
	assert_true(bool(tab.call("select_perk", bench)), "A benched perk can be picked")
	shell.refresh_all()
	await harness.settle()
	await _commit_agrees(harness, "FIT", Simulation.can_equip_perk(bench))


## The commit reads `verb`, is enabled exactly when the simulation allows the
## move, and a press does the move.
func _commit_agrees(harness: UiHarness, verb: String, allowed: bool) -> void:
	var button: Control = harness.driver.command(verb)
	assert_true(button != null, "The commit button reads %s for the picked perk" % verb)
	if button == null:
		return
	var enabled: bool = bool(button.call("is_enabled")) if button.has_method("is_enabled") else not (button as BaseButton).disabled
	assert_eq(enabled, allowed, "%s is enabled exactly when perk_capacity allows it" % verb)
	if not enabled:
		return
	var before: int = Array(Simulation.run_state.build.get("perks", [])).size()
	await harness.driver.press(button)
	var after: int = Array(Simulation.run_state.build.get("perks", [])).size()
	assert_eq(after, before + (1 if verb == "FIT" else -1), "%s moved one perk" % verb)


func _perks_tab(shell: Node) -> Node:
	var screen: CabinetScreen = _find_first(shell, func(node: Node) -> bool: return node is CabinetScreen) as CabinetScreen
	if screen == null:
		return null
	return screen.active_tab()


func _find_first(node: Node, predicate: Callable) -> Node:
	if node == null:
		return null
	if bool(predicate.call(node)):
		return node
	for child in node.get_children():
		var found: Node = _find_first(child, predicate)
		if found != null:
			return found
	return null


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
