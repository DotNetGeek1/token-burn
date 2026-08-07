class_name DemandSystem
extends RefCounted


func refresh_demand(run_state: RunState) -> void:
	var base: float = 2.0 + float(run_state.business.get("reputation", 0.0)) * 0.05
	var ad_boost: float = float(run_state.business.get("advertising", 0.0)) * 0.002
	var modifier: float = float(run_state.business.get("demand_modifier", 0.0))
	run_state.business["demand"] = clampf(base + ad_boost + modifier, 1.0, 8.0)
