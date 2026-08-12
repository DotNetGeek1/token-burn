extends ConsoleOverlay

## The Workflows screen: every pipeline the run owns, and the modules in them.
##
## A workflow is a named pipeline a contract can be assigned to, so this is
## where the run's ways of working are defined rather than one global board.
## Selection is explicit and always reported in the console's context line, with
## a CANCEL that is always available, so a tap never silently swaps or empties
## the wrong slot.
##
## The pipeline is printed as a numbered listing rather than drawn as a stack of
## cards: burn order is the whole point of the screen, and a numbered column is
## how the machine would report an order of operations.

enum Selection { NONE, MODULE, SLOT }

## Printed in the stage column when a slot has nothing in it yet.
const EMPTY_STAGE := "— EMPTY —"

var _tabs: HBoxContainer = null
var _tab_rows: Array[ConsoleMenuRow] = []
var _name_edit: LineEdit = null
var _name_caption: Label = null
var _assigned: Label = null
var _pipeline_caption: Label = null
var _pipeline: ConsoleTable = null
var _tray_caption: Label = null
var _tray: ConsoleTable = null

var _selection: Selection = Selection.NONE
var _selected_module_id: String = ""
var _selected_slot_index: int = -1


func _ready() -> void:
	super._ready()
	add_to_group("ui_refresh")
	setup("Workflows")
	# Placing a module is a decision in progress, so a stray tap on the room
	# behind the editor must not throw it away.
	dismiss_on_scrim = false
	set_close_label("DONE")
	_build_body()
	Simulation.work_tick_completed.connect(refresh)
	EventBus.operation_acquired.connect(func(_id: String) -> void: refresh())


