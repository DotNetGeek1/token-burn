class_name TabPerks
extends CabinetTab

## The perk rack on the glass: what is fitted, what is on the bench, and the
## combos the fitted set is producing. The big red button is FIT for a benched
## perk and BENCH for a fitted one.

var _selected: String = ""
var _capacity: Label = null
var _fitted: VBoxContainer = null
var _bench: VBoxContainer = null
var _title: Label = null
var _kicker: Label = null
var _rows: VBoxContainer = null
var _synergies: VBoxContainer = null


func tab_key() -> String:
	return "perks"


func _ready() -> void:
	super._ready()
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_theme_constant_override("separation", 3)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	var strip: HBoxContainer = make_strip()
	column.add_child(strip)
	var caption: Label = CabinetStyle.caption("PERK RACK")
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.add_child(caption)
	_capacity = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
	_capacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_capacity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.add_child(_capacity)

	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	_fitted = _rack(body, "FITTED")
	_bench = _rack(body, "BENCH")

	var detail := VBoxContainer.new()
	detail.mouse_filter = Control.MOUSE_FILTER_PASS
	detail.add_theme_constant_override("separation", 2)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_stretch_ratio = 1.1
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
	detail.add_child(CabinetStyle.caption("LIVE COMBOS", CabinetStyle.FONT_TINY, CabinetStyle.AMBER_DIM))
	_synergies = VBoxContainer.new()
	_synergies.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_synergies.add_theme_constant_override("separation", 0)
	detail.add_child(_synergies)


func _rack(host: Control, title: String) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	frame.add_theme_stylebox_override("panel", CabinetStyle.frame(CabinetStyle.AMBER, 0.3, 0.02))
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_child(frame)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_theme_constant_override("separation", 2)
	frame.add_child(column)
	column.add_child(CabinetStyle.caption(title, CabinetStyle.FONT_TINY, CabinetStyle.AMBER_DIM))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_PASS
	list.add_theme_constant_override("separation", 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list


func _fitted_ids() -> Array:
	return Array(Simulation.run_state.build.get("perks", []))


func _bench_ids() -> Array:
	var fitted: Array = _fitted_ids()
	var bench: Array = []
	for perk_id in Array(Simulation.run_state.build.get("perk_inventory", [])):
		if not (str(perk_id) in fitted):
			bench.append(str(perk_id))
	return bench


func refresh() -> void:
	var capacity: Dictionary = Simulation.perk_capacity()
	_capacity.text = "%d / %d FITTED · %d ON THE BENCH" % [int(capacity.get("active", 0)), int(capacity.get("cap", 0)), _bench_ids().size()]
	var all: Array = _fitted_ids() + _bench_ids()
	if not (_selected in all):
		_selected = str(all[0]) if not all.is_empty() else ""
	_fill(_fitted, _fitted_ids(), true)
	_fill(_bench, _bench_ids(), false)
	_refresh_detail()


func _fill(list: VBoxContainer, ids: Array, fitted: bool) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	if ids.is_empty():
		var empty: Label = CabinetStyle.mono("NOTHING FITTED" if fitted else "BENCH EMPTY", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
		return
	for raw in ids:
		var perk_id: String = str(raw)
		var perk: PerkDefinition = ContentDatabase.get_perk(perk_id)
		if perk == null:
			continue
		var can: bool = Simulation.can_bench_perk(perk_id) if fitted else Simulation.can_equip_perk(perk_id)
		var reason: String = Simulation.perk_bench_block_reason(perk_id) if fitted else Simulation.perk_equip_block_reason(perk_id)
		var tile := CabinetTile.new()
		tile.set_entry({
			"meta": perk_id,
			"name": perk.name.to_upper(),
			"sub": perk.rarity.to_upper(),
			"figure": "",
			"status": ("LIVE" if fitted else "BENCHED") if can or reason == "" else reason.to_upper(),
			"status_color": CabinetStyle.PHOSPHOR if fitted else CabinetStyle.PHOSPHOR_DIM,
			"icon": AssetCatalog.perk_icon(perk_id),
			"accent": AssetCatalog.rarity_color(perk.rarity),
			"tooltip": Simulation.get_perk_description(perk_id),
		})
		tile.set_selected(perk_id == _selected)
		tile.pressed.connect(func(meta: Variant) -> void: _pick(str(meta)))
		list.add_child(tile)


func _refresh_detail() -> void:
	var perk: PerkDefinition = ContentDatabase.get_perk(_selected) if _selected != "" else null
	if perk == null:
		_title.text = "—"
		_kicker.text = ""
		detail_rows(_rows, [{"text": "Perks arrive from the angels between rounds. Fit them here; the rack has %d slots." % int(Simulation.perk_capacity().get("cap", 0))}])
	else:
		var fitted: bool = _selected in _fitted_ids()
		_title.text = perk.name.to_upper()
		_kicker.text = "%s · %s" % [perk.rarity.to_upper(), "FITTED" if fitted else "ON THE BENCH"]
		_kicker.add_theme_color_override("font_color", AssetCatalog.rarity_color(perk.rarity))
		var rows: Array = [{"text": Simulation.get_perk_description(_selected)}]
		if not perk.tags.is_empty():
			rows.append({"stat": "Tags", "value": ", ".join(perk.tags).to_upper()})
		var reason: String = Simulation.perk_bench_block_reason(_selected) if fitted else Simulation.perk_equip_block_reason(_selected)
		if reason != "":
			rows.append({"warn": reason})
		detail_rows(_rows, rows)
	var synergies: Array = []
	for line in Simulation.get_synergies():
		synergies.append({"text": str(line), "role": "success"})
	if synergies.is_empty():
		synergies.append({"text": "No live combos yet."})
	detail_rows(_synergies, synergies)


func primary_action() -> Dictionary:
	var perk: PerkDefinition = ContentDatabase.get_perk(_selected) if _selected != "" else null
	if perk == null:
		return {"label": "FIT", "enabled": false, "sub": "pick a perk", "pressed": Callable()}
	var fitted: bool = _selected in _fitted_ids()
	if fitted:
		var can: bool = Simulation.can_bench_perk(_selected)
		return {
			"label": "BENCH", "enabled": can,
			"sub": perk.name.to_lower() if can else Simulation.perk_bench_block_reason(_selected).to_lower(),
			"pressed": _toggle.bind(_selected, true),
		}
	var can_fit: bool = Simulation.can_equip_perk(_selected)
	return {
		"label": "FIT", "enabled": can_fit,
		"sub": perk.name.to_lower() if can_fit else Simulation.perk_equip_block_reason(_selected).to_lower(),
		"pressed": _toggle.bind(_selected, false),
	}


func _toggle(perk_id: String, fitted: bool) -> void:
	var ok: bool = Simulation.bench_perk(perk_id) if fitted else Simulation.equip_perk(perk_id)
	if ok:
		UiSound.play("accept")
		shell.call("refresh_all")
		changed.emit()
		get_tree().call_group("ui_refresh", "refresh")
	else:
		UiSound.play("error")


func _pick(perk_id: String) -> void:
	UiSound.play("tap")
	_selected = perk_id
	for list in [_fitted, _bench]:
		for child in list.get_children():
			if child is CabinetTile:
				child.set_selected(str(child.meta) == perk_id)
	_refresh_detail()
	changed.emit()
