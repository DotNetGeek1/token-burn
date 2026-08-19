extends TestCase

## Quality used to be a pass mark: half pay under the client's bar, and nothing
## whatsoever for clearing it well. Reputation used to be a number that only
## moved contract tiers. Both are now curves the player can feel — quality sets
## the fee, the fee's quality feeds reputation, and reputation raises the fee.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_quality_pay_is_a_curve_not_a_gate()
	_test_quality_pay_reaches_the_fee()
	_test_reputation_raises_every_fee()
	_test_reputation_names_its_next_tier()
	_test_a_session_is_paid_in_reputation_by_quality()
	_test_a_throughput_only_board_misses_the_bar()
	_test_a_contract_is_judged_at_the_bar_it_advertises()
	_test_projected_pay_includes_known_bugs()
	_test_hidden_bugs_are_a_risk_class()


func _payout(quality: float, threshold: float) -> float:
	return JobSystem.quality_payout_multiplier(quality, threshold)


func _config() -> Dictionary:
	return ContentDatabase.balance.get("job_scaling", {}).get("quality_payout", {})


func _sim() -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	return sim


func _test_quality_pay_is_a_curve_not_a_gate() -> void:
	var floor_mult: float = float(_config().get("penalty_floor", 0.5))
	assert_almost_eq(_payout(0.0, 60.0), floor_mult, 0.001, "Delivering nothing pays the floor")
	assert_almost_eq(_payout(60.0, 60.0), 1.0, 0.001, "Exactly on the bar pays the fee in full")
	assert_almost_eq(
		_payout(30.0, 60.0),
		(floor_mult + 1.0) * 0.5,
		0.001,
		"Halfway to the bar pays halfway between the floor and the fee"
	)
	assert_true(
		_payout(50.0, 60.0) > _payout(40.0, 60.0),
		"Every point of quality under the bar is worth something, so there is no cliff"
	)


func _test_quality_pay_reaches_the_fee() -> void:
	var cfg: Dictionary = _config()
	var bonus_max: float = float(cfg.get("bonus_max", 0.3))
	var span: float = float(cfg.get("bonus_span", 40.0))
	assert_true(bonus_max > 0.0, "There is something to aim at above the bar")
	assert_almost_eq(
		_payout(60.0 + span, 60.0),
		1.0 + bonus_max,
		0.001,
		"A full span above the bar earns the whole bonus"
	)
	assert_almost_eq(
		_payout(60.0 + span * 4.0, 60.0),
		1.0 + bonus_max,
		0.001,
		"And the bonus is capped, so quality is not a runaway"
	)
	assert_true(
		_payout(80.0, 60.0) > _payout(61.0, 60.0),
		"Comfortably clearing the bar beats scraping over it"
	)
	assert_almost_eq(
		_payout(20.0, 0.0), 1.0, 0.001, "A contract with no quality bar pays the fee as written"
	)

	# The graded curve is what the payout actually uses, not just a helper.
	var state := RunState.new()
	var job_system := JobSystem.new()
	var messages: Array[String] = []
	var job: Dictionary = {
		"id": "job.test",
		"name": "Test Contract",
		"reward": 1000.0,
		"quality": 100.0,
		"quality_threshold": 60.0,
		"tokens_remaining": 0.0,
	}
	var paid: float = job_system._calculate_reward(
		state, job, EffectResolver.new(), [], {}, EconomySystem.new(), messages, false,
		DeterministicRng.new(11)
	)
	assert_almost_eq(
		paid, 1000.0 * _payout(100.0, 60.0), 0.01, "Delivered quality is priced into the fee"
	)
	assert_almost_eq(
		float(job.get("quality_multiplier", 0.0)),
		_payout(100.0, 60.0),
		0.001,
		"And the multiplier is recorded on the contract so the debrief can show it"
	)


