class_name PerkSystem
extends RefCounted


func acquire(run_state: RunState, perk_id: String, content_db: Node) -> bool:
	if perk_id in run_state.build["perks"]:
		return false
	var perk: PerkDefinition = content_db.get_perk(perk_id)
	if perk == null:
		return false
	for owned_id in run_state.build["perks"]:
		var owned: PerkDefinition = content_db.get_perk(str(owned_id))
		if owned == null:
			continue
		if perk_id in owned.incompatible_ids or owned.id in perk.incompatible_ids:
			return false
		for tag in perk.excludes_tags:
			if tag in owned.tags:
				return false
		for tag in owned.excludes_tags:
			if tag in perk.tags:
				return false
	for req_tag in perk.requires_tags:
		if not _owned_has_tag(run_state, content_db, req_tag):
			return false
	if not _stacking_allows(run_state, content_db, perk):
		return false
	run_state.build["perks"].append(perk_id)
	return true


func detect_synergies(run_state: RunState, content_db: Node) -> Array[String]:
	var owned: Array = run_state.build["perks"]
	var found: Array[String] = []
	for synergy in content_db.synergies:
		if not synergy is Dictionary:
			continue
		var required: Array = synergy.get("perks", [])
		var has_all := true
		for req in required:
			if str(req) not in owned:
				has_all = false
				break
		if has_all:
			found.append(str(synergy.get("name", "Synergy")))
	return found


func _owned_has_tag(run_state: RunState, content_db: Node, tag: String) -> bool:
	for owned_id in run_state.build["perks"]:
		var owned: PerkDefinition = content_db.get_perk(str(owned_id))
		if owned != null and tag in owned.tags:
			return true
	return false


func _stacking_allows(run_state: RunState, content_db: Node, perk: PerkDefinition) -> bool:
	if perk.stacking.is_empty():
		return true
	var limit: int = int(perk.stacking.get("limit", 99))
	var mode: String = str(perk.stacking.get("mode", "unique"))
	if mode == "unique":
		return int(run_state.build["perks"].count(perk.id)) < limit
	var same_tag_count: int = 0
	for owned_id in run_state.build["perks"]:
		var owned: PerkDefinition = content_db.get_perk(str(owned_id))
		if owned == null:
			continue
		for tag in perk.tags:
			if tag in owned.tags:
				same_tag_count += 1
				break
	return same_tag_count < limit
