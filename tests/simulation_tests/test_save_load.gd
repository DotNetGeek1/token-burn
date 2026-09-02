extends TestCase


func run() -> void:
	var state := RunState.new()
	state.economy["cash"] = 999.0
	state.business["reputation"] = 42.0
	state.compute["rate_modifiers"] = [{"multiplier": 1.5, "prompts_remaining": 3, "source": "test"}]
	var data: Dictionary = state.to_dict()
	var loaded := RunState.new()
	loaded.from_dict(data)
	assert_eq(loaded.economy.get("cash", 0.0), 999.0, "Save round-trip preserves cash")
	assert_eq(loaded.business.get("reputation", 0.0), 42.0, "Save round-trip preserves reputation")
	assert_true(loaded.compute.has("rate_modifiers"), "Save includes rate modifiers")

	var partial: Dictionary = {"economy": {"cash": 123.0}, "save_version": 1}
	var migrated := RunState.new()
	migrated.from_dict(partial)
	assert_true(migrated.compute.has("token_rate"), "Migration fills missing compute keys")
	assert_false(migrated.business.has("demand_modifier"), "Demand is no longer part of a run")
	assert_eq(migrated.economy.get("cash", 0.0), 123.0, "Migration preserves saved values")

	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(200)
	sim.run_state.business["active_jobs"] = [{
		"id": "job.test",
		"name": "Test Job",
		"tokens_remaining": 50.0,
		"token_requirement": 100.0,
		"deadline_prompts": 5,
		"prompts_remaining": 3,
		"reward": 500.0,
		"quality": 10.0,
		"quality_threshold": 50.0,
	}]
	sim.phase = sim.Phase.IN_ROUND
	var saved: Dictionary = sim.run_state.to_dict()
	var sim2: Node = sim_script.new()
	sim2.autosave_enabled = false
	sim2.run_state.from_dict(saved)
	sim2.phase = sim.Phase.IN_ROUND
	assert_true(sim2.run_state.business.get("active_jobs", []).size() > 0, "In-flight jobs survive save/load")
	sim.free()
	sim2.free()

	_test_round_end_pending_survives_load(sim_script)
	_test_a_pre_round_save_keeps_its_progress()
	_test_a_pre_workflow_save_keeps_its_pipelines()
	_test_v19_repairs_recurring_costs_and_sale_provenance()
	_test_v19_gives_legacy_jobs_unique_instance_ids()
	_test_v20_repairs_negative_contract_progress()
	_test_v21_refunds_removed_purchases_and_clears_state()
	_test_v21_skips_a_granted_cloud_account()
	_test_v21_refunds_legacy_repeatable_levels()
	_test_v21_skips_a_legacy_granted_cloud_account()
	_test_v21_is_idempotent()
	_test_v22_normalizes_workflow_mastery_and_job_evidence()
	_test_corrupt_primary_save_recovers_from_backup()


func _test_round_end_pending_survives_load(sim_script: GDScript) -> void:
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(201)
	sim.phase = sim.Phase.ANGEL_ROUND
	sim.debug_set_round_end_pending(true)
	sim.debug_present_angel_offers()
	# Written with the phase's old name on purpose: saves made before the angel
	# round was split out of the market still have to load.
	SaveManager.save_run(sim.run_state, "UPGRADE_CHOICE", sim.run_seed, sim.pending_choices, sim.debug_round_end_pending())

	var sim2: Node = sim_script.new()
	sim2.autosave_enabled = false
	assert_true(sim2.load_saved_run(), "Save with a pending round end loads")
	assert_eq(sim2.phase, sim2.Phase.ANGEL_ROUND, "A pre-split save resumes in the angel phase")
	assert_true(sim2.debug_round_end_pending(), "Round-end pending flag restored on load")
	var round_before: int = int(sim2.run_state.calendar["round"])
	sim2.decline_offers()
	assert_eq(int(sim2.run_state.calendar["round"]), round_before + 1, "The round rolls after loading mid angel phase")
	SaveManager.delete_save()
	sim.free()
	sim2.free()


