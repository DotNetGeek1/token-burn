extends TestCase

## The workstation is a projection of the current build, never saved state of its
## own. These tests pin every trigger and the transitions that can expose stale UI.


func run() -> void:
	_test_each_stage_trigger()
	_test_highest_stage_wins()
	_test_multiple_machines_promote()
	_test_sale_downgrades()
	_test_carried_hardware_derives_the_same_stage()
	_test_save_load_restores_from_build()


func _stage(hardware: Array = [], upgrades: Array = [], machines: int = 1) -> int:
	return AssetCatalog.rig_stage_for_build({
		"hardware": hardware,
		"upgrades": upgrades,
	}, machines)


func _test_each_stage_trigger() -> void:
	assert_eq(_stage(), 1, "Starter hardware uses the worn laptop")
	assert_eq(_stage(["custom_desktop"]), 2, "A custom desktop unlocks the ultrawide")
	assert_eq(_stage([], ["upgrade.second_monitor"]), 2, "The second-monitor upgrade unlocks the ultrawide")
	assert_eq(_stage([], ["upgrade.second_desk"]), 3, "A second desk unlocks dual displays")
	assert_eq(_stage([], ["upgrade.standing_desk"]), 3, "A standing desk unlocks dual displays")
	assert_eq(_stage(["gpu_rack"]), 4, "A GPU rack unlocks the dual-monitor GPU desk")
	assert_eq(_stage(["compute_cluster"]), 4, "A compute cluster unlocks the dual-monitor GPU desk")
	for hardware_key in ["garage_datacentre", "compute_warehouse", "industrial_campus"]:
		assert_eq(_stage([hardware_key]), 5, "%s unlocks the three-monitor command desk" % hardware_key)


func _test_highest_stage_wins() -> void:
	assert_eq(
		_stage(
			["custom_desktop", "gpu_rack", "industrial_campus"],
			["upgrade.second_monitor", "upgrade.second_desk"],
			4
		),
		5,
		"The ladder evaluates its highest matching stage first"
	)


func _test_multiple_machines_promote() -> void:
	assert_eq(_stage(["used_laptop"], [], 1), 1, "One compute machine stays at stage one")
	assert_eq(_stage(["used_laptop"], [], 2), 3, "Two compute machines promote to stage three")


func _test_sale_downgrades() -> void:
	var build := {"hardware": ["used_laptop", "gpu_rack"], "upgrades": []}
	assert_eq(AssetCatalog.rig_stage_for_build(build, 2), 4, "The owned rack is visible")
	build["hardware"].erase("gpu_rack")
	assert_eq(
		AssetCatalog.rig_stage_for_build(build, 1), 1,
		"Selling the rack and losing its machine slot immediately restores the laptop"
	)


func _test_carried_hardware_derives_the_same_stage() -> void:
	var carried_build := {"hardware": ["used_laptop", "compute_cluster"], "upgrades": []}
	assert_eq(
		AssetCatalog.rig_stage_for_build(carried_build, 2), 4,
		"Hardware carried into another room still selects its earned workstation"
	)


func _test_save_load_restores_from_build() -> void:
	var state := RunState.new()
	state.build["hardware"] = ["used_laptop", "custom_desktop"]
	state.build["upgrades"] = ["upgrade.second_monitor"]
	var loaded := RunState.new()
	loaded.from_dict(state.to_dict())
	assert_eq(
		AssetCatalog.rig_stage_for_build(loaded.build, 2), 3,
		"Loading needs no workstation field: the restored build derives the stage"
	)
