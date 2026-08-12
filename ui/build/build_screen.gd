extends Control

## The run's engine, listed the way the machine holds it: the perks in the build
## as a table, the combinations it has recognised printed underneath, and the two
## numbers the whole thing exists to move as readouts along the bottom.

const PERK_SLOT_LIMIT := 5
const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

@onready var frame: ConsoleFrame = $Margin/Frame

var _table: ConsoleTable = null
var _detail: ConsoleDetail = null
var _synergies: VBoxContainer = null
var _readouts: HBoxContainer = null
var _token_panel: ConsolePanel = null
var _cloud_panel: ConsolePanel = null
var _selected: String = ""
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
		{"label": "effect", "weight": 3.0},
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
	var perks: Array = Simulation.run_state.build.get("perks", [])
	frame.set_context("PERKS %d / %d" % [perks.size(), PERK_SLOT_LIMIT])
	_refresh_perks(perks)
	_refresh_synergies()
	_refresh_readouts()
	if _selected == "" or not _table.select_meta(_selected):
		_detail.clear("SELECT A PERK")
	_fit_console()


func _refresh_perks(perks: Array) -> void:
	_table.clear()
	if perks.is_empty():
		_table.add_note("NO PERKS INSTALLED — FINISH CONTRACTS AND PICK ONE")
		return
	var index: int = 1
	for perk_id in perks:
		var perk: PerkDefinition = ContentDatabase.get_perk(str(perk_id))
		if perk == null:
			continue
		_table.add_row([
			"[%02d]" % index,
			perk.name,
			{"text": perk.rarity.to_upper(), "color": AssetCatalog.rarity_color(perk.rarity)},
			{
				"text": Simulation.get_perk_description(str(perk_id)),
				"color": ConsoleStyle.PHOSPHOR_DIM,
			},
		], str(perk_id))
		index += 1


## Recognised combinations, printed rather than boxed: they are something the
## machine noticed about the build, not another thing to press.
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
	for key in perk.parameters.keys():
		lines.append({"stat": str(key), "value": str(perk.parameters[key])})
	_detail.show_detail(perk.name.to_upper(), lines)


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
