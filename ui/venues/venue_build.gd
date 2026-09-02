extends VenueScene

## Your build: the workshop where the run's perks are fitted and pulled.
##
## The same loadout the printed sheet showed — the same capacity, the same equip
## and bench and swap calls — read as a bench with the parts laid out on it. The
## state of the engine is written up the left, the perks themselves are cards on
## the board, and what one of them does and whether it can go in is on the sheet
## beside it.
##
## The table's problem was that a perk's rarity, its tags and the reason it will
## not equip all had to share one row with its name, so every row was a sentence
## fragment. A card has four lines and can afford to say all four things.

## The two racks: what is fitted and what is on the bench beside it.
const ACTIVE := "active"
const BENCH := "bench"

var _kicker: Label = null
var _index_lines: VBoxContainer = null
var _counters: VBoxContainer = null
var _workflow_rule: Control = null
var _workflow_row: ConsoleMenuRow = null
var _workflow_chrome: Button = null
var _painted_back_rule: Control = null
var _painted_back_row: ConsoleMenuRow = null
var _board_panel: VenuePanel = null
var _board: VenueBoard = null
var _notice: Label = null
var _counter_rows: Dictionary = {}
var _rack: String = ACTIVE


func venue_key() -> String:
	return "build"


func _hint_entries() -> Array:
	return []


func _painted_hints() -> bool:
	return false


## The index is a tall strip only 7.5% of the room width, so its close-up reaches
## the camera's maximum zoom. Scale its contents back by that zoom: the panel stays
## in the photographed Build room, while its lower WORKFLOWS door remains on the
## visible part of the panel instead of being pushed below the phone.
func _lean_scale() -> float:
	return clampf(_scale / maxf(_lean_zoom, 1.0), 1.0, _scale)


## Commit 3278eaf used the authored rectangular index region on Web. That is the
## composition the Build artwork was tuned against: the CRT face itself is read
## straight-on even though its metal housing is strongly foreshortened. The later
## generic affine fallback treated the housing's four measured corners as the
## display plane and tilted every menu row down to the right. Keep the newer
## affine mount for other measured panels, but preserve the original Build index
## placement exactly on Web/flat surfaces.
func _place_panel_affine(
	entry: Dictionary,
	panel: VenuePanel,
	plane: PackedVector2Array,
	view: Vector2
) -> bool:
	if str(entry.get("region", "")) != "index":
		return super._place_panel_affine(entry, panel, plane, view)
	if not entry.get("surface") is Node2D:
		return super._place_panel_affine(entry, panel, plane, view)
	var rect: Rect2 = _region_rect("index", view)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	rect = _camera(rect)
	_reset_flat_surface(entry)
	var leaning: bool = str(entry.get("region", "")) == _leaning_on
	if leaning:
		rect.size = rect.size.max(panel.get_combined_minimum_size())
		rect = _clamp_to_window(rect, view)
	_place_panel_rect(entry, panel, rect)
	return true


func _build_venue() -> void:
	_build_index()
	_build_board()
	_build_notice()
	_build_workflow_chrome()
	EventBus.perk_acquired.connect(func(_id: String) -> void: refresh())
	EventBus.run_started.connect(refresh)


func _build_index() -> void:
	var panel: VenuePanel = add_panel("index", "Your Build", {
		"console_order": 10, "console_min": 190.0,
	})
	var content: VBoxContainer = panel.content()

	_kicker = ConsoleStyle.label(
		"PERKS, LOADOUT AND PIPELINES", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	content.add_child(_kicker)

	_index_lines = VBoxContainer.new()
	_index_lines.add_theme_constant_override("separation", 2)
	content.add_child(_index_lines)

	content.add_child(ConsoleStyle.rule(0.22))

	_counters = VBoxContainer.new()
	_counters.add_theme_constant_override("separation", 0)
	_counters.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_counters)

	_workflow_rule = ConsoleStyle.rule(0.22)
	content.add_child(_workflow_rule)

	_workflow_row = ConsoleMenuRow.new()
	_workflow_row.index_label = "W"
	_workflow_row.headline = "WORKFLOWS"
	_workflow_row.pressed.connect(_on_workflows_pressed)
	content.add_child(_workflow_row)

	_painted_back_rule = ConsoleStyle.rule(0.22)
	content.add_child(_painted_back_rule)

	_painted_back_row = ConsoleMenuRow.new()
	_painted_back_row.index_label = "<"
	_painted_back_row.headline = "BACK TO DESK"
	_painted_back_row.pressed.connect(_on_back)
	content.add_child(_painted_back_row)


