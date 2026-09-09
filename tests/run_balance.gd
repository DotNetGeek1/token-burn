extends Node

## Configurable campaign balance sweep, intentionally separate from the fast
## correctness suite. Usage:
##   godot --headless --path . res://tests/run_balance.tscn -- --runs=50
##   godot --headless --path . res://tests/run_balance.tscn -- --runs=2 --profiles=fresh,veteran


func _ready() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var targets: Dictionary = ContentDatabase.balance.get("pacing_targets", {})
	var runs: int = int(targets.get("full_sweep_runs", 50))
	var profiles: PackedStringArray = ["fresh", "established", "veteran"]
	var difficulty: String = "normal"
	var seed_start: int = 1000
	for arg in OS.get_cmdline_user_args():
		var value: String = str(arg)
		if value.begins_with("--runs="):
			runs = maxi(1, int(value.trim_prefix("--runs=")))
		elif value.begins_with("--profiles="):
			profiles = PackedStringArray(value.trim_prefix("--profiles=").split(",", false))
		elif value.begins_with("--difficulty="):
			difficulty = value.trim_prefix("--difficulty=")
		elif value.begins_with("--seed="):
			seed_start = int(value.trim_prefix("--seed="))

	print("Token Burn -- campaign balance sweep")
	print("=".repeat(48))
	var accepted: bool = true
	for profile in profiles:
		var runner := BatchRunner.new()
		runner.verbose = true
		var summary: Dictionary = runner.run_campaign(
			runs, "builder", str(profile), difficulty, seed_start
		)
		_print_summary(summary)
		accepted = accepted and bool(summary.get("accepted", false))
	print("=".repeat(48))
	get_tree().quit(0 if accepted else 1)


func _print_summary(summary: Dictionary) -> void:
	print("Profile %s / %s -- %d run(s), outcomes %s" % [
		str(summary.get("profile", "")),
		str(summary.get("difficulty", "")),
		int(summary.get("runs", 0)),
		BatchRunner.describe_outcomes(summary),
	])
	for tier in range(InfrastructureSystem.max_tier() + 1):
		var tier_summary: Dictionary = Dictionary(summary.get("tiers", {}).get(str(tier), {}))
		if tier_summary.is_empty():
			continue
		print("  tier %d: win %.0f%%, round median %.1f / mean %.1f, target %.0f%% / quality %.0f, %.1f burns/job, one-burn %.0f%%, %.1f prompts/round, cool %.0f%%, peak heat %.0f%%, forecasts %d, fires %d, rate %.1f, cash %.1f, outcomes %s, hardware %s" % [
			tier,
			float(tier_summary.get("win_rate", 0.0)) * 100.0,
			float(tier_summary.get("median_victory_round", 0.0)),
			float(tier_summary.get("avg_victory_round", 0.0)),
			float(tier_summary.get("avg_ascension_burn_ratio", 0.0)) * 100.0,
			float(tier_summary.get("avg_ascension_quality", 0.0)),
			float(tier_summary.get("avg_burns_per_completed_job", 0.0)),
			float(tier_summary.get("one_burn_job_rate", 0.0)) * 100.0,
			float(tier_summary.get("prompts_per_round", 0.0)),
			float(tier_summary.get("cooling_share", 0.0)) * 100.0,
			float(tier_summary.get("peak_heat_ratio", 0.0)) * 100.0,
			int(tier_summary.get("dangerous_forecasts", 0)),
			int(tier_summary.get("fires", 0)),
			float(tier_summary.get("avg_peak_token_rate", 0.0)),
			float(tier_summary.get("avg_peak_cash", 0.0)),
			str(tier_summary.get("outcomes", {})),
			str(tier_summary.get("avg_hardware_acquisition_round", {})),
		])
	if bool(summary.get("accepted", false)):
		print("  ACCEPTED")
	else:
		print("  REJECTED: %s" % "; ".join(summary.get("acceptance_failures", [])))
