extends TestCase


func run() -> void:
	_test_first_module_reroll_cost_band()
	_test_local_tag_affinity_band()
	_test_pacing_contract_and_profile_fixtures()
	_test_fixed_seed_campaign_matrix_has_safe_nontrivial_first_burns()


func _sim() -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(5150)
	return sim


func _test_first_module_reroll_cost_band() -> void:
	var sim: Node = _sim()
	MarketService.ensure_module_stock(sim)
	var ratio: float = BatchRunner.module_reroll_cost_ratio(sim)
	assert_true(ratio >= 0.02, "First module reroll is not trivially cheap")
	assert_true(ratio <= 0.35, "First module reroll is not punishingly expensive")
	sim.free()


func _test_local_tag_affinity_band() -> void:
	var neutral: float = BatchRunner.module_market_tag_hit_rate(9000, "local", 40, [])
	var committed: float = BatchRunner.module_market_tag_hit_rate(
		9000, "local", 40, ["local"]
	)
	assert_true(committed >= neutral, "Tag affinity never reduces matching Market stock")
	assert_true(committed >= 0.12, "A committed archetype still sees local modules often enough")


func _test_pacing_contract_and_profile_fixtures() -> void:
	var targets: Dictionary = ContentDatabase.balance.get("pacing_targets", {})
	assert_true(not targets.is_empty(), "Pacing acceptance bands are loaded as balance data")
	for profile_id in ["fresh", "established", "veteran"]:
		assert_true(
			targets.get("profiles", {}).has(profile_id),
			"The %s campaign profile is an explicit fixture" % profile_id
		)
	var rounds: Dictionary = targets.get("normal", {}).get("chapter_rounds", {})
	assert_eq(int(rounds.get("fresh", [0, 0])[0]), 5, "Fresh normal pacing starts at five rounds")
	assert_eq(int(rounds.get("fresh", [0, 0])[1]), 8, "Fresh normal pacing ends at eight rounds")
	assert_eq(int(rounds.get("veteran", [0, 0])[0]), 3, "Veteran pacing starts at three rounds")
	assert_eq(int(rounds.get("veteran", [0, 0])[1]), 6, "Veteran pacing ends at six rounds")


## Cheap CI smoke: both fixed seeds, all seven chapters and all supported meta
## profiles can prepare an authored contract and forecast a safe, non-winning
## first burn. The configurable run_balance scene performs the expensive
## multi-round campaign sweep outside the everyday correctness suite.
func _test_fixed_seed_campaign_matrix_has_safe_nontrivial_first_burns() -> void:
	var runner := BatchRunner.new()
	var locations: Array = Array(ContentDatabase.balance.get("economy", {}).get("location_order", []))
	var seeds: Array = Array(
		ContentDatabase.balance.get("pacing_targets", {}).get("smoke", {}).get("seeds", [1000, 1001])
	)
	for seed_value in seeds:
		for profile_id in ["fresh", "established", "veteran"]:
			for location in locations:
				var sim: Node = load("res://core/simulation.gd").new()
				sim.autosave_enabled = false
				sim.start_run(int(seed_value), "normal")
				sim.apply_run_location(sim.run_state, str(location))
				runner._apply_profile(sim, profile_id)
				var offers: Array = sim.run_state.business.get("job_offers", [])
				var chosen: Dictionary = {}
				for offer in offers:
					if bool(offer.get("rig_matched", false)):
						chosen = offer
						break
				if chosen.is_empty() and not offers.is_empty():
					chosen = offers[0]
				assert_true(not chosen.is_empty(), "%s/%s has work on its fixed-seed board" % [profile_id, location])
				if not chosen.is_empty():
					sim.accept_job(str(chosen.get("id", "")))
				var preview: Dictionary = sim.preview_next_burn()
				assert_true(preview.get("ok", false), "%s/%s can forecast its first burn" % [profile_id, location])
				assert_false(
					bool(preview.get("crosses_fire", false)),
					"%s/%s canonical entry build does not cold-start into a fire (%.0f/%.0f heat)" % [
						profile_id, location, float(preview.get("heat_after", 0.0)),
						float(preview.get("heat_capacity", 0.0)),
					]
				)
				var contract: Dictionary = sim.ascension_boss_contract()
				assert_true(
					float(preview.get("tokens", INF)) < float(contract.get("total_burn", 0.0)),
					"%s/%s cannot clear its visible chapter contract with the first burn (%.1f/%.1f)" % [
						profile_id, location, float(preview.get("tokens", 0.0)),
						float(contract.get("total_burn", 0.0)),
					]
				)
				sim.free()
