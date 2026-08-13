extends TestCase

## The Burn Board is the work engine, so these cover the promises the screen
## makes to the player: order matters, a burn is predictable before you commit
## to it, hidden bugs stay hidden until something looks, and a contract's rules
## actually bite.

const STARTER_PIPELINE := ["op.prompt", "op.cheap_model", "op.unit_tests"]


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_every_operation_resolves()
	_test_empty_pipeline_refuses_to_burn()
	_test_order_matters()
	_test_cache_is_positional()
	_test_agent_repeats_the_stage_above()
	_test_ship_it_hides_its_bugs()
	_test_tests_reveal_and_fix()
	_test_burn_is_deterministic()
	_test_kill_process_keeps_finished_stages()
	_test_blocked_slots_are_unusable()
	_test_tag_bonus_rewards_matching_modules()
	_test_agent_scope_rule_adds_work()
	_test_cooling_modules_take_heat_off_the_rig()
	_test_circuit_breaker_sheds_once_the_rig_is_hot()
	_test_thermal_paste_leaves_cooling_alone()
	_test_burn_applies_to_the_job()
	_test_a_contract_takes_a_handful_of_burns()
	_test_shipping_early_pays_less()
	_test_boost_reaches_the_batch_it_was_armed_for()
	_test_a_queued_boost_reaches_the_rounds_first_prompt()
	_test_cloud_burst_is_only_rented()
	_test_heat_throttle_reaches_the_next_prompt()
	_test_a_run_opens_with_a_full_working_pipeline()
	_test_a_drafted_module_lands_on_the_bench()
	_test_widening_the_board_keeps_what_was_placed()
	_test_workflows_start_at_one_and_are_capacity_gated()
	_test_an_old_save_keeps_its_layout_as_the_first_workflow()
	_test_a_contract_burns_through_the_workflow_it_was_assigned()
	_test_deleting_a_workflow_rehomes_its_contracts()
	_test_a_met_demand_pays_and_an_ignored_one_hurts()
	_test_a_contract_with_no_demands_is_judged_on_the_pipeline_alone()
	_test_a_combo_pays_more_than_the_same_modules_apart()


# --- Harness -----------------------------------------------------------------

class Harness:
	extends RefCounted

	var board := BoardSystem.new()
	var resolver := EffectResolver.new()
	var state := RunState.new()
	var rng: DeterministicRng
	var job: Dictionary

	func _init(seed_value: int = 1234) -> void:
		rng = DeterministicRng.new(seed_value)
		board.ensure_board(state, ContentDatabase)
		job = {
			"id": "job.test",
			"name": "Test Contract",
			"token_requirement": 10000.0,
			"tokens_remaining": 10000.0,
			"quality": 0.0,
			"quality_threshold": 60.0,
			"known_bugs": 0,
			"hidden_bugs": 0,
			"blocked_slots": 0,
			"board_rules": [],
			"tags": [],
		}

	func own(operation_ids: Array) -> void:
		var owned: Array = board.owned_operations(state)
		for id in operation_ids:
			if not (str(id) in owned):
				owned.append(str(id))
		state.build["operations"] = owned

	## Sets the pipeline directly; placement rules are covered separately.
	func pipeline(operation_ids: Array) -> void:
		own(operation_ids)
		var slots: Array = board.slots(state)
		for i in range(slots.size()):
			slots[i] = str(operation_ids[i]) if i < operation_ids.size() else ""

	func burn(subscriptions: Array = [], stage_limit: int = -1, tokens: float = 1000.0) -> Dictionary:
		return board.resolve_burn(state, job, tokens, rng, resolver, subscriptions, stage_limit)


# --- Content -----------------------------------------------------------------

## Every module has to be able to take part in a burn without erroring or
## producing a batch of nothing.
func _test_every_operation_resolves() -> void:
	assert_true(ContentDatabase.operations.size() >= 8, "There are at least eight modules to draft")
	for operation in ContentDatabase.operations:
		var harness := Harness.new(11)
		harness.pipeline(["op.prompt", operation.id])
		var result: Dictionary = harness.burn()
		assert_true(result.get("ok", false), "%s resolves in a pipeline" % operation.id)
		assert_true(
			float(result.get("progress_tokens", 0.0)) > 0.0,
			"%s leaves the batch doing some work" % operation.id
		)


