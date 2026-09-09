extends Control

## The phone call.
##
## The Angel Investor is the only person in Token Burn: he buys the rig, sets
## the terms, marks the homework and either invests again or takes the keys
## back. This is where he does all of it — a phone held up over whatever the
## player was looking at, one paragraph at a time, typed out so he has a pace.
##
## The script itself lives in `content/narrative/investor.json` and is selected
## by `InvestorVoice`; this scene only knows how to deliver it.

## Characters typed per second. Slow enough to read as speech, fast enough that
## a player who has heard it before can tap straight past it.
const TYPE_SPEED := 68.0

## The handset as authored: 452 wide, 636 tall, held up in the middle of a
## 720-tall canvas. A phone canvas is ~300 tall, so there the same object has
## to be a shorter model: no portrait, tighter margins, a lower key.
const PHONE_WIDTH := 452.0
const PHONE_HEIGHT := 636.0
const EDGE_PAD := 16.0
const COMPACT_HEIGHT := 420.0
## Held sideways on a handset: the words run down the left and he sits on the
## right, so the call uses the width the screen has rather than the height it
## does not.
const COMPACT_PHONE_WIDTH := 560.0
## A floor rather than the size: the panel grows past it for a long paragraph.
const COMPACT_PHONE_HEIGHT := 196.0
const COMPACT_PORTRAIT_WIDTH := 132.0
const BODY_MIN_HEIGHT := 168.0
const COMPACT_BODY_MIN_HEIGHT := 48.0
const BUTTON_HEIGHT := 62.0
const COMPACT_BUTTON_HEIGHT := 40.0
const COMPACT_BODY_FONT_SIZE := 13

@onready var backdrop: ColorRect = $Backdrop
@onready var phone: PanelContainer = $Phone
@onready var margin: MarginContainer = $Phone/Margin
@onready var columns: HBoxContainer = $Phone/Margin/Columns
@onready var vbox: VBoxContainer = $Phone/Margin/Columns/VBox
@onready var call_state: Label = $Phone/Margin/Columns/VBox/CallState
@onready var portrait: TextureRect = $Phone/Margin/Columns/VBox/Portrait
@onready var name_label: Label = $Phone/Margin/Columns/VBox/Name
@onready var title_label: Label = $Phone/Margin/Columns/VBox/Title
@onready var subject_label: Label = $Phone/Margin/Columns/VBox/Subject
@onready var body_label: Label = $Phone/Margin/Columns/VBox/Body
@onready var progress_label: Label = $Phone/Margin/Columns/VBox/Progress
@onready var continue_button: GameButton = $Phone/Margin/Columns/VBox/ContinueButton

var _lines: Array = []
var _index: int = 0
var _typed: float = 0.0
var _typing: bool = false
var _compact: bool = false
var _backdrop_tap: TapGesture = TapGesture.new()


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	add_to_group("flow_overlay")
	phone.add_theme_stylebox_override("panel", UiThemeBuilder.phone_style())
	continue_button.pressed.connect(_on_continue)
	backdrop.gui_input.connect(_on_backdrop_input)
	var persona: Dictionary = InvestorVoice.persona()
	name_label.text = str(persona.get("name", "The Angel Investor"))
	title_label.text = "%s · %s" % [
		str(persona.get("title", "Angel Investor")), str(persona.get("fund", "")),
	]
	portrait.texture = AssetCatalog.investor_texture("portrait")
	portrait.visible = portrait.texture != null
	resized.connect(_fit_phone)
	visibility_changed.connect(func() -> void:
		if visible:
			call_deferred("_fit_phone")
	)
	_fit_phone()
	# The status light and the alert line are the phone's own screen, so they
	# burn in the same two colours the room's other screens use.
	call_state.add_theme_color_override("font_color", ConsoleStyle.PHOSPHOR)
	subject_label.add_theme_color_override("font_color", ConsoleStyle.DANGER)
	body_label.add_theme_font_override("font", UiThemeBuilder.body_font())


