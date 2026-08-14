class_name PerkSystem
extends RefCounted


## How many perks a run may hold active at once. Without a ceiling every long
## run converges on the same build — all of them — and the exclusions below never
## bite. Extra slots come from capacity perks and Legacy ranks (PR 3/8).
const DEFAULT_PERK_CAP := 6


func collect_perk(run_state: RunState, perk_id: String, content_db: Node) -> bool:
	if not can_collect(run_state, perk_id, content_db):
		return false
	_ensure_inventory(run_state).append(perk_id)
	return true


## Perks whose pickup effects have already fired. A `perk.acquired` loan or
## permanent liability is taken once and kept: benching the card does not hand
## the money back, so re-collecting must not hand out a second one.
static func liability_taken(run_state: RunState, perk_id: String) -> bool:
	return perk_id in Array(run_state.build.get("perk_liabilities", []))


static func record_liability(run_state: RunState, perk_id: String) -> void:
	var liabilities: Array = Array(run_state.build.get("perk_liabilities", []))
	if perk_id in liabilities:
		return
	liabilities.append(perk_id)
	run_state.build["perk_liabilities"] = liabilities


func equip_perk(run_state: RunState, perk_id: String, content_db: Node) -> bool:
	if not can_equip(run_state, perk_id, content_db):
		return false
	run_state.build["perks"].append(perk_id)
	return true


func bench_perk(run_state: RunState, perk_id: String, content_db: Node) -> bool:
	if not can_bench(run_state, perk_id, content_db):
		return false
	run_state.build["perks"].erase(perk_id)
	return true


## Bench-then-equip as one move. The incoming perk is judged against the loadout
## the swap leaves behind, not the one it replaces — otherwise a swap could never
## free the slot or clear the conflict it exists to resolve. A refused equip puts
## the outgoing perk straight back.
func swap_perk(run_state: RunState, out_id: String, in_id: String, content_db: Node) -> bool:
	if out_id == in_id:
		return false
	if not can_bench(run_state, out_id, content_db, in_id):
		return false
	var index: int = run_state.build["perks"].find(out_id)
	if index < 0:
		return false
	run_state.build["perks"].remove_at(index)
	if not can_equip(run_state, in_id, content_db):
		run_state.build["perks"].insert(index, out_id)
		return false
	run_state.build["perks"].append(in_id)
	return true


## Why `in_id` could not take `out_id`'s place, judged against the loadout the
## swap would leave behind. Empty when the swap is legal.
func swap_block_reason(run_state: RunState, out_id: String, in_id: String, content_db: Node) -> String:
	if out_id == in_id:
		return "Already active"
	var bench_reason: String = bench_block_reason(run_state, out_id, content_db, in_id)
	if bench_reason != "":
		return bench_reason
	var index: int = run_state.build["perks"].find(out_id)
	if index < 0:
		return "Not active"
	run_state.build["perks"].remove_at(index)
	var reason: String = equip_block_reason(run_state, in_id, content_db)
	run_state.build["perks"].insert(index, out_id)
	return reason


func can_swap(run_state: RunState, out_id: String, in_id: String, content_db: Node) -> bool:
	return swap_block_reason(run_state, out_id, in_id, content_db) == ""


## Whether a perk can enter the run's collection. A full active loadout must not
## remove an uncollected perk from the draft pool.
func can_collect(run_state: RunState, perk_id: String, content_db: Node) -> bool:
	if perk_id in collected_ids(run_state):
		return false
	var perk: PerkDefinition = content_db.get_perk(perk_id)
	if perk == null:
		return false
	if content_db.has_method("perk_is_unlocked") and not content_db.perk_is_unlocked(perk):
		return false
	if not _difficulty_allows(run_state, perk):
		return false
	if not _location_tier_allows(run_state, perk, content_db):
		return false
	return true


func can_equip(run_state: RunState, perk_id: String, content_db: Node) -> bool:
	if perk_id not in collected_ids(run_state):
		return false
	if perk_id in run_state.build["perks"]:
		return false
	var perk: PerkDefinition = content_db.get_perk(perk_id)
	if perk == null:
		return false
	if run_state.build["perks"].size() >= perk_capacity(run_state, content_db):
		return false
	return _active_compatibility_allows(run_state, content_db, perk)


func can_bench(
	run_state: RunState, perk_id: String, content_db: Node, incoming_id: String = ""
) -> bool:
	return bench_block_reason(run_state, perk_id, content_db, incoming_id) == ""