func _build_body() -> void:
	var body: VBoxContainer = content()

	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	body.add_child(_tabs)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	body.add_child(name_row)

	_name_caption = ConsoleStyle.label("NAME", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	name_row.add_child(_name_caption)

	_name_edit = ConsoleStyle.line_edit("workflow name", ConsoleStyle.FONT_SMALL)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.focus_exited.connect(func() -> void: _on_name_submitted(_name_edit.text))
	name_row.add_child(_name_edit)

	_assigned = ConsoleStyle.paragraph("", ConsoleStyle.FONT_TINY)
	body.add_child(_assigned)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)

	_pipeline_caption = ConsoleStyle.label(
		"PIPELINE · TOP TO BOTTOM", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	column.add_child(_pipeline_caption)

	_pipeline = ConsoleTable.new()
	_pipeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pipeline.row_selected.connect(_on_slot_selected)
	column.add_child(_pipeline)
	_pipeline.set_columns([
		{"label": "#", "weight": 0.35},
		{"label": "stage", "weight": 1.6},
		{"label": "effect", "weight": 3.0},
		{"label": "yield", "weight": 0.7, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	])

	_tray_caption = ConsoleStyle.label("MODULES", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	column.add_child(_tray_caption)

	_tray = ConsoleTable.new()
	_tray.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tray.row_selected.connect(_on_module_selected)
	column.add_child(_tray)
	_tray.set_columns([
		{"label": "module", "weight": 1.6},
		{"label": "type", "weight": 0.9},
		{"label": "effect", "weight": 3.0},
		{"label": "where", "weight": 0.9, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	])


func refresh() -> void:
	if not visible:
		return
	_rebuild_tabs()
	_refresh_name_row()
	_rebuild_pipeline()
	_rebuild_tray()
	_refresh_context()
	_refresh_actions()
	_apply_body_metrics()


func fit_console() -> void:
	super.fit_console()
	_apply_body_metrics()


## The body's own widgets are not part of the shell, so they are re-scaled
## alongside it whenever the room is laid out.
func _apply_body_metrics() -> void:
	var scale: float = console_scale()
	var font_tiny: int = ConsoleMetrics.font_tiny(scale)
	var font_small: int = ConsoleMetrics.font_small(scale)
	var height: int = ConsoleMetrics.row_height(scale)
	var pad_h: int = ConsoleMetrics.pad_h(scale)
	for label in [_name_caption, _assigned, _pipeline_caption, _tray_caption]:
		if label != null:
			label.add_theme_font_size_override("font_size", font_tiny)
	if _name_edit != null:
		_name_edit.add_theme_font_size_override("font_size", font_small)
		_name_edit.custom_minimum_size = Vector2(0, height)
	for row in _tab_rows:
		row.set_metrics(font_small, height, pad_h)
	if _pipeline != null:
		_pipeline.set_metrics(scale)
	if _tray != null:
		_tray.set_metrics(scale)


## One tab per workflow the run owns. The empty capacity it has not spent yet is
## reported on the NEW command rather than shown as a phantom tab.
func _rebuild_tabs() -> void:
	for row in _tab_rows:
		_tabs.remove_child(row)
		row.queue_free()
	_tab_rows.clear()
	var list: Array = Simulation.workflows()
	_tabs.visible = list.size() > 1 or Simulation.workflow_capacity() > 1
	if not _tabs.visible:
		return
	var active: int = Simulation.active_workflow_index()
	for i in range(list.size()):
		var workflow: Dictionary = list[i]
		var row := ConsoleMenuRow.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.add_child(row)
		row.index_label = str(i + 1)
		row.headline = str(workflow.get("name", "Workflow")).to_upper()
		row.value_text = "%d MOD" % _filled_count(Array(workflow.get("slots", [])))
		row.set_selected(i == active)
		row.pressed.connect(_on_workflow_pressed.bind(i))
		_tab_rows.append(row)


func _filled_count(layout: Array) -> int:
	var count: int = 0
	for entry in layout:
		if str(entry) != "":
			count += 1
	return count


func _refresh_name_row() -> void:
	var workflow: Dictionary = Simulation.active_workflow()
	if not _name_edit.has_focus():
		_name_edit.text = str(workflow.get("name", ""))
	_refresh_assigned_label(str(workflow.get("id", "")))


## Which contracts this pipeline is currently responsible for, so a change made
## here is never a surprise to the work already underway.
func _refresh_assigned_label(workflow_id: String) -> void:
	var names: Array[String] = []
	for job in Simulation.run_state.business.get("active_jobs", []):
		if job is Dictionary and str(job.get("workflow_id", "")) == workflow_id:
			names.append(str(job.get("name", "a contract")))
	if names.is_empty():
		_assigned.text = "No contract is assigned to this workflow."
	else:
		_assigned.text = "Working: %s" % ", ".join(names)


func _rebuild_pipeline() -> void:
	_pipeline.clear()
	var board_slots: Array = Simulation.board_slots()
	var job: Dictionary = Simulation.editing_job()
	var blocked: int = int(job.get("blocked_slots", 0))
	var blocked_label: String = _blocked_label(job)
	var evaluator := ExpressionEvaluator.new()
	for i in range(board_slots.size()):
		var number: String = "%02d" % (i + 1)
		if i < blocked:
			_pipeline.add_row([
				number,
				{"text": "OCCUPIED", "color": ConsoleStyle.DANGER},
				{"text": blocked_label, "color": ConsoleStyle.DANGER},
				"×",
			], i, ConsoleStyle.DANGER)
			continue
		var operation: OperationDefinition = ContentDatabase.get_operation(str(board_slots[i]))
		if operation == null:
			_pipeline.add_row([
				number,
				{"text": EMPTY_STAGE, "color": ConsoleStyle.PHOSPHOR_DIM},
				{"text": "Select a module below, then this slot.", "color": ConsoleStyle.PHOSPHOR_DIM},
				"",
			], i)
			continue
		_pipeline.add_row([
			number,
			operation.name.to_upper(),
			{
				"text": _stage_effect(operation, board_slots, i, blocked, evaluator),
				"color": ConsoleStyle.PHOSPHOR_DIM,
			},
			evaluator.render_template(operation.badge, operation.parameters),
		], i, AssetCatalog.rarity_color(operation.rarity))
	if board_slots.is_empty():
		_pipeline.add_note("NO SLOTS — THIS WORKFLOW HAS NO PIPELINE YET")
	if _selection == Selection.SLOT and _selected_slot_index >= 0:
		_pipeline.select_meta(_selected_slot_index, false)


## The module's own description, plus any named pairing it has live with its
## neighbours. Combos are reported on the stage rather than on the module,
## because they only exist because of what sits either side of it.
func _stage_effect(
	operation: OperationDefinition,
	board_slots: Array,
	index: int,
	blocked: int,
	evaluator: ExpressionEvaluator
) -> String:
	var text: String = evaluator.render_template(
		operation.description_template, operation.parameters
	)
	var combos: Array = operation.active_combos(
		_neighbour(board_slots, index, -1, blocked), _neighbour(board_slots, index, 1, blocked)
	)
	for combo in combos:
		if not combo is Dictionary:
			continue
		text += "  ◆ %s — %s" % [
			str(combo.get("name", "Combo")),
			evaluator.render_template(str(combo.get("description", "")), operation.parameters),
		]
	return text


## The nearest filled stage in `step` direction. Empty slots between two modules
## do not break a combo the player can plainly see lining up.
func _neighbour(board_slots: Array, index: int, step: int, blocked: int) -> String:
	var i: int = index + step
	while i >= blocked and i < board_slots.size():
		if str(board_slots[i]) != "":
			return str(board_slots[i])
		i += step
	return ""


func _blocked_label(job: Dictionary) -> String:
	for rule in Array(job.get("board_rules", [])):
		if rule is Dictionary and str(rule.get("type", "")) == BoardSystem.RULE_BLOCKED_SLOTS:
			return str(rule.get("label", "This contract already owns the slot."))
	return "This contract already owns the slot."


## The bench first, then everything already placed: what the player can still
## spend is the part of the list they came here for.
func _rebuild_tray() -> void:
	_tray.clear()
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
	_tray_caption.text = (
		"MODULES · %d OWNED, %d ON THE BENCH" % [owned.size(), benched]
		if benched > 0
		else "MODULES · %d OWNED, ALL IN THE PIPELINE" % owned.size()
	)
	var evaluator := ExpressionEvaluator.new()
	for operation_id in ordered:
		var operation: OperationDefinition = ContentDatabase.get_operation(str(operation_id))
		if operation == null:
			continue
		var placed: bool = str(operation_id) in board_slots
		_tray.add_row([
			operation.name.to_upper(),
			{"text": operation.category.to_upper(), "color": ConsoleStyle.PHOSPHOR_DIM},
			{
				"text": evaluator.render_template(
					operation.description_template, operation.parameters
				),
				"color": ConsoleStyle.PHOSPHOR_DIM,
			},
			{
				"text": "IN PIPELINE" if placed else "BENCH",
				"color": ConsoleStyle.PHOSPHOR_DIM if placed else ConsoleStyle.PHOSPHOR,
			},
		], str(operation_id), AssetCatalog.rarity_color(operation.rarity))
	if ordered.is_empty():
		_tray.add_note("NO MODULES OWNED YET — FINISH CONTRACTS TO EARN THEM")
	if _selection == Selection.MODULE and _selected_module_id != "":
		_tray.select_meta(_selected_module_id, false)


## What the editor is waiting for, printed in the header where the machine
## reports its state rather than in a banner that comes and goes.
func _refresh_context() -> void:
	match _selection:
		Selection.MODULE:
			var operation: OperationDefinition = ContentDatabase.get_operation(_selected_module_id)
			var op_name: String = operation.name if operation != null else _selected_module_id
			set_context("PLACING %s — PICK A SLOT" % op_name.to_upper(), ConsoleStyle.WARNING)
		Selection.SLOT:
			var slot_id: String = str(Simulation.board_slots()[_selected_slot_index])
			var slot_operation: OperationDefinition = ContentDatabase.get_operation(slot_id)
			var slot_name: String = slot_operation.name if slot_operation != null else "module"
			set_context(
				"MOVING %s — PICK ANOTHER SLOT" % slot_name.to_upper(), ConsoleStyle.WARNING
			)
		_:
			var workflow: Dictionary = Simulation.active_workflow()
			set_context(str(workflow.get("name", "")).to_upper())


## The footer commands change with the selection, so the only ones printed are
## the ones that would do something if pressed.
func _refresh_actions() -> void:
	var entries: Array = []
	var spare: int = Simulation.workflow_capacity() - Simulation.workflow_count()
	if _selection == Selection.SLOT:
		entries.append({
			"index": "R",
			"headline": "REMOVE MODULE",
			"value": "CLEAR THIS SLOT",
			"pressed": _on_remove_pressed,
		})
	if _selection != Selection.NONE:
		entries.append({
			"index": "C", "headline": "CANCEL SELECTION", "pressed": _clear_selection,
		})
	entries.append({
		"index": "N",
		"headline": "NEW WORKFLOW",
		"value": "%d SPARE" % spare if spare > 0 else "NO ROOM",
		"enabled": spare > 0,
		"pressed": _on_new_workflow,
	})
	entries.append({
		"index": "D",
		"headline": "DELETE WORKFLOW",
		"destructive": true,
		"enabled": Simulation.workflow_count() > 1,
		"pressed": _on_delete_workflow,
	})
	set_actions(entries)


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


func _on_slot_selected(meta: Variant) -> void:
	var index: int = int(meta)
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


func _on_module_selected(meta: Variant) -> void:
	var operation_id: String = str(meta)
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
