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
var _board_panel: VenuePanel = null
var _board: VenueBoard = null
var _signage_panel: VenuePanel = null
var _sign: VBoxContainer = null
var _detail: ConsoleDetail = null
var _notice: Label = null
var _counter_rows: Dictionary = {}
var _rack: String = ACTIVE
var _selected: String = ""
var _selected_active: bool = true
## The fitted perk the selected bench perk would replace, set when the sheet is
## drawn so the action and its handler always mean the same swap.
var _swap_target: String = ""


func venue_key() -> String:
	return "build"


func _hint_entries() -> Array:
	return [{"index": "ENTER", "headline": "FIT"}]


func _build_venue() -> void:
	_build_index()
	_build_board()
	_build_signage()
	_build_notice()
	EventBus.perk_acquired.connect(func(_id: String) -> void: refresh())
	EventBus.run_started.connect(refresh)


func _build_index() -> void:
	var panel: VenuePanel = add_panel("index", "Your Build", {
		"console_order": 10, "console_min": 190.0,
	})
	var content: VBoxContainer = panel.content()

	_kicker = ConsoleStyle.label(
		"PERKS AND LOADOUT", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
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


func _build_board() -> void:
	_board_panel = add_panel("board", "Fitted", {
		"console_order": 20, "console_min": 220.0, "grow": true,
	})
	_board = VenueBoard.new()
	_board.tile_selected.connect(_on_tile_selected)
	_board_panel.content().add_child(_board)


func _build_signage() -> void:
	_signage_panel = add_panel("signage", "", {
		"console_order": 30, "console_min": 0.0,
	})
	var content: VBoxContainer = _signage_panel.content()

	_sign = VBoxContainer.new()
	_sign.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sign.add_theme_constant_override("separation", 8)
	content.add_child(_sign)
	for line in ["FIT WHAT", "THE RUN NEEDS"]:
		var label: Label = ConsoleStyle.label(
			line, ConsoleStyle.FONT_BODY, ConsoleStyle.PHOSPHOR_DIM
		)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_sign.add_child(label)

	_detail = ConsoleDetail.new()
	_detail.visible = false
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.action_pressed.connect(_on_detail_action)
	_detail.closed.connect(_on_detail_closed)
	content.add_child(_detail)


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


# --- Refresh -----------------------------------------------------------------

func refresh() -> void:
	if _board == null:
		return
	var racks: Dictionary = _racks()
	if Array(racks.get(_rack, [])).is_empty():
		_rack = ACTIVE if not Array(racks[ACTIVE]).is_empty() else BENCH
	_refresh_index()
	_refresh_counters(racks)
	_refresh_board(racks)
	_refresh_notice()
	_refresh_detail()


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
	var liability: float = float(
		Simulation.run_state.economy.get("cloud_surcharge_liability", 0.0)
	)
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
	if liability > 0.0:
		lines.append({
			"stat": "Cloud owed",
			"value": NumberFormat.format_cash(liability),
			"color": ConsoleStyle.WARNING,
		})
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
	_selected = ""
	_board.clear_selection()
	refresh()
	lean_on("board")


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if SceneRouter.investor_busy():
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if _selected != "":
			_on_detail_action()
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
	if _selected != "":
		_board.select(_selected)


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
	if _swap_target_for(perk_id) != "":
		return "SWAP AVAILABLE"
	return Simulation.perk_equip_block_reason(perk_id)


func _perk_status_color(perk_id: String, fitted: bool) -> Color:
	if fitted:
		return ConsoleStyle.PHOSPHOR_DIM
	if Simulation.can_equip_perk(perk_id) or _swap_target_for(perk_id) != "":
		return ConsoleStyle.PHOSPHOR
	return ConsoleStyle.PHOSPHOR_DIM


# --- The sheet ---------------------------------------------------------------

func _on_tile_selected(meta: Variant) -> void:
	_selected = str(meta) if meta != null else ""
	_selected_active = _selected in Array(Simulation.run_state.build.get("perks", []))
	_refresh_detail()


func _on_detail_closed() -> void:
	_selected = ""
	_board.clear_selection()
	_refresh_detail()


func _refresh_detail() -> void:
	var perk: PerkDefinition = ContentDatabase.get_perk(_selected)
	var reading: bool = perk != null
	_sign.visible = not reading
	_detail.visible = reading
	_signage_panel.set_heading("" if not reading else "The perk")
	if not reading:
		return
	var lines: Array = [
		{"text": Simulation.get_perk_description(_selected)},
		{"stat": "Rarity", "value": perk.rarity.capitalize()},
	]
	if perk.tags.size() > 0:
		lines.append({"stat": "Tags", "value": ", ".join(perk.tags)})
	var action: String = ""
	var enabled: bool = false
	_swap_target = ""
	if _selected_active:
		var bench_reason: String = Simulation.perk_bench_block_reason(_selected)
		lines.append({
			"stat": "Status",
			"value": "Fitted" if bench_reason == "" else "Fitted · %s" % bench_reason,
		})
		action = "[ ENTER ] BENCH IT"
		enabled = bench_reason == ""
	else:
		var equip_reason: String = Simulation.perk_equip_block_reason(_selected)
		lines.append({
			"stat": "Fit",
			"value": "Ready" if Simulation.can_equip_perk(_selected) else equip_reason,
		})
		if Simulation.can_equip_perk(_selected):
			action = "[ ENTER ] FIT IT"
			enabled = true
		else:
			# Nothing else can free a slot for this perk, so the sheet offers the
			# swap it would have to make rather than a dead FIT line.
			_swap_target = _swap_target_for(_selected)
			if _swap_target != "":
				var outgoing: PerkDefinition = ContentDatabase.get_perk(_swap_target)
				var outgoing_name: String = (
					outgoing.name if outgoing != null else _swap_target
				)
				lines.append({"stat": "Swap out", "value": outgoing_name})
				action = "[ ENTER ] SWAP FOR %s" % outgoing_name.to_upper()
				enabled = true
			else:
				action = "[ -- ] NO ROOM"
				enabled = false
	_detail.show_detail(perk.name.to_upper(), lines, action, enabled)


## The fitted perk this one could replace. Only offered when exactly one clears
## the way, so a swap is never a guess about which one the player meant to give
## up.
func _swap_target_for(perk_id: String) -> String:
	var candidates: Array = []
	for active_id in Array(Simulation.run_state.build.get("perks", [])):
		if Simulation.can_swap_perk(str(active_id), perk_id):
			candidates.append(str(active_id))
		if candidates.size() > 1:
			return ""
	return str(candidates[0]) if candidates.size() == 1 else ""


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
	var base_rate: float = (
		_hardware_token_rate() + float(compute.get("cloud_capacity", 0.0))
	) * float(compute.get("efficiency", 1.0))
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


# --- Actions -----------------------------------------------------------------

func _on_detail_action() -> void:
	if _selected == "":
		return
	if _selected_active:
		if Simulation.bench_perk(_selected):
			_selected = ""
	elif _swap_target != "":
		if Simulation.swap_perk(_swap_target, _selected):
			_selected_active = true
		_swap_target = ""
	elif Simulation.equip_perk(_selected):
		_selected_active = true
	_board.clear_selection()
	refresh()
	get_tree().call_group("ui_refresh", "refresh")


# --- Layout ------------------------------------------------------------------

func _on_venue_layout() -> void:
	var scale: float = console_scale()
	if _board != null:
		_board.set_console(console_mode())
		_board.set_metrics(scale, content_width("board"))
	if _detail != null:
		_detail.set_metrics(scale)
	_layout_counter_rows()
	var font_tiny: int = ConsoleMetrics.font_tiny(scale)
	if _kicker != null:
		_kicker.add_theme_font_size_override("font_size", font_tiny)
	if _notice != null:
		_notice.add_theme_font_size_override("font_size", font_tiny)
	var font_body: int = ConsoleMetrics.font_body(scale)
	for label in _sign.get_children():
		if label is Label:
			label.add_theme_font_size_override("font_size", font_body)
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
