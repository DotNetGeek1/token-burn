extends VenueScene

## The visual workflow editor. The room is one large magnetic whiteboard: unused
## modules live in the narrow tray on the left and the active pipeline is a
## connected diagram on the right. Pointer users can drag cards directly; the
## tap-then-tap interaction remains as an equivalent touch and keyboard path.

enum Selection { NONE, MODULE, SLOT }

const LEFT_SHARE := 0.238
const RIGHT_SHARE := 0.762
const SECTION_GAP := 48
const LEFT_INSET := 10
## More of the divider gutter belongs to the diagram side: its heading and first
## stage should begin clearly beyond the metal rail, not straddle it.
const DIVIDER_RIGHT_WEIGHT := 0.65
## Clears the photographed metal rail. Keep this at the measured inset while
## the live notes are re-aligned to the writing surface; padding the panel is
## not a substitute.
const TOP_INSET := 24
const DOT := " \u00b7 "
const BOARD_INK := Color(0.025, 0.12, 0.072)
const BOARD_INK_DIM := Color(0.055, 0.22, 0.13)
const BOARD_WARNING := Color(0.38, 0.23, 0.035)

var _board_panel: VenuePanel = null
var _top_spacer: Control = null
var _body: Control = null
var _left: VBoxContainer = null
var _right: VBoxContainer = null

var _workflow_caption: Label = null
var _workflow_picker: OptionButton = null
var _name_edit: LineEdit = null
var _new_button: Button = null
var _delete_button: Button = null
var _tray_caption: Label = null
var _tray: WorkflowModuleTray = null
var _back_button: Button = null

var _pipeline_title: Label = null
var _prompt: Label = null
var _diagram: WorkflowDiagram = null
var _status: Label = null
var _remove_button: Button = null
var _add_stage_button: Button = null

var _selection: Selection = Selection.NONE
var _selected_module_id: String = ""
var _selected_slot_index: int = -1
var _syncing_picker: bool = false


func venue_key() -> String:
	return "workflows"


func _painted_hints() -> bool:
	return false


## The whiteboard is already enlarged by the room camera. Applying the complete
## handset readability multiplier inside that enlarged surface makes the picker
## outgrow the left side and the magnetic notes crowd the workflow. Compensate
## only this full-board editor for the camera zoom; narrow venue panels still use
## VenueScene's ordinary close-up scale.
func _lean_scale() -> float:
	return clampf(_scale / maxf(_lean_zoom, 1.0), 1.0, _scale)


func _build_venue() -> void:
	_board_panel = add_panel("board", "", {
		"console_order": 10,
		"console_min": 760.0,
		"grow": true,
	})
	_board_panel.set_whiteboard(true)
	var root: VBoxContainer = _board_panel.content()
	_top_spacer = Control.new()
	_top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_top_spacer)

	_body = Control.new()
	_body.clip_contents = true
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.resized.connect(_layout_whiteboard_columns)
	root.add_child(_body)

	_build_module_side()
	_build_diagram_side()

	Simulation.work_tick_completed.connect(refresh)
	EventBus.module_acquired.connect(func(_id: String) -> void: refresh())
	EventBus.run_started.connect(refresh)