## A run saved under the old month/round vocabulary has to come back as a
## round/prompt run with its money, its position and its contracts intact —
## dropping a run in progress on an update is not an acceptable migration.
func _test_a_pre_round_save_keeps_its_progress() -> void:
	var legacy: Dictionary = {
		"save_version": 6,
		"calendar": {"month": 5, "day": 1, "round": 7, "rounds_per_month": 12},
		"economy": {
			"cash": 2500.0,
			"monthly_rent": 900.0,
			"power_cost_per_round": 22.0,
			"costs_this_month": 60.0,
		},
		"compute": {
			"token_rate": 500.0,
			"round_rate": 750.0,
			"cloud_burst_rounds": 1,
			"rate_modifiers": [{"multiplier": 1.5, "rounds_remaining": 2, "source": "legacy"}],
		},
		"statistics": {"peak_round_tokens": 4200.0},
		"business": {
			"active_jobs": [{
				"id": "job.legacy",
				"name": "Legacy",
				"tokens_remaining": 30.0,
				"token_requirement": 100.0,
				"deadline_rounds": 9,
				"rounds_remaining": 4,
			}],
		},
	}
	var migrated := RunState.new()
	migrated.from_dict(legacy)
	assert_eq(int(migrated.calendar.get("round", 0)), 5, "The old month becomes the round")
	assert_eq(int(migrated.calendar.get("prompt", 0)), 7, "And the old round becomes the prompt")
	assert_false(migrated.calendar.has("rounds_per_month"), "The prompt budget is gone")
	assert_eq(float(migrated.economy.get("cash", 0.0)), 2500.0, "Cash survives the migration")
	assert_eq(float(migrated.economy.get("round_rent", 0.0)), 900.0, "Rent carries over at the same amount")
	assert_eq(float(migrated.economy.get("power_cost_per_prompt", 0.0)), 22.0, "Power is now metered per prompt")
	assert_eq(float(migrated.economy.get("costs_this_round", 0.0)), 60.0, "Costs already accrued stay accrued")
	assert_eq(float(migrated.compute.get("prompt_rate", 0.0)), 750.0, "The burst rate becomes the prompt rate")
	assert_false(migrated.compute.has("cloud_burst_prompts"), "A leftover cloud lease is dropped")
	assert_eq(
		int(Array(migrated.compute.get("rate_modifiers", []))[0].get("prompts_remaining", 0)),
		2,
		"Temporary boosts keep their remaining duration"
	)
	assert_eq(float(migrated.statistics.get("peak_prompt_tokens", 0.0)), 4200.0, "The peak-burn record is kept")
	var job: Dictionary = Array(migrated.business.get("active_jobs", []))[0]
	assert_eq(int(job.get("deadline_prompts", 0)), 9, "Contract deadlines convert one-for-one")
	assert_eq(int(job.get("prompts_remaining", 0)), 4, "And so does the time left on them")


## A run saved when there was one global pipeline, plus a saved second lane it
## had earned, has to come back as two named workflows with both layouts and the
## room to keep them.
func _test_a_pre_workflow_save_keeps_its_pipelines() -> void:
	var legacy: Dictionary = {
		"save_version": 7,
		"build": {
			"operations": ["op.prompt", "op.unit_tests", "op.cheap_model"],
			"lane_count": 2,
			"board": {
				"slot_count": 3,
				"active_lane": 1,
				"lane_slots": [
					["op.prompt", "op.cheap_model", ""],
					["op.unit_tests", "", "op.prompt"],
				],
			},
		},
	}
	var migrated := RunState.new()
	migrated.from_dict(legacy)
	var board := BoardSystem.new()
	board.ensure_board(migrated, ContentDatabase)

	assert_eq(board.workflow_count(migrated), 2, "Both saved lanes became workflows")
	assert_eq(board.workflow_capacity(migrated), 2, "And the run keeps the room it had earned")
	assert_eq(
		Array(board.workflow_at(migrated, 0).get("slots", [])),
		["op.prompt", "op.cheap_model", ""],
		"The first layout is untouched"
	)
	assert_eq(
		Array(board.workflow_at(migrated, 1).get("slots", [])),
		["op.unit_tests", "", "op.prompt"],
		"And so is the second"
	)
	assert_eq(board.active_workflow_index(migrated), 1, "The run resumes on the lane it was left on")
	assert_true(str(board.workflow_at(migrated, 0).get("name", "")) != "", "Every workflow arrives named")


