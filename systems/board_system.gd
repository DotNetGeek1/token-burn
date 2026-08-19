class_name BoardSystem
extends RefCounted

## The Burn Board: the player's token pipelines.
##
## A burn sends one token batch through the occupied slots of one workflow in
## order. Each stage declares its own contribution in a `stage.*` bag, which is
## then folded into the batch totals under whatever modifiers the stage above it
## left behind. Position therefore matters: a cache placed before a model
## discounts it, and the same cache placed last banks output instead.
##
## A run owns a list of named workflows, and every contract is assigned one.
## Two contracts worked in the same prompt each go through their own, so a
## throughput build and an audit build can be live at the same time.
##
## Resolution never touches the batch size itself. Throughput stays a property
## of the rig the player bought; the board decides what a batch of that size
## achieves.

const EVENT_BATCH_STARTED := "board.batch_started"
const EVENT_STAGE_RESOLVED := "board.stage_resolved"
## Last chance to change what the batch achieves. Dispatched after every stage
## and demand has had its say but before tokens and progress are worked out, so
## an effect that multiplies throughput still reaches the burn it belongs to.
const EVENT_BATCH_FINALIZING := "board.batch_finalizing"
## After the numbers are settled: cleanup, bug manipulation, and stats. Progress
## multipliers written here are too late to matter.
const EVENT_BATCH_FINISHED := "board.batch_finished"

## A run starts with fewer slots than the player owns modules. Room on the board
## is the scarce resource: new modules arrive benched, and taking one into the
## pipeline means taking something else out.
const DEFAULT_SLOT_COUNT := 3
const MAX_SLOT_COUNT := 8

## A run opens with one workflow. Capacity is earned: a Market upgrade, a perk,
## and the Simulation ascension ending each hand over another one.
const DEFAULT_WORKFLOW_CAPACITY := 1
const MAX_WORKFLOW_COUNT := 4

## Job constraints, declared per contract in jobs.json under `board_rules`.
const RULE_BLOCKED_SLOTS := "blocked_slots"
const RULE_TAG_BONUS := "tag_bonus"
const RULE_MAX_HIDDEN_BUGS := "max_hidden_bugs"
const RULE_RECURSION_RISK := "recursion_risk"
const RULE_AGENT_SCOPE := "agent_scope"
const RULE_FEATURE_CREEP := "feature_creep"

## What a contract can ask of the workflow assigned to it. Each is read off the
## modules placed in the pipeline rather than off a burn, so the answer is the
## same on the job card, in the assignment picker, and in the burn itself.
const CAPABILITY_FIX_BUGS := "fix_bugs"
const CAPABILITY_REVEAL_BUGS := "reveal_bugs"
const CAPABILITY_HEAVY_QUALITY := "heavy_quality"
const CAPABILITY_THROUGHPUT := "throughput"
const CAPABILITY_COOLING := "cooling"

## A single stage worth this much quality on its own is what a client with taste
## is asking for. Below it the pipeline is producing volume, not craft.
const HEAVY_QUALITY_THRESHOLD := 10.0

## Contributions a single stage may declare. Anything not listed here is not
## part of a burn and will be ignored by the fold.
const STAGE_DEFAULTS := {
	"progress_mult": 1.0,
	"token_mult": 1.0,
	"quality": 0.0,
	"bugs": 0.0,
	"hidden_bugs": 0.0,
	"heat": 0.0,
	"cost": 0.0,
	"reveal_bugs": 0.0,
	"fix_bugs": 0.0,
	"hide_bugs": 0.0,
	"quality_to_progress": 0.0,
	"repeat_previous": 0.0,
	## Post-construction scale on whatever actually repeats. Authored echo
	## amounts stay authored; Infinite Backlog multiplies this instead of the
	## echo itself, so a `set` or `cap_min` still reaches the fold.
	"repeat_strength": 1.0,
	## How many times the stage above is replayed, each at `repeat_previous`
	## strength. Two 55% forks are not one 110% fork: multiplier stages fold
	## non-linearly, so a module that says "twice" has to fold twice.
	"repeat_count": 1.0,
	"fix_hidden_bugs": 0.0,
	"next_multiplier": 1.0,
	"next_cost_mult": 1.0,
	"cascade_chance": 0.0,
	"cascade_strength": 1.0,
}


# --- Board state -------------------------------------------------------------

func ensure_board(run_state: RunState, content_db: Node) -> void:
	var board: Variant = run_state.build.get("board", null)
	if not board is Dictionary:
		board = {}
	_migrate_legacy_board_bonuses(run_state, content_db)
	var slot_count_value: int = derived_slot_count(run_state, content_db)
	board["slot_count"] = slot_count_value
	run_state.build["board"] = board

	# Starters are merged in rather than granted only to an empty list. A
	# `starting_module` unlock writes its module in before this runs, and the
	# old "skip if anything is owned" left that run with one module and no
	# pipeline to put it in — the reported bug where the workflow items vanish
	# and never come back.
	var owned: Array = Array(run_state.build.get("modules", []))
	for starter in content_db.starter_modules():
		if not (starter in owned):
			owned.append(starter)
	run_state.build["modules"] = owned

	_migrate_board_to_workflows(run_state)
	run_state.build["workflow_capacity"] = derived_workflow_capacity(run_state, content_db)
	_ensure_workflows(run_state, slot_count_value, content_db)
	_auto_fill_empty_workflows(run_state, content_db)


## Saves written before workflows existed keep one layout in `board.slots` and,
## if the Simulation ending had been earned, a second in `board.lane_slots`.
## Both become named workflows so a run in progress keeps the pipeline it built.
func _migrate_board_to_workflows(run_state: RunState) -> void:
	if run_state.build.get("workflows", null) is Array \
			and not Array(run_state.build["workflows"]).is_empty():
		return
	var board: Dictionary = run_state.build["board"]
	var layouts: Array = []
	var lane_slots: Variant = board.get("lane_slots", null)
	if lane_slots is Array and not Array(lane_slots).is_empty():
		for layout in Array(lane_slots):
			layouts.append(Array(layout) if layout is Array else [])
	elif board.get("slots", null) is Array:
		layouts.append(Array(board["slots"]))
	if layouts.is_empty():
		layouts.append([])
	var workflows: Array = []
	for index in range(layouts.size()):
		workflows.append({
			"id": "workflow.%d" % (index + 1),
			"name": _default_workflow_name(index),
			"slots": layouts[index],
		})
	run_state.build["workflows"] = workflows
	# A save that already carried two lanes has already earned the room for two.
	var lanes: int = maxi(1, int(run_state.build.get("lane_count", 1)))
	run_state.build["workflow_capacity"] = maxi(
		int(run_state.build.get("workflow_capacity", DEFAULT_WORKFLOW_CAPACITY)),
		maxi(lanes, workflows.size())
	)
	board.erase("slots")
	board.erase("lane_slots")
	board["active_workflow"] = clampi(
		int(board.get("active_lane", 0)), 0, workflows.size() - 1
	)
	board.erase("active_lane")


