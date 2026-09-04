class_name TabModules
extends CabinetTab

## The module bin: every module the run owns that is not seated in the active
## workflow, as cartridges. Tap one to arm it, then tap a bay in the dock (or
## drag it there) to seat it. A seated module picked out of the dock can be
## ejected back into the bin from here.
##
## The strip along the top carries the workflow housekeeping the old editor
## had: RENAME the active workflow (an inline field on the glass), DELETE it
## (its contracts fall back to the first one), CLEAR every stage, and + STAGE
## for an overflow bay. Picking and building workflows is the backplane's
## `WorkflowKeys`; a new workflow copies the active layout, so "duplicate" is
## the `+` key there.

## The cartridge armed for seating, or "".
var armed_module_id: String = ""
## The dock bay the player has picked out, or -1. Fed in by the shell.
var dock_slot: int = -1

var _bin: HBoxContainer = null
var _scroll: ScrollContainer = null
var _empty: Label = null
var _count: Label = null
var _name_edit: LineEdit = null
var _title: Label = null
var _kicker: Label = null
var _rows: VBoxContainer = null
var _keys: HBoxContainer = null


func tab_key() -> String:
	return "modules"


func _ready() -> void:
	super._ready()
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_theme_constant_override("separation", 3)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	var strip: HBoxContainer = make_strip()
	column.add_child(strip)
	var caption: Label = CabinetStyle.caption("MODULE BIN")
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.add_child(caption)
	_count = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.add_child(_count)
	_name_edit = ConsoleStyle.line_edit("WORKFLOW NAME", CabinetStyle.FONT_SMALL)
	_name_edit.name = "WorkflowNameEdit"
	_name_edit.max_length = 28
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_edit.add_theme_color_override("font_color", CabinetStyle.AMBER)
	_name_edit.add_theme_color_override("caret_color", CabinetStyle.AMBER)
	_name_edit.visible = false
	_name_edit.text_submitted.connect(func(text: String) -> void: _commit_rename(text))
	_name_edit.focus_exited.connect(func() -> void:
		if _name_edit.visible:
			_commit_rename(_name_edit.text)
	)
	_name_edit.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"):
			_cancel_rename()
			get_viewport().set_input_as_handled()
	)
	strip.add_child(_name_edit)
	_keys = HBoxContainer.new()
	_keys.mouse_filter = Control.MOUSE_FILTER_PASS
	_keys.add_theme_constant_override("separation", 4)
	strip.add_child(_keys)

	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var shelf := PanelContainer.new()
	shelf.mouse_filter = Control.MOUSE_FILTER_PASS
	shelf.add_theme_stylebox_override("panel", CabinetStyle.frame(CabinetStyle.AMBER, 0.3, 0.02))
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf.size_flags_stretch_ratio = 1.6
	body.add_child(shelf)
	_scroll = ScrollContainer.new()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	shelf.add_child(_scroll)
	_bin = HBoxContainer.new()
	_bin.mouse_filter = Control.MOUSE_FILTER_PASS
	_bin.add_theme_constant_override("separation", 4)
	_bin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_bin)
	_empty = CabinetStyle.mono("", CabinetStyle.FONT_SMALL, CabinetStyle.PHOSPHOR_DIM)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shelf.add_child(_empty)

	var detail := VBoxContainer.new()
	detail.mouse_filter = Control.MOUSE_FILTER_PASS
	detail.add_theme_constant_override("separation", 2)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(detail)
	_title = CabinetStyle.mono("", CabinetStyle.FONT_SMALL, CabinetStyle.AMBER)
	detail.add_child(_title)
	_kicker = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
	detail.add_child(_kicker)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(detail_scroll)
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_PASS
	_rows.add_theme_constant_override("separation", 1)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_rows)


func refresh() -> void:
	var scrolls: Dictionary = capture_scroll(self)
	_refresh_contents()
	restore_scroll(self, scrolls)


func _refresh_contents() -> void:
	var seated: Array = Simulation.board_slots()
	var loose: Array[String] = []
	for module_id in Simulation.owned_modules():
		if not (str(module_id) in seated):
			loose.append(str(module_id))
	if armed_module_id != "" and not (armed_module_id in loose):
		armed_module_id = ""
	_count.text = "%d LOOSE · %d/%d SEATED" % [loose.size(), Simulation.filled_slot_count(), seated.size()]
	for child in _bin.get_children():
		_bin.remove_child(child)
		child.queue_free()
	var height: float = shelf_card_height(_scroll)
	for module_id in loose:
		var cartridge := ModuleCartridge.new()
		cartridge.custom_minimum_size = Vector2(height * 0.58, height)
		cartridge.pressed.connect(_on_cartridge.bind(module_id))
		_bin.add_child(cartridge)
		cartridge.set_module(module_id)
		cartridge.set_selected(module_id == armed_module_id)
	_empty.visible = loose.is_empty()
	_empty.text = "EVERY MODULE YOU OWN IS SEATED — THE MARKET SELLS MORE" if not seated.is_empty() else "NO MODULES"
	_refresh_keys()
	_refresh_detail()


