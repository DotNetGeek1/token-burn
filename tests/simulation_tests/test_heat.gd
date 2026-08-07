extends TestCase

## Cooling has to be able to keep up with the rigs the player can buy, or the
## hardware ladder contains a purchase that guarantees a fire.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_every_rig_can_be_cooled()
	_test_rack_needs_industrial_space()
	_test_heat_sheds_between_rounds()
	_test_fire_risk_clears_when_cool()
	_test_purchase_warning()
	_test_burn_forecast_matches_the_heat_the_bar_actually_gains()
	_test_cool_forecast_matches_the_heat_the_bar_actually_loses()
	_test_status_effects_wear_off()
	_test_an_events_heat_spike_is_shed_like_any_other_heat()


## The point of the test: for each hardware tier there must exist some
## combination of purchasable space and cooling that holds heat steady.
func _test_every_rig_can_be_cooled() -> void:
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	var gain_factor: float = float(heat_cfg.get("gain_per_power", 0.025))
	var cooling_factor: float = float(heat_cfg.get("cooling_factor", 0.35))
	var dwellings: Dictionary = ContentDatabase.balance.get("dwelling_costs", {})
	var best_dwelling_cooling: float = 0.0
	for key in dwellings.keys():
		best_dwelling_cooling += float(dwellings[key].get("cooling_capacity", 0.0))
	var upgrade_cooling: float = 0.0
	for upgrade in ContentDatabase.upgrades:
		for effect in upgrade.effects:
			if effect is EffectDefinition and effect.target == "compute.cooling":
				upgrade_cooling += float(effect.value)
	var max_cooling: float = best_dwelling_cooling + upgrade_cooling

	var total_draw: float = 0.0
	var hardware: Dictionary = ContentDatabase.balance.get("hardware_curves", {})
	for key in hardware.keys():
		total_draw += float(hardware[key].get("power_draw", 0.0))
	var needed: float = total_draw * gain_factor / cooling_factor
	assert_true(
		max_cooling >= needed,
		"Every rig together can be cooled (need %d, max purchasable %d)" % [int(ceil(needed)), int(max_cooling)]
	)

	# The warehouse is the space that makes a rack viable, so it must be buyable.
	var has_warehouse_upgrade: bool = false
	for upgrade in ContentDatabase.upgrades:
		if upgrade.dwelling_key == "warehouse":
			has_warehouse_upgrade = true
	assert_true(has_warehouse_upgrade, "Warehouse dwelling is purchasable")


func _test_rack_needs_industrial_space() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(501)
	sim.run_state.economy["cash"] = 200000.0
	assert_true(sim.buy_upgrade("upgrade.portable_ac"), "Air conditioner bought")
	assert_true(sim.buy_upgrade("upgrade.garage"), "Garage rented")
	assert_true(sim.buy_upgrade("upgrade.gpu_rack"), "GPU rack bought")
	var garage_outlook: Dictionary = sim.heat_outlook()
	assert_false(bool(garage_outlook.get("sustainable", true)), "A rack still cooks in the garage")

	# Property is a ladder, so the office is the step between the two.
	assert_true(sim.buy_upgrade("upgrade.office_unit"), "Office unit rented")
	assert_true(sim.buy_upgrade("upgrade.warehouse"), "Warehouse leased")
	var warehouse_outlook: Dictionary = sim.heat_outlook()
	assert_true(bool(warehouse_outlook.get("sustainable", false)), "A rack is sustainable in the warehouse")
	assert_true(float(warehouse_outlook.get("heat_per_prompt", 1.0)) <= 0.0, "Warehouse cooling out-paces the rack")
	sim.free()


func _test_heat_sheds_between_rounds() -> void:
	var heat := HeatSystem.new()
	var state := RunState.new()
	state.compute["heat"] = 90.0
	heat.shed_between_rounds(state)
	assert_true(float(state.compute.get("heat", 0.0)) < 90.0, "Downtime between rounds sheds heat")
	assert_true(float(state.compute.get("heat", 0.0)) > 0.0, "Shedding does not wipe heat entirely")


func _test_fire_risk_clears_when_cool() -> void:
	var heat := HeatSystem.new()
	var state := RunState.new()
	state.flags["fire_risk"] = true
	state.compute["heat"] = 120.0
	heat.shed_between_rounds(state)
	assert_false(bool(state.flags.get("fire_risk", true)), "Cooling off clears the fire warning")

	var progression := ProgressionSystem.new()
	assert_false(progression.check_loss(state), "A cooled rig no longer burns down")


func _test_purchase_warning() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(502)
	assert_true(sim.upgrade_heat_warning("upgrade.gpu_rack") != "", "Bedroom warns about the rack")
	assert_eq(sim.upgrade_heat_warning("upgrade.portable_ac"), "", "Cooling hardware carries no heat warning")
	assert_eq(sim.upgrade_heat_warning("upgrade.garage"), "", "Dwellings carry no hardware heat warning")
	sim.free()