## Normalises the list: every workflow has an id, a name and exactly
## `slot_count` string slots, and the run never holds more of them than its
## capacity allows.
func _ensure_workflows(run_state: RunState, slot_count_value: int, content_db: Node = null) -> void:
	var workflows: Array = Array(run_state.build.get("workflows", []))
	var capacity: int = workflow_capacity(run_state, content_db)
	if workflows.size() > capacity:
		workflows.resize(capacity)
	if workflows.is_empty():
		workflows.append({"id": "workflow.1", "name": _default_workflow_name(0), "slots": []})
	for index in range(workflows.size()):
		var workflow: Variant = workflows[index]
		if not workflow is Dictionary:
			workflow = {}
		if str(workflow.get("id", "")) == "":
			workflow["id"] = "workflow.%d" % (index + 1)
		if str(workflow.get("name", "")) == "":
			workflow["name"] = _default_workflow_name(index)
		var layout: Array = Array(workflow.get("slots", []))
		layout.resize(slot_count_value)
		for i in range(slot_count_value):
			if not layout[i] is String:
				layout[i] = ""
		workflow["slots"] = layout
		workflows[index] = workflow
	run_state.build["workflows"] = workflows
	var board: Dictionary = run_state.build["board"]
	board["active_workflow"] = clampi(
		int(board.get("active_workflow", 0)), 0, workflows.size() - 1
	)


func _default_workflow_name(index: int) -> String:
	const NAMES := ["House Style", "Second Opinion", "The Fast One", "The Careful One"]
	if index < NAMES.size():
		return NAMES[index]
	return "Workflow %d" % (index + 1)


func workflows(run_state: RunState) -> Array:
	var stored: Variant = run_state.build.get("workflows", null)
	return Array(stored) if stored is Array else []


func workflow_count(run_state: RunState) -> int:
	return workflows(run_state).size()


## How many workflows this run is allowed to keep. One to begin with; the rest
## are bought, drafted, or won.
func workflow_capacity(run_state: RunState, content_db: Node = null) -> int:
	if content_db == null:
		return clampi(
			int(run_state.build.get("workflow_capacity", DEFAULT_WORKFLOW_CAPACITY)),
			1,
			MAX_WORKFLOW_COUNT
		)
	return derived_workflow_capacity(run_state, content_db)


static func active_perk_grant_total(run_state: RunState, content_db: Node, grant_key: String) -> int:
	var total: int = 0
	for perk_id in run_state.build.get("perks", []):
		var perk: PerkDefinition = content_db.get_perk(str(perk_id))
		if perk == null:
			continue
		total += int(perk.grants.get(grant_key, 0))
	return total


func derived_slot_count(run_state: RunState, content_db: Node) -> int:
	var board: Dictionary = run_state.build.get("board", {})
	var meta_bonus: int = int(board.get("meta_slot_bonus", 0))
	var perk_bonus: int = active_perk_grant_total(run_state, content_db, "board_slots")
	var upgrade_bonus: int = int(UpgradeSystem.additive_effect_total(
		run_state, content_db, "build.board.slot_count"
	))
	return clampi(
		DEFAULT_SLOT_COUNT + meta_bonus + perk_bonus + upgrade_bonus,
		1,
		MAX_SLOT_COUNT
	)


func derived_workflow_capacity(run_state: RunState, content_db: Node) -> int:
	var meta_bonus: int = int(run_state.build.get("meta_workflow_bonus", 0))
	var perk_bonus: int = active_perk_grant_total(run_state, content_db, "workflow_capacity")
	var upgrade_bonus: int = int(UpgradeSystem.additive_effect_total(
		run_state, content_db, "build.workflow_capacity"
	))
	return clampi(
		DEFAULT_WORKFLOW_CAPACITY + meta_bonus + perk_bonus + upgrade_bonus,
		1,
		MAX_WORKFLOW_COUNT
	)


func _migrate_legacy_board_bonuses(run_state: RunState, content_db: Node) -> void:
	var board: Dictionary = run_state.build.get("board", {})
	if not board.has("meta_slot_bonus"):
		var stored_slots: int = int(board.get("slot_count", DEFAULT_SLOT_COUNT))
		var perk_slots: int = active_perk_grant_total(run_state, content_db, "board_slots")
		var upgrade_slots: int = int(UpgradeSystem.additive_effect_total(
			run_state, content_db, "build.board.slot_count"
		))
		board["meta_slot_bonus"] = maxi(
			0, stored_slots - DEFAULT_SLOT_COUNT - perk_slots - upgrade_slots
		)
		run_state.build["board"] = board
	if not run_state.build.has("meta_workflow_bonus"):
		var stored_capacity: int = int(run_state.build.get("workflow_capacity", DEFAULT_WORKFLOW_CAPACITY))
		var perk_capacity_bonus: int = active_perk_grant_total(run_state, content_db, "workflow_capacity")
		var upgrade_capacity_bonus: int = int(UpgradeSystem.additive_effect_total(
			run_state, content_db, "build.workflow_capacity"
		))
		run_state.build["meta_workflow_bonus"] = maxi(
			0,
			stored_capacity - DEFAULT_WORKFLOW_CAPACITY \
				- perk_capacity_bonus - upgrade_capacity_bonus
		)


func active_workflow_index(run_state: RunState) -> int:
	var board: Dictionary = run_state.build.get("board", {})
	return clampi(int(board.get("active_workflow", 0)), 0, maxi(0, workflow_count(run_state) - 1))


## Points the editor at a workflow. Which one is live for a burn is decided by
## the contract, not by this: it only says whose slots `slots()` returns.
func set_active_workflow(run_state: RunState, index: int) -> bool:
	if index < 0 or index >= workflow_count(run_state):
		return false
	run_state.build["board"]["active_workflow"] = index
	return true


func workflow_at(run_state: RunState, index: int) -> Dictionary:
	var list: Array = workflows(run_state)
	if index < 0 or index >= list.size():
		return {}
	return list[index]


