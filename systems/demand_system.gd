class_name DemandSystem
extends RefCounted


## How many contracts the board holds, derived from scratch each round.
## `demand_modifier` carries this round's perk contributions and is re-seeded
## from `demand_modifier_base` by Simulation before the round.started dispatch,
## so a static bonus stays static instead of accumulating over a year.
func refresh_demand(run_state: RunState) -> void:
	var base: float = 2.0 + float(run_state.business.get("reputation", 0.0)) * 0.05
	var ad_boost: float = float(run_state.business.get("advertising", 0.0)) * 0.002
	var modifier: float = float(run_state.business.get("demand_modifier", 0.0))
	var offer_cap: float = float(maxi(8, ComputeSystem.job_slots(run_state)))
	run_state.business["demand"] = clampf(base + ad_boost + modifier, 1.0, offer_cap)
