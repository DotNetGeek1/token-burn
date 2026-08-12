class_name AscensionSystem
extends RefCounted

## The contract the location is played for.
##
## Every location has exactly one, and it is live from the first prompt of the
## run: the investor states his terms before anything is bought, and the run is
## measured against them from there. There is nothing to qualify for and nothing
## to opt into — the contract IS the level, and the year is its deadline.
##
## Completing it wins the run and opens the next location. Reaching the end of
## the year without it, or going under before then, ends the run.

const STATUS_NONE := ""
## Legacy saves wrote "committed" when the contract was something the player
## opted into part-way through a run. It means the same thing the new status
## does — this run is being played for that contract — so it is still read.
const STATUS_ACTIVE := "active"
const STATUS_LEGACY_ACTIVE := "committed"
const STATUS_COMPLETED := "completed"
const STATUS_FAILED := "failed"

## Rounds a contract has to be finished in, unless it names its own.
const DEFAULT_DEADLINE_ROUNDS := 12


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


## The one contract this run is playing for. Every location has exactly one; the
## alternate finales are retained content and are never a location's contract.
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


## Puts the run under its location's contract. Called once, as the run starts,
## before the first prompt is spent — everything burned from here counts.
func activate(run_state: RunState, content_db: Node) -> bool:
	var contract: Dictionary = location_contract(run_state, content_db)
	if contract.is_empty():
		run_state.ascension = {"status": STATUS_NONE}
		return false
	run_state.ascension = {
		"status": STATUS_ACTIVE,
		"contract_id": str(contract.get("id", "")),
		"baseline_tokens": float(run_state.statistics.get("lifetime_tokens", 0.0)),
		"tokens_burned": 0.0,
		"deadline_round": deadline_round(contract),
		"quality_sum": 0.0,
		"quality_count": 0,
	}
	return true


## The last round the contract can be finished in.
func deadline_round(contract: Dictionary) -> int:
	return maxi(1, int(contract.get("deadline_rounds", DEFAULT_DEADLINE_ROUNDS)))


func is_active(run_state: RunState) -> bool:
	var status: String = str(run_state.ascension.get("status", STATUS_NONE))
	return status == STATUS_ACTIVE or status == STATUS_LEGACY_ACTIVE


func active_contract(run_state: RunState, content_db: Node) -> Dictionary:
	if not is_active(run_state):
		return {}
	return content_db.get_ascension_contract(str(run_state.ascension.get("contract_id", "")))


## The contract the run is (or was) playing for, regardless of whether it is
## still in progress. Used once the run has ended to look up what was attempted.
func current_contract(run_state: RunState, content_db: Node) -> Dictionary:
	var contract_id: String = str(run_state.ascension.get("contract_id", ""))
	if contract_id == "":
		return {}
	return content_db.get_ascension_contract(contract_id)


## The contract cleared: the run is won. The contract stays named in the state so
## the verdict screen can say which one it was.
func record_final(run_state: RunState, _contract: Dictionary) -> void:
	run_state.ascension["status"] = STATUS_COMPLETED


## One prompt against the contract: rolls up what has been burned and reports
## whether that was the prompt that finished it. Failure is not decided here —
## the contract is only lost when the year runs out or the business does, both
## of which are round-boundary events.
func evaluate_prompt(run_state: RunState, content_db: Node) -> Dictionary:
	if not is_active(run_state):
		return {}
	var contract: Dictionary = active_contract(run_state, content_db)
	if contract.is_empty():
		run_state.ascension["status"] = STATUS_NONE
		return {}

	var asc: Dictionary = run_state.ascension
	asc["tokens_burned"] = (
		float(run_state.statistics.get("lifetime_tokens", 0.0))
		- float(asc.get("baseline_tokens", 0.0))
	)

	var messages: Array[String] = []
	var outcome: String = STATUS_NONE
	if float(asc["tokens_burned"]) >= float(contract.get("total_burn", 0.0)):
		if _quality_met(asc, contract):
			outcome = STATUS_COMPLETED
			messages.append("%s: requirement met." % str(contract.get("name", "Contract")))
		else:
			messages.append("Burn requirement met, but the quality bar is not.")

	if outcome != STATUS_NONE:
		asc["status"] = outcome
	run_state.ascension = asc
	return {
		"outcome": outcome,
		"messages": messages,
		"tokens_burned": asc["tokens_burned"],
		"total_burn": float(contract.get("total_burn", 0.0)),
	}


## The year has closed on an unfinished contract, which is the end of the run.
## Reported rather than acted on so the caller can settle the loss its own way.
func fail_on_deadline(run_state: RunState) -> void:
	if not is_active(run_state):
		return
	run_state.ascension["status"] = STATUS_FAILED


func _quality_met(asc: Dictionary, contract: Dictionary) -> bool:
	var required: float = float(contract.get("quality_min", 0.0))
	if required <= 0.0:
		return true
	var count: int = int(asc.get("quality_count", 0))
	if count <= 0:
		return false
	var average: float = float(asc.get("quality_sum", 0.0)) / float(count)
	return average >= required


## Folds a delivered job's quality into the contract's running average, so the
## quality bar is judged on the work actually shipped under it. Callers pass the
## delivered figure — `JobSystem.delivered_quality()` — rather than the raw
## pipeline output, so unfinished delivery and shipped known bugs count against
## the contract exactly as they count against the fee.
func record_job_quality(run_state: RunState, quality: float) -> void:
	if not is_active(run_state):
		return
	run_state.ascension["quality_sum"] = float(run_state.ascension.get("quality_sum", 0.0)) + quality
	run_state.ascension["quality_count"] = int(run_state.ascension.get("quality_count", 0)) + 1


## Average quality of everything delivered under the contract so far, or 0 when
## nothing has shipped yet.
func average_quality(run_state: RunState) -> float:
	var count: int = int(run_state.ascension.get("quality_count", 0))
	if count <= 0:
		return 0.0
	return float(run_state.ascension.get("quality_sum", 0.0)) / float(count)


## Reported for a finished contract as well as a live one: the verdict screen has
## to be able to say how close a run came after the contract has already failed.
func progress(run_state: RunState, content_db: Node) -> Dictionary:
	var contract: Dictionary = current_contract(run_state, content_db)
	if contract.is_empty():
		return {}
	var asc: Dictionary = run_state.ascension
	var total: float = float(contract.get("total_burn", 0.0))
	var burned: float = float(asc.get("tokens_burned", 0.0))
	var deadline: int = int(asc.get("deadline_round", deadline_round(contract)))
	return {
		"contract": contract,
		"tokens_burned": burned,
		"total_burn": total,
		"burn_ratio": 0.0 if total <= 0.0 else clampf(burned / total, 0.0, 1.0),
		"quality_min": float(contract.get("quality_min", 0.0)),
		"quality_average": average_quality(run_state),
		"deadline_round": deadline,
		"rounds_remaining": maxi(0, deadline - int(run_state.calendar.get("round", 1)) + 1),
	}


## Everything a readout needs to say where the run stands against its contract,
## without asking four separate questions or re-deriving any of the rules.
func summary(run_state: RunState, content_db: Node) -> Dictionary:
	var contract: Dictionary = location_contract(run_state, content_db)
	var status: String = str(run_state.ascension.get("status", STATUS_NONE))
	return {
		"location": str(run_state.build.get("dwelling", "")),
		"contract": contract,
		"active": is_active(run_state),
		"completed": status == STATUS_COMPLETED,
		"failed": status == STATUS_FAILED,
		"progress": progress(run_state, content_db),
	}