func _test_empty_pipeline_refuses_to_burn() -> void:
	var harness := Harness.new(12)
	harness.pipeline([])
	var result: Dictionary = harness.burn()
	assert_false(result.get("ok", true), "An empty board cannot burn")
	assert_true(str(result.get("reason", "")) != "", "And says why")


# --- Order semantics ---------------------------------------------------------

## The headline promise of the board. Cache-then-model discounts the model;
## model-then-cache does not.
func _test_order_matters() -> void:
	var cache_first := Harness.new(21)
	cache_first.pipeline(["op.token_cache", "op.premium_model"])
	var discounted: Dictionary = cache_first.burn()

	var model_first := Harness.new(21)
	model_first.pipeline(["op.premium_model", "op.token_cache"])
	var full_price: Dictionary = model_first.burn()

	assert_true(
		float(discounted.get("cost", 0.0)) < float(full_price.get("cost", 0.0)),
		"A cache above the model discounts it (%.0f vs %.0f)" % [
			float(discounted.get("cost", 0.0)),
			float(full_price.get("cost", 0.0)),
		]
	)


func _test_cache_is_positional() -> void:
	var last := Harness.new(22)
	last.pipeline(["op.prompt", "op.token_cache"])
	var banked: Dictionary = last.burn()

	var middle := Harness.new(22)
	middle.pipeline(["op.token_cache", "op.prompt"])
	var passthrough: Dictionary = middle.burn()

	assert_true(
		float(banked.get("quality", 0.0)) > float(passthrough.get("quality", 0.0)),
		"A cache in the last slot banks quality instead of discounting"
	)


func _test_agent_repeats_the_stage_above() -> void:
	var with_agent := Harness.new(23)
	with_agent.pipeline(["op.cheap_model", "op.agent_swarm"])
	var repeated: Dictionary = with_agent.burn()

	var alone := Harness.new(23)
	alone.pipeline(["op.cheap_model"])
	var single: Dictionary = alone.burn()

	assert_true(
		float(repeated.get("progress_mult", 1.0)) > float(single.get("progress_mult", 1.0)),
		"The swarm re-runs the model above it"
	)
	assert_true(
		int(repeated.get("bugs_added", 0)) > int(single.get("bugs_added", 0)),
		"Including the model's bugs"
	)
	assert_true(float(repeated.get("heat", 0.0)) > 0.0, "And it runs hot")


# --- Bugs --------------------------------------------------------------------

func _test_ship_it_hides_its_bugs() -> void:
	var honest := Harness.new(31)
	honest.pipeline(["op.prompt", "op.cheap_model"])
	var known: Dictionary = honest.burn()
	assert_true(int(known.get("bugs_added", 0)) > 0, "A cheap model writes bugs you can see")

	var reckless := Harness.new(31)
	reckless.pipeline(["op.prompt", "op.ship_it", "op.cheap_model"])
	var hidden: Dictionary = reckless.burn()
	assert_eq(int(hidden.get("bugs_added", 0)), 0, "Ship It books no known bugs")
	assert_true(int(hidden.get("hidden_added", 0)) > 0, "It buries them instead")
	assert_true(
		float(hidden.get("quality_converted", 0.0)) > 0.0,
		"And spends the batch's quality on progress instead"
	)
	assert_true(
		float(hidden.get("quality", 0.0)) < float(known.get("quality", 0.0)),
		"Which is quality the contract never receives"
	)


func _test_tests_reveal_and_fix() -> void:
	var harness := Harness.new(32)
	harness.job["hidden_bugs"] = 3
	harness.job["known_bugs"] = 0
	harness.pipeline(["op.unit_tests"])
	var result: Dictionary = harness.burn()
	assert_true(int(result.get("revealed", 0)) > 0, "Testing surfaces hidden bugs")
	assert_true(int(result.get("fixed", 0)) > 0, "And fixes what it finds")
	assert_true(
		int(result.get("hidden_bugs", 99)) < 3,
		"Leaving fewer landmines than it started with"
	)


# --- Preview and interruption ------------------------------------------------

