class_name InvestorProgression
extends RefCounted

## The investor's ladder: one continuous run measured against a sequence of
## targets, one per Investor Level. Level 1 is live from the first prompt;
## completing a target advances the level and activates the next one on the
## same calendar — nothing resets, nothing moves, the terms simply get bigger.
## The target marked `final` is the win. Past it the ladder is Deep Burn's.
##
## `run_state.investor` is the only gameplay progression authority: `level`
## is what difficulty, economy pressure and content gates key off. State keeps
## the old contract field names (`status`, `contract_id`, `baseline_tokens`,
## `tokens_burned`, `deadline_round`, `quality_sum`, `quality_count`) and adds
## `level`, `targets_completed`, `max_heat_ratio`, `catastrophes`,
## `profit_baseline` for the optional conditions a target may carry.
##
## Owned by Simulation as `_investor`. Stateless: everything lives on the run.

const STATUS_NONE := ""
## Legacy saves wrote "committed" when the contract was something the player
## opted into part-way through a run. It means the same thing the new status
## does — this run is being played for that target — so it is still read.
const STATUS_ACTIVE := "active"
const STATUS_LEGACY_ACTIVE := "committed"
const STATUS_COMPLETED := "completed"
const STATUS_FAILED := "failed"

## Rounds a target has to be finished in, unless it (or the curve) names its own.
const DEFAULT_DEADLINE_ROUNDS := 12
const FIRST_LEVEL := 1
## Ids for targets past the authored list.
const GENERATED_ID_PREFIX := "investor.generated."


# --- Content -----------------------------------------------------------------

## Every authored target, alternates included.
static func targets(content_db: Node = null) -> Array:
	var db: Node = content_db if content_db != null else ContentDatabase
	var stored: Variant = db.get("investor_targets")
	return Array(stored) if stored is Array else []


static func curves(content_db: Node = null) -> Dictionary:
	var db: Node = content_db if content_db != null else ContentDatabase
	return Dictionary(Dictionary(db.balance).get("investor_targets", {}))


## The authored target for a level, or empty when the list is shorter than that.
static func authored_target_for_level(level: int, content_db: Node = null) -> Dictionary:
	for target in targets(content_db):
		if not target is Dictionary or bool(target.get("alternate", false)):
			continue
		if int(target.get("level", 0)) == level:
			return Dictionary(target).duplicate(true)
	return {}


## The highest level the authored list reaches.
static func max_authored_level(content_db: Node = null) -> int:
	var top: int = 0
	for target in targets(content_db):
		if target is Dictionary and not bool(target.get("alternate", false)):
			top = maxi(top, int(target.get("level", 0)))
	return top


## The target whose completion is the win. Falls back to the highest authored
## level when nothing is marked, so the game always has an end.
static func final_target(content_db: Node = null) -> Dictionary:
	for target in targets(content_db):
		if target is Dictionary and bool(target.get("final", false)) and not bool(target.get("alternate", false)):
			return Dictionary(target).duplicate(true)
	return authored_target_for_level(max_authored_level(content_db), content_db)


static func final_level(content_db: Node = null) -> int:
	return int(final_target(content_db).get("level", max_authored_level(content_db)))


## The target for a level: authored if present, otherwise generated from the
## curves in `balance.investor_targets` off the last authored target. Deep
## Burn uses the generated tail to attach conditions to its escalated need.
static func target_for_level(level: int, content_db: Node = null) -> Dictionary:
	var authored: Dictionary = authored_target_for_level(level, content_db)
	if not authored.is_empty():
		return authored
	return generate_target(level, content_db)


static func generate_target(level: int, content_db: Node = null) -> Dictionary:
	var curve: Dictionary = curves(content_db)
	var top_level: int = max_authored_level(content_db)
	var base: Dictionary = authored_target_for_level(top_level, content_db)
	var steps: int = maxi(1, level - maxi(top_level, 0))
	var growth: float = maxf(1.0, float(curve.get("token_growth", 5.0)))
	var quality_step: float = float(curve.get("quality_step", 3.0))
	var quality_cap: float = float(curve.get("quality_cap", 90.0))
	var total_burn: float = float(base.get("total_burn", 25000000000000.0)) * pow(growth, float(steps))
	var quality_min: float = minf(quality_cap, float(base.get("quality_min", 45.0)) + quality_step * float(steps))
	var archetype: Dictionary = _archetype_for_level(level, curve)
	var target: Dictionary = {
		"id": "%s%d" % [GENERATED_ID_PREFIX, level],
		"name": "Target %d" % level,
		"level": level,
		"archetype": str(archetype.get("id", "volume")),
		"generated": true,
		"final": false,
		"tier": int(base.get("tier", 3)),
		"flavour": "The investor's next figure. He did not explain where it came from.",
		"burn_label": NumberFormat.format(total_burn),
		"total_burn": total_burn,
		"quality_min": quality_min,
		"deadline_rounds": int(curve.get("deadline_rounds", DEFAULT_DEADLINE_ROUNDS)),
		"picks": int(base.get("picks", 1)),
		"unlocks_age": false,
		"ending_unlock": "",
	}
	if archetype.has("max_heat_ratio"):
		target["max_heat_ratio"] = float(archetype["max_heat_ratio"])
	if bool(archetype.get("no_catastrophe", false)):
		target["no_catastrophe"] = true
	if archetype.has("min_profit"):
		target["min_profit"] = float(archetype["min_profit"])
	return target


