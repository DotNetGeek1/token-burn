extends TestCase

## Perk-only angel table and paid module Market shelf.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_angel_offers_are_perk_only()
	_test_three_perks_when_pool_permits()
	_test_fewer_than_three_perks_when_pool_is_small()
	_test_taking_perk_closes_draft()
	_test_decline_still_works()
	_test_angel_reroll_unavailable()
	_test_rejects_offer_not_on_table()
	_test_no_eligible_perks_cannot_wedge()
	_test_first_round_has_stock()
	_test_stock_size_scales_by_location()
	_test_market_eligibility_helpers()
	_test_stock_excludes_owned_modules()
	_test_opening_market_does_not_reroll()
	_test_save_load_preserves_stock()
	_test_next_round_naturally_restocks()
	_test_chapter_transition_restocks()
	_test_pricing_and_location_reward_scale()
	_test_purchase_flow()
	_test_cannot_buy_without_cash_or_absent()
	_test_can_buy_several_in_one_round()
	_test_reroll_escalation_and_reset()
	_test_reroll_charges_and_avoids_old_stock()
	_test_reroll_small_pool_fallback()
	_test_reroll_fills_empty_slots()
	_test_market_closed_during_angel()
	_test_mixed_pending_choice_migration()
	_test_modules_read_as_token_multipliers()
	_test_calibration_consumes_modules_and_cash()
	_test_calibration_rank_climbs_to_cap()
	_test_calibration_blockers()
	_test_calibration_multipliers_reach_the_stage()
	_test_calibration_survives_save_load()


# --- Module calibration ------------------------------------------------------

## A run with cash, a target and two benched modules to strip for parts.
## Returns {sim, target, spare: Array} — `spare` holds two owned, unseated
## modules that are not the target.
func _calibration_rig(seed_value: int) -> Dictionary:
	var sim: Node = _sim(seed_value)
	sim.run_state.economy["cash"] = 1_000_000.0
	var owned: Array = Array(sim.run_state.build.get("modules", []))
	assert_true(owned.size() > 0, "A fresh run owns its starter modules")
	var target: String = str(owned[0])
	_grant_spares(sim, target, 2)
	var spare: Array = CalibrationSystem.consumable_modules(sim.run_state, target).slice(0, 2)
	assert_eq(spare.size(), 2, "Two benched modules are available to consume")
	return {"sim": sim, "target": target, "spare": spare}


## Grants catalogue modules to the bench until `count` benched non-target
## modules exist.
func _grant_spares(sim: Node, target: String, count: int) -> void:
	for module in ContentDatabase.modules:
		if CalibrationSystem.consumable_modules(sim.run_state, target).size() >= count:
			return
		if module.id == target:
			continue
		sim.board_system().grant_module(sim.run_state, module.id, false)


func _test_calibration_consumes_modules_and_cash() -> void:
	var rig: Dictionary = _calibration_rig(9700)
	var sim: Node = rig["sim"]
	var target: String = rig["target"]
	var spare: Array = rig["spare"]
	# Bedroom major_purchase is 1200; rank 1 costs 1200 × 0.25 × 1.
	var cost: float = sim.module_calibration_cost(target)
	assert_almost_eq(cost, 300.0, 0.01, "First rank costs a quarter of the bedroom's major purchase")
	assert_eq(sim.module_calibration_rank(target), 0, "Modules start uncalibrated")
	var cash_before: float = float(sim.run_state.economy.get("cash", 0.0))
	var owned_before: int = Array(sim.run_state.build.get("modules", [])).size()
	assert_eq(sim.calibration_block_reason(target, spare), "", "A funded, stocked calibration is not blocked")
	assert_true(sim.can_calibrate_module(target, spare), "…and reads as possible")
	assert_true(sim.calibrate_module(target, spare), "Calibration commits")
	assert_almost_eq(
		float(sim.run_state.economy.get("cash", 0.0)), cash_before - cost, 0.01,
		"Cash falls by the quoted cost"
	)
	var owned: Array = Array(sim.run_state.build.get("modules", []))
	assert_eq(owned.size(), owned_before - 2, "Both consumed modules leave the inventory")
	for module_id in spare:
		assert_false(module_id in owned, "%s was consumed" % module_id)
	assert_true(target in owned, "The target stays owned")
	assert_eq(sim.module_calibration_rank(target), 1, "Rank climbs to 1")
	assert_eq(int(sim.run_state.statistics.get("modules_calibrated", 0)), 1, "Statistic counts the calibration")
	var ledger: Array = Array(sim.run_state.economy.get("ledger", []))
	assert_true(ledger.size() > 0, "The debit is on the ledger")
	if ledger.size() > 0:
		var last: Dictionary = ledger[ledger.size() - 1]
		assert_eq(str(last.get("reason", "")), "calibration:%s" % target, "The ledger names calibration as the reason")
		assert_almost_eq(float(last.get("amount", 0.0)), cost, 0.01, "…for the quoted amount")
	sim.free()