func _refresh_keys() -> void:
	for child in _keys.get_children():
		_keys.remove_child(child)
		child.queue_free()
	var running: bool = Simulation.is_work_running()
	var in_run: bool = Simulation.phase != Simulation.Phase.IDLE
	var name_text: String = str(Simulation.active_workflow().get("name", ""))
	var rename: Button = CabinetStyle.key("RENAME", CabinetStyle.PHOSPHOR, CabinetStyle.FONT_TINY)
	rename.tooltip_text = "Rename %s." % (name_text if name_text != "" else "the active workflow")
	rename.disabled = not in_run or Simulation.workflow_count() <= 0
	rename.pressed.connect(begin_rename)
	_keys.add_child(rename)
	var clear: Button = CabinetStyle.key("CLEAR", CabinetStyle.PHOSPHOR, CabinetStyle.FONT_TINY)
	clear.tooltip_text = "Eject every stage of %s back into the bin." % (name_text if name_text != "" else "the active workflow")
	clear.disabled = running or Simulation.filled_slot_count() <= 0
	clear.pressed.connect(clear_active_workflow)
	_keys.add_child(clear)
	var delete: Button = CabinetStyle.key("DELETE", CabinetStyle.RED, CabinetStyle.FONT_TINY)
	delete.tooltip_text = "Scrap %s; its contracts fall back to workflow 1." % (name_text if name_text != "" else "the active workflow")
	delete.disabled = running or Simulation.workflow_count() <= 1
	delete.pressed.connect(delete_active_workflow)
	_keys.add_child(delete)
	if Simulation.can_append_overflow():
		var stage: Button = CabinetStyle.key("+ STAGE", CabinetStyle.PHOSPHOR, CabinetStyle.FONT_TINY)
		stage.tooltip_text = "Bolt another stage onto the pipeline (%d overflow)." % Simulation.overflow_count()
		stage.pressed.connect(func() -> void:
			if Simulation.append_overflow_stage() >= 0:
				UiSound.play("accept")
				shell.call("refresh_all")
		)
		_keys.add_child(stage)


# --- Workflow housekeeping ----------------------------------------------------

## Opens the inline name field over the counter, filled with the current name.
func begin_rename() -> void:
	if Simulation.workflow_count() <= 0:
		return
	UiSound.play("tap")
	_name_edit.text = str(Simulation.active_workflow().get("name", ""))
	_count.visible = false
	_name_edit.visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()


func is_renaming() -> bool:
	return _name_edit != null and _name_edit.visible


func _cancel_rename() -> void:
	_name_edit.visible = false
	_count.visible = true
	_name_edit.release_focus()


func _commit_rename(text: String) -> void:
	_name_edit.visible = false
	_count.visible = true
	_name_edit.release_focus()
	rename_active_workflow(text)


## Renames the active workflow; a blank or unchanged name is a no-op.
func rename_active_workflow(new_name: String) -> bool:
	var wanted: String = new_name.strip_edges()
	if wanted == "" or str(Simulation.active_workflow().get("name", "")) == wanted:
		return false
	if not Simulation.rename_workflow(Simulation.active_workflow_index(), wanted):
		UiSound.play("error")
		return false
	UiSound.play("accept")
	shell.call("refresh_all")
	changed.emit()
	return true


## Ejects every seated stage of the active workflow back into the bin. Stages a
## contract has locked stay where they are.
func clear_active_workflow() -> bool:
	if Simulation.is_work_running():
		UiSound.play("error")
		return false
	var cleared: bool = false
	var slots: Array = Simulation.board_slots()
	for index in range(slots.size() - 1, -1, -1):
		if str(slots[index]) != "" and Simulation.clear_slot(index):
			cleared = true
	if not cleared:
		UiSound.play("error")
		return false
	UiSound.play("tap")
	armed_module_id = ""
	shell.call("set_dock_armed", false)
	shell.call("refresh_all")
	changed.emit()
	return true


## Scraps the active workflow. The last one cannot go; its contracts move to
## the first workflow, which is what the sim does for a deleted pipeline.
func delete_active_workflow() -> bool:
	if Simulation.is_work_running() or Simulation.workflow_count() <= 1:
		UiSound.play("error")
		return false
	if not Simulation.delete_workflow(Simulation.active_workflow_index()):
		UiSound.play("error")
		return false
	UiSound.play("accept")
	armed_module_id = ""
	dock_slot = -1
	shell.call("set_dock_armed", false)
	shell.call("refresh_all")
	changed.emit()
	return true


