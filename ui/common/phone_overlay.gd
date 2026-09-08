class_name PhoneOverlay
extends Control

## A handset held up over the room.
##
## The investor's call is the one overlay that never lived on the phosphor
## console: a dark moulded phone, centred on the glass, with a kicker, a title,
## body copy and a `GameButton` footer. The round-end paper — the perks table,
## the bills, the ship-or-abandon sheet — wants to read the same way, so this
## is that handset as a shell. It answers the same contract `CabinetFlow` relies
## on from `ConsoleOverlay` (`open`, `close`, `hide_overlay`, `closed`,
## `content()`, `set_actions`, `set_closable`, `dismiss_on_scrim`, `max_width`,
## the `flow_overlay` group and the `main_ui.sync_overlay_input` calls), so a
## screen can move off the console without the flow noticing.
##
## The panel grows to fit what is printed on it until the window runs out, then
## the body scrolls. Subclasses that override `_ready` must call `super._ready()`.

## Emitted after the overlay has been dismissed, however it was dismissed.
signal closed

## The investor's handset is 452 wide; every phone in the room is the same
## model unless a screen asks for a bigger one (`max_width`).
const MAX_WIDTH := 452.0
const EDGE_PAD := 16.0
const SCRIM := Color(0.0, 0.0, 0.0, 0.72)
const MARGIN_H := 22
const MARGIN_V := 20
const SECTION_SEPARATION := 12
const BODY_SEPARATION := 8
const FOOTER_SEPARATION := 8
## Footer keys are the phone's own button height rather than the desk's
## `ACTION_TARGET`: the handset is narrower than the side panel and its keys
## should read as part of the object.
const BUTTON_HEIGHT := 62.0

## A handset canvas is only ~300 design pixels tall (`DisplayScale` squeezes it
## until type is legible), and the same shape shows up in a short desktop
## window. Below this height the phone is laid out compactly: tighter margins,
## the footer keys in a row rather than a stack, the full width of the glass —
## otherwise a two-key sheet's chrome alone is taller than the screen and the
## keys are the part that goes.
const COMPACT_HEIGHT := 420.0
const COMPACT_MARGIN_H := 12
const COMPACT_MARGIN_V := 8
const COMPACT_SECTION_SEPARATION := 6
const COMPACT_BODY_SEPARATION := 4
const COMPACT_FOOTER_SEPARATION := 6
const COMPACT_BUTTON_HEIGHT := 44.0

## Whether tapping the dimmed room behind the phone dismisses it. Off for
## overlays that are a decision the player has to actually answer.
var dismiss_on_scrim: bool = true
## The cap `MAX_WIDTH` sets is the width of a handset. A screen that lays cards
## out side by side rather than printing lines can raise it.
var max_width: float = MAX_WIDTH
## Whether the line under the title is dropped on a handset. A pitch that only
## restates the screen can go when height is the thing in short supply; a line
## carrying figures the player needs cannot.
var compact_hides_context: bool = false

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _margin: MarginContainer = null
var _column: VBoxContainer = null
var _header: VBoxContainer = null
var _kicker: Label = null
var _title: Label = null
var _subtitle: Label = null
var _scroll: ScrollContainer = null
var _body: VBoxContainer = null
var _footer: BoxContainer = null
var _close_button: GameButton = null
var _action_buttons: Array[GameButton] = []
var _closable: bool = true
var _fit_queued: bool = false
var _compact: bool = false
var _scrim_tap: TapGesture = TapGesture.new()


func _ready() -> void:
	_ensure_built()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("flow_overlay")
	resized.connect(_request_fit)
	visibility_changed.connect(func() -> void:
		if visible:
			_request_fit()
	)