func workflow_by_id(run_state: RunState, workflow_id: String) -> Dictionary:
	for workflow in workflows(run_state):
		if workflow is Dictionary and str(workflow.get("id", "")) == workflow_id:
			return workflow
	return {}


func active_workflow(run_state: RunState) -> Dictionary:
	return workflow_at(run_state, active_workflow_index(run_state))


## The workflow a contract has been assigned, falling back to the first one so a
## job that predates the assignment (or whose workflow was deleted) still burns.
func workflow_for_job(run_state: RunState, job: Dictionary) -> Dictionary:
	var assigned: Dictionary = workflow_by_id(run_state, str(job.get("workflow_id", "")))
	if not assigned.is_empty():
		return assigned
	var list: Array = workflows(run_state)
	return list[0] if not list.is_empty() else {}


func slots_for_job(run_state: RunState, job: Dictionary) -> Array:
	var workflow: Dictionary = workflow_for_job(run_state, job)
	return Array(workflow.get("slots", [])) if not workflow.is_empty() else []


## Adds a workflow, copying the layout of the one currently being edited so the
## player starts from something that works rather than three empty slots.
func create_workflow(run_state: RunState, name: String = "", content_db: Node = null) -> Dictionary:
	var list: Array = workflows(run_state)
	if list.size() >= workflow_capacity(run_state, content_db):
		return {}
	var seed_layout: Array = Array(active_workflow(run_state).get("slots", [])).duplicate()
	var index: int = list.size()
	var used_ids: Array = []
	for workflow in list:
		used_ids.append(str(workflow.get("id", "")))
	var next_id: int = index + 1
	while ("workflow.%d" % next_id) in used_ids:
		next_id += 1
	var created: Dictionary = {
		"id": "workflow.%d" % next_id,
		"name": name if name != "" else _default_workflow_name(index),
		"slots": seed_layout,
	}
	list.append(created)
	run_state.build["workflows"] = list
	run_state.build["board"]["active_workflow"] = list.size() - 1
	return created


func rename_workflow(run_state: RunState, index: int, name: String) -> bool:
	var workflow: Dictionary = workflow_at(run_state, index)
	if workflow.is_empty() or name.strip_edges() == "":
		return false
	workflow["name"] = name.strip_edges().left(28)
	return true


## Removes a workflow and hands its contracts to the first one, so nothing is
## left pointing at a pipeline that no longer exists. The last workflow cannot
## go: a run with none of them could not burn at all.
func delete_workflow(run_state: RunState, index: int) -> bool:
	var list: Array = workflows(run_state)
	if list.size() <= 1 or index < 0 or index >= list.size():
		return false
	var removed_id: String = str(list[index].get("id", ""))
	list.remove_at(index)
	run_state.build["workflows"] = list
	run_state.build["board"]["active_workflow"] = clampi(index, 0, list.size() - 1)
	var fallback_id: String = str(list[0].get("id", ""))
	for collection in ["active_jobs", "job_queue", "job_offers"]:
		for job in run_state.business.get(collection, []):
			if job is Dictionary and str(job.get("workflow_id", "")) == removed_id:
				job["workflow_id"] = fallback_id
	return true


## A workflow with nothing on it cannot burn, so a fresh run opens with a
## working pipeline laid out. Only the modules that declare `opens_pipeline` are
## placed; anything else waits on the bench, which is the point.
func _auto_fill_empty_workflows(run_state: RunState, content_db: Node) -> void:
	var owned: Array = Array(run_state.build.get("modules", []))
	var opening: Array = content_db.opening_pipeline_modules()
	for workflow in workflows(run_state):
		var layout: Array = Array(workflow.get("slots", []))
		var filled: int = 0
		for entry in layout:
			if str(entry) != "":
				filled += 1
		if filled > 0:
			continue
		var index: int = 0
		for op_id in opening:
			if index >= layout.size():
				break
			if not (str(op_id) in owned):
				continue
			layout[index] = str(op_id)
			index += 1
		# A profile or save with an unusual module set may not cover the opening
		# pipeline, so anything still empty falls back to what is owned.
		for op_id in owned:
			if index >= layout.size():
				break
			if str(op_id) in layout:
				continue
			layout[index] = str(op_id)
			index += 1


## The workflow the editor is pointed at. Every existing call site that reads or
## writes `slots()` keeps working; which workflow that is has simply become a
## choice rather than a fact.
func slots(run_state: RunState) -> Array:
	var workflow: Dictionary = active_workflow(run_state)
	if workflow.is_empty() or not workflow.get("slots", null) is Array:
		return []
	return workflow["slots"]


func slot_count(run_state: RunState) -> int:
	return slots(run_state).size()


func filled_slot_count(run_state: RunState) -> int:
	return filled_count(slots(run_state))


func filled_count(layout: Array) -> int:
	var count: int = 0
	for entry in layout:
		if str(entry) != "":
			count += 1
	return count


func owned_modules(run_state: RunState) -> Array:
	return Array(run_state.build.get("modules", []))


func grant_module(run_state: RunState, module_id: String) -> bool:
	var owned: Array = owned_modules(run_state)
	if module_id in owned:
		return false
	owned.append(module_id)
	run_state.build["modules"] = owned
	# A newly drafted module goes straight into the first free slot so it is
	# in play without a detour through the board screen.
	var board_slots: Array = slots(run_state)
	for i in range(board_slots.size()):
		if str(board_slots[i]) == "":
			board_slots[i] = module_id
			break
	return true


## Slots a contract has taken over before the player touches it: legacy code,
## undocumented APIs, Steve's script.
func blocked_slots(job: Dictionary) -> int:
	return int(job.get("blocked_slots", 0))


func is_slot_usable(run_state: RunState, job: Dictionary, index: int) -> bool:
	if index < 0 or index >= slot_count(run_state):
		return false
	return index >= blocked_slots(job)


## Moves modules out of slots a contract has taken over, keeping their order.
## Applied to the workflow the contract is assigned, not to whichever one the
## editor happens to be showing. Returns the ids it could not find room for.
func compact_for_job(run_state: RunState, job: Dictionary) -> Array:
	var board_slots: Array = slots_for_job(run_state, job)
	var blocked: int = blocked_slots(job)
	if blocked <= 0:
		return []
	var displaced: Array = []
	for i in range(mini(blocked, board_slots.size())):
		if str(board_slots[i]) != "":
			displaced.append(str(board_slots[i]))
			board_slots[i] = ""
	var homeless: Array = []
	for module_id in displaced:
		var placed: bool = false
		for i in range(blocked, board_slots.size()):
			if str(board_slots[i]) == "":
				board_slots[i] = module_id
				placed = true
				break
		if not placed:
			homeless.append(module_id)
	return homeless


