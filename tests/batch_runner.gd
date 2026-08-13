class_name BatchRunner
extends RefCounted

## Plays whole runs headlessly under a fixed policy and reports how they ended.
##
## The point is not the win rate on its own — a run that limps to the end of the
## calendar used to count as a win, which hid the fact that nobody was reaching
## the endgame. What matters is the *shape* of the outcomes: how many ascended,
## how many collapsed, and how many never terminated at all.
##
## Every location has one contract and it is live from the first prompt, so the
## thing to read is how close the sample got: `avg_burn_ratio` is the share of
## the contract an average run finished. A sample that lands well under 1.0 means
## the contract is priced above what the chapter can build.

## A run that has not resolved in this many policy steps is stuck, not slow, and
## is reported as such rather than being quietly dropped from the sample.
const SAFETY_STEPS := 500

## Share of heat capacity the builder refuses to let the next burn land above.
## Venting costs a prompt and prompts are deadlines, so it vents only when the
## next burn would actually set the rig on fire.
const BUILDER_COOL_AT := 1.0

var invalid_number_count: int = 0
var guard_limit_count: int = 0

## Prints a line per run while the sweep is going. A sweep that stalls on one
## seed is otherwise indistinguishable from a sweep that is merely large.
var verbose: bool = false


## `location` is the chapter of the campaign every run in the sweep is set in.
## A run can no longer buy its way to bigger premises, so the sweep has to be
## told where it is happening the same way the campaign would tell it.
func run(count: int = 1000, policy: String = "random", location: String = MetaProgress.DEFAULT_LOCATION) -> Dictionary:
	var wins: int = 0
	var total_rounds: int = 0
	var stuck: int = 0
	var outcomes: Dictionary = {}
	var peak_token_rates: Array[float] = []
	var peak_cash: Array[float] = []
	var perk_counts: Dictionary = {}
	var expired_runs: int = 0
	var lifetime_tokens: Array[float] = []
	var burn_ratios: Array[float] = []
	invalid_number_count = 0
	guard_limit_count = 0
	# Balance numbers describe a first run from nothing, so unlocks stay out.
	MetaProgress.enabled = false

	for i in range(count):
		var sim := _create_headless_sim()
		var seed_value: int = 1000 + i
		var started_at: int = Time.get_ticks_msec()
		sim.start_run(seed_value)
		sim.apply_run_location(sim.run_state, location)
		var safety: int = 0
		while sim.phase != sim.Phase.RUN_END and safety < SAFETY_STEPS:
			safety += 1
			_play_policy_step(sim, policy)
			total_rounds += 1
			if _has_invalid_numbers(sim.run_state):
				invalid_number_count += 1
				break
			var guard: ChainGuard = sim.effect_resolver.get_guard()
			if guard != null and guard.terminated:
				guard_limit_count += 1
		var outcome: String = str(sim.run_state.flags.get("outcome", ""))
		if sim.phase != sim.Phase.RUN_END:
			stuck += 1
			outcome = "stuck"
		elif outcome == "":
			outcome = "ascended" if sim.run_state.flags.get("victory", false) else "lost"
		outcomes[outcome] = int(outcomes.get(outcome, 0)) + 1
		if verbose:
			print("    seed %d [%s]: %s in %d steps, %d ms" % [
				seed_value, policy, outcome, safety, Time.get_ticks_msec() - started_at,
			])
		if sim.run_state.flags.get("victory", false):
			wins += 1
		if outcome == "contract_expired":
			expired_runs += 1
		# What the run actually burned against what its contract asked for, which
		# is the number `total_burn` has to be priced against.
		var burned: float = float(sim.run_state.statistics.get("lifetime_tokens", 0.0))
		lifetime_tokens.append(burned)
		var target: float = float(sim.ascension_boss_contract().get("total_burn", 0.0))
		if target > 0.0:
			burn_ratios.append(burned / target)
		peak_token_rates.append(float(sim.run_state.statistics.get("peak_token_rate", 0.0)))
		peak_cash.append(float(sim.run_state.statistics.get("peak_cash", 0.0)))
		for perk_id in sim.run_state.build.get("perks", []):
			perk_counts[perk_id] = int(perk_counts.get(perk_id, 0)) + 1
		sim.free()

	var runs: int = maxi(count, 1)
	return {
		"runs": count,
		"policy": policy,
		"location": location,
		"win_rate": float(wins) / float(runs),
		"ascended_rate": float(int(outcomes.get("ascended", 0))) / float(runs),
		"expired_rate": float(expired_runs) / float(runs),
		"stuck_count": stuck,
		"outcomes": outcomes,
		"avg_rounds": float(total_rounds) / float(runs),
		"avg_peak_token_rate": _average(peak_token_rates),
		"avg_lifetime_tokens": _average(lifetime_tokens),
		"avg_burn_ratio": _average(burn_ratios),
		"max_burn_ratio": _maximum(burn_ratios),
		"avg_peak_cash": _average(peak_cash),
		"invalid_number_count": invalid_number_count,
		"guard_limit_count": guard_limit_count,
		"perk_counts": perk_counts,
	}


