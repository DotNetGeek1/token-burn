extends Control

## The run's engine: active perk loadout, benched collection, synergies, and
## equip/bench controls.

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

@onready var frame: ConsoleFrame = $Margin/Frame

var _table: ConsoleTable = null
var _detail: ConsoleDetail = null
var _synergies: VBoxContainer = null
var _readouts: HBoxContainer = null
var _token_panel: ConsolePanel = null
var _cloud_panel: ConsolePanel = null
var _selected: String = ""
var _selected_active: bool = true
## The active perk the selected bench perk would replace, set by the detail
## sheet so the action row and its handler always mean the same swap.
var _swap_target: String = ""
var _console_scale: float = 1.0


func _ready() -> void:
	add_to_group("ui_refresh")
	add_to_group("console_screens")
	frame.setup("Your Build")
	_build_console()
	resized.connect(_fit_console)
	visibility_changed.connect(_on_visibility_changed)
	EventBus.perk_acquired.connect(func(_id): refresh())
	EventBus.run_started.connect(refresh)
	if _detail != null:
		_detail.action_pressed.connect(_on_detail_action)
	refresh()


func _build_console() -> void:
	var content: VBoxContainer = frame.content()

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)

	_table = ConsoleTable.new()
	_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table.row_selected.connect(_on_row_selected)
	column.add_child(_table)
	_table.set_columns([
		{"label": "id", "weight": 0.5},
		{"label": "perk", "weight": 1.8},
		{"label": "rarity", "weight": 0.9},
		{"label": "status", "weight": 2.2},
	])

	_synergies = VBoxContainer.new()
	_synergies.add_theme_constant_override("separation", 2)
	column.add_child(_synergies)

	_detail = ConsoleDetail.new()
	_detail.size_flags_vertical = Control.SIZE_SHRINK_END
	content.add_child(_detail)
	_detail.clear("SELECT A PERK")

	_readouts = HBoxContainer.new()
	_readouts.add_theme_constant_override("separation", 8)
	content.add_child(_readouts)

	_token_panel = ConsolePanel.new()
	_token_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_readouts.add_child(_token_panel)
	_token_panel.setup("TOKEN RATE")

	_cloud_panel = ConsolePanel.new()
	_cloud_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_readouts.add_child(_cloud_panel)
	_cloud_panel.setup("CLOUD LIABILITY")


func fit_console() -> void:
	_fit_console()


func _on_visibility_changed() -> void:
	if visible:
		call_deferred("_fit_console")


func _fit_console() -> void:
	if size.y <= 1.0:
		return
	_console_scale = ConsoleMetrics.compute_scale(size.y, get_viewport_rect().size.x)
	frame.set_metrics(_console_scale)
	if _table != null:
		_table.set_metrics(_console_scale)
	if _detail != null:
		_detail.set_metrics(_console_scale)
	if _token_panel != null:
		_token_panel.set_metrics(_console_scale)
	if _cloud_panel != null:
		_cloud_panel.set_metrics(_console_scale)
	_refresh_synergies()


func refresh() -> void:
	var capacity: Dictionary = Simulation.perk_capacity()
	var active: Array = Simulation.run_state.build.get("perks", [])
	var collected: Array = Simulation.run_state.build.get("perk_inventory", [])
	frame.set_context(
		"ACTIVE %d / %d · COLLECTED %d" % [
			int(capacity.get("active", 0)),
			int(capacity.get("cap", 0)),
			collected.size(),
		]
	)
	_refresh_perks(active, collected)
	_refresh_synergies()
	_refresh_readouts()
	if _selected == "" or not _table.select_meta(_selected):
		_detail.clear("SELECT A PERK")
	else:
		_show_selected_detail()
	_fit_console()


func _refresh_perks(active: Array, collected: Array) -> void:
	_table.clear()
	_table.add_note("ACTIVE %d / %d" % [active.size(), Simulation.perk_capacity().get("cap", 0)])
	if active.is_empty():
		_table.add_note("NO ACTIVE PERKS")
	else:
		var index: int = 1
		for perk_id in active:
			_add_perk_row(perk_id, index, "ACTIVE", true)
			index += 1
	var benched: Array = []
	for perk_id in collected:
		if perk_id not in active:
			benched.append(perk_id)
	_table.add_note("BENCH %d" % benched.size())
	if benched.is_empty():
		_table.add_note("NOTHING ON THE BENCH")
	else:
		var bench_index: int = 1
		for perk_id in benched:
			_add_perk_row(perk_id, bench_index, "BENCH", false)
			bench_index += 1


func _add_perk_row(perk_id: String, index: int, status: String, is_active: bool) -> void:
	var perk: PerkDefinition = ContentDatabase.get_perk(perk_id)
	if perk == null:
		return
	var status_text: String = status
	if is_active:
		# A capacity or workflow perk that cannot leave says so on its own row,
		# rather than the player pressing BENCH and nothing happening.
		var bench_reason: String = Simulation.perk_bench_block_reason(perk_id)
		if bench_reason != "":
			status_text = bench_reason
	elif Simulation.can_equip_perk(perk_id):
		status_text = "READY TO EQUIP"
	else:
		status_text = Simulation.perk_equip_block_reason(perk_id)
		# On a full loadout the way in is a swap, so the row names that instead
		# of only reporting that there is no room.
		if _swap_target_for(perk_id) != "":
			status_text = "%s · SWAP AVAILABLE" % status_text
	_table.add_row([
		"[%02d]" % index,
		perk.name,
		{"text": perk.rarity.to_upper(), "color": AssetCatalog.rarity_color(perk.rarity)},
		{"text": status_text, "color": ConsoleStyle.PHOSPHOR_DIM},
	], perk_id)


