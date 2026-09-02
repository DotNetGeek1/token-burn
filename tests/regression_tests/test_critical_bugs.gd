extends TestCase


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_hardware_upgrade()
	_test_double_purchase()
	_test_round_end_choice()
	_test_a_successful_round_does_not_end_the_run()
	_test_headless_no_autosave()
	_test_market_purchase()
	_test_second_monitor_widens_the_pipeline_editor()
	_test_capacity_perks_apply_when_taken_from_the_angel()
	_test_mixed_job_finalization()
	_test_multi_job_tick_counts_once()
	_test_a_granted_module_does_not_replace_the_starters()
	_test_previews_emit_no_domain_events()
	_test_preview_cascade_does_not_hit_the_bus()
	_test_a_build_cannot_hold_more_than_its_cap()
	_test_rival_keystones_cannot_share_a_build()
	_test_investor_halfway_call_survives_leaving_the_desk()
	_test_duplicate_job_definitions_stay_independent()
	_test_executive_committee_does_not_compound()
	_test_wrapper_freezes_the_in_flight_fee()
	_test_failed_jobs_do_not_fire_completion_perks()
	_test_legacy_angel_operation_choice_is_selectable()


func _make_sim() -> Node:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	return sim


func _test_hardware_upgrade() -> void:
	var sim := _make_sim()
	sim.start_run(100)
	sim.run_state.economy["cash"] = 5000.0
	var rate_before: float = float(sim.run_state.compute.get("token_rate", 0.0))
	assert_true(sim.buy_upgrade("upgrade.custom_desktop"), "Hardware upgrade purchases")
	sim._compute_system.recalculate(sim.run_state, sim.effect_resolver, sim._collect_subscriptions(), sim.rng)
	var rate_after: float = float(sim.run_state.compute.get("token_rate", 0.0))
	assert_true(rate_after > rate_before, "Hardware upgrade increases token rate")
	sim.free()


func _test_double_purchase() -> void:
	var sim := _make_sim()
	sim.start_run(101)
	var cash_before: float = float(sim.run_state.economy.get("cash", 0.0))
	assert_true(sim.buy_upgrade("upgrade.portable_ac"), "First purchase succeeds")
	var cash_after_first: float = float(sim.run_state.economy.get("cash", 0.0))
	assert_false(sim.buy_upgrade("upgrade.portable_ac"), "Second purchase rejected")
	assert_eq(sim.run_state.economy.get("cash", 0.0), cash_after_first, "Cash not deducted twice")
	assert_true(cash_after_first < cash_before, "First purchase cost cash")
	sim.free()


func _test_second_monitor_widens_the_pipeline_editor() -> void:
	var sim := _make_sim()
	sim.start_run(103)
	sim.run_state.economy["cash"] = 5000.0
	var slots_before: int = sim.board_slots().size()
	assert_true(sim.buy_upgrade("upgrade.second_monitor"), "The second monitor can be bought")
	assert_eq(
		sim.board_slots().size(),
		slots_before + 1,
		"The pipeline editor immediately gains the slot the monitor promises"
	)
	sim.free()


func _test_capacity_perks_apply_when_taken_from_the_angel() -> void:
	var slot_sim := _make_sim()
	slot_sim.start_run(105)
	var slots_before: int = slot_sim.board_slots().size()
	slot_sim.phase = slot_sim.Phase.ANGEL_ROUND
	assert_true(
		slot_sim.accept_offer("perk", "perk.wide_bus"),
		"The angel can grant Wide Bus"
	)
	assert_eq(
		slot_sim.board_slots().size(),
		slots_before + 1,
		"Taking Wide Bus immediately adds its pipeline slot"
	)
	slot_sim.free()

	var workflow_sim := _make_sim()
	workflow_sim.start_run(106)
	var capacity_before: int = workflow_sim.workflow_capacity()
	workflow_sim.phase = workflow_sim.Phase.ANGEL_ROUND
	assert_true(
		workflow_sim.accept_offer("perk", "perk.two_ways_of_working"),
		"The angel can grant Two Ways of Working"
	)
	assert_eq(
		workflow_sim.workflow_capacity(),
		capacity_before + 1,
		"Taking Two Ways of Working immediately adds workflow capacity"
	)
	workflow_sim.free()


