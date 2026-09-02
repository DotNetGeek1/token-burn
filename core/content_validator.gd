class_name ContentValidator
extends RefCounted

## Validation entry used by ContentDatabase. The autoload stays the facade;
## callers still go through ContentDatabase.reload() / collect_validation_errors().


static func validate(database: Node) -> Array[String]:
	if database.has_method("collect_validation_errors"):
		return database.collect_validation_errors()
	return []
