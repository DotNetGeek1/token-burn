class_name AscensionSystem
extends RefCounted

## The endgame layer. Surviving the year keeps the lights on; the location's boss
## contract is the way out of it. Qualification checks whether the build is stable
## enough to attempt it; committing starts a Final Burn, in which every prompt is
## measured against the contract's requirements until it is completed, failed, or
## the clock runs out.
##
## Every location has exactly one boss. Completing it wins the run and opens the
## next location; failing it ends the run. There is no ladder inside a run — the
## ladder is the campaign, and it is climbed one run at a time.

const STATUS_NONE := ""
const STATUS_COMMITTED := "committed"
const STATUS_COMPLETED := "completed"
const STATUS_FAILED := "failed"


## Highest infrastructure tier reached by the dwelling or any owned hardware.
## Tiers are additive, not summed: the point is "how advanced is the best
## thing you have", not "how many things have you bought".
func infrastructure_tier(run_state: RunState, content_db: Node) -> int:
	var tiers: Dictionary = content_db.balance.get("economy", {}).get("infrastructure_tiers", {})
	var dwelling_tiers: Dictionary = tiers.get("dwelling", {})
	var hardware_tiers: Dictionary = tiers.get("hardware", {})
	var tier: int = int(dwelling_tiers.get(str(run_state.build.get("dwelling", "bedroom")), 0))
	for hardware_id in Array(run_state.build.get("hardware", [])):
		tier = maxi(tier, int(hardware_tiers.get(str(hardware_id), 0)))
	return tier


## Whether the build is stable enough that walking away from ordinary jobs to
## chase a contract would not immediately end the run. Deliberately separate
## from "can afford" — the player still has to choose to commit.
##
## Clearing the bars latches: a contract does not get harder to reach again
## just because income dipped for one round, and the entry point into the
## endgame must not flicker in and out of the Job Board while the player is
## deciding. `bars_met` still reports the live reading for the progress panel.
func qualification(run_state: RunState, content_db: Node) -> Dictionary:
	var thresholds: Dictionary = qualification_thresholds(run_state, content_db)
	var last_costs: float = float(run_state.economy.get("last_round_costs", 0.0))
	var income: float = float(run_state.economy.get("income", 0.0))
	var income_ratio: float = income / maxf(1.0, last_costs)
	var income_ok: bool = last_costs <= 0.0 or income_ratio >= float(thresholds.get("min_income_ratio", 1.0))
	var peak_rate: float = float(run_state.statistics.get("peak_token_rate", 0.0))
	var peak_ok: bool = peak_rate >= float(thresholds.get("min_peak_token_rate", 0.0))
	var round_ok: bool = int(run_state.calendar.get("round", 1)) >= int(thresholds.get("earliest_round", 1))
	var bars_met: bool = income_ok and peak_ok and round_ok
	if bars_met:
		run_state.flags["ascension_qualified"] = true
	return {
		"qualified": bars_met or bool(run_state.flags.get("ascension_qualified", false)),
		"bars_met": bars_met,
		"income_ok": income_ok,
		"income_ratio": income_ratio,
		"min_income_ratio": float(thresholds.get("min_income_ratio", 1.0)),
		"peak_ok": peak_ok,
		"peak_token_rate": peak_rate,
		"min_peak_token_rate": float(thresholds.get("min_peak_token_rate", 0.0)),
		"round_ok": round_ok,
		"earliest_round": int(thresholds.get("earliest_round", 1)),
	}


## The bars this run has to clear, which belong to the location's boss rather
## than to the game as a whole: a Bedroom run cannot be asked to prove what a
## Warehouse run can. The global block in the content file is the fallback for a
## location with no boss authored yet.
func qualification_thresholds(run_state: RunState, content_db: Node) -> Dictionary:
	var thresholds: Dictionary = Dictionary(content_db.ascension_qualification).duplicate(true)
	var boss: Dictionary = location_contract(run_state, content_db)
	for key in Dictionary(boss.get("qualification", {})).keys():
		thresholds[key] = boss["qualification"][key]
	return thresholds