func _ensure_built() -> void:
	if _panel != null:
		return

	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = SCRIM
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	# Named "Panel" so `UiTransition.enter` finds it without being told.
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", UiThemeBuilder.phone_style())
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_panel)

	_margin = MarginContainer.new()
	_margin.add_theme_constant_override("margin_left", MARGIN_H)
	_margin.add_theme_constant_override("margin_right", MARGIN_H)
	_margin.add_theme_constant_override("margin_top", MARGIN_V)
	_margin.add_theme_constant_override("margin_bottom", MARGIN_V)
	_panel.add_child(_margin)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", SECTION_SEPARATION)
	_margin.add_child(_column)

	_header = VBoxContainer.new()
	_header.add_theme_constant_override("separation", 4)
	_column.add_child(_header)

	# The kicker is the phone's own status line, so it burns in the same
	# phosphor the room's other screens use.
	_kicker = Label.new()
	_kicker.theme_type_variation = &"SectionLabel"
	_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kicker.add_theme_color_override("font_color", ConsoleStyle.PHOSPHOR)
	_kicker.visible = false
	_header.add_child(_kicker)

	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.visible = false
	_header.add_child(_title)

	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"MutedLabel"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.visible = false
	_header.add_child(_subtitle)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(_scroll)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", BODY_SEPARATION)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.minimum_size_changed.connect(_request_fit)
	_scroll.add_child(_body)

	_footer = BoxContainer.new()
	_footer.vertical = true
	_footer.add_theme_constant_override("separation", FOOTER_SEPARATION)
	_column.add_child(_footer)

	_close_button = _make_button("CLOSE", "SecondaryButton", "neutral")
	_close_button.pressed.connect(close)
	_footer.add_child(_close_button)


## The title printed across the top of the screen.
func setup(title: String) -> void:
	_ensure_built()
	_title.text = title
	_title.visible = title != ""
	_request_fit()


## The small line above the title: which screen this is ("HIS TABLE",
## "ROUND 4"). Blank hides it.
func set_kicker(text: String) -> void:
	_ensure_built()
	_kicker.text = text.to_upper()
	_kicker.visible = text != ""
	_request_fit()


## The line under the title, in muted text unless a colour is given. Blank
## hides it. Named to match `ConsoleOverlay.set_context` so screens moving off
## the console keep their call.
func set_context(text: String, color: Color = Color(UiThemeBuilder.TEXT_SECONDARY)) -> void:
	_ensure_built()
	_subtitle.text = text
	_subtitle.visible = text != "" and not (_compact and compact_hides_context)
	_subtitle.add_theme_color_override("font_color", color)
	_request_fit()


## Where a subclass builds its rows, cards and readouts.
func content() -> VBoxContainer:
	_ensure_built()
	return _body


## Footer keys, rebuilt on every call. Each entry is
## `{"headline": "CONTINUE", "pressed": Callable, "destructive": false,
## "secondary": false, "enabled": true, "accent_key": "action",
## "variation": ""}`. The default key is `PrimaryButton`; `destructive` makes
## it a `DangerButton`, `secondary` a `SecondaryButton`, and `variation` names
## the theme variation outright. Entries print in order, so the primary action
## belongs last, at the bottom of the phone.
func set_actions(entries: Array) -> void:
	_ensure_built()
	for button in _action_buttons:
		var parent: Node = button.get_parent()
		if parent != null:
			parent.remove_child(button)
		button.queue_free()
	_action_buttons.clear()
	for entry in entries:
		if not entry is Dictionary:
			continue
		var destructive: bool = bool(entry.get("destructive", false))
		var secondary: bool = bool(entry.get("secondary", false))
		var variation: String = str(entry.get("variation", ""))
		if variation == "":
			if destructive:
				variation = "DangerButton"
			elif secondary:
				variation = "SecondaryButton"
			else:
				variation = "PrimaryButton"
		var accent: String = str(entry.get("accent_key", ""))
		if accent == "":
			accent = "danger" if destructive else ("neutral" if secondary else "action")
		var button: GameButton = _make_button(str(entry.get("headline", "")), variation, accent)
		_style_button(button)
		var enabled: bool = bool(entry.get("enabled", true))
		button.disabled = not enabled
		var handler: Variant = entry.get("pressed", null)
		if enabled and handler is Callable:
			button.pressed.connect(handler)
		_footer.add_child(button)
		_footer.move_child(button, _close_button.get_index())
		_action_buttons.append(button)
	_request_fit()


## Whether the player may leave without answering: shows or hides the CLOSE key
## and arms or disarms `ui_cancel`.
func set_closable(value: bool) -> void:
	_ensure_built()
	_closable = value
	_close_button.visible = value
	_request_fit()


func open() -> void:
	_ensure_built()
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Shown before the refresh, because a screen that only redraws itself while
	# it is on the glass would otherwise open empty.
	UiTransition.enter(self, _panel)
	if has_method("refresh"):
		call("refresh")
	_request_fit()
	get_tree().call_group("main_ui", "sync_overlay_input")


func close() -> void:
	hide_overlay()
	get_tree().call_group("main_ui", "refresh_all")


