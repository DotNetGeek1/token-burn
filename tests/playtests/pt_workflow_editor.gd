extends PlaytestCase

## Exercises the workflow whiteboard's two input paths against the real
## simulation. The low-level card assertions cover Godot's drag contract; the
## venue assertions prove drops reach the same board state used by a burn.


func play(harness: UiHarness) -> void:
	await harness.boot(73)

	var module_id: String = _unused_module_id()
	assert_true(module_id != "", "There is a module available for the drag test")
	if module_id == "":
		return
	var owned: Array = Array(Simulation.run_state.build.get("modules", []))
	if not (module_id in owned):
		owned.append(module_id)
	Simulation.run_state.build["modules"] = owned

	# Make one unambiguously open target without changing the save schema or
	# bypassing the same API the editor uses.
	Simulation.clear_slot(0)
	await harness.goto_route("workflows")
	var venue: Node = harness.current_scene()
	assert_true(venue != null, "Workflow venue opens")
	assert_true(venue._tray is WorkflowModuleTray, "Unused modules have a dedicated tray")
	assert_true(venue._diagram is WorkflowDiagram, "The active workflow has a diagram")
	var photographed_split: float = venue._body.size.x * venue.LEFT_SHARE
	assert_true(
		venue._left.position.x >= venue.LEFT_INSET * venue.console_scale() - 1.0,
		"The module menu keeps clear of the left whiteboard frame"
	)
	assert_true(
		venue._left.position.x + venue._left.size.x <= photographed_split + 1.0,
		"The module tray stops at the photographed divider"
	)
	assert_true(
		venue._right.position.x >= photographed_split - 1.0,
		"The workflow starts on the diagram side of the divider"
	)
	assert_true(
		venue._right.position.x - (venue._left.position.x + venue._left.size.x)
		>= venue.LEFT_INSET * venue.console_scale() - 1.0,
		"The inset menu still leaves a generous divider gutter"
	)
	assert_true(
		venue._body.position.y >= venue._top_spacer.custom_minimum_size.y - 1.0,
		"The whiteboard content keeps its measured top inset"
	)
	var paper_card: WorkflowCard = _first_visible_card(venue._tray)
	assert_true(paper_card != null, "The unused tray prints a module card")
	if paper_card != null:
		var paper: StyleBox = paper_card.get_theme_stylebox("panel")
		assert_true(
			paper is StyleBoxFlat and (paper as StyleBoxFlat).bg_color.get_luminance() > 0.55,
			"Module cards use light paper instead of console glass"
		)
		var paper_module: ModuleDefinition = ContentDatabase.get_module(paper_card.module_id)
		assert_true(
			paper_module != null
			and paper_card._name.text == paper_module.name.to_upper()
			and paper_card._name.visible
			and paper_card._name.size.x > 1.0,
			"An unused note prints its module name on a dedicated line"
		)
		# Exercise the actual desktop release event. Directly calling the venue
		# handler misses focus, drag and relayout interactions in WorkflowCard.
		await harness.driver.press(paper_card)
		assert_eq(
			venue._selection,
			venue.Selection.MODULE,
			"Clicking a desktop module selects it without stalling the editor"
		)
		assert_eq(
			venue._selected_module_id,
			paper_card.module_id,
			"The selected desktop module is ready for a stage"
		)
		await harness.driver.press(paper_card)
		assert_eq(
			venue._selection,
			venue.Selection.NONE,
			"Clicking the selected module again clears it"
		)
	var first_stage: WorkflowCard = venue._diagram._cards[0]
	assert_true(
		first_stage.size.y <= venue._diagram.CARD_HEIGHT * venue.console_scale() + 1.0,
		"Workflow notes use the compact card height"
	)
	if first_stage.module_id != "":
		var stage_module: ModuleDefinition = ContentDatabase.get_module(first_stage.module_id)
		assert_true(
			stage_module != null
			and first_stage._name.text == stage_module.name.to_upper()
			and first_stage._name.visible
			and first_stage._name.size.x > 1.0,
			"A workflow stage prints its module name on a dedicated line"
		)

	var open_card := WorkflowCard.new()
	open_card.set_card({
		"meta": "slot:0", "role": WorkflowCard.ROLE_SLOT,
		"slot_index": 0, "name": "Empty",
	})
	assert_true(
		open_card._can_drop_data(Vector2.ZERO, {
			"kind": WorkflowCard.ROLE_MODULE, "module_id": module_id,
		}),
		"An open stage accepts a dragged module"
	)
	assert_false(
		open_card._can_drop_data(Vector2.ZERO, {
			"kind": WorkflowCard.ROLE_SLOT, "slot_index": 0,
		}),
		"A stage refuses a no-op drop onto itself"
	)

	var blocked_card := WorkflowCard.new()
	blocked_card.set_card({
		"meta": "slot:1", "role": WorkflowCard.ROLE_SLOT,
		"slot_index": 1, "name": "Locked", "blocked": true,
	})
	assert_false(
		blocked_card._can_drop_data(Vector2.ZERO, {
			"kind": WorkflowCard.ROLE_MODULE, "module_id": module_id,
		}),
		"A contract-locked stage rejects a drop"
	)
	open_card.free()
	blocked_card.free()

	venue._on_module_dropped(module_id, 0)
	assert_eq(
		str(Simulation.board_slots()[0]), module_id,
		"Dropping from the tray places the module in the target stage"
	)
	assert_false(
		_has_visible_module(venue._tray, module_id),
		"A placed module leaves the unused tray"
	)

	var second: int = _filled_slot_after(0)
	if second >= 0:
		var other: String = str(Simulation.board_slots()[second])
		venue._on_slot_dropped(0, second)
		assert_eq(
			str(Simulation.board_slots()[second]), module_id,
			"Dragging a stage onto another stage moves it"
		)
		assert_eq(
			str(Simulation.board_slots()[0]), other,
			"The displaced stage swaps back into the source position"
		)
	else:
		assert_true(true, "No second filled stage was available for a swap")

	assert_true(
		venue._back_button != null and venue._back_button.is_visible_in_tree(),
		"The painted workflow whiteboard has a visible way back"
	)
	await harness.driver.press(venue._back_button)
	assert_eq(SceneRouter.current, SceneRouter.DESK, "Back to desk leaves the workflow venue")


func _unused_module_id() -> String:
	var slots: Array = Simulation.board_slots()
	for module in ContentDatabase.modules:
		if not (module.id in slots):
			return module.id
	return ""


func _filled_slot_after(start: int) -> int:
	var slots: Array = Simulation.board_slots()
	for index in range(start + 1, slots.size()):
		if str(slots[index]) != "":
			return index
	return -1


func _has_visible_module(tray: WorkflowModuleTray, module_id: String) -> bool:
	for card in tray.find_children("*", "WorkflowCard", true, false):
		if card.visible and card.module_id == module_id:
			return true
	return false


func _first_visible_card(tray: WorkflowModuleTray) -> WorkflowCard:
	for card in tray.find_children("*", "WorkflowCard", true, false):
		if card.visible:
			return card as WorkflowCard
	return null