func _test_round_end_choice() -> void:
	var sim := _make_sim()
	sim.start_run(102)
	sim.run_state.business["job_queue"] = [{
		"id": "job.product_descriptions",
		"name": "Test",
		"token_requirement": 1.0,
		"tokens_remaining": 1.0,
		"deadline_prompts": 99,
		"prompts_remaining": 99,
		"reward": 500.0,
		"quality_threshold": 0.0,
		"quality": 0.0,
		"revision_risk": 0.0,
		"bug_chance": 0.0,
	}]
	sim.start_work_sync()
	assert_true(sim.phase == sim.Phase.ANGEL_ROUND, "Resolving the round's work opens the angel phase")
	assert_true(sim.pending_choices.size() > 0, "Angel choices are presented after the bills clear")
	sim.free()


## Completing the round's work is not the end of the company. The save Continue
## reloads must still be a live run — otherwise the Run Report's COMPANY CLOSED
## overlay and a playable next round disagree, and title-then-continue looks
## like a resurrection.
func _test_a_successful_round_does_not_end_the_run() -> void:
	const SCRATCH_SAVE := "user://save_test_successful_round.json"
	SaveManager.use_scratch(SCRATCH_SAVE)
	var sim := _make_sim()
	sim.autosave_enabled = true
	sim.start_run(104)
	sim.run_state.business["job_queue"] = [{
		"id": "job.product_descriptions",
		"name": "Test",
		"token_requirement": 1.0,
		"tokens_remaining": 1.0,
		"deadline_prompts": 99,
		"prompts_remaining": 99,
		"reward": 500.0,
		"quality_threshold": 0.0,
		"quality": 0.0,
		"revision_risk": 0.0,
		"bug_chance": 0.0,
	}]
	sim.start_work_sync()
	assert_true(
		sim.phase == sim.Phase.ANGEL_ROUND or sim.phase == sim.Phase.ROUND_PREP,
		"A delivered round is still in play"
	)
	assert_true(sim.phase != sim.Phase.RUN_END, "It is not a run ending")
	assert_eq(str(sim.run_state.flags.get("outcome", "")), "", "And it has no run-end outcome")
	var data: Dictionary = SaveManager.load_run()
	assert_false(data.is_empty(), "The round wrote a save Continue can reload")
	assert_true(
		str(data.get("phase", "")) != "RUN_END",
		"That save is a live run, not a closed company"
	)
	SaveManager.delete_save()
	SaveManager.restore_default()
	sim.free()


func _test_headless_no_autosave() -> void:
	SaveManager.delete_save()
	var sim := _make_sim()
	sim.autosave_enabled = false
	sim.start_run(103)
	if sim.run_state.business.get("job_offers", []).size() > 0:
		sim.accept_job(str(sim.run_state.business["job_offers"][0].get("id", "")))
		sim.start_work_sync()
	assert_false(SaveManager.has_save(), "Headless sim does not autosave")
	sim.free()


func _test_market_purchase() -> void:
	var sim := _make_sim()
	sim.start_run(104)
	sim.run_state.economy["cash"] = 10000.0
	assert_true(sim.can_buy_upgrade("upgrade.portable_ac"), "Can buy during round prep")
	assert_true(sim.buy_upgrade("upgrade.portable_ac"), "Market purchase succeeds in ROUND_PREP")
	sim.free()


func _test_mixed_job_finalization() -> void:
	var sim := _make_sim()
	sim.start_run(105)
	sim.run_state.economy["cash"] = 0.0
	sim.run_state.business["active_jobs"] = [
		{"id": "done", "name": "Done", "tokens_remaining": 0.0, "token_requirement": 100.0, "reward": 1000.0, "quality": 80.0, "quality_threshold": 50.0, "shipped": true},
		{"id": "fail", "name": "Fail", "tokens_remaining": 50.0, "token_requirement": 100.0, "reward": 1000.0, "quality": 10.0, "quality_threshold": 50.0},
	]
	sim.phase = sim.Phase.IN_ROUND
	sim._end_session("collapsed")
	var cash: float = float(sim.run_state.economy.get("cash", 0.0))
	assert_true(cash >= 900.0, "Completed job in mixed batch paid in full")
	sim.free()


