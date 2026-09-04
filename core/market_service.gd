class_name MarketService
extends RefCounted

## Buying and selling kit at the Market: the one place a run spends cash on
## upgrades and modules and gets some of it back. Pulled out of `Simulation`,
## which stays the facade every screen actually talks to — see
## `Simulation.buy_upgrade()` etc., which now just delegate here — per the
## Phase 5 split (RunLifecycle/WorkSession/SimulationPreview/MarketService).
##
## `sim` is the owning `Simulation` node, taken as a plain `Node` rather than
## `Simulation` to avoid a circular class reference. Collaborators use system
## accessors (`upgrade_system()`, `economy_system()`, …) rather than underscore
## fields, and routing methods on the facade for autosave / closing a draft.


## Selling happens at the same counter as buying, so it is allowed in exactly
## the phases the Market is open in. Perk decisions close the counter until
## the player takes or declines.
static func market_open(sim: Node) -> bool:
	return sim.phase == sim.Phase.ROUND_END or sim.phase == sim.Phase.ROUND_PREP


static func can_buy_upgrade(sim: Node, upgrade_id: String) -> bool:
	if not market_open(sim):
		return false
	return sim.upgrade_system().can_purchase(sim.run_state, upgrade_id, ContentDatabase)


static func buy_upgrade(sim: Node, upgrade_id: String) -> bool:
	if not market_open(sim):
		return false
	if not sim.upgrade_system().purchase(
		sim.run_state, upgrade_id, ContentDatabase, sim.effect_resolver, sim.economy_system()
	):
		return false
	# An upgrade may have widened the board, which only takes effect once the
	# slot array is resized to match.
	sim.board_system().ensure_board(sim.run_state, ContentDatabase)
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	EventBus.emit_event(EventBus.EVENT_UPGRADE_PURCHASED, {"upgrade_id": upgrade_id})
	sim._autosave()
	return true


static func hardware_sale_reason(sim: Node, hardware_key: String) -> String:
	if not market_open(sim):
		return "The Market is closed once a round is under way. Shop between rounds."
	return UpgradeSystem.sell_reason(sim.run_state, hardware_key, ContentDatabase)


static func hardware_sale_refund(sim: Node, hardware_key: String) -> float:
	return UpgradeSystem.sell_refund(sim.run_state, hardware_key, ContentDatabase)


static func can_sell_hardware(sim: Node, hardware_key: String) -> bool:
	return hardware_sale_reason(sim, hardware_key) == ""


## Decommissions one unit of owned kit, freeing its floor slot and refunding
## part of what the most recent copy cost.
static func sell_hardware(sim: Node, hardware_key: String) -> bool:
	if not market_open(sim):
		return false
	if not sim.upgrade_system().sell(sim.run_state, hardware_key, ContentDatabase, sim.economy_system()):
		return false
	sim.run_state.statistics["hardware_sold"] = int(sim.run_state.statistics.get("hardware_sold", 0)) + 1
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	EventBus.emit_event(EventBus.EVENT_HARDWARE_SOLD, {"hardware_key": hardware_key})
	sim.achievement_system().evaluate_tick(sim.run_state, ContentDatabase)
	sim._autosave()
	return true


# --- Cabinet systems ---------------------------------------------------------

## Buys the next tier of one cabinet system (compute, cooling, power,
## backplane, control). Returns the UpgradeSystem result — `ok`, the Market's
## `reason` when refused, the tier reached and every capacity that moved — so
## the SYSTEMS shelf can print the reveal without asking again.
static func upgrade_cabinet_system(sim: Node, system_id: String) -> Dictionary:
	if not market_open(sim):
		return {
			"ok": false,
			"reason": "MARKET CLOSED",
			"system_id": system_id,
			"tier": CabinetSystems.tier(sim.run_state, system_id),
			"previous_tier": CabinetSystems.tier(sim.run_state, system_id),
			"cost": CabinetSystems.next_tier_cost(sim.run_state, system_id),
			"effect": "",
			"delta": {},
		}
	var result: Dictionary = sim.upgrade_system().upgrade_cabinet_system(
		sim.run_state, system_id, sim.economy_system()
	)
	if not bool(result.get("ok", false)):
		return result
	# A wider backplane or control rack only takes effect once the board is
	# resized to match; a new compute or cooling tier changes the rig's rate.
	sim.board_system().ensure_board(sim.run_state, ContentDatabase)
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	EventBus.emit_event(EventBus.EVENT_CABINET_SYSTEM_UPGRADED, {
		"system_id": system_id, "tier": int(result.get("tier", 0)),
	})
	sim._autosave()
	return result


static func cabinet_system_tiers(sim: Node) -> Dictionary:
	return CabinetSystems.tiers(sim.run_state)