func _test_calibration_rank_climbs_to_cap() -> void:
	var rig: Dictionary = _calibration_rig(9701)
	var sim: Node = rig["sim"]
	var target: String = rig["target"]
	var cap: int = CalibrationSystem.max_rank()
	for expected_rank in range(1, cap + 1):
		_grant_spares(sim, target, 2)
		var spare: Array = CalibrationSystem.consumable_modules(sim.run_state, target).slice(0, 2)
		assert_almost_eq(
			sim.module_calibration_cost(target), 300.0 * float(expected_rank), 0.01,
			"Rank %d costs %d× the base share" % [expected_rank, expected_rank]
		)
		assert_true(sim.calibrate_module(target, spare), "Rank %d commits" % expected_rank)
		assert_eq(sim.module_calibration_rank(target), expected_rank, "Rank reads %d" % expected_rank)
	_grant_spares(sim, target, 2)
	var extra: Array = CalibrationSystem.consumable_modules(sim.run_state, target).slice(0, 2)
	assert_eq(
		sim.calibration_block_reason(target, extra), CalibrationSystem.REASON_MAX_RANK,
		"A capped module refuses another rank"
	)
	assert_false(sim.calibrate_module(target, extra), "…and the commit is refused")
	assert_eq(sim.module_calibration_rank(target), cap, "Rank never passes the cap")
	assert_almost_eq(sim.module_calibration_cost(target), 0.0, 0.001, "A capped module has no next-rank price")
	for module_id in extra:
		assert_true(module_id in Array(sim.run_state.build.get("modules", [])), "A refused calibration consumes nothing")
	sim.free()


func _test_calibration_blockers() -> void:
	var rig: Dictionary = _calibration_rig(9702)
	var sim: Node = rig["sim"]
	var target: String = rig["target"]
	var spare: Array = rig["spare"]
	var owned_before: Array = Array(sim.run_state.build.get("modules", [])).duplicate()

	sim.run_state.economy["cash"] = 0.0
	assert_true(
		sim.calibration_block_reason(target, spare).begins_with("NEED "),
		"No cash blocks with the shortfall"
	)
	assert_false(sim.calibrate_module(target, spare), "Broke calibration is refused")
	sim.run_state.economy["cash"] = 1_000_000.0

	assert_eq(
		sim.calibration_block_reason(target, [spare[0]]),
		CalibrationSystem.REASON_NEED_MODULES % CalibrationSystem.modules_consumed(),
		"Too few consumed modules blocks"
	)
	assert_eq(
		sim.calibration_block_reason(target, [spare[0], spare[0]]),
		CalibrationSystem.REASON_DUPLICATE,
		"The same module twice blocks"
	)
	assert_eq(
		sim.calibration_block_reason(target, [target, spare[0]]),
		CalibrationSystem.REASON_CONSUME_TARGET,
		"The target cannot be its own spare part"
	)
	assert_true(
		sim.calibration_block_reason(target, [spare[0], "op.not_a_real_module"]).ends_with("IS NOT OWNED"),
		"A module the run does not own cannot be consumed"
	)
	assert_eq(
		sim.calibration_block_reason("op.not_a_real_module", spare),
		CalibrationSystem.REASON_NOT_OWNED,
		"An unowned target blocks"
	)

	# Seat one spare in the active workflow: it has to be benched first.
	var job: Dictionary = {}
	var seated: String = str(spare[0])
	assert_true(sim.board_system().place_module(sim.run_state, job, seated, 0), "Spare is seated for the probe")
	assert_true(CalibrationSystem.is_seated(sim.run_state, seated), "The system sees the seat")
	assert_true(
		sim.calibration_block_reason(target, spare).begins_with("UNSEAT "),
		"A seated module cannot be consumed"
	)
	assert_false(seated in CalibrationSystem.consumable_modules(sim.run_state, target), "…and is not offered")
	assert_false(sim.calibrate_module(target, spare), "The commit is refused")
	assert_eq(Array(sim.run_state.build.get("modules", [])), owned_before, "Refusals consume nothing")
	assert_eq(sim.module_calibration_rank(target), 0, "…and grant no rank")

	# The Market's hours apply here as at every other counter.
	sim.board_system().clear_slot(sim.run_state, job, 0)
	sim.phase = sim.Phase.IN_ROUND
	assert_eq(sim.calibration_block_reason(target, spare), "MARKET CLOSED", "Closed Market blocks calibration")
	assert_false(sim.calibrate_module(target, spare), "…and refuses the commit")
	sim.phase = sim.Phase.ROUND_PREP
	assert_true(sim.calibrate_module(target, spare), "Reopened, the same calibration commits")
	sim.free()