func _build_module_side() -> void:
	_left = VBoxContainer.new()
	_left.name = "ModuleTray"
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left.size_flags_stretch_ratio = LEFT_SHARE
	_left.add_theme_constant_override("separation", 6)
	_body.add_child(_left)

	_workflow_caption = ConsoleStyle.label(
		"WORKFLOWS", ConsoleStyle.FONT_BODY, BOARD_INK
	)
	_left.add_child(_workflow_caption)

	_workflow_picker = OptionButton.new()
	_workflow_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workflow_picker.fit_to_longest_item = false
	_style_board_control(_workflow_picker)
	_workflow_picker.item_selected.connect(_on_workflow_selected)
	_left.add_child(_workflow_picker)

	_name_edit = ConsoleStyle.line_edit("workflow name", ConsoleStyle.FONT_SMALL)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_board_control(_name_edit)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.focus_exited.connect(func() -> void: _on_name_submitted(_name_edit.text))
	_left.add_child(_name_edit)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	_left.add_child(actions)

	_new_button = _board_button("+ NEW")
	_new_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_button.pressed.connect(_on_new_workflow)
	actions.add_child(_new_button)

	_delete_button = _board_button("DELETE", true)
	_delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_button.pressed.connect(_on_delete_workflow)
	actions.add_child(_delete_button)

	_left.add_child(ConsoleStyle.rule(0.35))

	_tray_caption = ConsoleStyle.label(
		"UNUSED MODULES", ConsoleStyle.FONT_SMALL, BOARD_INK
	)
	_left.add_child(_tray_caption)

	_tray = WorkflowModuleTray.new()
	_tray.module_tapped.connect(_on_module_tapped)
	_left.add_child(_tray)

	_back_button = _board_button("< BACK TO DESK")
	_back_button.pressed.connect(_on_back)
	_left.add_child(_back_button)


func _build_diagram_side() -> void:
	_right = VBoxContainer.new()
	_right.name = "WorkflowDiagram"
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.size_flags_stretch_ratio = RIGHT_SHARE
	_right.add_theme_constant_override("separation", 6)
	_body.add_child(_right)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	_right.add_child(title_row)

	_pipeline_title = ConsoleStyle.label(
		"WORKFLOW", ConsoleStyle.FONT_HEAD, BOARD_INK
	)
	_pipeline_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_pipeline_title)

	_add_stage_button = _board_button("+ STAGE")
	_add_stage_button.visible = false
	_add_stage_button.pressed.connect(_add_overflow_stage)
	title_row.add_child(_add_stage_button)

	_remove_button = _board_button("REMOVE STAGE", true)
	_remove_button.visible = false
	_remove_button.pressed.connect(_remove_selected_slot)
	title_row.add_child(_remove_button)

	_prompt = ConsoleStyle.label(
		"DRAG A MODULE INTO THE WORKFLOW", ConsoleStyle.FONT_SMALL, BOARD_WARNING
	)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_right.add_child(_prompt)

	_diagram = WorkflowDiagram.new()
	_diagram.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diagram.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_diagram.slot_tapped.connect(_on_slot_tapped)
	_diagram.module_dropped.connect(_on_module_dropped)
	_diagram.slot_dropped.connect(_on_slot_dropped)
	_right.add_child(_diagram)

	_status = ConsoleStyle.paragraph(
		"", ConsoleStyle.FONT_TINY, BOARD_INK_DIM
	)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_right.add_child(_status)


