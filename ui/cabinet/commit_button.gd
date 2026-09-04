class_name CommitButton
extends Button

## The commit control: the one physical button under the glass that commits
## whatever the active tab is for. It is contextual — the tab's
## `primary_action()` decides the word on its face (BURN on the run, ACCEPT on
## the contracts, BUY in the market, SEAT in the modules) and how it fires; the
## button itself only knows how to show a face, a word, a sub-line and take a
## press or a hold.
##
## Five states, each with its own face from the kit (960x400 on alpha):
##
##   idle     shutter down, low contrast, "SELECT ITEM" (or the tab's own
##            nothing-picked blocker); disabled.
##   armed    red glass lit, the verb and its consequence; one press fires.
##   danger   hazard face with a striped frame and a "HOLD" cue; the press
##            must be held `hold_seconds` while a ring fills, and lets go
##            cleanly on release, pointer exit, focus loss or window unfocus.
##            Fires once, when the ring closes.
##   busy     the batch is in flight: busy face, "WORKING", disabled. Never
##            skips — skipping the playback belongs to the CRT.
##   blocked  dark face and the reason a pick cannot be acted on
##            ("NEED $240 MORE", "MARKET CLOSED"); disabled.
##
## The shell listens to `committed`, not the Button's `pressed`: a Button
## fires `pressed` on release, and a danger action must fire when the hold
## completes and never on the release after it. A real Button underneath — the
## word is drawn by a Label on its face, but the press, the disabled state and
## the focus all belong to the button, so the playtest driver, a keyboard and a
## controller find it the same way a finger does (`ui_accept` held while
## focused is a hold).

## Fires once when an armed action is pressed or a danger hold completes.
signal committed
## The state changed: one of the STATE_* strings.
signal state_changed(state: String)
## A hold is in progress: 0..1. Emits 0 when a hold is cancelled.
signal hold_progress(ratio: float)

const STATE_IDLE := "idle"
const STATE_ARMED := "armed"
const STATE_DANGER := "danger"
const STATE_BUSY := "busy"
const STATE_BLOCKED := "blocked"

const BUSY_LABEL := "WORKING"
const HOLD_CUE := "HOLD"

## The housing's aspect on its canvas (960x400 with ~815 px of housing).
const FACE_CANVAS_ASPECT := 2.4
## The housing as a fraction of the canvas width, so the lettering sits on it.
const HOUSING_OF_CANVAS := 0.85

var _face: TextureRect = null
var _label: Label = null
var _sub: Label = null
var _overlay: Overlay = null
var _tween: Tween = null
var _faces: Dictionary = {}

var _state: String = STATE_IDLE
var _action: Dictionary = {}
var _busy: bool = false
var _hold: HoldGesture = null
var _fired: bool = false
var _delegated: bool = false


