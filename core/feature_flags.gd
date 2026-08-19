class_name FeatureFlags
extends RefCounted

## Reads feature toggles from config/feature_flags.json.
##
## Autoload registration is optional — see docs/decisions/ADR-003-feature-flags.md.

const CONFIG_PATH := "res://config/feature_flags.json"

static var _flags: Dictionary = {}
static var _loaded: bool = false


static func is_enabled(flag: String) -> bool:
	_ensure_loaded()
	return bool(_flags.get(flag, false))


static func set_enabled(flag: String, enabled: bool) -> void:
	_ensure_loaded()
	_flags[flag] = enabled


static func get_all() -> Dictionary:
	_ensure_loaded()
	return _flags.duplicate(true)


static func reload() -> void:
	_loaded = false
	_flags.clear()
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("FeatureFlags: missing config at %s" % CONFIG_PATH)
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("FeatureFlags: could not open %s" % CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_flags = parsed
	else:
		push_warning("FeatureFlags: invalid JSON in %s" % CONFIG_PATH)