func place_module(run_state: RunState, job: Dictionary, module_id: String, index: int) -> bool:
	if not is_slot_usable(run_state, job, index):
		return false
	if module_id != "" and not (module_id in owned_modules(run_state)):
		return false
	var board_slots: Array = slots(run_state)
	# One copy of a module can only be in one place at a time.
	if module_id != "":
		for i in range(board_slots.size()):
			if str(board_slots[i]) == module_id:
				board_slots[i] = ""
	board_slots[index] = module_id
	return true


func clear_slot(run_state: RunState, job: Dictionary, index: int) -> bool:
	if not is_slot_usable(run_state, job, index):
		return false
	slots(run_state)[index] = ""
	return true


func swap_slots(run_state: RunState, job: Dictionary, from_index: int, to_index: int) -> bool:
	if not is_slot_usable(run_state, job, from_index) or not is_slot_usable(run_state, job, to_index):
		return false
	var board_slots: Array = slots(run_state)
	var moved: Variant = board_slots[from_index]
	board_slots[from_index] = board_slots[to_index]
	board_slots[to_index] = moved
	return true


# --- Burn resolution ---------------------------------------------------------

## Sends `base_tokens` through the pipeline and reports what came out. Pure with
## respect to the job: nothing is applied here, so the same call can drive a
## preview animation and then the authoritative commit.
##
## `stage_limit` truncates the pipeline, which is how KILL PROCESS stops a batch
## before a dangerous stage activates.
func resolve_burn(
	run_state: RunState,
	job: Dictionary,
	base_tokens: float,
	rng: DeterministicRng,
	effect_resolver: EffectResolver,
	subscriptions: Array,
	stage_limit: int = -1,
	mode: int = ResolveMode.COMMIT
) -> Dictionary:
	var workflow: Dictionary = workflow_for_job(run_state, job)
	var board_slots: Array = Array(workflow.get("slots", []))
	var order: Array = _stage_order(board_slots, blocked_slots(job))
	if order.is_empty():
		return {
			"ok": false,
			"reason": "%s is empty. Place a module in a slot first." % str(
				workflow.get("name", "This workflow")
			),
			"job_id": str(job.get("id", "")),
			"workflow_id": str(workflow.get("id", "")),
			"workflow_name": str(workflow.get("name", "")),
			"stages": [],
			"messages": [],
		}

	var limit: int = order.size() if stage_limit < 0 else clampi(stage_limit, 0, order.size())
	var rules: Array = Array(job.get("board_rules", []))
	var messages: Array[String] = []
	var batch: Dictionary = {
		"tokens": base_tokens,
		"token_mult": 1.0,
		"progress_mult": 1.0,
		"quality": 0.0,
		"heat": 0.0,
		"cost": 0.0,
		"hide_bugs": 0.0,
		"quality_to_progress": 0.0,
		"known_bugs": float(job.get("known_bugs", 0)),
		"hidden_bugs": float(job.get("hidden_bugs", 0)),
		"revealed": 0.0,
		"fixed": 0.0,
		"scope_tokens": 0.0,
	}
	var bugs_before: float = batch["known_bugs"]
	var hidden_before: float = batch["hidden_bugs"]

	var start_heat_ratio: float = _heat_ratio(run_state)
	var dropped_stages: int = 0
	_dispatch_batch_event(
		EVENT_BATCH_STARTED, run_state, job, batch, rng, effect_resolver, subscriptions, {
			"stage_count": order.size(),
			"slot_count": board_slots.size(),
			"heat_ratio": start_heat_ratio,
			"start_heat_ratio": start_heat_ratio,
		}, board_slots
	)

	var stages: Array = []
	var pending_multiplier: float = 1.0
	var pending_cost_mult: float = 1.0
	var previous_stage: Dictionary = {}
	var cascade_history: Array = []
	var cascade_guard := ChainGuard.new("board.cascade")
	var reached_modules: Array = []

	for position in range(limit):
		var index: int = int(order[position])
		var module_id: String = str(board_slots[index])
		if module_id != "":
			reached_modules.append(module_id)
		var module: ModuleDefinition = ContentDatabase.get_module(module_id)
		if module == null:
			continue
		var stage: Dictionary = STAGE_DEFAULTS.duplicate(true)
		_dispatch_stage(
			run_state, job, batch, stage, module, rng, effect_resolver, subscriptions,
			board_slots, order, position, index
		)
		var rule_multiplier: float = _tag_bonus_for(rules, module)
		var effective_multiplier: float = pending_multiplier * rule_multiplier
		var before: Dictionary = _snapshot(batch)
		var dropped: bool = _maybe_drop_stage(run_state, rng, index)
		var cascaded: bool = false
		var cascade_depth: int = 0
		if not dropped:
			_maybe_redline_twist(run_state, rng, stage, batch, index)
		var repeat: float = maxf(0.0, float(stage["repeat_previous"]))
		var repeat_strength: float = maxf(0.0, float(stage["repeat_strength"]))
		var repeat_count: int = maxi(0, int(round(float(stage["repeat_count"]))))
		if dropped:
			dropped_stages += 1
			messages.append("%s dropped — the rack blinked." % module.name)
		else:
			_fold(batch, stage, effective_multiplier, pending_cost_mult)
			if repeat > 0.0 and repeat_count > 0 and not previous_stage.is_empty():
				for _fork in range(repeat_count):
					_fold(
						batch, previous_stage,
						repeat * repeat_strength * effective_multiplier, pending_cost_mult
					)
				run_state.statistics["stage_repeats"] = int(
					run_state.statistics.get("stage_repeats", 0)
				) + repeat_count
			_apply_stage_rules(rules, module, stage, batch, job, messages)
			cascade_depth = _maybe_cascade(
				run_state, job, batch, stage, cascade_history, module, rng,
				effect_resolver, subscriptions, board_slots, effective_multiplier,
				pending_cost_mult, index, cascade_guard, mode
			)
			cascaded = cascade_depth > 0
			if cascaded:
				messages.append("%s cascaded." % module.name)
			cascade_history.append({
				"stage": stage.duplicate(true),
				"module_id": module.id,
				"index": index,
			})

		var previous_id: String = str(board_slots[int(order[position - 1])]) if position > 0 else ""
		var next_id: String = (
			str(board_slots[int(order[position + 1])]) if position < order.size() - 1 else ""
		)
		var live_combos: Array = []
		for combo in module.active_combos(previous_id, next_id):
			live_combos.append({"name": str(combo.get("name", ""))})

		stages.append({
			"slot_index": index,
			"position": position,
			"module_id": module.id,
			"name": module.name,
			"badge": module.badge,
			"category": module.category,
			"multiplier": effective_multiplier,
			"repeated_previous": 0.0 if dropped else repeat,
			"repeat_strength": repeat_strength,
			"repeat_count": 0 if dropped else repeat_count,
			"combos": live_combos,
			"cascaded": cascaded,
			"cascade_depth": cascade_depth,
			"dropped": dropped,
			"stage": stage,
			"before": before,
			"after": _snapshot(batch),
		})

		pending_multiplier = maxf(0.0, float(stage["next_multiplier"]))
		pending_cost_mult = maxf(0.0, float(stage["next_cost_mult"]))
		previous_stage = stage

	# What the contract asked of this workflow, and what it costs to have
	# ignored it. Judged on the modules placed rather than on the stages that
	# happened to fire, so the verdict is the one the job card advertised.
	var demands: Array = demand_report(job, board_slots, blocked_slots(job))
	var bug_chance_mult: float = _apply_demands(demands, batch, messages)

	_dispatch_batch_event(
		EVENT_BATCH_FINALIZING, run_state, job, batch, rng, effect_resolver, subscriptions, {
			"stage_count": limit,
			"slot_count": board_slots.size(),
			"start_heat_ratio": start_heat_ratio,
			"batch_faulted": dropped_stages > 0,
			"batch_survived": dropped_stages == 0 and start_heat_ratio >= 1.0,
		}, reached_modules
	)

	var tokens: float = maxf(0.0, base_tokens * maxf(0.0, float(batch["token_mult"])))
	var progress_tokens: float = tokens * maxf(0.0, float(batch["progress_mult"]))
	var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
	var convert: float = clampf(float(batch["quality_to_progress"]), 0.0, 1.0)
	var converted_quality: float = 0.0
	if convert > 0.0:
		converted_quality = maxf(0.0, float(batch["quality"])) * convert
		progress_tokens += requirement * (converted_quality / 100.0)
		batch["quality"] = float(batch["quality"]) - converted_quality

	batch["progress_tokens"] = progress_tokens
	_dispatch_batch_event(
		EVENT_BATCH_FINISHED, run_state, job, batch, rng, effect_resolver, subscriptions, {
			"stage_count": limit,
			"slot_count": board_slots.size(),
			"start_heat_ratio": start_heat_ratio,
			"batch_faulted": dropped_stages > 0,
		}, board_slots
	)

	return {
		"ok": true,
		"reason": "",
		"job_id": str(job.get("id", "")),
		"workflow_id": str(workflow.get("id", "")),
		"workflow_name": str(workflow.get("name", "")),
		"demands": demands,
		"bug_chance_mult": bug_chance_mult,
		"base_tokens": base_tokens,
		"tokens": tokens,
		"token_mult": float(batch["token_mult"]),
		"progress_mult": float(batch["progress_mult"]),
		"progress_tokens": maxf(0.0, float(batch["progress_tokens"])),
		"quality": float(batch["quality"]),
		"quality_converted": converted_quality,
		# Signed: a pipeline built around Liquid Cooling or a tripped Circuit
		# Breaker is meant to take heat back off the rig, and clamping the total
		# at zero here made those modules do nothing once the rig was already
		# hot. `_apply_burn` is what keeps stored heat from going negative.
		"heat": float(batch["heat"]),
		"cost": maxf(0.0, float(batch["cost"])),
		"known_bugs": maxi(0, int(round(float(batch["known_bugs"])))),
		"hidden_bugs": maxi(0, int(round(float(batch["hidden_bugs"])))),
		"bugs_added": maxi(0, int(round(float(batch["known_bugs"]) - bugs_before))),
		"hidden_added": maxi(0, int(round(float(batch["hidden_bugs"]) - hidden_before))),
		"revealed": maxi(0, int(round(float(batch["revealed"])))),
		"fixed": maxi(0, int(round(float(batch["fixed"])))),
		"scope_tokens": maxf(0.0, float(batch["scope_tokens"])),
		"hides_bugs": float(batch["hide_bugs"]) > 0.0,
		"stages": stages,
		"stage_count": stages.size(),
		"truncated": limit < order.size(),
		"messages": messages,
	}