func _ready() -> void:
	text = ""
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var clear := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		add_theme_stylebox_override(state, clear)
	for face in ["armed", "idle", "danger", "busy"]:
		_faces[face] = AssetCatalog.cabinet_commit_texture(face)
	_face = TextureRect.new()
	_face.name = "Face"
	_face.texture = _faces["idle"]
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.visible = _face.texture != null
	add_child(_face)
	# The word and the sub-line are the first two Labels under the button, in
	# that order: the playtests read them that way.
	_label = Label.new()
	_label.name = "Word"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font: Font = UiThemeBuilder.header_font()
	if font != null:
		_label.add_theme_font_override("font", font)
	# Printed on the glass: pale lettering with the shadow it casts into the red,
	# rather than a glow floating above it.
	_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.80))
	_label.add_theme_color_override("font_shadow_color", Color(0.18, 0.0, 0.0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.add_theme_constant_override("shadow_outline_size", 1)
	_label.add_theme_constant_override("outline_size", 0)
	add_child(_label)
	_sub = CabinetStyle.mono("", CabinetStyle.FONT_TINY, Color(1.0, 0.82, 0.72, 0.85))
	_sub.name = "Sub"
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub.add_theme_color_override("font_shadow_color", Color(0.15, 0.0, 0.0, 0.8))
	_sub.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_sub)
	_overlay = Overlay.new()
	_overlay.name = "Overlay"
	add_child(_overlay)
	_hold = HoldGesture.new()
	_hold.completed.connect(_on_hold_completed)
	_hold.progress_changed.connect(_on_hold_progress)
	button_down.connect(_press_down)
	button_up.connect(_release)
	pressed.connect(_on_button_pressed)
	mouse_exited.connect(_cancel_hold)
	focus_exited.connect(_on_focus_changed)
	focus_entered.connect(_on_focus_changed)
	resized.connect(_layout)
	set_process(false)
	_layout()
	_apply()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_VISIBILITY_CHANGED:
			if what != NOTIFICATION_VISIBILITY_CHANGED or not is_visible_in_tree():
				_cancel_hold()


## The face fills the button; the lettering sits on the housing, which is a
## little narrower than the face's canvas.
func _layout() -> void:
	if _face == null or size.x <= 0.0 or size.y <= 0.0:
		return
	_face.position = Vector2.ZERO
	_face.size = size
	var face: Rect2 = _face_rect()
	var housing_w: float = face.size.x * HOUSING_OF_CANVAS
	var glass := Rect2(
		Vector2(face.position.x + (face.size.x - housing_w) * 0.5, face.position.y + face.size.y * 0.12),
		Vector2(housing_w, face.size.y * 0.76)
	)
	_label.position = glass.position
	_label.size = Vector2(glass.size.x, glass.size.y * 0.66)
	_label.pivot_offset = _label.size * 0.5
	_fit_label()
	# The sub may run the full width of the housing: it is one short line of
	# small type, and the other tabs' subs already sit out to the housing edge.
	_sub.position = Vector2(glass.position.x, glass.position.y + glass.size.y * 0.66)
	_sub.size = Vector2(glass.size.x, glass.size.y * 0.32)
	_fit_sub()
	_overlay.position = Vector2.ZERO
	_overlay.size = size
	_overlay.glass = glass
	_overlay.queue_redraw()


## Where the face art actually lands inside the button: the texture keeps its
## canvas aspect and centres (STRETCH_KEEP_ASPECT_CENTERED), so a button wider
## or taller than the canvas leaves empty margins the lettering must not use.
func _face_rect() -> Rect2:
	var aspect: float = FACE_CANVAS_ASPECT
	var texture: Texture2D = _face.texture if _face != null else null
	if texture != null and texture.get_height() > 0:
		aspect = float(texture.get_width()) / float(texture.get_height())
	var drawn_h: float = minf(size.y, size.x / aspect)
	var drawn := Vector2(drawn_h * aspect, drawn_h)
	return Rect2((size - drawn) * 0.5, drawn)


## The word wants 22–30 px at the baseline deck; a long one (BURN AGAIN) is let
## down in size until it fits the housing rather than clipped at its edge. Tall
## glyphs are fitted against the glass height too, so the word never spills off
## the housing when the button is narrower than the face's canvas.
func _fit_label() -> void:
	if _label == null or _label.size.x <= 0.0 or _label.size.y <= 0.0:
		return
	var target: int = clampi(int(_label.size.y * 0.80), 14, 44)
	var font: Font = _label.get_theme_font("font")
	var fitted: int = target
	if font != null and _label.text != "":
		while fitted > 12 and (
			font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fitted).x > _label.size.x * 0.96
			or font.get_height(fitted) > _label.size.y
		):
			fitted -= 1
	_label.add_theme_font_size_override("font_size", fitted)


