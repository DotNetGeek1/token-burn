class_name SimulationPreview
extends RefCounted

## Stateless foresight for the Burn Board and Market. Every method clones
## `RunState` or reads it without writing the live phase, RNG counters,
## signals, or saves. `sim` is the owning Simulation node, taken as a plain
## `Node` to avoid a circular class reference.


## What BURN TOKENS would produce right now, resolved on a throwaway copy of the
## state so the board screen can show the outcome without causing it.
##
## `burn.heat` is only the pipeline's own stage heat. Every prompt — burn or
## cool — also gains ambient heat from powered-on hardware and loses some to
## cooling capacity (`HeatSystem.process_prompt`), which `run_burn` applies too.
## `total_heat` is the two combined: the number the heat bar will actually move
## by, which is what the UI should show instead of the stage heat alone.
static func preview_burn(sim: Node, stage_limit: int = -1) -> Dictionary:
	if sim.phase != sim.Phase.IN_ROUND:
		return {"ok": false, "reason": "Not working."}
	var clone := RunState.new()
	clone.from_dict(sim.run_state.to_dict())
	var heat_before: float = float(clone.compute.get("heat", 0.0))
	var preview_resolver := EffectResolver.new()
	var result: Dictionary = sim.job_system().run_burn(
		clone,
		sim._burn_rng(),
		preview_resolver,
		sim.debug_collect_subscriptions(),
		sim.tuning,
		sim.compute_system(),
		sim.heat_system(),
		sim.economy_system(),
		sim.board_system(),
		stage_limit,
		ResolveMode.PREVIEW
	)
	var burn: Dictionary = result.get("burn", {"ok": false, "reason": "The pipeline is empty."})
	if burn.get("ok", false):
		burn = burn.duplicate(true)
		burn["trace"] = preview_resolver.get_trace()
		_decorate_burn_outlook(burn, heat_before, clone)
	return burn


