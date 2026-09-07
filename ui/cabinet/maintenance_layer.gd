class_name MaintenanceLayer
extends Control

## The cabinet's second camera. Operation is the machine filling the safe
## area; maintenance is the same machine zoomed out towards the top of the
## wall behind it, with the maintenance menu down the left (Resume, Settings,
## Help, Records, Save & Quit), the five system mounts along the floor under it
## — compute, cooling, power, backplane, control, each showing the tile of the
## tier the run owns — and the cabinet's generation stencilled on the wall.
##
## Nothing is bought, built or inventoried here. A mount is inspected, not
## acted on: selecting one prints `NAME · TIER N · <stat>`. The Market's
## SYSTEMS shelf (Phase 5) is where a tier is bought; after it is, the shelf
## calls `show_install` and this layer plays the swap.
##
## Mounted under the SafeArea above the OperationGrid, hidden by default. The
## wall (`wall()`) is a separate node the cabinet seats *behind* the grid, so
## the machine shrinks over it. Geometry comes from the `maintenance` block
## in presentation/cabinet_layout_profiles.json via `CabinetLayout`.
##
## While the layer is up it is a full-rect MOUSE_FILTER_STOP surface, so
## nothing on the shrunken machine can be pressed; the menu keys and mounts
## sit on top of it and take the input instead.

## The player picked a menu entry: "resume", "settings", "help", "records", "quit".
signal menu_pressed(action: String)
## A system mount was selected (inspection only).
signal mount_selected(system_id: String)
## The camera has settled in maintenance.
signal opened
## The camera has settled back in operation.
signal closed
## A `show_install` finished, skipped or not.
signal install_finished(system_id: String)

const MENU_ENTRIES := [
	["resume", "RESUME"],
	["settings", "SETTINGS"],
	["help", "HELP"],
	["records", "RECORDS"],
	["quit", "SAVE & QUIT"],
]

## How long an install reveal plays before it settles, and how long the
## reduced-motion crossfade takes instead.
const INSTALL_SECONDS := 1.25
const INSTALL_SECONDS_REDUCED := 0.6

var _layout: CabinetLayout = null
var _grid: Control = null
var _wall: TextureRect = null
var _menu: VBoxContainer = null
var _menu_keys: Dictionary = {}
var _caption_plate: PanelContainer = null
var _caption: Label = null
var _caption_sub: Label = null
var _inspect_plate: PanelContainer = null
var _inspect_title: Label = null
var _inspect_lines: VBoxContainer = null
var _mounts: Dictionary = {}
var _selected: String = ""
var _open: bool = false
var _transitioning: bool = false
var _closing: bool = false
var _tween: Tween = null
var _install_tween: Tween = null
var _installing: String = ""
var _install_done: Callable = Callable()
var _install_target: Dictionary = {}
## A mount pinned to a tier by `hold_tier` while the camera moves out ahead
## of a `show_install`, so the old part is what zooms away. `{id, tier}`.
var _held: Dictionary = {}
var _grid_rest_scale: Vector2 = Vector2.ONE
var _grid_rest_pivot: Vector2 = Vector2.ZERO