## The outcome histogram as one line, for the runner's console output.
static func describe_outcomes(summary: Dictionary) -> String:
	var outcomes: Dictionary = Dictionary(summary.get("outcomes", {}))
	var keys: Array = outcomes.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key in keys:
		parts.append("%s=%d" % [str(key), int(outcomes[key])])
	return ", ".join(parts) if parts.size() > 0 else "none"


func export_csv(path: String, summary: Dictionary) -> void:
	var lines: PackedStringArray = ["metric,value"]
	for key in summary.keys():
		if summary[key] is Dictionary:
			continue
		lines.append("%s,%s" % [key, str(summary[key])])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines))
		file.close()


func _create_headless_sim() -> Node:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	return sim


func _play_policy_step(sim: Node, policy: String) -> void:
	match sim.phase:
		sim.Phase.ROUND_PREP:
			if policy == "builder":
				_builder_shop(sim)
			if sim.run_state.has_queued_jobs():
				_work_round(sim, policy)
				return
			var offers: Array = sim.run_state.business.get("job_offers", [])
			if offers.is_empty():
				# A round with nothing to work still owes its rent, so closing it
				# out is the only move rather than a free skip.
				sim._end_round()
				return
			if policy == "builder":
				_builder_take_contracts(sim, offers)
				if sim.run_state.has_queued_jobs():
					_work_round(sim, policy)
				else:
					# A round with nothing worth taking still owes its rent.
					sim._end_round()
				return
			var pick: Dictionary = offers[0]
			if policy == "greedy":
				for offer in offers:
					if float(offer.get("reward", 0.0)) > float(pick.get("reward", 0.0)):
						pick = offer
			sim.accept_job(str(pick.get("id", "")))
			_work_round(sim, policy)
		sim.Phase.ANGEL_ROUND:
			if sim.pending_choices.size() > 0:
				var choice: Dictionary = sim.pending_choices[0]
				# A rejected offer must not wedge the policy on the angel screen.
				if not sim.accept_offer(str(choice.get("type", "")), str(choice.get("id", ""))):
					sim.decline_offers()
			else:
				sim.decline_offers()
		sim.Phase.ROUND_END:
			sim._end_round()
		_:
			pass