## The forecast on the screen is the same resolution the commit uses, so the
## player is never shown a number the burn then contradicts.
func _test_burn_is_deterministic() -> void:
	var first := Harness.new(41)
	first.pipeline(STARTER_PIPELINE)
	var preview: Dictionary = first.burn()

	var second := Harness.new(41)
	second.pipeline(STARTER_PIPELINE)
	var commit: Dictionary = second.burn()

	assert_almost_eq(
		float(preview.get("progress_tokens", 0.0)),
		float(commit.get("progress_tokens", 0.0)),
		0.0001,
		"The same seed and board resolve identically"
	)
	assert_eq(int(preview.get("bugs_added", 0)), int(commit.get("bugs_added", 0)), "Bugs included")


func _test_kill_process_keeps_finished_stages() -> void:
	var harness := Harness.new(42)
	harness.pipeline(["op.prompt", "op.cheap_model", "op.overclock"])
	var full: Dictionary = harness.burn()
	var killed: Dictionary = harness.burn([], 1)

	assert_eq(int(killed.get("stage_count", 0)), 1, "Killing after one stage resolves one stage")
	assert_true(killed.get("truncated", false), "The batch is marked as cut short")
	assert_eq(int(killed.get("bugs_added", 0)), 0, "The model never ran, so it wrote no bugs")
	assert_true(
		float(killed.get("progress_tokens", 0.0)) < float(full.get("progress_tokens", 0.0)),
		"A killed batch produces less than a finished one"
	)
	assert_true(float(killed.get("progress_tokens", 0.0)) > 0.0, "But the stages that ran still count")


# --- Job constraints ---------------------------------------------------------

func _test_blocked_slots_are_unusable() -> void:
	var harness := Harness.new(51)
	harness.pipeline(["", "", "", "", ""])
	harness.own(["op.prompt"])
	harness.job["blocked_slots"] = 2

	assert_false(
		harness.board.place_operation(harness.state, harness.job, "op.prompt", 0),
		"A contract's own slot cannot be overwritten"
	)
	assert_true(
		harness.board.place_operation(harness.state, harness.job, "op.prompt", 2),
		"The free slots below it still work"
	)
	# Anything already sitting in a blocked slot is ignored by resolution.
	harness.board.slots(harness.state)[0] = "op.overclock"
	var result: Dictionary = harness.burn()
	assert_eq(int(result.get("stage_count", 0)), 1, "Only the reachable slot burns")


func _test_tag_bonus_rewards_matching_modules() -> void:
	var plain := Harness.new(52)
	plain.pipeline(["op.prompt"])
	var baseline: Dictionary = plain.burn()

	var bonused := Harness.new(52)
	bonused.pipeline(["op.prompt"])
	bonused.job["board_rules"] = [{
		"type": BoardSystem.RULE_TAG_BONUS,
		"tag": "prompt",
		"value": 2.0,
		"label": "Prompts count double here.",
	}]
	var boosted: Dictionary = bonused.burn()

	assert_true(
		float(boosted.get("progress_mult", 1.0)) > float(baseline.get("progress_mult", 1.0)),
		"A matching tag is worth more on this contract"
	)


func _test_agent_scope_rule_adds_work() -> void:
	var harness := Harness.new(53)
	harness.pipeline(["op.prompt", "op.agent_swarm"])
	harness.job["board_rules"] = [{
		"type": BoardSystem.RULE_AGENT_SCOPE,
		"value": 0.1,
		"label": "Agents invent requirements on this contract.",
	}]
	var result: Dictionary = harness.burn()
	assert_true(float(result.get("scope_tokens", 0.0)) > 0.0, "Running an agent grows the contract")
	assert_true(Array(result.get("messages", [])).size() > 0, "And the player is told why")


# --- Cooling -----------------------------------------------------------------

