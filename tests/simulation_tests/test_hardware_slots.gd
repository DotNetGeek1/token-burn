extends TestCase

## Floor space is the constraint the early game is built around: machines can be
## bought more than once, so a room runs out of room, and the only way past that
## inside a run is to sell something already standing in it. A bigger room is a
## later chapter of the campaign, not a purchase.
## Components sidestep the constraint on purpose — they go inside a machine that
## is already standing there — so the cap they answer to is host count.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_machines_can_be_bought_twice()
	_test_each_copy_costs_more()
	_test_components_take_no_floor_space()
	_test_a_component_needs_a_machine_to_go_in()
	_test_duplicates_add_up_to_throughput()
	_test_selling_frees_the_slot_and_pays_back()
	_test_what_cannot_be_sold()


func _shop(location: String = "bedroom") -> Dictionary:
	var state := RunState.new()
	# These count what the shop sells and what the floor holds, so the machine
	# the room comes with would be an extra unit nobody bought.
	Simulation.apply_run_location(state, location, false)
	state.economy["cash"] = 100000000.0
	return {
		"state": state,
		"upgrades": UpgradeSystem.new(),
		"economy": EconomySystem.new(),
		"resolver": EffectResolver.new(),
	}


func _buy(shop: Dictionary, upgrade_id: String) -> bool:
	return shop["upgrades"].purchase(
		shop["state"], upgrade_id, ContentDatabase, shop["resolver"], shop["economy"]
	)


func _sell(shop: Dictionary, key: String) -> bool:
	return shop["upgrades"].sell(shop["state"], key, ContentDatabase, shop["economy"])


func _slots_used(shop: Dictionary) -> int:
	return UpgradeSystem.hardware_slots_used(shop["state"], ContentDatabase)


func _test_machines_can_be_bought_twice() -> void:
	var shop: Dictionary = _shop()
	assert_eq(_slots_used(shop), 1, "The run starts with the laptop on the floor")
	assert_true(_buy(shop, "upgrade.custom_desktop"), "A desktop fits beside it")
	assert_eq(_slots_used(shop), 2, "And takes the bedroom's second slot")
	assert_false(_buy(shop, "upgrade.custom_desktop"), "A second desktop has nowhere to stand")

	# The same shopping trip a chapter later, where the room is the thing that
	# changed rather than anything on the shelves.
	var garage: Dictionary = _shop("garage")
	assert_true(_buy(garage, "upgrade.custom_desktop"), "A desktop fits beside the laptop")
	assert_true(_buy(garage, "upgrade.custom_desktop"), "And a second one")
	assert_true(_buy(garage, "upgrade.custom_desktop"), "And a third")
	assert_eq(_slots_used(garage), 4, "Four machines in a four-slot garage")
	assert_false(_buy(garage, "upgrade.custom_desktop"), "The fourth desktop is one too many")
	assert_eq(
		UpgradeSystem.installed_count(garage["state"], "custom_desktop"),
		3,
		"Every copy bought is a machine owned"
	)
	assert_eq(
		UpgradeSystem.upgrade_level(garage["state"], "upgrade.custom_desktop"),
		3,
		"And the level tracks the count so pricing can climb with it"
	)


func _test_each_copy_costs_more() -> void:
	var desktop: UpgradeDefinition = ContentDatabase.get_upgrade("upgrade.custom_desktop")
	assert_true(desktop.repeatable, "The desktop is something you can own more than one of")
	assert_true(desktop.cost_growth > 1.0, "And each one costs more than the last")
	assert_almost_eq(
		UpgradeSystem.purchase_cost(desktop, 1),
		desktop.cost * desktop.cost_growth,
		0.01,
		"The second is priced one step up the ramp"
	)
	assert_true(
		UpgradeSystem.purchase_cost(desktop, 3) > UpgradeSystem.purchase_cost(desktop, 2),
		"So stacking one model is never simply the best move"
	)


func _test_components_take_no_floor_space() -> void:
	var shop: Dictionary = _shop()
	var before: int = _slots_used(shop)
	assert_true(_buy(shop, "upgrade.laptop_ram"), "The laptop takes more RAM")
	assert_eq(_slots_used(shop), before, "Which goes inside it rather than beside it")
	assert_true(_buy(shop, "upgrade.custom_desktop"), "So the desktop still fits the bedroom")
	assert_eq(_slots_used(shop), 2, "And the room is only now full")