## A calibrated module's stage runs cooler, cheaper and stronger through the
## same subscription path the burn uses; an uncalibrated one is untouched.
func _test_calibration_multipliers_reach_the_stage() -> void:
	var rig: Dictionary = _calibration_rig(9703)
	var sim: Node = rig["sim"]
	var target: String = rig["target"]
	assert_true(sim.calibrate_module(target, rig["spare"]), "Rank 1 commits")
	var state: RunState = sim.run_state
	assert_almost_eq(CalibrationSystem.multiplier(state, target, "heat"), 0.92, 0.0001, "Rank 1 heat multiplier")
	assert_almost_eq(CalibrationSystem.multiplier(state, target, "power"), 0.94, 0.0001, "Rank 1 power multiplier")
	assert_almost_eq(CalibrationSystem.multiplier(state, target, "effect"), 1.06, 0.0001, "Rank 1 effect multiplier")
	assert_almost_eq(CalibrationSystem.multiplier(state, "op.someone_else", "heat"), 1.0, 0.0001, "Other modules read ×1")

	var statuses: Array = Array(state.build.get("status_effects", []))
	var projected: int = 0
	for status in statuses:
		if status is Dictionary and str(Dictionary(status).get("id", "")) == "status.calibration.%s" % target:
			projected += 1
			assert_false(Dictionary(status).has("rounds"), "The calibration status never wears off")
	assert_eq(projected, 1, "Exactly one calibration status per module")

	var subs: Array = sim.debug_collect_subscriptions()
	var calibrated: Dictionary = _dispatch_probe_stage(state, subs, target)
	assert_almost_eq(float(calibrated["heat"]), 9.2, 0.001, "The calibrated stage's heat is discounted 8%")
	assert_almost_eq(float(calibrated["cost"]), 9.4, 0.001, "…its power cost 6%")
	assert_almost_eq(float(calibrated["token_mult"]), 1.06, 0.001, "…and its tokens rise 6%")
	var cooling: Dictionary = _dispatch_probe_stage(state, subs, target, -10.0)
	assert_almost_eq(float(cooling["heat"]), -10.0, 0.001, "A cooling stage's credit is not shrunk")
	var untouched: Dictionary = _dispatch_probe_stage(state, subs, "op.someone_else")
	assert_almost_eq(float(untouched["heat"]), 10.0, 0.001, "Other stages keep their heat")
	assert_almost_eq(float(untouched["cost"]), 10.0, 0.001, "…their cost")
	assert_almost_eq(float(untouched["token_mult"]), 1.0, 0.001, "…and their tokens")

	# Rank 2 compounds.
	_grant_spares(sim, target, 2)
	assert_true(
		sim.calibrate_module(target, CalibrationSystem.consumable_modules(state, target).slice(0, 2)),
		"Rank 2 commits"
	)
	var rank_two: Dictionary = _dispatch_probe_stage(state, sim.debug_collect_subscriptions(), target)
	assert_almost_eq(float(rank_two["heat"]), 10.0 * 0.92 * 0.92, 0.001, "Rank 2 heat compounds")
	assert_almost_eq(float(rank_two["token_mult"]), 1.06 * 1.06, 0.001, "Rank 2 tokens compound")
	sim.free()


## Dispatches one `board.stage_resolved` for `module_id` with 10 heat, 10 cost
## and ×1 tokens on the stage (as a module's own adds would leave it) and
## returns the stage values the run's subscriptions settled on.
func _dispatch_probe_stage(state: RunState, subs: Array, module_id: String, heat: float = 10.0) -> Dictionary:
	var resolver := EffectResolver.new()
	var mod_ctx := ModifierContext.new("board.stage_resolved", state)
	mod_ctx.rng = DeterministicRng.new(7)
	mod_ctx.extras = {"module_id": module_id, "op_id": module_id}
	mod_ctx.set_value("stage.heat", heat)
	mod_ctx.set_value("stage.cost", 10.0)
	mod_ctx.set_value("stage.token_mult", 1.0)
	resolver.begin_action("calibration.probe")
	resolver.dispatch("board.stage_resolved", mod_ctx, subs)
	return {
		"heat": float(mod_ctx.get_value("stage.heat", 0.0)),
		"cost": float(mod_ctx.get_value("stage.cost", 0.0)),
		"token_mult": float(mod_ctx.get_value("stage.token_mult", 1.0)),
	}