# --- Contract demands --------------------------------------------------------

## What a workflow can do, read off the modules in its reachable slots. Static
## on purpose: the job card, the assignment picker and the burn all have to give
## the same answer, and only a burn knows which conditional effects fired.
func pipeline_capabilities(board_slots: Array, blocked: int = 0) -> Dictionary:
	var found: Dictionary = {
		CAPABILITY_FIX_BUGS: false,
		CAPABILITY_REVEAL_BUGS: false,
		CAPABILITY_HEAVY_QUALITY: false,
		CAPABILITY_THROUGHPUT: false,
		CAPABILITY_COOLING: false,
		"cost": 0.0,
		"modules": 0,
	}
	for index in range(board_slots.size()):
		if index < blocked:
			continue
		var module: ModuleDefinition = ContentDatabase.get_module(str(board_slots[index]))
		if module == null:
			continue
		found["modules"] = int(found["modules"]) + 1
		for effect in module.slot_effects:
			if not effect is Dictionary:
				continue
			var target: String = str(effect.get("target", ""))
			var operator: String = str(effect.get("operation", "add"))
			var value: float = _parameter_value(effect.get("value", 0), module.parameters)
			match target:
				"stage.fix_bugs", "stage.fix_hidden_bugs":
					if value > 0.0:
						found[CAPABILITY_FIX_BUGS] = true
				"stage.reveal_bugs":
					if value > 0.0:
						found[CAPABILITY_REVEAL_BUGS] = true
				"stage.token_mult":
					found[CAPABILITY_THROUGHPUT] = true
				"stage.quality":
					if operator == "add" and value >= HEAVY_QUALITY_THRESHOLD:
						found[CAPABILITY_HEAVY_QUALITY] = true
				"stage.heat":
					if value < 0.0:
						found[CAPABILITY_COOLING] = true
				"stage.cost":
					if operator == "add" and value > 0.0:
						found["cost"] = float(found["cost"]) + value
	return found


## `$name` in an effect resolves against the module's own parameters; a reroll's
## value is a spec rather than a number and contributes nothing measurable.
func _parameter_value(raw: Variant, parameters: Dictionary) -> float:
	if raw is String and str(raw).begins_with("$"):
		raw = parameters.get(str(raw).substr(1), 0.0)
	if raw is bool:
		return 1.0 if raw else 0.0
	if raw is int or raw is float:
		return float(raw)
	return 0.0