## A pipeline built around a cooler is meant to take heat back off the rig. The
## batch total used to be clamped at zero, so those modules did nothing at all
## once the rig was already hot — which is exactly when they are placed.
func _test_cooling_modules_take_heat_off_the_rig() -> void:
	var harness := Harness.new(61)
	harness.pipeline(["op.prompt", "op.liquid_cooling"])
	var result: Dictionary = harness.burn()
	assert_true(
		float(result.get("heat", 0.0)) < 0.0,
		"A pipeline that only cools reports negative heat (%.1f)" % float(result.get("heat", 0.0))
	)

	var job_system := JobSystem.new()
	var heat_system := HeatSystem.new()
	var economy_system := EconomySystem.new()
	harness.state.compute["heat"] = 40.0
	harness.state.business["active_jobs"] = [harness.job]
	var messages: Array[String] = []
	job_system._apply_burn(
		harness.state, harness.job, result, harness.rng, messages, ResolveMode.PREVIEW,
		heat_system, economy_system, harness.resolver, []
	)
	assert_true(
		float(harness.state.compute.get("heat", 0.0)) < 40.0,
		"And that lands on the rig as a reduction"
	)

	harness.state.compute["heat"] = 2.0
	job_system._apply_burn(
		harness.state, harness.job, result, harness.rng, messages, ResolveMode.PREVIEW,
		heat_system, economy_system, harness.resolver, []
	)
	assert_true(
		float(harness.state.compute.get("heat", 0.0)) >= 0.0,
		"Stored heat still cannot go negative"
	)


## The breaker's whole conditional half is the shed. Below the trip line it
## boosts progress; at or above it, it has to actually cool.
func _test_circuit_breaker_sheds_once_the_rig_is_hot() -> void:
	var hot := Harness.new(62)
	hot.pipeline(["op.circuit_breaker"])
	hot.state.compute["heat_capacity"] = 100.0
	hot.state.compute["heat"] = 90.0
	var tripped: Dictionary = hot.burn()
	assert_true(
		float(tripped.get("heat", 0.0)) < 0.0,
		"A tripped breaker sheds heat rather than doing nothing"
	)

	var cool := Harness.new(62)
	cool.pipeline(["op.circuit_breaker"])
	cool.state.compute["heat_capacity"] = 100.0
	cool.state.compute["heat"] = 10.0
	var boosting: Dictionary = cool.burn()
	assert_almost_eq(
		float(boosting.get("heat", 0.0)), 0.0, 0.0001,
		"A cool rig gets the progress bonus instead of the shed"
	)
	assert_true(
		float(boosting.get("progress_mult", 1.0)) > 1.0,
		"Which is the bonus it advertises"
	)


## "Stages run cooler" must not mean "your coolers are worse at cooling".
func _test_thermal_paste_leaves_cooling_alone() -> void:
	var paste: Array = _perk_subscriptions("perk.thermal_paste")
	assert_true(paste.size() > 0, "Thermal Paste subscribes to the board")

	var cooled := Harness.new(63)
	cooled.pipeline(["op.liquid_cooling"])
	var without: Dictionary = cooled.burn()

	var pasted := Harness.new(63)
	pasted.pipeline(["op.liquid_cooling"])
	var with_paste: Dictionary = pasted.burn(paste)
	assert_almost_eq(
		float(with_paste.get("heat", 0.0)), float(without.get("heat", 0.0)), 0.0001,
		"Thermal Paste does not shrink a cooling stage"
	)

	var hot := Harness.new(63)
	hot.pipeline(["op.overclock"])
	var full_heat: Dictionary = hot.burn()

	var damped := Harness.new(63)
	damped.pipeline(["op.overclock"])
	var reduced: Dictionary = damped.burn(paste)
	assert_true(
		float(reduced.get("heat", 0.0)) < float(full_heat.get("heat", 0.0)),
		"But it still cools a stage that makes heat"
	)


func _perk_subscriptions(perk_id: String) -> Array:
	var perk := ContentDatabase.get_perk(perk_id)
	if perk == null:
		return []
	var subs: Array = []
	for sub in perk.subscriptions:
		var copy: Dictionary = sub.duplicate(true)
		copy["source_id"] = perk.id
		copy["parameters"] = perk.parameters.duplicate(true)
		subs.append(copy)
	return subs


# --- Integration -------------------------------------------------------------

