class_name RunScore
extends RefCounted

## Turns a finished run's raw statistics into the debrief scoreboard. Cash was
## always the means; this is the accounting of the actual achievement.


static func compute(run_state: RunState, content_db: Node) -> Dictionary:
	var stats: Dictionary = run_state.statistics
	var lifetime_tokens: float = float(stats.get("lifetime_tokens", 0.0))
	var ascension_system := AscensionSystem.new()
	return {
		"total_tokens_burned": lifetime_tokens,
		"comparison": NumberFormat.comparison(lifetime_tokens, content_db.comparisons),
		"peak_prompt_tokens": float(stats.get("peak_prompt_tokens", 0.0)),
		"peak_token_rate": float(stats.get("peak_token_rate", 0.0)),
		"completed_jobs": int(stats.get("completed_jobs", 0)),
		"failed_jobs": int(stats.get("failed_jobs", 0)),
		"hidden_bugs_shipped": int(stats.get("hidden_bugs_shipped", 0)),
		"infrastructure_tier": ascension_system.infrastructure_tier(run_state, content_db),
		"peak_cash": float(stats.get("peak_cash", 0.0)),
		"rounds_survived": int(run_state.calendar.get("round", 1)),
		"outcome": str(run_state.flags.get("outcome", "")),
		"ascension_tier": int(run_state.flags.get("ascension_tier", 0)),
		"contract_name": _contract_name(run_state, content_db),
	}


static func _contract_name(run_state: RunState, content_db: Node) -> String:
	var contract_id: String = str(run_state.ascension.get("contract_id", ""))
	if contract_id == "":
		return ""
	return str(content_db.get_ascension_contract(contract_id).get("name", ""))


## Headline text for the debrief: the one number the whole run was for.
static func headline(score: Dictionary) -> String:
	return "TOTAL TOKENS BURNED: %s" % NumberFormat.format_tokens(float(score.get("total_tokens_burned", 0.0)))


static func rows(score: Dictionary) -> Array:
	var result: Array = [
		{"label": "Peak burn in one prompt", "value": NumberFormat.format_tokens(float(score.get("peak_prompt_tokens", 0.0)))},
		{"label": "Peak sustained throughput", "value": NumberFormat.format_token_rate(float(score.get("peak_token_rate", 0.0)))},
		{"label": "Contracts completed", "value": str(int(score.get("completed_jobs", 0)))},
		{"label": "Contracts failed", "value": str(int(score.get("failed_jobs", 0)))},
		{"label": "Infrastructure tier", "value": "Tier %d" % int(score.get("infrastructure_tier", 0))},
		{"label": "Hidden bugs shipped", "value": str(int(score.get("hidden_bugs_shipped", 0)))},
		{"label": "Peak cash", "value": NumberFormat.format_cash(float(score.get("peak_cash", 0.0)))},
		{"label": "Rounds survived", "value": str(int(score.get("rounds_survived", 1)))},
	]
	return result
