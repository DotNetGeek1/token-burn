class_name ProgressionSystem
extends RefCounted


func check_loss(run_state: RunState) -> bool:
	if float(run_state.economy.get("cash", 0.0)) <= -5000.0 or float(run_state.economy.get("debt", 0.0)) > 50000.0:
		run_state.flags["loss_reason"] = "Bankruptcy"
		return true
	if int(run_state.economy.get("rent_unpaid_streak", 0)) >= 2:
		run_state.flags["loss_reason"] = "Eviction"
		return true
	if run_state.flags.get("fire_risk", false) and float(run_state.compute.get("heat", 0.0)) >= float(run_state.compute.get("heat_capacity", 100.0)):
		run_state.flags["loss_reason"] = "Hardware fire"
		return true
	if float(run_state.business.get("reputation", 0.0)) <= -5.0:
		run_state.flags["loss_reason"] = "Reputation collapse"
		return true
	return false
