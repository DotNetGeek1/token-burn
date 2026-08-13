class_name ComputeSystem
extends RefCounted


func recalculate(run_state: RunState, effect_resolver: EffectResolver, subscriptions: Array, rng: DeterministicRng) -> void:
	var hardware_rate: float = 0.0
	var power_draw: float = 0.0
	var hardware_curves: Dictionary = ContentDatabase.balance.get("hardware_curves", {})
	for hardware_id in run_state.build["hardware"]:
		var hw: Dictionary = hardware_curves.get(str(hardware_id), {})
		hardware_rate += float(hw.get("token_rate", 0.0))
		power_draw += float(hw.get("power_draw", 0.0))
	run_state.compute["local_capacity"] = hardware_rate
	run_state.compute["power_draw"] = power_draw
	_update_power_cost(run_state, power_draw)
	var base_cooling: float = derive_cooling(run_state)
	var cloud_rate: float = float(run_state.compute.get("cloud_capacity", 0.0)) + float(
		run_state.compute.get("cloud_burst", 0.0)
	)
	# Perks and status effects modify efficiency for the length of one
	# recalculation; only the base carries between prompts.
	var base_efficiency: float = float(run_state.compute.get("efficiency_base", 1.0))
	var base_rate: float = hardware_rate + cloud_rate
	for entry in run_state.compute.get("rate_modifiers", []):
		if entry is Dictionary:
			base_rate *= float(entry.get("multiplier", 1.0))
	# Legacy throughput (Old Silicon) is kit the profile owns rather than a
	# modifier the run applied, so it lands on the base the same way a faster
	# machine would and everything else composes on top of it.
	base_rate *= float(run_state.business.get("legacy_token_multiplier", 1.0))
	# Rule-changer: heat above 60% of capacity feeds back into throughput
	# instead of just risking a fire. A build that leans into this runs hot on
	# purpose.
	if "unlock.rule_heat_recycler" in Array(run_state.build.get("meta_unlocks", [])):
		var heat_ratio: float = float(run_state.compute.get("heat", 0.0)) / maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))
		if heat_ratio > 0.6:
			base_rate *= 1.0 + (heat_ratio - 0.6) * 0.5
	# Metered cloud spend is re-derived from what the cloud shelf bills, so a
	# perk that discounts it discounts the price rather than its own last
	# answer. Left in RunState after the dispatch because the charge lands per
	# prompt, well after this, in EconomySystem.accrue_prompt_costs.
	var base_cloud_cost: float = float(run_state.economy.get("cloud_base_cost_per_prompt", 0.0))
	effect_resolver.begin_action(EventBus.EVENT_COMPUTE_RECALCULATE)
	var mod_ctx := ModifierContext.new(EventBus.EVENT_COMPUTE_RECALCULATE, run_state)
	mod_ctx.rng = rng.derive(EventBus.EVENT_COMPUTE_RECALCULATE)
	mod_ctx.set_value("compute.token_rate", base_rate)
	mod_ctx.set_value("compute.efficiency", base_efficiency)
	mod_ctx.set_value("compute.local_capacity", hardware_rate)
	mod_ctx.set_value("compute.cooling", base_cooling)
	# Local and cloud throughput are separate numbers a perk can pull apart, so
	# a build can genuinely be bare-metal or cloud-native rather than both at a
	# discount. They are recombined into `token_rate` once the dispatch is done.
	mod_ctx.set_value("compute.local_rate", hardware_rate)
	mod_ctx.set_value("compute.cloud_rate", cloud_rate)
	mod_ctx.set_value("economy.cloud_cost_per_prompt", base_cloud_cost)
	effect_resolver.dispatch(EventBus.EVENT_COMPUTE_RECALCULATE, mod_ctx, subscriptions)
	var efficiency: float = float(mod_ctx.get_value("compute.efficiency", base_efficiency))
	run_state.compute["efficiency"] = efficiency
	var local: float = maxf(0.0, float(mod_ctx.get_value("compute.local_rate", hardware_rate)))
	var cloud: float = maxf(0.0, float(mod_ctx.get_value("compute.cloud_rate", cloud_rate)))
	run_state.compute["local_rate"] = local
	run_state.compute["cloud_rate"] = cloud
	run_state.compute["cloud_share"] = cloud / maxf(1.0, local + cloud)
	run_state.statistics["max_cloud_share"] = maxf(
		float(run_state.statistics.get("max_cloud_share", 0.0)),
		float(run_state.compute.get("cloud_share", 0.0))
	)
	# `compute.token_rate` stays targetable for build-neutral perks: what they
	# multiply is the combined rate, and whatever the split did to the two
	# halves is folded in as a scale so throttles and heat still apply to it.
	var split_before: float = hardware_rate + cloud_rate
	var split_scale: float = (local + cloud) / split_before if split_before > 0.0 else 1.0
	var combined: float = float(mod_ctx.get_value("compute.token_rate", base_rate)) * split_scale
	run_state.compute["token_rate"] = maxf(0.0, combined) * efficiency
	run_state.compute["cooling"] = maxf(0.0, float(mod_ctx.get_value("compute.cooling", base_cooling)))
	run_state.economy["cloud_cost_per_prompt"] = maxf(
		0.0, float(mod_ctx.get_value("economy.cloud_cost_per_prompt", base_cloud_cost))
	)


