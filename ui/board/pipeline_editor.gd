extends Control

## The Workflows screen: every pipeline the run owns, and the modules in them.
##
## A workflow is a named pipeline a contract can be assigned to, so this is
## where the run's ways of working are defined rather than one global board.
## Selection is explicit and always shown in the banner at top, with a CANCEL
## that is always available, so a tap never silently swaps or empties the wrong
## slot.

const SlotScript := preload("res://ui/board/burn_slot.gd")
const ChipScript := preload("res://ui/board/burn_module_chip.gd")

enum Selection { NONE, MODULE, SLOT }

@onready var panel: PanelContainer = $Panel
@onready var done_button: GameButton = $Panel/Margin/VBox/HeaderRow/DoneButton
@onready var workflow_tabs: HBoxContainer = $Panel/Margin/VBox/WorkflowTabs
@onready var name_edit: LineEdit = $Panel/Margin/VBox/WorkflowRow/NameEdit
@onready var new_button: GameButton = $Panel/Margin/VBox/WorkflowRow/NewButton
@onready var delete_button: GameButton = $Panel/Margin/VBox/WorkflowRow/DeleteButton
@onready var assigned_label: Label = $Panel/Margin/VBox/AssignedLabel
@onready var banner_panel: PanelContainer = $Panel/Margin/VBox/BannerPanel
@onready var banner_label: Label = $Panel/Margin/VBox/BannerPanel/BannerMargin/BannerRow/BannerLabel
@onready var remove_button: GameButton = $Panel/Margin/VBox/BannerPanel/BannerMargin/BannerRow/RemoveButton
@onready var cancel_button: GameButton = $Panel/Margin/VBox/BannerPanel/BannerMargin/BannerRow/CancelButton
@onready var slot_list: VBoxContainer = $Panel/Margin/VBox/Scroll/Content/SlotList
@onready var tray_grid: GridContainer = $Panel/Margin/VBox/Scroll/Content/TrayGrid
@onready var tray_section_label: Label = $Panel/Margin/VBox/Scroll/Content/TraySectionLabel

var _slots: Array[BurnSlot] = []
var _selection: Selection = Selection.NONE
var _selected_module_id: String = ""
var _selected_slot_index: int = -1
var _tab_buttons: Array[GameButton] = []


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("flow_overlay")
	add_to_group("ui_refresh")
	done_button.pressed.connect(close)
	cancel_button.pressed.connect(_clear_selection)
	remove_button.pressed.connect(_on_remove_pressed)
	new_button.pressed.connect(_on_new_workflow)
	delete_button.pressed.connect(_on_delete_workflow)
	name_edit.text_submitted.connect(_on_name_submitted)
	name_edit.focus_exited.connect(func(): _on_name_submitted(name_edit.text))
	Simulation.work_tick_completed.connect(refresh)
	EventBus.operation_acquired.connect(func(_id): refresh())