## The forecast used to show only the pipeline's own stage heat, but every
## round also gains ambient heat from powered-on hardware and loses some to
## cooling, regardless of burning or cooling. That ambient half was invisible,
## so the number shown never matched what the heat bar actually did.
func _test_burn_forecast_matches_the_heat_the_bar_actually_gains() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(503)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work()

	var preview: Dictionary = sim.preview_burn()
	assert_true(preview.get("ok", false), "The board previews the burn")
	var heat_before: float = float(sim.run_state.compute.get("heat", 0.0))
	sim.burn_batch()
	var actual_delta: float = float(sim.run_state.compute.get("heat", 0.0)) - heat_before
	assert_almost_eq(
		float(preview.get("total_heat", 0.0)), actual_delta, 0.01,
		"The forecast heat delta matches what actually lands on the heat bar"
	)
	sim.free()


## COOL vents a share of current heat, but the same ambient gain/cooling pass
## lands the round either way. A forecast that only showed the vent amount
## could look like nothing happened, or that heat went up, with no warning.
func _test_cool_forecast_matches_the_heat_the_bar_actually_loses() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(504)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work()
	sim.run_state.compute["heat"] = 60.0

	var preview: Dictionary = sim.preview_cool()
	assert_true(preview.get("ok", false), "The board previews cooling")
	var heat_before: float = float(sim.run_state.compute.get("heat", 0.0))
	sim.cool_hardware()
	var actual_delta: float = float(sim.run_state.compute.get("heat", 0.0)) - heat_before
	assert_almost_eq(
		float(preview.get("total_heat", 0.0)), actual_delta, 0.01,
		"The forecast net heat change matches what COOL actually does"
	)
	sim.free()


## An event that hangs a per-prompt cost on the rig used to charge it for the
## rest of the run, because nothing ever removed a status effect. A rig that
## gains heat every prompt forever can never be cooled back down.
func _test_status_effects_wear_off() -> void:
	var sim: Node = _sim_with_a_one_prompt_contract(505)
	sim.run_state.build["status_effects"] = [
		{
			"id": "status.test_war_room",
			"name": "Test War Room",
			"rounds": 2,
			"subscriptions": [{
				"event": "prompt.started",
				"priority": 0,
				"conditions": [],
				"effects": [{"operation": "add", "target": "compute.heat", "value": 4}],
			}],
		},
		{
			"id": "status.test_permanent",
			"name": "Test Standing Bonus",
			"subscriptions": [{
				"event": "round.started",
				"priority": 0,
				"conditions": [],
				"effects": [{"operation": "add", "target": "economy.cash", "value": 1}],
			}],
		},
	]
	sim._invalidate_subscriptions()

	sim._expire_status_effects()
	assert_eq(
		sim.run_state.build["status_effects"].size(), 2,
		"A two-round status survives its first round end"
	)
	assert_eq(
		int(sim.run_state.build["status_effects"][0].get("rounds", 0)), 1,
		"With one round left on it"
	)

	sim._expire_status_effects()
	var remaining: Array = sim.run_state.build["status_effects"]
	assert_eq(remaining.size(), 1, "And is gone by the end of the second")
	assert_eq(
		str(remaining[0].get("id", "")), "status.test_permanent",
		"A status with no stated duration is permanent by design"
	)
	var sources: Array = []
	for sub in sim._collect_subscriptions():
		sources.append(str(sub.get("source_id", "")))
	assert_false(
		"status.test_war_room" in sources,
		"An expired status no longer reaches the dispatcher"
	)
	sim.free()


## The +25 from a dying fan used to land after the round's downtime had already
## been taken, so it sat on the rig with nothing to shed it.
func _test_an_events_heat_spike_is_shed_like_any_other_heat() -> void:
	var sim: Node = _sim_with_a_one_prompt_contract(506)
	sim.run_state.economy["cash"] = 50000.0
	sim.start_work_sync()
	var after_round: float = float(sim.run_state.compute.get("heat", 0.0))
	var retained: float = float(
		ContentDatabase.balance.get("economy", {}).get("heat", {}).get("round_end_retained", 0.5)
	)
	# Whatever the round's event did, the shed is the last thing to touch heat,
	# so the rig can never open a round hotter than the retained share of 200.
	assert_true(
		after_round <= 200.0 * retained + 0.01,
		"Downtime is applied after the round's event, not before it"
	)
	sim.free()


## A run with one trivial contract, so working the round closes it immediately.
func _sim_with_a_one_prompt_contract(seed_value: int) -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(seed_value)
	sim.run_state.business["job_queue"] = [{
		"id": "job.product_descriptions",
		"name": "Test",
		"token_requirement": 1.0,
		"tokens_remaining": 1.0,
		"deadline_prompts": 99,
		"prompts_remaining": 99,
		"reward": 20.0,
		"quality_threshold": 0.0,
		"quality": 0.0,
		"revision_risk": 0.0,
		"bug_chance": 0.0,
	}]
	return sim
