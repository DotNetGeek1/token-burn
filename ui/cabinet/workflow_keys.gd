class_name WorkflowKeys
extends Control

## The column of four keys under the abort lever: one per workflow the run can
## hold. The active workflow's key is lit amber, owned ones phosphor, the next
## free one reads "+" and builds a new pipeline, and keys past the run's
## workflow capacity are dead.

signal workflow_selected(index: int)

const KEYS := 4
## The plate paints the four keys as squares on a pitch; each key's face is
## this much of the pitch, the rest is the rail between them.
const KEY_OF_PITCH := 0.68

var _keys: Array[Button] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in range(KEYS):
		var key: Button = CabinetStyle.key(str(index + 1), CabinetStyle.PHOSPHOR, CabinetStyle.FONT_SMALL)
		# The key itself is painted on the plate; the button is only the light
		# in it, so it must never grow past the painted square to fit its digit.
		key.clip_text = true
		key.pressed.connect(_on_key.bind(index))
		add_child(key)
		_keys.append(key)
	resized.connect(_layout)


## One button per painted square: the region is the column's bounding box and
## the squares sit on an even pitch inside it.
func _layout() -> void:
	var pitch: float = size.y / (KEYS - 1 + KEY_OF_PITCH)
	var height: float = pitch * KEY_OF_PITCH
	for index in range(KEYS):
		var key: Button = _keys[index]
		key.position = Vector2(0.0, index * pitch)
		key.size = Vector2(size.x, height)
		key.add_theme_font_size_override("font_size", clampi(int(height * 0.6), 6, 14))


## The light in a painted key: a wash of the accent over the square and a
## hairline of it round the bevel. Nothing here has a margin, so the button
## stays the size of the square it sits on.
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
			key.add_theme_stylebox_override(state, _key_style(accent, owned or creatable, index == active, state))
		key.add_theme_color_override("font_color", CabinetStyle.AMBER if index == active else CabinetStyle.WHITE)
		key.add_theme_color_override("font_disabled_color", Color(CabinetStyle.GREY.r, CabinetStyle.GREY.g, CabinetStyle.GREY.b, 0.45))
		var workflow: Dictionary = Simulation.workflows()[index] if owned else {}
		key.tooltip_text = (
			"Workflow %d: %s" % [index + 1, str(workflow.get("name", ""))] if owned
			else ("Build a new workflow" if creatable else "")
		)


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