## Weighted archetype, chosen deterministically by level so the same level
## always generates the same target: the weights lay the archetypes out on a
## wheel and the level walks round it.
static func _archetype_for_level(level: int, curve: Dictionary) -> Dictionary:
	var archetypes: Array = Array(curve.get("archetypes", []))
	if archetypes.is_empty():
		return {"id": "volume"}
	var total: int = 0
	for archetype in archetypes:
		if archetype is Dictionary:
			total += maxi(0, int(archetype.get("weight", 1)))
	if total <= 0:
		return Dictionary(archetypes[0]) if archetypes[0] is Dictionary else {"id": "volume"}
	var pick: int = posmod(level * 7 + 3, total)
	for archetype in archetypes:
		if not archetype is Dictionary:
			continue
		pick -= maxi(0, int(archetype.get("weight", 1)))
		if pick < 0:
			return archetype
	return Dictionary(archetypes[-1]) if archetypes[-1] is Dictionary else {"id": "volume"}


## The economy pressure hooks, indexed by level - 1 with the last entry
## repeating. Both curves ship at 1.0; Workstream C wires them into rent and
## job rewards.
static func rent_multiplier(level: int, content_db: Node = null) -> float:
	return pressure(content_db, "rent_mult_by_level", level)


static func reward_multiplier(level: int, content_db: Node = null) -> float:
	return pressure(content_db, "reward_mult_by_level", level)


## One investor pressure curve read for a level: `investor_targets.<key>`
## indexed by `level - 1`, clamped so the last entry extends past the end of
## the authored table. 1.0 when the curve is missing or empty.
static func pressure(content_db: Node, key: String, level: int) -> float:
	var table: Array = Array(curves(content_db).get(key, []))
	if table.is_empty():
		return 1.0
	return float(table[clampi(level - 1, 0, table.size() - 1)])


# --- Run state ---------------------------------------------------------------

static func default_state() -> Dictionary:
	return {
		"status": STATUS_NONE,
		"contract_id": "",
		"level": FIRST_LEVEL,
		"targets_completed": 0,
		"baseline_tokens": 0.0,
		"tokens_burned": 0.0,
		"deadline_round": 0,
		"quality_sum": 0.0,
		"quality_count": 0,
		"max_heat_ratio": 0.0,
		"catastrophes": 0,
		"in_catastrophe": false,
		"profit_baseline": 0.0,
	}


## The run's Investor Level, 1-based.
func level(run_state: RunState) -> int:
	return maxi(FIRST_LEVEL, int(run_state.investor.get("level", FIRST_LEVEL)))


func targets_completed(run_state: RunState) -> int:
	return maxi(0, int(run_state.investor.get("targets_completed", 0)))


## Puts the run under the target for `new_level`, measured from where the run
## stands right now: tokens from here, quality from here, the deadline
## `deadline_rounds` from the current round on the continuous calendar. Nothing
## else on the run moves.
func activate_level(run_state: RunState, new_level: int, content_db: Node = null) -> bool:
	var target: Dictionary = target_for_level(new_level, content_db)
	var completed: int = targets_completed(run_state)
	if target.is_empty():
		run_state.investor = default_state()
		run_state.investor["level"] = new_level
		run_state.investor["targets_completed"] = completed
		return false
	var current_round: int = int(run_state.calendar.get("round", 1))
	run_state.investor = {
		"status": STATUS_ACTIVE,
		"contract_id": str(target.get("id", "")),
		"level": new_level,
		"targets_completed": completed,
		"baseline_tokens": float(run_state.statistics.get("lifetime_tokens", 0.0)),
		"tokens_burned": 0.0,
		"deadline_round": current_round + deadline_rounds_for(target) - 1,
		"quality_sum": 0.0,
		"quality_count": 0,
		"max_heat_ratio": 0.0,
		"catastrophes": 0,
		"in_catastrophe": false,
		"profit_baseline": float(run_state.economy.get("cash", 0.0)),
	}
	return true


## The target is done: the level goes up by one and the next target goes live.
func advance(run_state: RunState, content_db: Node = null) -> bool:
	var next_level: int = level(run_state) + 1
	run_state.investor["targets_completed"] = targets_completed(run_state) + 1
	return activate_level(run_state, next_level, content_db)