func _test_calibration_survives_save_load() -> void:
	var rig: Dictionary = _calibration_rig(9704)
	var sim: Node = rig["sim"]
	var target: String = rig["target"]
	assert_true(sim.calibrate_module(target, rig["spare"]), "Rank 1 commits")
	var owned: Array = Array(sim.run_state.build.get("modules", [])).duplicate()
	var saved: Dictionary = sim.run_state.to_dict()
	var sim2: Node = load("res://core/simulation.gd").new()
	sim2.autosave_enabled = false
	sim2.run_state.from_dict(saved)
	sim2.phase = sim2.Phase.ROUND_PREP
	assert_eq(sim2.module_calibration_rank(target), 1, "Rank survives save/load")
	assert_eq(Array(sim2.run_state.build.get("modules", [])), owned, "The trimmed inventory survives")
	var found: bool = false
	for sub in sim2.debug_collect_subscriptions():
		if str(Dictionary(sub).get("source_id", "")) == "calibration.%s" % target:
			found = true
	assert_true(found, "The loaded run still carries the calibration subscription")
	var reloaded: Dictionary = _dispatch_probe_stage(sim2.run_state, sim2.debug_collect_subscriptions(), target)
	assert_almost_eq(float(reloaded["heat"]), 9.2, 0.001, "The loaded run's stage is still discounted")
	sim.free()
	sim2.free()


## The shelf sells tokens: a module's headline figure is the multiplier it puts
## on the batch's tokens, read straight off its unconditional slot effects.
func _test_modules_read_as_token_multipliers() -> void:
	var prompt: ModuleDefinition = ContentDatabase.get_module("op.prompt")
	assert_true(prompt != null, "The starter prompt is in the catalogue")
	assert_almost_eq(prompt.token_multiplier(), 1.25, 0.001, "Hand-Written Prompt is ×1.25 tokens")
	assert_true(prompt.scales_tokens(), "A ×1.25 tokens card scales tokens")
	var description: String = Simulation.get_module_description("op.prompt")
	assert_true(description.contains("×1.25 tokens"), "Its copy reads as tokens: %s" % description)
	assert_false(description.contains("progress"), "Its copy no longer says progress")

	var synthetic := ModuleDefinition.new()
	synthetic.id = "op.synthetic_tokens"
	synthetic.parameters = {"progress": 1.5}
	synthetic.slot_effects = [
		{"operation": "multiply", "target": "stage.progress_mult", "value": "$progress"},
		{"operation": "multiply", "target": "stage.token_mult", "value": 2.0},
		{"operation": "multiply", "target": "stage.quality_mult", "value": 3.0},
		{"operation": "add", "target": "stage.progress_mult", "value": 9.0},
		{
			"operation": "multiply", "target": "stage.progress_mult", "value": 10.0,
			"conditions": [{"left": "$is_first_stage", "operator": "==", "right": true}],
		},
	]
	assert_almost_eq(
		synthetic.token_multiplier(), 3.0, 0.001,
		"Progress and token multipliers fold together; quality, adds and conditional effects stay out"
	)
	var quality_only := ModuleDefinition.new()
	quality_only.slot_effects = [{"operation": "add", "target": "stage.quality", "value": 8}]
	assert_almost_eq(quality_only.token_multiplier(), 1.0, 0.001, "A quality card is ×1 tokens")
	assert_false(quality_only.scales_tokens(), "And does not claim to scale tokens")


func _sim(seed_value: int = 4242) -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(seed_value)
	return sim


func _test_angel_offers_are_perk_only() -> void:
	var sim: Node = _sim(9001)
	for _i in range(12):
		sim.debug_present_angel_offers()
		if sim.pending_choices.is_empty():
			continue
		for offer in sim.pending_choices:
			assert_eq(str(offer.get("type", "")), "perk", "Angel offers are perk-only")
		sim.decline_offers()
		sim.run_state.calendar["round"] = int(sim.run_state.calendar.get("round", 1)) + 1
		MarketService.ensure_module_stock(sim)
	sim.free()


func _test_three_perks_when_pool_permits() -> void:
	var rng := DeterministicRng.new(4242)
	var state := RunState.new()
	state.reset()
	var offers: Array = ContentDatabase.draw_angel_perks(rng, state, 3, [], [])
	assert_eq(offers.size(), 3, "His Table draws three perks when the pool permits")
	var ids: Dictionary = {}
	for offer in offers:
		assert_eq(str(offer.get("type", "")), "perk", "Every offer is a perk")
		ids[str(offer.get("id", ""))] = true
	assert_eq(ids.size(), 3, "The three perks are distinct")