func _test_v19_repairs_recurring_costs_and_sale_provenance() -> void:
	var legacy: Dictionary = {
		"save_version": 18,
		"economy": {
			"recurring_costs_base": 1440.0,
			"recurring_costs": 1440.0,
		},
		"build": {
			"dwelling": "office_unit",
			"hardware": ["used_laptop", "gpu_rack", "gpu_rack"],
			"upgrade_levels": {"upgrade.gpu_rack": 2},
			"upgrade_counts": {"upgrade.gpu_rack": 2},
			"purchased_upgrade_counts": {"upgrade.gpu_rack": 2},
		},
	}
	var migrated := RunState.new()
	migrated.from_dict(legacy)
	var rack: UpgradeDefinition = ContentDatabase.get_upgrade("upgrade.gpu_rack")
	assert_almost_eq(
		float(migrated.economy.get("recurring_costs_base", 0.0)),
		rack.recurring_cost_delta * 2.0,
		0.01,
		"v19 rebuilds the true recurring base from owned upgrades"
	)
	assert_true(
		UpgradeSystem.purchased_upgrade_counts(migrated).is_empty(),
		"Pre-v19 hardware is conservatively migrated as non-refundable"
	)
	assert_almost_eq(
		UpgradeSystem.sell_refund(migrated, "gpu_rack", ContentDatabase),
		0.0,
		0.01,
		"The old save cannot cash out hardware whose provenance is unknown"
	)

	var upgrades := UpgradeSystem.new()
	var economy := EconomySystem.new()
	migrated.economy["cash"] = 1_000_000.0
	assert_true(
		upgrades.purchase(migrated, "upgrade.custom_desktop", ContentDatabase, EffectResolver.new(), economy),
		"A purchase made after migration succeeds"
	)
	assert_eq(
		int(UpgradeSystem.purchased_upgrade_counts(migrated).get("upgrade.custom_desktop", 0)),
		1,
		"And only that new copy becomes refundable"
	)


func _test_v20_repairs_negative_contract_progress() -> void:
	var legacy: Dictionary = {
		"save_version": 19,
		"business": {
			"active_jobs": [{
				"id": "job.deep_burn",
				"token_requirement": 61.0e15,
				"tokens_remaining": 62.6e15,
			}],
		},
	}
	var migrated := RunState.new()
	migrated.from_dict(legacy)
	var job: Dictionary = Array(migrated.business.get("active_jobs", []))[0]
	assert_almost_eq(
		float(job.get("tokens_remaining", 0.0)),
		62.6e15,
		1.0,
		"v20 preserves every outstanding token"
	)
	assert_almost_eq(
		float(job.get("token_requirement", 0.0)),
		62.6e15,
		1.0,
		"v20 raises the requirement enough to prevent negative progress"
	)

	var round_tripped := RunState.new()
	round_tripped.from_dict(migrated.to_dict())
	var loaded_job: Dictionary = Array(round_tripped.business.get("active_jobs", []))[0]
	assert_almost_eq(
		float(loaded_job.get("token_requirement", 0.0)),
		float(job.get("token_requirement", 0.0)),
		1.0,
		"A v20 round trip leaves the repaired contract stable"
	)


