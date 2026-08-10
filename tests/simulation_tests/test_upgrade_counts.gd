extends TestCase

## `build.upgrade_counts` is meant to become the one ledger of what a run
## owns, folding together the older split of a hardware array, a one-off list
## and a repeatable level map. These pin it staying in sync with purchases
## and sales, and that a save from before it existed rebuilds it correctly.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_purchase_records_a_count_of_one()
	_test_repeatable_purchases_accumulate()
	_test_selling_decrements_and_zero_erases()
	_test_carriable_rig_reads_the_unified_ledger()
	_test_legacy_save_migrates_counts_from_the_split_fields()


func _shop(location: String = "bedroom") -> Dictionary:
	var state := RunState.new()
	Simulation.apply_run_location(state, location)
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


func _test_purchase_records_a_count_of_one() -> void:
	var shop: Dictionary = _shop()
	assert_true(_buy(shop, "upgrade.custom_desktop"), "A first machine is affordable")
	var counts: Dictionary = UpgradeSystem.upgrade_counts(shop["state"])
	assert_eq(int(counts.get("upgrade.custom_desktop", 0)), 1, "The unified ledger records one unit bought")


func _test_repeatable_purchases_accumulate() -> void:
	var shop: Dictionary = _shop("garage")
	assert_true(_buy(shop, "upgrade.custom_desktop"), "First unit")
	assert_true(_buy(shop, "upgrade.custom_desktop"), "Second unit of the same repeatable machine")
	var counts: Dictionary = UpgradeSystem.upgrade_counts(shop["state"])
	assert_eq(int(counts.get("upgrade.custom_desktop", 0)), 2, "The ledger counts both copies")
	assert_eq(
		int(counts.get("upgrade.custom_desktop", 0)),
		UpgradeSystem.upgrade_level(shop["state"], "upgrade.custom_desktop"),
		"The ledger agrees with the older per-upgrade level counter"
	)


func _test_selling_decrements_and_zero_erases() -> void:
	var shop: Dictionary = _shop("garage")
	_buy(shop, "upgrade.custom_desktop")
	_buy(shop, "upgrade.custom_desktop")
	shop["upgrades"].sell(shop["state"], "custom_desktop", ContentDatabase, shop["economy"])
	assert_eq(
		int(UpgradeSystem.upgrade_counts(shop["state"]).get("upgrade.custom_desktop", 0)), 1,
		"Selling one unit takes the ledger back down to one"
	)
	shop["upgrades"].sell(shop["state"], "custom_desktop", ContentDatabase, shop["economy"])
	assert_false(
		UpgradeSystem.upgrade_counts(shop["state"]).has("upgrade.custom_desktop"),
		"Selling the last unit removes the entry rather than leaving a zero behind"
	)


## Issue #2 from the review: cloud and advertising tiers must not ride along
## with the rig carried into the next location.
func _test_carriable_rig_reads_the_unified_ledger() -> void:
	var shop: Dictionary = _shop()
	_buy(shop, "upgrade.custom_desktop")
	_buy(shop, "upgrade.cloud_account")
	var levels: Dictionary = UpgradeSystem.carriable_rig_levels(shop["state"], ContentDatabase)
	assert_true(levels.has("upgrade.custom_desktop"), "Hardware carries forward")
	assert_false(levels.has("upgrade.cloud_account"), "A cloud tier is Market stock, not rig")


## Pre-inventory-unification saves have the same facts spread across
## `hardware`/`upgrades`/`upgrade_levels`; migration has to fold them into
## `upgrade_counts` without double-counting or losing anything.
func _test_legacy_save_migrates_counts_from_the_split_fields() -> void:
	var legacy: Dictionary = {
		"save_version": 13,
		"build": {
			"hardware": ["used_laptop", "custom_desktop", "custom_desktop"],
			"upgrades": ["upgrade.dedicated_line"],
			"upgrade_levels": {"upgrade.custom_desktop": 2},
		},
	}
	var migrated := RunState.new()
	migrated.from_dict(legacy)
	var counts: Dictionary = UpgradeSystem.upgrade_counts(migrated)
	assert_eq(int(counts.get("upgrade.custom_desktop", 0)), 2, "Repeatable levels migrate straight across")
	assert_eq(int(counts.get("upgrade.dedicated_line", 0)), 1, "A one-off migrates in at a count of one")
