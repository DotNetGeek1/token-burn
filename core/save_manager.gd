class_name SaveManager
extends RefCounted

const SAVE_PATH := "user://savegame.json"
const CURRENT_SAVE_VERSION := 2


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
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


static func load_run() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