## The authoritative next-click forecast. Unlike `preview_burn`, this also works
## while accepted work is still queued, before the first BURN has opened the
## session. The throwaway state follows the same preparation order as
## `start_work`: recalculate, promote queued jobs, apply queued surges, burn.
## Nothing touches the live phase, state, RNG counters, signals, trace, or save.
static func preview_next_burn(sim: Node, stage_limit: int = -1) -> Dictionary:
	if sim.phase == sim.Phase.IN_ROUND and sim._work_running:
		return preview_burn(sim, stage_limit)
	if not sim.can_start_work():
		return {"ok": false, "reason": "No queued work."}
	var clone := RunState.new()
	clone.from_dict(sim.run_state.to_dict())
	var heat_before: float = float(clone.compute.get("heat", 0.0))
	var preview_resolver := EffectResolver.new()
	sim.board_system().ensure_board(clone, ContentDatabase)
	sim.compute_system().recalculate(
		clone, preview_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	if not sim.job_system().begin_work_session(clone, ContentDatabase):
		return {"ok": false, "reason": "No queued work."}
	_apply_queued_preview_options(sim, clone)
	var result: Dictionary = sim.job_system().run_burn(
		clone,
		sim._burn_rng(),
		preview_resolver,
		sim.debug_collect_subscriptions(),
		sim.tuning,
		sim.compute_system(),
		sim.heat_system(),
		sim.economy_system(),
		sim.board_system(),
		stage_limit,
		ResolveMode.PREVIEW
	)
	var burn: Dictionary = result.get("burn", {"ok": false, "reason": "The pipeline is empty."})
	if burn.get("ok", false):
		burn = burn.duplicate(true)
		burn["trace"] = preview_resolver.get_trace()
		_decorate_burn_outlook(burn, heat_before, clone)
	return burn


static func _decorate_burn_outlook(burn: Dictionary, heat_before: float, state: RunState) -> void:
	var heat_after: float = float(state.compute.get("heat", 0.0))
	var capacity: float = maxf(1.0, float(state.compute.get("heat_capacity", 100.0)))
	var throttle_ratio: float = float(
		ContentDatabase.balance.get("economy", {}).get("heat", {}).get("throttle_ratio", 0.8)
	)
	burn["heat_before"] = heat_before
	burn["heat_delta"] = heat_after - heat_before
	# Kept for callers written against the original preview contract.
	burn["total_heat"] = heat_after - heat_before
	burn["heat_after"] = heat_after
	burn["heat_capacity"] = capacity
	burn["heat_ratio_after"] = heat_after / capacity
	burn["crosses_throttle"] = heat_before < capacity * throttle_ratio and heat_after >= capacity * throttle_ratio
	burn["crosses_fire"] = heat_before < capacity and heat_after >= capacity


static func _apply_queued_preview_options(sim: Node, state: RunState) -> void:
	if sim.queued_boost:
		state.add_rate_modifier(1.35, 1, "boost")
		sim.heat_system().add_heat(state, 12.0)
	if not sim.queued_cloud or not (sim.CLOUD_ACCOUNT_UPGRADE in state.build.get("upgrades", [])):
		return
	var burst: float = float(state.compute.get("local_capacity", 0.0)) * sim._cloud_burst_multiplier_for(state)
	var price: float = sim._cloud_burst_cost_for(state)
	if not sim.economy_system().purchase(state, price, "cloud_burst_preview"):
		return
	state.compute["cloud_burst"] = burst
	state.compute["cloud_burst_prompts"] = 1


## What COOL would actually do to the heat bar right now: the vent, plus the
## same ambient heat/cooling pass a burn prompt gets, since `end_prompt` runs
## either way. This is what makes COOL sometimes barely move the bar — the
## ambient gain can eat most or all of the vent.
static func preview_cool(sim: Node) -> Dictionary:
	if not sim.can_burn():
		return {"ok": false, "reason": "Not working."}
	var clone := RunState.new()
	clone.from_dict(sim.run_state.to_dict())
	var heat_before: float = float(clone.compute.get("heat", 0.0))
	var preview_resolver := EffectResolver.new()
	var result: Dictionary = sim.job_system().run_cooling_prompt(
		clone,
		sim._burn_rng(),
		preview_resolver,
		sim.debug_collect_subscriptions(),
		sim.tuning,
		sim.compute_system(),
		sim.heat_system(),
		sim.economy_system(),
		ResolveMode.PREVIEW
	)
	if not result.get("ok", false):
		return result
	result["heat_before"] = heat_before
	result["heat_after"] = float(clone.compute.get("heat", 0.0))
	result["total_heat"] = float(result["heat_after"]) - heat_before
	return result


## How loaded the round's slate is relative to its tightest deadline.
## Pass an offer to preview the load if that offer were also accepted.
## ratio 1.0 means the slate needs exactly every prompt its tightest deadline
## allows. Parallel lanes do not make the slate lighter — they share one batch —
## so throughput is measured against the rig's rate either way.
static func queue_load_info(sim: Node, extra_offer: Dictionary = {}) -> Dictionary:
	var rate: float = maxf(1.0, float(sim.run_state.compute.get("token_rate", 1.0)))
	var tokens: float = 0.0
	var deadline: int = 0
	var jobs: Array = []
	jobs.append_array(sim.run_state.business.get("active_jobs", []))
	jobs.append_array(sim.run_state.business.get("job_queue", []))
	if not extra_offer.is_empty():
		jobs.append(extra_offer)
	for job in jobs:
		tokens += maxf(0.0, float(job.get("tokens_remaining", job.get("token_requirement", 0.0))))
		var job_deadline: int = int(job.get("prompts_remaining", job.get("deadline_prompts", 0)))
		if job_deadline > 0:
			deadline = job_deadline if deadline == 0 else mini(deadline, job_deadline)
	var prompts_needed: float = tokens / rate
	var ratio: float = 0.0 if deadline <= 0 else prompts_needed / float(deadline)
	return {
		"jobs": jobs.size(),
		"tokens": tokens,
		"prompts_needed": prompts_needed,
		"deadline_prompts": deadline,
		"ratio": ratio,
		"over_capacity": ratio > 1.0,
		"cap": queue_capacity_cap(),
		"job_slots": sim.job_slots(),
	}


## Live picture of the round's costs: the flat charges that fall due when the
## round ends, and the metered ones that have already been paid prompt by prompt.
## Rent does not grow with a long round; the power bill does.
static func cost_forecast(sim: Node) -> Dictionary:
	var cloud_multiplier: float = float(sim.tuning.get("cloud_cost_multiplier", 1.0))
	var rent: float = float(sim.run_state.economy.get("round_rent", 0.0))
	var recurring: float = float(sim.run_state.economy.get("recurring_costs", 0.0))
	# Already carries the multiplier from accrual; billed at face value.
	var cloud_bill: float = float(sim.run_state.economy.get("cloud_surcharge_liability", 0.0))
	var power_per_prompt: float = float(sim.run_state.economy.get("power_cost_per_prompt", 0.0))
	var cloud_per_prompt: float = float(sim.run_state.economy.get("cloud_cost_per_prompt", 0.0)) * cloud_multiplier
	var operating_per_prompt: float = power_per_prompt + cloud_per_prompt
	var operating_so_far: float = float(sim.run_state.economy.get("costs_this_round", 0.0))
	var fixed_due: float = rent + recurring + cloud_bill
	return {
		"rent": rent,
		"recurring": recurring,
		"cloud_bill": cloud_bill,
		"power_per_prompt": power_per_prompt,
		"cloud_per_prompt": cloud_per_prompt,
		"operating_per_prompt": operating_per_prompt,
		"operating_so_far": operating_so_far,
		"fixed_due": fixed_due,
		"accrued_total": operating_so_far + fixed_due,
		"prompts_used": sim.prompts_used_this_round(),
		"power_draw": float(sim.run_state.compute.get("power_draw", 0.0)),
	}


## What this round still owes and therefore what is genuinely free to spend, so
## the player is never surprised by a bill they had already spent.
static func bills_outlook(sim: Node) -> Dictionary:
	var costs: Dictionary = cost_forecast(sim)
	# Only the end-of-round lump is held back. Power and cloud are metered prompt
	# by prompt out of the income the same prompts bring in, so counting a whole
	# round of them here would say "safe to spend nothing" every round.
	var still_due: float = float(costs.get("fixed_due", 0.0))
	var cash: float = float(sim.run_state.economy.get("cash", 0.0))
	return {
		"due": still_due,
		"rent": float(costs.get("rent", 0.0)),
		"prompts_used": int(costs.get("prompts_used", 0)),
		"cash": cash,
		"spendable": maxf(0.0, cash - still_due),
		"shortfall": maxf(0.0, still_due - cash),
	}


## Warning text for a purchase that would leave this round's bills unpayable.
static func purchase_bill_warning(sim: Node, cost: float) -> String:
	if cost <= 0.0:
		return ""
	var outlook: Dictionary = bills_outlook(sim)
	var left: float = float(outlook.get("cash", 0.0)) - cost
	var due: float = float(outlook.get("due", 0.0))
	if left >= due:
		return ""
	return "Leaves you %s short of the %s due when this round ends." % [
		NumberFormat.format_cash(due - left),
		NumberFormat.format_cash(due),
	]


## Cooling an upgrade brings with it, for previewing a purchase.
static func cooling_from_effects(effects: Array) -> float:
	var total: float = 0.0
	for effect in effects:
		if effect is EffectDefinition and effect.target == "compute.cooling":
			total += float(effect.value)
	return total


## Whether cooling can keep up with a given power draw, and by how much. Used to
## warn the player before they buy hardware their space cannot cool.
static func heat_outlook(sim: Node, extra_power: float = 0.0, extra_cooling: float = 0.0) -> Dictionary:
	var power: float = float(sim.run_state.compute.get("power_draw", 0.0)) + extra_power
	var cooling: float = float(sim.run_state.compute.get("cooling", 0.0)) + extra_cooling
	var capacity: float = maxf(1.0, float(sim.run_state.compute.get("heat_capacity", 100.0)))
	var tier: int = HeatSystem.work_tier(sim.run_state)
	var delta: float = HeatSystem.ambient_delta_for(power, cooling, capacity, tier)
	var needed: float = HeatSystem.cooling_needed_for(power, tier)
	return {
		"power_draw": power,
		"cooling": cooling,
		"heat_per_prompt": delta,
		"sustainable": delta <= 0.0,
		"cooling_needed": needed,
	}


## Warning text for a hardware purchase that cooling could not keep up with.
static func upgrade_heat_warning(sim: Node, upgrade_id: String) -> String:
	var upgrade: UpgradeDefinition = ContentDatabase.get_upgrade(upgrade_id)
	if upgrade == null or upgrade.hardware_key == "":
		return ""
	var hardware: Dictionary = ContentDatabase.balance.get("hardware_curves", {}).get(upgrade.hardware_key, {})
	var extra_cooling: float = cooling_from_effects(upgrade.effects)
	var outlook: Dictionary = heat_outlook(sim, float(hardware.get("power_draw", 0.0)), extra_cooling)
	if bool(outlook.get("sustainable", true)):
		return ""
	var shortfall: float = float(outlook.get("cooling_needed", 0.0)) - float(outlook.get("cooling", 0.0))
	var warning: String = "Your space cannot cool this: +%.0f heat per prompt. Needs %d cooling, you would have %d." % [
		float(outlook.get("heat_per_prompt", 0.0)),
		int(ceil(float(outlook.get("cooling_needed", 0.0)))),
		int(outlook.get("cooling", 0.0)),
	]
	var remedy: String = cooling_remedy(sim, shortfall)
	if remedy != "":
		warning += " %s" % remedy
	return warning


## The cooling on sale right now that would close a shortfall, named and
## counted. A warning that only says "not enough cooling" leaves the player
## hunting the Market for a shelf that may look empty; this says what to buy.
static func cooling_remedy(sim: Node, shortfall: float) -> String:
	if shortfall <= 0.0:
		return ""
	var best: UpgradeDefinition = null
	var best_cooling: float = 0.0
	for upgrade in ContentDatabase.upgrades:
		if not ("cooling" in Array(upgrade.tags)):
			continue
		if not UpgradeSystem.prerequisites_met(sim.run_state, upgrade, ContentDatabase):
			continue
		if UpgradeSystem.is_maxed(sim.run_state, upgrade):
			continue
		if not upgrade.repeatable and upgrade.id in sim.run_state.build.get("upgrades", []):
			continue
		var cooling: float = cooling_from_effects(upgrade.effects)
		if cooling <= 0.0:
			continue
		# The smallest unit that still closes the gap in a sensible number of
		# purchases, so the advice is the cheap thing rather than the biggest.
		if best == null or cooling < best_cooling:
			best = upgrade
			best_cooling = cooling
	if best == null:
		return "Nothing on the Cooling shelf reaches this yet — take the next property up first."
	var units: int = int(ceil(shortfall / best_cooling))
	if units <= 1:
		return "A %s from the Market's Cooling shelf would cover it." % best.name
	return "About %d × %s from the Market's Cooling shelf would cover it." % [units, best.name]


static func queue_capacity_cap() -> float:
	return float(ContentDatabase.balance.get("job_scaling", {}).get("queue_capacity_cap", 2.0))
