class_name MarketService
extends RefCounted

## Buying and selling kit at the Market: the one place a run spends cash on
## upgrades and gets some of it back. Pulled out of `Simulation`, which stays
## the facade every screen actually talks to — see `Simulation.buy_upgrade()`
## etc., which now just delegate here — per the Phase 5 split
## (RunLifecycle/WorkSession/SimulationPreview/MarketService) that the rest of
## the file has yet to follow.
##
## `sim` is the owning `Simulation` node, taken as a plain `Node` rather than
## `Simulation` to avoid a circular class reference. Collaborators use system
## accessors (`upgrade_system()`, `economy_system()`, …) rather than underscore
## fields, and routing methods on the facade for autosave / closing a draft.


## Selling happens at the same counter as buying, so it is allowed in exactly
## the phases the Market is open in.
static func market_open(sim: Node) -> bool:
	return sim.phase == sim.Phase.ANGEL_ROUND or sim.phase == sim.Phase.ROUND_END or sim.phase == sim.Phase.ROUND_PREP


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
	# Shopping past the angels closes their draft.
	if sim.phase == sim.Phase.ANGEL_ROUND:
		sim._after_angel_round()
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