func _init(layout: CabinetLayout) -> void:
	_layout = layout
	name = "MaintenanceLayer"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	modulate = Color(1, 1, 1, 0)
	gui_input.connect(_on_layer_input)

	_wall = TextureRect.new()
	_wall.name = "MaintenanceWall"
	_wall.texture = AssetCatalog.cabinet_v2_texture("maintenance_wall")
	_wall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wall.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wall.visible = false
	_wall.modulate = Color(1, 1, 1, 0)

	# The menu column: an engraved caption and the five keys under it.
	_menu = VBoxContainer.new()
	_menu.name = "MaintenanceMenu"
	_menu.mouse_filter = Control.MOUSE_FILTER_PASS
	_menu.add_theme_constant_override("separation", 6)
	add_child(_menu)
	var head: Label = CabinetStyle.caption("MAINTENANCE", CabinetStyle.FONT_SMALL, CabinetStyle.AMBER)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(head)
	_menu.add_child(CabinetStyle.rule(CabinetStyle.AMBER, 0.4))
	for entry in MENU_ENTRIES:
		var action: String = str(entry[0])
		var key: Button = CabinetStyle.key(str(entry[1]), CabinetStyle.RED if action == "quit" else CabinetStyle.AMBER, CabinetStyle.FONT_SMALL)
		key.name = "Menu%s" % action.to_pascal_case()
		key.focus_mode = Control.FOCUS_ALL
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.custom_minimum_size = Vector2(0, 40)
		key.pressed.connect(_on_menu.bind(action))
		_menu.add_child(key)
		_menu_keys[action] = key

	# The generation stencil on the wall.
	_caption_plate = PanelContainer.new()
	_caption_plate.name = "GenerationCaption"
	_caption_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_plate.add_theme_stylebox_override("panel", CabinetStyle.legend_plate())
	add_child(_caption_plate)
	var caption_column := VBoxContainer.new()
	caption_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_column.add_theme_constant_override("separation", 0)
	_caption_plate.add_child(caption_column)
	_caption_sub = CabinetStyle.caption("GENERATION", CabinetStyle.FONT_TINY, CabinetStyle.AMBER_DIM)
	_caption_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_column.add_child(_caption_sub)
	_caption = CabinetStyle.mono("", CabinetStyle.FONT_BODY, CabinetStyle.AMBER)
	_caption.name = "GenerationName"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.clip_text = false
	_caption.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	var stencil: Font = UiThemeBuilder.header_font()
	if stencil != null:
		_caption.add_theme_font_override("font", stencil)
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_caption.add_theme_constant_override("outline_size", 2)
	caption_column.add_child(_caption)

	# The inspection readout: what the selected mount is and does.
	_inspect_plate = CabinetStyle.glass_panel()
	_inspect_plate.name = "Inspect"
	_inspect_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_inspect_plate)
	var inspect_column := VBoxContainer.new()
	inspect_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspect_column.add_theme_constant_override("separation", 2)
	_inspect_plate.add_child(inspect_column)
	_inspect_title = CabinetStyle.mono("", CabinetStyle.FONT_SMALL, CabinetStyle.PHOSPHOR)
	_inspect_title.name = "InspectTitle"
	_inspect_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspect_title.clip_text = false
	_inspect_title.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	inspect_column.add_child(_inspect_title)
	_inspect_lines = VBoxContainer.new()
	_inspect_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_lines.add_theme_constant_override("separation", 1)
	inspect_column.add_child(_inspect_lines)

	# The five mounts.
	for raw in CabinetSystems.system_ids():
		var system_id: String = str(raw)
		var mount := SystemMount.new(system_id)
		mount.name = "Mount%s" % system_id.to_pascal_case()
		mount.pressed.connect(_on_mount.bind(system_id))
		add_child(mount)
		_mounts[system_id] = mount
	refresh()


## The wall the cabinet seats behind the OperationGrid. Created here so the
## layer can fade it; parented by the cabinet so it draws under the machine.
func wall() -> TextureRect:
	return _wall


# --- Layout ------------------------------------------------------------------

## Places the menu, caption, readout and mounts against the maintenance block
## of the current layout profile. The layer itself spans the safe area.
func layout() -> void:
	if _layout == null:
		return
	_place(_menu, "menu")
	_place(_caption_plate, "caption")
	_place(_inspect_plate, "inspect")
	for system_id in _mounts:
		_place(_mounts[system_id], "mount_%s" % system_id)
	var caption_h: float = _caption_plate.size.y
	_caption.add_theme_font_size_override("font_size", clampi(int(caption_h * 0.28), CabinetStyle.FONT_SMALL, CabinetStyle.FONT_HEAD))
	if _open and not _transitioning and _grid != null:
		_apply_zoom(1.0)


func _place(control: Control, key: String) -> void:
	var rect: Rect2 = _layout.maintenance_rect_local(key)
	control.visible = rect.size.x > 0.0 and rect.size.y > 0.0
	control.position = rect.position
	control.size = rect.size


# --- Camera ------------------------------------------------------------------