static func demand_definitions() -> Dictionary:
	return ContentDatabase.balance.get("job_demands", {})


## Every demand this contract makes, and whether the given layout answers it.
## Pure and cheap, so the UI can call it per card.
func demand_report(job: Dictionary, board_slots: Array, blocked: int = 0) -> Array:
	var declared: Array = Array(job.get("demands", []))
	if declared.is_empty():
		return []
	var definitions: Dictionary = demand_definitions()
	var capabilities: Dictionary = pipeline_capabilities(board_slots, blocked)
	var report: Array = []
	for demand_id in declared:
		var definition: Variant = definitions.get(str(demand_id), null)
		if not definition is Dictionary:
			continue
		var match_spec: Dictionary = Dictionary(definition.get("match", {}))
		var met: bool = true
		var requirement: String = str(definition.get("requirement", ""))
		if match_spec.has("capability"):
			met = bool(capabilities.get(str(match_spec["capability"]), false))
		elif match_spec.has("max_cost"):
			var budget: float = float(match_spec["max_cost"])
			met = float(capabilities.get("cost", 0.0)) <= budget
			requirement = requirement.replace("{value}", str(int(budget)))
		report.append({
			"id": str(demand_id),
			"name": str(definition.get("name", demand_id)),
			"short": str(definition.get("short", definition.get("name", demand_id))),
			"requirement": requirement,
			"met": met,
			"note": str(definition.get("met_note" if met else "unmet_note", "")),
			"effects": Dictionary(definition.get("met" if met else "unmet", {})),
		})
	return report


## Folds the verdict into the batch and reports the multiplier the contract's
## own defect roll should carry. A satisfied demand is a modest bonus; an
## ignored one is meant to hurt, because that is the decision being made.
func _apply_demands(demands: Array, batch: Dictionary, messages: Array[String]) -> float:
	var bug_chance_mult: float = 1.0
	for entry in demands:
		var effects: Dictionary = Dictionary(entry.get("effects", {}))
		if effects.is_empty():
			continue
		batch["quality"] = float(batch["quality"]) + float(effects.get("quality", 0.0))
		batch["progress_mult"] = float(batch["progress_mult"]) * float(effects.get("progress_mult", 1.0))
		batch["hidden_bugs"] = float(batch["hidden_bugs"]) + maxf(0.0, float(effects.get("hidden_bugs", 0.0)))
		batch["cost"] = float(batch["cost"]) * maxf(0.0, float(effects.get("cost_mult", 1.0)))
		bug_chance_mult *= maxf(0.0, float(effects.get("bug_chance_mult", 1.0)))
		if not bool(entry.get("met", false)):
			messages.append("%s: %s" % [str(entry.get("name", "This contract")), str(entry.get("note", ""))])
	return bug_chance_mult


## Match summary for one workflow against one contract, for the assignment UI.
func workflow_match(run_state: RunState, job: Dictionary, workflow: Dictionary) -> Dictionary:
	var layout: Array = Array(workflow.get("slots", []))
	var report: Array = demand_report(job, layout, blocked_slots(job))
	var met: int = 0
	for entry in report:
		if bool(entry.get("met", false)):
			met += 1
	return {
		"workflow_id": str(workflow.get("id", "")),
		"name": str(workflow.get("name", "")),
		"demands": report,
		"met": met,
		"total": report.size(),
		"modules": filled_count(layout),
		"perfect": report.size() > 0 and met == report.size(),
	}


func _stage_order(board_slots: Array, blocked: int) -> Array:
	var order: Array = []
	for i in range(board_slots.size()):
		if i < blocked:
			continue
		if str(board_slots[i]) != "":
			order.append(i)
	return order


func _dispatch_stage(
	run_state: RunState,
	job: Dictionary,
	batch: Dictionary,
	stage: Dictionary,
	module: ModuleDefinition,
	rng: DeterministicRng,
	effect_resolver: EffectResolver,
	subscriptions: Array,
	board_slots: Array,
	order: Array,
	position: int,
	index: int
) -> void:
	var mod_ctx := ModifierContext.new(EVENT_STAGE_RESOLVED, run_state)
	mod_ctx.rng = rng.derive("stage_%d_%s" % [index, module.id])
	mod_ctx.job = job
	mod_ctx.tags = PackedStringArray(Array(job.get("tags", [])))
	var previous_id: String = str(board_slots[int(order[position - 1])]) if position > 0 else ""
	var next_id: String = (
		str(board_slots[int(order[position + 1])]) if position < order.size() - 1 else ""
	)
	mod_ctx.extras = {
		"slot_index": index,
		"stage_position": position,
		"slot_count": board_slots.size(),
		"stage_count": order.size(),
		"is_first_stage": position == 0,
		"is_last_stage": position == order.size() - 1,
		# `op` and `module` name the same thing. Content ids stayed `op.*`, so the
		# short spelling stays authored and supported alongside the domain word.
		"prev_op": previous_id,
		"next_op": next_id,
		"prev_module": previous_id,
		"next_module": next_id,
		"op_id": module.id,
		"op_category": module.category,
		"module_id": module.id,
		"module_category": module.category,
		"heat_ratio": _heat_ratio(run_state),
		"stage_roll": rng.derive("stage_roll_%d_%s" % [index, module.id]).next_float(),
		"instability": float(run_state.compute.get("instability", 0.0)),
	}
	for key in stage.keys():
		mod_ctx.set_value("stage.%s" % key, stage[key])
	for key in batch.keys():
		mod_ctx.set_value("batch.%s" % key, batch[key])

	var stage_subscriptions: Array = subscriptions.duplicate()
	stage_subscriptions.append_array(module.to_subscriptions(EVENT_STAGE_RESOLVED))
	effect_resolver.begin_action("board.stage.%d.%s" % [index, module.id])
	effect_resolver.dispatch(EVENT_STAGE_RESOLVED, mod_ctx, stage_subscriptions)

	for key in stage.keys():
		stage[key] = _as_float(mod_ctx.get_value("stage.%s" % key, stage[key]))
	for key in batch.keys():
		batch[key] = _as_float(mod_ctx.get_value("batch.%s" % key, batch[key]))