func _test_fewer_than_three_perks_when_pool_is_small() -> void:
	var state := RunState.new()
	state.reset()
	var perk_system := PerkSystem.new()
	var initial: Array = ContentDatabase.draw_angel_perks(
		DeterministicRng.new(4243),
		state,
		200,
		[],
		perk_system.undraftable_ids(state, ContentDatabase)
	)
	assert_true(initial.size() >= 2, "Fresh run has at least two legal perks")
	if initial.size() < 2:
		return
	var allowed: Array = [str(initial[0].get("id", "")), str(initial[1].get("id", ""))]
	var collected: Array = []
	for perk in ContentDatabase.perks:
		if perk.id not in allowed:
			collected.append(perk.id)
	state.build["perks"] = collected
	# Owning everything else may exclude one of the two spares outright; the
	# table shows whatever is still legal, and no more.
	var legal: int = 0
	for perk_id in allowed:
		if perk_system.can_acquire(state, perk_id, ContentDatabase):
			legal += 1
	assert_true(legal >= 1 and legal < 3, "Fewer than three perks remain legal (%d)" % legal)
	var offers: Array = ContentDatabase.draw_angel_perks(
		DeterministicRng.new(4244),
		state,
		3,
		[],
		perk_system.undraftable_ids(state, ContentDatabase)
	)
	assert_eq(offers.size(), legal, "The table shows every legal perk when fewer than three remain")


func _test_taking_perk_closes_draft() -> void:
	var sim: Node = _sim(9002)
	sim.debug_present_angel_offers()
	assert_true(sim.pending_choices.size() > 0, "A table is dealt")
	var offer: Dictionary = sim.pending_choices[0]
	var perk_id: String = str(offer.get("id", ""))
	var taken_before: int = int(sim.run_state.statistics.get("angel_offers_taken", 0))
	assert_true(sim.accept_offer("perk", perk_id), "Taking a perk succeeds")
	assert_true(perk_id in Array(sim.run_state.build.get("perks", [])), "Perk is owned")
	assert_eq(
		int(sim.run_state.statistics.get("angel_offers_taken", 0)),
		taken_before + 1,
		"angel_offers_taken increments"
	)
	assert_true(sim.pending_choices.is_empty(), "Pending choices clear")
	assert_eq(sim.phase, sim.Phase.ROUND_PREP, "Phase leaves Angel Round")
	sim.free()


func _test_decline_still_works() -> void:
	var sim: Node = _sim(9003)
	sim.debug_present_angel_offers()
	var declined_before: int = int(sim.run_state.statistics.get("angel_offers_declined", 0))
	var owned_before: int = Array(sim.run_state.build.get("perks", [])).size()
	sim.decline_offers()
	assert_eq(
		Array(sim.run_state.build.get("perks", [])).size(),
		owned_before,
		"Decline acquires nothing"
	)
	assert_eq(
		int(sim.run_state.statistics.get("angel_offers_declined", 0)),
		declined_before + 1,
		"Decline increments the decline counter"
	)
	assert_eq(sim.phase, sim.Phase.ROUND_PREP, "Decline returns to round prep")
	sim.free()


func _test_angel_reroll_unavailable() -> void:
	var sim: Node = _sim(9004)
	sim.debug_present_angel_offers()
	assert_false(sim.has_method("angel_reroll_cost"), "Angel reroll cost API is removed")
	assert_false(sim.has_method("can_reroll_angel"), "Angel reroll gate API is removed")
	assert_false(sim.has_method("reroll_angel_offers"), "Angel reroll action API is removed")
	sim.free()


func _test_rejects_offer_not_on_table() -> void:
	var sim: Node = _sim(9005)
	sim.debug_present_angel_offers()
	assert_false(
		sim.accept_offer("perk", "perk.technical_debt"),
		"A perk not on the current table is refused"
	)
	assert_eq(sim.phase, sim.Phase.ANGEL_ROUND, "A refused accept leaves the table open")
	sim.free()


func _test_no_eligible_perks_cannot_wedge() -> void:
	var sim: Node = _sim(9006)
	# Owning every perk at once is not legal, but the draw only asks whether
	# each card is already in the build.
	var everything: Array = []
	for perk in ContentDatabase.perks:
		everything.append(perk.id)
	sim.run_state.build["perks"] = everything
	sim.debug_present_angel_offers()
	assert_true(sim.pending_choices.is_empty(), "No offers when every perk is owned")
	assert_eq(sim.phase, sim.Phase.ROUND_PREP, "An empty table does not wedge Angel Round")
	sim.free()


func _test_first_round_has_stock() -> void:
	var sim: Node = _sim(9100)
	var stock: Array = sim.module_market_stock()
	assert_eq(stock.size(), 3, "Bedroom round 1 stocks three modules")
	assert_eq(str(sim.run_state.build.get("dwelling", "")), "bedroom", "Fresh run is in the bedroom")
	sim.free()


func _test_stock_size_scales_by_location() -> void:
	var expected := {
		"bedroom": 3,
		"garage": 4,
		"office_unit": 4,
		"warehouse": 5,
		"datacentre_campus": 5,
		"private_power_grid": 6,
		"moon_facility": 6,
	}
	for location in expected.keys():
		var sim: Node = _sim(9100 + int(expected[location]))
		sim.apply_run_location(sim.run_state, str(location), false)
		sim.run_state.calendar["round"] = 1
		MarketService.restock_modules(sim, false)
		assert_eq(
			sim.module_market_stock().size(),
			int(expected[location]),
			"%s stocks %d modules" % [location, int(expected[location])]
		)
		sim.free()


