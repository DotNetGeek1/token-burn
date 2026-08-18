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


## Later chapters start hotter until that era's cooler is bought. Ratios are
## cooling / cooling_needed on the room's starter machine (laptop included).
const STARTER_PRESSURE := [
	{"location": "office_unit", "cooler": "upgrade.immersion_cooling"},
	{"location": "warehouse", "cooler": "upgrade.industrial_chiller"},
	{"location": "datacentre_campus", "cooler": "upgrade.chilled_water_plant"},
	{"location": "private_power_grid", "cooler": "upgrade.cryo_exchange"},
	{"location": "moon_facility", "cooler": "upgrade.orbital_cooling_array"},
]


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_every_era_can_still_vent()
	_test_cooling_is_always_on_sale()
	_test_a_hot_late_rig_can_be_cooled_back_to_zero()
	_test_moon_ambient_stays_on_the_bar()
	_test_overclock_is_a_share_of_the_bar()
	_test_office_starter_is_not_sustainable()
	_test_later_starters_run_hotter_until_cooled()


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


## The old watt-vs-cooling formula dumped tens of thousands of heat on the moon
## in one prompt. The load-normalized tick cannot exceed load_pressure × bar.
func _test_moon_ambient_stays_on_the_bar() -> void:
	var sim: Node = _starter_in("moon_facility")
	var outlook: Dictionary = sim.heat_outlook()
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	var load_pressure: float = float(heat_cfg.get("load_pressure", 0.15))
	var capacity: float = maxf(1.0, float(sim.run_state.compute.get("heat_capacity", 800.0)))
	var ambient: float = float(outlook.get("heat_per_prompt", 0.0))
	assert_true(
		absf(ambient) <= load_pressure * capacity + 0.01,
		"Moon ambient stays on the bar (ΔH=%s, cap=%s)" % [str(ambient), str(capacity)]
	)
	var heat := HeatSystem.new()
	var before: float = float(sim.run_state.compute.get("heat", 0.0))
	heat.process_prompt(sim.run_state, [], EffectResolver.new(), DeterministicRng.new(1))
	assert_almost_eq(
		float(sim.run_state.compute.get("heat", 0.0)) - before,
		ambient,
		0.01,
		"process_prompt and heat_outlook share the same moon ambient tick"
	)
	sim.free()


## Overclock is authored as +18 on a 100-point bedroom bar. Scaling has to keep
## that the same share of every later room, or the card becomes a rounding error.
func _test_overclock_is_a_share_of_the_bar() -> void:
	for location in ["bedroom", "moon_facility"]:
		var sim: Node = _starter_in(location)
		_start_a_round(sim)
		var slots: Array = sim.board_slots()
		for i in range(slots.size()):
			slots[i] = ""
		if slots.size() > 0:
			slots[0] = "op.overclock"
		sim.run_state.build["board"]["slots"] = slots
		var preview: Dictionary = sim.preview_burn()
		assert_true(preview.get("ok", false), "Overclock burn previews in the %s" % location)
		var ambient: float = float(sim.heat_outlook().get("heat_per_prompt", 0.0))
		var pipeline: float = float(preview.get("total_heat", 0.0)) - ambient
		var capacity: float = maxf(1.0, float(sim.run_state.compute.get("heat_capacity", 100.0)))
		assert_almost_eq(
			pipeline / capacity, 0.18, 0.02,
			"Overclock is ~18%% of the %s bar (applied %s / %s)" % [
				location, str(pipeline), str(capacity),
			]
		)
		sim.free()


## The GPU rack is the teaching beat: the office starts cooking until immersion
## is bought. Bedroom laptop stays the one starter that is already fine.
func _test_office_starter_is_not_sustainable() -> void:
	var bedroom: Node = _starter_in("bedroom")
	var bedroom_outlook: Dictionary = bedroom.heat_outlook()
	assert_true(bool(bedroom_outlook.get("sustainable", false)), "Bedroom laptop stays sustainable")
	assert_true(
		float(bedroom_outlook.get("heat_per_prompt", 1.0)) <= 0.0,
		"Bedroom ambient does not climb before any burns"
	)
	bedroom.free()

	var office: Node = _starter_in("office_unit")
	assert_false(
		bool(office.heat_outlook().get("sustainable", true)),
		"Office starter (laptop + GPU rack, no extra cooler) is not sustainable"
	)
	office.free()


## Each later chapter starts at a higher load than the last. Buying that era's
## cooler has to close the gap, which is the coolability budget the Market sells.
func _test_later_starters_run_hotter_until_cooled() -> void:
	var previous_ratio: float = INF
	for era in STARTER_PRESSURE:
		var sim: Node = _starter_in(str(era["location"]))
		var outlook: Dictionary = sim.heat_outlook()
		var needed: float = maxf(0.0001, float(outlook.get("cooling_needed", 0.0)))
		var have: float = float(outlook.get("cooling", 0.0))
		var ratio: float = have / needed
		assert_true(
			ratio < previous_ratio - 0.01,
			"%s starter is hotter than the chapter before it (%.2f vs %.2f)" % [
				str(era["location"]), ratio, previous_ratio,
			]
		)
		assert_false(
			bool(outlook.get("sustainable", true)),
			"%s starter runs hot until its cooler is bought" % str(era["location"])
		)
		previous_ratio = ratio

		sim.run_state.economy["cash"] = 1.0e15
		var safety: int = 0
		while not bool(sim.heat_outlook().get("sustainable", false)) and safety < 8:
			safety += 1
			if not sim.buy_upgrade(str(era["cooler"])):
				break
		assert_true(
			bool(sim.heat_outlook().get("sustainable", false)),
			"%s is sustainable after its era cooler (need %d, have %d)" % [
				str(era["location"]),
				int(ceil(float(sim.heat_outlook().get("cooling_needed", 0.0)))),
				int(sim.heat_outlook().get("cooling", 0.0)),
			]
		)
		sim.free()


func _starter_in(location: String) -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(6100)
	sim.apply_run_location(sim.run_state, location)
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	return sim


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