## The sub line (`$1.5K · LEFT $18.5K`) is let down one step at a time, to a
## floor under the body minimum, before it is allowed to elide; a price cut off
## at `$1...` reads as a different number. The floor is 8: below that the line
## is not legible at all, and a long sub eliding its tail (`... · OPENS THE R…`)
## still leads with what matters.
func _fit_sub() -> void:
	if _sub == null or _sub.size.x <= 0.0 or _sub.size.y <= 0.0:
		return
	var target: int = clampi(int(_sub.size.y * 0.8), 8, 14)
	var font: Font = _sub.get_theme_font("font")
	var fitted: int = target
	if font != null and _sub.text != "":
		while fitted > 8 and font.get_string_size(_sub.text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fitted).x > _sub.size.x * 0.98:
			fitted -= 1
	_sub.add_theme_font_size_override("font_size", fitted)


# --- State -------------------------------------------------------------------

## Takes a tab's `primary_action()` (any shape; normalised here) and shows it.
## An empty dictionary is the idle shutter. Busy, once latched, stays on top
## until `set_busy(false)`; the action is kept and shown again then.
func set_state(action: Dictionary) -> void:
	_action = CabinetTab.normalize_action(action)
	_apply()


## The batch is in flight: the busy face and WORKING until it is not.
func set_busy(busy: bool) -> void:
	if _busy == busy:
		return
	_busy = busy
	_apply()


func is_busy() -> bool:
	return _busy


## One of the STATE_* strings.
func state() -> String:
	return _state


## The normalised action being shown.
func action() -> Dictionary:
	return _action.duplicate()


## Thin wrapper on `set_state` for callers with only a word, a flag and a
## line (the shell's own BURN).
func set_action(label_text: String, enabled: bool, sub: String = "") -> void:
	set_state({"label": label_text, "enabled": enabled, "sub": sub, "pressed": Callable()})


func is_enabled() -> bool:
	return not disabled


## Whether the commit that just fired ran a tab's own `pressed` callable. A
## listener on `committed` reads this to tell a tab's action from the shell's
## bare BURN, because the action may already have moved the glass to another
## tab by the time the signal arrives (ACCEPT lands on the run tab).
func last_commit_delegated() -> bool:
	return _delegated


## Whether the current state fires on a completed hold rather than a press.
func requires_hold() -> bool:
	return _state == STATE_DANGER


func hold_seconds() -> float:
	return float(_action.get("hold_seconds", CabinetTab.DEFAULT_HOLD_SECONDS))


## 0..1 while a hold is in progress.
func hold_ratio() -> float:
	return _hold.progress() if _hold != null else 0.0


func is_holding() -> bool:
	return _hold != null and _hold.is_holding()


func _resolve_state() -> String:
	if _busy:
		return STATE_BUSY
	if _action.is_empty():
		return STATE_IDLE
	if not bool(_action.get("enabled", false)):
		var reason: String = str(_action.get("sub", "")).strip_edges().to_upper()
		if reason == "" or reason in CabinetTab.SELECTION_BLOCKERS:
			return STATE_IDLE
		return STATE_BLOCKED
	if str(_action.get("tone", CabinetTab.TONE_NORMAL)) == CabinetTab.TONE_DANGER \
			or str(_action.get("confirm", CabinetTab.CONFIRM_PRESS)) == CabinetTab.CONFIRM_HOLD:
		return STATE_DANGER
	return STATE_ARMED


