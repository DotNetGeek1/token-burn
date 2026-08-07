class_name AscensionSystem
extends RefCounted

## The endgame layer, and the run's level-up track. Surviving the year keeps the
## lights on; Ascension Contracts are the ladder out of it. Qualification checks
## whether the build is stable enough to attempt one; committing starts a Final
## Burn, in which every prompt is measured against the contract's requirements
## until it is completed, failed, or the clock runs out.
##
## Contracts come in three tiers and are climbed one rung at a time. Tiers 1 and
## 2 are level-ups: completing one pays out its picks as an in-run reward draft
## and hands the run back, with the next tier now on the table. Only a Tier 3
## contract is the finish line, which is why a run no longer ends the first time
## a contract clears.

const STATUS_NONE := ""
const STATUS_COMMITTED := "committed"
const STATUS_COMPLETED := "completed"
const STATUS_FAILED := "failed"

## The top of the ladder. A contract at this tier beats the game; anything below
## it is a rung on the way there.
const FINAL_TIER := 3


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
	var thresholds: Dictionary = content_db.ascension_qualification
	var last_costs: float = float(run_state.economy.get("last_round_costs", 0.0))
	var income: float = float(run_state.economy.get("income", 0.0))
	var income_ratio: float = income / maxf(1.0, last_costs)
	var income_ok: bool = last_costs <= 0.0 or income_ratio >= float(thresholds.get("min_income_ratio", 1.0))
	var peak_rate: float = float(run_state.statistics.get("peak_token_rate", 0.0))
	var peak_ok: bool = peak_rate >= float(thresholds.get("min_peak_token_rate", 0.0))
	var tier: int = infrastructure_tier(run_state, content_db)
	var infra_ok: bool = tier >= int(thresholds.get("min_infrastructure_tier", 0))
	var round_ok: bool = int(run_state.calendar.get("round", 1)) >= int(thresholds.get("earliest_round", 1))
	var bars_met: bool = income_ok and peak_ok and infra_ok and round_ok
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
		"infra_ok": infra_ok,
		"infrastructure_tier": tier,
		"min_infrastructure_tier": int(thresholds.get("min_infrastructure_tier", 0)),
		"round_ok": round_ok,
		"earliest_round": int(thresholds.get("earliest_round", 1)),
	}


## The highest contract tier this run has already completed. Zero means the run
## is still on the first rung.
func highest_tier_completed(run_state: RunState) -> int:
	return int(run_state.ascension.get("highest_tier_completed", 0))


## The rung the run is on now: one above whatever it has finished, and never past
## the top. Clamping at the top is what keeps the remaining Tier 3 endings on the
## table once one of them has already been beaten, which is the whole point of
## carrying a won run on into endless.
func current_rung(run_state: RunState) -> int:
	return mini(FINAL_TIER, highest_tier_completed(run_state) + 1)


func is_final_contract(contract: Dictionary) -> bool:
	return int(contract.get("tier", 1)) >= FINAL_TIER


func completed_contract_ids(run_state: RunState) -> Array:
	return Array(run_state.ascension.get("completed_ids", []))


## Everything the UI needs to say where the run is on the ladder without asking
## four separate questions.
func ladder(run_state: RunState) -> Dictionary:
	return {
		"rung": current_rung(run_state),
		"total": FINAL_TIER,
		"highest_tier_completed": highest_tier_completed(run_state),
		"completed_ids": completed_contract_ids(run_state),
		"pending_picks": int(run_state.ascension.get("pending_picks", 0)),
	}


## Contracts the current build could actually attempt: qualification cleared at
## some point, the contract's own infrastructure tier met now, and the contract
## on the rung the run has actually reached. A run cannot skip to the finale, and
## cannot climb the same rung twice.
func eligible_contracts(run_state: RunState, content_db: Node) -> Array:
	if not bool(qualification(run_state, content_db).get("qualified", false)):
		return []
	var tier: int = infrastructure_tier(run_state, content_db)
	var rung: int = current_rung(run_state)
	var completed: Array = completed_contract_ids(run_state)
	var eligible: Array = []
	for contract in content_db.ascension_contracts:
		if int(contract.get("tier", 1)) != rung:
			continue
		if str(contract.get("id", "")) in completed:
			continue
		if int(contract.get("required_infrastructure_tier", 0)) <= tier:
			eligible.append(Dictionary(contract).duplicate(true))
	return eligible


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
	# The ladder outlives any one contract, so committing resets the Final Burn's
	# counters without forgetting which rungs the run has already climbed or what
	# it is still owed for climbing them.
	run_state.ascension = _with_ladder(run_state, {
		"status": STATUS_COMMITTED,
		"contract_id": contract_id,
		"committed_round": int(run_state.calendar.get("round", 1)),
		"baseline_tokens": float(run_state.statistics.get("lifetime_tokens", 0.0)),
		"tokens_burned": 0.0,
		"prompts_remaining": int(contract.get("deadline_prompts", 12)),
		"violations": 0,
		"quality_sum": 0.0,
		"quality_count": 0,
	})
	return true


func _with_ladder(run_state: RunState, fields: Dictionary) -> Dictionary:
	var merged: Dictionary = fields.duplicate(true)
	merged["completed_ids"] = completed_contract_ids(run_state)
	merged["highest_tier_completed"] = highest_tier_completed(run_state)
	merged["pending_picks"] = int(run_state.ascension.get("pending_picks", 0))
	return merged


## A Tier 1 or 2 contract clearing: the rung is banked, the contract's picks are
## added to what the run is owed, and the Final Burn state is wound back to idle
## so the next rung can be committed to. The run carries on.
func complete_rung(run_state: RunState, contract: Dictionary) -> void:
	var completed: Array = completed_contract_ids(run_state)
	var contract_id: String = str(contract.get("id", ""))
	if contract_id != "" and not (contract_id in completed):
		completed.append(contract_id)
	var picks: int = maxi(0, int(contract.get("picks", 1)))
	run_state.ascension = {
		"status": STATUS_NONE,
		"contract_id": "",
		"committed_round": 0,
		"baseline_tokens": 0.0,
		"tokens_burned": 0.0,
		"prompts_remaining": 0,
		"violations": 0,
		"quality_sum": 0.0,
		"quality_count": 0,
		"completed_ids": completed,
		"highest_tier_completed": maxi(
			highest_tier_completed(run_state), int(contract.get("tier", 1))
		),
		"pending_picks": int(run_state.ascension.get("pending_picks", 0)) + picks,
	}


## A Tier 3 contract clearing: the run is won. The contract stays named in the
## state so the verdict screen can say which ending was reached, but the status
## leaves "committed" so the tracker stands down and a continued run can reach for
## one of the other endings.
func record_final(run_state: RunState, contract: Dictionary) -> void:
	var completed: Array = completed_contract_ids(run_state)
	var contract_id: String = str(contract.get("id", ""))
	if contract_id != "" and not (contract_id in completed):
		completed.append(contract_id)
	run_state.ascension["completed_ids"] = completed
	run_state.ascension["highest_tier_completed"] = maxi(
		highest_tier_completed(run_state), int(contract.get("tier", 1))
	)
	run_state.ascension["status"] = STATUS_COMPLETED


## Reward picks the run has earned from rungs and not yet spent.
func pending_picks(run_state: RunState) -> int:
	return maxi(0, int(run_state.ascension.get("pending_picks", 0)))


func set_pending_picks(run_state: RunState, value: int) -> void:
	run_state.ascension["pending_picks"] = maxi(0, value)


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
		"rung": int(contract.get("tier", 1)),
		"rungs": FINAL_TIER,
		"is_final": is_final_contract(contract),
	}