## Puts the run under the target for whatever level it is on (a fresh run's
## level 1), measured from where it stands now.
func activate(run_state: RunState, content_db: Node = null) -> bool:
	return activate_level(run_state, level(run_state), content_db)


## Rounds the target allows from activation.
static func deadline_rounds_for(target: Dictionary) -> int:
	return maxi(1, int(target.get("deadline_rounds", DEFAULT_DEADLINE_ROUNDS)))


## The last round the live target can be finished in, on the run's calendar.
## A run whose target was activated before deadlines were absolute reads its
## authored length from round one, which is what those saves meant.
func deadline_round(run_state: RunState, target: Dictionary = {}) -> int:
	var stored: int = int(run_state.investor.get("deadline_round", 0))
	if stored > 0:
		return stored
	var resolved: Dictionary = target if not target.is_empty() else current_target(run_state)
	return deadline_rounds_for(resolved)


func is_active(run_state: RunState) -> bool:
	var status: String = str(run_state.investor.get("status", STATUS_NONE))
	return status == STATUS_ACTIVE or status == STATUS_LEGACY_ACTIVE


## The target the run is playing for right now, empty when none is live.
func active_target(run_state: RunState, content_db: Node = null) -> Dictionary:
	if not is_active(run_state):
		return {}
	return current_target(run_state, content_db)


## The target the run is (or was) playing for, regardless of whether it is
## still in progress: the verdict screen has to name what was attempted.
func current_target(run_state: RunState, content_db: Node = null) -> Dictionary:
	var contract_id: String = str(run_state.investor.get("contract_id", ""))
	if contract_id != "":
		var authored: Dictionary = _target_by_id(contract_id, content_db)
		if not authored.is_empty():
			return authored
		if contract_id.begins_with(GENERATED_ID_PREFIX):
			return generate_target(level(run_state), content_db)
	return target_for_level(level(run_state), content_db)


static func _target_by_id(target_id: String, content_db: Node = null) -> Dictionary:
	for target in targets(content_db):
		if target is Dictionary and str(target.get("id", "")) == target_id:
			return Dictionary(target).duplicate(true)
	return {}


## Whether the run's live target is the one whose completion wins the game.
func is_final_target(run_state: RunState, content_db: Node = null) -> bool:
	return bool(current_target(run_state, content_db).get("final", false))


## The target cleared. The target stays named in the state so the verdict
## screen can say which one it was; `advance` is what moves on.
func record_final(run_state: RunState, _target: Dictionary) -> void:
	run_state.investor["status"] = STATUS_COMPLETED


## A catastrophe under the live target, for targets that forbid one.
func record_catastrophe(run_state: RunState) -> void:
	if not is_active(run_state):
		return
	run_state.investor["catastrophes"] = int(run_state.investor.get("catastrophes", 0)) + 1


## One prompt against the target: rolls up what has been burned, tracks the
## heat ceiling, and reports whether that was the prompt that finished it.
## Failure is not decided here — the target is only lost when its deadline
## passes or the business does, both round-boundary events.
func evaluate_prompt(run_state: RunState, content_db: Node = null) -> Dictionary:
	if not is_active(run_state):
		return {}
	var target: Dictionary = active_target(run_state, content_db)
	if target.is_empty():
		run_state.investor["status"] = STATUS_NONE
		return {}

	var inv: Dictionary = run_state.investor
	inv["tokens_burned"] = (
		float(run_state.statistics.get("lifetime_tokens", 0.0))
		- float(inv.get("baseline_tokens", 0.0))
	)
	var capacity: float = maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))
	var heat_ratio: float = float(run_state.compute.get("heat", 0.0)) / capacity
	inv["max_heat_ratio"] = maxf(float(inv.get("max_heat_ratio", 0.0)), heat_ratio)
	# A catastrophe is the rig crossing the catastrophe line; counted once per
	# excursion, not once per prompt spent above it.
	var over_line: bool = heat_ratio >= HeatSystem.catastrophe_ratio(HeatSystem.work_tier(run_state))
	if over_line and not bool(inv.get("in_catastrophe", false)):
		inv["catastrophes"] = int(inv.get("catastrophes", 0)) + 1
	inv["in_catastrophe"] = over_line

	var messages: Array[String] = []
	var outcome: String = STATUS_NONE
	if float(inv["tokens_burned"]) >= float(target.get("total_burn", 0.0)):
		var unmet: Array[String] = unmet_conditions(run_state, target)
		if unmet.is_empty():
			outcome = STATUS_COMPLETED
			messages.append("%s: requirement met." % str(target.get("name", "Target")))
		else:
			messages.append("Burn requirement met, but %s." % " and ".join(unmet))

	if outcome != STATUS_NONE:
		inv["status"] = outcome
	run_state.investor = inv
	return {
		"outcome": outcome,
		"messages": messages,
		"level": level(run_state),
		"tokens_burned": inv["tokens_burned"],
		"total_burn": float(target.get("total_burn", 0.0)),
	}