func is_open() -> bool:
	return _open


func is_transitioning() -> bool:
	return _transitioning


## Zooms the machine out and brings the maintenance surfaces up. `grid` is the
## OperationGrid; the layer remembers its resting transform and puts it back.
func open(grid: Control) -> void:
	if _open or _transitioning:
		return
	_grid = grid
	_open = true
	_transitioning = true
	_grid_rest_scale = _grid.scale
	_grid_rest_pivot = _grid.pivot_offset
	refresh()
	visible = true
	_wall.visible = true
	_set_menu_enabled(false)
	var tuning: Dictionary = _layout.maintenance_tuning()
	var seconds: float = float(tuning.get("duration_s", 0.3))
	var wall_alpha: float = float(tuning.get("wall_alpha", 0.9))
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	if UiFx.reduced_motion():
		# No movement: the machine is small at once and the surfaces fade in.
		_apply_zoom(1.0)
		_tween.tween_property(self, "modulate:a", 1.0, seconds)
		_tween.tween_property(_wall, "modulate:a", wall_alpha, seconds)
	else:
		_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_tween.tween_method(_apply_zoom, 0.0, 1.0, seconds)
		_tween.tween_property(self, "modulate:a", 1.0, seconds)
		_tween.tween_property(_wall, "modulate:a", wall_alpha, seconds)
	_tween.chain().tween_callback(_on_opened)


func _on_opened() -> void:
	_transitioning = false
	# An install that started during the zoom keeps the menu locked until it
	# lands; a press anywhere on the layer skips it instead.
	_set_menu_enabled(_installing == "")
	var resume: Button = _menu_keys.get("resume")
	if resume != null and is_visible_in_tree() and _installing == "":
		resume.grab_focus()
	opened.emit()


## Brings the machine back to fill the safe area and hides the surfaces. A
## close during the opening move reverses from wherever the camera is; a
## second close during the closing move is ignored.
func close() -> void:
	if not _open or _closing:
		return
	_closing = true
	_transitioning = true
	_set_menu_enabled(false)
	skip_install()
	var tuning: Dictionary = _layout.maintenance_tuning()
	var seconds: float = float(tuning.get("duration_s", 0.3))
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	if UiFx.reduced_motion():
		_tween.tween_property(self, "modulate:a", 0.0, seconds)
		_tween.tween_property(_wall, "modulate:a", 0.0, seconds)
	else:
		_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_tween.tween_method(_apply_zoom, _current_zoom(), 0.0, seconds)
		_tween.tween_property(self, "modulate:a", 0.0, seconds)
		_tween.tween_property(_wall, "modulate:a", 0.0, seconds)
	_tween.chain().tween_callback(_on_closed)


## Where the camera is between operation (0) and maintenance (1), read back
## from the grid so a reversed move starts from the right place.
func _current_zoom() -> float:
	if _grid == null:
		return 1.0
	var target: float = float(_layout.maintenance_tuning().get("zoom_scale", 0.62))
	if is_equal_approx(target, 1.0):
		return 1.0
	return clampf((1.0 - _grid.scale.x) / (1.0 - target), 0.0, 1.0)


func _on_closed() -> void:
	_apply_zoom(0.0)
	if _grid != null:
		_grid.scale = _grid_rest_scale
		_grid.pivot_offset = _grid_rest_pivot
	visible = false
	_wall.visible = false
	_open = false
	_closing = false
	_transitioning = false
	_held = {}
	if get_viewport() != null:
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused != null and is_ancestor_of(focused):
			focused.release_focus()
	closed.emit()


## Interpolates the grid between operation (0) and maintenance (1).
func _apply_zoom(t: float) -> void:
	if _grid == null:
		return
	var tuning: Dictionary = _layout.maintenance_tuning()
	var target: float = float(tuning.get("zoom_scale", 0.62))
	var pivot_raw: Variant = tuning.get("zoom_pivot", [0.5, 0.0])
	var pivot := Vector2(0.5, 0.0)
	if pivot_raw is Array and Array(pivot_raw).size() >= 2:
		pivot = Vector2(float(Array(pivot_raw)[0]), float(Array(pivot_raw)[1]))
	_grid.pivot_offset = Vector2(_grid.size.x * pivot.x, _grid.size.y * pivot.y)
	var s: float = lerpf(1.0, target, clampf(t, 0.0, 1.0))
	_grid.scale = Vector2(s, s)