func _test_reputation_raises_every_fee() -> void:
	var cfg: Dictionary = ContentDatabase.balance.get("job_scaling", {}).get("reputation", {})
	var per_point: float = float(cfg.get("reward_per_point", 0.0))
	var cap: float = float(cfg.get("reward_bonus_cap", 0.0))
	assert_true(per_point > 0.0, "Reputation is worth something on the fee")

	var state := RunState.new()
	state.business["reputation"] = 20.0
	assert_almost_eq(
		JobSystem.reputation_reward_multiplier(state, ContentDatabase),
		1.0 + 20.0 * per_point,
		0.001,
		"A known studio charges more for the same work"
	)
	state.business["reputation"] = 100000.0
	assert_almost_eq(
		JobSystem.reputation_reward_multiplier(state, ContentDatabase),
		1.0 + cap,
		0.001,
		"But only up to a point"
	)
	state.business["reputation"] = -4.0
	assert_almost_eq(
		JobSystem.reputation_reward_multiplier(state, ContentDatabase),
		1.0,
		0.001,
		"A damaged reputation costs tiers and the run, not the fee twice over"
	)


func _test_reputation_names_its_next_tier() -> void:
	var state := RunState.new()
	var thresholds: Array = ContentDatabase.balance.get("job_scaling", {}).get(
		"tier_unlock_by_reputation", []
	)
	assert_true(thresholds.size() > 1, "There is a reputation ladder to climb")
	state.business["reputation"] = 0.0
	var next_tier: Dictionary = JobSystem.next_reputation_tier(state, ContentDatabase)
	assert_eq(int(next_tier.get("tier", -1)), 1, "The first rung above a fresh run is tier 1")
	assert_almost_eq(
		float(next_tier.get("reputation", 0.0)),
		float(thresholds[1]),
		0.001,
		"Named at the reputation it actually wants"
	)

	var reduction: float = float(
		ContentDatabase.balance.get("job_scaling", {}).get("sales_level_rep_reduction", 2)
	)
	state.build["upgrade_levels"] = {"upgrade.sales_investment": 1}
	assert_almost_eq(
		float(JobSystem.next_reputation_tier(state, ContentDatabase).get("reputation", 0.0)),
		float(thresholds[1]) - reduction,
		0.001,
		"Sales outreach brings the next rung closer"
	)

	state.build["upgrade_levels"] = {}
	state.business["reputation"] = 100000.0
	assert_true(
		JobSystem.next_reputation_tier(state, ContentDatabase).is_empty(),
		"With every tier open there is nothing left to name"
	)


## Shipping work is worth something on its own, but not enough to clear a real
## client's bar. A build with no quality modules in the pipeline has to miss, or
## the bar is decoration and the whole stat is a number that only goes up.
func _test_a_throughput_only_board_misses_the_bar() -> void:
	var scaling: Dictionary = ContentDatabase.balance.get("job_scaling", {})
	var base_ratio: float = float(scaling.get("board", {}).get("base_quality_ratio", 0.45))
	assert_true(base_ratio > 0.0, "Delivered work is still worth something")
	# A contract carried all the way to delivery by throughput alone, and nothing
	# else: this is the whole quality a board with no quality stages can earn.
	var passive: float = 100.0 * base_ratio
	var mid_tier_bar: float = float(
		scaling.get("quality_scaling", {}).get("base_threshold", 50.0)
	) + 2.0 * float(scaling.get("quality_scaling", {}).get("per_tier_increase", 8.0))
	assert_true(
		passive < mid_tier_bar,
		"A throughput-only build lands at %.0f, under a mid-tier bar of %.0f" % [
			passive, mid_tier_bar
		]
	)
	assert_true(
		_payout(passive, mid_tier_bar) < 1.0,
		"And is paid less than the advertised fee for it"
	)


