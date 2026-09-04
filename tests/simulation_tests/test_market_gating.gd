extends TestCase

## The Market's hard gates: premises are not for sale at all (they are chapters
## of the campaign, not rows in upgrades.json), a rack needs the cabinet system
## tier it names, later-chapter kit stays in its chapter, and a machine needs
## somewhere to stand. Each of these used to be a warning the sim ignored, so
## these tests are about refusal, not about presentation.

const SCRATCH_PROFILE := "user://profile_gating_test.json"


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_premises_are_not_content()
	_test_hardware_needs_the_system_tier_for_it()
	_test_chapter_kit_stays_in_its_chapter()
	_test_a_run_cannot_move_out_of_its_location()
	_test_hardware_needs_floor_space()


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


## Where the run happens is a chapter of the campaign, won rather than bought.
## There is no premises row left to sell, no shelf for one, and the old ids
## are refused like any other unknown upgrade.
func _test_premises_are_not_content() -> void:
	var shop: Dictionary = _shop()
	assert_eq(shop["state"].build.get("dwelling", ""), "bedroom", "A run starts in the bedroom")
	for upgrade in ContentDatabase.upgrades:
		assert_true(upgrade.category != "dwelling", "%s is not a premises row" % upgrade.id)
		assert_true(
			upgrade.category in ContentDatabase.KNOWN_UPGRADE_CATEGORIES,
			"%s has a category the Market knows" % upgrade.id
		)
	for tab in UpgradePresentation.TABS:
		assert_false(
			"dwelling" in Array(tab["groups"]),
			"No Market counter sells premises (%s)" % str(tab["key"])
		)
	for premises in ["upgrade.garage", "upgrade.office_unit", "upgrade.moon_facility"]:
		assert_true(ContentDatabase.get_upgrade(premises) == null, "%s no longer exists" % premises)
		assert_false(_buy(shop, premises), "And buying it is refused like any unknown id")
	assert_eq(
		shop["state"].build.get("dwelling", ""),
		"bedroom",
		"So the run is still in the bedroom it started in"
	)


## A GPU rack asks for a tier-2 Power Bus, which is a thing the SYSTEMS shelf
## sells; the gate is about floor space, not about which room the run is in.
func _test_hardware_needs_the_system_tier_for_it() -> void:
	var shop: Dictionary = _shop()
	var rack: UpgradeDefinition = ContentDatabase.get_upgrade("upgrade.gpu_rack")
	assert_eq(int(rack.requires_system.get("power", 0)), 2, "The rack is gated on the Power Bus tier")
	assert_true(_buy(shop, "upgrade.custom_desktop"), "A desktop fits in a bedroom")
	assert_false(_buy(shop, "upgrade.gpu_rack"), "A GPU rack does not, however much cash is in hand")
	assert_false(
		"gpu_rack" in shop["state"].build.get("hardware", []),
		"A refused machine is not installed"
	)
	# Buying the tier in the bedroom opens the rack without leaving the chapter.
	CabinetSystems.set_tier(shop["state"], "power", 2)
	assert_true(_buy(shop, "upgrade.gpu_rack"), "With a tier-2 Power Bus the rack has a home")
	assert_eq(str(shop["state"].build.get("dwelling", "")), "bedroom", "And the run never moved")

	# A garage run opens with garage-tier systems, so the rack is on sale there.
	var garage: Dictionary = _shop()
	Simulation.apply_run_location(garage["state"], "garage")
	garage["state"].economy["cash"] = 100000000.0
	assert_true(_buy(garage, "upgrade.gpu_rack"), "In the garage the rack has a home from the start")


## Kit that belongs to a later chapter is not a capacity question, so no tier
## bought in an earlier chapter opens it.
func _test_chapter_kit_stays_in_its_chapter() -> void:
	var shop: Dictionary = _shop()
	var cluster: UpgradeDefinition = ContentDatabase.get_upgrade("upgrade.compute_cluster")
	assert_eq(cluster.requires_chapter, "office_unit", "The cluster belongs to the office chapter")
	for system_id in CabinetSystems.system_ids():
		CabinetSystems.set_tier(shop["state"], str(system_id), CabinetSystems.max_tier())
	assert_false(_buy(shop, "upgrade.compute_cluster"), "Maxed systems in the bedroom do not buy office kit")

	var garage: Dictionary = _shop()
	Simulation.apply_run_location(garage["state"], "garage")
	garage["state"].economy["cash"] = 100000000.0
	assert_false(_buy(garage, "upgrade.compute_cluster"), "A cluster still wants the office")

	var office: Dictionary = _shop()
	Simulation.apply_run_location(office["state"], "office_unit")
	office["state"].economy["cash"] = 100000000.0
	assert_true(_buy(office, "upgrade.compute_cluster"), "And in the office it is on sale")


## The invariant the whole refactor rests on: a run's location is fixed. Nothing
## on any shelf, bought in any order, changes it.
func _test_a_run_cannot_move_out_of_its_location() -> void:
	var sim: Node = _sim()
	sim.start_run(4204)
	sim.run_state.economy["cash"] = 1.0e12
	for upgrade in ContentDatabase.upgrades:
		sim.buy_upgrade(upgrade.id)
	assert_eq(
		str(sim.run_state.build.get("dwelling", "")),
		"bedroom",
		"Buying everything the Market will sell leaves the run where it started"
	)
	sim.free()


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