func _set_menu_enabled(enabled: bool) -> void:
	for action in _menu_keys:
		(_menu_keys[action] as Button).disabled = not enabled


# --- Content -----------------------------------------------------------------

## Re-reads the tiers and the generation from the simulation. Cheap; called
## on open and by the shell's refresh_all. A mount mid-reveal, or held ahead
## of one, keeps the tier the reveal is showing.
func refresh() -> void:
	var tiers: Dictionary = Simulation.cabinet_system_tiers()
	for system_id in _mounts:
		var mount: SystemMount = _mounts[system_id]
		if _installing == system_id or str(_held.get("id", "")) == system_id:
			continue
		mount.set_tier(int(tiers.get(system_id, CabinetSystems.min_tier())))
		mount.set_selected(system_id == _selected)
	_refresh_caption()
	_refresh_inspect()


## Pins one mount to `tier` through refreshes until `show_install` takes it
## over (or the layer closes). The shell calls this before opening the camera
## for an install, so the machine zooms out still wearing the old part.
func hold_tier(system_id: String, tier: int) -> void:
	if not _mounts.has(system_id):
		return
	_held = {"id": system_id, "tier": tier}
	(_mounts[system_id] as SystemMount).set_tier(tier)


func _refresh_caption() -> void:
	var generation: Dictionary = Simulation.cabinet_generation()
	_caption.text = str(generation.get("name", "Improvised Cabinet")).to_upper()
	_caption_sub.text = "GENERATION %d · SYSTEMS %d" % [int(generation.get("index", 0)) + 1, int(generation.get("sum", 0))]


## The mounts by system id, for the shell and the playtests.
func mounts() -> Dictionary:
	return _mounts.duplicate()


func mount(system_id: String) -> Control:
	return _mounts.get(system_id)


func menu_key(action: String) -> Button:
	return _menu_keys.get(action)


func selected_system() -> String:
	return _selected


## The stencil on the wall.
func generation_caption() -> String:
	return _caption.text


## The readout's headline, `NAME · TIER N · <stat>`.
func inspection_text() -> String:
	return _inspect_title.text


## Selects a mount for inspection. Returns false for an unknown system.
func select_system(system_id: String) -> bool:
	if not _mounts.has(system_id):
		return false
	_selected = system_id
	for other in _mounts:
		(_mounts[other] as SystemMount).set_selected(other == system_id)
	_refresh_inspect()
	mount_selected.emit(system_id)
	return true


func _refresh_inspect() -> void:
	for child in _inspect_lines.get_children():
		_inspect_lines.remove_child(child)
		child.queue_free()
	if _selected == "" or not _mounts.has(_selected):
		_inspect_title.text = "SELECT A SYSTEM TO INSPECT"
		_inspect_title.add_theme_color_override("font_color", CabinetStyle.PHOSPHOR_DIM)
		return
	var info: Dictionary = Simulation.cabinet_system_next(_selected)
	var tier: int = int(info.get("tier", 1))
	var stats: PackedStringArray = []
	for stat_key in CabinetSystems.stat_keys(_selected):
		var key: String = str(stat_key)
		var value: float = CabinetSystems.capacity(Simulation.run_state, _selected, key)
		stats.append("%s %s" % [_format_stat(key, value), CabinetSystems.stat_label(key)])
	_inspect_title.text = "%s · TIER %d · %s" % [str(info.get("name", _selected)).to_upper(), tier, " · ".join(stats)]
	_inspect_title.add_theme_color_override("font_color", CabinetStyle.PHOSPHOR)
	var lines: Array = [
		{"stat": "Fitted", "value": str(info.get("tier_name", "")).to_upper()},
	]
	if bool(info.get("maxed", false)):
		lines.append({"stat": "Next", "value": "TOP TIER", "role": "success"})
	else:
		lines.append({"stat": "Next", "value": "TIER %d · %s" % [int(info.get("next_tier", tier + 1)), str(info.get("next_tier_name", "")).to_upper()]})
		var effect: String = str(info.get("effect", ""))
		if effect != "":
			lines.append({"text": effect})
		var reason: String = str(info.get("reason", ""))
		# The blocker is already the Market's capitals ("NEXT CHAPTER UNLOCKS
		# TIER 3"); every other line on this panel is caps too.
		lines.append({"text": "BOUGHT AT THE MARKET." if reason == "" else reason.to_upper(), "role": "warning" if reason != "" else "success"})
	CabinetTab.detail_rows(_inspect_lines, lines, CabinetStyle.FONT_MIN_BODY)


