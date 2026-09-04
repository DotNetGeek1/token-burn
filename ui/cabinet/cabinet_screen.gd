class_name CabinetScreen
extends PanelContainer

## The wide central CRT. Every place the player used to walk to — the job board,
## the market, the perk workshop, the module bin — is a tab on this one piece of
## glass now, with the run overview as the default.

signal tab_changed(key: String)
## The live tab's selection moved; the shell re-reads the primary action.
signal action_changed
## The SKIP key in the glass's corner was pressed.
signal skip_pressed
## The MAINT key at the end of the tab strip was pressed.
signal maintenance_pressed

## The maintenance key's face. Plain text so it needs no art and so the
## playtest driver finds it by its word; its colour, not a glyph, marks it as
## a door rather than a tab.
const MAINT_LABEL := "MAINT"

var _strip: HBoxContainer = null
var _host: Control = null
var _tabs: Dictionary = {}
var _buttons: Dictionary = {}
var _active: String = ""
var _hint: Label = null
var _skip: Button = null
var _maint: Button = null


func _ready() -> void:
	add_theme_stylebox_override("panel", CabinetStyle.glass_box(0.9))
	clip_contents = true
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_theme_constant_override("separation", 0)
	column.add_child(head)
	_strip = HBoxContainer.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_PASS
	_strip.add_theme_constant_override("separation", 0)
	_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_strip)
	_hint = CabinetStyle.mono("", CabinetStyle.FONT_TINY, CabinetStyle.PHOSPHOR_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_hint)
	# SKIP: only on the glass while a burn is playing back and can be jumped
	# to its result. Sits in the top right, where the hint is, so it is never
	# mistaken for a tab.
	_skip = CabinetStyle.key("SKIP", CabinetStyle.AMBER, CabinetStyle.FONT_TINY)
	_skip.name = "SkipKey"
	_skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_skip.tooltip_text = "Jump the playback to its result. The batch still commits in full."
	_skip.visible = false
	_skip.pressed.connect(func() -> void:
		UiSound.play("tap")
		skip_pressed.emit()
	)
	head.add_child(_skip)
	# MAINT: the way into the maintenance view, the last entry in the strip. A
	# door rather than a tab: pressing it never changes which screen is active.
	_maint = CabinetStyle.tab(MAINT_LABEL)
	_maint.name = "MaintKey"
	_maint.add_theme_color_override("font_color", CabinetStyle.AMBER_DIM)
	_maint.add_theme_color_override("font_focus_color", CabinetStyle.AMBER_DIM)
	_maint.tooltip_text = "Maintenance: settings, help, records, save & quit."
	_maint.pressed.connect(func() -> void:
		UiSound.play("tap")
		maintenance_pressed.emit()
	)
	head.add_child(_maint)
	column.add_child(CabinetStyle.rule(CabinetStyle.AMBER, 0.3))
	_host = Control.new()
	_host.mouse_filter = Control.MOUSE_FILTER_PASS
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host.clip_contents = true
	column.add_child(_host)
	add_child(CabinetStyle.crt_overlay(0.16))


func add_tab(tab: CabinetTab) -> void:
	var key: String = tab.tab_key()
	_tabs[key] = tab
	tab.visible = false
	_host.add_child(tab)
	tab.changed.connect(func() -> void:
		if key == _active:
			action_changed.emit()
	)
	var button: Button = CabinetStyle.tab(tab.tab_title())
	button.pressed.connect(func() -> void:
		UiSound.play("tap")
		show_tab(key)
	)
	_strip.add_child(button)
	_buttons[key] = button


## A tab-strip entry that is a door rather than a screen (HELP, say). MENU is
## not one any more: the MAINT key at the end of the strip is the way out.
func add_door(title: String, pressed: Callable) -> void:
	var button: Button = CabinetStyle.tab(title)
	button.pressed.connect(func() -> void:
		UiSound.play("tap")
		pressed.call()
	)
	_strip.add_child(button)


## Shows or hides the SKIP key in the corner of the glass.
func set_skippable(skippable: bool) -> void:
	_skip.visible = skippable
	_hint.visible = not skippable


func is_skip_visible() -> bool:
	return _skip.visible


func skip_key() -> Button:
	return _skip


func maintenance_key() -> Button:
	return _maint


func has_tab(key: String) -> bool:
	return _tabs.has(key)


func show_tab(key: String) -> void:
	if not _tabs.has(key):
		return
	_active = key
	for other in _tabs:
		var tab: CabinetTab = _tabs[other]
		tab.visible = other == key
		CabinetStyle.set_tab_active(_buttons[other], other == key)
	(_tabs[key] as CabinetTab).activated()
	tab_changed.emit(key)
	action_changed.emit()


func active_key() -> String:
	return _active


func active_tab() -> CabinetTab:
	return _tabs.get(_active)


func tab(key: String) -> CabinetTab:
	return _tabs.get(key)


func refresh() -> void:
	for key in _tabs:
		var tab: CabinetTab = _tabs[key]
		if tab.visible:
			tab.refresh()


## The line in the top right of the glass: the round, the phase.
func set_hint(text: String, color: Color = CabinetStyle.PHOSPHOR_DIM) -> void:
	_hint.text = text.to_upper()
	_hint.add_theme_color_override("font_color", color)