static func cabinet_generation(sim: Node) -> Dictionary:
	return CabinetSystems.generation(sim.run_state)


## Everything a SYSTEMS row needs about one system; when the Market is closed
## the row is still described, only the button is dead.
static func cabinet_system_next(sim: Node, system_id: String) -> Dictionary:
	var info: Dictionary = CabinetSystems.next_tier_info(sim.run_state, system_id)
	if not market_open(sim) and bool(info.get("can_upgrade", false)):
		info["can_upgrade"] = false
		info["reason"] = "MARKET CLOSED"
	return info


# --- Module market -----------------------------------------------------------

static func _module_market_tuning() -> Dictionary:
	return Dictionary(ContentDatabase.balance.get("economy", {}).get("module_market", {}))


static func ensure_module_market_state(sim: Node) -> Dictionary:
	var business: Dictionary = sim.run_state.business
	var state: Variant = business.get("module_market", {})
	if not state is Dictionary:
		state = {}
	var market: Dictionary = state
	if not market.has("stock") or not market["stock"] is Array:
		market["stock"] = []
	if not market.has("location"):
		market["location"] = ""
	if not market.has("round"):
		market["round"] = 0
	if not market.has("sequence"):
		market["sequence"] = 0
	if not market.has("rerolls"):
		market["rerolls"] = 0
	business["module_market"] = market
	return market


static func module_stock_size(sim: Node) -> int:
	var slots: Array = Array(_module_market_tuning().get("slots_by_location_tier", [3]))
	var tier: int = ContentDatabase.location_tier_for_run(sim.run_state)
	if slots.is_empty():
		return 3
	return maxi(1, int(slots[clampi(tier, 0, slots.size() - 1)]))


static func module_stock(sim: Node) -> Array:
	ensure_module_stock(sim)
	return Array(ensure_module_market_state(sim).get("stock", [])).duplicate()


## Restock when missing, or when the current location/round stamp no longer
## matches. Opening the Market never regenerates the shelf.
static func ensure_module_stock(sim: Node) -> void:
	var market: Dictionary = ensure_module_market_state(sim)
	var location: String = str(sim.run_state.build.get("dwelling", "bedroom"))
	var round_number: int = int(sim.run_state.calendar.get("round", 1))
	var needs_restock: bool = (
		str(market.get("location", "")) != location
		or int(market.get("round", 0)) != round_number
	)
	# Missing state (empty location stamp) always restocks. An already-current
	# empty shelf from purchases must not refill until the stamp changes.
	if str(market.get("location", "")) == "" and int(market.get("round", 0)) == 0:
		needs_restock = true
	if needs_restock:
		restock_modules(sim, false)


static func restock_modules(sim: Node, paid_reroll: bool = false) -> void:
	var market: Dictionary = ensure_module_market_state(sim)
	var location: String = str(sim.run_state.build.get("dwelling", "bedroom"))
	var round_number: int = int(sim.run_state.calendar.get("round", 1))
	var blocked: Array = []
	if paid_reroll:
		for module_id in Array(market.get("stock", [])):
			var text_id: String = str(module_id)
			if text_id != "" and text_id not in blocked:
				blocked.append(text_id)
	market["sequence"] = int(market.get("sequence", 0)) + 1
	if not paid_reroll:
		market["rerolls"] = 0
		market["location"] = location
		market["round"] = round_number
	var capacity: int = module_stock_size(sim)
	var drawn: Array[ModuleDefinition] = _draw_shelf(sim, market, capacity, blocked)
	if paid_reroll and drawn.size() < capacity and not blocked.is_empty():
		# Keep every genuinely new card from the first pass, then permit old
		# shelf IDs only for the slots the reduced pool could not fill.
		var fallback_blocked: Array = []
		for module in drawn:
			fallback_blocked.append(module.id)
		drawn.append_array(
			_draw_shelf(sim, market, capacity - drawn.size(), fallback_blocked)
		)
	var stock: Array = []
	for module in drawn:
		stock.append(module.id)
	market["stock"] = stock
	sim.run_state.business["module_market"] = market


static func _draw_shelf(
	sim: Node, market: Dictionary, capacity: int, blocked_ids: Array
) -> Array[ModuleDefinition]:
	var owned_tags: Array = sim.perk_system().owned_tags(sim.run_state, ContentDatabase)
	var rng: DeterministicRng = _module_market_rng(sim, market)
	return ContentDatabase.draw_market_modules(
		rng, sim.run_state, capacity, owned_tags, blocked_ids
	)