func _board_button(text: String, destructive: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.clip_text = true
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var color: Color = Color("7b3035") if destructive else BOARD_INK
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", BOARD_INK)
	button.add_theme_color_override("font_pressed_color", BOARD_INK)
	button.add_theme_color_override("font_disabled_color", Color(BOARD_INK.r, BOARD_INK.g, BOARD_INK.b, 0.32))
	button.add_theme_stylebox_override("normal", _whiteboard_box(color, 0.38, 0.92))
	button.add_theme_stylebox_override("hover", _whiteboard_box(color, 0.72, 1.0, Color("eee4b0")))
	button.add_theme_stylebox_override("pressed", _whiteboard_box(color, 0.90, 1.0, Color("d8cf9f")))
	button.add_theme_stylebox_override("focus", _whiteboard_box(color, 0.85, 0.96))
	button.add_theme_stylebox_override("disabled", _whiteboard_box(color, 0.16, 0.42))
	return button


func _style_board_control(control: Control) -> void:
	for state in ["normal", "read_only"]:
		control.add_theme_stylebox_override(state, _whiteboard_box(BOARD_INK, 0.36, 0.92))
	control.add_theme_stylebox_override("focus", _whiteboard_box(BOARD_INK, 0.82, 0.96))
	control.add_theme_stylebox_override("hover", _whiteboard_box(BOARD_INK, 0.72, 0.96))
	control.add_theme_stylebox_override("pressed", _whiteboard_box(BOARD_INK, 0.90, 0.98))
	control.add_theme_color_override("font_color", BOARD_INK)
	control.add_theme_color_override("font_hover_color", BOARD_INK)
	control.add_theme_color_override("font_pressed_color", BOARD_INK)
	control.add_theme_color_override("font_placeholder_color", Color(BOARD_INK.r, BOARD_INK.g, BOARD_INK.b, 0.52))


func _whiteboard_box(
	ink: Color,
	border_alpha: float,
	fill_alpha: float,
	fill: Color = Color("f1eee1")
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(fill.r, fill.g, fill.b, fill_alpha)
	box.border_color = Color(ink.r, ink.g, ink.b, border_alpha)
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	return box


# --- Refresh -----------------------------------------------------------------

func refresh() -> void:
	if _diagram == null:
		return
	_refresh_workflow_picker()
	_refresh_commands()
	_refresh_tray()
	_refresh_diagram()
	_refresh_prompt()
	_refresh_status()


func _refresh_workflow_picker() -> void:
	var workflows: Array = Simulation.workflows()
	_syncing_picker = true
	_workflow_picker.clear()
	for index in range(workflows.size()):
		var workflow: Dictionary = Dictionary(workflows[index])
		var filled: int = _filled_count(Array(workflow.get("slots", [])))
		_workflow_picker.add_item(
			"%d  %s%s%d MOD" % [index + 1, str(workflow.get("name", "Workflow")).to_upper(), DOT, filled],
			index
		)
	_workflow_picker.select(Simulation.active_workflow_index())
	_syncing_picker = false
	if not _name_edit.has_focus():
		_name_edit.text = str(Simulation.active_workflow().get("name", ""))


func _refresh_commands() -> void:
	var spare: int = Simulation.workflow_capacity() - Simulation.workflow_count()
	_new_button.text = "+ NEW  (%d)" % spare if spare > 0 else "+ NEW"
	_new_button.disabled = spare <= 0
	_delete_button.disabled = Simulation.workflow_count() <= 1


func _refresh_tray() -> void:
	var slots: Array = Simulation.board_slots()
	var entries: Array = []
	var evaluator := ExpressionEvaluator.new()
	for module_value in Simulation.owned_modules():
		var module_id := str(module_value)
		if module_id in slots:
			continue
		var module: ModuleDefinition = ContentDatabase.get_module(module_id)
		if module == null:
			continue
		entries.append({
			"meta": _module_meta(module_id),
			"role": WorkflowCard.ROLE_MODULE,
			"module_id": module_id,
			"name": module.name,
			"badge": evaluator.render_template(module.badge, module.parameters),
			"description": evaluator.render_template(
				module.description_template, module.parameters
			),
			"status": module.category,
		})
	_tray_caption.text = "%s%s%d" % [
		"ON THE BENCH" if Simulation.overflow_unlocked() else "UNUSED MODULES",
		DOT,
		entries.size(),
	]
	var note: String = ""
	if entries.is_empty():
		note = (
			"ALL OWNED MODULES ARE IN THIS WORKFLOW"
			if not Simulation.owned_modules().is_empty()
			else "FINISH CONTRACTS TO EARN MODULES"
		)
	_tray.set_modules(entries, note)
	if _selection == Selection.MODULE:
		_tray.select(_module_meta(_selected_module_id))
	else:
		_tray.clear_selection()


func _refresh_diagram() -> void:
	var slots: Array = Simulation.board_slots()
	var job: Dictionary = Simulation.editing_job()
	var blocked: int = int(job.get("blocked_slots", 0))
	var blocked_label: String = _blocked_label(job)
	var evaluator := ExpressionEvaluator.new()
	var entries: Array = []
	for index in range(slots.size()):
		entries.append(_slot_entry(slots, index, blocked, blocked_label, evaluator))
	_diagram.set_slots(entries)
	if _selection == Selection.SLOT:
		_diagram.select(_slot_meta(_selected_slot_index))
	else:
		_diagram.clear_selection()
	_pipeline_title.text = str(
		Simulation.active_workflow().get("name", "Workflow")
	).to_upper()
	_add_stage_button.visible = Simulation.can_append_overflow()


func _refresh_prompt() -> void:
	match _selection:
		Selection.MODULE:
			_prompt.text = "DROP %s ON A STAGE%sOR TAP A STAGE" % [
				_module_name(_selected_module_id).to_upper(), DOT
			]
		Selection.SLOT:
			_prompt.text = "DRAG %s TO REORDER%sOR TAP ANOTHER STAGE" % [
				_slot_name(_selected_slot_index).to_upper(), DOT
			]
		_:
			_prompt.text = "DRAG AN UNUSED MODULE FROM THE LEFT INTO THE WORKFLOW"
	_remove_button.visible = _selection == Selection.SLOT


func _refresh_status() -> void:
	var workflow_id: String = str(Simulation.active_workflow().get("id", ""))
	var names: PackedStringArray = []
	for job_value in Array(Simulation.run_state.business.get("active_jobs", [])):
		if not job_value is Dictionary:
			continue
		var job: Dictionary = Dictionary(job_value)
		if str(job.get("workflow_id", "")) == workflow_id:
			names.append(str(job.get("name", "a contract")).to_upper())
	_status.text = (
		"ACTIVE: %s" % DOT.join(names)
		if not names.is_empty()
		else "NO CONTRACT ASSIGNED"
	)


func _slot_entry(
	slots: Array,
	index: int,
	blocked_count: int,
	blocked_label: String,
	evaluator: ExpressionEvaluator
) -> Dictionary:
	var module_id: String = str(slots[index])
	var module: ModuleDefinition = ContentDatabase.get_module(module_id)
	var overflow: bool = index >= Simulation.supported_capacity()
	var step: String = "STAGE %02d%s" % [index + 1, "!" if overflow else ""]
	if index < blocked_count:
		return {
			"meta": _slot_meta(index),
			"role": WorkflowCard.ROLE_SLOT,
			"slot_index": index,
			"module_id": module_id,
			"blocked": true,
			"overflow": overflow,
			"step": step,
			"name": module.name if module != null else "OCCUPIED",
			"badge": "\u00d7",
			"description": blocked_label,
			"status": "CONTRACT LOCKED",
		}
	if module == null:
		return {
			"meta": _slot_meta(index),
			"role": WorkflowCard.ROLE_SLOT,
			"slot_index": index,
			"overflow": overflow,
			"step": step,
			"name": "EMPTY",
			"description": "Drop a module here",
			"status": "UNSUPPORTED" if overflow else "AVAILABLE",
		}
	return {
		"meta": _slot_meta(index),
		"role": WorkflowCard.ROLE_SLOT,
		"slot_index": index,
		"module_id": module_id,
		"overflow": overflow,
		"step": step,
		"name": module.name,
		"badge": "UNSUPPORTED" if overflow else evaluator.render_template(module.badge, module.parameters),
		"description": _stage_effect(module, slots, index, blocked_count, evaluator),
		"status": "UNSUPPORTED" if overflow else module.category,
	}


func _stage_effect(
	module: ModuleDefinition,
	slots: Array,
	index: int,
	blocked_count: int,
	evaluator: ExpressionEvaluator
) -> String:
	var text: String = evaluator.render_template(module.description_template, module.parameters)
	var combos: Array = module.active_combos(
		_neighbour(slots, index, -1, blocked_count),
		_neighbour(slots, index, 1, blocked_count)
	)
	if not combos.is_empty():
		text += "  \u25c6 %s" % str(Dictionary(combos[0]).get("name", "COMBO")).to_upper()
	return text


func _neighbour(slots: Array, index: int, step: int, blocked_count: int) -> String:
	var cursor: int = index + step
	while cursor >= blocked_count and cursor < slots.size():
		if str(slots[cursor]) != "":
			return str(slots[cursor])
		cursor += step
	return ""


func _blocked_label(job: Dictionary) -> String:
	for rule_value in Array(job.get("board_rules", [])):
		if not rule_value is Dictionary:
			continue
		var rule: Dictionary = Dictionary(rule_value)
		if str(rule.get("type", "")) == BoardSystem.RULE_BLOCKED_SLOTS:
			return str(rule.get("label", "This contract owns this stage."))
	return "This contract owns this stage."


# --- Actions -----------------------------------------------------------------

func _on_module_dropped(module_id: String, slot_index: int) -> void:
	if Simulation.place_module(module_id, slot_index):
		_clear_selection()


func _on_slot_dropped(from_index: int, to_index: int) -> void:
	if from_index >= 0 and Simulation.swap_slots(from_index, to_index):
		_clear_selection()


func _on_module_tapped(meta: Variant) -> void:
	if meta == null:
		return
	var module_id: String = str(meta).trim_prefix("mod:")
	if _selection == Selection.MODULE and _selected_module_id == module_id:
		_clear_selection(false)
		return
	_selection = Selection.MODULE
	_selected_module_id = module_id
	_selected_slot_index = -1
	_sync_selection_view()


func _on_slot_tapped(meta: Variant) -> void:
	if meta == null:
		return
	var index: int = int(str(meta).trim_prefix("slot:"))
	match _selection:
		Selection.MODULE:
			if Simulation.place_module(_selected_module_id, index):
				_clear_selection()
		Selection.SLOT:
			if index == _selected_slot_index:
				_clear_selection(false)
			elif Simulation.swap_slots(_selected_slot_index, index):
				_clear_selection()
		_:
			if str(Simulation.board_slots()[index]) == "":
				return
			_selection = Selection.SLOT
			_selected_slot_index = index
			_selected_module_id = ""
			_sync_selection_view()


func _add_overflow_stage() -> void:
	if Simulation.append_overflow_stage() < 0:
		return
	_clear_selection()


func _remove_selected_slot() -> void:
	if _selection == Selection.SLOT and Simulation.clear_slot(_selected_slot_index):
		_clear_selection()


func _clear_selection(rebuild: bool = true) -> void:
	_selection = Selection.NONE
	_selected_module_id = ""
	_selected_slot_index = -1
	if rebuild:
		refresh()
	else:
		_sync_selection_view()


## Selecting a note changes only highlights and instruction copy. Rebuilding the
## picker, tray and full diagram from inside a desktop mouse-release callback can
## churn focus and layout while Godot is still dispatching that same event.
func _sync_selection_view() -> void:
	if _selection == Selection.MODULE:
		_tray.select(_module_meta(_selected_module_id))
	else:
		_tray.clear_selection()
	if _selection == Selection.SLOT:
		_diagram.select(_slot_meta(_selected_slot_index))
	else:
		_diagram.clear_selection()
	_refresh_prompt()


func _on_workflow_selected(index: int) -> void:
	if _syncing_picker:
		return
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
	if wanted == "" or str(Simulation.active_workflow().get("name", "")) == wanted:
		return
	if Simulation.rename_workflow(Simulation.active_workflow_index(), wanted):
		refresh()


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
		KEY_R, KEY_DELETE:
			if _selection == Selection.SLOT:
				_remove_selected_slot()
				get_viewport().set_input_as_handled()
			return
		KEY_N:
			if not _new_button.disabled:
				_on_new_workflow()
				get_viewport().set_input_as_handled()
			return
	var workflow_index: int = event.keycode - KEY_1
	if workflow_index >= 0 and workflow_index < Simulation.workflow_count():
		_on_workflow_selected(workflow_index)
		get_viewport().set_input_as_handled()


# --- Layout ------------------------------------------------------------------

func _on_venue_layout() -> void:
	var scale: float = console_scale()
	_top_spacer.custom_minimum_size.y = (
		0.0 if console_mode() else float(ConsoleMetrics.px(TOP_INSET, scale))
	)
	_left.add_theme_constant_override("separation", ConsoleMetrics.px(6, scale))
	_right.add_theme_constant_override("separation", ConsoleMetrics.px(6, scale))

	var tiny: int = ConsoleMetrics.font_tiny(scale)
	var small: int = ConsoleMetrics.font_small(scale)
	var body_font: int = ConsoleMetrics.font_body(scale)
	var head: int = ConsoleMetrics.font_head(scale)
	_workflow_caption.add_theme_font_size_override("font_size", body_font)
	_tray_caption.add_theme_font_size_override("font_size", small)
	_pipeline_title.add_theme_font_size_override("font_size", head)
	_prompt.add_theme_font_size_override("font_size", small)
	_status.add_theme_font_size_override("font_size", tiny)
	_name_edit.add_theme_font_size_override("font_size", small)
	_workflow_picker.add_theme_font_size_override("font_size", small)
	for button in [_new_button, _delete_button, _remove_button, _back_button]:
		button.add_theme_font_size_override("font_size", small)
	# Console mode already has VenueScene's full-width ESC/BACK row. Keeping one
	# exit in each layout avoids the duplicate controls the venue pass removed.
	_back_button.visible = not console_mode()

	# The tray fills leftover column space and scrolls. Paper-sized cards must
	# not set the VBox's minimum height, or BACK is pushed below `_body`'s clip.
	_tray.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tray.custom_minimum_size.y = ConsoleMetrics.px(260 if console_mode() else 0, scale)
	_tray.set_metrics(scale)
	_diagram.set_metrics(scale)
	_layout_whiteboard_columns()


## The photographed divider is authoritative. A container would first honour the
## controls' minimum widths and only then apply the stretch ratio, which is what
## pushed the tray over the metal rail. Manual placement fixes the split to the
## board, and the narrow controls wrap or clip inside their side of it.
func _layout_whiteboard_columns() -> void:
	if _body == null or _left == null or _right == null or _body.size.x <= 1.0:
		return
	var gap: float = float(ConsoleMetrics.px(SECTION_GAP, console_scale()))
	if console_mode():
		var left_height: float = maxf(
			_left.get_combined_minimum_size().y,
			float(ConsoleMetrics.px(390, console_scale()))
		)
		var right_height: float = maxf(
			_right.get_combined_minimum_size().y,
			float(ConsoleMetrics.px(420, console_scale()))
		)
		_left.position = Vector2.ZERO
		_left.size = Vector2(_body.size.x, left_height)
		_right.position = Vector2(0.0, left_height + gap)
		_right.size = Vector2(_body.size.x, right_height)
		_body.custom_minimum_size.y = left_height + gap + right_height
		return
	var divider_x: float = _body.size.x * LEFT_SHARE
	var left_gutter: float = gap * (1.0 - DIVIDER_RIGHT_WEIGHT)
	var right_gutter: float = gap * DIVIDER_RIGHT_WEIGHT
	var left_inset: float = float(ConsoleMetrics.px(LEFT_INSET, console_scale()))
	_left.position = Vector2(left_inset, 0.0)
	_left.size = Vector2(
		maxf(1.0, divider_x - left_gutter),
		_body.size.y
	)
	_right.position = Vector2(divider_x + right_gutter, 0.0)
	_right.size = Vector2(maxf(1.0, _body.size.x - divider_x - right_gutter), _body.size.y)
	_body.custom_minimum_size.y = 0.0


func _filled_count(slots: Array) -> int:
	var count: int = 0
	for module_id in slots:
		if str(module_id) != "":
			count += 1
	return count


func _slot_meta(index: int) -> String:
	return "slot:%d" % index


func _module_meta(module_id: String) -> String:
	return "mod:%s" % module_id


func _module_name(module_id: String) -> String:
	var module: ModuleDefinition = ContentDatabase.get_module(module_id)
	return module.name if module != null else module_id


func _slot_name(index: int) -> String:
	var slots: Array = Simulation.board_slots()
	if index < 0 or index >= slots.size():
		return "module"
	return _module_name(str(slots[index]))