## The one contract this run is playing for, whether or not it has qualified yet.
## Every location has exactly one; the alternate finales are retained content and
## are never offered as a location's boss.
func location_contract(run_state: RunState, content_db: Node) -> Dictionary:
	var location: String = str(run_state.build.get("dwelling", ""))
	if location == "":
		return {}
	for contract in content_db.ascension_contracts:
		if bool(contract.get("alternate", false)):
			continue
		if str(contract.get("location", "")) == location:
			return Dictionary(contract).duplicate(true)
	return {}


## The boss once it can actually be committed to: the location's contract, gated
## on qualification. Empty means "not yet", not "never".
func boss_contract(run_state: RunState, content_db: Node) -> Dictionary:
	if not bool(qualification(run_state, content_db).get("qualified", false)):
		return {}
	if is_active(run_state):
		return {}
	return location_contract(run_state, content_db)


## Kept as an array so the overlay and the batch policies can keep treating the
## endgame as "whatever is on the table", which is now never more than one thing.
func eligible_contracts(run_state: RunState, content_db: Node) -> Array:
	var boss: Dictionary = boss_contract(run_state, content_db)
	return [] if boss.is_empty() else [boss]


func is_active(run_state: RunState) -> bool:
	return str(run_state.ascension.get("status", STATUS_NONE)) == STATUS_COMMITTED


func active_contract(run_state: RunState, content_db: Node) -> Dictionary:
	if not is_active(run_state):
		return {}
	return content_db.get_ascension_contract(str(run_state.ascension.get("contract_id", "")))


## The contract the run is (or was) attempting, regardless of whether it is
## still in progress. Used once the run has already ended to look up what was
## completed or failed.
func current_contract(run_state: RunState, content_db: Node) -> Dictionary:
	var contract_id: String = str(run_state.ascension.get("contract_id", ""))
	if contract_id == "":
		return {}
	return content_db.get_ascension_contract(contract_id)


## Commits the run to one contract. The Final Burn starts on the prompt after
## this call: every burn from here counts toward the contract, not just
## whatever job happens to be focused.
func commit(run_state: RunState, contract_id: String, content_db: Node) -> bool:
	if is_active(run_state):
		return false
	var contract: Dictionary = content_db.get_ascension_contract(contract_id)
	if contract.is_empty():
		return false
	if not (contract in eligible_contracts(run_state, content_db)):
		return false
	run_state.ascension = {
		"status": STATUS_COMMITTED,
		"contract_id": contract_id,
		"committed_round": int(run_state.calendar.get("round", 1)),
		"baseline_tokens": float(run_state.statistics.get("lifetime_tokens", 0.0)),
		"tokens_burned": 0.0,
		"prompts_remaining": int(contract.get("deadline_prompts", 12)),
		"violations": 0,
		"quality_sum": 0.0,
		"quality_count": 0,
	}
	return true


## The boss cleared: the run is won. The contract stays named in the state so the
## verdict screen can say which one it was, but the status leaves "committed" so
## the tracker stands down and a continued run is not still burning for it.
func record_final(run_state: RunState, _contract: Dictionary) -> void:
	run_state.ascension["status"] = STATUS_COMPLETED


