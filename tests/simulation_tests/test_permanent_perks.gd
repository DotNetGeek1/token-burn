extends TestCase

## Perks are permanent: one array, `build["perks"]`, that a perk enters when
## the investor's goal is met and never leaves. No bench, no capacity, no swap.

const PerkSystemScript := preload("res://systems/perk_system.gd")


func run() -> void:
	_test_acquire_adds_to_the_build_for_good()
	_test_duplicate_acquisition_rejected()
	_test_exclusions_are_the_only_ceiling()
	_test_undraftable_is_the_complement_of_can_acquire()
	_test_bench_api_is_gone()
	_test_grant_perk_wires_the_effect_in()
	_test_v25_migration_folds_the_bench_into_the_build()
	_test_v25_migration_keeps_the_active_side_of_a_conflict()
	_test_synergy_needs_both_perks_owned()
	_test_management_perks_no_longer_grant_slots()


func _perk_system() -> PerkSystem:
	return PerkSystemScript.new()


func _fresh_run() -> RunState:
	var state := RunState.new()
	state.reset()
	return state


func _sim() -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	return sim


func _test_acquire_adds_to_the_build_for_good() -> void:
	var system := _perk_system()
	var state := _fresh_run()
	assert_true(system.can_acquire(state, "perk.vibe_check", ContentDatabase), "A fresh build can take a common")
	assert_eq(system.acquire_block_reason(state, "perk.vibe_check", ContentDatabase), "", "With nothing blocking it")
	assert_true(system.acquire(state, "perk.vibe_check", ContentDatabase), "Acquire succeeds")
	assert_eq(Array(state.build["perks"]), ["perk.vibe_check"], "The perk is in the build")
	assert_eq(system.owned_ids(state), ["perk.vibe_check"], "And owned_ids reports it")
	assert_false(state.build.has("perk_inventory"), "There is no bench to land on")


func _test_duplicate_acquisition_rejected() -> void:
	var system := _perk_system()
	var state := _fresh_run()
	assert_true(system.acquire(state, "perk.prompt_engineer", ContentDatabase), "First acquire succeeds")
	assert_false(system.can_acquire(state, "perk.prompt_engineer", ContentDatabase), "Duplicate refused")
	assert_eq(
		system.acquire_block_reason(state, "perk.prompt_engineer", ContentDatabase),
		"Already owned",
		"For the obvious reason"
	)
	assert_false(system.acquire(state, "perk.prompt_engineer", ContentDatabase), "And acquire returns false")
	assert_eq(Array(state.build["perks"]).size(), 1, "Without duplicating the entry")
	assert_eq(system.acquire_block_reason(state, "perk.not_real", ContentDatabase), "Unknown perk", "Unknown ids are named as such")


## No cap: the only thing that keeps a perk out is another perk it cannot sit
## beside — and that refusal is for the rest of the run.
func _test_exclusions_are_the_only_ceiling() -> void:
	var system := _perk_system()
	var state := _fresh_run()
	var taken: int = 0
	for perk in ContentDatabase.perks:
		if system.acquire(state, perk.id, ContentDatabase):
			taken += 1
	assert_true(taken > 6, "Well past the old six-perk cap (%d owned)" % taken)
	assert_eq(Array(state.build["perks"]).size(), taken, "Everything acquired is in the build")
	# A single pass in catalogue order can leave a requirement unmet at the
	# moment it was checked; a second pass picks those up, and afterwards
	# every remaining refusal is a real exclusion, stated as such.
	for perk in ContentDatabase.perks:
		system.acquire(state, perk.id, ContentDatabase)
	for perk in ContentDatabase.perks:
		if perk.id in Array(state.build["perks"]):
			continue
		var reason: String = system.acquire_block_reason(state, perk.id, ContentDatabase)
		assert_true(reason != "", "%s was left out for a stated reason" % perk.id)
		assert_true(reason != "Already owned", "%s is not owned" % perk.id)
		assert_false(
			reason.begins_with("Requires"),
			"%s: once the build has settled, only exclusions keep a perk out (%s)" % [perk.id, reason]
		)

	var rivals := _fresh_run()
	assert_true(system.acquire(rivals, "perk.stack_overflow_tab", ContentDatabase), "A bugs common opens the keystones")
	assert_true(system.acquire(rivals, "perk.move_fast_and_break_everything", ContentDatabase), "Move Fast follows")
	assert_false(system.can_acquire(rivals, "perk.enterprise_grade", ContentDatabase), "Enterprise Grade is shut out for good")
	assert_true(
		system.acquire_block_reason(rivals, "perk.enterprise_grade", ContentDatabase).begins_with("Excluded")
		or system.acquire_block_reason(rivals, "perk.enterprise_grade", ContentDatabase).begins_with("Conflicts")
		or system.acquire_block_reason(rivals, "perk.enterprise_grade", ContentDatabase).begins_with("Excludes"),
		"And the refusal names the conflict"
	)