func _test_burn_applies_to_the_job() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(2201)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(offers.size() > 0, "Offers available for the board test")
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work()

	var before: Dictionary = sim.focused_job()
	assert_false(before.is_empty(), "Starting work focuses a contract")
	assert_true(sim.can_burn(), "A starter board can burn")
	var remaining_before: float = float(before.get("tokens_remaining", 0.0))
	var prompt_before: int = int(sim.run_state.calendar.get("prompt", 0))
	var preview: Dictionary = sim.preview_burn()
	assert_true(preview.get("ok", false), "The board previews the burn")

	sim.burn_batch()
	var after: Dictionary = sim.focused_job()
	if after.is_empty():
		# One burn finished it outright, which is a legitimate outcome.
		assert_true(true, "The contract completed on the first burn")
	else:
		assert_true(
			float(after.get("tokens_remaining", 0.0)) < remaining_before,
			"A burn moves the contract forward"
		)
		assert_true(float(after.get("quality", 0.0)) > 0.0, "And earns quality")
		assert_eq(
			int(sim.run_state.calendar.get("prompt", 0)),
			prompt_before + 1,
			"A burn spends a prompt"
		)
	assert_false(sim.preview_burn().has("__committed"), "Previewing does not write to the run")
	sim.free()


## Pacing target for V1: a contract should be a handful of deliberate burns, not
## one click and not a grind.
func _test_a_contract_takes_a_handful_of_burns() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(2202)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work()
	var job: Dictionary = sim.focused_job()
	var requirement: float = float(job.get("token_requirement", 0.0))
	var preview: Dictionary = sim.preview_burn()
	var per_burn: float = maxf(1.0, float(preview.get("progress_tokens", 0.0)))
	var burns: float = requirement / per_burn
	assert_true(
		burns >= 1.5 and burns <= 8.0,
		"A first contract is %.1f burns of work on a starter board" % burns
	)
	assert_true(
		int(job.get("deadline_prompts", 0)) >= int(ceil(burns)),
		"And its deadline leaves room for them"
	)
	sim.free()


func _test_shipping_early_pays_less() -> void:
	var jobs := JobSystem.new()
	var state := RunState.new()
	var full: Dictionary = {
		"token_requirement": 1000.0,
		"tokens_remaining": 0.0,
		"quality": 100.0,
		"quality_threshold": 50.0,
		"known_bugs": 0,
		"hidden_bugs": 0,
	}
	var partial: Dictionary = full.duplicate(true)
	partial["tokens_remaining"] = 400.0
	partial["shipped_unfinished"] = true
	partial["shipped_progress"] = 0.6
	var buggy: Dictionary = full.duplicate(true)
	buggy["known_bugs"] = 3

	var messages: Array[String] = []
	var full_penalty: float = jobs._delivery_penalty(state, full, DeterministicRng.new(1), messages)
	var partial_penalty: float = jobs._delivery_penalty(state, partial, DeterministicRng.new(1), messages)
	var buggy_penalty: float = jobs._delivery_penalty(state, buggy, DeterministicRng.new(1), messages)
	assert_true(partial_penalty < full_penalty, "Shipping at 60% pays less than finishing")
	assert_true(buggy_penalty < full_penalty, "Known bugs cost you at delivery")
	assert_true(partial_penalty > 0.0, "But an early ship still pays something")


## A one-round modifier used to be aged out at the start of the round it was
## meant to affect, which made BOOST a button that only produced heat.
func _test_boost_reaches_the_batch_it_was_armed_for() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(2301)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work()

	var plain: Dictionary = sim.preview_burn()
	assert_false(sim.boost_engaged(), "Nothing is boosted to begin with")
	assert_true(sim.boost(), "BOOST can be engaged during a session")
	assert_true(sim.boost_engaged(), "And the board can see that it is armed")
	var boosted: Dictionary = sim.preview_burn()
	assert_true(
		float(boosted.get("tokens", 0.0)) > float(plain.get("tokens", 0.0)),
		"The armed boost is in the batch the player is about to burn (%s vs %s)" % [
			NumberFormat.format(float(boosted.get("tokens", 0.0))),
			NumberFormat.format(float(plain.get("tokens", 0.0))),
		]
	)
	assert_false(sim.boost(), "It cannot be double-engaged in one round")

	sim.burn_batch()
	assert_false(sim.boost_engaged(), "And it is spent once the batch has run")
	sim.free()


