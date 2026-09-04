class_name TabContracts
extends CabinetTab

## The job board on the glass: the offers on the wire as a row of paper tags,
## the contracts already on the slate behind a second tab, and the brief of
## whichever one is picked printed beside them. The big red button is ACCEPT.

const WIRE := "wire"
const SLATE := "slate"

var _shelf: String = WIRE
var _selected: String = ""
var _strip: HBoxContainer = null
var _shelf_buttons: Dictionary = {}
var _take_all: Button = null
var _cards_row: HBoxContainer = null
var _scroll: ScrollContainer = null
var _title: Label = null
var _kicker: Label = null
var _rows: VBoxContainer = null
var _summary: VBoxContainer = null
var _empty: Label = null
var _round_cost: float = 1.0


func tab_key() -> String:
	return "contracts"


func _ready() -> void:
	super._ready()
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_theme_constant_override("separation", 3)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	_strip = make_strip()
	column.add_child(_strip)
	for key in [WIRE, SLATE]:
		var button: Button = CabinetStyle.tab("ON THE WIRE" if key == WIRE else "ON THE SLATE")
		button.add_theme_font_size_override("font_size", CabinetStyle.FONT_TINY)
		button.pressed.connect(_on_shelf.bind(key))
		_strip.add_child(button)
		_shelf_buttons[key] = button
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(spacer)
	_take_all = CabinetStyle.key("TAKE ALL THAT FIT", CabinetStyle.PHOSPHOR, CabinetStyle.FONT_TINY)
	_take_all.pressed.connect(_on_take_all)
	_strip.add_child(_take_all)

	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var browser := PanelContainer.new()
	browser.mouse_filter = Control.MOUSE_FILTER_PASS
	browser.add_theme_stylebox_override("panel", CabinetStyle.frame(CabinetStyle.AMBER, 0.3, 0.02))
	browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browser.size_flags_stretch_ratio = 1.55
	body.add_child(browser)
	_scroll = ScrollContainer.new()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	browser.add_child(_scroll)
	_cards_row = HBoxContainer.new()
	_cards_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_cards_row.add_theme_constant_override("separation", 6)
	_cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_cards_row)
	_empty = CabinetStyle.mono("", CabinetStyle.FONT_SMALL, CabinetStyle.PHOSPHOR_DIM)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	browser.add_child(_empty)

	var detail := VBoxContainer.new()
	detail.mouse_filter = Control.MOUSE_FILTER_PASS
	detail.add_theme_constant_override("separation", 2)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_stretch_ratio = 1.0
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
	_summary = VBoxContainer.new()
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary.add_theme_constant_override("separation", 0)
	detail.add_child(_summary)


func activated() -> void:
	if Simulation.phase == Simulation.Phase.ROUND_PREP:
		Simulation.ensure_job_offers()
	super.activated()


func refresh() -> void:
	var costs: Dictionary = Simulation.cost_forecast()
	_round_cost = maxf(1.0, float(costs.get("fixed_due", 0.0)))
	var shelves: Dictionary = _shelves()
	for key in _shelf_buttons:
		var button: Button = _shelf_buttons[key]
		button.text = "%s  %d" % ["ON THE WIRE" if key == WIRE else "ON THE SLATE", Array(shelves[key]).size()]
		CabinetStyle.set_tab_active(button, key == _shelf)
	var open: int = 0
	for job in Array(shelves[WIRE]):
		if _can_accept(str(Dictionary(job).get("id", ""))):
			open += 1
	_take_all.visible = _shelf == WIRE
	_take_all.disabled = open <= 0
	_rebuild_cards(Array(shelves[_shelf]))
	_refresh_detail()


func _shelves() -> Dictionary:
	var state := Simulation.run_state
	return {
		WIRE: Array(state.business.get("job_offers", [])),
		SLATE: Array(state.business.get("job_queue", [])) + Array(state.business.get("active_jobs", [])),
	}


func _rebuild_cards(jobs: Array) -> void:
	for child in _cards_row.get_children():
		_cards_row.remove_child(child)
		child.queue_free()
	var ids: Array[String] = []
	for job in jobs:
		ids.append(str(Dictionary(job).get("id", "")))
	if not (_selected in ids):
		_selected = ids[0] if not ids.is_empty() else ""
	var height: float = shelf_card_height(_scroll, 120.0)
	for job in jobs:
		var card := ContractCard.new()
		card.compact = true
		card.custom_minimum_size = Vector2(height * 0.6, height)
		var id: String = str(Dictionary(job).get("id", ""))
		card.pressed.connect(_on_card.bind(id))
		_cards_row.add_child(card)
		card.set_job(job)
		card.set_selected(id == _selected)
	_empty.visible = jobs.is_empty()
	_empty.text = _empty_line()


func _empty_line() -> String:
	if _shelf == SLATE:
		return "NOTHING ON THE SLATE — TAKE A CONTRACT FROM THE WIRE"
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		return "AWAITING UPGRADE — CONTRACTS RESUME AFTER"
	if Simulation.is_work_running():
		return "ROUND UNDER WAY — NEW OFFERS BETWEEN ROUNDS"
	return "NO CONTRACTS ON THE WIRE — FINISH THE ROUND"


func _selected_job() -> Dictionary:
	for job in Array(_shelves()[_shelf]):
		if str(Dictionary(job).get("id", "")) == _selected:
			return job
	return {}


