class_name DepthSystem
extends RefCounted

## Post-Moon score-attack ladder. Beating the last authored chapter unlocks
## voluntary depths: harder work and stacked affixes in exchange for score.

const STATUS_NONE := ""
const STATUS_ACTIVE := "active"
const STATUS_COMPLETE := "complete"


static func default_state() -> Dictionary:
	return {
		"level": 0,
		"affixes": [],
		"stacks": {},
		"status": STATUS_NONE,
		"score_mult": 1.0,
		"requirement_mult": 1.0,
		"tokens_needed": 0.0,
		"baseline_tokens": 0.0,
		"pending_picks": [],
	}


static func is_active(run_state: RunState) -> bool:
	return int(run_state.depth.get("level", 0)) > 0


static func affixes(content_db: Node) -> Array:
	return Array(content_db.balance.get("job_scaling", {}).get("depth_affixes", []))


static func growth_for(level: int, content_db: Node) -> float:
	var growth: Array = Array(content_db.balance.get("job_scaling", {}).get("depth_growth", [3.0, 5.0, 10.0]))
	if growth.is_empty():
		return 10.0
	return float(growth[mini(maxi(0, level - 1), growth.size() - 1)])


static func tokens_burned(run_state: RunState) -> float:
	return maxf(
		0.0,
		float(run_state.statistics.get("lifetime_tokens", 0.0))
		- float(run_state.depth.get("baseline_tokens", 0.0))
	)


static func remaining(run_state: RunState) -> float:
	return maxf(0.0, float(run_state.depth.get("tokens_needed", 0.0)) - tokens_burned(run_state))


static func is_complete(run_state: RunState) -> bool:
	if str(run_state.depth.get("status", STATUS_NONE)) == STATUS_COMPLETE:
		return true
	if not is_active(run_state):
		return false
	var needed: float = float(run_state.depth.get("tokens_needed", 0.0))
	if needed <= 0.0:
		return false
	return tokens_burned(run_state) >= needed


func can_begin(run_state: RunState) -> bool:
	if not FeatureFlags.is_enabled("depth_ladder_enabled"):
		return false
	return MetaProgress.next_location_after(str(run_state.build.get("dwelling", ""))) == ""


func progress(run_state: RunState) -> Dictionary:
	if not is_active(run_state) and str(run_state.depth.get("status", STATUS_NONE)) == STATUS_NONE:
		return {}
	var needed: float = float(run_state.depth.get("tokens_needed", 0.0))
	var burned: float = tokens_burned(run_state)
	return {
		"level": int(run_state.depth.get("level", 0)),
		"status": str(run_state.depth.get("status", STATUS_NONE)),
		"tokens_burned": burned,
		"tokens_needed": needed,
		"remaining": maxf(0.0, needed - burned),
		"ratio": 0.0 if needed <= 0.0 else clampf(burned / needed, 0.0, 1.0),
	}


func evaluate_prompt(run_state: RunState) -> Dictionary:
	if str(run_state.depth.get("status", STATUS_NONE)) == STATUS_COMPLETE:
		return {"outcome": STATUS_COMPLETE, "messages": []}
	if not is_active(run_state):
		return {}
	if not is_complete(run_state):
		return {
			"outcome": STATUS_ACTIVE,
			"messages": [],
			"tokens_burned": tokens_burned(run_state),
			"tokens_needed": float(run_state.depth.get("tokens_needed", 0.0)),
		}
	run_state.depth["status"] = STATUS_COMPLETE
	var level: int = int(run_state.depth.get("level", 0))
	EventBus.emit_event(EventBus.EVENT_DEPTH_COMPLETE, {"level": level})
	return {
		"outcome": STATUS_COMPLETE,
		"messages": ["Depth %d complete." % level],
		"tokens_burned": tokens_burned(run_state),
		"tokens_needed": float(run_state.depth.get("tokens_needed", 0.0)),
	}