## Fits the handset to the canvas it is held up in front of. On a desktop that
## is the authored 452×636; on a handset canvas the phone is as tall as the
## screen allows and drops the portrait so the words and the key still fit.
func _fit_phone() -> void:
	var area: Vector2 = size
	if area.x <= 1.0 or area.y <= 1.0:
		area = get_viewport_rect().size
	if area.x <= 1.0 or area.y <= 1.0:
		return
	var compact: bool = area.y < COMPACT_HEIGHT
	var width: float = minf(COMPACT_PHONE_WIDTH if compact else PHONE_WIDTH, area.x - EDGE_PAD * 2.0)
	var height: float = minf(COMPACT_PHONE_HEIGHT if compact else PHONE_HEIGHT, area.y - EDGE_PAD * 2.0)
	_apply_layout(compact)
	phone.set_anchors_preset(Control.PRESET_CENTER)
	phone.offset_left = -width * 0.5
	phone.offset_right = width * 0.5
	phone.offset_top = -height * 0.5
	phone.offset_bottom = height * 0.5


## Everything about the handset that differs between the two models. Upright,
## the portrait heads a centred column; sideways, it moves out to a column of
## its own on the right and the words line up left against it, at the phone's
## type scale.
func _apply_layout(compact: bool) -> void:
	_compact = compact
	margin.add_theme_constant_override("margin_left", 12 if compact else 22)
	margin.add_theme_constant_override("margin_right", 12 if compact else 22)
	margin.add_theme_constant_override("margin_top", 8 if compact else 20)
	margin.add_theme_constant_override("margin_bottom", 8 if compact else 20)
	vbox.add_theme_constant_override("separation", 3 if compact else 12)
	phone.theme = UiThemeBuilder.compact_type_theme() if compact else null

	var portrait_home: Node = columns if compact else vbox
	if portrait.get_parent() != portrait_home:
		portrait.reparent(portrait_home, false)
	if compact:
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_END
		portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
		portrait.custom_minimum_size = Vector2(COMPACT_PORTRAIT_WIDTH, 0.0)
	else:
		vbox.move_child(portrait, call_state.get_index() + 1)
		portrait.size_flags_horizontal = Control.SIZE_FILL
		portrait.size_flags_vertical = Control.SIZE_FILL
		portrait.custom_minimum_size = Vector2(0.0, 190.0)
	portrait.visible = portrait.texture != null

	var align: int = HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER
	for label in [call_state, name_label, title_label, subject_label, progress_label]:
		(label as Label).horizontal_alignment = align
	title_label.visible = not compact
	if compact:
		body_label.add_theme_font_size_override("font_size", COMPACT_BODY_FONT_SIZE)
	else:
		body_label.remove_theme_font_size_override("font_size")
	body_label.custom_minimum_size = Vector2(
		0.0, COMPACT_BODY_MIN_HEIGHT if compact else BODY_MIN_HEIGHT
	)
	continue_button.compact = compact
	continue_button.set_min_height(COMPACT_BUTTON_HEIGHT if compact else BUTTON_HEIGHT)


## Rings the player. `context` may name the `variant` and the `seed` outright;
## anything it leaves out is worked out from the run, so most callers only have
## to say which beat this is.
func call_player(trigger: String, context: Dictionary = {}) -> void:
	var variant: String = str(context.get("variant", _variant_for(trigger, context)))
	var seed: int = int(context.get("seed", _seed_for(trigger)))
	var call: Dictionary = InvestorVoice.call_for(trigger, variant, seed)
	var lines: Array = Array(call.get("lines", []))
	if lines.is_empty():
		return
	_lines = _fill_terms(lines)
	_index = 0
	subject_label.text = str(call.get("subject", "")).to_upper()
	subject_label.visible = subject_label.text != ""
	call_state.text = "INCOMING CALL" if trigger != "terms" else "CALL CONNECTED"
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiSound.play("accept")
	_start_line()
	UiTransition.enter(self)
	get_tree().call_group("main_ui", "sync_overlay_input")


## Substitutes the run's actual terms into his script, so "burn {burn} in {rounds}
## rounds or lose the {rent} a round I'm covering" is the real contract rather
## than a number the writer guessed at when the line was written.
func _fill_terms(lines: Array) -> Array:
	var contract: Dictionary = Simulation.investor_target()
	var progress: Dictionary = Simulation.investor_progress()
	var replacements: Dictionary = {
		# The figure itself rather than the contract's "30 Megatokens" label, in
		# the same notation the cabinet's readouts use, so what he asks for is
		# the number the player watches climb.
		"{burn}": _burn_text(float(contract.get("total_burn", 0.0))),
		"{rounds}": str(int(progress.get("deadline_round", Simulation.ROUNDS_PER_RUN))),
		"{rounds_left}": str(int(progress.get("rounds_remaining", 0))),
		"{rent}": NumberFormat.format_cash(float(Simulation.run_state.economy.get("round_rent", 0.0))),
		"{contract}": str(contract.get("name", "the contract")),
		"{done}": "%.0f%%" % (float(progress.get("burn_ratio", 0.0)) * 100.0),
	}
	var filled: Array = []
	for line in lines:
		var text: String = str(line)
		for token in replacements:
			text = text.replace(token, str(replacements[token]))
		filled.append(text)
	return filled


