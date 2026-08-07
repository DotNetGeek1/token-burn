class_name TestCase
extends RefCounted

var _passed: int = 0
var _failed: int = 0
var _errors: Array[String] = []


func assert_true(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		_errors.append(message)


func assert_false(condition: bool, message: String) -> void:
	assert_true(not condition, message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	assert_true(actual == expected, "%s (expected %s got %s)" % [message, str(expected), str(actual)])


func assert_almost_eq(actual: float, expected: float, tolerance: float, message: String) -> void:
	assert_true(absf(actual - expected) <= tolerance, "%s (expected ~%s got %s)" % [message, str(expected), str(actual)])


func get_results() -> Dictionary:
	return {"passed": _passed, "failed": _failed, "errors": _errors}


func run() -> void:
	pass
