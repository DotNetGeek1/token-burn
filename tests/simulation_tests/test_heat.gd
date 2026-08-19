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
	_test_queued_burn_forecast_is_pure_and_matches_the_first_burn()
	_test_queued_surges_are_included_in_the_first_burn_forecast()
	_test_first_burn_forecast_marks_a_projected_fire_without_blocking()
	_test_cool_forecast_matches_the_heat_the_bar_actually_loses()
	_test_status_effects_wear_off()
	_test_an_events_heat_spike_is_shed_like_any_other_heat()


## The point of the test: for each hardware tier there must exist some
## combination of purchasable space and cooling that holds heat steady.
func _test_every_rig_can_be_cooled() -> void:
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	var gain_factor: float = float(heat_cfg.get("gain_per_power", 0.06))
	var cooling_factor: float = float(heat_cfg.get("cooling_factor", 0.25))
	var dwellings: Dictionary = ContentDatabase.balance.get("dwelling_costs", {})
	# One run, one location: the best environment on offer, not every one of
	# them stacked on top of each other.
	var best_dwelling_cooling: float = 0.0
	for key in dwellings.keys():
		best_dwelling_cooling = maxf(
			best_dwelling_cooling, float(dwellings[key].get("cooling_capacity", 0.0))
		)
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

	# The warehouse is the space that makes a rack viable, so the campaign has
	# to contain it as a chapter the player can eventually reach.
	assert_true(
		"warehouse" in MetaProgress.location_order(),
		"The warehouse is a location the campaign leads to"
	)


func _test_rack_needs_industrial_space() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(501)
	sim.apply_run_location(sim.run_state, "garage")
	sim.run_state.economy["cash"] = 200000.0
	assert_true(sim.buy_upgrade("upgrade.portable_ac"), "Air conditioner bought")
	assert_true(sim.buy_upgrade("upgrade.gpu_rack"), "GPU rack bought")
	var garage_outlook: Dictionary = sim.heat_outlook()
	assert_false(bool(garage_outlook.get("sustainable", true)), "A rack still cooks in the garage")

	# The same rig, a chapter later. Nothing was bought to get here: the run
	# would have started in the warehouse.
	sim.apply_run_location(sim.run_state, "warehouse")
	var warehouse_outlook: Dictionary = sim.heat_outlook()
	assert_true(bool(warehouse_outlook.get("sustainable", false)), "A rack is sustainable in the warehouse")
	assert_true(float(warehouse_outlook.get("heat_per_prompt", 1.0)) <= 0.0, "Warehouse cooling keeps the rack sustainable")
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
	var gpu: Dictionary = ContentDatabase.balance.get("hardware_curves", {}).get("gpu_rack", {})
	var extra_power: float = float(gpu.get("power_draw", 0.0))
	var current_tier: Dictionary = sim.heat_outlook(extra_power, 0.0, 0)
	var prospective: Dictionary = sim.heat_outlook(extra_power, 0.0, int(gpu.get("work_tier", 2)))
	assert_true(
		HeatSystem.uses_thermal_load(int(gpu.get("work_tier", 2))),
		"A GPU Rack purchase is judged on the thermal-load model"
	)
	assert_true(
		not is_equal_approx(
			float(current_tier.get("heat_per_prompt", 0.0)),
			float(prospective.get("heat_per_prompt", 0.0))
		),
		"The bedroom laptop equation is not the GPU Rack forecast"
	)
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


func _test_queued_burn_forecast_is_pure_and_matches_the_first_burn() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(1503)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(sim.accept_job(str(offers[0].get("id", ""))), "A contract is queued")
	var state_before: Dictionary = sim.run_state.to_dict()
	var phase_before: int = sim.phase
	var queued: Dictionary = sim.preview_next_burn()
	assert_true(queued.get("ok", false), "The first burn is forecast before work opens")
	assert_eq(sim.run_state.to_dict(), state_before, "Queued forecasting does not mutate live state")
	assert_eq(sim.phase, phase_before, "Queued forecasting does not open the session")

	sim.start_work()
	var active: Dictionary = sim.preview_next_burn()
	assert_almost_eq(float(queued.get("tokens", 0.0)), float(active.get("tokens", 0.0)), 0.01,
		"Queued and active previews agree on tokens")
	assert_almost_eq(float(queued.get("heat_after", 0.0)), float(active.get("heat_after", 0.0)), 0.01,
		"Queued and active previews agree on projected heat")
	var before_heat: float = float(sim.run_state.compute.get("heat", 0.0))
	sim.burn_batch()
	assert_almost_eq(
		float(queued.get("heat_after", 0.0)),
		before_heat + (float(sim.run_state.compute.get("heat", 0.0)) - before_heat),
		0.01,
		"The queued forecast matches the committed first burn"
	)
	sim.free()


func _test_queued_surges_are_included_in_the_first_burn_forecast() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(1504)
	sim.run_state.build["upgrades"].append(Simulation.CLOUD_ACCOUNT_UPGRADE)
	sim.run_state.economy["cash"] = 1000000.0
	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	var baseline: Dictionary = sim.preview_next_burn()
	sim.set_queued_boost(true)
	sim.set_queued_cloud(true)
	var surged: Dictionary = sim.preview_next_burn()
	assert_true(
		float(surged.get("tokens", 0.0)) > float(baseline.get("tokens", 0.0)),
		"Queued BOOST and CLOUD increase the pre-session token forecast"
	)
	var boost_heat: float = HeatSystem.boost_heat_for(
		maxf(1.0, float(sim.run_state.compute.get("heat_capacity", 100.0)))
	)
	assert_almost_eq(
		float(surged.get("heat_after", 0.0)) - float(baseline.get("heat_after", 0.0)),
		boost_heat,
		0.5,
		"Queued BOOST heat is visible before the first click"
	)
	sim.free()


func _test_first_burn_forecast_marks_a_projected_fire_without_blocking() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(1505)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	sim.run_state.compute["heat_capacity"] = 1.0
	sim.run_state.compute["heat"] = 0.99
	sim.set_queued_boost(true)
	var preview: Dictionary = sim.preview_next_burn()
	assert_true(bool(preview.get("crosses_fire", false)), "The queued forecast flags a cold-start fire")
	assert_true(sim.can_start_work(), "A fire warning remains informational rather than blocking BURN")
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