func _test_undraftable_is_the_complement_of_can_acquire() -> void:
	var system := _perk_system()
	var state := _fresh_run()
	system.acquire(state, "perk.stack_overflow_tab", ContentDatabase)
	system.acquire(state, "perk.move_fast_and_break_everything", ContentDatabase)
	var blocked: Array = system.undraftable_ids(state, ContentDatabase)
	for perk in ContentDatabase.perks:
		assert_eq(
			perk.id in blocked,
			not system.can_acquire(state, perk.id, ContentDatabase),
			"%s is undraftable exactly when it cannot be acquired" % perk.id
		)
	assert_true("perk.stack_overflow_tab" in blocked, "Owned perks are not dealt again")
	assert_true("perk.enterprise_grade" in blocked, "Nor are perks the build has shut out")


func _test_bench_api_is_gone() -> void:
	var system := _perk_system()
	for method in [
		"equip_perk", "bench_perk", "swap_perk", "collect_perk", "can_equip", "can_bench",
		"can_swap", "can_collect", "perk_capacity", "equip_block_reason", "bench_block_reason",
		"swap_block_reason", "unequippable_ids", "collected_ids",
	]:
		assert_false(system.has_method(method), "PerkSystem.%s is gone" % method)
	var sim: Node = _sim()
	for method in [
		"equip_perk", "bench_perk", "swap_perk", "collect_perk", "can_equip_perk",
		"can_bench_perk", "can_swap_perk", "perk_capacity", "perk_equip_block_reason",
		"perk_bench_block_reason", "perk_swap_block_reason",
	]:
		assert_false(sim.has_method(method), "Simulation.%s is gone" % method)
	for method in ["grant_perk", "can_acquire_perk", "perk_acquire_block_reason", "owned_perk_ids"]:
		assert_true(sim.has_method(method), "Simulation.%s is the replacement" % method)
	sim.free()


func _test_grant_perk_wires_the_effect_in() -> void:
	var sim: Node = _sim()
	sim.start_run(8801)
	var before: float = float(sim.run_state.compute.get("local_rate", 0.0))
	assert_true(sim.grant_perk("perk.works_on_my_machine"), "The grant goes through")
	assert_true("perk.works_on_my_machine" in sim.owned_perk_ids(), "And is owned")
	assert_true(
		float(sim.run_state.compute.get("local_rate", 0.0)) > before,
		"The standing local bonus is live straight away"
	)
	assert_false(sim.grant_perk("perk.works_on_my_machine"), "Granting it again is refused")
	assert_eq(sim.owned_perk_ids().count("perk.works_on_my_machine"), 1, "And nothing doubles up")
	sim.free()


