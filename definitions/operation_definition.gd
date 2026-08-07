class_name OperationDefinition
extends Resource

## Static definition for a Burn Board operation: a module the player drops into
## a pipeline slot. Effects target the reserved `stage.*` and `batch.*` paths
## that BoardSystem folds into a burn result.

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
## Named adjacency pairings, declared so the pipeline editor can show them
## before the player finds them by accident. Each entry names the modules it
## reacts to in `after` (the stage above) or `before` (the stage below); the
## mechanical half lives in `slot_effects` behind matching `$prev_op` /
## `$next_op` conditions.
@export var combos: Array[Dictionary] = []


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
		"combos": combos,
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


## Subscription-shaped view of the operation, so slot effects resolve through
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
	return subscriptions


func _subscription(event_name: String, effects: Array, conditions: Array) -> Dictionary:
	return {
		"event": event_name,
		"priority": priority,
		"conditions": conditions,
		"effects": effects,
		"parameters": parameters.duplicate(true),
		"source_id": id,
	}
