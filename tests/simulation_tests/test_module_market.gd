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
	state.build["perk_inventory"] = collected
	var offers: Array = ContentDatabase.draw_angel_perks(
		DeterministicRng.new(4244),
		state,
		3,
		[],
		perk_system.undraftable_ids(state, ContentDatabase)
	)
	assert_eq(offers.size(), 2, "Angel table shows every legal perk when fewer than three remain")


func _test_taking_perk_closes_draft() -> void:
	var sim: Node = _sim(9002)
	sim.debug_present_angel_offers()
	assert_true(sim.pending_choices.size() > 0, "A table is dealt")
	var offer: Dictionary = sim.pending_choices[0]
	var perk_id: String = str(offer.get("id", ""))
	var taken_before: int = int(sim.run_state.statistics.get("angel_offers_taken", 0))
	assert_true(sim.accept_offer("perk", perk_id), "Taking a perk succeeds")
	assert_true(perk_id in Array(sim.run_state.build.get("perk_inventory", [])), "Perk is collected")
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
	var inventory_before: int = Array(sim.run_state.build.get("perk_inventory", [])).size()
	sim.decline_offers()
	assert_eq(
		Array(sim.run_state.build.get("perk_inventory", [])).size(),
		inventory_before,
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
	for perk in ContentDatabase.perks:
		sim.perk_system().collect_perk(sim.run_state, perk.id, ContentDatabase)
	sim.debug_present_angel_offers()
	assert_true(sim.pending_choices.is_empty(), "No offers when every perk is collected")
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
	assert_almost_eq(
		sim.module_market_reroll_cost(),
		250.0,
		0.01,
		"Garage reroll uses 5% of its 5000 base job reward when that exceeds rent share"
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