func _refresh_synergies() -> void:
	for child in _synergies.get_children():
		_synergies.remove_child(child)
		child.queue_free()
	var entries: Array[Dictionary] = _active_synergy_entries()
	_synergies.add_child(
		ConsoleStyle.label(
			"SYNERGIES",
			ConsoleMetrics.font_tiny(_console_scale),
			ConsoleStyle.PHOSPHOR_DIM
		)
	)
	if entries.is_empty():
		_synergies.add_child(
			ConsoleStyle.label(
				"NONE RECOGNISED YET",
				ConsoleMetrics.font_tiny(_console_scale),
				ConsoleStyle.PHOSPHOR_DIM
			)
		)
		return
	for entry in entries:
		_synergies.add_child(ConsoleStyle.paragraph(
			"+ %s — %s" % [str(entry.get("name", "Synergy")).to_upper(), str(entry.get("perks", ""))],
			ConsoleMetrics.font_small(_console_scale),
			ConsoleStyle.PHOSPHOR
		))


func _refresh_readouts() -> void:
	_token_panel.set_readout("×%.1f" % _token_rate_multiplier(), "against raw hardware")
	_cloud_panel.set_readout(
		NumberFormat.format_cash(
			float(Simulation.run_state.economy.get("cloud_surcharge_liability", 0.0))
		),
		"owed at round end"
	)


func _on_row_selected(meta: Variant) -> void:
	_selected = str(meta) if meta != null else ""
	_selected_active = _selected in Simulation.run_state.build.get("perks", [])
	_show_selected_detail()


func _show_selected_detail() -> void:
	var perk: PerkDefinition = ContentDatabase.get_perk(_selected)
	if perk == null:
		_detail.clear("SELECT A PERK")
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
			"value": "Active" if bench_reason == "" else "Active · %s" % bench_reason,
		})
		action = "BENCH"
		enabled = bench_reason == ""
	else:
		var equip_reason: String = Simulation.perk_equip_block_reason(_selected)
		lines.append({
			"stat": "Equip",
			"value": "Ready" if Simulation.can_equip_perk(_selected) else equip_reason,
		})
		if Simulation.can_equip_perk(_selected):
			action = "EQUIP"
			enabled = true
		else:
			# Nothing else can free a slot for this perk, so the screen offers
			# the swap it would have to make rather than a dead EQUIP line.
			_swap_target = _swap_target_for(_selected)
			if _swap_target != "":
				var outgoing: PerkDefinition = ContentDatabase.get_perk(_swap_target)
				var outgoing_name: String = outgoing.name if outgoing != null else _swap_target
				lines.append({"stat": "Swap out", "value": outgoing_name})
				action = "SWAP FOR %s" % outgoing_name.to_upper()
				enabled = true
			else:
				action = "EQUIP"
				enabled = false
	_detail.show_detail(perk.name.to_upper(), lines, action, enabled)


## The active perk this one could replace. Only offered when exactly one active
## perk clears the way, so a swap is never a guess about which one the player
## meant to give up.
func _swap_target_for(perk_id: String) -> String:
	var candidates: Array = []
	for active_id in Simulation.run_state.build.get("perks", []):
		if Simulation.can_swap_perk(str(active_id), perk_id):
			candidates.append(str(active_id))
		if candidates.size() > 1:
			return ""
	return str(candidates[0]) if candidates.size() == 1 else ""


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
	refresh()
	get_tree().call_group("ui_refresh", "refresh")
	get_tree().call_group("main_ui", "refresh_all")


func _active_synergy_entries() -> Array[Dictionary]:
	var owned: Array = Simulation.run_state.build.get("perks", [])
	var entries: Array[Dictionary] = []
	for synergy in ContentDatabase.synergies:
		if not synergy is Dictionary:
			continue
		var required: Array = synergy.get("perks", [])
		var has_all := true
		for req in required:
			if str(req) not in owned:
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
			"name": str(synergy.get("name", "Synergy")),
			"perks": " + ".join(perk_names),
		})
	return entries


func _token_rate_multiplier() -> float:
	var compute: Dictionary = Simulation.run_state.compute
	var base_rate: float = (_hardware_token_rate() + float(compute.get("cloud_capacity", 0.0))) * float(
		compute.get("efficiency", 1.0)
	)
	if base_rate <= 0.0:
		return 1.0
	return float(compute.get("token_rate", 0.0)) / base_rate


func _hardware_token_rate() -> float:
	var total: float = 0.0
	var curves: Dictionary = ContentDatabase.balance.get("hardware_curves", {})
	for hardware_id in Simulation.run_state.build.get("hardware", []):
		var hw: Dictionary = curves.get(str(hardware_id), {})
		total += float(hw.get("token_rate", 0.0))
	return total
