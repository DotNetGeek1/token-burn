extends TestCase

## The Market's three hard gates: cloud is a capability you buy rather than one
## you start with, property is a ladder climbed a rung at a time, and a machine
## needs somewhere to stand. Each of these used to be a warning the sim ignored,
## so these tests are about refusal, not about presentation.

const SCRATCH_PROFILE := "user://profile_gating_test.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_cloud_needs_an_account()
	_test_cloud_stock_needs_the_account()
	_test_a_burst_costs_more_than_loose_change()
	_test_property_is_climbed_one_rung_at_a_time()
	_test_hardware_needs_the_premises_for_it()
	_test_hardware_needs_floor_space()
	_test_the_meta_unlock_opens_the_account()


func _sim() -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	return sim


func _shop() -> Dictionary:
	var state := RunState.new()
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


func _test_cloud_needs_an_account() -> void:
	var sim: Node = _sim()
	sim.start_run(4201)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	assert_true(sim.can_start_work(), "There is a contract waiting, so a session could start")

	assert_false(sim.cloud_enabled(), "A run does not begin with a cloud provider")
	sim.set_queued_cloud(true)
	assert_false(sim.queued_cloud, "So a burst cannot be armed before work starts")
	assert_false(sim._apply_cloud_burst(), "And firing one outright does nothing")

	sim.run_state.build["upgrades"].append(Simulation.CLOUD_ACCOUNT_UPGRADE)
	assert_true(sim.cloud_enabled(), "Opening an account enables the cloud")
	sim.set_queued_cloud(true)
	assert_true(sim.queued_cloud, "And the burst can be armed")

	sim.run_state.economy["cash"] = 100000.0
	assert_true(sim._apply_cloud_burst(), "A burst fires once there is somebody to bill")
	assert_true(sim.cloud_engaged(), "And the rented capacity is live for the round")
	sim.free()


func _test_cloud_stock_needs_the_account() -> void:
	var shop: Dictionary = _shop()
	assert_false(
		shop["upgrades"].can_purchase(shop["state"], "upgrade.cloud_payg", ContentDatabase),
		"Capacity cannot be bought without an account to bill it to"
	)
	assert_false(_buy(shop, "upgrade.cloud_payg"), "And the purchase is refused, not just hidden")
	assert_eq(
		shop["state"].compute.get("cloud_capacity", 0.0),
		0.0,
		"A refused purchase provisions nothing"
	)

	assert_true(_buy(shop, Simulation.CLOUD_ACCOUNT_UPGRADE), "The account itself is buyable")
	assert_true(_buy(shop, "upgrade.cloud_payg"), "Which opens the rest of the shelf")
	assert_true(
		float(shop["state"].compute.get("cloud_capacity", 0.0)) > 0.0,
		"And capacity finally arrives"
	)


func _test_a_burst_costs_more_than_loose_change() -> void:
	var sim: Node = _sim()
	sim.start_run(4202)
	sim.run_state.build["upgrades"].append(Simulation.CLOUD_ACCOUNT_UPGRADE)
	var economy: Dictionary = ContentDatabase.balance.get("economy", {})
	var rate: float = float(economy.get("cloud_burst_cost_per_token", 0.0))
	var fee: float = float(economy.get("cloud_burst_activation_fee", 0.0))
	var capacity: float = float(sim.run_state.compute.get("local_capacity", 0.0))
	assert_true(fee > 0.0, "Turning the tap on is charged for on its own")
	assert_almost_eq(
		sim.cloud_burst_cost(),
		capacity * Simulation.CLOUD_BURST_BASE_MULTIPLIER * rate + fee,
		0.01,
		"A burst is priced per rented token plus the activation fee"
	)
	assert_almost_eq(
		sim.cloud_burst_multiplier(),
		Simulation.CLOUD_BURST_BASE_MULTIPLIER,
		0.001,
		"With no upgrades the burst starts at its floor"
	)
	sim.run_state.build["upgrade_levels"][Simulation.CLOUD_BURST_UPGRADE] = 2
	assert_almost_eq(
		sim.cloud_burst_multiplier(),
		Simulation.CLOUD_BURST_BASE_MULTIPLIER + 2.0 * Simulation.CLOUD_BURST_PER_LEVEL,
		0.001,
		"And levels are the only way to raise it"
	)
	sim.free()