func _test_market_eligibility_helpers() -> void:
	var state := RunState.new()
	state.reset()
	var module := ModuleDefinition.new()
	module.id = "op.market_gate_probe"
	module.difficulty = PackedStringArray(["hard"])
	module.min_location_tier = 2
	assert_false(
		ContentDatabase.module_is_eligible(module, state),
		"Wrong difficulty and location keep a module out of stock"
	)
	state.flags["difficulty"] = "hard"
	assert_false(
		ContentDatabase.module_is_eligible(module, state),
		"Location gate still applies after difficulty is met"
	)
	state.build["dwelling"] = "office_unit"
	assert_true(
		ContentDatabase.module_is_eligible(module, state),
		"Module becomes eligible when difficulty and location gates are met"
	)
	assert_false(
		ContentDatabase.module_is_eligible(module, state, [module.id]),
		"Explicitly blocked modules stay out of stock"
	)
	state.build["modules"] = [module.id]
	assert_false(
		ContentDatabase.module_is_eligible(module, state),
		"Owned modules stay out of stock"
	)


func _test_stock_excludes_owned_modules() -> void:
	var sim: Node = _sim(9200)
	var stock: Array = sim.module_market_stock()
	assert_true(stock.size() > 0, "Stock exists")
	var first: String = str(stock[0])
	sim.board_system().grant_module(sim.run_state, first, false)
	MarketService.restock_modules(sim, false)
	assert_false(first in sim.module_market_stock(), "Owned modules never appear for sale")
	sim.free()


func _test_opening_market_does_not_reroll() -> void:
	var sim: Node = _sim(9201)
	var before: Array = sim.module_market_stock()
	for _i in range(5):
		assert_eq(sim.module_market_stock(), before, "Opening/refreshing Market does not change stock")
	sim.free()


func _test_save_load_preserves_stock() -> void:
	var sim: Node = _sim(9202)
	sim.run_state.economy["cash"] = 1_000_000.0
	assert_true(sim.reroll_module_market(), "Paid reroll succeeds")
	var stock: Array = sim.module_market_stock()
	var market: Dictionary = Dictionary(sim.run_state.business.get("module_market", {})).duplicate(true)
	var saved: Dictionary = sim.run_state.to_dict()
	var sim2: Node = load("res://core/simulation.gd").new()
	sim2.autosave_enabled = false
	sim2.run_state.from_dict(saved)
	sim2.phase = sim2.Phase.ROUND_PREP
	sim2.rng.set_seed(sim.run_seed)
	assert_eq(sim2.module_market_stock(), stock, "Stock IDs survive save/load")
	var loaded: Dictionary = Dictionary(sim2.run_state.business.get("module_market", {}))
	assert_eq(int(loaded.get("rerolls", -1)), int(market.get("rerolls", 0)), "Reroll count survives")
	assert_eq(str(loaded.get("location", "")), str(market.get("location", "")), "Location stamp survives")
	assert_eq(int(loaded.get("round", -1)), int(market.get("round", 0)), "Round stamp survives")
	sim.free()
	sim2.free()


func _test_next_round_naturally_restocks() -> void:
	var sim: Node = _sim(9203)
	sim.run_state.economy["cash"] = 1_000_000.0
	assert_true(sim.reroll_module_market(), "Paid reroll bumps the counter")
	assert_true(int(sim.run_state.business["module_market"].get("rerolls", 0)) > 0, "Rerolls recorded")
	var sequence_before: int = int(sim.run_state.business["module_market"].get("sequence", 0))
	sim.run_state.calendar["round"] = 2
	MarketService.ensure_module_stock(sim)
	var market: Dictionary = Dictionary(sim.run_state.business.get("module_market", {}))
	assert_eq(int(market.get("round", 0)), 2, "Round stamp advances")
	assert_eq(int(market.get("rerolls", -1)), 0, "Natural restock resets rerolls")
	assert_true(int(market.get("sequence", 0)) > sequence_before, "Sequence advances")
	sim.free()


func _test_chapter_transition_restocks() -> void:
	var sim: Node = _sim(9204)
	var bedroom_sequence: int = int(Dictionary(sim.run_state.business.get("module_market", {})).get("sequence", 0))
	sim.apply_run_location(sim.run_state, "garage", false)
	sim.run_state.calendar["round"] = 1
	MarketService.ensure_module_stock(sim)
	var market: Dictionary = Dictionary(sim.run_state.business.get("module_market", {}))
	assert_eq(str(market.get("location", "")), "garage", "Location stamp follows the chapter")
	assert_eq(sim.module_market_stock().size(), 4, "Garage stocks four modules")
	assert_true(
		int(market.get("sequence", 0)) > bedroom_sequence,
		"Chapter transition advances the market sequence"
	)
	sim.free()


