extends TestCase

## The builds the design leans on, played end to end.
##
## Every case here is a promise printed on a card: the perk or module fires on
## the burn the player is watching, at the strength the copy claims, and in the
## order the resolver documents. Each one covers an interaction that has been
## silently broken before — a subscription landing after the maths it was meant
## to change, a recursion floor overwriting a bigger echo, a payout reading a
## field nothing had written yet.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_bug_alchemy_changes_this_burn()
	_test_test_driven_changes_this_burns_tokens()
	_test_vibe_coding_synergy_lands_on_this_burn()
	_test_infinite_backlog_strengthens_only_real_echoes()
	_test_deja_vu_is_a_floor_not_an_override()
	_test_fractal_split_forks_twice()
	_test_known_unknowns_pays_per_shipped_bug()
	_test_audit_trail_needs_a_clean_ship()
	_test_technical_debt_lends_once_on_pickup()
	_test_a_free_stage_stays_free_when_echoed()
	_test_vibe_cannon_converts_then_rerolls()
	_test_warm_cache_doubles_the_discount()
	_test_caught_in_review_is_the_combo_not_a_slot_effect()
	_test_heat_gates_read_the_rig_not_the_burn()
	_test_bench_is_blocked_when_it_orphans_a_dependent()
	_test_owned_modules_steer_the_draft()
	_test_conditions_see_the_stage_before_effects_run()


# --- Harness -----------------------------------------------------------------