func _test_multi_job_tick_counts_once() -> void:
	var sim := _make_sim()
	sim.start_run(106)
	sim.run_state.economy["cash"] = 10000.0
	sim.run_state.compute["token_rate"] = 100.0
	var small := {
		"id": "small", "name": "Small", "token_requirement": 10.0, "tokens_remaining": 10.0,
		"deadline_prompts": 99, "prompts_remaining": 99, "reward": 500.0,
		"quality": 0.0, "quality_threshold": 0.0, "revision_risk": 0.0, "bug_chance": 0.0,
	}
	var big := {
		"id": "big", "name": "Big", "token_requirement": 1e15, "tokens_remaining": 1e15,
		"deadline_prompts": 99, "prompts_remaining": 99, "reward": 500.0,
		"quality": 0.0, "quality_threshold": 0.0, "revision_risk": 0.0, "bug_chance": 0.0,
	}
	var failing := {
		"id": "late", "name": "Late", "token_requirement": 1e15, "tokens_remaining": 1e15,
		"deadline_prompts": 1, "prompts_remaining": 0, "reward": 500.0,
		"quality": 0.0, "quality_threshold": 0.0, "revision_risk": 0.0, "bug_chance": 0.0,
	}
	sim.run_state.business["active_jobs"] = [small, big, failing]
	sim.phase = sim.Phase.IN_ROUND
	var result: Dictionary = sim._job_system.run_production_tick(
		sim.run_state, sim.rng, sim.effect_resolver, sim._collect_subscriptions(),
		sim.tuning, sim._compute_system, sim._heat_system, sim._economy_system
	)
	assert_true(bool(result.get("ok", false)), "Multi-job tick runs")
	assert_eq(result.get("completed_count", -1), 1, "The late contract is auto-shipped when its deadline hits")
	assert_eq(result.get("failed_count", -1), 0, "A missed deadline ships rather than failing")
	assert_false(bool(result.get("all_resolved", true)), "The round is not resolved while a contract continues")
	sim.free()


## The reported bug: after a win, every workflow item disappeared and no new ones
## ever arrived. A `starting_module` unlock writes its module into the build
## before the board is sized, and the board used to read a non-empty list as
## "starters already granted" — so the run got that one module and nothing else,
## for ever.
func _test_a_granted_module_does_not_replace_the_starters() -> void:
	var state := RunState.new()
	state.reset()
	var granted: String = str(ContentDatabase.modules[0].id)
	state.build["modules"] = [granted]
	BoardSystem.new().ensure_board(state, ContentDatabase)
	var owned: Array = Array(state.build.get("modules", []))
	assert_true(granted in owned, "The granted module is still there")
	for starter in ContentDatabase.starter_modules():
		assert_true(str(starter) in owned, "And so is starter %s" % str(starter))


## A preview is the board screen asking what would happen. Anything listening on
## the bus — achievements, perks, the HUD — must not be told it did happen, or
## simply opening the burn readout awards progress the player never earned.
func _test_previews_emit_no_domain_events() -> void:
	var sim := _make_sim()
	sim.start_run(140)
	sim.run_state.economy["cash"] = 1000000.0
	sim.run_state.business["active_jobs"] = [{
		"id": "job.preview_probe",
		"name": "Preview Probe",
		"token_requirement": 1.0,
		"tokens_remaining": 1.0,
		"deadline_prompts": 8,
		"prompts_remaining": 8,
		"reward": 500.0,
		"quality": 0.0,
		"quality_threshold": 0.0,
		"revision_risk": 1.0,
		"bug_chance": 1.0,
	}]
	sim.run_state.business["focused_job_id"] = "job.preview_probe"
	sim.phase = sim.Phase.IN_ROUND
	sim._work_running = true
	sim._board_system.ensure_board(sim.run_state, ContentDatabase)
	# Hot enough that a prompt is guaranteed to cross the throttle threshold,
	# so the heat event is genuinely on the table for the preview to suppress.
	sim.run_state.compute["heat"] = float(sim.run_state.compute.get("heat_capacity", 100.0))

	var seen: Array[String] = []
	var connections: Array = [
		[EventBus.tokens_generated, func(_a: float) -> void: seen.append("tokens.generated")],
		[EventBus.tokens_consumed, func(_a: float) -> void: seen.append("tokens.consumed")],
		[EventBus.quality_calculated, func(_v: float) -> void: seen.append("quality.calculated")],
		[EventBus.bug_generated, func() -> void: seen.append("bug.generated")],
		[EventBus.job_completed, func(_id: String) -> void: seen.append("job.completed")],
		[EventBus.heat_threshold_crossed, func(_l: float) -> void: seen.append("heat.threshold_crossed")],
	]
	for pair in connections:
		pair[0].connect(pair[1])

	var burn: Dictionary = sim.preview_burn()
	assert_true(bool(burn.get("ok", false)), "The burn previews")
	assert_true(seen.is_empty(), "preview_burn() tells the bus nothing: %s" % str(seen))

	var cool: Dictionary = sim.preview_cool()
	assert_true(bool(cool.get("ok", false)), "The cool previews")
	assert_true(seen.is_empty(), "preview_cool() tells the bus nothing either: %s" % str(seen))

	for pair in connections:
		pair[0].disconnect(pair[1])
	sim.free()