func _test_a_component_needs_a_machine_to_go_in() -> void:
	var shop: Dictionary = _shop()
	assert_false(
		shop["upgrades"].can_purchase(shop["state"], "upgrade.second_gpu", ContentDatabase),
		"A graphics card needs a desktop to go in"
	)
	assert_false(_buy(shop, "upgrade.second_gpu"), "And the purchase is refused, not just hidden")

	assert_true(_buy(shop, "upgrade.custom_desktop"), "Buying the desktop gives it a home")
	assert_true(_buy(shop, "upgrade.second_gpu"), "So the card goes in")
	assert_false(_buy(shop, "upgrade.second_gpu"), "But a second card needs a second desktop")

	var garage: Dictionary = _shop("garage")
	assert_true(_buy(garage, "upgrade.custom_desktop"), "A garage has room for two desktops")
	assert_true(_buy(garage, "upgrade.custom_desktop"), "So the second one goes in")
	assert_true(_buy(garage, "upgrade.second_gpu"), "Which is a home for the first card")
	assert_true(_buy(garage, "upgrade.second_gpu"), "And the second")
	assert_false(_buy(garage, "upgrade.second_gpu"), "But not a third")
	assert_eq(
		UpgradeSystem.installed_count(garage["state"], "second_gpu"),
		2,
		"One card per desktop owned, no more"
	)


func _test_duplicates_add_up_to_throughput() -> void:
	var shop: Dictionary = _shop("garage")
	var compute := ComputeSystem.new()
	var rng := DeterministicRng.new(7)
	compute.recalculate(shop["state"], shop["resolver"], [], rng)
	var one_machine: float = float(shop["state"].compute.get("local_capacity", 0.0))

	assert_true(_buy(shop, "upgrade.custom_desktop"), "Add a desktop")
	compute.recalculate(shop["state"], shop["resolver"], [], rng)
	var two_machines: float = float(shop["state"].compute.get("local_capacity", 0.0))
	assert_true(two_machines > one_machine, "A second machine raises local capacity")

	assert_true(_buy(shop, "upgrade.custom_desktop"), "And buy the same model again")
	compute.recalculate(shop["state"], shop["resolver"], [], rng)
	assert_almost_eq(
		float(shop["state"].compute.get("local_capacity", 0.0)),
		two_machines + (two_machines - one_machine),
		1.0,
		"Two of the same machine are worth exactly twice one of them"
	)
	assert_true(
		float(shop["state"].compute.get("power_draw", 0.0)) > 65.0,
		"And both of them are drawing power"
	)


func _test_selling_frees_the_slot_and_pays_back() -> void:
	var shop: Dictionary = _shop("garage")
	assert_true(_buy(shop, "upgrade.custom_desktop"), "Buy a machine")
	assert_true(_buy(shop, "upgrade.custom_desktop"), "Buy a second")
	var slots_before: int = _slots_used(shop)
	var cash_before: float = float(shop["state"].economy.get("cash", 0.0))
	var refund: float = UpgradeSystem.sell_refund(shop["state"], "custom_desktop", ContentDatabase)
	var desktop: UpgradeDefinition = ContentDatabase.get_upgrade("upgrade.custom_desktop")
	assert_almost_eq(
		refund,
		UpgradeSystem.purchase_cost(desktop, 1) * UpgradeSystem.SELL_REFUND_RATIO,
		0.01,
		"A machine is sold on for part of what the last one cost"
	)

	assert_true(_sell(shop, "custom_desktop"), "And it can go")
	assert_eq(_slots_used(shop), slots_before - 1, "Which frees the floor slot")
	assert_almost_eq(
		float(shop["state"].economy.get("cash", 0.0)),
		cash_before + refund,
		0.01,
		"The refund lands as cash"
	)
	assert_eq(
		UpgradeSystem.upgrade_level(shop["state"], "upgrade.custom_desktop"),
		1,
		"And the count comes back down, so the next one is priced as the second again"
	)
	assert_almost_eq(
		float(shop["state"].economy.get("income", 0.0)),
		0.0,
		0.01,
		"Selling the furniture is not the business earning"
	)


func _test_what_cannot_be_sold() -> void:
	var shop: Dictionary = _shop()
	assert_true(
		UpgradeSystem.sell_reason(shop["state"], "used_laptop", ContentDatabase) != "",
		"The starter laptop came with the run and nobody will take it"
	)
	assert_false(_sell(shop, "used_laptop"), "So the sale is refused")

	var only := _shop()
	only["state"].build["hardware"] = ["custom_desktop"]
	only["state"].build["upgrade_levels"] = {"upgrade.custom_desktop": 1}
	assert_true(
		UpgradeSystem.sell_reason(only["state"], "custom_desktop", ContentDatabase) != "",
		"The last machine in the room stays: selling it leaves nothing to burn with"
	)

	assert_true(_buy(shop, "upgrade.custom_desktop"), "Buy a desktop")
	assert_true(_buy(shop, "upgrade.second_gpu"), "And put a card in it")
	assert_true(
		UpgradeSystem.sell_reason(shop["state"], "custom_desktop", ContentDatabase).contains(
			ContentDatabase.get_upgrade("upgrade.second_gpu").name
		),
		"The host cannot go while the card inside it has nowhere else to live"
	)
	assert_true(_sell(shop, "second_gpu"), "Take the card out first")
	assert_true(_sell(shop, "custom_desktop"), "And then the desktop can go")
