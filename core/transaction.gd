class_name Transaction
extends RefCounted

## Records a single economic or state mutation for debugging and replay.

var id: String = ""
var event_name: String = ""
var target_path: String = ""
var operation: String = ""
var value: Variant = null
var timestamp: Dictionary = {}


func _init(
	p_id: String = "",
	p_event_name: String = "",
	p_target_path: String = "",
	p_operation: String = "",
	p_value: Variant = null
) -> void:
	id = p_id
	event_name = p_event_name
	target_path = p_target_path
	operation = p_operation
	value = p_value


func to_dict() -> Dictionary:
	return {
		"id": id,
		"event_name": event_name,
		"target_path": target_path,
		"operation": operation,
		"value": value,
		"timestamp": timestamp,
	}
