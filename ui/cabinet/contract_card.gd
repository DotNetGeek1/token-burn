class_name ContractCard
extends Control

## The paper job tag clipped into the cabinet's screen: the contract being
## worked, written on the generated paper card in ink. Everything on it is live
## text over the blank paper so the card reads whatever the run is doing.
##
## Also used, smaller, for the offers on the CONTRACTS tab. `compact` drops the
## progress line and the pager, which only mean something for a contract in hand.

signal pressed
## The lane pager at the foot of the card: the player wants the next contract.
signal page_pressed

## Where the paper sits inside the generated card texture, as fractions of the
## drawn card: the metal frame and the hanging tab are outside this.
const PAPER := Rect2(0.11, 0.075, 0.78, 0.86)

var compact: bool = false
var _paper: TextureRect = null
var _body: VBoxContainer = null
var _title: Label = null
var _glyph: TextureRect = null
var _target: Label = null
var _reward: Label = null
var _risk_row: HBoxContainer = null
var _risk_holder: HBoxContainer = null
var _risk_text: Label = null
var _spec: Label = null
var _progress: Label = null
var _pager: Label = null
var _selected: bool = false
var _outline: Panel = null
var _job: Dictionary = {}
var _tap := TapGesture.new()


## Built in `_init` so a card can be written before it is put on the glass.
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_paper = TextureRect.new()
	_paper.texture = AssetCatalog.cabinet_texture("job_card")
	_paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_paper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_paper)

	_outline = Panel.new()
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline.add_theme_stylebox_override("panel", CabinetStyle.frame(CabinetStyle.AMBER, 0.9, 0.0, 2))
	_outline.visible = false
	add_child(_outline)

	_body = VBoxContainer.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_constant_override("separation", 2)
	add_child(_body)

	_title = CabinetStyle.mono("", CabinetStyle.FONT_SMALL, CabinetStyle.INK)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.clip_text = false
	_title.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.custom_minimum_size = Vector2(0, 26)
	_body.add_child(_title)

	_glyph = CabinetStyle.glyph(null, 28.0, CabinetStyle.INK)
	_glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(_glyph)

	_target = _field("TARGET")
	_reward = _field("REWARD")
	_reward.add_theme_color_override("font_color", CabinetStyle.INK_GREEN)
	_spec = _field("")
	_spec.add_theme_color_override("font_color", CabinetStyle.INK_DIM)

	_body.add_child(CabinetStyle.caption("RISK", CabinetStyle.FONT_TINY, CabinetStyle.INK_DIM))
	_risk_row = HBoxContainer.new()
	_risk_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_risk_row.add_theme_constant_override("separation", 6)
	_body.add_child(_risk_row)
	_risk_holder = HBoxContainer.new()
	_risk_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_risk_row.add_child(_risk_holder)
	_risk_text = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.INK_RED)
	_risk_row.add_child(_risk_text)

	_progress = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.INK)
	_body.add_child(_progress)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(spacer)

	_pager = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.INK_DIM)
	_pager.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pager.mouse_filter = Control.MOUSE_FILTER_STOP
	_pager.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_pager.gui_input.connect(_on_pager_input)
	_body.add_child(_pager)

	resized.connect(_layout)
	gui_input.connect(_on_input)
	_layout()


func _field(caption: String) -> Label:
	if caption != "":
		_body.add_child(CabinetStyle.caption(caption, CabinetStyle.FONT_TINY, CabinetStyle.INK_DIM))
	var value: Label = CabinetStyle.mono("", CabinetStyle.FONT_SMALL, CabinetStyle.INK)
	_body.add_child(value)
	return value