func _test_preview_cascade_does_not_hit_the_bus() -> void:
	var sim := _make_sim()
	sim.start_run(141)
	sim.apply_run_location(sim.run_state, "warehouse")
	sim.run_state.economy["cash"] = 1000000.0
	sim._board_system.ensure_board(sim.run_state, ContentDatabase)
	sim.run_state.build["modules"] = ["op.prompt", "op.recursive_compiler"]
	var slots: Array = sim._board_system.slots(sim.run_state)
	for i in range(slots.size()):
		slots[i] = str(["op.prompt", "op.recursive_compiler"][i]) if i < 2 else ""
	sim.run_state.business["active_jobs"] = [{
		"id": "job.preview_cascade",
		"name": "Preview Cascade",
		"token_requirement": 1.0,
		"tokens_remaining": 1.0,
		"deadline_prompts": 8,
		"prompts_remaining": 8,
		"reward": 500.0,
		"quality": 0.0,
		"quality_threshold": 0.0,
		"revision_risk": 0.0,
		"bug_chance": 0.0,
		"blocked_slots": 0,
		"board_rules": [],
		"tags": [],
	}]
	sim.run_state.business["focused_job_id"] = "job.preview_cascade"
	sim.phase = sim.Phase.IN_ROUND
	sim._work_running = true
	sim.run_state.compute["heat"] = float(sim.run_state.compute.get("heat_capacity", 100.0))
	var seen: Array[String] = []
	var on_cascade := func(_id: String) -> void: seen.append("board.cascade_triggered")
	EventBus.cascade_triggered.connect(on_cascade)
	var cascaded := false
	for _i in range(24):
		var burn: Dictionary = sim.preview_burn()
		if bool(burn.get("ok", false)):
			for stage in burn.get("stages", []):
				if stage is Dictionary and bool(stage.get("cascaded", false)):
					cascaded = true
					break
		if cascaded:
			break
	assert_true(seen.is_empty(), "A preview cascade does not notify EventBus: %s" % str(seen))
	EventBus.cascade_triggered.disconnect(on_cascade)
	sim.free()
	assert_true(
		cascaded or seen.is_empty(),
		"Preview either cascaded silently or never cascaded; the bus stayed quiet either way"
	)


func _test_a_build_cannot_hold_more_than_its_cap() -> void:
	var sim := _make_sim()
	sim.start_run(152)
	var cap: int = sim._perk_system.perk_capacity(sim.run_state, ContentDatabase)
	var taken: int = 0
	for perk in ContentDatabase.perks:
		if sim.run_state.build["perks"].size() >= cap:
			break
		if sim._perk_system.collect_perk(sim.run_state, perk.id, ContentDatabase):
			if sim._perk_system.equip_perk(sim.run_state, perk.id, ContentDatabase):
				taken += 1
	assert_true(taken > 0, "At least some perks are equippable from an empty build")
	assert_true(
		sim.run_state.build["perks"].size() <= cap,
		"Active loadout stops at its cap of %d, not %d" % [cap, sim.run_state.build["perks"].size()]
	)
	sim.free()


