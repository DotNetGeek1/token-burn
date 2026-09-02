extends TestCase

const PerkSystemScript := preload("res://systems/perk_system.gd")


func run() -> void:
	_test_collect_allowed_at_full_active_loadout()
	_test_duplicate_collection_rejected()
	_test_equip_requires_inventory()
	_test_bench_removes_active_effect()
	_test_inventory_compatibility_vs_active()
	_test_save_migration_seeds_inventory()
	_test_synergy_requires_active_perks()


func _perk_system() -> PerkSystem:
	return PerkSystemScript.new()


func _fresh_run() -> RunState:
	var state := RunState.new()
	state.reset()
	return state


func _test_collect_allowed_at_full_active_loadout() -> void:
	var system := _perk_system()
	var state := _fresh_run()
	var cap: int = system.perk_capacity(state, ContentDatabase)
	var filler: Array[String] = [
		"perk.vibe_check",
		"perk.stack_overflow_tab",
		"perk.thermal_paste",
		"perk.prompt_engineer",
		"perk.homelab_hero",
		"perk.consultancy_mode",
	]
	for perk_id in filler:
		if state.build["perks"].size() >= cap:
			break
		if system.can_collect(state, perk_id, ContentDatabase):
			system.collect_perk(state, perk_id, ContentDatabase)
			system.equip_perk(state, perk_id, ContentDatabase)
	assert_eq(state.build["perks"].size(), cap, "Active loadout filled to cap")
	var spare_id: String = ""
	for perk in ContentDatabase.perks:
		if perk.id not in state.build["perk_inventory"]:
			spare_id = perk.id
			break
	assert_false(spare_id == "", "Found an uncollected perk for the bench test")
	assert_true(
		system.can_collect(state, spare_id, ContentDatabase),
		"A full active loadout does not block collecting another perk"
	)
	assert_true(system.collect_perk(state, spare_id, ContentDatabase), "Collect succeeds at full loadout")
	assert_false(
		spare_id in state.build["perks"],
		"Collected perk waits on the bench when active slots are full"
	)
	assert_true(spare_id in state.build["perk_inventory"], "Collected perk is in inventory")


func _test_duplicate_collection_rejected() -> void:
	var system := _perk_system()
	var state := _fresh_run()
	assert_true(system.collect_perk(state, "perk.ship_it", ContentDatabase), "First collect succeeds")
	assert_false(system.can_collect(state, "perk.ship_it", ContentDatabase), "Duplicate collect rejected")


func _test_equip_requires_inventory() -> void:
	var system := _perk_system()
	var state := _fresh_run()
	assert_false(system.can_equip(state, "perk.vibe_check", ContentDatabase), "Cannot equip without collecting")
	system.collect_perk(state, "perk.vibe_check", ContentDatabase)
	assert_true(system.equip_perk(state, "perk.vibe_check", ContentDatabase), "Equip after collect")


func _test_bench_removes_active_effect() -> void:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(8801)
	sim._perk_system.collect_perk(sim.run_state, "perk.works_on_my_machine", ContentDatabase)
	sim._perk_system.equip_perk(sim.run_state, "perk.works_on_my_machine", ContentDatabase)
	sim._invalidate_subscriptions()
	sim._compute_system.recalculate(sim.run_state, sim.effect_resolver, sim._collect_subscriptions(), sim.rng)
	var active_rate: float = float(sim.run_state.compute.get("local_rate", 0.0))
	sim._perk_system.bench_perk(sim.run_state, "perk.works_on_my_machine", ContentDatabase)
	sim._invalidate_subscriptions()
	sim._compute_system.recalculate(sim.run_state, sim.effect_resolver, sim._collect_subscriptions(), sim.rng)
	var benched_rate: float = float(sim.run_state.compute.get("local_rate", 0.0))
	assert_true(active_rate > benched_rate, "Benching removes the standing local bonus")
	sim._perk_system.equip_perk(sim.run_state, "perk.works_on_my_machine", ContentDatabase)
	sim._invalidate_subscriptions()
	sim._compute_system.recalculate(sim.run_state, sim.effect_resolver, sim._collect_subscriptions(), sim.rng)
	assert_almost_eq(
		float(sim.run_state.compute.get("local_rate", 0.0)),
		active_rate,
		0.01,
		"Re-equipping restores the standing bonus"
	)
	sim.free()


func _test_inventory_compatibility_vs_active() -> void:
	var system := _perk_system()
	var state := _fresh_run()
	system.collect_perk(state, "perk.stack_overflow_tab", ContentDatabase)
	system.collect_perk(state, "perk.move_fast_and_break_everything", ContentDatabase)
	system.collect_perk(state, "perk.enterprise_grade", ContentDatabase)
	assert_true("perk.enterprise_grade" in state.build["perk_inventory"], "Rival keystones may coexist in inventory")
	system.equip_perk(state, "perk.stack_overflow_tab", ContentDatabase)
	system.equip_perk(state, "perk.move_fast_and_break_everything", ContentDatabase)
	assert_false(system.can_equip(state, "perk.enterprise_grade", ContentDatabase), "Cannot equip rival keystone while Move Fast is active")
	system.bench_perk(state, "perk.move_fast_and_break_everything", ContentDatabase)
	assert_true(system.can_equip(state, "perk.enterprise_grade", ContentDatabase), "Can equip rival after benching the other")


func _test_save_migration_seeds_inventory() -> void:
	var legacy := RunState.new()
	legacy.build["perks"] = ["perk.ship_it", "perk.vibe_check"]
	var data: Dictionary = legacy.to_dict()
	data["save_version"] = 15
	var loaded := RunState.new()
	loaded.from_dict(data)
	assert_true("perk_inventory" in loaded.build, "Migration adds perk_inventory")
	assert_eq(loaded.build["perk_inventory"].size(), 2, "Migration seeds inventory from active perks")


func _test_synergy_requires_active_perks() -> void:
	var system := _perk_system()
	var state := _fresh_run()
	system.collect_perk(state, "perk.rubber_duck", ContentDatabase)
	system.collect_perk(state, "perk.pipeline_momentum", ContentDatabase)
	assert_eq(system.detect_synergies(state, ContentDatabase).size(), 0, "Synergy inactive while perks are benched")
	system.equip_perk(state, "perk.rubber_duck", ContentDatabase)
	system.equip_perk(state, "perk.pipeline_momentum", ContentDatabase)
	assert_true(system.detect_synergies(state, ContentDatabase).size() > 0, "Synergy active when both perks are equipped")