## The `flow_overlay` group contract: returning to the title dismisses every
## overlay through this, without refreshing the run behind it.
func hide_overlay() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_inside_tree():
		get_tree().call_group("main_ui", "sync_overlay_input")
	closed.emit()


## Whether the phone is on its handset layout.
func is_compact() -> bool:
	return _compact


## Re-measures the phone against the window. Called by the shell's own hooks;
## a subclass whose content changes size without going through `content()` can
## call it too.
func fit_phone() -> void:
	_fit_phone()


func _on_backdrop_input(event: InputEvent) -> void:
	if dismiss_on_scrim and _scrim_tap.feed(event):
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _closable:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _make_button(headline: String, variation: String, accent: String) -> GameButton:
	var button := GameButton.new()
	button.theme_type_variation = StringName(variation)
	button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.allow_wide = true
	button.accent_key = accent
	button.set_lines(headline, "")
	return button


## Layout is settled once per frame at most, however many rows were added.
func _request_fit() -> void:
	if _fit_queued or _panel == null:
		return
	_fit_queued = true
	call_deferred("_fit_phone")


func _fit_phone() -> void:
	_fit_queued = false
	if _panel == null:
		return
	var area: Vector2 = _window()
	if area.x <= 1.0 or area.y <= 1.0:
		return
	_apply_metrics(area.y < COMPACT_HEIGHT)
	# Centred on the glass and inset from every edge, so the room stays visible
	# around it and the phone reads as something held up in front of the desk.
	# A handset has no room to spare in either direction, so there the phone
	# takes the whole width and lets the height decide what scrolls.
	var width: float = area.x - EDGE_PAD * 2.0
	if not _compact:
		width = minf(width, max_width)
	var limit: float = area.y - EDGE_PAD * 2.0
	# The scroll view reports no height of its own, so the phone's natural
	# height is its chrome plus whatever is printed in the body; past the window
	# the body gives way and scrolls.
	var chrome: float = _panel.get_combined_minimum_size().y
	var body: float = _body.get_combined_minimum_size().y
	var height: float = clampf(chrome + body, 0.0, limit)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	_panel.offset_top = -height * 0.5
	_panel.offset_bottom = height * 0.5


## Switches the chrome between the handset's tight layout and the desktop's.
## Idempotent, so it can run on every fit.
func _apply_metrics(compact: bool) -> void:
	if compact == _compact and _footer.has_meta("phone_metrics"):
		return
	_compact = compact
	_footer.set_meta("phone_metrics", true)
	_margin.add_theme_constant_override("margin_left", COMPACT_MARGIN_H if compact else MARGIN_H)
	_margin.add_theme_constant_override("margin_right", COMPACT_MARGIN_H if compact else MARGIN_H)
	_margin.add_theme_constant_override("margin_top", COMPACT_MARGIN_V if compact else MARGIN_V)
	_margin.add_theme_constant_override("margin_bottom", COMPACT_MARGIN_V if compact else MARGIN_V)
	_column.add_theme_constant_override("separation", COMPACT_SECTION_SEPARATION if compact else SECTION_SEPARATION)
	_header.add_theme_constant_override("separation", 2 if compact else 4)
	_body.add_theme_constant_override("separation", COMPACT_BODY_SEPARATION if compact else BODY_SEPARATION)
	_footer.add_theme_constant_override("separation", COMPACT_FOOTER_SEPARATION if compact else FOOTER_SEPARATION)
	# Keys stack on a desktop phone; on a handset they share one row, because a
	# stack of three is the height of the whole screen.
	_footer.vertical = not compact
	_subtitle.visible = _subtitle.text != "" and not (compact and compact_hides_context)
	_style_button(_close_button)
	for button in _action_buttons:
		_style_button(button)


func _style_button(button: GameButton) -> void:
	button.compact = _compact
	button.set_min_height(COMPACT_BUTTON_HEIGHT if _compact else BUTTON_HEIGHT)


## The overlay is always the whole window, but it is often built and mounted in
## the same frame its host is, before the layout pass has given it a rect. The
## parent's area — and failing that the viewport — is the size it is going to
## end up at anyway.
func _window() -> Vector2:
	if size.x > 1.0 and size.y > 1.0:
		return size
	var parent_area: Vector2 = get_parent_area_size()
	if parent_area.x > 1.0 and parent_area.y > 1.0:
		return parent_area
	return get_viewport_rect().size