## What the detail column describes: the armed cartridge, else the module in the
## picked dock bay, else nothing.
func _shown_module() -> String:
	if armed_module_id != "":
		return armed_module_id
	var slots: Array = Simulation.board_slots()
	if dock_slot >= 0 and dock_slot < slots.size():
		return str(slots[dock_slot])
	return ""


func _refresh_detail() -> void:
	var module_id: String = _shown_module()
	var module: ModuleDefinition = ContentDatabase.get_module(module_id) if module_id != "" else null
	if module == null:
		_title.text = "PICK A CARTRIDGE OR A BAY"
		_kicker.text = ""
		detail_rows(_rows, [
			{"text": "Tap a cartridge to arm it, then tap a bay in the dock to seat it. Tap two bays to swap them, or drag a bay onto another."},
			{"text": "The keys on the backplane pick a workflow; the + key builds a new one from this layout. RENAME, CLEAR and DELETE above act on the active workflow."},
		])
		return
	_title.text = module.name.to_upper()
	_kicker.text = "%s · %s · %s" % [module.category.to_upper(), module.rarity.to_upper(), Simulation.get_module_badge(module_id).to_upper()]
	_kicker.add_theme_color_override("font_color", AssetCatalog.rarity_color(module.rarity))
	var rows: Array = [{"text": Simulation.get_module_description(module_id)}]
	var combos: Array = module.combos
	if not combos.is_empty():
		rows.append({"text": "COMBOS"})
		for combo in combos:
			if not combo is Dictionary:
				continue
			var partners: Array = Array(combo.get("after", combo.get("before", [])))
			var names: PackedStringArray = []
			for partner in partners:
				var other: ModuleDefinition = ContentDatabase.get_module(str(partner))
				names.append(other.name if other != null else str(partner))
			rows.append({
				"rule": str(combo.get("name", "Combo")),
				"text": "%s%s" % [
					("after " if combo.has("after") else "before ") + ", ".join(names) + ". " if not names.is_empty() else "",
					str(combo.get("description", "")),
				],
			})
	if armed_module_id == "" and dock_slot >= 0:
		rows.append({"stat": "Seated in", "value": "BAY %d" % (dock_slot + 1)})
	detail_rows(_rows, rows)


func primary_action() -> Dictionary:
	var slots: Array = Simulation.board_slots()
	var running: bool = Simulation.is_work_running()
	if armed_module_id != "":
		var bay_picked: bool = dock_slot >= 0 and dock_slot < slots.size()
		if running:
			return blocked_action("SEAT", "ROUND UNDER WAY")
		if not bay_picked:
			return blocked_action("SEAT", BLOCK_SELECT_BAY)
		var swaps: bool = str(slots[dock_slot]) != ""
		return normalize_action({
			"label": "SEAT",
			"enabled": true,
			"sub": ("BAY %d · REPLACES SEATED" % (dock_slot + 1)) if swaps else ("BAY %d" % (dock_slot + 1)),
			"pressed": func() -> void: seat(armed_module_id, dock_slot),
		})
	if dock_slot >= 0 and dock_slot < slots.size() and str(slots[dock_slot]) != "":
		if running:
			return blocked_action("EJECT", "ROUND UNDER WAY")
		return normalize_action({
			"label": "EJECT",
			"enabled": true,
			"sub": "BAY %d · BACK TO THE BIN" % (dock_slot + 1),
			"pressed": func() -> void: eject(dock_slot),
		})
	return blocked_action("SEAT", BLOCK_SELECT_ITEM)


func arm(module_id: String) -> void:
	armed_module_id = module_id
	refresh()
	changed.emit()
	shell.call("set_dock_armed", module_id != "")


func disarm() -> void:
	arm("")


func seat(module_id: String, slot: int) -> void:
	if module_id == "" or slot < 0:
		return
	if Simulation.place_module(module_id, slot):
		UiSound.play("accept")
		armed_module_id = ""
		shell.call("set_dock_armed", false)
		shell.call("refresh_all")
		changed.emit()
	else:
		UiSound.play("error")


func eject(slot: int) -> void:
	if Simulation.clear_slot(slot):
		UiSound.play("tap")
		shell.call("refresh_all")
		changed.emit()


## The shell tells the bin which bay is picked so the detail follows the dock.
func set_dock_slot(slot: int) -> void:
	dock_slot = slot
	if visible:
		_refresh_detail()
	changed.emit()


func _on_cartridge(module_id: String) -> void:
	UiSound.play("tap")
	arm("" if armed_module_id == module_id else module_id)