func _format_stat(stat_key: String, value: float) -> String:
	if stat_key == "base_token_rate":
		return NumberFormat.format(value)
	return str(int(round(value)))


# --- Install reveal ----------------------------------------------------------

## Plays a tier swap on one mount: the tile flickers and sparks, the new tier's
## tile lands, the label reads the new tier; 1.0–1.5 s, then `on_done` (and
## `install_finished`). Any press on the layer, or `skip_install()`, jumps to
## the end. Under reduced motion the swap is a plain crossfade.
func show_install(system_id: String, old_tier: int, new_tier: int, on_done: Callable = Callable()) -> void:
	if not _mounts.has(system_id):
		if on_done.is_valid():
			on_done.call()
		return
	skip_install()
	_held = {}
	var target: SystemMount = _mounts[system_id]
	_installing = system_id
	_install_done = on_done
	_install_target = {"id": system_id, "tier": new_tier}
	# Input is locked to the reveal: the menu is dead until it lands, and any
	# press on the layer jumps to the end.
	_set_menu_enabled(false)
	if get_viewport() != null:
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused != null and is_ancestor_of(focused):
			focused.release_focus()
	select_system(system_id)
	target.set_tier(old_tier)
	target.begin_install(old_tier, new_tier)
	if _install_tween != null and _install_tween.is_valid():
		_install_tween.kill()
	_install_tween = create_tween()
	if UiFx.reduced_motion():
		_install_tween.tween_property(target.tile(), "modulate:a", 0.0, INSTALL_SECONDS_REDUCED * 0.5)
		_install_tween.tween_callback(func() -> void:
			target.set_tier(new_tier)
			UiSound.play("install")
		)
		_install_tween.tween_property(target.tile(), "modulate:a", 1.0, INSTALL_SECONDS_REDUCED * 0.5)
	else:
		# Flicker out, swap under a spark, flicker in.
		var flicker: Array = [0.25, 1.0, 0.15, 0.9, 0.05]
		for level in flicker:
			_install_tween.tween_property(target.tile(), "modulate:a", float(level), INSTALL_SECONDS * 0.08)
		_install_tween.tween_callback(func() -> void:
			target.set_tier(new_tier)
			target.spark()
			UiSound.play("install")
		)
		_install_tween.tween_property(target.tile(), "modulate:a", 1.0, INSTALL_SECONDS * 0.15)
		_install_tween.tween_interval(INSTALL_SECONDS * 0.45)
	_install_tween.tween_callback(_finish_install)


func is_installing() -> bool:
	return _installing != ""


## Jumps a running install to its end state.
func skip_install() -> void:
	if _installing == "":
		return
	if _install_tween != null and _install_tween.is_valid():
		_install_tween.kill()
	_finish_install()


func _finish_install() -> void:
	if _installing == "":
		return
	var system_id: String = _installing
	var target: SystemMount = _mounts.get(system_id)
	if target != null:
		target.set_tier(int(_install_target.get("tier", target.tier())))
		target.tile().modulate.a = 1.0
		target.end_install()
	_installing = ""
	var done: Callable = _install_done
	_install_done = Callable()
	_install_target = {}
	# The mount keeps the tier the reveal landed on (the caller has already
	# upgraded the simulation); the caption and readout re-read the run.
	_refresh_caption()
	_refresh_inspect()
	if _open and not _transitioning and not _closing:
		_set_menu_enabled(true)
	install_finished.emit(system_id)
	if done.is_valid():
		done.call()


