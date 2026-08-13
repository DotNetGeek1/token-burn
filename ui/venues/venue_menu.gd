extends VenueScene

## The lobby: everything that is not the run itself.
##
## Settings down the left, the places you can go from here as cards on the board.
## The old version of this was a numbered index in the side panel, which is the
## right shape for a list of commands and the wrong shape for a set of
## destinations — a destination wants to say how much of itself is left to see,
## and a single line has nowhere to put that.

## Where each destination goes, and what the card says about it. Ordered as the
## index was: the run's own tools first, then the profile's records, then the
## debug door.
const DESTINATIONS := [
	{
		"id": "workflows",
		"name": "Workflows",
		"blurb": "The pipelines this run works its contracts through.",
		"run_only": true,
	},
	{
		"id": "legacy",
		"name": "The Legacy",
		"blurb": "What every run so far has permanently bought you.",
	},
	{
		"id": "achievements",
		"name": "The Trophy Cabinet",
		"blurb": "Awards earned, awards missed, and what they hand over.",
	},
	{
		"id": "burn_lab",
		"name": "Burn Lab",
		"blurb": "Developer tooling. Opens back at the desk.",
		"flag": "burn_lab_enabled",
	},
]

var _kicker: Label = null
var _difficulty: VBoxContainer = null
var _rows: Dictionary = {}
var _board_panel: VenuePanel = null
var _board: VenueBoard = null
var _sign: Label = null
var _notice: Label = null


func venue_key() -> String:
	return "menu"


func _build_venue() -> void:
	_build_index()
	_build_board()
	_build_signage()
	_build_notice()
	EventBus.run_started.connect(refresh)


## The left-hand panel: the settings, which are the only things in this room that
## are decisions rather than doors.
func _build_index() -> void:
	var panel: VenuePanel = add_panel("index", "More", {
		"console_order": 20, "console_min": 190.0,
	})
	var content: VBoxContainer = panel.content()

	_kicker = ConsoleStyle.label(
		"DIFFICULTY · APPLIES FROM YOUR NEXT NEW RUN",
		ConsoleStyle.FONT_TINY,
		ConsoleStyle.PHOSPHOR_DIM
	)
	_kicker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_kicker)

	_difficulty = VBoxContainer.new()
	_difficulty.add_theme_constant_override("separation", 0)
	_difficulty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_difficulty)

	_add_row(_difficulty, "normal", "1", "NORMAL", _on_pick_difficulty.bind("normal"))
	_add_row(_difficulty, "hard", "2", "HARD", _on_pick_difficulty.bind("hard"))
	_add_row(_difficulty, "endless", "3", "ENDLESS MODE", _on_toggle_endless)

	content.add_child(ConsoleStyle.rule(0.22))
	_add_row(content, "title", "X", "QUIT TO TITLE", _on_title, true)


func _add_row(
	parent: Node,
	key: String,
	index_label: String,
	headline: String,
	handler: Callable,
	destructive: bool = false
) -> void:
	var row := ConsoleMenuRow.new()
	row.index_label = index_label
	row.headline = headline
	row.destructive = destructive
	row.pressed.connect(handler)
	parent.add_child(row)
	_rows[key] = row


func _build_board() -> void:
	_board_panel = add_panel("board", "Records and tools", {
		"console_order": 10, "console_min": 200.0, "grow": true,
	})
	_board = VenueBoard.new()
	_board.tile_selected.connect(_on_destination)
	_board_panel.content().add_child(_board)


func _build_signage() -> void:
	var panel: VenuePanel = add_panel("signage", "", {
		"console_order": 30, "console_hide": true,
	})
	_sign = ConsoleStyle.paragraph(
		"AUTOSAVE RUNS AFTER EVERY DECISION",
		ConsoleStyle.FONT_TINY,
		ConsoleStyle.PHOSPHOR_DIM
	)
	_sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.content().add_child(_sign)