## `start_work_sync` auto-burns to the end of the session, which never presses
## COOL. The builder works the round by hand so venting is part of the sample:
## a rig whose cooling has fallen behind shows up here as a run that cooks.
func _work_round(sim: Node, policy: String) -> void:
	if policy != "builder":
		sim.start_work_sync()
		return
	if not sim.can_start_work():
		return
	sim.start_work()
	# Nobody is here to lay out the pipeline, and an empty board cannot burn.
	sim.auto_arrange_board()
	var safety: int = 0
	var consecutive_cools: int = 0
	while sim.phase == sim.Phase.IN_ROUND and safety < SAFETY_STEPS:
		safety += 1
		var capacity: float = maxf(1.0, float(sim.run_state.compute.get("heat_capacity", 100.0)))
		var heat: float = float(sim.run_state.compute.get("heat", 0.0))
		# Burning blind is how a rig catches fire: the next burn's own heat is
		# forecastable, so vent first when it would take the bar over the top.
		var projected: float = heat + float(sim.preview_burn().get("total_heat", 0.0))
		var too_hot: bool = projected >= capacity * BUILDER_COOL_AT
		var acted: bool = false
		if too_hot and consecutive_cools < 8 and float(sim.preview_cool().get("total_heat", 0.0)) < 0.0:
			acted = bool(sim.cool_hardware().get("ok", false))
		if acted:
			consecutive_cools += 1
			continue
		consecutive_cools = 0
		if not bool(sim.burn_batch().get("ok", false)):
			break
	if sim.phase == sim.Phase.IN_ROUND:
		sim._end_session("stalled")


## Reward alone is the wrong thing to chase: the fattest contract on the board is
## usually the one this rig cannot deliver, and a missed deadline costs
## reputation rather than just the fee. The builder takes the best-paying work it
## can finish, then keeps loading the slate while throughput still covers it.
## Taking nothing is better than taking work that will fail.
func _builder_take_contracts(sim: Node, offers: Array) -> void:
	var safety: int = 0
	while safety < 8:
		safety += 1
		var pick: String = ""
		var best_reward: float = -1.0
		var fallback: String = ""
		var lightest: float = INF
		for offer in offers:
			var id: String = str(offer.get("id", ""))
			if not sim.can_accept_offer(id):
				continue
			var ratio: float = float(sim.queue_load_info(offer).get("ratio", 0.0))
			if ratio < lightest:
				lightest = ratio
				fallback = id
			if ratio > 1.0:
				continue
			if float(offer.get("reward", 0.0)) <= best_reward:
				continue
			pick = id
			best_reward = float(offer.get("reward", 0.0))
		# An empty round earns nothing and still pays rent, so when everything
		# on the board is a stretch, take the least of them rather than none.
		if pick == "" and not sim.run_state.has_queued_jobs():
			pick = fallback
		if pick == "" or not sim.accept_job(pick):
			return
		offers = sim.run_state.business.get("job_offers", [])


## Buys the way a player does: cooling before the machine that needs it, space
## before the machine that will not fit, and never everything at once.
func _builder_shop(sim: Node) -> void:
	if not sim.market_open():
		return
	# Two rounds of bills stay in the bank; the rest is for growth. Holding a
	# fixed share back instead never accumulates enough for the next rung, and
	# spending down to one round's bills bankrupts the run on the standing costs
	# the purchase itself adds.
	var reserve: float = float(sim.cost_forecast().get("fixed_due", 0.0)) * 2.0
	var budget: float = maxf(0.0, float(sim.run_state.economy.get("cash", 0.0)) - reserve) * 0.5
	var safety: int = 0
	while safety < 40:
		safety += 1
		var pick: String = _builder_next_purchase(sim, budget)
		if pick == "":
			return
		var cost: float = _cost_of(sim, pick)
		if not sim.buy_upgrade(pick):
			return
		budget -= cost


