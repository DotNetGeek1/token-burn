class_name EventDefinition
extends Resource

## Static definition for random or scripted run events.

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var trigger_event: String = ""
@export var weight: float = 1.0
@export var conditions: Array[Dictionary] = []
@export var effects: Array[EffectDefinition] = []


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"description": description,
		"trigger_event": trigger_event,
		"weight": weight,
		"conditions": conditions,
		"effects": effects.map(func(e: EffectDefinition) -> Dictionary: return e.to_dict()),
	}