func _test_pricing_and_location_reward_scale() -> void:
	var sim: Node = _sim(9205)
	sim.run_state.economy["round_rent"] = 1000.0
	var multipliers: Dictionary = ContentDatabase.balance["economy"]["module_market"][
		"rarity_price_rent_mult"
	]
	for rarity in multipliers:
		var found: ModuleDefinition = null
		for module in ContentDatabase.modules:
			if module.rarity == str(rarity):
				found = module
				break
		assert_true(found != null, "Catalogue contains %s module pricing probe" % rarity)
		if found != null:
			assert_almost_eq(
				sim.module_market_price(found.id),
				1000.0 * float(multipliers[rarity]),
				0.01,
				"%s price follows the rent multiplier" % rarity
			)
	sim.apply_run_location(sim.run_state, "garage", false)
	MarketService.ensure_module_stock(sim)
	# Garage: rent share 1400 × 0.15 = 210, job share 5000 × 0.05 = 250,
	# major_purchase share 15000 × 0.02 = 300 — the wealth anchor wins.
	assert_almost_eq(
		sim.module_market_reroll_cost(),
		300.0,
		0.01,
		"Garage reroll uses 2% of its 15000 major_purchase when that exceeds rent and job shares"
	)
	sim.free()


func _test_purchase_flow() -> void:
	var sim: Node = _sim(9300)
	sim.run_state.economy["cash"] = 1_000_000.0
	var stock: Array = sim.module_market_stock()
	assert_true(stock.size() > 0, "Shelf has stock")
	var module_id: String = str(stock[0])
	var price: float = sim.module_market_price(module_id)
	var cash_before: float = float(sim.run_state.economy.get("cash", 0.0))
	var drafted_before: int = int(sim.run_state.statistics.get("modules_drafted", 0))
	var length_before: int = stock.size()
	var acquired: Array = []
	var on_acquired := func(acquired_id: String) -> void:
		acquired.append(acquired_id)
	EventBus.module_acquired.connect(on_acquired)
	assert_true(sim.buy_module(module_id), "Purchase succeeds")
	EventBus.module_acquired.disconnect(on_acquired)
	assert_almost_eq(
		float(sim.run_state.economy.get("cash", 0.0)),
		cash_before - price,
		0.01,
		"Cash falls by the quoted price"
	)
	assert_true(module_id in Array(sim.run_state.build.get("modules", [])), "Module is owned")
	assert_false(module_id in sim.module_market_stock(), "Purchased ID leaves the shelf")
	assert_eq(sim.module_market_stock().size(), length_before - 1, "Purchase does not auto-refill")
	assert_eq(
		int(sim.run_state.statistics.get("modules_drafted", 0)),
		drafted_before + 1,
		"modules_drafted increments on purchase"
	)
	assert_eq(acquired, [module_id], "Purchase emits module_acquired once for the bought ID")
	assert_false(
		module_id in Array(sim.board_system().slots(sim.run_state)),
		"Market purchases stay on the bench"
	)
	sim.free()


func _test_cannot_buy_without_cash_or_absent() -> void:
	var sim: Node = _sim(9301)
	var stock: Array = sim.module_market_stock()
	var module_id: String = str(stock[0])
	sim.run_state.economy["cash"] = 0.0
	assert_false(sim.can_buy_module(module_id), "Cannot buy without cash")
	assert_false(sim.buy_module(module_id), "Purchase without cash is refused")
	assert_false(sim.buy_module("op.linter"), "Absent module is refused")
	sim.run_state.economy["cash"] = 1_000_000.0
	sim.board_system().grant_module(sim.run_state, module_id, false)
	assert_false(sim.can_buy_module(module_id), "Owned module left in stale stock is rejected")
	assert_false(sim.buy_module(module_id), "Owned module cannot be purchased twice")
	sim.free()


func _test_can_buy_several_in_one_round() -> void:
	var sim: Node = _sim(9302)
	sim.run_state.economy["cash"] = 1_000_000.0
	var bought: int = 0
	for module_id in sim.module_market_stock().duplicate():
		if sim.buy_module(str(module_id)):
			bought += 1
	assert_true(bought >= 2, "Multiple modules can be bought in one visit")
	sim.free()


func _test_reroll_escalation_and_reset() -> void:
	var sim: Node = _sim(9400)
	sim.run_state.economy["cash"] = 1_000_000.0
	var first: float = sim.module_market_reroll_cost()
	assert_true(first > 0.0, "First reroll has a positive cost")
	assert_true(sim.reroll_module_market(), "First reroll succeeds")
	var second: float = sim.module_market_reroll_cost()
	assert_almost_eq(second, first * 2.0, 0.01, "Reroll cost doubles")
	assert_true(sim.reroll_module_market(), "Second reroll succeeds")
	var third: float = sim.module_market_reroll_cost()
	assert_almost_eq(third, first * 4.0, 0.01, "Reroll cost keeps escalating")
	sim.run_state.calendar["round"] = 2
	MarketService.ensure_module_stock(sim)
	assert_almost_eq(sim.module_market_reroll_cost(), first, 0.01, "Natural restock resets reroll cost")
	sim.free()