func _dispatch_batch_event(
	event_name: String,
	run_state: RunState,
	job: Dictionary,
	batch: Dictionary,
	rng: DeterministicRng,
	effect_resolver: EffectResolver,
	subscriptions: Array,
	extras: Dictionary,
	board_slots: Array = []
) -> void:
	var mod_ctx := ModifierContext.new(event_name, run_state)
	mod_ctx.rng = rng.derive(event_name)
	mod_ctx.job = job
	mod_ctx.tags = PackedStringArray(Array(job.get("tags", [])))
	mod_ctx.extras = extras.duplicate()
	mod_ctx.extras["heat_ratio"] = _heat_ratio(run_state)
	for key in batch.keys():
		mod_ctx.set_value("batch.%s" % key, batch[key])
	var event_subscriptions: Array = subscriptions.duplicate()
	event_subscriptions.append_array(_module_event_subscriptions(board_slots, event_name))
	effect_resolver.begin_action(event_name)
	effect_resolver.dispatch(event_name, mod_ctx, event_subscriptions)
	for key in batch.keys():
		batch[key] = _as_float(mod_ctx.get_value("batch.%s" % key, batch[key]))


func _module_event_subscriptions(board_slots: Array, event_name: String) -> Array:
	var extra: Array = []
	if event_name != EVENT_BATCH_FINALIZING:
		return extra
	for module_id in board_slots:
		var module: ModuleDefinition = ContentDatabase.get_module(str(module_id))
		if module == null:
			continue
		extra.append_array(module.to_finalizing_subscriptions(event_name))
	return extra


func _maybe_drop_stage(run_state: RunState, rng: DeterministicRng, index: int) -> bool:
	if not FeatureFlags.is_enabled("instability_enabled"):
		return false
	var tier: int = HeatSystem.work_tier(run_state)
	var ratio: float = _heat_ratio(run_state)
	if tier < 2 or ratio < 1.0:
		return false
	var band_t: float = clampf((ratio - 1.0) / 0.40, 0.0, 1.0)
	return rng.derive("drop_%d" % index).next_float() < 0.10 * band_t


func _maybe_redline_twist(
	run_state: RunState,
	rng: DeterministicRng,
	stage: Dictionary,
	batch: Dictionary,
	index: int
) -> void:
	if not FeatureFlags.is_enabled("instability_enabled"):
		return
	var tier: int = HeatSystem.work_tier(run_state)
	var ratio: float = _heat_ratio(run_state)
	if tier < 2 or ratio < 1.0:
		return
	var band_t: float = clampf((ratio - 1.0) / 0.40, 0.0, 1.0)
	if rng.derive("corrupt_%d" % index).next_float() < 0.12 * band_t:
		batch["quality"] = maxf(0.0, float(batch["quality"]) - 4.0)
	if rng.derive("rerun_%d" % index).next_float() < 0.10 * band_t:
		stage["repeat_count"] = float(stage["repeat_count"]) + 1.0
		stage["heat"] = float(stage["heat"]) + 6.0


func _maybe_cascade(
	run_state: RunState,
	job: Dictionary,
	batch: Dictionary,
	stage: Dictionary,
	history: Array,
	module: ModuleDefinition,
	rng: DeterministicRng,
	effect_resolver: EffectResolver,
	subscriptions: Array,
	board_slots: Array,
	effective_multiplier: float,
	pending_cost_mult: float,
	index: int,
	guard: ChainGuard,
	mode: int
) -> int:
	if history.is_empty():
		return 0
	if not _cascade_hits(run_state, stage, rng, index, 0):
		return 0
	var strength: float = maxf(0.0, float(stage.get("cascade_strength", 1.0)))
	var queue: Array = [{
		"hist": history.size() - 1,
		"depth": 1,
		"multiplier": strength * effective_multiplier,
		"cost_mult": pending_cost_mult,
		"source_id": module.id,
	}]
	return _drain_cascade_queue(
		queue, history, guard, run_state, job, batch, rng, effect_resolver,
		subscriptions, board_slots, mode
	)


func _cascade_hits(
	run_state: RunState, stage: Dictionary, rng: DeterministicRng, index: int, depth: int
) -> bool:
	if not FeatureFlags.is_enabled("cascade_enabled"):
		return false
	var chance: float = maxf(0.0, float(stage.get("cascade_chance", 0.0)))
	var heat_ratio: float = _heat_ratio(run_state)
	if heat_ratio >= 0.85:
		chance += (heat_ratio - 0.85) * float(HeatSystem.heat_config().get("cascade_heat_scale", 0.40))
	var work_tier: int = HeatSystem.work_tier(run_state)
	if chance <= 0.0 or (work_tier < 4 and float(stage.get("cascade_chance", 0.0)) <= 0.0):
		return false
	chance = clampf(chance, 0.0, 0.65)
	return rng.derive("cascade_%d_%d" % [index, depth]).next_float() < chance


func _drain_cascade_queue(
	queue: Array,
	history: Array,
	guard: ChainGuard,
	run_state: RunState,
	job: Dictionary,
	batch: Dictionary,
	rng: DeterministicRng,
	effect_resolver: EffectResolver,
	subscriptions: Array,
	board_slots: Array,
	mode: int
) -> int:
	var triggered: int = 0
	while not queue.is_empty():
		if not guard.can_continue(EventBus.EVENT_CASCADE_TRIGGERED):
			break
		var proc: Dictionary = queue.pop_front()
		var hist_index: int = int(proc.get("hist", -1))
		if hist_index < 0 or hist_index >= history.size():
			continue
		guard.record(EventBus.EVENT_CASCADE_TRIGGERED)
		var entry: Dictionary = history[hist_index]
		var replay: Dictionary = Dictionary(entry.get("stage", {}))
		if replay.is_empty():
			continue
		var multiplier: float = float(proc.get("multiplier", 1.0))
		var cost_mult: float = float(proc.get("cost_mult", 1.0))
		_fold(batch, replay, multiplier, cost_mult)
		triggered += 1
		run_state.statistics["cascades_triggered"] = int(
			run_state.statistics.get("cascades_triggered", 0)
		) + 1
		var heat_ratio: float = _heat_ratio(run_state)
		var source_module_id: String = str(proc.get("source_id", ""))
		var replayed_module_id: String = str(entry.get("module_id", ""))
		var payload := {
			"module_id": source_module_id if source_module_id != "" else replayed_module_id,
			"source_module_id": source_module_id,
			"replayed_module_id": replayed_module_id,
			"heat_ratio": heat_ratio,
		}
		if mode == ResolveMode.COMMIT:
			EventBus.emit_event(EventBus.EVENT_CASCADE_TRIGGERED, payload)
		_dispatch_batch_event(
			EventBus.EVENT_CASCADE_TRIGGERED, run_state, job, batch, rng, effect_resolver,
			subscriptions, payload, board_slots
		)
		var prior: Dictionary = {}
		if hist_index > 0:
			prior = Dictionary(history[hist_index - 1].get("stage", {}))
		var repeat: float = maxf(0.0, float(replay.get("repeat_previous", 0.0)))
		var repeat_strength: float = maxf(0.0, float(replay.get("repeat_strength", 1.0)))
		var repeat_count: int = maxi(0, int(round(float(replay.get("repeat_count", 0.0)))))
		if repeat > 0.0 and repeat_count > 0 and not prior.is_empty():
			for _fork in range(repeat_count):
				_fold(batch, prior, repeat * repeat_strength * multiplier, cost_mult)
			run_state.statistics["stage_repeats"] = int(
				run_state.statistics.get("stage_repeats", 0)
			) + repeat_count
		var next_depth: int = int(proc.get("depth", 1))
		if hist_index > 0 and _cascade_hits(
			run_state, replay, rng, int(entry.get("index", 0)), next_depth
		):
			if guard.can_continue(EventBus.EVENT_CASCADE_TRIGGERED):
				queue.append({
					"hist": hist_index - 1,
					"depth": next_depth + 1,
					"multiplier": maxf(0.0, float(replay.get("cascade_strength", 1.0))) * multiplier,
					"cost_mult": cost_mult,
					"source_id": replayed_module_id,
				})
	return triggered