func _test_v19_gives_legacy_jobs_unique_instance_ids() -> void:
	var active_a: Dictionary = {
		"id": "job.marketplace", "tokens_remaining": 100.0, "prompts_remaining": 5,
	}
	var active_b: Dictionary = {
		"id": "job.marketplace", "tokens_remaining": 100.0, "prompts_remaining": 6,
	}
	var legacy: Dictionary = {
		"save_version": 18,
		"business": {
			"job_offers": [{"id": "job.marketplace"}],
			"job_queue": [{"id": "job.marketplace"}],
			"active_jobs": [active_a, active_b],
			"focused_job_id": "job.marketplace",
		},
		"build": {
			"hardware": ["used_laptop", "custom_desktop"],
			"upgrade_levels": {"upgrade.custom_desktop": 1},
			"upgrade_counts": {"upgrade.custom_desktop": 1},
		},
	}
	var migrated := RunState.new()
	migrated.from_dict(legacy)
	var ids: Dictionary = {}
	for collection in ["job_offers", "job_queue", "active_jobs"]:
		for job in migrated.business.get(collection, []):
			assert_eq(
				str(job.get("definition_id", "")),
				"job.marketplace",
				"Legacy jobs retain their authored definition id"
			)
			var instance_id: String = str(job.get("id", ""))
			assert_false(ids.has(instance_id), "Every migrated live job has a unique instance id")
			ids[instance_id] = true
	var active_jobs: Array = Array(migrated.business.get("active_jobs", []))
	assert_eq(
		str(migrated.business.get("focused_job_id", "")),
		str(active_jobs[0].get("id", "")),
		"Legacy focus deterministically follows the first matching active job"
	)
	assert_true(
		Dictionary(migrated.business.get("active_job", {})).is_empty(),
		"The single-job compatibility field is empty when two jobs are active"
	)
	assert_eq(
		JobSystem.new().burn_lane_jobs(migrated).size(),
		2,
		"Both formerly duplicate active jobs can now occupy parallel lanes"
	)


func _test_v21_refunds_removed_purchases_and_clears_state() -> void:
	var sales_refund: float = 400.0 + 400.0 * 1.35
	var legacy: Dictionary = {
		"save_version": 20,
		"economy": {
			"cash": 1000.0,
			"recurring_costs_base": 45.0,
			"cloud_surcharge_liability": 80.0,
			"cloud_cost_per_prompt": 40.0,
		},
		"compute": {"cloud_capacity": 2000000.0, "cloud_share": 0.4},
		"business": {"demand": 8.0, "advertising": 100.0, "demand_modifier": 2.0},
		"build": {
			"upgrades": ["upgrade.cloud_account", "upgrade.ads_basic"],
			"upgrade_levels": {"upgrade.sales_investment": 2},
			"upgrade_counts": {
				"upgrade.cloud_account": 1,
				"upgrade.ads_basic": 1,
				"upgrade.sales_investment": 2,
				"upgrade.custom_desktop": 1,
			},
			"purchased_upgrade_counts": {
				"upgrade.cloud_account": 1,
				"upgrade.ads_basic": 1,
				"upgrade.sales_investment": 2,
				"upgrade.custom_desktop": 1,
			},
			"perks": ["perk.cloud_baron", "perk.ship_it"],
			"perk_inventory": ["perk.cloud_baron", "perk.ship_it"],
			"modules": ["op.spot_fleet", "op.prompt"],
			"cloud_tier": "upgrade.cloud_account",
			"advertising_tier": "upgrade.ads_basic",
		},
		"statistics": {"max_cloud_share": 0.9},
	}
	var migrated := RunState.new()
	migrated.from_dict(legacy)
	assert_almost_eq(
		float(migrated.economy.get("cash", 0.0)),
		1000.0 + 600.0 + 300.0 + sales_refund,
		0.01,
		"Paid cloud, ads and both sales levels come back as cash"
	)
	assert_false(migrated.economy.has("cloud_surcharge_liability"), "Cloud bills are wiped")
	assert_false(migrated.compute.has("cloud_capacity"), "Cloud capacity is wiped")
	assert_false(migrated.business.has("advertising"), "Advertising is wiped")
	assert_false("upgrade.cloud_account" in Array(migrated.build.get("upgrades", [])), "Removed upgrades leave the ledger")
	assert_false(Dictionary(migrated.build.get("upgrade_counts", {})).has("upgrade.sales_investment"), "Sales levels are gone")
	assert_true("upgrade.custom_desktop" in Dictionary(migrated.build.get("upgrade_counts", {})), "Hardware stays")
	assert_eq(Array(migrated.build.get("perks", [])), ["perk.ship_it"], "Removed perks leave the loadout")
	assert_eq(Array(migrated.build.get("modules", [])), ["op.prompt"], "Removed modules leave the board")
	assert_false(migrated.build.has("cloud_tier"), "Cloud shelf markers are gone")
	assert_false(migrated.statistics.has("max_cloud_share"), "Cloud stats are gone")


