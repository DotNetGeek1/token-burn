class_name PerkSystem
extends RefCounted

## Perks are permanent. A perk enters `build["perks"]` when the investor's goal
## is met and it stays there for the rest of the run: there is no bench, no
## capacity ceiling and no swap. The only question the system answers is
## whether a perk may join the build at all — and the exclusions
## (`incompatible_ids`, `excludes_tags`, `requires_tags`, `stacking`) are what
## make that a real question, because a wrong pick can never be undone.


## Perks whose pickup effects have already fired. A `perk.acquired` loan or
## permanent liability is taken once and kept, so re-acquiring (a migration,
## a debug grant) must not hand out a second one.
static func liability_taken(run_state: RunState, perk_id: String) -> bool:
	return perk_id in Array(run_state.build.get("perk_liabilities", []))


static func record_liability(run_state: RunState, perk_id: String) -> void:
	var liabilities: Array = Array(run_state.build.get("perk_liabilities", []))
	if perk_id in liabilities:
		return
	liabilities.append(perk_id)
	run_state.build["perk_liabilities"] = liabilities


## Adds the perk to the build for good. False (and no change) when
## `can_acquire` says no. Effect wiring — invalidating subscriptions, firing
## `perk.acquired`, resizing the board — is the Simulation's job.
func acquire(run_state: RunState, perk_id: String, content_db: Node) -> bool:
	if not can_acquire(run_state, perk_id, content_db):
		return false
	_owned(run_state).append(perk_id)
	return true


func can_acquire(run_state: RunState, perk_id: String, content_db: Node) -> bool:
	return acquire_block_reason(run_state, perk_id, content_db) == ""


## Why a perk cannot join the build, in the order the rules are checked. Empty
## when it can.
func acquire_block_reason(run_state: RunState, perk_id: String, content_db: Node) -> String:
	var perk: PerkDefinition = content_db.get_perk(perk_id)
	if perk == null:
		return "Unknown perk"
	if content_db.has_method("perk_is_unlocked") and not content_db.perk_is_unlocked(perk):
		return "Not unlocked"
	if not _difficulty_allows(run_state, perk):
		return "Not on this difficulty"
	if not _investor_level_allows(run_state, perk):
		return "Investor Target %d" % perk.min_investor_level
	if perk_id in _owned(run_state):
		return "Already owned"
	return _compatibility_reason(run_state, content_db, perk)


## The perks the run owns, in the order they were taken.
func owned_ids(run_state: RunState) -> Array:
	return _owned(run_state)


## Every tag the build has committed to, for draft weighting and tag thresholds.
##
## Modules count as well as perks, and owning one is enough: drafting three
## recursion modules is a declaration of intent, and the draft should be able
## to offer more of what the pipeline is already doing.
func owned_tags(run_state: RunState, content_db: Node) -> Array:
	var tags: Array = []
	for owned_id in _owned(run_state):
		var owned: PerkDefinition = content_db.get_perk(str(owned_id))
		if owned == null:
			continue
		for tag in owned.tags:
			if tag not in tags:
				tags.append(tag)
	for module_id in Array(run_state.build.get("modules", [])):
		var module: ModuleDefinition = content_db.get_module(str(module_id))
		if module == null:
			continue
		for tag in module.tags:
			if tag not in tags:
				tags.append(tag)
	return tags


## Perk ids that cannot join the build right now, so drafts leave them out.
## A permanent perk that cannot be taken is not worth a card.
func undraftable_ids(run_state: RunState, content_db: Node) -> Array:
	var blocked: Array = []
	for perk in content_db.perks:
		if not can_acquire(run_state, perk.id, content_db):
			blocked.append(perk.id)
	return blocked


## Backwards-compatible alias for draft filtering.
func blocked_ids(run_state: RunState, content_db: Node) -> Array:
	return undraftable_ids(run_state, content_db)