## Folds one stage's contribution into the batch at `multiplier` strength. A
## multiplier below 1 is a partial re-run (an agent echoing the stage above it);
## above 1 is a stage being amplified by the one before it.
func _fold(batch: Dictionary, stage: Dictionary, multiplier: float, cost_mult: float) -> void:
	var strength: float = maxf(0.0, multiplier)
	batch["token_mult"] = float(batch["token_mult"]) * _scaled_multiplier(float(stage["token_mult"]), strength)
	batch["progress_mult"] = float(batch["progress_mult"]) * _scaled_multiplier(float(stage["progress_mult"]), strength)
	batch["quality"] = float(batch["quality"]) + float(stage["quality"]) * strength
	batch["heat"] = float(batch["heat"]) + float(stage["heat"]) * strength
	batch["cost"] = float(batch["cost"]) + float(stage["cost"]) * strength * maxf(0.0, cost_mult)
	batch["quality_to_progress"] = (
		float(batch["quality_to_progress"]) + float(stage["quality_to_progress"]) * strength
	)

	var new_bugs: float = maxf(0.0, float(stage["bugs"]) * strength)
	if float(batch["hide_bugs"]) > 0.0:
		batch["hidden_bugs"] = float(batch["hidden_bugs"]) + new_bugs
	else:
		batch["known_bugs"] = float(batch["known_bugs"]) + new_bugs
	batch["hidden_bugs"] = float(batch["hidden_bugs"]) + maxf(0.0, float(stage["hidden_bugs"]) * strength)
	batch["hide_bugs"] = float(batch["hide_bugs"]) + float(stage["hide_bugs"]) * strength

	var reveal: float = minf(maxf(0.0, float(stage["reveal_bugs"]) * strength), float(batch["hidden_bugs"]))
	if reveal > 0.0:
		batch["hidden_bugs"] = float(batch["hidden_bugs"]) - reveal
		batch["known_bugs"] = float(batch["known_bugs"]) + reveal
		batch["revealed"] = float(batch["revealed"]) + reveal
	var fixed: float = minf(maxf(0.0, float(stage["fix_bugs"]) * strength), float(batch["known_bugs"]))
	if fixed > 0.0:
		batch["known_bugs"] = float(batch["known_bugs"]) - fixed
		batch["fixed"] = float(batch["fixed"]) + fixed
	var hidden_fixed: float = minf(
		maxf(0.0, float(stage["fix_hidden_bugs"]) * strength), float(batch["hidden_bugs"])
	)
	if hidden_fixed > 0.0:
		batch["hidden_bugs"] = float(batch["hidden_bugs"]) - hidden_fixed
		batch["fixed"] = float(batch["fixed"]) + hidden_fixed


## A multiplier applied at partial strength keeps its direction but shrinks its
## distance from 1, so a 30% echo of a ×2 stage is ×1.3 rather than ×0.6.
func _scaled_multiplier(value: float, strength: float) -> float:
	return maxf(0.0, 1.0 + (value - 1.0) * strength)


func _tag_bonus_for(rules: Array, module: ModuleDefinition) -> float:
	var multiplier: float = 1.0
	for rule in rules:
		if not rule is Dictionary or str(rule.get("type", "")) != RULE_TAG_BONUS:
			continue
		var tag: String = str(rule.get("tag", ""))
		if tag != "" and (tag in Array(module.tags) or tag == module.category):
			multiplier *= float(rule.get("value", 1.0))
	return multiplier


func _apply_stage_rules(
	rules: Array,
	module: ModuleDefinition,
	stage: Dictionary,
	batch: Dictionary,
	job: Dictionary,
	messages: Array[String]
) -> void:
	for rule in rules:
		if not rule is Dictionary:
			continue
		match str(rule.get("type", "")):
			RULE_RECURSION_RISK:
				var repeat: float = maxf(0.0, float(stage["repeat_previous"]))
				var forks: float = maxf(0.0, float(stage["repeat_count"]))
				if repeat <= 0.0 or forks <= 0.0:
					continue
				batch["quality"] = float(batch["quality"]) - float(rule.get("value", 0.0)) * repeat * forks
				messages.append("Compliance flags the recursive stage: quality docked.")
			RULE_AGENT_SCOPE:
				if not ("agent" in Array(module.tags)):
					continue
				var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
				batch["scope_tokens"] = float(batch["scope_tokens"]) + requirement * float(rule.get("value", 0.0))
				messages.append("%s invented another requirement." % module.name)


func _snapshot(batch: Dictionary) -> Dictionary:
	return {
		"progress_mult": float(batch["progress_mult"]),
		"token_mult": float(batch["token_mult"]),
		"quality": float(batch["quality"]),
		"heat": float(batch["heat"]),
		"cost": float(batch["cost"]),
		"known_bugs": float(batch["known_bugs"]),
		"hidden_bugs": float(batch["hidden_bugs"]),
	}


func _heat_ratio(run_state: RunState) -> float:
	return float(run_state.compute.get("heat", 0.0)) / maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))


func _as_float(value: Variant, fallback: float = 0.0) -> float:
	if value is bool:
		return 1.0 if value else 0.0
	if value is int or value is float:
		return float(value)
	return fallback
