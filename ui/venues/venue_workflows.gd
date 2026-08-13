extends VenueScene

## Workflows: the room where the run's ways of working are wired up.
##
## This is the screen the whole exercise was for. It was a `ConsoleOverlay` inside
## a centred frame inside the side panel, which on a handset meant editing a
## pipeline through a letterbox 442 pixels wide: two tables of four columns each,
## every effect wrapped to three lines, and a tap target the width of a fingernail.
##
## Here it is a wall. The pipelines the run owns are listed on the left, the
## pipeline being edited is the board — burn order top to bottom, one stage per
## card, because the order *is* the screen — and the modules not yet placed are
## on the bench under it. Placing is still the same two taps it always was: pick a
## module, pick a slot.

enum Selection { NONE, MODULE, SLOT }

## Printed on a card for a slot with nothing in it yet.
const EMPTY_STAGE := "— EMPTY —"

## Where the two halves of the board are separated, since they are two boards in
## one panel rather than one list of mixed things.
const SECTION_GAP := 10

var _kicker: Label = null
var _workflows: VBoxContainer = null
var _name_edit: LineEdit = null
var _commands: VBoxContainer = null
var _new_row: ConsoleMenuRow = null
var _delete_row: ConsoleMenuRow = null
var _board_panel: VenuePanel = null
var _board_scroll: ScrollContainer = null
var _board_column: VBoxContainer = null
var _prompt: Label = null
var _pipeline_caption: Label = null
var _pipeline: VenueBoard = null
var _bench_caption: Label = null
var _bench: VenueBoard = null
var _signage_panel: VenuePanel = null
var _sign: VBoxContainer = null
var _detail: ConsoleDetail = null
var _notice: Label = null
var _workflow_rows: Array[ConsoleMenuRow] = []

var _selection: Selection = Selection.NONE
var _selected_module_id: String = ""
var _selected_slot_index: int = -1


func venue_key() -> String:
	return "workflows"


func _hint_entries() -> Array:
	# Placing is a tap on the board rather than a key, so the only keys worth
	# printing are the two that undo a selection and leave.
	return [{"index": "C", "headline": "CANCEL"}]


func _build_venue() -> void:
	_build_index()
	_build_board()
	_build_signage()
	_build_notice()
	Simulation.work_tick_completed.connect(refresh)
	EventBus.operation_acquired.connect(func(_id: String) -> void: refresh())
	EventBus.run_started.connect(refresh)


## The left-hand panel: which pipelines exist, what this one is called, and the
## two commands that change the set of them.
func _build_index() -> void:
	var panel: VenuePanel = add_panel("index", "Workflows", {
		"console_order": 10, "console_min": 200.0,
	})
	var content: VBoxContainer = panel.content()

	_kicker = ConsoleStyle.label(
		"PIPELINES", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	content.add_child(_kicker)

	_workflows = VBoxContainer.new()
	_workflows.add_theme_constant_override("separation", 0)
	content.add_child(_workflows)

	content.add_child(ConsoleStyle.rule(0.22))

	_name_edit = ConsoleStyle.line_edit("workflow name", ConsoleStyle.FONT_SMALL)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.focus_exited.connect(func() -> void: _on_name_submitted(_name_edit.text))
	content.add_child(_name_edit)

	_commands = VBoxContainer.new()
	_commands.add_theme_constant_override("separation", 0)
	_commands.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_commands)

	_new_row = ConsoleMenuRow.new()
	_new_row.index_label = "N"
	_new_row.headline = "NEW WORKFLOW"
	_new_row.pressed.connect(_on_new_workflow)
	_commands.add_child(_new_row)

	_delete_row = ConsoleMenuRow.new()
	_delete_row.index_label = "D"
	_delete_row.headline = "DELETE THIS ONE"
	_delete_row.destructive = true
	_delete_row.pressed.connect(_on_delete_workflow)
	_commands.add_child(_delete_row)