func _test_v21_skips_a_granted_cloud_account() -> void:
	var legacy: Dictionary = {
		"save_version": 20,
		"economy": {"cash": 200.0},
		"build": {
			"upgrades": ["upgrade.cloud_account"],
			"upgrade_counts": {"upgrade.cloud_account": 1},
			"purchased_upgrade_counts": {},
		},
	}
	var migrated := RunState.new()
	migrated.from_dict(legacy)
	assert_eq(
		float(migrated.economy.get("cash", 0.0)),
		200.0,
		"A granted cloud account with no purchase provenance is not refunded"
	)


func _test_v21_refunds_legacy_repeatable_levels() -> void:
	var sales_refund: float = 400.0 + 400.0 * 1.35
	var compute_refund: float = 350.0 + 350.0 * 1.4
	var legacy: Dictionary = {
		"save_version": 18,
		"economy": {"cash": 100.0},
		"build": {
			"upgrades": ["upgrade.sales_investment", "upgrade.cloud_compute"],
			"upgrade_levels": {"upgrade.sales_investment": 2, "upgrade.cloud_compute": 2},
			"upgrade_counts": {"upgrade.sales_investment": 2, "upgrade.cloud_compute": 2},
		},
	}
	var migrated := RunState.new()
	migrated.from_dict(legacy)
	assert_almost_eq(
		float(migrated.economy.get("cash", 0.0)),
		100.0 + sales_refund + compute_refund,
		0.01,
		"Pre-v19 saves refund geometric Sales Outreach and Cloud Compute totals"
	)


func _test_v21_skips_a_legacy_granted_cloud_account() -> void:
	var restore_path: String = MetaProgress.profile_path
	var restore_enabled: bool = MetaProgress.enabled
	var scratch := "user://profile_v21_grant_test.json"
	MetaProgress.enabled = true
	MetaProgress.use_scratch_profile(scratch)
	var legacy_profile := {
		"version": 6,
		"unlocks": {"unlock.cloud_account": 1},
		"pending_picks": 0,
	}
	var file := FileAccess.open(scratch, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy_profile))
	file.close()
	MetaProgress._loaded = false
	MetaProgress._ensure_loaded()
	assert_true(MetaProgress.retired_cloud_unlocks(), "Retired cloud ranks are remembered")
	assert_eq(MetaProgress.pending_picks(), 1, "The spent cloud rank comes back as a pick")

	var legacy: Dictionary = {
		"save_version": 18,
		"economy": {"cash": 200.0},
		"build": {
			"upgrades": ["upgrade.cloud_account"],
			"upgrade_counts": {"upgrade.cloud_account": 1},
		},
	}
	var migrated := RunState.new()
	migrated.from_dict(legacy)
	assert_eq(
		float(migrated.economy.get("cash", 0.0)),
		200.0,
		"A pre-v19 granted cloud account is not treated as a purchase"
	)

	if FileAccess.file_exists(scratch):
		DirAccess.remove_absolute(scratch)
	MetaProgress.profile_path = restore_path
	MetaProgress.enabled = restore_enabled
	MetaProgress._loaded = false