func _build_board() -> void:
	_board_panel = add_panel("board", "Fitted", {
		"console_order": 20, "console_min": 220.0, "grow": true,
	})
	_board = VenueBoard.new()
	_board.tile_action.connect(_on_perk_action)
	_board_panel.content().add_child(_board)


## The card on the cabinet, carrying the one thing about a loadout that is not a
## property of any single perk in it: which combinations the run has accidentally
## assembled.
func _build_notice() -> void:
	var panel: VenuePanel = add_panel("notice", "", {
		"console_order": 40, "console_min": 70.0,
	})
	_notice = ConsoleStyle.paragraph("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.content().add_child(_notice)


## A phone has no W key, and the photographed index is an unusually narrow,
## projectively mapped surface. Keep the same route available in room chrome so
## it cannot disappear below the close-up or become unreachable through the
## surface input mapping. Hidden on desktop and in console mode, where the normal
## row is already directly usable.
func _build_workflow_chrome() -> void:
	_workflow_chrome = Button.new()
	_workflow_chrome.name = "WorkflowChrome"
	_workflow_chrome.text = "WORKFLOWS  ►"
	_workflow_chrome.flat = true
	_workflow_chrome.focus_mode = Control.FOCUS_NONE
	_workflow_chrome.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_workflow_chrome.visible = false
	_workflow_chrome.pressed.connect(_on_workflows_pressed)
	add_child(_workflow_chrome)


# --- Refresh -----------------------------------------------------------------

func refresh() -> void:
	if _board == null:
		return
	var racks: Dictionary = _racks()
	if Array(racks.get(_rack, [])).is_empty():
		_rack = ACTIVE if not Array(racks[ACTIVE]).is_empty() else BENCH
	_refresh_index()
	_refresh_counters(racks)
	_refresh_workflows_door()
	_refresh_board(racks)
	_refresh_notice()


func _racks() -> Dictionary:
	var active: Array = Array(Simulation.run_state.build.get("perks", []))
	var benched: Array = []
	for perk_id in Array(Simulation.run_state.build.get("perk_inventory", [])):
		if not (perk_id in active):
			benched.append(str(perk_id))
	return {ACTIVE: active, BENCH: benched}


func _refresh_index() -> void:
	for child in _index_lines.get_children():
		_index_lines.remove_child(child)
		child.queue_free()
	var capacity: Dictionary = Simulation.perk_capacity()
	var lines: Array = [
		{
			"stat": "Slots",
			"value": "%d / %d" % [int(capacity.get("active", 0)), int(capacity.get("cap", 0))],
		},
		{
			"stat": "Collected",
			"value": "%d" % Array(
				Simulation.run_state.build.get("perk_inventory", [])
			).size(),
		},
		{"stat": "Token rate", "value": "×%.1f" % _token_rate_multiplier()},
	]
	for entry in lines:
		var line: Control = ConsoleStyle.detail_line(
			entry, ConsoleMetrics.font_small(console_scale())
		)
		if line != null:
			_index_lines.add_child(line)


func _refresh_counters(racks: Dictionary) -> void:
	var wanted: Array[String] = [ACTIVE, BENCH]
	if wanted != _counter_order():
		for child in _counters.get_children():
			_counters.remove_child(child)
			child.queue_free()
		_counter_rows.clear()
		var index: int = 1
		for key in wanted:
			var row := ConsoleMenuRow.new()
			row.index_label = str(index)
			row.headline = _counter_label(key)
			row.pressed.connect(_on_counter_pressed.bind(key))
			_counters.add_child(row)
			_counter_rows[key] = row
			index += 1
	for key in _counter_rows:
		var row: ConsoleMenuRow = _counter_rows[key]
		row.value_text = "%d" % Array(racks.get(key, [])).size()
		row.set_selected(str(key) == _rack)
	_layout_counter_rows()


func _counter_order() -> Array[String]:
	var keys: Array[String] = []
	for child in _counters.get_children():
		for key in _counter_rows:
			if _counter_rows[key] == child:
				keys.append(str(key))
	return keys


func _counter_label(key: String) -> String:
	return "ON THE BENCH" if key == BENCH else "FITTED"


func _on_counter_pressed(key: String) -> void:
	if _rack == key:
		return
	_rack = key
	_board.clear_selection()
	refresh()
	lean_on("board")


## A door, not a rack: the pipelines live in their own room, and this is how
## the workshop sends you there. Hidden between runs, because there is nothing
## to wire until one has started.
func _refresh_workflows_door() -> void:
	if _workflow_row == null:
		return
	var in_run: bool = Simulation.phase != Simulation.Phase.IDLE
	_workflow_row.visible = in_run
	if _workflow_rule != null:
		_workflow_rule.visible = in_run
	if in_run:
		_workflow_row.value_text = "%d / %d" % [
			Simulation.workflow_count(), Simulation.workflow_capacity(),
		]
	_layout_workflow_row()
	_layout_workflow_chrome()


func _on_workflows_pressed() -> void:
	if Simulation.phase == Simulation.Phase.IDLE:
		return
	SceneRouter.open_workflows()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if SceneRouter.investor_busy():
		return
	if event.keycode == KEY_W:
		_on_workflows_pressed()
		get_viewport().set_input_as_handled()
		return
	var slot: int = event.keycode - KEY_1
	var order: Array[String] = _counter_order()
	if slot < 0 or slot >= order.size():
		return
	_on_counter_pressed(order[slot])
	get_viewport().set_input_as_handled()


func _refresh_board(racks: Dictionary) -> void:
	_board_panel.set_heading(_counter_label(_rack).capitalize())
	var fitted: bool = _rack == ACTIVE
	var entries: Array = []
	for perk_id in Array(racks.get(_rack, [])):
		var entry: Dictionary = _perk_entry(str(perk_id), fitted)
		if not entry.is_empty():
			entries.append(entry)
	var note: String = ""
	if entries.is_empty():
		note = (
			"NOTHING FITTED — WIN A ROUND AND THE ANGELS WILL OFFER SOMETHING"
			if fitted else "BENCH EMPTY — EVERYTHING YOU OWN IS IN"
		)
	_board.set_entries(entries, note)


## The synergies the loadout has assembled, which is the only reason to fit two
## perks that are individually worse than a third.
func _refresh_notice() -> void:
	var entries: Array[Dictionary] = _active_synergy_entries()
	if entries.is_empty():
		_notice.text = "NO SYNERGIES RECOGNISED YET"
		_notice.add_theme_color_override("font_color", ConsoleStyle.PHOSPHOR_DIM)
		return
	var names: PackedStringArray = []
	for entry in entries:
		names.append(str(entry.get("name", "Synergy")).to_upper())
	_notice.text = "%d SYNERGY(S)\n%s" % [entries.size(), " · ".join(names)]
	_notice.add_theme_color_override("font_color", ConsoleStyle.PHOSPHOR)


# --- Tiles -------------------------------------------------------------------

## A perk as a card: what it is, how rare it is set large and in its own colour
## because rarity is how a draft is read, what it tags into, and whether it can
## move — which for a benched perk is the whole question.
func _perk_entry(perk_id: String, fitted: bool) -> Dictionary:
	var perk: PerkDefinition = ContentDatabase.get_perk(perk_id)
	if perk == null:
		return {}
	var enabled: bool = (
		Simulation.can_bench_perk(perk_id) if fitted
		else Simulation.can_equip_perk(perk_id)
	)
	var blocked_reason: String = (
		Simulation.perk_bench_block_reason(perk_id) if fitted
		else Simulation.perk_equip_block_reason(perk_id)
	)
	return {
		"meta": perk_id,
		"name": perk.name,
		"figure": perk.rarity.to_upper(),
		"figure_color": AssetCatalog.rarity_color(perk.rarity),
		"unit": "",
		"spec": Simulation.get_perk_description(perk_id),
		"price": ", ".join(perk.tags) if perk.tags.size() > 0 else "",
		"price_color": ConsoleStyle.PHOSPHOR_DIM,
		"status": _perk_status(perk_id, fitted),
		"status_color": _perk_status_color(perk_id, fitted),
		"tooltip": Simulation.get_perk_description(perk_id),
		"action_text": "UNEQUIP" if fitted else "EQUIP",
		"action_enabled": enabled,
		"action_warning": fitted,
		"action_tooltip": "" if enabled else blocked_reason,
	}


## What the card says about moving. A fitted perk that cannot leave says so rather
## than the player pressing BENCH and nothing happening; a benched one that has no
## room names the swap that would make room.
func _perk_status(perk_id: String, fitted: bool) -> String:
	if fitted:
		var blocked: String = Simulation.perk_bench_block_reason(perk_id)
		return blocked if blocked != "" else "FITTED"
	if Simulation.can_equip_perk(perk_id):
		return "READY TO FIT"
	return Simulation.perk_equip_block_reason(perk_id)


func _perk_status_color(perk_id: String, fitted: bool) -> Color:
	if fitted:
		return ConsoleStyle.PHOSPHOR_DIM
	if Simulation.can_equip_perk(perk_id):
		return ConsoleStyle.PHOSPHOR
	return ConsoleStyle.PHOSPHOR_DIM


# --- Actions -----------------------------------------------------------------

func _on_perk_action(meta: Variant) -> void:
	var perk_id: String = str(meta)
	if perk_id == "":
		return
	var active: bool = perk_id in Array(Simulation.run_state.build.get("perks", []))
	var changed: bool = (
		Simulation.bench_perk(perk_id) if active
		else Simulation.equip_perk(perk_id)
	)
	if not changed:
		return
	_board.clear_selection()
	refresh()
	get_tree().call_group("ui_refresh", "refresh")


func _active_synergy_entries() -> Array[Dictionary]:
	var owned: Array = Array(Simulation.run_state.build.get("perks", []))
	var entries: Array[Dictionary] = []
	for synergy in ContentDatabase.synergies:
		if not synergy is Dictionary:
			continue
		var required: Array = Array(Dictionary(synergy).get("perks", []))
		var has_all: bool = true
		for req in required:
			if not (str(req) in owned):
				has_all = false
				break
		if not has_all:
			continue
		var perk_names: PackedStringArray = []
		for req in required:
			var req_perk: PerkDefinition = ContentDatabase.get_perk(str(req))
			if req_perk != null:
				perk_names.append(req_perk.name)
		entries.append({
			"name": str(Dictionary(synergy).get("name", "Synergy")),
			"perks": " + ".join(perk_names),
		})
	return entries


## What the fitted perks are worth, as a multiple of what the same hardware would
## do with an empty loadout.
func _token_rate_multiplier() -> float:
	var compute: Dictionary = Simulation.run_state.compute
	var base_rate: float = _hardware_token_rate() * float(compute.get("efficiency", 1.0))
	if base_rate <= 0.0:
		return 1.0
	return float(compute.get("token_rate", 0.0)) / base_rate


func _hardware_token_rate() -> float:
	var total: float = 0.0
	var curves: Dictionary = ContentDatabase.balance.get("hardware_curves", {})
	for hardware_id in Array(Simulation.run_state.build.get("hardware", [])):
		var hardware: Dictionary = Dictionary(curves.get(str(hardware_id), {}))
		total += float(hardware.get("token_rate", 0.0))
	return total


# --- Layout ------------------------------------------------------------------

func _on_venue_layout() -> void:
	var scale: float = console_scale()
	if _board != null:
		_board.set_console(console_mode())
		_board.set_metrics(scale, content_width("board"))
	_layout_counter_rows()
	_layout_workflow_row()
	_layout_workflow_chrome()
	_layout_painted_back_row()
	var font_tiny: int = ConsoleMetrics.font_tiny(scale)
	if _kicker != null:
		_kicker.add_theme_font_size_override("font_size", font_tiny)
	if _notice != null:
		_notice.add_theme_font_size_override("font_size", font_tiny)
	for line in _index_lines.get_children():
		_apply_line_font(line, ConsoleMetrics.font_small(scale))


func _apply_line_font(line: Node, font_size: int) -> void:
	if line is Label:
		line.add_theme_font_size_override("font_size", font_size)
		return
	for child in line.get_children():
		_apply_line_font(child, font_size)


func _layout_counter_rows() -> void:
	var scale: float = console_scale()
	var font: int = ConsoleMetrics.font_small(scale)
	var height: int = ConsoleMetrics.row_height(scale)
	var pad: int = ConsoleMetrics.pad_h(scale)
	for key in _counter_rows:
		(_counter_rows[key] as ConsoleMenuRow).set_metrics(font, height, pad)


func _layout_workflow_row() -> void:
	if _workflow_row == null:
		return
	var scale: float = console_scale()
	_workflow_row.set_metrics(
		ConsoleMetrics.font_small(scale),
		ConsoleMetrics.row_height(scale),
		ConsoleMetrics.pad_h(scale)
	)


func _layout_workflow_chrome() -> void:
	if _workflow_chrome == null:
		return
	var in_run: bool = Simulation.phase != Simulation.Phase.IDLE
	_workflow_chrome.visible = _room_mode and in_run
	if not _workflow_chrome.visible:
		return
	_workflow_chrome.add_theme_font_override("font", UiThemeBuilder.mono_font())
	_workflow_chrome.add_theme_font_size_override(
		"font_size", ConsoleMetrics.font_body(_scale)
	)
	var pad: float = float(ConsoleMetrics.pad_h(_scale))
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.02, 0.05, 0.04, 0.96 if state == "hover" else 0.86)
		box.border_color = Color(
			ConsoleStyle.PHOSPHOR.r,
			ConsoleStyle.PHOSPHOR.g,
			ConsoleStyle.PHOSPHOR.b,
			0.45
		)
		box.set_border_width_all(1)
		box.content_margin_left = pad
		box.content_margin_right = pad
		box.content_margin_top = pad * 0.6
		box.content_margin_bottom = pad * 0.6
		_workflow_chrome.add_theme_stylebox_override(state, box)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		_workflow_chrome.add_theme_color_override(state, ConsoleStyle.PHOSPHOR)
	_workflow_chrome.reset_size()
	_workflow_chrome.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	_workflow_chrome.offset_left = EDGE_PAD
	_workflow_chrome.offset_right = _workflow_chrome.size.x + EDGE_PAD
	_workflow_chrome.offset_bottom = -EDGE_PAD
	_workflow_chrome.offset_top = -_workflow_chrome.size.y - EDGE_PAD


func _layout_painted_back_row() -> void:
	if _painted_back_row == null:
		return
	var painted: bool = not console_mode()
	_painted_back_row.visible = painted
	if _painted_back_rule != null:
		_painted_back_rule.visible = painted
	var scale: float = console_scale()
	_painted_back_row.set_metrics(
		ConsoleMetrics.font_small(scale),
		ConsoleMetrics.row_height(scale),
		ConsoleMetrics.pad_h(scale)
	)