static func _module_market_rng(sim: Node, market: Dictionary) -> DeterministicRng:
	var location: String = str(market.get("location", sim.run_state.build.get("dwelling", "bedroom")))
	var round_number: int = int(market.get("round", sim.run_state.calendar.get("round", 1)))
	var sequence: int = int(market.get("sequence", 0))
	var rerolls: int = int(market.get("rerolls", 0))
	return sim.rng.derive(
		"module_market.%s.%d.sequence.%d.reroll.%d" % [location, round_number, sequence, rerolls]
	)


static func module_price(sim: Node, module_id: String) -> float:
	var module: ModuleDefinition = ContentDatabase.get_module(module_id)
	if module == null:
		return 0.0
	var tuning: Dictionary = _module_market_tuning()
	var rarity_mults: Dictionary = Dictionary(tuning.get("rarity_price_rent_mult", {}))
	var mult: float = float(rarity_mults.get(module.rarity, 1.0))
	var rent: float = float(sim.run_state.economy.get("round_rent", 400.0))
	var floor_price: float = float(tuning.get("price_floor", 25.0))
	return maxf(floor_price, snappedf(rent * mult, 1.0))


static func can_buy_module(sim: Node, module_id: String) -> bool:
	if not market_open(sim):
		return false
	ensure_module_stock(sim)
	var market: Dictionary = ensure_module_market_state(sim)
	if module_id not in Array(market.get("stock", [])):
		return false
	var module: ModuleDefinition = ContentDatabase.get_module(module_id)
	if module == null:
		return false
	if not ContentDatabase.module_is_eligible(module, sim.run_state):
		return false
	return sim.economy_system().can_afford(sim.run_state, module_price(sim, module_id))


static func buy_module(sim: Node, module_id: String) -> bool:
	if not can_buy_module(sim, module_id):
		return false
	var cost: float = module_price(sim, module_id)
	if not sim.economy_system().purchase(sim.run_state, cost, "module_market:%s" % module_id):
		return false
	if not sim.board_system().grant_module(sim.run_state, module_id, false):
		# Refund if ownership somehow failed after the charge.
		sim.economy_system().credit(sim.run_state, cost, "module_market_refund:%s" % module_id)
		return false
	var market: Dictionary = ensure_module_market_state(sim)
	var stock: Array = Array(market.get("stock", []))
	stock.erase(module_id)
	market["stock"] = stock
	sim.run_state.business["module_market"] = market
	# Legacy counter: historically "modules drafted"; now modules acquired.
	sim.run_state.statistics["modules_drafted"] = int(
		sim.run_state.statistics.get("modules_drafted", 0)
	) + 1
	EventBus.emit_event(EventBus.EVENT_MODULE_ACQUIRED, {"module_id": module_id})
	sim.achievement_system().evaluate_tick(sim.run_state, ContentDatabase)
	sim._autosave()
	return true


static func module_reroll_cost(sim: Node) -> float:
	ensure_module_stock(sim)
	var market: Dictionary = ensure_module_market_state(sim)
	var tuning: Dictionary = _module_market_tuning()
	var rent: float = float(sim.run_state.economy.get("round_rent", 400.0))
	var base: float = maxf(
		rent * float(tuning.get("reroll_rent_mult", 0.15)),
		_location_base_job_reward(sim) * float(tuning.get("reroll_job_reward_mult", 0.05))
	)
	var growth: float = float(tuning.get("reroll_growth", 2.0))
	var rerolls: int = int(market.get("rerolls", 0))
	return snappedf(base * pow(growth, float(rerolls)), 1.0)


static func can_reroll_modules(sim: Node) -> bool:
	if not market_open(sim):
		return false
	return sim.economy_system().can_afford(sim.run_state, module_reroll_cost(sim))


static func reroll_modules(sim: Node) -> bool:
	if not can_reroll_modules(sim):
		return false
	var cost: float = module_reroll_cost(sim)
	if not sim.economy_system().purchase(sim.run_state, cost, "module_market_reroll"):
		return false
	var market: Dictionary = ensure_module_market_state(sim)
	market["rerolls"] = int(market.get("rerolls", 0)) + 1
	sim.run_state.business["module_market"] = market
	restock_modules(sim, true)
	sim._autosave()
	return true


static func _location_base_job_reward(sim: Node) -> float:
	var bands: Array = JobSystem.location_bands(ContentDatabase)
	if not bands.is_empty():
		var tier: int = JobSystem.location_tier(sim.run_state, ContentDatabase)
		return float(Dictionary(bands[clampi(tier, 0, bands.size() - 1)]).get(
			"base_reward", sim.run_state.economy.get("round_rent", 400.0)
		))
	return float(sim.run_state.economy.get("round_rent", 400.0))


static func next_module_restock_round(sim: Node) -> int:
	ensure_module_stock(sim)
	var market: Dictionary = ensure_module_market_state(sim)
	return int(market.get("round", int(sim.run_state.calendar.get("round", 1)))) + 1
