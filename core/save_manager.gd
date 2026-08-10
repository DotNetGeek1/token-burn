class_name SaveManager
extends RefCounted

const SAVE_PATH := "user://savegame.json"
const SAVE_TMP_PATH := "user://savegame.json.tmp"
const SAVE_BAK_PATH := "user://savegame.json.bak"
const CURRENT_SAVE_VERSION := 2


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

	var tmp_file := FileAccess.open(SAVE_TMP_PATH, FileAccess.WRITE)
	if tmp_file == null:
		push_warning("SaveManager: could not open temp save file for writing")
		return false
	tmp_file.store_string(text)
	tmp_file.close()

	if not _verify_parses(SAVE_TMP_PATH):
		push_warning("SaveManager: temp save failed to verify, aborting save")
		return false

	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(SAVE_BAK_PATH):
			DirAccess.remove_absolute(SAVE_BAK_PATH)
		DirAccess.rename_absolute(SAVE_PATH, SAVE_BAK_PATH)

	var err: Error = DirAccess.rename_absolute(SAVE_TMP_PATH, SAVE_PATH)
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
	var primary: Dictionary = _load_from(SAVE_PATH)
	if not primary.is_empty():
		return primary
	if FileAccess.file_exists(SAVE_PATH):
		push_warning("SaveManager: primary save unreadable, falling back to backup")
	return _load_from(SAVE_BAK_PATH)


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
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(SAVE_BAK_PATH)


static func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	if FileAccess.file_exists(SAVE_BAK_PATH):
		DirAccess.remove_absolute(SAVE_BAK_PATH)
	if FileAccess.file_exists(SAVE_TMP_PATH):
		DirAccess.remove_absolute(SAVE_TMP_PATH)