## The first BURN of a round is what opens the session, so the only way to
## boost the first prompt is to arm it beforehand. The queued surge must be
## live when that first batch resolves, not aged out by the session opening.
func _test_a_queued_boost_reaches_the_rounds_first_prompt() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(2304)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	sim.set_queued_boost(true)
	assert_true(sim.queued_boost, "BOOST can be armed before the session opens")
	sim.start_work()
	assert_true(
		sim.boost_engaged(),
		"Opening the session fires the queued boost, in time for the first prompt"
	)
	sim.burn_batch()
	assert_false(sim.boost_engaged(), "And it is spent with that first batch")
	sim.free()


## Rented capacity has to go back, or the button is a permanent free upgrade.
func _test_cloud_burst_is_only_rented() -> void:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(2302)
	# Bursting is a capability the run buys before it can be used at all.
	sim.run_state.build["upgrades"].append(Simulation.CLOUD_ACCOUNT_UPGRADE)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work()
	var cash_before: float = float(sim.run_state.economy.get("cash", 0.0))
	var owned_before: float = float(sim.run_state.compute.get("cloud_capacity", 0.0))

	assert_true(sim.cloud_burst(), "Capacity can be rented during a session")
	assert_true(float(sim.run_state.compute.get("cloud_burst", 0.0)) > 0.0, "The lease is recorded")
	assert_almost_eq(
		float(sim.run_state.compute.get("cloud_capacity", 0.0)),
		owned_before,
		0.01,
		"Renting does not add to the capacity the player owns"
	)
	assert_true(
		float(sim.run_state.economy.get("cash", 0.0)) < cash_before,
		"Cash is deducted immediately"
	)

	sim.burn_batch()
	assert_almost_eq(
		float(sim.run_state.compute.get("cloud_burst", 0.0)),
		0.0,
		0.01,
		"The lease ends with the prompt it was rented for"
	)
	assert_false(sim.cloud_engaged(), "So the next prompt starts on the player's own rig")
	sim.free()


## Throttling was being expired before it could slow anything down.
func _test_heat_throttle_reaches_the_next_prompt() -> void:
	var state := RunState.new()
	var heat := HeatSystem.new()
	var resolver := EffectResolver.new()
	var rng := DeterministicRng.new(3)
	state.compute["heat"] = 95.0
	heat.process_prompt(state, [], resolver, rng)
	var modifiers: Array = state.compute.get("rate_modifiers", [])
	var throttled: bool = false
	for entry in modifiers:
		if entry is Dictionary and str(entry.get("source", "")) == "heat_throttle":
			throttled = true
	assert_true(throttled, "Running hot registers a throttle")

	var compute := ComputeSystem.new()
	compute.recalculate(state, resolver, [], rng)
	var throttled_rate: float = float(state.compute.get("token_rate", 0.0))
	state.tick_rate_modifiers()
	compute.recalculate(state, resolver, [], rng)
	assert_true(
		float(state.compute.get("token_rate", 0.0)) > throttled_rate,
		"The throttle costs throughput while it lasts, and lifts when it expires"
	)


## A run opens on a working pipeline with nothing benched: a first-round bench
## of modules that cannot be placed reads as a broken board rather than as a
## decision. Room becomes scarce as modules are drafted, not before.
func _test_a_run_opens_with_a_full_working_pipeline() -> void:
	var state := RunState.new()
	var board := BoardSystem.new()
	board.ensure_board(state, ContentDatabase)
	var owned: Array = board.owned_operations(state)
	var slots: Array = board.slots(state)
	assert_eq(
		owned.size(), slots.size(),
		"A fresh run owns exactly the modules it can place (%d)" % owned.size()
	)
	assert_eq(board.filled_slot_count(state), slots.size(), "And it opens with every slot working")
	for op_id in STARTER_PIPELINE:
		assert_true(str(op_id) in slots, "The opening pipeline includes %s" % op_id)


## Drafting on a full board is a decision, not a free win: the module has to wait
## until the player takes something out.
func _test_a_drafted_module_lands_on_the_bench() -> void:
	var state := RunState.new()
	var board := BoardSystem.new()
	board.ensure_board(state, ContentDatabase)
	var slots_before: Array = board.slots(state).duplicate()

	assert_true(board.grant_operation(state, "op.linter"), "A drafted module is owned")
	assert_true("op.linter" in board.owned_operations(state), "It shows up in the tray")
	assert_false("op.linter" in board.slots(state), "But not in the pipeline, which was full")
	assert_eq(board.slots(state), slots_before, "And nothing already placed was displaced")


