class_name DepthSystem
extends RefCounted

## Post-Moon score-attack ladder. Beating the last authored chapter unlocks
## voluntary depths: harder work and stacked affixes in exchange for score.


static func default_state() -> Dictionary:
	return {
		"level": 0,
		"affixes": [],
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


func can_begin(run_state: RunState) -> bool:
	if not FeatureFlags.is_enabled("depth_ladder_enabled"):
		return false
	return MetaProgress.next_location_after(str(run_state.build.get("dwelling", ""))) == ""


func offer_picks(run_state: RunState, rng: DeterministicRng, content_db: Node) -> Array:
	var pool: Array = affixes(content_db).duplicate()
	if pool.is_empty():
		run_state.depth["pending_picks"] = []
		return []
	pool = rng.shuffle(pool)
	var picks: Array = []
	var taken: Dictionary = {}
	for affix in pool:
		if not affix is Dictionary:
			continue
		var affix_id: String = str(affix.get("id", ""))
		if affix_id == "" or taken.has(affix_id):
			continue
		if affix_id in Array(run_state.depth.get("affixes", [])):
			continue
		taken[affix_id] = true
		picks.append(affix.duplicate(true))
		if picks.size() >= 3:
			break
	if picks.is_empty():
		for affix in pool:
			if affix is Dictionary:
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
		for affix in affixes(content_db):
			if affix is Dictionary and str(affix.get("id", "")) == affix_id:
				chosen = affix.duplicate(true)
				break
	if chosen.is_empty():
		return false
	var next_level: int = int(run_state.depth.get("level", 0)) + 1
	run_state.depth["level"] = next_level
	var owned: Array = Array(run_state.depth.get("affixes", []))
	owned.append(affix_id)
	run_state.depth["affixes"] = owned
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
	_apply_affix_status(run_state, chosen)
	EventBus.emit_event(EventBus.EVENT_DEPTH_ADVANCED, {"level": next_level, "affix_id": affix_id})
	return true


func _apply_affix_status(run_state: RunState, affix: Dictionary) -> void:
	var status: Variant = affix.get("status", {})
	if not status is Dictionary or status.is_empty():
		return
	if not (run_state.build.get("status_effects") is Array):
		run_state.build["status_effects"] = []
	var copy: Dictionary = status.duplicate(true)
	copy["id"] = str(copy.get("id", "status.depth.%s" % str(affix.get("id", "affix"))))
	run_state.build["status_effects"].append(copy)