## `incoming_id` is the perk taking this one's place in a swap. It covers the
## tags it provides, so trading one risk perk for another is still legal while
## removing the last one is not.
func bench_block_reason(
	run_state: RunState, perk_id: String, content_db: Node, incoming_id: String = ""
) -> String:
	if perk_id not in run_state.build["perks"]:
		return "Not active"
	var perk: PerkDefinition = content_db.get_perk(perk_id)
	if perk == null:
		return "Unknown perk"
	var incoming: PerkDefinition = content_db.get_perk(incoming_id) if incoming_id != "" else null
	var slot_grant: int = int(perk.grants.get("perk_slots", 0))
	if slot_grant > 0:
		var without: int = perk_capacity(run_state, content_db) - slot_grant
		if run_state.build["perks"].size() > without:
			return "Bench other perks before removing this capacity perk"
	var workflow_grant: int = int(perk.grants.get("workflow_capacity", 0))
	if workflow_grant > 0:
		var board := BoardSystem.new()
		var without: int = board.derived_workflow_capacity(run_state, content_db) - workflow_grant
		var in_use: int = board.workflow_count(run_state)
		if in_use > without:
			return "Remove surplus workflows before benching this perk"
	var board_slot_grant: int = int(perk.grants.get("board_slots", 0))
	if board_slot_grant > 0:
		var board := BoardSystem.new()
		var meta_bonus: int = int(Dictionary(run_state.build.get("board", {})).get("meta_slot_bonus", 0))
		var perk_bonus: int = BoardSystem.active_perk_grant_total(
			run_state, content_db, "board_slots"
		) - board_slot_grant
		var upgrade_bonus: int = int(UpgradeSystem.additive_effect_total(
			run_state, content_db, "build.board.slot_count"
		))
		if incoming != null:
			perk_bonus += int(incoming.grants.get("board_slots", 0))
		var resulting_slots: int = clampi(
			BoardSystem.DEFAULT_SLOT_COUNT + meta_bonus + perk_bonus + upgrade_bonus,
			1,
			BoardSystem.MAX_SLOT_COUNT
		)
		for workflow in board.workflows(run_state):
			if not workflow is Dictionary:
				continue
			var layout: Array = Array(workflow.get("slots", []))
			for index in range(resulting_slots, layout.size()):
				if str(layout[index]) != "":
					return "Clear the extra pipeline slot before benching this perk"
	# `requires_tags` is checked when a perk goes in, so it has to be checked
	# when its provider comes out too. Otherwise the loadout can be walked into
	# a state the equip rules would have refused outright.
	for tag in perk.tags:
		if incoming != null and tag in incoming.tags:
			continue
		for other_id in run_state.build["perks"]:
			if str(other_id) == perk_id:
				continue
			var other: PerkDefinition = content_db.get_perk(str(other_id))
			if other == null or tag not in other.requires_tags:
				continue
			# The dependent is excluded from the search as well, because a perk
			# never counted as its own provider when it was equipped.
			if not _owned_has_tag(run_state, content_db, tag, perk_id, str(other_id)):
				return "%s needs this for: %s" % [other.name, tag]
	return ""


func equip_block_reason(run_state: RunState, perk_id: String, content_db: Node) -> String:
	if perk_id not in collected_ids(run_state):
		return "Not in collection"
	if perk_id in run_state.build["perks"]:
		return "Already active"
	var perk: PerkDefinition = content_db.get_perk(perk_id)
	if perk == null:
		return "Unknown perk"
	if run_state.build["perks"].size() >= perk_capacity(run_state, content_db):
		return "Active loadout full"
	return _active_compatibility_reason(run_state, content_db, perk)


## Backwards-compatible alias: collect and equip atomically, matching the old
## behaviour where incompatible perks could not enter the build at all.
func acquire(run_state: RunState, perk_id: String, content_db: Node) -> bool:
	if not can_acquire(run_state, perk_id, content_db):
		return false
	return collect_perk(run_state, perk_id, content_db) and equip_perk(run_state, perk_id, content_db)


func can_acquire(run_state: RunState, perk_id: String, content_db: Node) -> bool:
	return can_collect(run_state, perk_id, content_db) and can_equip(run_state, perk_id, content_db)


func base_perk_cap(content_db: Node) -> int:
	var economy: Dictionary = content_db.balance.get("economy", {})
	var build: Variant = economy.get("build", {})
	if build is Dictionary:
		return int(build.get("perk_cap", DEFAULT_PERK_CAP))
	return DEFAULT_PERK_CAP


func perk_cap(content_db: Node) -> int:
	return base_perk_cap(content_db)


func perk_capacity(run_state: RunState, content_db: Node) -> int:
	var bonus: int = 0
	for perk_id in run_state.build.get("perks", []):
		var perk: PerkDefinition = content_db.get_perk(str(perk_id))
		if perk != null:
			bonus += int(perk.grants.get("perk_slots", 0))
	if MetaProgress.has_method("legacy_perk_slot_bonus"):
		bonus += MetaProgress.legacy_perk_slot_bonus()
	return base_perk_cap(content_db) + bonus