## The board: the pipeline, then the bench under it.
##
## Both are `VenueBoard`s inline in one scroll rather than scrolling themselves,
## because a scroll view inside a scroll view swallows the drag and traps the
## player — which is exactly what the old overlay did on a handset.
func _build_board() -> void:
	_board_panel = add_panel("board", "Pipeline", {
		"console_order": 20, "console_min": 320.0, "grow": true,
	})
	var content: VBoxContainer = _board_panel.content()

	# What the editor is waiting for, at the top of the thing being edited rather
	# than in a banner somewhere else on the wall.
	_prompt = ConsoleStyle.label("", ConsoleStyle.FONT_SMALL, ConsoleStyle.WARNING)
	_prompt.visible = false
	content.add_child(_prompt)

	_board_scroll = ScrollContainer.new()
	_board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_board_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_board_scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", SECTION_GAP)
	_board_scroll.add_child(column)
	_board_column = column

	_pipeline_caption = ConsoleStyle.label(
		"PIPELINE · TOP TO BOTTOM", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	column.add_child(_pipeline_caption)

	_pipeline = VenueBoard.new()
	_pipeline.tile_selected.connect(_on_slot_pressed)
	# One stage per row whatever the width: burn order is the point of the
	# listing, and a grid would have the player reading it in a snake.
	_pipeline.set_inline(true, 1)
	column.add_child(_pipeline)

	_bench_caption = ConsoleStyle.label(
		"MODULES", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	column.add_child(_bench_caption)

	_bench = VenueBoard.new()
	_bench.tile_selected.connect(_on_module_pressed)
	_bench.set_inline(true)
	column.add_child(_bench)


func _build_signage() -> void:
	_signage_panel = add_panel("signage", "", {
		"console_order": 30, "console_min": 0.0,
	})
	var content: VBoxContainer = _signage_panel.content()

	_sign = VBoxContainer.new()
	_sign.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sign.add_theme_constant_override("separation", 8)
	content.add_child(_sign)
	for line in ["PICK A MODULE", "THEN A SLOT"]:
		var label: Label = ConsoleStyle.label(
			line, ConsoleStyle.FONT_BODY, ConsoleStyle.PHOSPHOR_DIM
		)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_sign.add_child(label)

	_detail = ConsoleDetail.new()
	_detail.visible = false
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.action_pressed.connect(_on_detail_action)
	_detail.closed.connect(_clear_selection)
	content.add_child(_detail)


## The card by the cabinet: which contracts this pipeline is currently
## responsible for, so a change made here is never a surprise to work already
## under way.
func _build_notice() -> void:
	var panel: VenuePanel = add_panel("notice", "", {
		"console_order": 40, "console_min": 70.0,
	})
	_notice = ConsoleStyle.paragraph("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.content().add_child(_notice)


# --- Refresh -----------------------------------------------------------------

func refresh() -> void:
	if _pipeline == null:
		return
	_refresh_workflows()
	_refresh_name()
	_refresh_commands()
	_refresh_pipeline()
	_refresh_bench()
	_refresh_prompt()
	_refresh_notice()
	_refresh_detail()
	# The board just changed height, and the containers inside it only report the
	# new one after this frame has settled.
	call_deferred("_layout_board_scroll")


## One row per pipeline the run owns. The capacity it has not spent is reported on
## the NEW command rather than shown as a phantom row.
func _refresh_workflows() -> void:
	var list: Array = Simulation.workflows()
	if list.size() != _workflow_rows.size():
		for row in _workflow_rows:
			_workflows.remove_child(row)
			row.queue_free()
		_workflow_rows.clear()
		for index in range(list.size()):
			var row := ConsoleMenuRow.new()
			row.index_label = str(index + 1)
			row.pressed.connect(_on_workflow_pressed.bind(index))
			_workflows.add_child(row)
			_workflow_rows.append(row)
	var active: int = Simulation.active_workflow_index()
	for index in range(_workflow_rows.size()):
		var workflow: Dictionary = Dictionary(list[index])
		var row: ConsoleMenuRow = _workflow_rows[index]
		row.headline = str(workflow.get("name", "Workflow")).to_upper()
		row.value_text = "%d MOD" % _filled_count(Array(workflow.get("slots", [])))
		row.set_selected(index == active)
	_layout_rows()


func _filled_count(slots: Array) -> int:
	var count: int = 0
	for entry in slots:
		if str(entry) != "":
			count += 1
	return count


func _refresh_name() -> void:
	if _name_edit.has_focus():
		return
	_name_edit.text = str(Simulation.active_workflow().get("name", ""))


func _refresh_commands() -> void:
	var spare: int = Simulation.workflow_capacity() - Simulation.workflow_count()
	_new_row.value_text = "%d SPARE" % spare if spare > 0 else "NO ROOM"
	_new_row.disabled = spare <= 0
	_delete_row.disabled = Simulation.workflow_count() <= 1
	_layout_rows()


func _refresh_pipeline() -> void:
	_board_panel.set_heading(
		str(Simulation.active_workflow().get("name", "Pipeline"))
	)
	var slots: Array = Simulation.board_slots()
	var job: Dictionary = Simulation.editing_job()
	var blocked: int = int(job.get("blocked_slots", 0))
	var blocked_label: String = _blocked_label(job)
	var evaluator := ExpressionEvaluator.new()
	var entries: Array = []
	for index in range(slots.size()):
		entries.append(
			_slot_entry(slots, index, blocked, blocked_label, evaluator)
		)
	var note: String = ""
	if slots.is_empty():
		note = "NO SLOTS — THIS WORKFLOW HAS NO PIPELINE YET"
	_pipeline.set_entries(entries, note)
	if _selection == Selection.SLOT:
		_pipeline.select(_slot_meta(_selected_slot_index))
	else:
		_pipeline.clear_selection()


## The bench first, then everything already placed: what the player can still
## spend is the part of the list they came here for.
func _refresh_bench() -> void:
	var slots: Array = Simulation.board_slots()
	var owned: Array = Simulation.owned_operations()
	var ordered: Array = []
	for operation_id in owned:
		if not (str(operation_id) in slots):
			ordered.append(str(operation_id))
	var benched: int = ordered.size()
	for operation_id in owned:
		if str(operation_id) in slots:
			ordered.append(str(operation_id))
	_bench_caption.text = (
		"MODULES · %d OWNED, %d ON THE BENCH" % [owned.size(), benched]
		if benched > 0
		else "MODULES · %d OWNED, ALL IN THE PIPELINE" % owned.size()
	)
	var evaluator := ExpressionEvaluator.new()
	var entries: Array = []
	for operation_id in ordered:
		var entry: Dictionary = _module_entry(str(operation_id), slots, evaluator)
		if not entry.is_empty():
			entries.append(entry)
	var note: String = ""
	if entries.is_empty():
		note = "NO MODULES OWNED YET — FINISH CONTRACTS TO EARN THEM"
	_bench.set_entries(entries, note)
	if _selection == Selection.MODULE:
		_bench.select(_module_meta(_selected_module_id))
	else:
		_bench.clear_selection()


func _refresh_prompt() -> void:
	match _selection:
		Selection.MODULE:
			_prompt.text = "PLACING %s — PICK A SLOT" % _operation_name(
				_selected_module_id
			).to_upper()
		Selection.SLOT:
			_prompt.text = "MOVING %s — PICK ANOTHER SLOT" % _slot_name(
				_selected_slot_index
			).to_upper()
		_:
			_prompt.text = ""
	_prompt.visible = _prompt.text != ""


func _refresh_notice() -> void:
	var workflow_id: String = str(Simulation.active_workflow().get("id", ""))
	var names: PackedStringArray = []
	for job in Array(Simulation.run_state.business.get("active_jobs", [])):
		if job is Dictionary and str(Dictionary(job).get("workflow_id", "")) == workflow_id:
			names.append(str(Dictionary(job).get("name", "a contract")).to_upper())
	if names.is_empty():
		_notice.text = "NO CONTRACT ASSIGNED"
		_notice.add_theme_color_override("font_color", ConsoleStyle.PHOSPHOR_DIM)
		return
	_notice.text = "WORKING\n%s" % " · ".join(names)
	_notice.add_theme_color_override("font_color", ConsoleStyle.PHOSPHOR)


# --- Tiles -------------------------------------------------------------------

func _slot_meta(index: int) -> String:
	return "slot:%d" % index


func _module_meta(operation_id: String) -> String:
	return "mod:%s" % operation_id


## One stage of the pipeline. The badge is the figure because a stage is judged on
## what it does to the batch, and the effect line carries any combo it has live
## with its neighbours — which exists only because of what sits either side, so it
## belongs on the stage rather than on the module.
func _slot_entry(
	slots: Array,
	index: int,
	blocked: int,
	blocked_label: String,
	evaluator: ExpressionEvaluator
) -> Dictionary:
	var number: String = "%02d" % (index + 1)
	if index < blocked:
		return {
			"meta": null,
			"name": "%s · OCCUPIED" % number,
			"figure": "×",
			"figure_color": ConsoleStyle.DANGER,
			"spec": blocked_label,
			"status": "TAKEN BY THE CONTRACT",
			"status_color": ConsoleStyle.DANGER,
		}
	var operation: OperationDefinition = ContentDatabase.get_operation(str(slots[index]))
	if operation == null:
		return {
			"meta": _slot_meta(index),
			"name": "%s · %s" % [number, EMPTY_STAGE],
			"figure": "",
			"spec": "Pick a module from the bench, then this slot.",
			"status": "EMPTY",
		}
	return {
		"meta": _slot_meta(index),
		"name": "%s · %s" % [number, operation.name],
		"figure": evaluator.render_template(operation.badge, operation.parameters),
		"figure_color": AssetCatalog.rarity_color(operation.rarity),
		"spec": _stage_effect(operation, slots, index, blocked, evaluator),
		"price": operation.category.to_upper(),
		"price_color": ConsoleStyle.PHOSPHOR_DIM,
		"status": "TAP TO MOVE",
	}


func _module_entry(
	operation_id: String, slots: Array, evaluator: ExpressionEvaluator
) -> Dictionary:
	var operation: OperationDefinition = ContentDatabase.get_operation(operation_id)
	if operation == null:
		return {}
	var placed: bool = operation_id in slots
	return {
		"meta": _module_meta(operation_id),
		"name": operation.name,
		"figure": evaluator.render_template(operation.badge, operation.parameters),
		"figure_color": AssetCatalog.rarity_color(operation.rarity),
		"spec": evaluator.render_template(
			operation.description_template, operation.parameters
		),
		"price": operation.category.to_upper(),
		"price_color": ConsoleStyle.PHOSPHOR_DIM,
		"status": "IN PIPELINE" if placed else "ON THE BENCH",
		"status_color": ConsoleStyle.PHOSPHOR_DIM if placed else ConsoleStyle.PHOSPHOR,
	}


func _stage_effect(
	operation: OperationDefinition,
	slots: Array,
	index: int,
	blocked: int,
	evaluator: ExpressionEvaluator
) -> String:
	var text: String = evaluator.render_template(
		operation.description_template, operation.parameters
	)
	var combos: Array = operation.active_combos(
		_neighbour(slots, index, -1, blocked), _neighbour(slots, index, 1, blocked)
	)
	for combo in combos:
		if not combo is Dictionary:
			continue
		text += "  ◆ %s — %s" % [
			str(Dictionary(combo).get("name", "Combo")),
			evaluator.render_template(
				str(Dictionary(combo).get("description", "")), operation.parameters
			),
		]
	return text


## The nearest filled stage in `step` direction. Empty slots between two modules
## do not break a combo the player can plainly see lining up.
func _neighbour(slots: Array, index: int, step: int, blocked: int) -> String:
	var i: int = index + step
	while i >= blocked and i < slots.size():
		if str(slots[i]) != "":
			return str(slots[i])
		i += step
	return ""


func _blocked_label(job: Dictionary) -> String:
	for rule in Array(job.get("board_rules", [])):
		if rule is Dictionary and str(Dictionary(rule).get("type", "")) == BoardSystem.RULE_BLOCKED_SLOTS:
			return str(Dictionary(rule).get("label", "This contract already owns the slot."))
	return "This contract already owns the slot."


func _operation_name(operation_id: String) -> String:
	var operation: OperationDefinition = ContentDatabase.get_operation(operation_id)
	return operation.name if operation != null else operation_id


func _slot_name(index: int) -> String:
	var slots: Array = Simulation.board_slots()
	if index < 0 or index >= slots.size():
		return "module"
	return _operation_name(str(slots[index]))


# --- The sheet ---------------------------------------------------------------

## What is selected, said in full beside the board: the module and what it does,
## and the one command that applies to it.
func _refresh_detail() -> void:
	var reading: bool = _selection != Selection.NONE
	_sign.visible = not reading
	_detail.visible = reading
	_signage_panel.set_heading("" if not reading else "Selected")
	if not reading:
		return
	var evaluator := ExpressionEvaluator.new()
	var operation_id: String = (
		_selected_module_id if _selection == Selection.MODULE
		else str(Simulation.board_slots()[_selected_slot_index])
	)
	var operation: OperationDefinition = ContentDatabase.get_operation(operation_id)
	if operation == null:
		_clear_selection()
		return
	var lines: Array = [
		{
			"text": evaluator.render_template(
				operation.description_template, operation.parameters
			),
		},
		{"stat": "Type", "value": operation.category.capitalize()},
		{"stat": "Rarity", "value": operation.rarity.capitalize()},
	]
	if _selection == Selection.MODULE:
		lines.append({"text": "Pick a slot in the pipeline to place it."})
		_detail.show_detail(operation.name.to_upper(), lines, "[ C ] CANCEL", false)
		return
	lines.append({
		"stat": "Slot", "value": "%02d" % (_selected_slot_index + 1),
	})
	lines.append({"text": "Pick another slot to move it, or clear this one."})
	_detail.show_detail(
		operation.name.to_upper(), lines, "[ R ] REMOVE FROM PIPELINE", true
	)


# --- Actions -----------------------------------------------------------------

## Placing is two taps: a module, then a slot. The second tap is on the board
## rather than on a confirm button, so the gesture is the same on a desk and under
## a thumb.
func _on_slot_pressed(meta: Variant) -> void:
	if meta == null:
		return
	var index: int = int(str(meta).trim_prefix("slot:"))
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
			_selected_module_id = ""
			refresh()


func _on_module_pressed(meta: Variant) -> void:
	if meta == null:
		return
	var operation_id: String = str(meta).trim_prefix("mod:")
	if _selection == Selection.MODULE and _selected_module_id == operation_id:
		_clear_selection()
		return
	_selection = Selection.MODULE
	_selected_module_id = operation_id
	_selected_slot_index = -1
	refresh()


func _on_detail_action() -> void:
	if _selection != Selection.SLOT:
		return
	Simulation.clear_slot(_selected_slot_index)
	_clear_selection()


func _clear_selection() -> void:
	_selection = Selection.NONE
	_selected_module_id = ""
	_selected_slot_index = -1
	refresh()


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
	var wanted: String = new_name.strip_edges()
	if wanted == "":
		return
	if str(Simulation.active_workflow().get("name", "")) == wanted:
		return
	if Simulation.rename_workflow(Simulation.active_workflow_index(), wanted):
		refresh()


## The pipeline answers to the keyboard as well as the pointer: the workflows are
## numbered, and the two commands that are not a tap on the board have letters.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if SceneRouter.investor_busy() or _name_edit.has_focus():
		return
	match event.keycode:
		KEY_C:
			if _selection != Selection.NONE:
				_clear_selection()
				get_viewport().set_input_as_handled()
			return
		KEY_R:
			if _selection == Selection.SLOT:
				_on_detail_action()
				get_viewport().set_input_as_handled()
			return
		KEY_N:
			if not _new_row.disabled:
				_on_new_workflow()
				get_viewport().set_input_as_handled()
			return
	var slot: int = event.keycode - KEY_1
	if slot < 0 or slot >= _workflow_rows.size():
		return
	_on_workflow_pressed(slot)
	get_viewport().set_input_as_handled()


# --- Layout ------------------------------------------------------------------

func _on_venue_layout() -> void:
	var scale: float = console_scale()
	var width: float = content_width("board")
	if _pipeline != null:
		_pipeline.set_metrics(scale, width)
	if _bench != null:
		_bench.set_metrics(scale, width)
	if _detail != null:
		_detail.set_metrics(scale)
	_layout_board_scroll()
	_layout_rows()
	var font_tiny: int = ConsoleMetrics.font_tiny(scale)
	for label in [_kicker, _pipeline_caption, _bench_caption, _notice]:
		if label != null:
			label.add_theme_font_size_override("font_size", font_tiny)
	if _prompt != null:
		_prompt.add_theme_font_size_override("font_size", ConsoleMetrics.font_small(scale))
	if _name_edit != null:
		_name_edit.add_theme_font_size_override("font_size", ConsoleMetrics.font_small(scale))
		_name_edit.custom_minimum_size = Vector2(0.0, ConsoleMetrics.row_height(scale))
	var font_body: int = ConsoleMetrics.font_body(scale)
	for label in _sign.get_children():
		if label is Label:
			label.add_theme_font_size_override("font_size", font_body)


## On the wall the board is a fixed rectangle and the pipeline scrolls inside it.
## In the console column it must not: the column is already a scroll view, and a
## scroll view inside one swallows the drag — the player reaches the bottom of the
## pipeline and cannot get past it to the bench. So the board reports its full
## height instead and the column grows.
func _layout_board_scroll() -> void:
	if _board_scroll == null:
		return
	var nested: bool = console_mode()
	_board_scroll.vertical_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED if nested else ScrollContainer.SCROLL_MODE_AUTO
	)
	_board_scroll.custom_minimum_size.y = (
		_board_column.get_combined_minimum_size().y if nested else 0.0
	)


func _layout_rows() -> void:
	var scale: float = console_scale()
	var font: int = ConsoleMetrics.font_small(scale)
	var height: int = ConsoleMetrics.row_height(scale)
	var pad: int = ConsoleMetrics.pad_h(scale)
	for row in _workflow_rows:
		row.set_metrics(font, height, pad)
	for row in [_new_row, _delete_row]:
		if row != null:
			row.set_metrics(font, height, pad)
