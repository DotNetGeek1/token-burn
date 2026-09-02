class_name ModuleDefinition
extends Resource

## Static definition for a Burn Board module: the thing the player drops into a
## pipeline slot. Effects target the reserved `stage.*` and `batch.*` paths that
## BoardSystem folds into a burn result.

@export var id: String = ""
@export var name: String = ""
@export var category: String = ""
@export var rarity: String = "common"
@export var tags: PackedStringArray = []
@export var description_template: String = ""
## Short badge shown on the slot itself, e.g. "×1.8" or "Repeat".
@export var badge: String = ""
@export var parameters: Dictionary = {}
@export var slot_effects: Array[Dictionary] = []
## Ordering against perk subscriptions on board.stage_resolved.
@export var priority: int = 50
## Owned from the first round of a run. A run starts owning more starters than
## it has slots, so being owned is not the same as being in the pipeline.
@export var starter: bool = false
## Placed on the board at the start of a run, rather than waiting on the bench.
@export var opens_pipeline: bool = false
## Achievement that has to be earned before this module joins the draft pool.
## Blank means it is available from the first run.
@export var unlock_achievement: String = ""
## Total campaign victories required before this module joins the draft pool.
@export var min_victories: int = 0
## Hard-difficulty victories required before this module joins the draft pool.
@export var min_hard_victories: int = 0
@export var min_location_tier: int = 0
@export var max_location_tier: int = -1
@export var draft_weight: float = 1.0
@export var difficulty: PackedStringArray = ["normal", "hard"]
## Named adjacency pairings, declared so the pipeline editor can show them
## before the player finds them by accident. Each entry names the modules it
## reacts to in `after` (the stage above) or `before` (the stage below), and
## carries its own `effects`.
##
## The combo is the single source of truth: `to_subscriptions()` compiles those
## effects into the `$prev_module` / `$next_module` conditions the resolver gates
## on.
## Written the other way round — advertisement here, mechanics in `slot_effects`
## — the tooltip could promise "works after X" while the effect checked for Y,
## and nothing would catch it.
@export var combos: Array[Dictionary] = []
## Optional effects on `board.batch_finalizing`, so a module can change the
## finished batch (Dead Man's Switch) without pretending those are slot effects.
@export var finalizing_effects: Array[Dictionary] = []
## After a stage has folded, so a card can react to bugs it just created or
## revealed without guessing during slot resolution.
@export var folded_effects: Array[Dictionary] = []
## Fired when the assigned contract first completes, through the mastery event.
@export var completion_effects: Array[Dictionary] = []


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"category": category,
		"rarity": rarity,
		"tags": Array(tags),
		"description_template": description_template,
		"badge": badge,
		"parameters": parameters,
		"slot_effects": slot_effects,
		"priority": priority,
		"starter": starter,
		"opens_pipeline": opens_pipeline,
		"unlock_achievement": unlock_achievement,
		"min_victories": min_victories,
		"min_hard_victories": min_hard_victories,
		"min_location_tier": min_location_tier,
		"max_location_tier": max_location_tier,
		"draft_weight": draft_weight,
		"difficulty": Array(difficulty),
		"combos": combos,
		"finalizing_effects": finalizing_effects,
		"folded_effects": folded_effects,
		"completion_effects": completion_effects,
	}


## The modules this one pairs with, in either direction.
func combo_partners() -> Array:
	var partners: Array = []
	for combo in combos:
		if not combo is Dictionary:
			continue
		for key in ["after", "before"]:
			for partner_id in Array(combo.get(key, [])):
				if not (str(partner_id) in partners):
					partners.append(str(partner_id))
	return partners