class Build:
	extends RefCounted

	var board := BoardSystem.new()
	var resolver := EffectResolver.new()
	var state := RunState.new()
	var perk_system := PerkSystem.new()
	var rng: DeterministicRng
	var job: Dictionary

	func _init(module_ids: Array, perk_ids: Array = [], seed_value: int = 7700) -> void:
		rng = DeterministicRng.new(seed_value)
		board.ensure_board(state, ContentDatabase)
		state.build["perks"] = []
		for perk_id in perk_ids:
			state.build["perks"].append(str(perk_id))
		state.build["modules"] = []
		for module_id in module_ids:
			state.build["modules"].append(str(module_id))
		var slots: Array = board.slots(state)
		for i in range(slots.size()):
			slots[i] = str(module_ids[i]) if i < module_ids.size() else ""
		job = {
			"id": "job.test",
			"name": "Test Contract",
			"reward": 1000.0,
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

	## Mirrors what Simulation feeds the resolver: equipped perks, completed
	## synergies, and any status effect a pickup has spawned.
	func subscriptions() -> Array:
		var subs: Array = []
		for perk_id in state.build["perks"]:
			var perk := ContentDatabase.get_perk(str(perk_id))
			if perk == null:
				continue
			for sub in perk.subscriptions:
				var copy: Dictionary = sub.duplicate(true)
				copy["source_id"] = perk.id
				copy["parameters"] = perk.parameters.duplicate(true)
				subs.append(copy)
		for synergy in perk_system.active_synergies(state, ContentDatabase):
			for sub in synergy.get("subscriptions", []):
				var copy: Dictionary = sub.duplicate(true)
				copy["source_id"] = "synergy.%s" % str(synergy.get("name", "set"))
				copy["parameters"] = synergy.get("parameters", {})
				subs.append(copy)
		for status in state.build["status_effects"]:
			for sub in status.get("subscriptions", []):
				var copy: Dictionary = sub.duplicate(true)
				copy["parameters"] = copy.get("parameters", status.get("parameters", {}))
				copy["source_id"] = copy.get("source_id", str(status.get("id", "status")))
				subs.append(copy)
		return subs

	func burn(tokens: float = 1000.0) -> Dictionary:
		return board.resolve_burn(state, job, tokens, rng, resolver, subscriptions(), -1)

	## The pickup half of a perk, which is where liabilities and loans live.
	func acquire(perk_id: String) -> void:
		var perk := ContentDatabase.get_perk(perk_id)
		if perk == null or PerkSystem.liability_taken(state, perk_id):
			return
		var subs: Array = []
		for sub in perk.subscriptions:
			if str(sub.get("event", "")) != "perk.acquired":
				continue
			var copy: Dictionary = sub.duplicate(true)
			copy["source_id"] = perk.id
			copy["parameters"] = perk.parameters.duplicate(true)
			subs.append(copy)
		if subs.is_empty():
			return
		PerkSystem.record_liability(state, perk_id)
		resolver.begin_action("perk.acquired.%s" % perk_id)
		var mod_ctx := ModifierContext.new("perk.acquired", state)
		mod_ctx.rng = rng.derive("perk.acquired")
		resolver.dispatch("perk.acquired", mod_ctx, subs)


func _stage_named(result: Dictionary, module_id: String) -> Dictionary:
	for stage in result.get("stages", []):
		if str(stage.get("module_id", "")) == module_id:
			return stage
	return {}


# --- Timing: batch_finalizing --------------------------------------------------

## Bug Alchemy converts known bugs into progress. On `batch_finished` the
## progress multiplier had already been spent, so the perk read as a no-op.
func _test_bug_alchemy_changes_this_burn() -> void:
	var pipeline := ["op.prompt", "op.stack_overflow"]
	var plain: Dictionary = Build.new(pipeline).burn()
	var alchemy: Dictionary = Build.new(pipeline, ["perk.bug_alchemy"]).burn()

	assert_true(
		int(plain.get("known_bugs", 0)) > 0,
		"The build under test actually produces bugs to convert"
	)
	assert_true(
		float(alchemy.get("progress_tokens", 0.0)) > float(plain.get("progress_tokens", 0.0)),
		"Bug Alchemy pays out on the burn it was equipped for (%.0f vs %.0f)" % [
			float(alchemy.get("progress_tokens", 0.0)), float(plain.get("progress_tokens", 0.0)),
		]
	)
	assert_true(
		int(alchemy.get("known_bugs", 0)) < int(plain.get("known_bugs", 0)),
		"And the bugs it converted are gone from the ledger"
	)


## Test-Driven feeds fixed bugs back into tokens, which is locked before
## `batch_finished` fires.
func _test_test_driven_changes_this_burns_tokens() -> void:
	var pipeline := ["op.stack_overflow", "op.unit_tests"]
	var plain: Dictionary = Build.new(pipeline).burn()
	var driven: Dictionary = Build.new(pipeline, ["perk.test_driven"]).burn()

	assert_true(int(plain.get("fixed", 0)) > 0, "The build fixes something to be paid for")
	assert_true(
		float(driven.get("tokens", 0.0)) > float(plain.get("tokens", 0.0)),
		"Every fix feeds this batch more tokens (%.0f vs %.0f)" % [
			float(driven.get("tokens", 0.0)), float(plain.get("tokens", 0.0)),
		]
	)


## A completed set has to pay out on the burn as well, or the build screen is
## congratulating the player on nothing.
func _test_vibe_coding_synergy_lands_on_this_burn() -> void:
	var pipeline := ["op.prompt", "op.stack_overflow"]
	var pair := ["perk.vibe_check", "perk.bug_alchemy"]
	var one: Dictionary = Build.new(pipeline, ["perk.bug_alchemy"]).burn()
	var both: Dictionary = Build.new(pipeline, pair).burn()

	var synergy_names: Array = []
	for synergy in Build.new(pipeline, pair).perk_system.active_synergies(
		Build.new(pipeline, pair).state, ContentDatabase
	):
		synergy_names.append(str(synergy.get("name", "")))
	assert_true("Vibe Coding" in synergy_names, "Vibe Check plus Bug Alchemy completes Vibe Coding")
	assert_true(
		float(both.get("progress_mult", 1.0)) > float(one.get("progress_mult", 1.0)),
		"And the set multiplies this batch's progress (×%.2f vs ×%.2f)" % [
			float(both.get("progress_mult", 1.0)), float(one.get("progress_mult", 1.0)),
		]
	)


# --- Recursion ---------------------------------------------------------------

## Conditions are matched against a fresh stage, so Infinite Backlog cannot ask
## whether the stage repeats. `multiply` of nothing is still nothing, which is
## what keeps it honest on a stage that does not echo.
func _test_infinite_backlog_strengthens_only_real_echoes() -> void:
	var echoing := ["op.prompt", "op.agent_swarm"]
	var plain: Dictionary = Build.new(echoing).burn()
	var boosted: Dictionary = Build.new(echoing, ["perk.infinite_backlog"]).burn()
	var swarm_plain: Dictionary = _stage_named(plain, "op.agent_swarm")
	var swarm_boosted: Dictionary = _stage_named(boosted, "op.agent_swarm")

	assert_almost_eq(
		float(swarm_plain.get("repeated_previous", 0.0)), 1.0, 0.001,
		"Agent Swarm repeats the stage above at full strength"
	)
	assert_almost_eq(
		float(swarm_boosted.get("repeated_previous", 0.0)), 1.6, 0.001,
		"Infinite Backlog runs that echo at 1.6×"
	)

	var flat: Dictionary = Build.new(["op.prompt", "op.cheap_model"], ["perk.infinite_backlog"]).burn()
	assert_almost_eq(
		float(_stage_named(flat, "op.cheap_model").get("repeated_previous", 1.0)), 0.0, 0.001,
		"A pipeline with nothing to repeat is left alone"
	)


## `cap_min` is a floor: it lands after the adds, so it may not overwrite the
## bigger echo a recursion build paid for.
func _test_deja_vu_is_a_floor_not_an_override() -> void:
	var quiet: Dictionary = Build.new(["op.prompt", "op.cheap_model"], ["perk.stage_deja_vu"]).burn()
	assert_almost_eq(
		float(_stage_named(quiet, "op.cheap_model").get("repeated_previous", 0.0)), 0.35, 0.001,
		"Every stage echoes the one above at the 35% floor"
	)

	var loud: Dictionary = Build.new(
		["op.rubber_duck", "op.agent_swarm"], ["perk.stage_deja_vu"]
	).burn()
	assert_almost_eq(
		float(_stage_named(loud, "op.agent_swarm").get("repeated_previous", 0.0)), 1.0, 0.001,
		"And a full-strength echo is never floored back down to 35%"
	)


## Two 55% forks, not one 110% fold.
func _test_fractal_split_forks_twice() -> void:
	var result: Dictionary = Build.new(["op.foundation_model", "op.fractal_split"]).burn()
	var split: Dictionary = _stage_named(result, "op.fractal_split")

	assert_almost_eq(
		float(split.get("repeated_previous", 0.0)), 0.55, 0.001, "Each fork runs at 55% strength"
	)
	assert_eq(int(split.get("repeat_count", 0)), 2, "And there are two of them")

	# The forks are folds of the stage above, so the quality they contribute is
	# twice 55% of Foundation Model's own.
	var foundation: ModuleDefinition = ContentDatabase.get_module("op.foundation_model")
	var per_fork: float = float(foundation.parameters.get("quality", 0.0)) * 0.55
	var forked_quality: float = (
		float(split.get("after", {}).get("quality", 0.0))
		- float(split.get("before", {}).get("quality", 0.0))
	)
	assert_almost_eq(
		forked_quality, per_fork * 2.0, 0.01, "Both forks fold the stage above into the batch"
	)


# --- Delivery ----------------------------------------------------------------

func _reward(job: Dictionary, perk_ids: Array, state: RunState) -> float:
	var subs: Array = []
	for perk_id in perk_ids:
		var perk := ContentDatabase.get_perk(str(perk_id))
		if perk == null:
			continue
		for sub in perk.subscriptions:
			var copy: Dictionary = sub.duplicate(true)
			copy["source_id"] = perk.id
			copy["parameters"] = perk.parameters.duplicate(true)
			subs.append(copy)
	var messages: Array[String] = []
	return JobSystem.new()._calculate_reward(
		state, job, EffectResolver.new(), subs, {}, EconomySystem.new(),
		messages, false, DeterministicRng.new(31)
	)


## Hidden-bug discovery is settled before `reward.calculated`, so the perk is
## paid on the delivery that actually happened.
func _test_known_unknowns_pays_per_shipped_bug() -> void:
	var state := RunState.new()
	var cash_before: float = float(state.economy.get("cash", 0.0))
	var job: Dictionary = {
		"id": "job.shipped_bugs",
		"name": "Shipped Bugs",
		"reward": 1000.0,
		"quality": 100.0,
		"quality_threshold": 0.0,
		"tokens_remaining": 0.0,
		"known_bugs": 0,
		"hidden_bugs": 4,
		"hidden_bugs_discovered": 0,
		"hidden_bugs_shipped": 4,
	}
	_reward(job, ["perk.known_unknowns"], state)
	var payout: float = float(ContentDatabase.get_perk("perk.known_unknowns").parameters.get("payout", 0.0))
	assert_almost_eq(
		float(state.economy.get("cash", 0.0)) - cash_before, payout * 4.0, 0.01,
		"Every hidden bug that shipped undetected pays out"
	)


## "No bugs at all" has to mean none of either kind.
func _test_audit_trail_needs_a_clean_ship() -> void:
	var multiplier: float = float(
		ContentDatabase.get_perk("perk.audit_trail").parameters.get("multiplier", 1.0)
	)
	var clean: Dictionary = {
		"id": "job.clean", "name": "Clean", "reward": 1000.0, "quality": 100.0,
		"quality_threshold": 0.0, "tokens_remaining": 0.0, "known_bugs": 0, "hidden_bugs": 0,
		"hidden_bugs_discovered": 0, "hidden_bugs_shipped": 0,
	}
	var known: Dictionary = clean.duplicate(true)
	known["id"] = "job.known"
	known["known_bugs"] = 2
	var hidden: Dictionary = clean.duplicate(true)
	hidden["id"] = "job.hidden"
	hidden["hidden_bugs"] = 2
	hidden["hidden_bugs_shipped"] = 2

	# Fresh copies each time: settling a delivery writes back to the contract.
	var baseline: float = _reward(clean.duplicate(true), [], RunState.new())
	var clean_paid: float = _reward(clean.duplicate(true), ["perk.audit_trail"], RunState.new())
	assert_almost_eq(
		clean_paid, baseline * multiplier, 0.01, "A spotless delivery pays the bonus"
	)
	var known_baseline: float = _reward(known.duplicate(true), [], RunState.new())
	var known_paid: float = _reward(known.duplicate(true), ["perk.audit_trail"], RunState.new())
	assert_almost_eq(
		known_paid, known_baseline, 0.01, "Visible bugs disqualify it, not just hidden ones"
	)
	var hidden_baseline: float = _reward(hidden.duplicate(true), [], RunState.new())
	var hidden_paid: float = _reward(hidden.duplicate(true), ["perk.audit_trail"], RunState.new())
	assert_almost_eq(
		hidden_paid, hidden_baseline, 0.01, "And so do the ones nobody found"
	)


## The loan is a pickup effect and the liability is permanent, so neither is
## allowed to depend on the perk still being equipped.
func _test_technical_debt_lends_once_on_pickup() -> void:
	var build := Build.new(["op.prompt"], [])
	build.state.economy["round_rent"] = 100.0
	var cash_before: float = float(build.state.economy.get("cash", 0.0))

	build.acquire("perk.technical_debt")
	var lent: float = float(build.state.economy.get("cash", 0.0)) - cash_before
	var rent_multiple: float = float(
		ContentDatabase.get_perk("perk.technical_debt").parameters.get("rent_multiple", 0.0)
	)
	assert_almost_eq(lent, 100.0 * rent_multiple, 0.01, "Picking it up borrows against the rent")
	assert_true(
		PerkSystem.liability_taken(build.state, "perk.technical_debt"),
		"And the pickup is recorded so it cannot be taken twice"
	)

	build.acquire("perk.technical_debt")
	assert_almost_eq(
		float(build.state.economy.get("cash", 0.0)) - cash_before, lent, 0.01,
		"Re-acquiring it does not lend again"
	)

	assert_true(
		build.state.build["status_effects"].size() > 0,
		"The liability lands as a status effect rather than a hardcoded branch"
	)
	# It is never equipped in this build, which is the point: the debt outlives
	# the perk slot.
	var indebted: Dictionary = build.burn()
	assert_true(
		int(indebted.get("hidden_added", 0)) > 0,
		"Every batch then ships an extra hidden bug, benched or not"
	)


# --- Positional and combo builds ---------------------------------------------

## Intentional: Agent Swarm replaying a free stage does not invent a bill for
## it. A zero-cost fold stays zero.
func _test_a_free_stage_stays_free_when_echoed() -> void:
	var prompt: ModuleDefinition = ContentDatabase.get_module("op.prompt")
	assert_almost_eq(
		float(prompt.parameters.get("cost", 0.0)), 0.0, 0.001, "The opening prompt is free"
	)
	var result: Dictionary = Build.new(["op.prompt", "op.agent_swarm"]).burn()
	var swarm: ModuleDefinition = ContentDatabase.get_module("op.agent_swarm")
	assert_almost_eq(
		float(result.get("cost", 0.0)), float(swarm.parameters.get("cost", 0.0)), 0.01,
		"Echoing it costs the swarm's fee and nothing more"
	)


## Vibe Coder drains quality into progress; Vibe Check then rerolls whatever is
## left, which only works because it runs after the conversion.
func _test_vibe_cannon_converts_then_rerolls() -> void:
	var build := Build.new(["op.rubber_duck", "op.vibe_coder"], ["perk.vibe_check"])
	var result: Dictionary = build.burn()
	var params: Dictionary = ContentDatabase.get_perk("perk.vibe_check").parameters

	assert_true(
		float(result.get("quality_converted", 0.0)) > 0.0,
		"Quality is turned into progress before the batch is scored"
	)
	assert_true(
		float(result.get("quality", 0.0)) >= float(params.get("quality_min", 0)),
		"And the leftover is rerolled inside the advertised band"
	)
	assert_true(
		float(result.get("quality", 0.0)) <= float(params.get("quality_max", 100)),
		"Which is a band, not a bonus"
	)


## Token Cache above an expensive model is a named combo, and the combo is what
## carries the extra discount.
func _test_warm_cache_doubles_the_discount() -> void:
	var cache: ModuleDefinition = ContentDatabase.get_module("op.token_cache")
	var foundation: ModuleDefinition = ContentDatabase.get_module("op.foundation_model")
	assert_eq(
		cache.active_combos("", "op.foundation_model").size(), 1,
		"Token Cache declares Warm Cache with the model below it"
	)

	var result: Dictionary = Build.new(["op.token_cache", "op.foundation_model"]).burn()
	var expected: float = (
		float(foundation.parameters.get("cost", 0.0))
		* float(cache.parameters.get("cost_mult", 1.0))
		* float(cache.parameters.get("combo_cost_mult", 1.0))
	)
	assert_almost_eq(
		float(result.get("cost", 0.0)), expected, 0.01,
		"Both discounts apply to the model's bill"
	)

	var apart: Dictionary = Build.new(["op.foundation_model", "op.token_cache"]).burn()
	assert_true(
		float(apart.get("cost", 0.0)) > float(result.get("cost", 0.0)),
		"The same two modules the other way round pay full price"
	)


## Combos are the mechanical source of truth now, so the effect has to come from
## the combo rather than from a duplicated conditional slot effect.
func _test_caught_in_review_is_the_combo_not_a_slot_effect() -> void:
	var tests: ModuleDefinition = ContentDatabase.get_module("op.unit_tests")
	var combo_fix: float = float(tests.parameters.get("combo_fix", 0.0))
	var base_fix: float = float(tests.parameters.get("fix", 0.0))

	var reviewed: Dictionary = Build.new(["op.stack_overflow", "op.unit_tests"]).burn()
	var alone: Dictionary = Build.new(["op.prompt", "op.unit_tests"]).burn()
	assert_almost_eq(
		float(_stage_named(reviewed, "op.unit_tests").get("stage", {}).get("fix_bugs", 0.0)),
		base_fix + combo_fix, 0.001,
		"Testing what the stage above just wrote fixes more"
	)
	assert_almost_eq(
		float(_stage_named(alone, "op.unit_tests").get("stage", {}).get("fix_bugs", 0.0)),
		base_fix, 0.001,
		"And an unrelated neighbour is not a combo"
	)
	for effect in tests.slot_effects:
		for condition in effect.get("conditions", []):
			assert_false(
				str(condition.get("left", "")) in ["$prev_op", "$prev_module"],
				"Unit Tests keeps its partner list on the combo, not on a slot effect"
			)


## `$heat_ratio` is the rig's heat when the burn starts. Heat produced earlier in
## the same burn deliberately does not arm these modules.
func _test_heat_gates_read_the_rig_not_the_burn() -> void:
	var bank: ModuleDefinition = ContentDatabase.get_module("op.heat_sink_bank")
	var threshold: float = float(bank.parameters.get("threshold", 0.9))

	# Crunch Mode above the bank, on a small rig: the burn itself pushes the rig
	# well past the threshold the bank is looking for.
	var cool := Build.new(["op.crunch_mode", "op.heat_sink_bank"])
	cool.state.compute["heat_capacity"] = 20.0
	cool.state.compute["heat"] = 0.0
	var from_cold: Dictionary = cool.burn()
	assert_true(
		float(from_cold.get("heat", 0.0)) > threshold * 20.0,
		"The build produces more than enough heat during the burn"
	)

	var hot := Build.new(["op.crunch_mode", "op.heat_sink_bank"])
	hot.state.compute["heat_capacity"] = 20.0
	hot.state.compute["heat"] = 19.0
	assert_almost_eq(
		float(hot.burn().get("progress_mult", 1.0)),
		float(from_cold.get("progress_mult", 1.0)) * float(bank.parameters.get("progress", 1.0)),
		0.001,
		"Only a rig that was already redlined when the burn started gets the bonus"
	)


# --- Loadout rules -----------------------------------------------------------

## Benching is not allowed to leave an illegal board behind it.
func _test_bench_is_blocked_when_it_orphans_a_dependent() -> void:
	var build := Build.new([], ["perk.stack_overflow_tab", "perk.bug_alchemy"])
	var alchemy: PerkDefinition = ContentDatabase.get_perk("perk.bug_alchemy")
	var provider: PerkDefinition = ContentDatabase.get_perk("perk.stack_overflow_tab")
	assert_true("bugs" in Array(alchemy.requires_tags), "Bug Alchemy needs a bug source")
	assert_true("bugs" in Array(provider.tags), "Stack Overflow Tab is one")

	assert_false(
		build.perk_system.can_bench(build.state, "perk.stack_overflow_tab", ContentDatabase),
		"Benching the only bug source would orphan Bug Alchemy"
	)
	assert_true(
		build.perk_system.bench_block_reason(
			build.state, "perk.stack_overflow_tab", ContentDatabase
		).find(alchemy.name) >= 0,
		"And the block names the perk that would be left stranded"
	)

	# A drafted module carries the tag just as well, so the same bench is legal
	# once the board provides it.
	build.state.build["modules"] = ["op.stack_overflow"]
	assert_true(
		"bugs" in Array(ContentDatabase.get_module("op.stack_overflow").tags),
		"Copy-Paste from Stack Overflow is a bug source"
	)
	assert_true(
		build.perk_system.can_bench(build.state, "perk.stack_overflow_tab", ContentDatabase),
		"With a bug-making module owned, the perk can be benched"
	)


## Drafting a recursion module is a commitment, so the angel should read it.
func _test_owned_modules_steer_the_draft() -> void:
	var state := RunState.new()
	state.build["modules"] = ["op.agent_swarm", "op.crunch_mode"]
	var tags: Array = PerkSystem.new().owned_tags(state, ContentDatabase)
	assert_true("recursion" in tags, "Owned recursion modules count towards draft affinity")
	assert_true(
		"agent" in tags, "Along with the rest of what those modules say about the build"
	)


# --- Resolver contracts ------------------------------------------------------

## The two rules every subscription above depends on: a condition is matched
## against the stage as authored, and `cap_min` lands after the adds.
func _test_conditions_see_the_stage_before_effects_run() -> void:
	var resolver := EffectResolver.new()
	var state := RunState.new()
	var mod_ctx := ModifierContext.new("board.stage_resolved", state)
	mod_ctx.rng = DeterministicRng.new(3)
	mod_ctx.set_value("stage.repeat_previous", 0.0)
	resolver.begin_action("resolver.contract")
	resolver.dispatch("board.stage_resolved", mod_ctx, [
		{
			"event": "board.stage_resolved",
			"priority": 10,
			"conditions": [],
			"effects": [{"operation": "add", "target": "stage.repeat_previous", "value": 1.0}],
		},
		{
			"event": "board.stage_resolved",
			"priority": 20,
			"conditions": [{"left": "stage.repeat_previous", "operator": ">", "right": 0.5}],
			"effects": [{"operation": "add", "target": "stage.quality", "value": 5.0}],
		},
		{
			"event": "board.stage_resolved",
			"priority": 30,
			"conditions": [],
			"effects": [{"operation": "cap_min", "target": "stage.repeat_previous", "value": 0.35}],
		},
	])
	assert_almost_eq(
		float(mod_ctx.get_value("stage.quality", 0.0)), 0.0, 0.001,
		"A condition cannot see a value another subscription is about to add"
	)
	assert_almost_eq(
		float(mod_ctx.get_value("stage.repeat_previous", 0.0)), 1.0, 0.001,
		"And a floor applied after the adds leaves the larger value alone"
	)