## The next thing worth buying, in the order the game expects: close a live
## cooling shortfall, then take the biggest machine the money reaches — buying
## the cooling it will need first if the shop says it would cook.
func _builder_next_purchase(sim: Node, budget: float) -> String:
	if not bool(sim.heat_outlook().get("sustainable", true)):
		return _affordable(sim, budget, ["cooling"], true)
	# Components are the cheapest throughput in the game and take no floor
	# space: maxing what the run already owns is how the early game gets off the
	# laptop at all, long before it can afford a machine or a bigger room.
	var component: String = _affordable(sim, budget, ["component"], false)
	if component != "" and sim.upgrade_heat_warning(component) == "":
		return component
	var machine: String = _affordable(sim, budget, ["hardware"], false)
	if machine != "" and sim.upgrade_heat_warning(machine) != "":
		# The machine is affordable but the room cannot cool it, which is what
		# the Cooling shelf is for — as long as both still fit in the budget.
		# Buying cooling for a machine the run cannot also afford is how a
		# policy spends every round's profit and never grows.
		var cooler: String = _affordable(sim, budget - _cost_of(sim, machine), ["cooling"], true)
		return cooler
	return machine


func _cost_of(sim: Node, upgrade_id: String) -> float:
	return UpgradeSystem.purchase_cost(
		ContentDatabase.get_upgrade(upgrade_id), UpgradeSystem.upgrade_level(sim.run_state, upgrade_id)
	)


## The most expensive thing on a shelf the run can afford. `cooling_only`
## selects between the Cooling shelf and everything else, since an upgrade can
## carry both tags.
func _affordable(sim: Node, budget: float, tags: Array, cooling_only: bool) -> String:
	var best: String = ""
	var best_cost: float = -1.0
	for upgrade in ContentDatabase.upgrades:
		var tagged: bool = false
		for tag in tags:
			if str(tag) in Array(upgrade.tags):
				tagged = true
		if not tagged:
			continue
		if cooling_only != ("cooling" in Array(upgrade.tags)):
			continue
		if not sim.can_buy_upgrade(upgrade.id):
			continue
		var cost: float = UpgradeSystem.purchase_cost(
			upgrade, UpgradeSystem.upgrade_level(sim.run_state, upgrade.id)
		)
		if cost > budget or cost <= best_cost:
			continue
		# The sticker price is not the commitment: every rung also adds to the
		# standing bill for the rest of the run, which is what actually ends a
		# run that over-bought.
		if upgrade.recurring_cost_delta > _recurring_headroom(sim):
			continue
		best = upgrade.id
		best_cost = cost
	return best


func _recurring_headroom(sim: Node) -> float:
	return maxf(100.0, float(sim.run_state.economy.get("income", 0.0)) * 0.25)


func _has_invalid_numbers(state: RunState) -> bool:
	for section in [state.economy, state.compute, state.business, state.statistics]:
		for value in section.values():
			if value is float and (is_nan(value) or is_inf(value)):
				return true
	return false


func _average(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for v in values:
		total += float(v)
	return total / float(values.size())


## Headless balance guidance: first reroll should land around 10–25% of a normal
## contract reward at the bedroom tier.
static func angel_reroll_cost_ratio(sim: Node) -> float:
	var contract_reward: float = maxf(1.0, float(sim.run_state.economy.get("round_rent", 400.0)) * 4.0)
	return sim.angel_reroll_cost() / contract_reward


## Draw `tables` angel tables and report how many cards matched `tag`.
static func draft_tag_hit_rate(
	seed_value: int,
	tag: String,
	tables: int = 40,
	owned_tags: Array = []
) -> float:
	var hits: int = 0
	var total: int = 0
	for i in range(tables):
		var rng := DeterministicRng.new(seed_value + i)
		var state := RunState.new()
		state.reset()
		for offer in ContentDatabase.draw_angel_offers(rng, state, 3, owned_tags, 0.0):
			total += 1
			for offer_tag in Array(offer.get("tags", [])):
				if str(offer_tag) == tag:
					hits += 1
					break
	return float(hits) / maxf(1.0, float(total))


## The best run in the sample. A contract nobody averages but the best run
## clears is priced as a stretch; one nothing comes near is priced wrong.
func _maximum(values: Array) -> float:
	var best: float = 0.0
	for v in values:
		best = maxf(best, float(v))
	return best