## "30M tokens", "2.5B tokens": the cabinet's suffixes, with a whole number left
## whole so he does not say "thirty point zero".
static func _burn_text(total: float) -> String:
	var figure: String = NumberFormat.format(total)
	var suffix: String = ""
	while not figure.is_empty() and not figure[-1].is_valid_int() and figure[-1] != ".":
		suffix = figure[-1] + suffix
		figure = figure.left(-1)
	if figure.ends_with(".0"):
		figure = figure.left(-2)
	return "%s%s tokens" % [figure, suffix]


## Which version of himself he shows up as. The run already knows the answer to
## every one of these, so the callers do not have to.
func _variant_for(trigger: String, context: Dictionary) -> String:
	match trigger:
		"run_intro", "ascension_complete":
			# Keyed by the room the run is drawn in, which follows the
			# Infrastructure Tier.
			return RoomProgression.room_for(Simulation.run_state)
		"room_changed":
			var room: String = str(context.get("room", ""))
			return room if not room.is_empty() else RoomProgression.room_for(Simulation.run_state)
		"terms":
			var progress: Dictionary = Simulation.investor_progress()
			if progress.is_empty():
				return "default"
			var deadline: int = maxi(1, int(progress.get("deadline_round", 12)))
			var elapsed: float = float(int(Simulation.run_state.calendar.get("round", 1))) / float(deadline)
			return "behind" if float(progress.get("burn_ratio", 0.0)) < elapsed else "ahead"
		"round_debrief":
			return InvestorVoice.debrief_variant(
				Dictionary(context.get("summary", {})),
				Dictionary(context.get("statement", {}))
			)
		"run_lost":
			# The outcome names the specific ending when there is one; otherwise
			# the loss reason does, and it is a phrase rather than a key.
			var outcome: String = str(Simulation.run_state.flags.get("outcome", ""))
			if InvestorVoice.has_call("run_lost", outcome):
				return outcome
			var reason: String = str(
				Simulation.run_state.flags.get("loss_reason", "")
			).to_lower().replace(" ", "_")
			return reason if InvestorVoice.has_call("run_lost", reason) else "default"
		_:
			return "default"


## Stable per moment, so a call the player reopens says the same thing.
func _seed_for(trigger: String) -> int:
	var round_number: int = int(Simulation.run_state.calendar.get("round", 1))
	return round_number + trigger.length()


func _start_line() -> void:
	_typed = 0.0
	_typing = true
	body_label.text = ""
	body_label.visible_characters = 0
	progress_label.text = "%d / %d" % [_index + 1, _lines.size()]
	body_label.text = str(_lines[_index])
	_refresh_button()
	set_process(true)


func _process(delta: float) -> void:
	if not _typing:
		set_process(false)
		return
	_typed += delta * TYPE_SPEED
	var total: int = body_label.text.length()
	body_label.visible_characters = mini(total, int(_typed))
	if body_label.visible_characters >= total:
		_finish_typing()


func _finish_typing() -> void:
	_typing = false
	set_process(false)
	body_label.visible_characters = -1
	_refresh_button()


func _refresh_button() -> void:
	if _typing:
		continue_button.set_lines("SKIP", "")
		return
	var last: bool = _index >= _lines.size() - 1
	continue_button.set_lines("GOT IT" if last else "GO ON", "")


## Anywhere on the dimmed room behind the phone works too: the first tap finishes
## the line being typed, the next moves him on. A TapGesture, so the press that
## arrives twice (real and emulated) advances once, and so the phone leaves on
## the release rather than the press: hanging up on the press let the paired
## release fall through to whatever the cabinet had under the finger.
func _on_backdrop_input(event: InputEvent) -> void:
	if _backdrop_tap.feed(event):
		_on_continue()


func _on_continue() -> void:
	if _typing:
		_finish_typing()
		return
	_index += 1
	if _index >= _lines.size():
		hide_overlay()
		return
	_start_line()


func hide_overlay() -> void:
	_typing = false
	set_process(false)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().call_group("main_ui", "sync_overlay_input")