# --- Input -------------------------------------------------------------------

func _on_layer_input(event: InputEvent) -> void:
	if _installing != "" and (
		(event is InputEventMouseButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
		or event.is_action_pressed("ui_accept")
	):
		skip_install()
		accept_event()


func _on_menu(action: String) -> void:
	if _transitioning:
		return
	UiSound.play("tap")
	menu_pressed.emit(action)


func _on_mount(system_id: String) -> void:
	if _transitioning:
		return
	if _installing != "":
		skip_install()
	UiSound.play("tap")
	select_system(system_id)


## One system mount: the tier's tile on a dark plate with the system's name
## and tier under it. A Button, so a finger, the driver and a keyboard all
## reach it; selection is a full frame plus a notch, not a colour change.
class SystemMount extends Button:
	var system_id: String = ""
	var _tier: int = 1
	var _tile: TextureRect = null
	var _plate: Panel = null
	var _name_label: Label = null
	var _tier_label: Label = null
	var _marker: Label = null
	var _spark: Spark = null
	var _selected: bool = false
	var _installing: bool = false
	var _install_from: int = 1
	var _install_to: int = 1
	var _tier_suffix: String = ""

	func _init(id: String) -> void:
		system_id = id
		text = ""
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var clear := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(state, clear)
		var focus := CabinetStyle.frame(CabinetStyle.AMBER, 0.95, 0.0, 2)
		add_theme_stylebox_override("focus", focus)
		_plate = Panel.new()
		_plate.name = "Plate"
		_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_plate)
		_tile = TextureRect.new()
		_tile.name = "Tile"
		_tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_tile)
		_spark = Spark.new()
		_spark.name = "Spark"
		add_child(_spark)
		_marker = CabinetStyle.mono("►", CabinetStyle.FONT_TINY, CabinetStyle.AMBER)
		_marker.name = "Marker"
		_marker.visible = false
		add_child(_marker)
		_name_label = CabinetStyle.caption(CabinetSystems.system_name(id), CabinetStyle.FONT_TINY, CabinetStyle.AMBER)
		_name_label.name = "Name"
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_name_label)
		_tier_label = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR)
		_tier_label.name = "Tier"
		_tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_tier_label)
		resized.connect(_layout)
		_restyle()

	func tier() -> int:
		return _tier

	func tile() -> TextureRect:
		return _tile

	func set_tier(new_tier: int) -> void:
		_tier = new_tier
		_tile.texture = AssetCatalog.cabinet_system_tile(system_id, new_tier)
		_tile.visible = _tile.texture != null
		if not _installing:
			_tier_suffix = ""
			_tier_label.text = _tier_text(_tier_suffix)
		tooltip_text = "%s — %s (tier %d)" % [CabinetSystems.system_name(system_id), CabinetSystems.tier_name(system_id, new_tier), new_tier]

	## "TIER 2 · GPU CAGE" when the plate is wide enough, "TIER 2" when the
	## name would only be cut to an ellipsis. `suffix` is appended either way.
	func _tier_text(suffix: String) -> String:
		return _fit_text([
			"TIER %d · %s%s" % [_tier, CabinetSystems.tier_name(system_id, _tier).to_upper(), suffix],
			"TIER %d%s" % [_tier, suffix],
		])

	## The first of `candidates` that fits the tier label's width; the last one
	## when none does, so a short plate still says the most it can.
	func _fit_text(candidates: Array[String]) -> String:
		var font: Font = _tier_label.get_theme_font("font")
		var font_px: int = _tier_label.get_theme_font_size("font_size")
		if font == null or _tier_label.size.x <= 0.0:
			return candidates[0]
		for candidate in candidates:
			if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px).x <= _tier_label.size.x:
				return candidate
		return candidates[candidates.size() - 1]

	func set_selected(selected: bool) -> void:
		_selected = selected
		_restyle()

	func is_selected() -> bool:
		return _selected

	func begin_install(old_tier: int, new_tier: int) -> void:
		_installing = true
		_install_from = old_tier
		_install_to = new_tier
		_tier_label.text = _install_text()
		_tier_label.add_theme_color_override("font_color", CabinetStyle.AMBER)

	## "INSTALLING · TIER 1 → 2", or as much of it as the plate has room for.
	func _install_text() -> String:
		return _fit_text([
			"INSTALLING · TIER %d → %d" % [_install_from, _install_to],
			"TIER %d → %d" % [_install_from, _install_to],
			"INSTALLING",
		])

	func end_install() -> void:
		_installing = false
		_tier_label.add_theme_color_override("font_color", CabinetStyle.PHOSPHOR)
		_tier_suffix = " FITTED"
		_tier_label.text = _tier_text(_tier_suffix)

	func spark() -> void:
		_spark.fire()

	func _restyle() -> void:
		var box: StyleBoxFlat = CabinetStyle.glass_box(0.9, Color(0.03, 0.03, 0.028, 0.96))
		if _selected:
			box.border_color = CabinetStyle.AMBER
			box.set_border_width_all(2)
		_plate.add_theme_stylebox_override("panel", box)
		_marker.visible = _selected
		_name_label.add_theme_color_override("font_color", CabinetStyle.AMBER if _selected else CabinetStyle.AMBER_DIM)

	func _layout() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		_plate.position = Vector2.ZERO
		_plate.size = size
		var label_h: float = clampf(size.y * 0.13, 12.0, 18.0)
		var pad: float = clampf(size.y * 0.04, 2.0, 8.0)
		var tile_h: float = maxf(8.0, size.y - label_h * 2.0 - pad * 3.0)
		_tile.position = Vector2(pad, pad)
		_tile.size = Vector2(size.x - pad * 2.0, tile_h)
		_spark.position = _tile.position
		_spark.size = _tile.size
		_marker.position = Vector2(pad, pad)
		_marker.size = Vector2(label_h, label_h)
		_name_label.position = Vector2(pad, pad + tile_h + pad * 0.5)
		_name_label.size = Vector2(size.x - pad * 2.0, label_h)
		_tier_label.position = Vector2(pad, _name_label.position.y + label_h)
		_tier_label.size = Vector2(size.x - pad * 2.0, label_h)
		var font_px: int = clampi(int(label_h * 0.7), 9, 12)
		# The system's name is let down to 9 px before it is cut: WORKFLOW
		# BACKPLANE on a compact plate is a name, WORKFLOW BACK… is not.
		var name_px: int = font_px
		var name_font: Font = _name_label.get_theme_font("font")
		if name_font != null:
			while name_px > 9 and name_font.get_string_size(_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, name_px).x > _name_label.size.x:
				name_px -= 1
		_name_label.add_theme_font_size_override("font_size", name_px)
		_tier_label.add_theme_font_size_override("font_size", font_px)
		_tier_label.text = _install_text() if _installing else _tier_text(_tier_suffix)


## A burst of short amber lines from the tile's centre that fades out: the
## spark of a new part seating.
class Spark extends Control:
	var _life: float = 0.0
	var _seed: int = 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	func fire() -> void:
		_life = 1.0
		_seed = randi()
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		_life -= delta * 2.2
		if _life <= 0.0:
			_life = 0.0
			set_process(false)
		queue_redraw()

	func _draw() -> void:
		if _life <= 0.0:
			return
		var centre: Vector2 = size * 0.5
		var reach: float = minf(size.x, size.y) * (0.25 + 0.45 * (1.0 - _life))
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed
		for index in range(10):
			var angle: float = rng.randf_range(0.0, TAU)
			var length: float = reach * rng.randf_range(0.5, 1.0)
			var from: Vector2 = centre + Vector2.RIGHT.rotated(angle) * length * 0.55
			var to: Vector2 = centre + Vector2.RIGHT.rotated(angle) * length
			draw_line(from, to, Color(1.0, 0.85, 0.45, _life), 2.0)
		draw_circle(centre, reach * 0.18 * _life, Color(1.0, 0.95, 0.8, _life * 0.8))