## A pre-v25 save carried an active loadout and a bench. Both fold into the
## one permanent set, the bench key goes, and removed perks are stripped.
func _test_v25_migration_folds_the_bench_into_the_build() -> void:
	var legacy := RunState.new()
	legacy.reset()
	var data: Dictionary = legacy.to_dict()
	data["save_version"] = 24
	# Ship It requires a `risk` tag the save never carried: a perk already in
	# the run met its requirement when it was taken, so the migration keeps it.
	data["build"]["perks"] = ["perk.ship_it", "perk.vibe_check"]
	data["build"]["perk_inventory"] = [
		"perk.ship_it", "perk.vibe_check", "perk.thermal_paste", "perk.cloud_baron",
	]
	var loaded := RunState.new()
	loaded.from_dict(data)
	var perks: Array = Array(loaded.build.get("perks", []))
	assert_false(loaded.build.has("perk_inventory"), "The bench key is dropped")
	assert_eq(
		perks, ["perk.ship_it", "perk.vibe_check", "perk.thermal_paste"],
		"Active perks first, then the bench, minus the removed Cloud Baron"
	)
	for perk_id in perks:
		assert_eq(perks.count(perk_id), 1, "%s appears once" % perk_id)


## Two rival keystones could coexist on a bench; they cannot coexist in a
## build. The active side of the save wins.
func _test_v25_migration_keeps_the_active_side_of_a_conflict() -> void:
	var legacy := RunState.new()
	legacy.reset()
	var data: Dictionary = legacy.to_dict()
	data["save_version"] = 24
	data["build"]["perks"] = ["perk.stack_overflow_tab", "perk.move_fast_and_break_everything"]
	data["build"]["perk_inventory"] = [
		"perk.stack_overflow_tab", "perk.move_fast_and_break_everything", "perk.enterprise_grade",
	]
	var loaded := RunState.new()
	loaded.from_dict(data)
	var perks: Array = Array(loaded.build.get("perks", []))
	assert_true("perk.move_fast_and_break_everything" in perks, "The active keystone stays")
	assert_false("perk.enterprise_grade" in perks, "The benched rival is dropped rather than made illegal")
	var system := _perk_system()
	for perk_id in perks:
		var others: Array = perks.duplicate()
		others.erase(perk_id)
		var probe := RunState.new()
		probe.reset()
		probe.build["perks"] = others
		assert_true(
			system._compatibility_reason(
				probe, ContentDatabase, ContentDatabase.get_perk(str(perk_id)), false
			) == "",
			"%s is compatible with the rest of the migrated build" % perk_id
		)


func _test_synergy_needs_both_perks_owned() -> void:
	var system := _perk_system()
	var state := _fresh_run()
	system.acquire(state, "perk.rubber_duck", ContentDatabase)
	assert_eq(system.detect_synergies(state, ContentDatabase).size(), 0, "One half of a pair is no combo")
	system.acquire(state, "perk.pipeline_momentum", ContentDatabase)
	assert_true(system.detect_synergies(state, ContentDatabase).size() > 0, "Both owned lights the combo")


## Org Chart and Executive Committee used to widen the rack. There is no rack
## to widen, so they trade reward for running costs instead.
func _test_management_perks_no_longer_grant_slots() -> void:
	for perk in ContentDatabase.perks:
		assert_false(perk.grants.has("perk_slots"), "%s grants no perk slots" % perk.id)
		var text: String = JSON.stringify(perk.subscriptions)
		assert_false(text.contains("perk_slots"), "%s has no perk_slots effect" % perk.id)
	for perk_id in ["perk.org_chart", "perk.executive_committee"]:
		var perk: PerkDefinition = ContentDatabase.get_perk(perk_id)
		assert_true(perk != null, "%s exists" % perk_id)
		var targets: Array = []
		for sub in perk.subscriptions:
			for effect in Array(sub.get("effects", [])):
				targets.append(str(effect.get("target", "")))
		assert_true("job.reward" in targets, "%s pays more per contract" % perk_id)
		assert_true("economy.recurring_costs" in targets, "%s costs more to run" % perk_id)
	assert_false(
		Dictionary(ContentDatabase.balance.get("economy", {})).get("build", {}).has("perk_cap"),
		"economy.build.perk_cap is gone"
	)
