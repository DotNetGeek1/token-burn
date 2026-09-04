class_name AbortLever
extends Control

## The red lever on the left of the cabinet, made to pull. The kit paints it in
## two parts: the riveted channel plate with its slot knocked out, fitted to the
## rail by height (the plate's brackets crop at a narrow rail — the slot and its
## tick marks are what has to show), and the handle, which slides down inside
## the slot on a pull so it never stops looking like part of the machine.
##
## During a burn a pull is KILL; between prompts it is ABANDON (through the
## shell's confirmation), and with nothing on the bench it does nothing but
## thunk.
##
## Both armed actions throw work away, so the pull is a hold: the handle rides
## down the slot with the finger and a progress bar fills along the channel;
## letting go early, leaving the rail or losing focus puts the handle back
## without firing. `pulled` fires once, when the hold completes. With nothing
## armed a tap still thunks the handle (no hold, no `pulled`).

signal pulled
## The hold in progress, 0..1; 0 when it is let go.
signal hold_progress(ratio: float)

## The slot in the channel plate as a fraction of the plate, mirrored from the
## catalog's `cabinet_v2.lever.channel_slot`; the layout profile may override.
const DEFAULT_CHANNEL_SLOT := Rect2(0.431, 0.072, 0.135, 0.855)
## How long a destructive pull has to be held.
const HOLD_SECONDS := HoldGesture.DEFAULT_SECONDS

var _channel_art: TextureRect = null
var _handle: TextureRect = null
var _legend: PanelContainer = null
var _tag: Label = null
var _progress: HoldBar = null
var _channel: Rect2 = Rect2()
var _handle_rect: Rect2 = Rect2()
var _pulling: bool = false
var _tap := TapGesture.new()
var _hold := HoldGesture.new(HOLD_SECONDS)
var _armed: String = ""
var _tuning: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = true
	_channel_art = TextureRect.new()
	_channel_art.name = "Channel"
	_channel_art.texture = AssetCatalog.cabinet_v2_texture("lever_channel")
	_channel_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_channel_art.stretch_mode = TextureRect.STRETCH_SCALE
	_channel_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_channel_art)
	_handle = TextureRect.new()
	_handle.name = "Handle"
	_handle.texture = AssetCatalog.cabinet_v2_texture("lever_handle")
	_handle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_handle.stretch_mode = TextureRect.STRETCH_SCALE
	_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_handle)
	# The legend plate under the channel: what a pull does right now, engraved
	# on a small plate.
	_legend = PanelContainer.new()
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.add_theme_stylebox_override("panel", CabinetStyle.legend_plate())
	add_child(_legend)
	_tag = CabinetStyle.caption("", CabinetStyle.FONT_TINY, CabinetStyle.AMBER)
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_legend.add_child(_tag)
	_progress = HoldBar.new()
	_progress.name = "HoldBar"
	_progress.visible = false
	add_child(_progress)
	_hold.progress_changed.connect(_on_hold_progress)
	_hold.completed.connect(_on_hold_completed)
	focus_mode = Control.FOCUS_ALL
	gui_input.connect(_on_input)
	mouse_exited.connect(_release_hold)
	focus_exited.connect(_release_hold)
	resized.connect(_fit)
	set_process(false)
	_fit()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_release_hold()


## The lever's tuning table from the layout profiles (`lever`), so the shell can
## hand it over without the lever reading the profiles itself.
func set_tuning(tuning: Dictionary) -> void:
	_tuning = tuning
	_fit()


## Fits the channel and handle to the rail this control has been given.
func _fit() -> void:
	if _channel_art == null or size.x <= 0.0 or size.y <= 0.0:
		return
	if _pulling or _hold.is_holding():
		return
	var texture: Texture2D = _channel_art.texture
	var texture_size: Vector2 = texture.get_size() if texture != null else Vector2(585, 1040)
	var legend_h: float = clampf(size.y * float(_tuning.get("legend_of_height", 0.09)), 14.0, 28.0)
	var channel_h: float = maxf(1.0, size.y * float(_tuning.get("channel_of_height", 0.86)))
	channel_h = minf(channel_h, size.y - legend_h - 4.0)
	var channel_w: float = channel_h * texture_size.x / maxf(1.0, texture_size.y)
	var channel_pos := Vector2((size.x - channel_w) * 0.5, 0.0)
	_channel_art.position = channel_pos
	_channel_art.size = Vector2(channel_w, channel_h)
	var slot_fraction: Rect2 = DEFAULT_CHANNEL_SLOT
	if _tuning.has("channel_slot") and Array(_tuning["channel_slot"]).size() >= 4:
		var raw: Array = _tuning["channel_slot"]
		slot_fraction = Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
	_channel = Rect2(channel_pos + slot_fraction.position * _channel_art.size, slot_fraction.size * _channel_art.size)
	# The handle's grip is a fraction of its square canvas; size the canvas so
	# the grip reads a little wider than the slot it rides in.
	var grip_of_canvas: float = clampf(float(_tuning.get("handle_grip_of_canvas", 0.34)), 0.1, 1.0)
	var grip_w: float = _channel.size.x * float(_tuning.get("handle_of_slot_width", 1.6))
	var canvas: float = minf(grip_w / grip_of_canvas, _channel.size.y * 0.6)
	_handle_rect = Rect2(Vector2(_channel.get_center().x - canvas * 0.5, _channel.position.y), Vector2(canvas, canvas))
	_handle.position = _handle_rect.position
	_handle.size = _handle_rect.size
	_legend.position = Vector2(0.0, size.y - legend_h)
	_legend.size = Vector2(size.x, legend_h)
	_tag.add_theme_font_size_override("font_size", clampi(int(legend_h * 0.5), 8, 13))
	_fit_progress()


