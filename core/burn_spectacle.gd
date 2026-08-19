extends RefCounted

## Turns a resolved burn into a beat list the Burn Board can play as events
## rather than as a fixed-time arithmetic crawl.


static func build(preview: Dictionary, trace: Array = [], board_slots: Array = []) -> Array:
	var beats: Array = []
	var stages: Array = Array(preview.get("stages", []))
	var running_mult: float = 1.0
	for stage in stages:
		if not stage is Dictionary:
			continue
		var before: Dictionary = Dictionary(stage.get("before", {}))
		var after: Dictionary = Dictionary(stage.get("after", {}))
		var before_mult: float = maxf(0.01, float(before.get("progress_mult", 1.0)))
		var after_mult: float = maxf(0.01, float(after.get("progress_mult", 1.0)))
		var jump: float = after_mult / before_mult
		var module_id: String = str(stage.get("module_id", ""))
		beats.append({
			"kind": "stage",
			"label": str(stage.get("name", "stage")),
			"module_id": module_id,
			"source_id": module_id,
			"before_mult": running_mult,
			"after_mult": running_mult * jump,
			"duration_ms": 180,
			"slot_index": int(stage.get("slot_index", 0)),
			"dropped": bool(stage.get("dropped", false)),
		})
		if bool(stage.get("dropped", false)):
			beats[-1]["kind"] = "fault"
			beats[-1]["label"] = "DROPPED"
			beats[-1]["duration_ms"] = 550
		var combo_name: String = _live_combo_name(module_id, board_slots, int(stage.get("slot_index", 0)))
		if combo_name != "":
			beats.append({
				"kind": "combo",
				"label": combo_name.to_upper(),
				"module_id": module_id,
				"source_id": module_id,
				"before_mult": running_mult,
				"after_mult": running_mult * jump,
				"duration_ms": 550,
				"slot_index": int(stage.get("slot_index", 0)),
			})
		for source_id in _named_sources_for_stage(trace, module_id, int(stage.get("slot_index", -1))):
			var source_kind: String = "status" if str(source_id).begins_with("status.") else "perk"
			beats.append({
				"kind": source_kind,
				"label": _display_name(source_id),
				"module_id": module_id,
				"source_id": source_id,
				"before_mult": running_mult,
				"after_mult": running_mult * jump,
				"duration_ms": 550,
				"slot_index": int(stage.get("slot_index", 0)),
			})
		if float(stage.get("repeated_previous", 0.0)) > 0.0 and int(stage.get("repeat_count", 0)) > 0:
			beats.append({
				"kind": "repeat",
				"label": "RECURSIVE FORK",
				"module_id": module_id,
				"source_id": module_id,
				"before_mult": running_mult,
				"after_mult": running_mult * jump,
				"duration_ms": 800,
				"slot_index": int(stage.get("slot_index", 0)),
			})
		if bool(stage.get("cascaded", false)):
			beats.append({
				"kind": "cascade",
				"label": "CASCADE",
				"module_id": module_id,
				"source_id": module_id,
				"before_mult": running_mult,
				"after_mult": running_mult * jump,
				"duration_ms": 800,
				"slot_index": int(stage.get("slot_index", 0)),
			})
		if jump >= 1.15:
			beats.append({
				"kind": "mult",
				"label": "×%.2f" % (running_mult * jump),
				"module_id": module_id,
				"source_id": module_id,
				"before_mult": running_mult,
				"after_mult": running_mult * jump,
				"duration_ms": 550 if jump < 1.5 else 800,
				"slot_index": int(stage.get("slot_index", 0)),
			})
		running_mult *= jump
	var overkill: float = float(preview.get("overkill_ratio", 0.0))
	if overkill >= 1.25:
		beats.append({
			"kind": "overkill",
			"label": "%d%% OVERKILL" % int(overkill * 100.0),
			"module_id": "",
			"source_id": "",
			"before_mult": running_mult,
			"after_mult": running_mult,
			"duration_ms": 400,
			"slot_index": -1,
		})
	return beats


static func total_duration_ms(beats: Array) -> int:
	var total: int = 0
	for beat in beats:
		if beat is Dictionary:
			total += int(beat.get("duration_ms", 180))
	return total


static func _live_combo_name(module_id: String, board_slots: Array, slot_index: int) -> String:
	var module: ModuleDefinition = ContentDatabase.get_module(module_id)
	if module == null:
		return ""
	var prev_id: String = ""
	var next_id: String = ""
	var filled: Array = []
	for entry in board_slots:
		if str(entry) != "":
			filled.append(str(entry))
	var pos: int = filled.find(module_id)
	if slot_index >= 0 and slot_index < board_slots.size():
		for i in range(slot_index - 1, -1, -1):
			if str(board_slots[i]) != "":
				prev_id = str(board_slots[i])
				break
		for i in range(slot_index + 1, board_slots.size()):
			if str(board_slots[i]) != "":
				next_id = str(board_slots[i])
				break
	elif pos >= 0:
		if pos > 0:
			prev_id = str(filled[pos - 1])
		if pos < filled.size() - 1:
			next_id = str(filled[pos + 1])
	var combos: Array = module.active_combos(prev_id, next_id)
	if combos.is_empty():
		return ""
	return str(Dictionary(combos[0]).get("name", ""))


static func _named_sources_for_stage(trace: Array, module_id: String, slot_index: int) -> Array[String]:
	var found: Array[String] = []
	var chain: String = "board.stage.%d.%s" % [slot_index, module_id]
	for entry in trace:
		if not entry is Dictionary:
			continue
		var source: String = str(entry.get("source_id", ""))
		if not (source.begins_with("perk.") or source.begins_with("status.")):
			continue
		var chain_id: String = str(entry.get("chain_id", ""))
		if chain_id != "" and chain_id != chain:
			continue
		if not (source in found):
			found.append(source)
	return found


static func _display_name(source_id: String) -> String:
	if source_id.begins_with("perk."):
		var perk: PerkDefinition = ContentDatabase.get_perk(source_id)
		if perk != null:
			return perk.name.to_upper()
	return source_id.replace("perk.", "").replace("_", " ").to_upper()
