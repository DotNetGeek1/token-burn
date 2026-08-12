class_name PerkSystem
extends RefCounted


## How many perks a run may hold. Without a ceiling every long run converges on
## the same build — all of them — and the exclusions below never bite.
const DEFAULT_PERK_CAP := 6


func acquire(run_state: RunState, perk_id: String, content_db: Node) -> bool:
	if not can_acquire(run_state, perk_id, content_db):
		return false
	run_state.build["perks"].append(perk_id)
	return true


## Whether the build could take this perk right now. Drafts ask before offering,
## so a card on the table is always a card the player can actually pick.
func can_acquire(run_state: RunState, perk_id: String, content_db: Node) -> bool:
	if perk_id in run_state.build["perks"]:
		return false
	var perk: PerkDefinition = content_db.get_perk(perk_id)
	if perk == null:
		return false
	if run_state.build["perks"].size() >= perk_cap(content_db):
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
	return _stacking_allows(run_state, content_db, perk)


func perk_cap(content_db: Node) -> int:
	var economy: Dictionary = content_db.balance.get("economy", {})
	var build: Variant = economy.get("build", {})
	if build is Dictionary:
		return int(build.get("perk_cap", DEFAULT_PERK_CAP))
	return DEFAULT_PERK_CAP


## Every tag the build has committed to, for draft weighting and tag thresholds.
func owned_tags(run_state: RunState, content_db: Node) -> Array:
	var tags: Array = []
	for owned_id in run_state.build["perks"]:
		var owned: PerkDefinition = content_db.get_perk(str(owned_id))
		if owned == null:
			continue
		for tag in owned.tags:
			if tag not in tags:
				tags.append(tag)
	return tags


## Perk ids the build cannot take, so drafts can leave them out of the pool.
func blocked_ids(run_state: RunState, content_db: Node) -> Array:
	var blocked: Array = []
	for perk in content_db.perks:
		if not can_acquire(run_state, perk.id, content_db):
			blocked.append(perk.id)
	return blocked


func detect_synergies(run_state: RunState, content_db: Node) -> Array[String]:
	var found: Array[String] = []
	for synergy in active_synergies(run_state, content_db):
		found.append(str(synergy.get("name", "Synergy")))
	return found


## The synergy entries the build currently satisfies, whole. A synergy may carry
## its own `subscriptions`, which is what makes a set bonus a real effect rather
## than a label on the build screen.
func active_synergies(run_state: RunState, content_db: Node) -> Array:
	var owned: Array = run_state.build["perks"]
	var found: Array = []
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
			found.append(synergy)
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