func open() -> void:
	UiTransition.enter(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_clear_selection()
	get_tree().call_group("main_ui", "sync_overlay_input")


func close() -> void:
	hide_overlay()
	get_tree().call_group("main_ui", "refresh_all")


## Named for the `flow_overlay` group contract: returning to the title dismisses
## every overlay by calling this, and the editor used to be skipped because it
## only had `close`, which also refreshes the game behind it.
func hide_overlay() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().call_group("main_ui", "sync_overlay_input")


func refresh() -> void:
	if not visible:
		return
	_rebuild_workflow_tabs()
	_refresh_workflow_row()
	_rebuild_slots()
	_rebuild_tray()
	_refresh_banner()


## One tab per workflow the run owns, plus the empty capacity it has not spent
## yet, so the room for another way of working is visible before it is used.
func _rebuild_workflow_tabs() -> void:
	for button in _tab_buttons:
		button.queue_free()
	_tab_buttons.clear()
	var list: Array = Simulation.workflows()
	workflow_tabs.visible = list.size() > 1 or Simulation.workflow_capacity() > 1
	if not workflow_tabs.visible:
		return
	var active: int = Simulation.active_workflow_index()
	for i in range(list.size()):
		var workflow: Dictionary = list[i]
		var button := GameButton.new()
		button.custom_minimum_size = Vector2(0, 78)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = &"PrimaryButton" if i == active else &"SecondaryButton"
		button.accent_key = "action" if i == active else "neutral"
		button.disabled = i == active
		button.pressed.connect(_on_workflow_pressed.bind(i))
		workflow_tabs.add_child(button)
		# The content is built on tree entry, so the lines are set after the add.
		button.set_lines(
			str(workflow.get("name", "Workflow")).to_upper(),
			"%d module(s)" % _filled_count(Array(workflow.get("slots", [])))
		)
		_tab_buttons.append(button)


func _filled_count(layout: Array) -> int:
	var count: int = 0
	for entry in layout:
		if str(entry) != "":
			count += 1
	return count


func _refresh_workflow_row() -> void:
	var workflow: Dictionary = Simulation.active_workflow()
	var spare: int = Simulation.workflow_capacity() - Simulation.workflow_count()
	if not name_edit.has_focus():
		name_edit.text = str(workflow.get("name", ""))
	new_button.disabled = spare <= 0
	new_button.set_lines("NEW", "%d spare" % spare if spare > 0 else "NO ROOM")
	delete_button.disabled = Simulation.workflow_count() <= 1
	_refresh_assigned_label(str(workflow.get("id", "")))


## Which contracts this pipeline is currently responsible for, so a change made
## here is never a surprise to the work already underway.
func _refresh_assigned_label(workflow_id: String) -> void:
	var names: Array[String] = []
	for job in Simulation.run_state.business.get("active_jobs", []):
		if job is Dictionary and str(job.get("workflow_id", "")) == workflow_id:
			names.append(str(job.get("name", "a contract")))
	if names.is_empty():
		assigned_label.text = "No contract is assigned to this workflow."
	else:
		assigned_label.text = "Working: %s" % ", ".join(names)


func _on_workflow_pressed(index: int) -> void:
	if Simulation.set_active_workflow(index):
		_clear_selection()


func _on_new_workflow() -> void:
	if not Simulation.create_workflow().is_empty():
		_clear_selection()


func _on_delete_workflow() -> void:
	if Simulation.delete_workflow(Simulation.active_workflow_index()):
		_clear_selection()


func _on_name_submitted(new_name: String) -> void:
	if new_name.strip_edges() == "":
		return
	if str(Simulation.active_workflow().get("name", "")) == new_name.strip_edges():
		return
	if Simulation.rename_workflow(Simulation.active_workflow_index(), new_name):
		refresh()


func _rebuild_slots() -> void:
	var board_slots: Array = Simulation.board_slots()
	var job: Dictionary = Simulation.editing_job()
	var blocked: int = int(job.get("blocked_slots", 0))
	var blocked_label: String = _blocked_label(job)
	while _slots.size() > board_slots.size():
		var extra: BurnSlot = _slots.pop_back()
		extra.queue_free()
	while _slots.size() < board_slots.size():
		var slot: BurnSlot = SlotScript.new()
		slot.slot_pressed.connect(_on_slot_pressed)
		slot_list.add_child(slot)
		_slots.append(slot)
	for i in range(_slots.size()):
		_slots[i].setup(i, str(board_slots[i]), i < blocked, blocked_label)
		_apply_combos(_slots[i], board_slots, i, blocked)
		_slots[i].set_selected(_selection == Selection.SLOT and i == _selected_slot_index)


## Which named pairings the module in this slot has live. Neighbours are the
## stages either side in burn order, so empty slots between two modules do not
## break a combo the player can plainly see lining up.
func _apply_combos(slot: BurnSlot, board_slots: Array, index: int, blocked: int) -> void:
	var operation: OperationDefinition = ContentDatabase.get_operation(str(board_slots[index]))
	if operation == null:
		return
	var previous_id: String = ""
	for i in range(index - 1, blocked - 1, -1):
		if str(board_slots[i]) != "":
			previous_id = str(board_slots[i])
			break
	var next_id: String = ""
	for i in range(index + 1, board_slots.size()):
		if str(board_slots[i]) != "":
			next_id = str(board_slots[i])
			break
	slot.set_combos(operation.active_combos(previous_id, next_id), operation.parameters)


func _blocked_label(job: Dictionary) -> String:
	for rule in Array(job.get("board_rules", [])):
		if rule is Dictionary and str(rule.get("type", "")) == BoardSystem.RULE_BLOCKED_SLOTS:
			return str(rule.get("label", "This contract already owns the slot."))
	return "This contract already owns the slot."


func _rebuild_tray() -> void:
	for child in tray_grid.get_children():
		child.queue_free()
	var board_slots: Array = Simulation.board_slots()
	var owned: Array = Simulation.owned_operations()
	var ordered: Array = []
	for operation_id in owned:
		if not (str(operation_id) in board_slots):
			ordered.append(operation_id)
	var benched: int = ordered.size()
	for operation_id in owned:
		if str(operation_id) in board_slots:
			ordered.append(operation_id)
	tray_section_label.text = (
		"MODULES · %d owned, %d on the bench" % [owned.size(), benched]
		if benched > 0
		else "MODULES · %d owned, all in the pipeline" % owned.size()
	)
	for operation_id in ordered:
		var operation: OperationDefinition = ContentDatabase.get_operation(str(operation_id))
		if operation == null:
			continue
		var chip: BurnModuleChip = ChipScript.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tray_grid.add_child(chip)
		chip.setup(operation, str(operation_id) in board_slots)
		chip.chip_pressed.connect(_on_chip_pressed)
		if _selection == Selection.MODULE and str(operation_id) == _selected_module_id:
			chip.modulate = UiThemeBuilder.semantic("action")


func _refresh_banner() -> void:
	match _selection:
		Selection.MODULE:
			var operation: OperationDefinition = ContentDatabase.get_operation(_selected_module_id)
			var op_name: String = operation.name if operation != null else _selected_module_id
			banner_label.text = "PLACING %s — tap a slot" % op_name.to_upper()
			remove_button.visible = false
			banner_panel.visible = true
		Selection.SLOT:
			var slot_operation_id: String = str(Simulation.board_slots()[_selected_slot_index])
			var slot_operation: OperationDefinition = ContentDatabase.get_operation(slot_operation_id)
			var slot_name: String = slot_operation.name if slot_operation != null else "module"
			banner_label.text = "MOVING %s — tap another slot to swap" % slot_name.to_upper()
			remove_button.visible = true
			banner_panel.visible = true
		_:
			banner_panel.visible = false


func _on_slot_pressed(index: int) -> void:
	match _selection:
		Selection.MODULE:
			Simulation.place_operation(_selected_module_id, index)
			_clear_selection()
		Selection.SLOT:
			if index == _selected_slot_index:
				_clear_selection()
			else:
				Simulation.swap_slots(_selected_slot_index, index)
				_clear_selection()
		_:
			if str(Simulation.board_slots()[index]) == "":
				return
			_selection = Selection.SLOT
			_selected_slot_index = index
			refresh()


func _on_chip_pressed(operation_id: String) -> void:
	if _selection == Selection.MODULE and _selected_module_id == operation_id:
		_clear_selection()
		return
	_selection = Selection.MODULE
	_selected_module_id = operation_id
	_selected_slot_index = -1
	refresh()


func _on_remove_pressed() -> void:
	if _selection != Selection.SLOT:
		return
	Simulation.clear_slot(_selected_slot_index)
	_clear_selection()


func _clear_selection() -> void:
	_selection = Selection.NONE
	_selected_module_id = ""
	_selected_slot_index = -1
	refresh()
