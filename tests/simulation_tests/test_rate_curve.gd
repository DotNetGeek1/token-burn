extends TestCase

## Throughput has to grow by buying things, not by compounding on itself. These
## cover the ways a multiplier can quietly turn into an exponent.

const RECALC_MULTIPLIER_PERK := {
	"event": "compute.recalculate",
	"priority": 10,
	"source_id": "test.efficiency_perk",
	"conditions": [],
	"effects": [{"operation": "multiply", "target": "compute.efficiency", "value": 1.5}],
}


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_recalculation_does_not_compound()
	_test_triggered_recalculation_does_not_compound()
	_test_permanent_change_uses_the_base()
	_test_burst_stays_out_of_the_sustained_rate()
	_test_burst_is_capped()
	_test_repeat_can_be_bounded()
	_test_curve_stays_in_scale()


## A "+50% efficiency" perk must mean +50%, however many prompts go by.
func _test_recalculation_does_not_compound() -> void:
	var compute := ComputeSystem.new()
	var resolver := EffectResolver.new()
	var state := RunState.new()
	var rng := DeterministicRng.new(7)
	var subs: Array = [RECALC_MULTIPLIER_PERK]

	compute.recalculate(state, resolver, subs, rng)
	var first: float = float(state.compute.get("token_rate", 0.0))
	assert_almost_eq(float(state.compute.get("efficiency", 0.0)), 1.5, 0.0001, "Perk applies its multiplier once")
	for _i in range(20):
		compute.recalculate(state, resolver, subs, rng)
	assert_almost_eq(float(state.compute.get("efficiency", 0.0)), 1.5, 0.0001, "Twenty recalculations still mean +50%")
	assert_almost_eq(float(state.compute.get("token_rate", 0.0)), first, 0.0001, "Rate does not drift across recalculations")
	assert_almost_eq(float(state.compute.get("efficiency_base", 0.0)), 1.0, 0.0001, "The base is left alone")


## Content can re-trigger a recalculation from inside another event, which used
## to hand the stat its own output and compound it every prompt.
func _test_triggered_recalculation_does_not_compound() -> void:
	var compute := ComputeSystem.new()
	var resolver := EffectResolver.new()
	var state := RunState.new()
	var rng := DeterministicRng.new(7)
	var subs: Array = [
		RECALC_MULTIPLIER_PERK,
		{
			"event": "prompt.started",
			"priority": 0,
			"source_id": "test.cascade",
			"conditions": [],
			"effects": [{"operation": "trigger", "target": "", "value": "compute.recalculate"}],
		},
	]
	compute.recalculate(state, resolver, subs, rng)
	for _i in range(10):
		resolver.begin_action("prompt.started")
		var mod_ctx := ModifierContext.new("prompt.started", state)
		mod_ctx.rng = rng.derive("prompt.started")
		mod_ctx.set_value("compute.token_rate", float(state.compute.get("token_rate", 0.0)))
		resolver.dispatch("prompt.started", mod_ctx, subs)
	assert_almost_eq(
		float(state.compute.get("efficiency_base", 0.0)),
		1.0,
		0.0001,
		"A triggered recalculation cannot bank its own multiplier"
	)


## Events that mean to change efficiency for good still can.
func _test_permanent_change_uses_the_base() -> void:
	var compute := ComputeSystem.new()
	var resolver := EffectResolver.new()
	var state := RunState.new()
	var rng := DeterministicRng.new(7)
	resolver.apply_effects(state, [{"operation": "multiply", "target": "compute.efficiency_base", "value": 0.5}], "event.test")
	compute.recalculate(state, resolver, [], rng)
	assert_almost_eq(float(state.compute.get("efficiency", 0.0)), 0.5, 0.0001, "A permanent debuff reaches the derived rate")
	compute.recalculate(state, resolver, [], rng)
	assert_almost_eq(float(state.compute.get("efficiency", 0.0)), 0.5, 0.0001, "And stays put rather than decaying further")


func _test_burst_stays_out_of_the_sustained_rate() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(910)
	var sustained_before: float = float(sim.run_state.compute.get("token_rate", 0.0))
	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(offers.size() > 0, "Offers available for burst test")
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work_sync()
	assert_almost_eq(
		float(sim.run_state.compute.get("token_rate", 0.0)),
		sustained_before,
		0.01,
		"Working a round does not inflate the rate the player is shown"
	)
	sim.free()


func _test_burst_is_capped() -> void:
	var scaling: Dictionary = ContentDatabase.balance.get("job_scaling", {})
	var cap: float = float(scaling.get("max_burst_multiplier", 8.0))
	assert_true(cap > 1.0, "A burst is worth more than a normal prompt")

	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(911)
	# A perk stack far beyond anything in content, to prove the cap holds.
	sim.run_state.build["perks"] = ["perk.hot_streak", "perk.infinite_context", "perk.pipeline_momentum"]
	sim.run_state.calendar["round"] = 9
	sim._invalidate_subscriptions()
	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work_sync()
	var sustained: float = float(sim.run_state.compute.get("token_rate", 0.0))
	assert_true(
		float(sim.run_state.compute.get("prompt_rate", 0.0)) <= sustained * cap + 0.01,
		"However the perks stack, one prompt is capped at %.0f× the rig" % cap
	)
	sim.free()


func _test_repeat_can_be_bounded() -> void:
	var resolver := EffectResolver.new()
	var state := RunState.new()
	state.calendar["round"] = 10
	var mod_ctx := ModifierContext.new("prompt.started", state)
	mod_ctx.set_value("compute.token_rate", 100.0)
	var subs: Array = [{
		"event": "prompt.started",
		"priority": 0,
		"conditions": [],
		"effects": [{
			"operation": "repeat",
			"value": "calendar.round",
			"max_repeats": 3,
			"effects": [{"operation": "multiply", "target": "compute.token_rate", "value": 2.0}],
		}],
	}]
	resolver.begin_action("repeat.test")
	resolver.dispatch("prompt.started", mod_ctx, subs)
	assert_almost_eq(
		float(mod_ctx.get_value("compute.token_rate", 0.0)),
		800.0,
		0.01,
		"Ten rounds of growth stops at three stacks"
	)


## Guards the shape of the curve: everything buyable, stacked together, should
## land in the scale the contract tiers are written for.
func _test_curve_stays_in_scale() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(912)
	sim.run_state.economy["cash"] = 500000.0
	for upgrade in ContentDatabase.upgrades:
		sim.buy_upgrade(upgrade.id)
	var sustained: float = float(sim.run_state.compute.get("token_rate", 0.0))
	var scaling: Dictionary = ContentDatabase.balance.get("job_scaling", {})
	var top_tier_rate: float = 0.0
	for entry in scaling.get("tier_unlock_by_token_rate", []):
		if entry is Dictionary:
			top_tier_rate = maxf(top_tier_rate, float(entry.get("rate", 0.0)))
	assert_true(
		sustained >= top_tier_rate,
		"Owning everything reaches the top contract tier (%s of %s)" % [
			NumberFormat.format_token_rate(sustained),
			NumberFormat.format_token_rate(top_tier_rate),
		]
	)
	assert_true(
		sustained <= top_tier_rate * 20.0,
		"The ladder does not overshoot the tier table by orders of magnitude (%s)" % NumberFormat.format_token_rate(sustained)
	)
	sim.free()