## A doctrine is only a choice if picking one closes the other.
func _test_rival_keystones_cannot_share_a_build() -> void:
	var sim := _make_sim()
	sim.start_run(153)
	var ps = sim._perk_system
	assert_true(
		ps.collect_perk(sim.run_state, "perk.stack_overflow_tab", ContentDatabase),
		"A quality/bugs common enters the collection"
	)
	assert_true(
		ps.equip_perk(sim.run_state, "perk.stack_overflow_tab", ContentDatabase),
		"The common opens both remaining keystone doctrines"
	)
	assert_true(
		ps.collect_perk(sim.run_state, "perk.move_fast_and_break_everything", ContentDatabase),
		"Move Fast can be collected after a bugs perk"
	)
	assert_true(
		ps.equip_perk(sim.run_state, "perk.move_fast_and_break_everything", ContentDatabase),
		"Move Fast follows from owning bugs perks"
	)
	assert_true(
		ps.collect_perk(sim.run_state, "perk.enterprise_grade", ContentDatabase),
		"Enterprise Grade may be collected even when Move Fast is active"
	)
	assert_false(
		ps.can_equip(sim.run_state, "perk.enterprise_grade", ContentDatabase),
		"Enterprise Grade cannot be equipped once the build has gone Move Fast"
	)
	sim.free()


## The desk is unloaded on every venue trip. The halfway call used to live on
## that scene, so coming back from the market rang Vince again. It belongs on
## the run, which is what survives the trip — and a save, and a Continue.
func _test_investor_halfway_call_survives_leaving_the_desk() -> void:
	var sim := _make_sim()
	sim.start_run(160)
	assert_false(
		sim.run_state.investor_beat_heard("contract_halfway"),
		"A fresh run has not heard the halfway call"
	)
	sim.run_state.mark_investor_beat("contract_halfway")
	assert_true(
		sim.run_state.investor_beat_heard("contract_halfway"),
		"Marking remembers it for the rest of the run"
	)
	var snapshot: Dictionary = sim.run_state.to_dict()
	var restored := RunState.new()
	restored.from_dict(snapshot)
	assert_true(
		restored.investor_beat_heard("contract_halfway"),
		"Coming back to the desk — or Continue — still remembers"
	)
	sim.start_run(161)
	assert_false(
		sim.run_state.investor_beat_heard("contract_halfway"),
		"A new run has not heard it"
	)
	sim.free()


## Two cards from the same JobDefinition used to share one id, so accepting,
## focusing or laning one of them selected both.
func _test_duplicate_job_definitions_stay_independent() -> void:
	var sim := _make_sim()
	sim.start_run(7701)
	sim.run_state.economy["cash"] = 10_000_000.0
	var job_def: JobDefinition = ContentDatabase.get_job("job.product_descriptions")
	var jobs := JobSystem.new()
	var first: Dictionary = jobs._scale_job(
		job_def, 4, ContentDatabase, sim.tuning, sim.run_state, null, 0
	)
	var second: Dictionary = jobs._scale_job(
		job_def, 4, ContentDatabase, sim.tuning, sim.run_state, null, 1
	)
	assert_true(
		str(first.get("id", "")) != str(second.get("id", "")),
		"Two copies of the same contract have distinct instance ids"
	)
	assert_eq(
		str(first.get("definition_id", "")), job_def.id,
		"definition_id keeps the authored id"
	)
	assert_eq(
		str(second.get("definition_id", "")), job_def.id,
		"Both copies share a definition"
	)
	first["token_requirement"] = 100.0
	second["token_requirement"] = 100.0
	first["deadline_prompts"] = 20
	second["deadline_prompts"] = 20
	sim.run_state.business["job_offers"] = [first, second]
	assert_true(sim.accept_job(str(first.get("id", ""))), "First copy can be taken by instance id")
	assert_true(sim.accept_job(str(second.get("id", ""))), "Second copy can be taken independently")
	assert_eq(sim.run_state.business["job_queue"].size(), 2, "Both copies are on the slate")
	assert_true(sim.buy_upgrade("upgrade.custom_desktop"), "A second machine opens a second lane")
	sim.start_work()
	var lanes: Array = sim.burn_lanes()
	assert_eq(lanes.size(), 2, "Two copies can occupy two parallel lanes")
	assert_true(
		str(lanes[0].get("id", "")) != str(lanes[1].get("id", "")),
		"Each lane holds a different instance"
	)
	sim.free()