## The conditions beyond the burn that the target still fails, in the words
## the round log prints. Empty when everything is met.
func unmet_conditions(run_state: RunState, target: Dictionary) -> Array[String]:
	var inv: Dictionary = run_state.investor
	var unmet: Array[String] = []
	if not _quality_met(inv, target):
		unmet.append("the quality bar is not")
	if target.has("max_heat_ratio"):
		if float(inv.get("max_heat_ratio", 0.0)) > float(target["max_heat_ratio"]):
			unmet.append("the rig ran hotter than the investor allowed")
	if bool(target.get("no_catastrophe", false)) and int(inv.get("catastrophes", 0)) > 0:
		unmet.append("there was a catastrophe on his watch")
	if target.has("min_profit"):
		var profit: float = float(run_state.economy.get("cash", 0.0)) - float(inv.get("profit_baseline", 0.0))
		if profit < float(target["min_profit"]):
			unmet.append("the books are short of the profit he asked for")
	return unmet


## The deadline has closed on an unfinished target, which is the end of the run.
## Reported rather than acted on so the caller can settle the loss its own way.
func fail_on_deadline(run_state: RunState) -> void:
	if not is_active(run_state):
		return
	run_state.investor["status"] = STATUS_FAILED


func _quality_met(inv: Dictionary, target: Dictionary) -> bool:
	var required: float = float(target.get("quality_min", 0.0))
	if required <= 0.0:
		return true
	var count: int = int(inv.get("quality_count", 0))
	if count <= 0:
		return false
	var average: float = float(inv.get("quality_sum", 0.0)) / float(count)
	return average >= required


## Folds a delivered job's quality into the target's running average, so the
## quality bar is judged on the work actually shipped under it. Callers pass
## the delivered figure — `JobSystem.delivered_quality()` — rather than the raw
## pipeline output, so unfinished delivery and shipped known bugs count against
## the target exactly as they count against the fee.
func record_job_quality(run_state: RunState, quality: float) -> void:
	if not is_active(run_state):
		return
	run_state.investor["quality_sum"] = float(run_state.investor.get("quality_sum", 0.0)) + quality
	run_state.investor["quality_count"] = int(run_state.investor.get("quality_count", 0)) + 1


## Average quality of everything delivered under the target so far, or 0 when
## nothing has shipped yet.
func average_quality(run_state: RunState) -> float:
	var count: int = int(run_state.investor.get("quality_count", 0))
	if count <= 0:
		return 0.0
	return float(run_state.investor.get("quality_sum", 0.0)) / float(count)


## Reported for a finished target as well as a live one: the verdict screen has
## to be able to say how close a run came after the target has already failed.
func progress(run_state: RunState, content_db: Node = null) -> Dictionary:
	var target: Dictionary = current_target(run_state, content_db)
	if target.is_empty():
		return {}
	var inv: Dictionary = run_state.investor
	var total: float = float(target.get("total_burn", 0.0))
	var burned: float = float(inv.get("tokens_burned", 0.0))
	var deadline: int = deadline_round(run_state, target)
	return {
		"level": level(run_state),
		"target": target,
		"final": bool(target.get("final", false)),
		"tokens_burned": burned,
		"total_burn": total,
		"burn_ratio": 0.0 if total <= 0.0 else clampf(burned / total, 0.0, 1.0),
		"quality_min": float(target.get("quality_min", 0.0)),
		"quality_average": average_quality(run_state),
		"max_heat_ratio": float(inv.get("max_heat_ratio", 0.0)),
		"catastrophes": int(inv.get("catastrophes", 0)),
		"profit": float(run_state.economy.get("cash", 0.0)) - float(inv.get("profit_baseline", 0.0)),
		"deadline_round": deadline,
		"rounds_remaining": maxi(0, deadline - int(run_state.calendar.get("round", 1)) + 1),
	}


## Everything a readout needs to say where the run stands against its target,
## without asking four separate questions or re-deriving any of the rules.
func summary(run_state: RunState, content_db: Node = null) -> Dictionary:
	var target: Dictionary = current_target(run_state, content_db)
	var status: String = str(run_state.investor.get("status", STATUS_NONE))
	return {
		"level": level(run_state),
		"targets_completed": targets_completed(run_state),
		"target": target,
		"room": InfrastructureSystem.room_id(run_state, content_db),
		"final": bool(target.get("final", false)),
		"active": is_active(run_state),
		"completed": status == STATUS_COMPLETED,
		"failed": status == STATUS_FAILED,
		"game_completed": bool(run_state.flags.get("game_completed", false)),
		"progress": progress(run_state, content_db),
	}
