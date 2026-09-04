class_name MaintenanceSettingsSheet
extends ConsoleOverlay

## Settings, on a CRT sheet over the maintenance view. The same decisions the
## old lobby (`venue_menu`) kept down its left: difficulty (applies from the
## next new run), endless mode once it is unlocked, sound, and — new — reduced
## motion, which turns the hold ring into a fill, the maintenance zoom into a
## crossfade and switches off the CRT shake. Every row is a toggle or a pick;
## nothing here leaves the cabinet.

var _rows: Dictionary = {}
var _kicker: Label = null
var _note: Label = null


func _ready() -> void:
	super._ready()
	name = "MaintenanceSettings"
	setup("settings")
	compact = true
	var body: VBoxContainer = content()
	_kicker = ConsoleStyle.label("DIFFICULTY · APPLIES FROM YOUR NEXT NEW RUN", ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM)
	_kicker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_kicker)
	_add_row(body, "normal", "1", "NORMAL", _on_pick_difficulty.bind("normal"))
	_add_row(body, "hard", "2", "HARD", _on_pick_difficulty.bind("hard"))
	body.add_child(ConsoleStyle.rule(0.22))
	_add_row(body, "endless", "3", "ENDLESS MODE", _on_toggle_endless)
	_add_row(body, "sound", "4", "SOUND", _on_toggle_sound)
	_add_row(body, "motion", "5", "REDUCED MOTION", _on_toggle_motion)
	_note = ConsoleStyle.paragraph(
		"Reduced motion: hold rings become plain fills, the maintenance camera crossfades and the screen never shakes.",
		ConsoleStyle.FONT_TINY, ConsoleStyle.PHOSPHOR_DIM
	)
	body.add_child(_note)
	set_close_label("BACK TO MAINTENANCE")


func _add_row(parent: Node, key: String, index_label: String, headline: String, handler: Callable) -> void:
	var row := ConsoleMenuRow.new()
	row.name = "Setting%s" % key.to_pascal_case()
	row.index_label = index_label
	row.headline = headline
	row.pressed.connect(handler)
	parent.add_child(row)
	_rows[key] = row


func refresh() -> void:
	var current: String = MetaProgress.difficulty()
	_rows["normal"].set_selected(current == "normal")
	_rows["hard"].set_selected(current == "hard")
	var unlocked: bool = MetaProgress.endless_unlocked()
	var endless: ConsoleMenuRow = _rows["endless"]
	endless.visible = unlocked
	if unlocked:
		var on: bool = MetaProgress.endless_enabled()
		endless.value_text = "ON" if on else "OFF"
		endless.set_selected(on)
	_rows["sound"].value_text = "OFF" if MetaProgress.sound_muted() else "ON"
	var motion: bool = UiFx.reduced_motion()
	_rows["motion"].value_text = "ON" if motion else "OFF"
	_rows["motion"].set_selected(motion)
	set_context("SETTINGS · %s" % current.to_upper())
	_layout_rows()


## The current value of one setting, for the playtests: "normal"/"hard",
## true/false.
func setting_value(key: String) -> Variant:
	match key:
		"difficulty":
			return MetaProgress.difficulty()
		"endless":
			return MetaProgress.endless_enabled()
		"sound":
			return not MetaProgress.sound_muted()
		"motion":
			return UiFx.reduced_motion()
	return null


func row(key: String) -> ConsoleMenuRow:
	return _rows.get(key)


func _on_pick_difficulty(difficulty_id: String) -> void:
	MetaProgress.set_difficulty(difficulty_id)
	UiSound.play("tap")
	refresh()


func _on_toggle_endless() -> void:
	MetaProgress.set_endless_enabled(not MetaProgress.endless_enabled())
	UiSound.play("tap")
	refresh()


func _on_toggle_sound() -> void:
	MetaProgress.toggle_sound_muted()
	UiSound.resume()
	UiSound.play("tap")
	refresh()


func _on_toggle_motion() -> void:
	MetaProgress.set_reduced_motion(not UiFx.reduced_motion())
	UiSound.play("tap")
	refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1:
			_on_pick_difficulty("normal")
		KEY_2:
			_on_pick_difficulty("hard")
		KEY_3:
			if MetaProgress.endless_unlocked():
				_on_toggle_endless()
		KEY_4:
			_on_toggle_sound()
		KEY_5:
			_on_toggle_motion()
		_:
			return
	get_viewport().set_input_as_handled()


func _fit_console() -> void:
	super._fit_console()
	_layout_rows()


func _layout_rows() -> void:
	var scale: float = console_scale()
	var font: int = ConsoleMetrics.font_small(scale)
	var height: int = ConsoleMetrics.row_height(scale)
	var pad: int = ConsoleMetrics.pad_h(scale)
	for key in _rows:
		(_rows[key] as ConsoleMenuRow).set_metrics(font, height, pad)
	var tiny: int = ConsoleMetrics.font_tiny(scale)
	for label in [_kicker, _note]:
		if label != null:
			label.add_theme_font_size_override("font_size", tiny)