## Walks `candidate_ids` in order and keeps every perk that exists and is
## compatible with the ones kept before it. Used by the save migration that
## folds the old bench into the permanent set: two rival keystones that could
## coexist on a bench cannot coexist in a build, so the earlier one wins.
## Unlock, difficulty and level gates are deliberately not applied, and nor
## are `requires_tags` — a perk already in the run was legitimately earned and
## met its requirement when it was taken. Only mutual exclusions are enforced.
func legal_subset(run_state: RunState, candidate_ids: Array, content_db: Node) -> Array:
	var previous: Array = _owned(run_state)
	var kept: Array = []
	run_state.build["perks"] = kept
	for raw in candidate_ids:
		var perk_id: String = str(raw)
		if perk_id in kept:
			continue
		var perk: PerkDefinition = content_db.get_perk(perk_id)
		if perk == null:
			continue
		if _compatibility_reason(run_state, content_db, perk, false) == "":
			kept.append(perk_id)
	run_state.build["perks"] = previous
	return kept


func detect_synergies(run_state: RunState, content_db: Node) -> Array[String]:
	var found: Array[String] = []
	for synergy in active_synergies(run_state, content_db):
		found.append(str(synergy.get("name", "Synergy")))
	return found


## The synergy entries the build currently satisfies.
func active_synergies(run_state: RunState, content_db: Node) -> Array:
	var found: Array = []
	for synergy in content_db.synergies:
		if not synergy is Dictionary:
			continue
		if synergy_is_active(run_state, content_db, synergy):
			found.append(synergy)
	return found


func synergy_is_active(run_state: RunState, content_db: Node, synergy: Dictionary) -> bool:
	var required: Array = synergy.get("perks", [])
	if not required.is_empty():
		var owned: Array = _owned(run_state)
		for req in required:
			if str(req) not in owned:
				return false
	for requirement in Array(synergy.get("requires_tag_counts", [])):
		if not requirement is Dictionary:
			continue
		var needed: int = int(requirement.get("count", 0))
		if needed <= 0:
			continue
		if slotted_tag_density(run_state, content_db, Array(requirement.get("tags", []))) < needed:
			return false
	return not required.is_empty() or not Array(synergy.get("requires_tag_counts", [])).is_empty()


## Owned perks plus modules actually sitting in a workflow. Loose modules do
## not count: density is about the machine you are running, not the drawer.
func slotted_tag_density(run_state: RunState, content_db: Node, tags: Array) -> int:
	var wanted: Dictionary = {}
	for tag in tags:
		wanted[str(tag)] = true
	if wanted.is_empty():
		return 0
	var counted: Dictionary = {}
	var total: int = 0
	for perk_id in _owned(run_state):
		var perk: PerkDefinition = content_db.get_perk(str(perk_id))
		if perk == null or counted.has(perk.id):
			continue
		if _has_any_tag(perk.tags, wanted):
			counted[perk.id] = true
			total += 1
	for workflow in Array(run_state.build.get("workflows", [])):
		if not workflow is Dictionary:
			continue
		for module_id in Array(workflow.get("slots", [])):
			var key: String = str(module_id)
			if key == "" or counted.has(key):
				continue
			var module: ModuleDefinition = content_db.get_module(key)
			if module == null:
				continue
			if _has_any_tag(module.tags, wanted):
				counted[key] = true
				total += 1
	return total


func _has_any_tag(tags: PackedStringArray, wanted: Dictionary) -> bool:
	for tag in tags:
		if wanted.has(str(tag)):
			return true
	return false


func near_synergies(run_state: RunState, content_db: Node) -> Array:
	var near: Array = []
	for synergy in content_db.synergies:
		if not synergy is Dictionary:
			continue
		if synergy_is_active(run_state, content_db, synergy):
			continue
		var progress: Dictionary = synergy_progress(run_state, content_db, synergy)
		if int(progress.get("have", 0)) > 0 and int(progress.get("need", 0)) > 0:
			near.append(progress)
	return near