## Lays the ink onto the paper part of the drawn card, whatever size the card is.
func _layout() -> void:
	if _paper == null or _paper.texture == null:
		return
	var texture_size: Vector2 = _paper.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return
	var scale: float = minf(size.x / texture_size.x, size.y / texture_size.y)
	var drawn: Vector2 = texture_size * scale
	var origin: Vector2 = (size - drawn) * 0.5
	var paper := Rect2(origin + PAPER.position * drawn, PAPER.size * drawn)
	_body.position = paper.position
	_body.size = paper.size
	_outline.position = origin + Vector2(2, 2)
	_outline.size = drawn - Vector2(4, 4)
	# Ink is cut to the paper's width: ~10 characters of the fixed-pitch face
	# across the card at `small`, with `tiny` for captions and figures.
	var small: int = maxi(9, int(round(paper.size.x * 0.105)))
	var tiny: int = maxi(8, int(round(paper.size.x * 0.085)))
	_title.add_theme_font_size_override("font_size", small)
	_title.custom_minimum_size = Vector2(0, small * 2.4)
	for label in [_target, _reward]:
		label.add_theme_font_size_override("font_size", small)
	for label in [_spec, _risk_text, _progress, _pager]:
		label.add_theme_font_size_override("font_size", tiny)
	for child in _body.get_children():
		if child is Label and child != _title and child not in [_target, _reward, _spec, _risk_text, _progress, _pager]:
			child.add_theme_font_size_override("font_size", tiny)
	_glyph.custom_minimum_size = Vector2.ONE * clampf(paper.size.x * 0.22, 14.0, 44.0)
	_body.add_theme_constant_override("separation", 1 if paper.size.y < 220.0 else 2)


func set_job(job: Dictionary, lane_index: int = 0, lane_count: int = 1) -> void:
	_job = job
	if job.is_empty():
		_title.text = "NO CONTRACT"
		_glyph.texture = AssetCatalog.cabinet_stamp("target")
		_target.text = "—"
		_reward.text = "—"
		_spec.text = "TAKE A CONTRACT"
		_set_risk(0, "")
		_progress.text = ""
		_pager.text = ""
		return
	var identity: Dictionary = JobPresentation.sector(job)
	_title.text = str(job.get("name", "Contract")).to_upper()
	_glyph.texture = AssetCatalog.cabinet_stamp(_sector_icon_key(job))
	_target.text = str(identity.get("client", "")).to_upper()
	_reward.text = NumberFormat.format_cash(float(job.get("reward", 0.0)))
	var spec: PackedStringArray = [
		"%s BT" % NumberFormat.format(float(job.get("token_requirement", 0.0))),
	]
	var prompts: int = int(job.get("prompts_remaining", job.get("deadline_prompts", 0)))
	spec.append("%dP" % maxi(0, prompts))
	var threshold: float = float(job.get("quality_threshold", 0.0))
	if threshold > 0.0:
		spec.append("Q%s" % JobPresentation.quality_mark(threshold))
	_spec.text = " · ".join(spec)
	var risk: String = JobSystem.production_risk_class(job)
	_set_risk(CabinetStyle.risk_level(risk), risk)
	if compact:
		_progress.text = ""
	else:
		var requirement: float = maxf(1.0, float(job.get("token_requirement", 1.0)))
		var remaining: float = maxf(0.0, float(job.get("tokens_remaining", requirement)))
		var done: float = clampf(1.0 - remaining / requirement, 0.0, 1.0)
		# The figure leads so a narrow card trims the bar, never the number.
		var filled: int = int(round(done * 8.0))
		_progress.text = "%d%% %s%s" % [int(round(done * 100.0)), "▮".repeat(filled), "▯".repeat(8 - filled)]
	_pager.text = "%d/%d ▸" % [lane_index + 1, lane_count] if lane_count > 1 and not compact else ""


## The stat-icon name the sector table gives this contract, which is also the
## key of its stamp on the cabinet.
func _sector_icon_key(job: Dictionary) -> String:
	for tag in Array(job.get("tags", [])):
		var key: String = str(tag).to_lower()
		if JobPresentation.SECTORS.has(key):
			return str(Dictionary(JobPresentation.SECTORS[key]).get("icon", "target"))
	return "target"


func _set_risk(level: int, risk: String) -> void:
	for child in _risk_holder.get_children():
		_risk_holder.remove_child(child)
		child.queue_free()
	var color: Color = CabinetStyle.INK_RED if level >= 4 else (CabinetStyle.INK if level >= 3 else CabinetStyle.INK_GREEN)
	_risk_holder.add_child(CabinetStyle.pips(level, color, 5, 6.0, Color(0.2, 0.15, 0.1, 0.18)))
	_risk_text.text = risk
	_risk_text.add_theme_color_override("font_color", color)


func job() -> Dictionary:
	return _job


func set_selected(selected: bool) -> void:
	_selected = selected
	_outline.visible = selected


func _on_input(event: InputEvent) -> void:
	if _tap.feed(event):
		pressed.emit()
		accept_event()


func _on_pager_input(event: InputEvent) -> void:
	if _pager.text == "":
		return
	if _tap.feed(event):
		page_pressed.emit()
		accept_event()
