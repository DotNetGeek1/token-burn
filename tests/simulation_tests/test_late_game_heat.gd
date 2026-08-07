extends TestCase

## The reported bug, as a test: by the middle of the game the COOL key only ever
## showed "+N HEAT". Cooling had stopped being something the market sold and
## started being something the property ladder happened to include, so a rig
## grown past the garage could not be brought back down at all.
##
## Every era is checked the way a player reaches it: start in that chapter's
## location, buy the machine, buy the cooling that era sells, and then ask
## whether venting still works. If it does not, the era is unplayable.

## Each chapter of the campaign: where the run happens, the machine that belongs
## in it, and the cooling on sale there.
const ERAS := [
	{"location": "bedroom", "hardware": "upgrade.custom_desktop", "cooler": "upgrade.portable_ac"},
	{"location": "garage", "hardware": "upgrade.gpu_rack", "cooler": "upgrade.immersion_cooling"},
	{"location": "office_unit", "hardware": "upgrade.compute_cluster", "cooler": "upgrade.industrial_chiller"},
	{"location": "warehouse", "hardware": "upgrade.garage_datacentre", "cooler": "upgrade.chilled_water_plant"},
	{"location": "datacentre_campus", "hardware": "upgrade.compute_warehouse", "cooler": "upgrade.cryo_exchange"},
]


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_every_era_can_still_vent()
	_test_cooling_is_always_on_sale()
	_test_a_hot_late_rig_can_be_cooled_back_to_zero()


## The core assertion: at every era, with that era's cooling bought, ambient
## heat is not running away and the COOL key reads as a reduction.
func _test_every_era_can_still_vent() -> void:
	for era in ERAS:
		var sim: Node = _rig_for(era)
		var outlook: Dictionary = sim.heat_outlook()
		assert_true(
			bool(outlook.get("sustainable", false)),
			"%s is sustainable once its own cooling is bought (need %d, have %d)" % [
				str(era["hardware"]),
				int(ceil(float(outlook.get("cooling_needed", 0.0)))),
				int(outlook.get("cooling", 0.0)),
			]
		)

		_start_a_round(sim)
		sim.run_state.compute["heat"] = 80.0
		var preview: Dictionary = sim.preview_cool()
		assert_true(preview.get("ok", false), "%s can preview a cool" % str(era["hardware"]))
		assert_true(
			float(preview.get("total_heat", 0.0)) < 0.0,
			"COOL still sheds heat at %s (forecast %+.1f)" % [
				str(era["hardware"]), float(preview.get("total_heat", 0.0)),
			]
		)
		sim.free()


## Whatever the player has just bought, there is always more cooling to buy.
## The original cliff was an empty Cooling shelf after the one air conditioner.
func _test_cooling_is_always_on_sale() -> void:
	for era in ERAS:
		var sim: Node = _rig_for(era)
		sim.run_state.economy["cash"] = 1.0e15
		var on_sale: Array[String] = []
		for upgrade in ContentDatabase.upgrades:
			if "cooling" in Array(upgrade.tags) and sim.can_buy_upgrade(upgrade.id):
				on_sale.append(upgrade.id)
		assert_true(
			on_sale.size() > 0,
			"The Cooling shelf still has stock after %s (owns %s)" % [
				str(era["cooler"]), str(era["hardware"]),
			]
		)
		sim.free()


## Venting has to be able to finish the job, not merely tick the number down by
## less than the next prompt puts back on.
func _test_a_hot_late_rig_can_be_cooled_back_to_zero() -> void:
	var sim: Node = _rig_for(ERAS[2])
	_start_a_round(sim)
	sim.run_state.compute["heat"] = 190.0
	var last: float = 190.0
	for i in range(12):
		var result: Dictionary = sim.cool_hardware()
		if not bool(result.get("ok", false)):
			break
		var now: float = float(sim.run_state.compute.get("heat", 0.0))
		assert_true(now < last + 0.01, "Cool prompt %d does not add heat (%.1f -> %.1f)" % [i, last, now])
		last = now
		if last <= 0.01:
			break
	assert_true(last <= 1.0, "A cooked compute cluster can be brought back down (left at %.1f)" % last)
	sim.free()


## A run set in one chapter of the campaign, with the money already there and
## nothing else bought that would muddy the heat maths.
func _rig_for(era: Dictionary) -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(6100)
	sim.apply_run_location(sim.run_state, str(era["location"]))
	sim.run_state.economy["cash"] = 1.0e15
	assert_true(sim.buy_upgrade(str(era["hardware"])), "Bought the %s" % str(era["hardware"]))
	var cooler: String = str(era["cooler"])
	var safety: int = 0
	# Buy the era's cooling until the rig is in balance, which is exactly what
	# the Market's own shortfall warning tells the player to do.
	while not bool(sim.heat_outlook().get("sustainable", false)) and safety < 40:
		safety += 1
		if not sim.buy_upgrade(cooler):
			break
	return sim


## COOL is a prompt, and prompts only happen inside a working round.
func _start_a_round(sim: Node) -> void:
	sim.run_state.business["job_queue"] = [{
		"id": "job.product_descriptions",
		"name": "Heat Test",
		"token_requirement": 1.0e18,
		"tokens_remaining": 1.0e18,
		"deadline_prompts": 999,
		"prompts_remaining": 999,
		"reward": 20.0,
		"quality_threshold": 0.0,
		"quality": 0.0,
		"revision_risk": 0.0,
		"bug_chance": 0.0,
	}]
	sim.start_work()
