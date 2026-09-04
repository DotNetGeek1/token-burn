class_name WorkflowKeys
extends Control

## The workflow selectors in the backplane header: a row of four keys, one per
## workflow the run can hold, with the active workflow's name printed beside
## them. The active workflow's key is lit amber, owned ones phosphor, the next
## free one reads "+" and builds a new pipeline, and keys past the run's
## workflow capacity are dead.

signal workflow_selected(index: int)

const KEYS := 4
## The gap between keys in the header row, as a fraction of the key size.
const ROW_GAP := 0.18

var _keys: Array[Button] = []
var _name: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in range(KEYS):
		var key: Button = CabinetStyle.key(str(index + 1), CabinetStyle.PHOSPHOR, CabinetStyle.FONT_SMALL)
		key.clip_text = true
		key.pressed.connect(_on_key.bind(index))
		add_child(key)
		_keys.append(key)
	_name = CabinetStyle.mono("", CabinetStyle.FONT_SMALL, CabinetStyle.AMBER)
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	if _name == null or size.x <= 0.0 or size.y <= 0.0:
		return
	_name.visible = true
	var key_size: float = size.y
	var gap: float = key_size * ROW_GAP
	# Four keys must fit before the name; shrink them on a rail too narrow.
	var needed: float = KEYS * key_size + (KEYS - 1) * gap
	if needed > size.x * 0.6:
		key_size = (size.x * 0.6) / (KEYS + (KEYS - 1) * ROW_GAP)
		gap = key_size * ROW_GAP
	for index in range(KEYS):
		var key: Button = _keys[index]
		key.position = Vector2(index * (key_size + gap), (size.y - key_size) * 0.5)
		key.size = Vector2(key_size, key_size)
		key.add_theme_font_size_override("font_size", clampi(int(key_size * 0.5), 8, 18))
	var name_x: float = KEYS * (key_size + gap) + gap
	_name.position = Vector2(name_x, 0.0)
	_name.size = Vector2(maxf(0.0, size.x - name_x), size.y)
	_name.add_theme_font_size_override("font_size", clampi(int(size.y * 0.42), 10, 16))


## The light in a key: a wash of the accent over the square and a hairline of
## it round the bevel. Nothing here has a margin, so the button stays the size
## of the square it sits on.
static func _key_style(accent: Color, lit: bool, active: bool, state: String) -> StyleBoxFlat:
	var fill: float = 0.30 if active else (0.10 if lit else 0.0)
	match state:
		"hover":
			fill += 0.10
		"pressed":
			fill += 0.18
	var box := StyleBoxFlat.new()
	box.bg_color = Color(accent.r, accent.g, accent.b, fill)
	box.border_color = Color(accent.r, accent.g, accent.b, 0.9 if active else (0.5 if lit else 0.0))
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	box.set_content_margin_all(0)
	return box


## The header key: the same light, over a dark key face so it reads on the rail.
static func _row_key_style(accent: Color, lit: bool, active: bool, state: String) -> StyleBoxFlat:
	var box: StyleBoxFlat = _key_style(accent, lit, active, state)
	var face: Color = Color(0.06, 0.055, 0.05, 0.95)
	box.bg_color = face.lerp(Color(accent.r, accent.g, accent.b, 1.0), box.bg_color.a)
	box.border_color = Color(accent.r, accent.g, accent.b, 0.9 if active else (0.55 if lit else 0.2))
	box.set_corner_radius_all(3)
	return box


func refresh() -> void:
	var count: int = Simulation.workflow_count()
	var capacity: int = Simulation.workflow_capacity()
	var active: int = Simulation.active_workflow_index()
	var in_run: bool = Simulation.phase != Simulation.Phase.IDLE
	for index in range(KEYS):
		var key: Button = _keys[index]
		var owned: bool = index < count
		var creatable: bool = index == count and index < capacity and in_run and not Simulation.is_work_running()
		key.disabled = not (owned or creatable)
		key.text = "+" if creatable else str(index + 1)
		var accent: Color = CabinetStyle.AMBER if index == active else (CabinetStyle.PHOSPHOR if owned else CabinetStyle.GREY)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			key.add_theme_stylebox_override(state, _row_key_style(accent, owned or creatable, index == active, state))
		key.add_theme_color_override("font_color", CabinetStyle.AMBER if index == active else CabinetStyle.WHITE)
		key.add_theme_color_override("font_disabled_color", Color(CabinetStyle.GREY.r, CabinetStyle.GREY.g, CabinetStyle.GREY.b, 0.45))
		var workflow: Dictionary = Simulation.workflows()[index] if owned else {}
		key.tooltip_text = (
			"Workflow %d: %s" % [index + 1, str(workflow.get("name", ""))] if owned
			else ("Build a new workflow" if creatable else "")
		)
	var active_workflow: Dictionary = Simulation.active_workflow()
	var shown_name: String = str(active_workflow.get("name", "")).to_upper()
	_name.text = shown_name if shown_name != "" else ("NO WORKFLOW" if count == 0 else "WORKFLOW %d" % (active + 1))
	_name.add_theme_color_override("font_color", CabinetStyle.AMBER if count > 0 else CabinetStyle.GREY)


func _on_key(index: int) -> void:
	if index < Simulation.workflow_count():
		if Simulation.set_active_workflow(index):
			UiSound.play("tap")
			workflow_selected.emit(index)
		return
	if index == Simulation.workflow_count() and index < Simulation.workflow_capacity():
		var created: Dictionary = Simulation.create_workflow()
		if not created.is_empty():
			UiSound.play("accept")
			Simulation.set_active_workflow(index)
			workflow_selected.emit(index)
