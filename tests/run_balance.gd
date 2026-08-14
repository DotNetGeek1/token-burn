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
	for profile in profiles:
		var runner := BatchRunner.new()
		runner.verbose = true
		var summary: Dictionary = runner.run_campaign(
			runs, "builder", str(profile), difficulty, seed_start
		)
		_print_summary(summary)
	print("=".repeat(48))
	get_tree().quit()


func _print_summary(summary: Dictionary) -> void:
	print("Profile %s / %s -- %d run(s), outcomes %s" % [
		str(summary.get("profile", "")),
		str(summary.get("difficulty", "")),
		int(summary.get("runs", 0)),
		BatchRunner.describe_outcomes(summary),
	])
	var order: Array = Array(ContentDatabase.balance.get("economy", {}).get("location_order", []))
	for location in order:
		var chapter: Dictionary = Dictionary(summary.get("chapters", {}).get(str(location), {}))
		if chapter.is_empty():
			continue
		print("  %s: win %.0f%%, round median %.1f / mean %.1f, boss %.0f%% / quality %.0f, %.1f burns/job, one-burn %.0f%%, %.1f prompts/round, cool %.0f%%, peak heat %.0f%%, forecasts %d, fires %d, rate %.1f, cash %.1f, outcomes %s, hardware %s" % [
			str(location),
			float(chapter.get("win_rate", 0.0)) * 100.0,
			float(chapter.get("median_victory_round", 0.0)),
			float(chapter.get("avg_victory_round", 0.0)),
			float(chapter.get("avg_ascension_burn_ratio", 0.0)) * 100.0,
			float(chapter.get("avg_ascension_quality", 0.0)),
			float(chapter.get("avg_burns_per_completed_job", 0.0)),
			float(chapter.get("one_burn_job_rate", 0.0)) * 100.0,
			float(chapter.get("prompts_per_round", 0.0)),
			float(chapter.get("cooling_share", 0.0)) * 100.0,
			float(chapter.get("peak_heat_ratio", 0.0)) * 100.0,
			int(chapter.get("dangerous_forecasts", 0)),
			int(chapter.get("fires", 0)),
			float(chapter.get("avg_peak_token_rate", 0.0)),
			float(chapter.get("avg_peak_cash", 0.0)),
			str(chapter.get("outcomes", {})),
			str(chapter.get("avg_hardware_acquisition_round", {})),
		])
	if bool(summary.get("accepted", false)):
		print("  ACCEPTED")
	else:
		print("  REJECTED: %s" % "; ".join(summary.get("acceptance_failures", [])))