## Cooling is derived from the run rather than accumulated onto it. Moving in,
## reloading and recalculating used to each add the same environmental cooling
## again; adding up what the run demonstrably has makes that impossible.
##
##     location cooling + installed cooling + permanent unlocks
##
## Modifiers get a say on top, for the length of one recalculation only.
static func derive_cooling(run_state: RunState) -> float:
	return (
		UpgradeSystem.location_cooling(run_state, ContentDatabase)
		+ UpgradeSystem.installed_cooling(run_state, ContentDatabase)
		+ float(run_state.compute.get("meta_cooling", 0.0))
	)


## Electricity is a standing charge plus metered draw, so bigger rigs cost more
## to run every prompt and not just more to buy.
func _update_power_cost(run_state: RunState, power_draw: float) -> void:
	var economy_balance: Dictionary = ContentDatabase.balance.get("economy", {})
	var per_watt: float = float(economy_balance.get("power_cost_per_watt_prompt", 0.0))
	var standing: float = float(run_state.economy.get("power_base_cost_per_prompt", 10.0))
	run_state.economy["power_cost_per_prompt"] = standing + power_draw * per_watt


## Multiplier from raw hardware/cloud capacity to the rate the HUD shows. Shop
## cards use this so a listed 50M/s matches what buying it adds right now.
static func current_rate_scale(run_state: RunState) -> float:
	var hardware_rate: float = float(run_state.compute.get("local_capacity", -1.0))
	if hardware_rate < 0.0:
		hardware_rate = _sum_hardware_rate(run_state)
	var cloud_rate: float = float(run_state.compute.get("cloud_capacity", 0.0)) + float(
		run_state.compute.get("cloud_burst", 0.0)
	)
	var base: float = hardware_rate + cloud_rate
	if base <= 0.0:
		return 1.0
	return float(run_state.compute.get("token_rate", 0.0)) / base


static func _sum_hardware_rate(run_state: RunState) -> float:
	var hardware_rate: float = 0.0
	var hardware_curves: Dictionary = ContentDatabase.balance.get("hardware_curves", {})
	for hardware_id in run_state.build["hardware"]:
		var hw: Dictionary = hardware_curves.get(str(hardware_id), {})
		hardware_rate += float(hw.get("token_rate", 0.0))
	return hardware_rate


## How many contracts the rig can work at once. One machine, one contract: a
## second desktop is what turns a queue that had to be worked in order into two
## contracts advancing side by side. Components (a GPU inside a desktop) make
## the machine they live in faster rather than adding a parallel line.
static func job_slots(run_state: RunState) -> int:
	return maxi(1, UpgradeSystem.hardware_slots_used(run_state, ContentDatabase))