## An unlocked or bought slot is only worth having if it arrives empty and leaves
## the existing pipeline alone.
func _test_widening_the_board_keeps_what_was_placed() -> void:
	var state := RunState.new()
	var board := BoardSystem.new()
	board.ensure_board(state, ContentDatabase)
	var slots_before: Array = board.slots(state).duplicate()

	state.build["board"]["meta_slot_bonus"] = int(state.build["board"].get("meta_slot_bonus", 0)) + 1
	board.ensure_board(state, ContentDatabase)
	var slots_after: Array = board.slots(state)
	assert_eq(slots_after.size(), slots_before.size() + 1, "The board is one slot wider")
	for index in range(slots_before.size()):
		assert_eq(str(slots_after[index]), str(slots_before[index]), "Placed modules stayed put")
	assert_eq(str(slots_after[slots_after.size() - 1]), "", "And the new slot is empty to fill")


# --- Workflows ---------------------------------------------------------------

## A run opens with one way of working. A second is earned, not assumed, so
## capacity is what gates the list rather than the player's patience.
func _test_workflows_start_at_one_and_are_capacity_gated() -> void:
	var state := RunState.new()
	var board := BoardSystem.new()
	board.ensure_board(state, ContentDatabase)
	assert_eq(board.workflow_count(state), 1, "A fresh run has exactly one workflow")
	assert_true(board.create_workflow(state).is_empty(), "A second one needs capacity first")

	state.build["meta_workflow_bonus"] = 1
	var created: Dictionary = board.create_workflow(state, "The Careful One", ContentDatabase)
	assert_false(created.is_empty(), "With capacity the second workflow is created")
	assert_eq(board.workflow_count(state), 2, "And the run now owns two")
	assert_eq(str(created.get("name", "")), "The Careful One", "Named as asked")
	assert_eq(
		Array(created.get("slots", [])), Array(board.workflow_at(state, 0).get("slots", [])),
		"Seeded from the workflow that was on screen, so it starts from something that works"
	)
	assert_true(board.create_workflow(state).is_empty(), "A third is refused at capacity 2")


## A save from before workflows existed has to open on the pipeline it was left
## on, not on an empty board.
func _test_an_old_save_keeps_its_layout_as_the_first_workflow() -> void:
	var state := RunState.new()
	state.build["operations"] = ["op.prompt", "op.unit_tests"]
	state.build["board"] = {
		"slot_count": 3,
		"slots": ["op.unit_tests", "", "op.prompt"],
	}
	state.build.erase("workflows")
	var board := BoardSystem.new()
	board.ensure_board(state, ContentDatabase)

	assert_eq(board.workflow_count(state), 1, "The old layout became one workflow")
	assert_eq(
		board.slots(state), ["op.unit_tests", "", "op.prompt"],
		"With every module exactly where the player left it"
	)
	assert_false(state.build["board"].has("slots"), "And the old key is gone")


## The point of the whole system: two contracts worked in the same run go
## through the pipelines they were each assigned.
func _test_a_contract_burns_through_the_workflow_it_was_assigned() -> void:
	var harness := Harness.new(4101)
	harness.state.build["workflow_capacity"] = 2
	harness.own(["op.prompt", "op.premium_model", "op.cheap_model"])
	var first: Dictionary = harness.board.workflow_at(harness.state, 0)
	first["slots"] = ["op.prompt", "op.cheap_model", ""]
	var second: Dictionary = harness.board.create_workflow(harness.state, "Expensive")
	second["slots"] = ["op.prompt", "op.premium_model", ""]

	harness.job["workflow_id"] = str(first.get("id", ""))
	var cheap: Dictionary = harness.burn()
	harness.job["workflow_id"] = str(second.get("id", ""))
	var expensive: Dictionary = harness.burn()

	assert_eq(str(cheap.get("workflow_name", "")), str(first.get("name", "")), "The first burn names its workflow")
	assert_eq(str(expensive.get("workflow_name", "")), "Expensive", "And the second names the other one")
	assert_true(
		float(expensive.get("cost", 0.0)) > float(cheap.get("cost", 0.0)),
		"The assignment decides what the contract costs to work (%.0f vs %.0f)" % [
			float(expensive.get("cost", 0.0)), float(cheap.get("cost", 0.0)),
		]
	)


