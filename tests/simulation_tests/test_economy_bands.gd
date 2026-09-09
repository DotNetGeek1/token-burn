extends TestCase

## Per-chapter economy bands: module prices and the reroll fee are measured
## against the chapter's `base_reward` (one ordinary contract) so no shelf is
## ever pocket change next to a single job, and no refresh is priced out.


## A legendary should cost somewhere between half a contract and three of
## them. The bedroom sits at the top of the band on purpose: its legendary
## anchors to rent (3.5 × 400) and that scarcity is the opening chapter's
## design. Every later chapter is anchored to `major_purchase` instead.
const LEGENDARY_TO_REWARD_MIN: float = 0.5
const LEGENDARY_TO_REWARD_MAX: float = 3.0
const REROLL_TO_REWARD_MIN: float = 0.01
const REROLL_TO_REWARD_MAX: float = 0.35


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_every_band_is_priced_against_its_contract()
	_test_major_purchase_anchor_takes_over_after_the_bedroom()


func _sim(seed_value: int) -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(seed_value)
	return sim


func _probe(rarity: String) -> ModuleDefinition:
	for module in ContentDatabase.modules:
		if module.rarity == rarity:
			return module
	return null


func _test_every_band_is_priced_against_its_contract() -> void:
	var bands: Array = JobSystem.location_bands(ContentDatabase)
	assert_eq(bands.size(), 7, "Seven chapter bands are loaded")
	var rare: ModuleDefinition = _probe("rare")
	var legendary: ModuleDefinition = _probe("legendary")
	assert_true(rare != null, "Catalogue has a rare pricing probe")
	assert_true(legendary != null, "Catalogue has a legendary pricing probe")
	if rare == null or legendary == null:
		return
	var seed_value: int = 7100
	for band in bands:
		var location: String = str(Dictionary(band).get("location", ""))
		var base_reward: float = float(Dictionary(band).get("base_reward", 0.0))
		assert_true(base_reward > 0.0, "%s has a positive base_reward" % location)
		if base_reward <= 0.0:
			continue
		var sim: Node = _sim(seed_value)
		seed_value += 1
		sim.apply_run_location(sim.run_state, location, false)
		sim.run_state.calendar["round"] = 1
		MarketService.restock_modules(sim, false)

		var legendary_price: float = sim.module_market_price(legendary.id)
		var legendary_ratio: float = legendary_price / base_reward
		assert_true(
			legendary_ratio >= LEGENDARY_TO_REWARD_MIN,
			"%s legendary (%.0f) is not pocket change next to one contract (%.0f): ratio %.2f" % [
				location, legendary_price, base_reward, legendary_ratio,
			]
		)
		assert_true(
			legendary_ratio <= LEGENDARY_TO_REWARD_MAX,
			"%s legendary (%.0f) is not priced out of a chapter (%.0f): ratio %.2f" % [
				location, legendary_price, base_reward, legendary_ratio,
			]
		)

		var shelf: int = MarketService.module_stock_size(sim)
		var rare_shelf_total: float = sim.module_market_price(rare.id) * float(shelf)
		assert_true(
			rare_shelf_total > base_reward,
			"%s: a full shelf of %d rares (%.0f) costs more than one contract (%.0f)" % [
				location, shelf, rare_shelf_total, base_reward,
			]
		)

		var reroll: float = sim.module_market_reroll_cost()
		var reroll_ratio: float = reroll / base_reward
		assert_true(
			reroll_ratio >= REROLL_TO_REWARD_MIN,
			"%s first reroll (%.0f) is not trivially cheap against one contract (%.0f): ratio %.3f" % [
				location, reroll, base_reward, reroll_ratio,
			]
		)
		assert_true(
			reroll_ratio <= REROLL_TO_REWARD_MAX,
			"%s first reroll (%.0f) is not punishing against one contract (%.0f): ratio %.3f" % [
				location, reroll, base_reward, reroll_ratio,
			]
		)
		sim.free()


## The rent anchor alone would leave a moon legendary at 21M against a 500M
## contract; the `major_purchase` anchor is what carries prices up the ladder.
func _test_major_purchase_anchor_takes_over_after_the_bedroom() -> void:
	var tuning: Dictionary = ContentDatabase.balance["economy"]["module_market"]
	var ratios: Dictionary = Dictionary(tuning.get("rarity_price_major_purchase_ratio", {}))
	for rarity in ["common", "uncommon", "rare", "legendary"]:
		assert_true(
			float(ratios.get(rarity, 0.0)) > 0.0,
			"economy.json prices %s modules against major_purchase" % rarity
		)
	var probes: Dictionary = {}
	for rarity in ratios:
		var probe: ModuleDefinition = _probe(str(rarity))
		if probe != null:
			probes[str(rarity)] = probe
	for band in JobSystem.location_bands(ContentDatabase):
		var location: String = str(Dictionary(band).get("location", ""))
		if location == "bedroom":
			continue
		var major_purchase: float = float(Dictionary(band).get("major_purchase", 0.0))
		var sim: Node = _sim(7200)
		sim.apply_run_location(sim.run_state, location, false)
		for rarity in probes:
			var expected: float = snappedf(major_purchase * float(ratios[rarity]), 1.0)
			assert_almost_eq(
				sim.module_market_price(probes[rarity].id),
				expected,
				0.01,
				"%s %s price is %.0f (%.2f × major_purchase)" % [location, rarity, expected, float(ratios[rarity])]
			)
		assert_almost_eq(
			sim.module_market_reroll_cost(),
			snappedf(major_purchase * float(tuning.get("reroll_major_purchase_ratio", 0.02)), 1.0),
			0.01,
			"%s first reroll is 2%% of major_purchase" % location
		)
		sim.free()