## The cap on the tier baseline used to overwrite whatever a contract asked for,
## so a brief demanding 88 was quietly marked at 50 and every board cleared it.
func _test_a_contract_is_judged_at_the_bar_it_advertises() -> void:
	var demanding: JobDefinition = null
	for job in ContentDatabase.jobs:
		if job.quality_threshold >= 70.0:
			demanding = job
			break
	if demanding == null:
		return
	var job_system := JobSystem.new()
	var state := RunState.new()
	var offer: Dictionary = job_system._scale_job(
		demanding, 1, ContentDatabase, {}, state, DeterministicRng.new(7)
	)
	assert_almost_eq(
		float(offer.get("quality_threshold", 0.0)),
		clampf(demanding.quality_threshold, 35.0, 92.0),
		0.001,
		"%s is posted at the bar its brief asks for" % demanding.name
	)


func _test_a_session_is_paid_in_reputation_by_quality() -> void:
	var cfg: Dictionary = ContentDatabase.balance.get("job_scaling", {}).get("reputation", {})
	var margin: float = float(cfg.get("excellent_margin", 20))
	var sim: Node = _sim()

	sim.run_state.business["reputation"] = 10.0
	var excellent: float = sim._settle_reputation(
		[{"quality": 60.0 + margin, "quality_threshold": 60.0}], []
	)
	assert_almost_eq(
		excellent,
		float(cfg.get("session_gain_excellent", 3)),
		0.001,
		"Work well clear of the client's bar is what gets talked about"
	)

	sim.run_state.business["reputation"] = 10.0
	var met: float = sim._settle_reputation([{"quality": 62.0, "quality_threshold": 60.0}], [])
	assert_almost_eq(
		met,
		float(cfg.get("session_gain_met", 2)),
		0.001,
		"Clearing it is worth the ordinary gain"
	)
	assert_true(met < excellent, "And less than clearing it comfortably")

	sim.run_state.business["reputation"] = 10.0
	var under: float = sim._settle_reputation([{"quality": 40.0, "quality_threshold": 60.0}], [])
	assert_almost_eq(
		under,
		float(cfg.get("session_gain_under", 0)),
		0.001,
		"Shipping under the bar takes the reduced fee and earns no standing"
	)

	sim.run_state.business["reputation"] = 10.0
	var failed: float = sim._settle_reputation([], [{"quality": 0.0, "quality_threshold": 60.0}, {}])
	assert_almost_eq(failed, -4.0, 0.001, "A missed deadline still costs two per contract")
	assert_almost_eq(
		float(sim.run_state.business.get("reputation", 0.0)),
		6.0,
		0.001,
		"And the loss lands on the run"
	)
	sim.free()


func _test_projected_pay_includes_known_bugs() -> void:
	var clean := {
		"quality": 70.0, "quality_threshold": 60.0, "known_bugs": 0, "hidden_bugs": 0,
	}
	var buggy: Dictionary = clean.duplicate()
	buggy["known_bugs"] = 2
	assert_almost_eq(
		JobSystem.known_bug_quality_penalty(buggy), 6.0, 0.001, "Two known bugs cost six quality"
	)
	assert_true(
		JobSystem.projected_payout_multiplier(buggy) < JobSystem.projected_payout_multiplier(clean),
		"The HUD pay figure includes the known-bug tax, not just the raw meter"
	)
	assert_almost_eq(
		JobSystem.known_bug_fee_multiplier(buggy), 0.84, 0.001, "Two known bugs also cut the fee 8% each"
	)


func _test_hidden_bugs_are_a_risk_class() -> void:
	assert_eq(JobSystem.production_risk_class({"hidden_bugs": 0}), "LOW", "No buried defects is low risk")
	assert_eq(JobSystem.production_risk_class({"hidden_bugs": 1}), "ELEVATED", "One is elevated")
	assert_eq(JobSystem.production_risk_class({"hidden_bugs": 2}), "HIGH", "Two is high")
	assert_eq(JobSystem.production_risk_class({"hidden_bugs": 4}), "INSANE", "Four is insane")
	assert_almost_eq(
		JobSystem.expected_reputation_hit({"hidden_bugs": 2}), 1.2, 0.001,
		"Expected reputation loss stays a band, not a roll"
	)