## One prompt of the Final Burn: ages the deadline, checks throughput and heat
## against the contract, and reports whether the contract just completed or
## failed. Called once per prompt while a contract is committed.
func evaluate_prompt(run_state: RunState, content_db: Node) -> Dictionary:
	if not is_active(run_state):
		return {}
	var contract: Dictionary = active_contract(run_state, content_db)
	if contract.is_empty():
		run_state.ascension["status"] = STATUS_NONE
		return {}

	var asc: Dictionary = run_state.ascension
	asc["tokens_burned"] = float(run_state.statistics.get("lifetime_tokens", 0.0)) - float(asc.get("baseline_tokens", 0.0))
	asc["prompts_remaining"] = int(asc.get("prompts_remaining", 0)) - 1

	var prompt_rate: float = float(run_state.compute.get("prompt_rate", run_state.compute.get("token_rate", 0.0)))
	var heat_ratio: float = float(run_state.compute.get("heat", 0.0)) / maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))
	var messages: Array[String] = []
	if prompt_rate > 0.0 and prompt_rate < float(contract.get("min_prompt_rate", 0.0)):
		asc["violations"] = int(asc.get("violations", 0)) + 1
		messages.append("Throughput dipped below the contract's floor.")
	if heat_ratio > float(contract.get("max_heat_pct", 1.0)):
		asc["violations"] = int(asc.get("violations", 0)) + 1
		messages.append("Heat exceeded the contract's ceiling.")

	var hidden_shipped: int = int(run_state.statistics.get("hidden_bugs_shipped", 0))
	var outcome: String = STATUS_NONE
	if hidden_shipped > int(contract.get("max_hidden_bugs", 999999)):
		outcome = STATUS_FAILED
		messages.append("Too many defects shipped under the contract's watch.")
	elif int(asc.get("violations", 0)) > int(contract.get("max_failed_burns", 999999)):
		outcome = STATUS_FAILED
		messages.append("The contract collapsed under repeated failures.")
	elif float(asc.get("tokens_burned", 0.0)) >= float(contract.get("total_burn", 0.0)):
		var quality_ok: bool = _quality_met(asc, contract)
		if quality_ok:
			outcome = STATUS_COMPLETED
			messages.append("%s: requirement met." % str(contract.get("name", "Contract")))
		else:
			messages.append("Burn requirement met, but quality is not there yet.")
	elif int(asc.get("prompts_remaining", 0)) < 0:
		outcome = STATUS_FAILED
		messages.append("The deadline passed before the burn requirement was met.")

	if outcome != STATUS_NONE:
		asc["status"] = outcome
	run_state.ascension = asc
	return {
		"outcome": outcome,
		"messages": messages,
		"tokens_burned": asc["tokens_burned"],
		"total_burn": float(contract.get("total_burn", 0.0)),
		"prompts_remaining": asc["prompts_remaining"],
		"violations": asc["violations"],
	}


func _quality_met(asc: Dictionary, contract: Dictionary) -> bool:
	var required: float = float(contract.get("quality_min", 0.0))
	if required <= 0.0:
		return true
	var count: int = int(asc.get("quality_count", 0))
	if count <= 0:
		return false
	var average: float = float(asc.get("quality_sum", 0.0)) / float(count)
	return average >= required


## Folds a delivered job's quality into the contract's running average. Called
## whenever a job completes while a contract is committed, so the finale's
## "support contracts" still count toward the quality bar.
func record_job_quality(run_state: RunState, quality: float) -> void:
	if not is_active(run_state):
		return
	run_state.ascension["quality_sum"] = float(run_state.ascension.get("quality_sum", 0.0)) + quality
	run_state.ascension["quality_count"] = int(run_state.ascension.get("quality_count", 0)) + 1


func progress(run_state: RunState, content_db: Node) -> Dictionary:
	if not is_active(run_state):
		return {}
	var contract: Dictionary = active_contract(run_state, content_db)
	var asc: Dictionary = run_state.ascension
	return {
		"contract": contract,
		"tokens_burned": float(asc.get("tokens_burned", 0.0)),
		"total_burn": float(contract.get("total_burn", 0.0)),
		"prompts_remaining": int(asc.get("prompts_remaining", 0)),
		"violations": int(asc.get("violations", 0)),
		"max_failed_burns": int(contract.get("max_failed_burns", 0)),
		"hidden_bugs_shipped": int(run_state.statistics.get("hidden_bugs_shipped", 0)),
		"max_hidden_bugs": int(contract.get("max_hidden_bugs", 0)),
	}


## Everything a readout needs to say where the run stands against its boss,
## without asking four separate questions or re-deriving any of the rules.
func summary(run_state: RunState, content_db: Node) -> Dictionary:
	var contract: Dictionary = location_contract(run_state, content_db)
	var q: Dictionary = qualification(run_state, content_db)
	var requirements: Array = [
		{"label": "Round", "met": bool(q.get("round_ok", false))},
		{"label": "Peak throughput", "met": bool(q.get("peak_ok", false))},
		{"label": "Income vs costs", "met": bool(q.get("income_ok", false))},
	]
	var met: int = 0
	for requirement in requirements:
		if bool(requirement["met"]):
			met += 1
	return {
		"location": str(run_state.build.get("dwelling", "")),
		"contract": contract,
		"qualification": q,
		"requirements": requirements,
		"requirements_met": met,
		"requirements_total": requirements.size(),
		"qualified": bool(q.get("qualified", false)),
		"committed": is_active(run_state),
		"completed": str(run_state.ascension.get("status", STATUS_NONE)) == STATUS_COMPLETED,
		"progress": progress(run_state, content_db),
	}
