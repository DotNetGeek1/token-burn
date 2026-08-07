class_name Ages
extends RefCounted

## Compute Ages: the run-to-run progression layer above individual Ascension
## Contracts. Completing a Tier 3 contract that unlocks the next age is what
## actually advances it; everything here is just the read side.

const PATH := "res://content/meta/ages.json"

static var _cache: Array = []


static func all() -> Array:
	if _cache.is_empty():
		_cache = _load()
	return _cache


static func max_age_index() -> int:
	return maxi(0, all().size() - 1)


static func get_age(index: int) -> Dictionary:
	var ages: Array = all()
	if ages.is_empty():
		return {}
	return Dictionary(ages[clampi(index, 0, ages.size() - 1)]).duplicate(true)


static func _load() -> Array:
	if not FileAccess.file_exists(PATH):
		return []
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Array else []
