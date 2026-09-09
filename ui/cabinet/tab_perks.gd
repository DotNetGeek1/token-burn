class_name TabPerks
extends CabinetTab

## The perk rack on the glass: every perk the run owns and the combos they are
## producing. Perks are permanent — the investor deals one per chapter and it
## stays fitted for the rest of the run — so this tab is a read-only reference
## and the big red button has nothing to commit while it is up.

## The commit button's line while this tab is up: there is nothing to press.
const BLOCK_PERKS_FIXED := "PERKS ARE PERMANENT"

var _selected: String = ""
var _capacity: Label = null
var _owned: VBoxContainer = null
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

	_owned = _rack(body, "OWNED")

	var detail := VBoxContainer.new()
	detail.mouse_filter = Control.MOUSE_FILTER_PASS
	detail.add_theme_constant_override("separation", 2)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_stretch_ratio = 1.4
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


func _owned_ids() -> Array:
	return Simulation.owned_perk_ids()


func refresh() -> void:
	var scrolls: Dictionary = capture_scroll(self)
	_refresh_contents()
	restore_scroll(self, scrolls)


func selected_id() -> String:
	return _selected


## Picks an owned perk by id. Returns false when the run does not own it.
func select_perk(perk_id: String) -> bool:
	if not (perk_id in _owned_ids()):
		return false
	_pick(perk_id)
	return true


func _refresh_contents() -> void:
	var owned: Array = _owned_ids()
	_capacity.text = "%d OWNED · PERMANENT" % owned.size()
	if not (_selected in owned):
		_selected = str(owned[0]) if not owned.is_empty() else ""
	_fill(_owned, owned)
	_refresh_detail()


func _fill(list: VBoxContainer, ids: Array) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	if ids.is_empty():
		var empty: Label = CabinetStyle.mono("NOTHING OWNED YET", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
		return
	for raw in ids:
		var perk_id: String = str(raw)
		var perk: PerkDefinition = ContentDatabase.get_perk(perk_id)
		if perk == null:
			continue
		var tile := CabinetTile.new()
		tile.set_entry({
			"meta": perk_id,
			"name": perk.name.to_upper(),
			"sub": perk.rarity.to_upper(),
			"figure": "",
			"status": "LIVE",
			"status_color": CabinetStyle.PHOSPHOR,
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
		detail_rows(_rows, [{
			"text": "Perks are dealt by the investor when a chapter's goal is met. Each one is permanent: it stays fitted for the rest of the run.",
		}])
	else:
		_title.text = perk.name.to_upper()
		_kicker.text = "%s · PERMANENT" % perk.rarity.to_upper()
		_kicker.add_theme_color_override("font_color", AssetCatalog.rarity_color(perk.rarity))
		var rows: Array = [{"text": Simulation.get_perk_description(_selected)}]
		if not perk.tags.is_empty():
			rows.append({"stat": "Tags", "value": ", ".join(perk.tags).to_upper()})
		detail_rows(_rows, rows)
	var synergies: Array = []
	for line in Simulation.get_synergies():
		synergies.append({"text": str(line), "role": "success"})
	if synergies.is_empty():
		synergies.append({"text": "No live combos yet."})
	detail_rows(_synergies, synergies)


## Nothing to commit here: perks cannot be fitted, benched or swapped. The
## button explains itself rather than going blank.
func primary_action() -> Dictionary:
	return blocked_action("PERMANENT", BLOCK_PERKS_FIXED)


func _pick(perk_id: String) -> void:
	UiSound.play("tap")
	_selected = perk_id
	for child in _owned.get_children():
		if child is CabinetTile:
			child.set_selected(str(child.meta) == perk_id)
	_refresh_detail()
	changed.emit()