func synergy_progress(run_state: RunState, content_db: Node, synergy: Dictionary) -> Dictionary:
	var have: int = 0
	var need: int = 0
	var required: Array = Array(synergy.get("perks", []))
	if not required.is_empty():
		need = required.size()
		for req in required:
			if str(req) in _owned(run_state):
				have += 1
	for requirement in Array(synergy.get("requires_tag_counts", [])):
		if not requirement is Dictionary:
			continue
		var count: int = int(requirement.get("count", 0))
		if count <= 0:
			continue
		need += count
		have += mini(count, slotted_tag_density(run_state, content_db, Array(requirement.get("tags", []))))
	return {
		"name": str(synergy.get("name", "Synergy")),
		"description": str(synergy.get("description", "")),
		"have": have,
		"need": need,
		"active": have >= need and need > 0,
	}


func _owned(run_state: RunState) -> Array:
	if not run_state.build.has("perks") or not (run_state.build["perks"] is Array):
		run_state.build["perks"] = []
	return run_state.build["perks"]


## Whether anything in the build provides `tag`, counting the modules the run
## owns as well as its perks. `excludes_tags` deliberately does not read
## modules: a requirement is something the build can satisfy, but a cooling
## module quietly banning a thermal keystone is a rule the player cannot see
## coming.
func _owned_has_tag(run_state: RunState, content_db: Node, tag: String) -> bool:
	for owned_id in _owned(run_state):
		var owned: PerkDefinition = content_db.get_perk(str(owned_id))
		if owned != null and tag in owned.tags:
			return true
	for module_id in Array(run_state.build.get("modules", [])):
		var module: ModuleDefinition = content_db.get_module(str(module_id))
		if module != null and tag in module.tags:
			return true
	return false


func _compatibility_reason(
	run_state: RunState, content_db: Node, perk: PerkDefinition, check_requirements: bool = true
) -> String:
	if check_requirements:
		for req_tag in perk.requires_tags:
			if not _owned_has_tag(run_state, content_db, req_tag):
				return "Requires: %s" % req_tag
	for owned_id in _owned(run_state):
		var owned: PerkDefinition = content_db.get_perk(str(owned_id))
		if owned == null:
			continue
		if perk.id in owned.incompatible_ids or owned.id in perk.incompatible_ids:
			return "Conflicts with: %s" % owned.name
		for tag in perk.excludes_tags:
			if tag in owned.tags:
				return "Excludes: %s" % tag
		for tag in owned.excludes_tags:
			if tag in perk.tags:
				return "Excluded by: %s" % owned.name
	if not _stacking_allows(run_state, content_db, perk):
		return "Stacking limit reached"
	return ""


func _stacking_allows(run_state: RunState, content_db: Node, perk: PerkDefinition) -> bool:
	if perk.stacking.is_empty():
		return true
	var limit: int = int(perk.stacking.get("limit", 99))
	var mode: String = str(perk.stacking.get("mode", "unique"))
	if mode == "unique":
		return int(_owned(run_state).count(perk.id)) < limit
	var same_tag_count: int = 0
	for owned_id in _owned(run_state):
		var owned: PerkDefinition = content_db.get_perk(str(owned_id))
		if owned == null:
			continue
		for tag in perk.tags:
			if tag in owned.tags:
				same_tag_count += 1
				break
	return same_tag_count < limit


func _difficulty_allows(run_state: RunState, perk: PerkDefinition) -> bool:
	if perk.difficulty.is_empty():
		return true
	var run_difficulty: String = str(run_state.flags.get("difficulty", "normal"))
	return run_difficulty in perk.difficulty


## The perk's Investor Level window against the run's level. A minimum of 0 or
## 1 is open from the first target; a maximum of -1 has no ceiling.
func _investor_level_allows(run_state: RunState, perk: PerkDefinition) -> bool:
	var level: int = _current_investor_level(run_state)
	if perk.min_investor_level > InvestorProgression.FIRST_LEVEL and level < perk.min_investor_level:
		return false
	if perk.max_investor_level >= 0 and level > perk.max_investor_level:
		return false
	return true


func _current_investor_level(run_state: RunState) -> int:
	return maxi(
		InvestorProgression.FIRST_LEVEL,
		int(run_state.investor.get("level", InvestorProgression.FIRST_LEVEL))
	)