## Executive Committee multiplies the standing bill. Without a base it
## multiplied its own last answer every recalculation.
func _test_executive_committee_does_not_compound() -> void:
	var sim := _make_sim()
	sim.start_run(7702)
	sim.run_state.economy["recurring_costs_base"] = 1000.0
	sim._perk_system.collect_perk(sim.run_state, "perk.executive_committee", ContentDatabase)
	sim._perk_system.equip_perk(sim.run_state, "perk.executive_committee", ContentDatabase)
	sim.debug_invalidate_subscriptions()
	var subs: Array = sim.debug_collect_subscriptions()
	for _i in range(10):
		sim.compute_system().recalculate(sim.run_state, sim.effect_resolver, subs, sim.rng)
	assert_almost_eq(
		float(sim.run_state.economy.get("recurring_costs", 0.0)), 1200.0, 0.01,
		"Base 1000 is still exactly 1200 after ten recalculations"
	)
	sim.free()

	var migrated_sim := _make_sim()
	migrated_sim.run_state.from_dict({
		"save_version": 17,
		"economy": {"recurring_costs": 1440.0},
		"build": {
			"hardware": ["used_laptop", "gpu_rack", "gpu_rack"],
			"upgrade_levels": {"upgrade.gpu_rack": 2},
			"upgrade_counts": {"upgrade.gpu_rack": 2},
		},
	})
	migrated_sim._perk_system.collect_perk(
		migrated_sim.run_state, "perk.executive_committee", ContentDatabase
	)
	migrated_sim._perk_system.equip_perk(
		migrated_sim.run_state, "perk.executive_committee", ContentDatabase
	)
	migrated_sim.debug_invalidate_subscriptions()
	migrated_sim.compute_system().recalculate(
		migrated_sim.run_state,
		migrated_sim.effect_resolver,
		migrated_sim.debug_collect_subscriptions(),
		migrated_sim.rng
	)
	assert_almost_eq(
		float(migrated_sim.run_state.economy.get("recurring_costs", 0.0)),
		120.0,
		0.01,
		"A legacy 1440 bill rebuilds to the two racks' 100 base, then takes one 20% penalty"
	)
	migrated_sim.free()


## The Wrapper used to freeze last_job_reward, which is only written after
## finalize — first job £0 forever, later jobs cloned the previous session.
func _test_wrapper_freezes_the_in_flight_fee() -> void:
	var sim := _make_sim()
	sim.start_run(7703)
	sim._perk_system.collect_perk(sim.run_state, "perk.the_wrapper", ContentDatabase)
	sim._perk_system.equip_perk(sim.run_state, "perk.the_wrapper", ContentDatabase)
	sim.debug_invalidate_subscriptions()
	var perk := ContentDatabase.get_perk("perk.the_wrapper")
	var clone: float = 1.0 + float(perk.parameters.get("passive_ratio", 0.15))
	var income_ratio: float = float(perk.parameters.get("passive_income_ratio", 0.03))
	_dispatch_wrapper_reward(sim, perk, 1000.0)
	sim.debug_invalidate_subscriptions()
	var first_freeze: float = 1000.0 * clone * income_ratio
	assert_almost_eq(
		_wrapper_stream_total(sim), first_freeze, 0.01,
		"A £1000 job freezes 3% of the in-flight fee"
	)
	var cash_before: float = float(sim.run_state.economy.get("cash", 0.0))
	_dispatch_round_started(sim)
	assert_almost_eq(
		float(sim.run_state.economy.get("cash", 0.0)) - cash_before, first_freeze, 0.01,
		"The next round.started pays that frozen stream"
	)
	_dispatch_wrapper_reward(sim, perk, 2000.0)
	sim.debug_invalidate_subscriptions()
	var second_freeze: float = 2000.0 * clone * income_ratio
	assert_almost_eq(
		_wrapper_stream_total(sim), first_freeze + second_freeze, 0.01,
		"A later £2000 job adds an independent stream"
	)
	cash_before = float(sim.run_state.economy.get("cash", 0.0))
	_dispatch_round_started(sim)
	assert_almost_eq(
		float(sim.run_state.economy.get("cash", 0.0)) - cash_before,
		first_freeze + second_freeze, 0.01,
		"Both streams pay on the following round.started"
	)
	sim.free()


