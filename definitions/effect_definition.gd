class_name EffectDefinition
extends Resource

## Describes a single data-driven effect operation.

@export var operation: String = "add"
@export var target: String = ""
@export var value: Variant = 0.0


func to_dict() -> Dictionary:
	return {
		"operation": operation,
		"target": target,
		"value": value,
	}