func _refresh_detail() -> void:
	var job: Dictionary = _selected_job()
	if job.is_empty():
		_title.text = "—"
		_kicker.text = ""
		detail_rows(_rows, [])
		detail_rows(_summary, [])
		return
	var identity: Dictionary = JobPresentation.sector(job)
	_title.text = str(job.get("name", "Contract")).to_upper()
	_kicker.text = "%s · %s" % [str(identity["label"]).to_upper(), str(identity["client"]).to_upper()]
	var rows: Array = []
	if str(job.get("description", "")) != "":
		rows.append({"text": str(job.get("description", ""))})
	var demands: Array = JobPresentation.demands(job)
	if not demands.is_empty():
		rows.append({"text": "REQUIREMENTS"})
		for demand in Simulation.job_demands(job):
			rows.append({
				"rule": "%s %s" % ["[x]" if bool(demand.get("met", false)) else "[ ]", str(demand.get("name", "Demand"))],
				"text": str(demand.get("note", demand.get("requirement", ""))),
				"role": "success" if bool(demand.get("met", false)) else "warning",
			})
	rows.append_array(JobPresentation.rules(job))
	for warning in _capacity_warnings(job):
		rows.append({"warn": warning})
	detail_rows(_rows, rows)
	var risk: String = JobSystem.production_risk_class(job)
	var threshold: float = float(job.get("quality_threshold", 0.0))
	var summary: Array = [
		{"stat": "Reward", "value": NumberFormat.format_cash(float(job.get("reward", 0.0))), "role": "money"},
		{"stat": "Pays for", "value": "%.1f rounds of bills" % (float(job.get("reward", 0.0)) / _round_cost)},
		{"stat": "Tokens", "value": "%s BT" % NumberFormat.format(float(job.get("token_requirement", 0.0)))},
		{"stat": "Deadline", "value": "%d prompts" % int(job.get("deadline_prompts", 0))},
		{"stat": "Quality bar", "value": "%s / 10" % JobPresentation.quality_mark(threshold) if threshold > 0.0 else "unmarked"},
		{"stat": "Risk tier", "value": risk, "color": CabinetStyle.risk_color(risk)},
	]
	var status: String = _status_line(job)
	summary.append({"stat": "Status", "value": status, "color": CabinetStyle.PHOSPHOR if status == "OPEN" else CabinetStyle.PHOSPHOR_DIM})
	detail_rows(_summary, summary)


func _status_line(job: Dictionary) -> String:
	if _shelf == SLATE:
		return "TAKEN"
	var id: String = str(job.get("id", ""))
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		return "UPGRADE FIRST"
	if _can_accept(id):
		return "OPEN"
	if Simulation.is_work_running():
		return "BUSY"
	return "AT CAPACITY"


func _capacity_warnings(offer: Dictionary) -> Array:
	if _shelf != WIRE or Array(Simulation.run_state.business.get("job_queue", [])).is_empty():
		return []
	var info: Dictionary = Simulation.queue_load_info(offer)
	var ratio: float = float(info.get("ratio", 0.0))
	if ratio <= 1.0:
		return []
	if ratio > float(info.get("cap", 2.0)):
		return ["Queue full — this will not fit in the round"]
	return ["Queue at %.0f%% capacity" % (ratio * 100.0)]


func _can_accept(offer_id: String) -> bool:
	if offer_id == "":
		return false
	if Simulation.phase != Simulation.Phase.ROUND_PREP or Simulation.is_work_running():
		return false
	return Simulation.can_accept_offer(offer_id)


func primary_action() -> Dictionary:
	var job: Dictionary = _selected_job()
	if _shelf == SLATE or job.is_empty():
		return {"label": "ACCEPT", "enabled": false, "sub": "pick a contract on the wire" if job.is_empty() else "already on the slate", "pressed": Callable()}
	var id: String = str(job.get("id", ""))
	var can: bool = _can_accept(id)
	var sub: String = NumberFormat.format_cash(float(job.get("reward", 0.0))) if can else _status_line(job).to_lower()
	return {"label": "ACCEPT", "enabled": can, "sub": sub, "pressed": _accept.bind(id)}


func _accept(job_id: String) -> void:
	if not _can_accept(job_id):
		return
	UiSound.play("accept")
	if Simulation.accept_job(job_id):
		refresh()
		changed.emit()
		get_tree().call_group("ui_refresh", "refresh")


func _on_take_all() -> void:
	var ids: Array[String] = []
	for job in Array(Simulation.run_state.business.get("job_offers", [])):
		ids.append(str(Dictionary(job).get("id", "")))
	var taken: int = 0
	for job_id in ids:
		if _can_accept(job_id) and Simulation.accept_job(job_id):
			taken += 1
	if taken <= 0:
		return
	UiSound.play("accept")
	refresh()
	changed.emit()
	get_tree().call_group("ui_refresh", "refresh")


func _on_shelf(key: String) -> void:
	if _shelf == key:
		return
	UiSound.play("tap")
	_shelf = key
	_selected = ""
	refresh()
	changed.emit()


func _on_card(id: String) -> void:
	UiSound.play("tap")
	_selected = id
	for card in _cards_row.get_children():
		if card is ContractCard:
			card.set_selected(str(card.job().get("id", "")) == id)
	_refresh_detail()
	changed.emit()