## The hold bar runs up the channel's edge, the height of the slot.
func _fit_progress() -> void:
	if _progress == null:
		return
	var bar_w: float = clampf(_channel.size.x * 0.35, 4.0, 10.0)
	_progress.position = Vector2(_channel.end.x + bar_w * 0.6, _channel.position.y)
	_progress.size = Vector2(bar_w, _channel.size.y)
	_progress.queue_redraw()


## What a pull would do right now, engraved on the plate under the channel:
## KILL in red, ABANDON in brass, or a blank plate when there is nothing to pull for.
func set_armed(action: String) -> void:
	_armed = action
	_tag.text = action.to_upper()
	_tag.add_theme_color_override("font_color", CabinetStyle.RED if action == "KILL" else CabinetStyle.AMBER)
	tooltip_text = {
		"KILL": "Hold to kill the batch after the current stage.",
		"ABANDON": "Hold to abandon the contract on the bench.",
	}.get(action, "Nothing to abort.")
	if action == "":
		_release_hold()


## What a pull does right now: "KILL", "ABANDON" or "".
func armed_action() -> String:
	return _armed


## Whether a pull needs to be held: it does whenever it would do anything.
func requires_hold() -> bool:
	return _armed != ""


func is_holding() -> bool:
	return _hold.is_holding()


func hold_ratio() -> float:
	return _hold.progress()


func _on_input(event: InputEvent) -> void:
	if _armed == "":
		# Nothing to abort: a tap still thunks the handle, as it always did.
		if _tap.feed(event):
			pull()
			accept_event()
		return
	var press: bool = false
	var release: bool = false
	if event is InputEventScreenTouch:
		press = event.pressed
		release = not event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		press = event.pressed
		release = not event.pressed
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		press = true
	elif event.is_action_released("ui_accept"):
		release = true
	if press:
		grab_focus()
		begin_hold()
		accept_event()
	elif release:
		_release_hold()
		accept_event()


## Starts the hold: the handle sinks with the clock and the bar fills. For
## the playtests as much as the finger; a completed hold emits `pulled`.
func begin_hold() -> void:
	if _armed == "" or _pulling or _hold.is_holding():
		return
	_hold.reset()
	_hold.begin()
	_progress.visible = true
	_progress.set_look(_armed == "KILL")
	UiSound.play("tap")
	set_process(true)


## Lets an unfinished hold go: the handle rides back up, nothing fires.
func _release_hold() -> void:
	if not _hold.is_holding():
		return
	_hold.cancel()
	_hold.reset()
	set_process(false)
	_progress.visible = false
	_progress.ratio = 0.0
	hold_progress.emit(0.0)
	if not _pulling and _handle != null:
		var tween: Tween = create_tween()
		tween.tween_property(_handle, "position:y", _handle_rect.position.y, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _process(delta: float) -> void:
	if not _hold.is_holding():
		set_process(false)
		return
	if not is_visible_in_tree() or _armed == "":
		_release_hold()
		return
	_hold.tick(delta)


func _on_hold_progress(ratio: float) -> void:
	if not _hold.is_holding() and ratio < 1.0:
		return
	# The handle follows the hold down the slot.
	var travel: float = maxf(0.0, _channel.size.y - _handle_rect.size.y)
	_handle.position.y = _handle_rect.position.y + travel * ratio
	_progress.ratio = ratio
	_progress.queue_redraw()
	hold_progress.emit(ratio)


func _on_hold_completed() -> void:
	set_process(false)
	_progress.visible = false
	_progress.ratio = 0.0
	_pulling = true
	UiSound.play("alarm" if _armed == "KILL" else "tap")
	pulled.emit()
	var tween: Tween = create_tween()
	tween.tween_interval(0.18)
	tween.tween_property(_handle, "position:y", _handle_rect.position.y, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func() -> void:
		_pulling = false
		_hold.reset()
		_fit()
	)


## The full pull in one go: the handle travels, `pulled` fires when it lands,
## the handle comes back. What a completed hold does, and what a tap does when
## nothing is armed (without the `pulled`).
func pull() -> void:
	if _pulling:
		return
	_pulling = true
	_release_hold()
	UiSound.play("alarm" if _armed == "KILL" else "tap")
	var travel: float = maxf(0.0, _channel.size.y - _handle_rect.size.y)
	var tween: Tween = create_tween()
	tween.tween_property(_handle, "position:y", _handle_rect.position.y + travel, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	if _armed != "":
		tween.tween_callback(func() -> void: pulled.emit())
	tween.tween_interval(0.18)
	tween.tween_property(_handle, "position:y", _handle_rect.position.y, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func() -> void:
		_pulling = false
		_fit()
	)


## The bar beside the slot: a dark track, filled bottom-up as the hold runs.
## Under reduced motion it is the same plain fill; there is no ring to lose.
class HoldBar extends Control:
	var ratio: float = 0.0
	var danger: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_look(is_danger: bool) -> void:
		danger = is_danger
		queue_redraw()

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var track := Rect2(Vector2.ZERO, size)
		draw_rect(track, Color(0.0, 0.0, 0.0, 0.7))
		var fill_h: float = size.y * clampf(ratio, 0.0, 1.0)
		var fill := Rect2(Vector2(0.0, size.y - fill_h), Vector2(size.x, fill_h))
		draw_rect(fill, CabinetStyle.RED if danger else CabinetStyle.AMBER)
		draw_rect(track, Color(CabinetStyle.AMBER.r, CabinetStyle.AMBER.g, CabinetStyle.AMBER.b, 0.7), false, 1.0)