func offer_picks(run_state: RunState, rng: DeterministicRng, content_db: Node) -> Array:
	var pool: Array = affixes(content_db).duplicate()
	if pool.is_empty():
		run_state.depth["pending_picks"] = []
		return []
	pool = rng.shuffle(pool)
	var stacks: Dictionary = Dictionary(run_state.depth.get("stacks", {}))
	var picks: Array = []
	var taken: Dictionary = {}
	for affix in pool:
		if not affix is Dictionary:
			continue
		var affix_id: String = str(affix.get("id", ""))
		if affix_id == "" or taken.has(affix_id):
			continue
		if not _can_offer(affix, stacks):
			continue
		taken[affix_id] = true
		picks.append(affix.duplicate(true))
		if picks.size() >= 3:
			break
	run_state.depth["pending_picks"] = picks
	return picks


func choose_affix(
	run_state: RunState, affix_id: String, content_db: Node
) -> bool:
	var chosen: Dictionary = {}
	for pick in Array(run_state.depth.get("pending_picks", [])):
		if pick is Dictionary and str(pick.get("id", "")) == affix_id:
			chosen = pick.duplicate(true)
			break
	if chosen.is_empty():
		return false
	var stacks: Dictionary = Dictionary(run_state.depth.get("stacks", {}))
	if not _can_offer(chosen, stacks):
		return false
	var next_level: int = int(run_state.depth.get("level", 0)) + 1
	run_state.depth["level"] = next_level
	run_state.depth["status"] = STATUS_ACTIVE
	var owned: Array = Array(run_state.depth.get("affixes", []))
	owned.append(affix_id)
	run_state.depth["affixes"] = owned
	var stack_n: int = int(stacks.get(affix_id, 0)) + 1
	stacks[affix_id] = stack_n
	run_state.depth["stacks"] = stacks
	run_state.depth["score_mult"] = float(run_state.depth.get("score_mult", 1.0)) * float(
		chosen.get("score_mult", 1.0)
	)
	run_state.depth["requirement_mult"] = float(run_state.depth.get("requirement_mult", 1.0)) * growth_for(
		next_level, content_db
	) * float(chosen.get("requirement_mult", 1.0))
	run_state.depth["pending_picks"] = []
	run_state.depth["baseline_tokens"] = float(run_state.statistics.get("lifetime_tokens", 0.0))
	var moon: Dictionary = {}
	for contract in content_db.ascension_contracts:
		if str(contract.get("location", "")) == "moon_facility":
			moon = contract
			break
	var base_need: float = float(moon.get("total_burn", 25000000000000.0))
	run_state.depth["tokens_needed"] = base_need * float(run_state.depth["requirement_mult"])
	run_state.statistics["depth_reached"] = maxi(
		int(run_state.statistics.get("depth_reached", 0)), next_level
	)
	_apply_affix_status(run_state, chosen, stack_n)
	EventBus.emit_event(EventBus.EVENT_DEPTH_ADVANCED, {"level": next_level, "affix_id": affix_id})
	return true


func _can_offer(affix: Dictionary, stacks: Dictionary) -> bool:
	var affix_id: String = str(affix.get("id", ""))
	if affix_id == "":
		return false
	var held: int = int(stacks.get(affix_id, 0))
	if held <= 0:
		return true
	if not bool(affix.get("repeatable", false)):
		return false
	var cap: int = int(affix.get("max_stacks", 0))
	return cap <= 0 or held < cap


func _apply_affix_status(run_state: RunState, affix: Dictionary, stack_n: int) -> void:
	var status: Variant = affix.get("status", {})
	if not status is Dictionary or status.is_empty():
		return
	if not (run_state.build.get("status_effects") is Array):
		run_state.build["status_effects"] = []
	var copy: Dictionary = status.duplicate(true)
	var base_id: String = str(copy.get("id", "status.depth.%s" % str(affix.get("id", "affix"))))
	copy["id"] = base_id if stack_n <= 1 else "%s.%d" % [base_id, stack_n]
	if stack_n > 1:
		copy["name"] = "%s %s" % [str(copy.get("name", "Affix")), _roman(stack_n)]
	run_state.build["status_effects"].append(copy)


func _roman(value: int) -> String:
	var numerals: Array = [
		[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"],
	]
	var remaining: int = maxi(1, value)
	var out := ""
	for pair in numerals:
		while remaining >= int(pair[0]):
			out += str(pair[1])
			remaining -= int(pair[0])
	return out
