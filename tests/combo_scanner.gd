class_name ComboScanner
extends RefCounted

const OUTLIER_WIN_RATE := 0.95
const OUTLIER_TOKEN_RATE := 1_000_000_000.0


func scan_pairings(perks: Array[PerkDefinition], sample_runs: int = 20) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for i in range(perks.size()):
		for j in range(i + 1, perks.size()):
			var summary: Dictionary = _simulate_with_perks([perks[i].id, perks[j].id], sample_runs)
			if _is_outlier(summary):
				results.append({
					"combo": [perks[i].id, perks[j].id],
					"win_rate": summary.get("win_rate", 0.0),
					"avg_peak_token_rate": summary.get("avg_peak_token_rate", 0.0),
				})
	return results


func _simulate_with_perks(perk_ids: Array, runs: int) -> Dictionary:
	var runner := BatchRunner.new()
	var wins: int = 0
	var peak_rates: Array[float] = []
	for i in range(runs):
		var sim_script: GDScript = load("res://core/simulation.gd")
		var sim: Node = sim_script.new()
		sim.autosave_enabled = false
		if ContentDatabase.jobs.is_empty():
			ContentDatabase.reload()
		sim.start_run(5000 + i)
		for perk_id in perk_ids:
			sim.run_state.build["perks"].append(perk_id)
		sim._invalidate_subscriptions()
		var safety: int = 0
		while sim.phase != sim.Phase.RUN_END and safety < 300:
			safety += 1
			runner._play_policy_step(sim, "greedy")
		if sim.run_state.flags.get("victory", false):
			wins += 1
		peak_rates.append(float(sim.run_state.statistics.get("peak_token_rate", 0.0)))
		sim.free()
	return {
		"win_rate": float(wins) / float(maxi(runs, 1)),
		"avg_peak_token_rate": runner._average(peak_rates),
	}


func _is_outlier(summary: Dictionary) -> bool:
	return float(summary.get("win_rate", 0.0)) >= OUTLIER_WIN_RATE or float(summary.get("avg_peak_token_rate", 0.0)) >= OUTLIER_TOKEN_RATE