func _test_v21_is_idempotent() -> void:
	var legacy: Dictionary = {
		"save_version": 20,
		"economy": {"cash": 50.0},
		"build": {
			"purchased_upgrade_counts": {"upgrade.ads_basic": 1},
			"upgrade_counts": {"upgrade.ads_basic": 1},
			"upgrades": ["upgrade.ads_basic"],
		},
	}
	var first := RunState.new()
	first.from_dict(legacy)
	var second := RunState.new()
	second.from_dict(first.to_dict())
	assert_almost_eq(
		float(second.economy.get("cash", 0.0)),
		float(first.economy.get("cash", 0.0)),
		0.01,
		"Reloading a migrated save does not refund again"
	)


func _test_v22_normalizes_workflow_mastery_and_job_evidence() -> void:
	var legacy: Dictionary = {
		"save_version": 21,
		"build": {
			"workflows": [{"id": "workflow.1", "name": "House Style", "slots": ["op.prompt"]}],
		},
		"business": {
			"active_jobs": [{"id": "job.old", "token_requirement": 100.0, "tokens_remaining": 40.0}],
		},
	}
	var migrated := RunState.new()
	migrated.from_dict(legacy)
	var workflow: Dictionary = Array(migrated.build.get("workflows", []))[0]
	assert_almost_eq(float(workflow.get("output_mult", 0.0)), 1.0, 0.001, "v22 seeds OUTPUT ×1")
	assert_almost_eq(float(workflow.get("quality_mult", 0.0)), 1.0, 0.001, "v22 seeds QUALITY ×1")
	assert_almost_eq(float(workflow.get("thermal_mult", 0.0)), 1.0, 0.001, "v22 seeds THERMAL ×1")
	assert_true(workflow.get("gain_ledger") is Array, "v22 adds a gain ledger")
	var job: Dictionary = Array(migrated.business.get("active_jobs", []))[0]
	assert_eq(int(job.get("burn_count", -1)), 0, "v22 seeds burn_count")
	assert_eq(int(job.get("bugs_created", -1)), 0, "v22 seeds bugs_created")
	assert_false(bool(job.get("mastery_evaluated", true)), "v22 leaves mastery unevaluated")
	var again := RunState.new()
	again.from_dict(migrated.to_dict())
	assert_almost_eq(
		float(Array(again.build.get("workflows", []))[0].get("output_mult", 0.0)),
		1.0,
		0.001,
		"v22 remigration is idempotent"
	)


## Saving is what produces the `.bak` in the first place: a truncated write to
## the live save must not cost the player the previous, good save it replaced.
func _test_corrupt_primary_save_recovers_from_backup() -> void:
	var state := RunState.new()
	state.economy["cash"] = 4242.0
	var saved: bool = SaveManager.save_run(state, "IN_ROUND", 777, [], false)
	assert_true(saved, "First save succeeds and becomes the backup on the next save")

	state.economy["cash"] = 9999.0
	saved = SaveManager.save_run(state, "IN_ROUND", 777, [], false)
	assert_true(saved, "Second save succeeds, demoting the first to .bak")

	var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string("{not valid json")
	file.close()

	var loaded: Dictionary = SaveManager.load_run()
	assert_true(not loaded.is_empty(), "A corrupt primary save falls back to the backup")
	var recovered_state: Dictionary = loaded.get("run_state", {})
	assert_eq(
		float(recovered_state.get("economy", {}).get("cash", 0.0)), 4242.0,
		"The recovered save is the last good write, not the corrupt one"
	)
	SaveManager.delete_save()