func collected_ids(run_state: RunState) -> Array:
	return _ensure_inventory(run_state)


## Every tag the build has committed to, for draft weighting and tag thresholds.
##
## Modules count as well as perks, and owning one is enough: drafting three
## recursion modules is a declaration of intent, and steering only on active
## perks made build-building a one-way street where the pipeline could never ask
## the angel for more of what it was already doing. Benched modules count for the
## same reason a benched module still cost a pick.
func owned_tags(run_state: RunState, content_db: Node) -> Array:
	var tags: Array = []
	for owned_id in run_state.build["perks"]:
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


## Perk ids that cannot be collected this run, so drafts can leave them out.
func undraftable_ids(run_state: RunState, content_db: Node) -> Array:
	var blocked: Array = []
	for perk in content_db.perks:
		if not can_collect(run_state, perk.id, content_db):
			blocked.append(perk.id)
	return blocked


## Perk ids that cannot be equipped right now (but may still be draftable).
func unequippable_ids(run_state: RunState, content_db: Node) -> Array:
	var blocked: Array = []
	for perk_id in collected_ids(run_state):
		if perk_id in run_state.build["perks"]:
			continue
		if not can_equip(run_state, str(perk_id), content_db):
			blocked.append(perk_id)
	return blocked


## Backwards-compatible alias for draft filtering.
func blocked_ids(run_state: RunState, content_db: Node) -> Array:
	return undraftable_ids(run_state, content_db)


func detect_synergies(run_state: RunState, content_db: Node) -> Array[String]:
	var found: Array[String] = []
	for synergy in active_synergies(run_state, content_db):
		found.append(str(synergy.get("name", "Synergy")))
	return found


## The synergy entries the active loadout currently satisfies.
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


func _ensure_inventory(run_state: RunState) -> Array:
	if not run_state.build.has("perk_inventory") or not (run_state.build["perk_inventory"] is Array):
		run_state.build["perk_inventory"] = []
	return run_state.build["perk_inventory"]


## Whether anything in the build provides `tag`, counting the modules the run
## owns as well as the perks it has equipped. `excludes_tags` deliberately does
## not read modules: a requirement is something the build can satisfy, but a
## cooling module quietly banning a thermal keystone is a rule the player cannot
## see coming.
func _owned_has_tag(
	run_state: RunState,
	content_db: Node,
	tag: String,
	ignored_perk_id: String = "",
	also_ignored_perk_id: String = ""
) -> bool:
	for owned_id in run_state.build["perks"]:
		if str(owned_id) == ignored_perk_id or str(owned_id) == also_ignored_perk_id:
			continue
		var owned: PerkDefinition = content_db.get_perk(str(owned_id))
		if owned != null and tag in owned.tags:
			return true
	for module_id in Array(run_state.build.get("modules", [])):
		var module: ModuleDefinition = content_db.get_module(str(module_id))
		if module != null and tag in module.tags:
			return true
	return false


func _active_compatibility_allows(run_state: RunState, content_db: Node, perk: PerkDefinition) -> bool:
	return _active_compatibility_reason(run_state, content_db, perk) == ""


func _active_compatibility_reason(run_state: RunState, content_db: Node, perk: PerkDefinition) -> String:
	for owned_id in run_state.build["perks"]:
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
	for req_tag in perk.requires_tags:
		if not _owned_has_tag(run_state, content_db, req_tag):
			return "Requires: %s" % req_tag
	if not _stacking_allows(run_state, content_db, perk):
		return "Stacking limit reached"
	return ""


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


func _difficulty_allows(run_state: RunState, perk: PerkDefinition) -> bool:
	if perk.difficulty.is_empty():
		return true
	var run_difficulty: String = str(run_state.flags.get("difficulty", "normal"))
	return run_difficulty in perk.difficulty


func _location_tier_allows(run_state: RunState, perk: PerkDefinition, content_db: Node) -> bool:
	var tier: int = _current_location_tier(run_state, content_db)
	if perk.min_location_tier > 0 and tier < perk.min_location_tier:
		return false
	if perk.max_location_tier >= 0 and tier > perk.max_location_tier:
		return false
	return true


func _current_location_tier(run_state: RunState, content_db: Node) -> int:
	var order: Array = []
	if MetaProgress.has_method("location_order"):
		order = MetaProgress.location_order()
	if order.is_empty():
		order = Array(content_db.balance.get("economy", {}).get("location_order", []))
	var dwelling: String = str(run_state.build.get("dwelling", "bedroom"))
	var index: int = order.find(dwelling)
	return maxi(0, index)