func _apply() -> void:
	if _label == null:
		return
	var next: String = _resolve_state()
	if next != _state or _hold.is_holding():
		_cancel_hold()
	var was: String = _state
	_state = next
	_fired = false
	var word: String = str(_action.get("label", "")).to_upper()
	var sub: String = str(_action.get("sub", ""))
	var face_key: String = "idle"
	var face_tint: Color = Color.WHITE
	var word_alpha: float = 1.0
	var sub_alpha: float = 1.0
	match _state:
		STATE_IDLE:
			if word == "":
				word = CabinetTab.BLOCK_SELECT_ITEM
			if sub.strip_edges() == "":
				sub = CabinetTab.BLOCK_SELECT_ITEM
			word_alpha = 0.55
			sub_alpha = 0.6
		STATE_BLOCKED:
			face_tint = Color(0.55, 0.55, 0.55)
			word_alpha = 0.7
			sub_alpha = 0.9
		STATE_ARMED:
			face_key = "armed"
		STATE_DANGER:
			face_key = "danger"
			sub = ("%s · %s" % [HOLD_CUE, sub]) if sub.strip_edges() != "" else HOLD_CUE
		STATE_BUSY:
			face_key = "busy"
			word = BUSY_LABEL
			sub = "BATCH IN FLIGHT"
			sub_alpha = 0.85
	_label.text = word
	_sub.text = sub
	_fit_label()
	_fit_sub()
	var enabled: bool = _state == STATE_ARMED or _state == STATE_DANGER
	disabled = not enabled
	var texture: Texture2D = _faces.get(face_key)
	if texture == null:
		texture = _faces.get("armed" if enabled else "idle")
	_face.texture = texture
	_face.visible = texture != null
	_face.modulate = face_tint
	_label.modulate = Color(1, 1, 1, word_alpha)
	_sub.modulate = Color(1, 1, 1, sub_alpha)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	_overlay.hazard = _state == STATE_DANGER
	_overlay.focused = has_focus()
	_overlay.ratio = 0.0
	_overlay.queue_redraw()
	if was != _state:
		state_changed.emit(_state)


# --- Press and hold -----------------------------------------------------------

## The letters sink into the glass while the button is held; a danger action
## also starts its hold here.
func _press_down() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_label.scale = Vector2(0.96, 0.96)
	_label.modulate = Color(0.85, 0.75, 0.68, _label.modulate.a)
	if _state == STATE_DANGER and not disabled:
		_fired = false
		_hold.reset()
		_hold.seconds = hold_seconds()
		_hold.begin()
		set_process(true)


func _release() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_label, "scale", Vector2.ONE, 0.18)
	_tween.tween_property(_label, "modulate", Color(1, 1, 1, _label.modulate.a), 0.18)
	_cancel_hold()


## A Button fires `pressed` on release. For an armed action that is the
## commit; for a danger action the hold already decided, so it is nothing.
func _on_button_pressed() -> void:
	if disabled:
		return
	if _state == STATE_ARMED:
		_fire()


func _process(delta: float) -> void:
	if not _hold.is_holding():
		set_process(false)
		return
	# A hold is only honoured while the press (mouse, touch or ui_accept) is
	# still down on an enabled danger button. Pointer exit and focus loss
	# cancel through their own signals.
	if not is_visible_in_tree() or disabled or _state != STATE_DANGER or not is_pressed():
		_cancel_hold()
		return
	_hold.tick(delta)


func _on_hold_progress(ratio: float) -> void:
	_overlay.ratio = ratio
	_overlay.queue_redraw()
	hold_progress.emit(ratio)


func _on_hold_completed() -> void:
	set_process(false)
	_overlay.ratio = 1.0
	_overlay.queue_redraw()
	_fire()


func _cancel_hold() -> void:
	if _hold == null:
		return
	var was_holding: bool = _hold.is_holding()
	_hold.cancel()
	_hold.reset()
	set_process(false)
	if _overlay != null and (was_holding or _overlay.ratio != 0.0):
		_overlay.ratio = 0.0
		_overlay.queue_redraw()
	if was_holding:
		hold_progress.emit(0.0)


func _fire() -> void:
	if _fired:
		return
	_fired = true
	var callback: Variant = _action.get("pressed")
	# The tab's own handler first, so a listener on `committed` reads the
	# state the action left behind.
	_delegated = callback is Callable and (callback as Callable).is_valid()
	if _delegated:
		(callback as Callable).call()
	committed.emit()
	# The next press is a fresh commit unless the shell re-arms first.
	_fired = false


func _on_focus_changed() -> void:
	if not has_focus():
		_cancel_hold()
	if _overlay != null:
		_overlay.focused = has_focus()
		_overlay.queue_redraw()