## Whichever combos are live for this module given its neighbours in the
## pipeline. Empty strings mean "nothing there", which matches nothing.
func active_combos(previous_id: String, next_id: String) -> Array:
	var live: Array = []
	for combo in combos:
		if not combo is Dictionary:
			continue
		var after: Array = Array(combo.get("after", []))
		var before: Array = Array(combo.get("before", []))
		var matched: bool = (previous_id != "" and previous_id in after) \
			or (next_id != "" and next_id in before)
		if matched:
			live.append(combo.duplicate(true))
	return live


## Subscription-shaped view of the module, so slot effects resolve through
## the same dispatch path as perks and can be ordered against them.
##
## The resolver gates whole subscriptions rather than individual effects, so an
## effect carrying its own `conditions` becomes a subscription of its own.
func to_subscriptions(event_name: String) -> Array:
	var unconditional: Array = []
	var subscriptions: Array = []
	for effect in slot_effects:
		if not effect is Dictionary:
			continue
		var conditions: Array = Array(effect.get("conditions", []))
		if conditions.is_empty():
			unconditional.append(effect.duplicate(true))
			continue
		subscriptions.append(_subscription(event_name, [effect.duplicate(true)], conditions))
	if not unconditional.is_empty():
		subscriptions.push_front(_subscription(event_name, unconditional, []))
	subscriptions.append_array(_combo_subscriptions(event_name))
	return subscriptions


## Compiles the named combos into adjacency-gated subscriptions. A combo naming
## both directions fires for either neighbour, which is the same reading
## `active_combos()` gives the pipeline editor.
func _combo_subscriptions(event_name: String) -> Array:
	var subscriptions: Array = []
	for combo in combos:
		if not combo is Dictionary:
			continue
		var effects: Array = Array(combo.get("effects", []))
		if effects.is_empty():
			continue
		for direction in [["after", "$prev_module"], ["before", "$next_module"]]:
			var partners: Array = Array(combo.get(str(direction[0]), []))
			if partners.is_empty():
				continue
			var copies: Array = []
			for effect in effects:
				if effect is Dictionary:
					copies.append(effect.duplicate(true))
			subscriptions.append(_subscription(event_name, copies, [{
				"left": str(direction[1]),
				"operator": "in",
				"right": partners.duplicate(),
			}], {
				"source_kind": "combo",
				"combo_name": str(combo.get("name", "")),
			}))
	return subscriptions


func to_folded_subscriptions(event_name: String) -> Array:
	return _effects_to_subscriptions(folded_effects, event_name)


func to_completion_subscriptions(event_name: String) -> Array:
	return _effects_to_subscriptions(completion_effects, event_name)


func to_finalizing_subscriptions(event_name: String) -> Array:
	return _effects_to_subscriptions(finalizing_effects, event_name)


func _effects_to_subscriptions(effects: Array, event_name: String) -> Array:
	if effects.is_empty():
		return []
	var unconditional: Array = []
	var subscriptions: Array = []
	for effect in effects:
		if not effect is Dictionary:
			continue
		var conditions: Array = Array(effect.get("conditions", []))
		if conditions.is_empty():
			unconditional.append(effect.duplicate(true))
			continue
		subscriptions.append(_subscription(event_name, [effect.duplicate(true)], conditions))
	if not unconditional.is_empty():
		subscriptions.push_front(_subscription(event_name, unconditional, []))
	return subscriptions


func _subscription(
	event_name: String,
	effects: Array,
	conditions: Array,
	extras: Dictionary = {}
) -> Dictionary:
	var sub := {
		"event": event_name,
		"priority": priority,
		"conditions": conditions,
		"effects": effects,
		"parameters": parameters.duplicate(true),
		"source_id": id,
	}
	# ChainGuard still keys off the module id. The combo name is presentation:
	# the resolver copies it into trace metadata so a burn can slam READ THE DOCS
	# without treating each combo as a different effect identity.
	if str(extras.get("source_kind", "")) != "":
		sub["source_kind"] = str(extras["source_kind"])
	if str(extras.get("combo_name", "")) != "":
		sub["combo_name"] = str(extras["combo_name"])
	return sub