func _dispatch_wrapper_reward(sim: Node, perk: PerkDefinition, reward: float) -> void:
	sim.effect_resolver.begin_action("reward.wrapper")
	var mod_ctx := ModifierContext.new("reward.calculated", sim.run_state)
	mod_ctx.rng = sim.rng.derive("reward.wrapper")
	mod_ctx.job = {"id": "job.wrap", "reward": reward, "completed": true}
	mod_ctx.set_value("job.reward", reward)
	mod_ctx.set_value("job.completed", true)
	for sub in perk.subscriptions:
		if str(sub.get("event", "")) != "reward.calculated":
			continue
		var copy: Dictionary = sub.duplicate(true)
		copy["parameters"] = perk.parameters.duplicate(true)
		sim.effect_resolver.dispatch("reward.calculated", mod_ctx, [copy])


func _wrapper_stream_total(sim: Node) -> float:
	var total: float = 0.0
	for status in sim.run_state.build.get("status_effects", []):
		if not status is Dictionary or str(status.get("id", "")) != "wrapper.passive":
			continue
		for sub in status.get("subscriptions", []):
			for effect in Array(sub.get("effects", [])):
				if effect is Dictionary:
					total += float(effect.get("value", 0.0))
	return total


func _dispatch_round_started(sim: Node) -> void:
	sim.effect_resolver.begin_action("round.started")
	var mod_ctx := ModifierContext.new("round.started", sim.run_state)
	mod_ctx.rng = sim.rng.derive("round.started")
	sim.effect_resolver.dispatch("round.started", mod_ctx, sim.debug_collect_subscriptions())


## Deadline failures share reward.calculated with completions. Completion-worded
## perks have to see job.completed or they double consolation and spawn passives.
func _test_failed_jobs_do_not_fire_completion_perks() -> void:
	var sim := _make_sim()
	sim.start_run(7704)
	# Written straight onto the loadout so Ship It's requires_tags gate does not
	# keep the completion perk off the failed-payout path this is measuring.
	sim.run_state.build["perks"] = ["perk.ship_it", "perk.the_wrapper"]
	sim.debug_invalidate_subscriptions()
	var job: Dictionary = {
		"id": "job.missed",
		"name": "Missed",
		"reward": 1000.0,
		"token_requirement": 1000.0,
		"tokens_remaining": 500.0,
		"quality": 100.0,
		"quality_threshold": 0.0,
		"time_remaining_ratio": 0.0,
		"prompts_remaining": 0,
		"abandoned": false,
	}
	var cash_before: float = float(sim.run_state.economy.get("cash", 0.0))
	var messages: Array[String] = []
	var payout: Dictionary = sim.job_system().finalize_failed_jobs(
		sim.run_state, [job], sim.effect_resolver, sim.debug_collect_subscriptions(),
		sim.tuning, sim.economy_system(), ContentDatabase, messages, sim.rng
	)
	var consolation: float = 1000.0 * 0.5 * float(
		ContentDatabase.balance.get("job_scaling", {}).get("failed_job_consolation_ratio", 0.2)
	)
	assert_almost_eq(
		float(payout.get("reward", 0.0)), consolation, 0.01,
		"Ship It does not double a failed consolation payout"
	)
	assert_almost_eq(
		float(sim.run_state.economy.get("cash", 0.0)) - cash_before, consolation, 0.01,
		"The consolation is what actually landed"
	)
	assert_eq(_wrapper_stream_total(sim), 0.0, "The Wrapper does not spawn a passive from a failure")
	sim.free()


## Saves written when pipeline pieces were still called operations restore a
## card accept_offer would otherwise refuse.
func _test_legacy_angel_operation_choice_is_selectable() -> void:
	var sim := _make_sim()
	sim.start_run(7705)
	sim.phase = sim.Phase.ANGEL_ROUND
	sim.pending_choices = [{
		"type": "operation",
		"id": "op.whiteboard",
		"label": "Whiteboard Session",
		"description": "",
		"cost": 0.0,
	}]
	sim._migrate_pending_choices()
	assert_eq(
		str(sim.pending_choices[0].get("type", "")), "module",
		"A legacy operation choice becomes a module"
	)
	assert_true(
		sim.accept_offer("module", "op.whiteboard"),
		"And it is selectable as a module"
	)
	sim.free()