func _test_reroll_charges_and_avoids_old_stock() -> void:
	var sim: Node = _sim(9402)
	sim.run_state.economy["cash"] = 1_000_000.0
	var previous: Array = sim.module_market_stock()
	var cost: float = sim.module_market_reroll_cost()
	var cash_before: float = float(sim.run_state.economy.get("cash", 0.0))
	assert_true(sim.reroll_module_market(), "Paid reroll succeeds with a large pool")
	assert_almost_eq(
		float(sim.run_state.economy.get("cash", 0.0)),
		cash_before - cost,
		0.01,
		"Reroll deducts its quoted cost"
	)
	var replacement: Array = sim.module_market_stock()
	for module_id in replacement:
		assert_false(
			module_id in previous,
			"Reroll avoids every previous shelf card when the pool is large"
		)
	sim.free()


func _test_reroll_small_pool_fallback() -> void:
	var sim: Node = _sim(9403)
	sim.run_state.economy["cash"] = 1_000_000.0
	var retained: Array = sim.module_market_stock().slice(0, 2)
	assert_eq(retained.size(), 2, "Fallback probe starts with two stocked modules")
	var owned: Array = []
	for module in ContentDatabase.modules:
		if module.id not in retained:
			owned.append(module.id)
	sim.run_state.build["modules"] = owned
	sim.run_state.business["module_market"]["stock"] = retained.duplicate()
	assert_true(sim.reroll_module_market(), "Small-pool reroll succeeds")
	assert_eq(
		sim.module_market_stock().size(),
		2,
		"Fallback fills as much of the shelf as the eligible pool permits"
	)
	for module_id in retained:
		assert_true(
			module_id in sim.module_market_stock(),
			"Fallback permits a previous card only when needed to fill the small pool"
		)
	sim.free()


func _test_reroll_fills_empty_slots() -> void:
	var sim: Node = _sim(9401)
	sim.run_state.economy["cash"] = 1_000_000.0
	var capacity: int = MarketService.module_stock_size(sim)
	var first: String = str(sim.module_market_stock()[0])
	assert_true(sim.buy_module(first), "Buy one module to empty a slot")
	assert_eq(sim.module_market_stock().size(), capacity - 1, "Shelf shrinks after purchase")
	assert_true(sim.reroll_module_market(), "Reroll succeeds")
	assert_eq(sim.module_market_stock().size(), capacity, "Reroll refills to capacity")
	sim.free()


func _test_market_closed_during_angel() -> void:
	var sim: Node = _sim(9500)
	sim.run_state.economy["cash"] = 1_000_000.0
	sim.debug_present_angel_offers()
	assert_eq(sim.phase, sim.Phase.ANGEL_ROUND, "Angel table is open")
	assert_false(sim.market_open(), "Market is closed during the perk decision")
	var stock: Array = Array(Dictionary(sim.run_state.business.get("module_market", {})).get("stock", []))
	if not stock.is_empty():
		assert_false(sim.buy_module(str(stock[0])), "Module purchase rejected during angel")
	assert_false(sim.can_reroll_module_market(), "Module reroll rejected during angel")
	assert_false(sim.buy_upgrade("upgrade.portable_ac"), "Hardware purchase rejected during angel")
	assert_eq(sim.phase, sim.Phase.ANGEL_ROUND, "Shopping does not close the perk draft")
	sim.decline_offers()
	assert_true(sim.market_open(), "Market reopens after decline")
	sim.free()


func _test_mixed_pending_choice_migration() -> void:
	var sim: Node = _sim(9600)
	sim.phase = sim.Phase.ANGEL_ROUND
	sim.pending_choices = [
		{"type": "module", "id": "op.linter", "label": "Linter", "description": "", "cost": 0.0},
		{"type": "operation", "id": "op.whiteboard", "label": "Whiteboard", "description": "", "cost": 0.0},
	]
	sim._migrate_pending_choices()
	assert_true(
		sim.phase == sim.Phase.ANGEL_ROUND or sim.phase == sim.Phase.ROUND_PREP,
		"Migration does not wedge the phase"
	)
	for choice in sim.pending_choices:
		assert_eq(str(choice.get("type", "")), "perk", "Only perks remain after migration")
	assert_false(
		"op.linter" in Array(sim.run_state.build.get("modules", [])),
		"Discarded module choices are not granted free"
	)
	sim.free()