## Deleting a pipeline must not leave a contract pointing at nothing.
func _test_deleting_a_workflow_rehomes_its_contracts() -> void:
	var state := RunState.new()
	var board := BoardSystem.new()
	board.ensure_board(state, ContentDatabase)
	state.build["meta_workflow_bonus"] = 1
	var second: Dictionary = board.create_workflow(state, "", ContentDatabase)
	var job: Dictionary = {"id": "job.test", "workflow_id": str(second.get("id", ""))}
	state.business["active_jobs"] = [job]

	assert_true(board.delete_workflow(state, 1), "The second workflow can go")
	assert_eq(board.workflow_count(state), 1, "Leaving one behind")
	assert_eq(
		str(job.get("workflow_id", "")), str(board.workflow_at(state, 0).get("id", "")),
		"And the contract it was working moved to the one that is left"
	)
	assert_false(board.delete_workflow(state, 0), "The last workflow cannot be deleted")


# --- Contract demands --------------------------------------------------------

## Soft correlation, with teeth: any workflow can run any contract, but a
## defect-prone job put through a pipeline that tests nothing is punished for it.
func _test_a_met_demand_pays_and_an_ignored_one_hurts() -> void:
	var tested := Harness.new(4202)
	tested.job["demands"] = ["demand.testing"]
	tested.pipeline(["op.prompt", "op.unit_tests"])
	var careful: Dictionary = tested.burn()

	var untested := Harness.new(4202)
	untested.job["demands"] = ["demand.testing"]
	untested.pipeline(["op.prompt", "op.cheap_model"])
	var reckless: Dictionary = untested.burn()

	assert_eq(Array(careful.get("demands", [])).size(), 1, "The contract's demand is reported")
	assert_true(bool(careful["demands"][0].get("met", false)), "Testing in the pipeline meets it")
	assert_false(bool(reckless["demands"][0].get("met", true)), "A pipeline with no tests does not")
	assert_true(
		float(reckless.get("bug_chance_mult", 1.0)) > float(careful.get("bug_chance_mult", 1.0)),
		"And skipping it makes defects likelier"
	)
	assert_true(
		int(reckless.get("hidden_bugs", 0)) > int(careful.get("hidden_bugs", 0)),
		"The ignored demand plants a defect of its own"
	)
	assert_true(
		Array(reckless.get("messages", [])).size() > 0,
		"The player is told why, rather than finding out at delivery"
	)


## A demand-free contract is unaffected either way, so the early game is not
## quietly taxed by a system it has not met yet.
func _test_a_contract_with_no_demands_is_judged_on_the_pipeline_alone() -> void:
	var harness := Harness.new(4203)
	harness.pipeline(["op.prompt", "op.cheap_model"])
	var result: Dictionary = harness.burn()
	assert_eq(Array(result.get("demands", [])).size(), 0, "Nothing is demanded")
	assert_eq(float(result.get("bug_chance_mult", 0.0)), 1.0, "And nothing is penalised")


# --- Module synergies --------------------------------------------------------

## Adjacency has to be worth building around, or position is just decoration.
func _test_a_combo_pays_more_than_the_same_modules_apart() -> void:
	var adjacent := Harness.new(4301)
	adjacent.pipeline(["op.cheap_model", "op.unit_tests"])
	var combined: Dictionary = adjacent.burn()

	var apart := Harness.new(4301)
	apart.pipeline(["op.unit_tests", "op.cheap_model"])
	var separate: Dictionary = apart.burn()

	var tests: OperationDefinition = ContentDatabase.get_operation("op.unit_tests")
	assert_eq(
		tests.active_combos("op.cheap_model", "").size(), 1,
		"Unit Tests declares a combo with the module above it"
	)
	assert_eq(
		tests.active_combos("op.prompt", "").size(), 0,
		"And not with a module it has nothing to do with"
	)
	assert_true(
		float(combined.get("quality", 0.0)) > float(separate.get("quality", 0.0)),
		"Testing what the stage above just wrote is worth more than the same two modules reversed (%.1f vs %.1f)" % [
			float(combined.get("quality", 0.0)), float(separate.get("quality", 0.0)),
		]
	)