## Lights the lettering for a beat, for anything the cabinet wants to shout about.
func flash() -> void:
	_label.modulate = Color(1.6, 1.4, 1.2, 1.0)
	var tween: Tween = create_tween()
	tween.tween_property(_label, "modulate", Color(1, 1, 1, 1.0 if not disabled else 0.55), 0.35)


## What sits over the face: the hazard frame on a danger action, the hold ring
## (a plain fill under reduced motion) while a hold runs, and the focus ring
## whenever the button has keyboard focus. All drawn, none of it a texture, so
## it scales with whatever deck the layout hands the button.
class Overlay extends Control:
	var glass: Rect2 = Rect2()
	var hazard: bool = false
	var focused: bool = false
	var ratio: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if glass.size.x <= 0.0 or glass.size.y <= 0.0:
			return
		if hazard:
			_draw_hazard()
		if ratio > 0.0:
			if UiFx.reduced_motion():
				_draw_fill()
			else:
				_draw_ring()
		if focused:
			var focus_rect: Rect2 = glass.grow(3.0)
			draw_rect(focus_rect, Color(CabinetStyle.AMBER.r, CabinetStyle.AMBER.g, CabinetStyle.AMBER.b, 0.95), false, 2.0)
			draw_rect(focus_rect.grow(2.0), Color(0.0, 0.0, 0.0, 0.6), false, 1.0)

	## Amber and black chevrons around the housing: danger without relying on
	## the red of the glass.
	func _draw_hazard() -> void:
		var rect: Rect2 = glass.grow(1.0)
		var width: float = maxf(3.0, glass.size.y * 0.06)
		draw_rect(rect, CabinetStyle.AMBER, false, width)
		var dash: float = maxf(6.0, width * 2.2)
		var dark := Color(0.06, 0.05, 0.04, 0.95)
		var half: float = width * 0.5
		# Top and bottom runs.
		for edge_y in [rect.position.y + half, rect.end.y - half]:
			var x: float = rect.position.x
			var on: bool = false
			while x < rect.end.x:
				var x2: float = minf(x + dash, rect.end.x)
				if on:
					draw_line(Vector2(x, edge_y), Vector2(x2, edge_y), dark, width)
				on = not on
				x = x2
		# Left and right runs.
		for edge_x in [rect.position.x + half, rect.end.x - half]:
			var y: float = rect.position.y
			var on: bool = false
			while y < rect.end.y:
				var y2: float = minf(y + dash, rect.end.y)
				if on:
					draw_line(Vector2(edge_x, y), Vector2(edge_x, y2), dark, width)
				on = not on
				y = y2

	## The ring closes clockwise from twelve, centred on the word.
	func _draw_ring() -> void:
		var centre: Vector2 = glass.position + glass.size * 0.5
		var radius: float = minf(glass.size.y * 0.62, glass.size.x * 0.45)
		var width: float = maxf(3.0, glass.size.y * 0.07)
		draw_arc(centre, radius, 0.0, TAU, 64, Color(0.0, 0.0, 0.0, 0.55), width + 2.0, true)
		draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * clampf(ratio, 0.0, 1.0), 64, Color(1.0, 0.92, 0.70, 0.95), width, true)

	## Reduced motion: a plain bar that fills left to right under the word.
	func _draw_fill() -> void:
		var bar := Rect2(glass.position + Vector2(glass.size.x * 0.08, glass.size.y * 0.84), Vector2(glass.size.x * 0.84, maxf(4.0, glass.size.y * 0.08)))
		draw_rect(bar, Color(0.0, 0.0, 0.0, 0.6))
		var filled := Rect2(bar.position, Vector2(bar.size.x * clampf(ratio, 0.0, 1.0), bar.size.y))
		draw_rect(filled, Color(1.0, 0.92, 0.70, 0.95))
		draw_rect(bar, Color(1.0, 0.92, 0.70, 0.6), false, 1.0)
