class_name SaveManager
extends RefCounted

const SAVE_PATH := "user://savegame.json"
const SAVE_TMP_PATH := "user://savegame.json.tmp"
const SAVE_BAK_PATH := "user://savegame.json.bak"
const CURRENT_SAVE_VERSION := 2

## Redirected by playtests onto a scratch file, so the suite never writes the
## save the developer is actually playing.
static var _path: String = SAVE_PATH
static var _tmp_path: String = SAVE_TMP_PATH
static var _bak_path: String = SAVE_BAK_PATH


static func use_scratch(path: String) -> void:
	_path = path
	_tmp_path = path + ".tmp"
	_bak_path = path + ".bak"
	delete_save()


static func restore_default() -> void:
	_path = SAVE_PATH
	_tmp_path = SAVE_TMP_PATH
	_bak_path = SAVE_BAK_PATH


## Writes to a temp file and verifies it parses back before it ever touches
## the real save — a crash or a full disk mid-write must never leave the
## player's only save half-written. The previous save is kept as a `.bak` so
## a corrupt write (or a corrupt save from an older, buggier build) still has
## a way back in.
static func save_run(run_state: RunState, phase: String, run_seed: int, pending_choices: Array = [], round_end_pending: bool = false) -> bool:
	var payload := {
		"version": CURRENT_SAVE_VERSION,
		"phase": phase,
		"seed": run_seed,
		"run_state": run_state.to_dict(),
		"pending_choices": pending_choices.duplicate(true),
		"round_end_pending": round_end_pending,
		"saved_at": Time.get_unix_time_from_system(),
	}
	var text: String = JSON.stringify(payload, "\t")

	var tmp_file := FileAccess.open(_tmp_path, FileAccess.WRITE)
	if tmp_file == null:
		push_warning("SaveManager: could not open temp save file for writing")
		return false
	tmp_file.store_string(text)
	tmp_file.close()

	if not _verify_parses(_tmp_path):
		push_warning("SaveManager: temp save failed to verify, aborting save")
		return false

	if FileAccess.file_exists(_path):
		if FileAccess.file_exists(_bak_path):
			DirAccess.remove_absolute(_bak_path)
		DirAccess.rename_absolute(_path, _bak_path)

	var err: Error = DirAccess.rename_absolute(_tmp_path, _path)
	if err != OK:
		push_warning("SaveManager: failed to move temp save into place (%s)" % err)
		return false
	return true


static func _verify_parses(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text: String = file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return false
	return parser.get_data() is Dictionary


static func load_run() -> Dictionary:
	var primary: Dictionary = _load_from(_path)
	if not primary.is_empty():
		return primary
	if FileAccess.file_exists(_path):
		push_warning("SaveManager: primary save unreadable, falling back to backup")
	return _load_from(_bak_path)


static func _load_from(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		push_warning("SaveManager: failed to parse %s at line %d: %s" % [
			path, parser.get_error_line(), parser.get_error_message()
		])
		return {}
	var parsed: Variant = parser.get_data()
	return parsed if parsed is Dictionary else {}


static func has_save() -> bool:
	return FileAccess.file_exists(_path) or FileAccess.file_exists(_bak_path)


static func delete_save() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)
	if FileAccess.file_exists(_bak_path):
		DirAccess.remove_absolute(_bak_path)
	if FileAccess.file_exists(_tmp_path):
		DirAccess.remove_absolute(_tmp_path)