func _build_notice() -> void:
	var panel: VenuePanel = add_panel("notice", "", {
		"console_order": 40, "console_hide": true,
	})
	_notice = ConsoleStyle.paragraph("", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.content().add_child(_notice)


# --- Refresh -----------------------------------------------------------------

func refresh() -> void:
	if _board == null:
		return
	_refresh_difficulty()
	_refresh_endless()
	_refresh_board()
	_notice.text = MetaProgress.difficulty().to_upper()
	_layout_rows()


func _refresh_difficulty() -> void:
	var current: String = MetaProgress.difficulty()
	_rows["normal"].set_selected(current == "normal")
	_rows["hard"].set_selected(current == "hard")


func _refresh_endless() -> void:
	var unlocked: bool = MetaProgress.endless_unlocked()
	var row: ConsoleMenuRow = _rows["endless"]
	row.visible = unlocked
	if not unlocked:
		return
	var on: bool = MetaProgress.endless_enabled()
	row.value_text = "ON" if on else "OFF"
	row.set_selected(on)


func _refresh_board() -> void:
	var entries: Array = []
	for destination in DESTINATIONS:
		var entry: Dictionary = _destination_entry(Dictionary(destination))
		if not entry.is_empty():
			entries.append(entry)
	_board.set_entries(entries)


## A destination that this profile or this run cannot use is absent rather than
## greyed: workflows belong to a run, and the burn lab belongs to a build with
## the flag on.
func _destination_entry(destination: Dictionary) -> Dictionary:
	var id: String = str(destination.get("id", ""))
	var flag: String = str(destination.get("flag", ""))
	if flag != "" and not FeatureFlags.is_enabled(flag):
		return {}
	if bool(destination.get("run_only", false)) \
			and Simulation.phase == Simulation.Phase.IDLE:
		return {}
	var figure: Dictionary = _destination_figure(id)
	return {
		"meta": id,
		"name": str(destination.get("name", id)),
		"figure": str(figure.get("figure", "")),
		"unit": str(figure.get("unit", "")),
		"spec": str(destination.get("blurb", "")),
		"status": "OPEN",
		"tooltip": str(destination.get("blurb", "")),
	}


## How much of the place there is to see, which is the one thing a door can
## usefully say about the room behind it.
func _destination_figure(id: String) -> Dictionary:
	match id:
		"achievements":
			return {
				"figure": "%d / %d" % [
					MetaProgress.achievement_count(),
					ContentDatabase.achievements.size(),
				],
				"unit": "earned",
			}
		"workflows":
			return {
				"figure": "%d / %d" % [
					Simulation.workflow_count(), Simulation.workflow_capacity(),
				],
				"unit": "defined",
			}
		"legacy":
			return {
				"figure": "%.0f%%" % float(
					MetaProgress.completion_summary().get("percent", 0.0)
				),
				"unit": "career complete",
			}
		_:
			return {"figure": "", "unit": ""}


# --- Actions -----------------------------------------------------------------

func _on_destination(meta: Variant) -> void:
	# Nothing in this room stays selected: a door is pressed, not chosen.
	_board.clear_selection()
	match str(meta):
		"workflows":
			SceneRouter.open_workflows()
		"legacy":
			SceneRouter.open_legacy()
		"achievements":
			SceneRouter.open_achievements()
		"burn_lab":
			SceneRouter.open_burn_lab()


func _on_pick_difficulty(difficulty_id: String) -> void:
	MetaProgress.set_difficulty(difficulty_id)
	refresh()


func _on_toggle_endless() -> void:
	MetaProgress.set_endless_enabled(not MetaProgress.endless_enabled())
	refresh()


func _on_title() -> void:
	SceneRouter.open_title()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if SceneRouter.investor_busy():
		return
	match event.keycode:
		KEY_1:
			_on_pick_difficulty("normal")
		KEY_2:
			_on_pick_difficulty("hard")
		KEY_3:
			if MetaProgress.endless_unlocked():
				_on_toggle_endless()
		KEY_X:
			_on_title()
		_:
			return
	get_viewport().set_input_as_handled()


# --- Layout ------------------------------------------------------------------

func _on_venue_layout() -> void:
	var scale: float = console_scale()
	if _board != null:
		_board.set_console(console_mode())
		_board.set_metrics(scale, content_width("board"))
	_layout_rows()
	var font_tiny: int = ConsoleMetrics.font_tiny(scale)
	for label in [_kicker, _sign, _notice]:
		if label != null:
			label.add_theme_font_size_override("font_size", font_tiny)


func _layout_rows() -> void:
	var scale: float = console_scale()
	var font: int = ConsoleMetrics.font_small(scale)
	var height: int = ConsoleMetrics.row_height(scale)
	var pad: int = ConsoleMetrics.pad_h(scale)
	for key in _rows:
		(_rows[key] as ConsoleMenuRow).set_metrics(font, height, pad)