func _test_property_is_climbed_one_rung_at_a_time() -> void:
	var shop: Dictionary = _shop()
	assert_eq(shop["state"].build.get("dwelling", ""), "bedroom", "A run starts in the bedroom")
	assert_false(_buy(shop, "upgrade.warehouse"), "A warehouse cannot be leased from a bedroom")
	assert_false(_buy(shop, "upgrade.moon_facility"), "Nor can the last rung be bought first")
	assert_eq(shop["state"].build.get("dwelling", ""), "bedroom", "A refused move changes nothing")

	assert_true(_buy(shop, "upgrade.garage"), "The next rung is available")
	assert_eq(shop["state"].build.get("dwelling", ""), "garage", "And it moves the run")
	assert_false(_buy(shop, "upgrade.warehouse"), "The warehouse is still two steps away")
	assert_true(_buy(shop, "upgrade.office_unit"), "The office comes after the garage")
	assert_true(_buy(shop, "upgrade.warehouse"), "And the warehouse after the office")

	var office_cost: float = ContentDatabase.get_upgrade("upgrade.office_unit").cost
	var warehouse_cost: float = ContentDatabase.get_upgrade("upgrade.warehouse").cost
	assert_true(office_cost < warehouse_cost, "Each rung costs more than the one below it")


func _test_hardware_needs_the_premises_for_it() -> void:
	var shop: Dictionary = _shop()
	assert_true(_buy(shop, "upgrade.custom_desktop"), "A desktop fits in a bedroom")
	assert_false(_buy(shop, "upgrade.gpu_rack"), "A GPU rack does not, however much cash is in hand")
	assert_false(
		"gpu_rack" in shop["state"].build.get("hardware", []),
		"A refused machine is not installed"
	)
	assert_false(_buy(shop, "upgrade.compute_cluster"), "Nor does anything above it")

	assert_true(_buy(shop, "upgrade.garage"), "Moving to the garage buys somewhere to put one")
	assert_true(_buy(shop, "upgrade.gpu_rack"), "And the rack finally has a home")
	assert_false(_buy(shop, "upgrade.compute_cluster"), "A cluster still wants the office")


func _test_hardware_needs_floor_space() -> void:
	var shop: Dictionary = _shop()
	var slots: int = int(
		ContentDatabase.balance.get("dwelling_costs", {}).get("bedroom", {}).get("hardware_slots", 0)
	)
	assert_true(slots >= 2, "The bedroom fits the laptop and one machine beside it")

	# Cooling is not a machine, so it must never be what fills the room.
	assert_true(_buy(shop, "upgrade.portable_ac"), "An air conditioner takes no floor space")
	assert_true(_buy(shop, "upgrade.custom_desktop"), "So the desktop still fits after it")

	var desktop: UpgradeDefinition = ContentDatabase.get_upgrade("upgrade.custom_desktop")
	assert_true(
		UpgradeSystem.hardware_space_full(shop["state"], desktop, ContentDatabase),
		"With both slots running the bedroom is full"
	)
	shop["state"].build["dwelling"] = "garage"
	assert_false(
		UpgradeSystem.hardware_space_full(shop["state"], desktop, ContentDatabase),
		"And a bigger space has room again"
	)


func _test_the_meta_unlock_opens_the_account() -> void:
	var restore_path: String = MetaProgress.profile_path
	var restore_enabled: bool = MetaProgress.enabled
	MetaProgress.enabled = true
	MetaProgress.use_scratch_profile(SCRATCH_PROFILE)

	var sim: Node = _sim()
	sim.start_run(4203)
	assert_false(sim.cloud_enabled(), "A fresh profile still has to buy the account")

	MetaProgress.bank_victory()
	assert_true(MetaProgress.spend_pick("unlock.cloud_account"), "The account can be kept")
	sim.start_run(4203)
	assert_true(sim.cloud_enabled(), "So the next run begins with the cloud already open")
	assert_true(
		Simulation.CLOUD_ACCOUNT_UPGRADE in sim.run_state.build.get("upgrades", []),
		"And the Market treats it as bought, so it is not sold twice"
	)
	sim.free()

	if FileAccess.file_exists(SCRATCH_PROFILE):
		DirAccess.remove_absolute(SCRATCH_PROFILE)
	MetaProgress.profile_path = restore_path
	MetaProgress.enabled = restore_enabled
	MetaProgress._loaded = false
