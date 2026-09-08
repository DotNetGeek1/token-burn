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
const BODY_MIN_HEIGHT := 168.0
const COMPACT_BODY_MIN_HEIGHT := 48.0
const BUTTON_HEIGHT := 62.0
const COMPACT_BUTTON_HEIGHT := 44.0

@onready var backdrop: ColorRect = $Backdrop
@onready var phone: PanelContainer = $Phone
@onready var margin: MarginContainer = $Phone/Margin
@onready var vbox: VBoxContainer = $Phone/Margin/VBox
@onready var call_state: Label = $Phone/Margin/VBox/CallState
@onready var portrait: TextureRect = $Phone/Margin/VBox/Portrait
@onready var name_label: Label = $Phone/Margin/VBox/Name
@onready var title_label: Label = $Phone/Margin/VBox/Title
@onready var subject_label: Label = $Phone/Margin/VBox/Subject
@onready var body_label: Label = $Phone/Margin/VBox/Body
@onready var progress_label: Label = $Phone/Margin/VBox/Progress
@onready var continue_button: GameButton = $Phone/Margin/VBox/ContinueButton

var _lines: Array = []
var _index: int = 0
var _typed: float = 0.0
var _typing: bool = false
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
	var width: float = minf(PHONE_WIDTH, area.x - EDGE_PAD * 2.0)
	var height: float = minf(PHONE_HEIGHT, area.y - EDGE_PAD * 2.0)
	margin.add_theme_constant_override("margin_left", 12 if compact else 22)
	margin.add_theme_constant_override("margin_right", 12 if compact else 22)
	margin.add_theme_constant_override("margin_top", 8 if compact else 20)
	margin.add_theme_constant_override("margin_bottom", 8 if compact else 20)
	vbox.add_theme_constant_override("separation", 4 if compact else 12)
	portrait.visible = portrait.texture != null and not compact
	title_label.visible = not compact
	body_label.custom_minimum_size = Vector2(0.0, COMPACT_BODY_MIN_HEIGHT if compact else BODY_MIN_HEIGHT)
	continue_button.compact = compact
	continue_button.set_min_height(COMPACT_BUTTON_HEIGHT if compact else BUTTON_HEIGHT)
	phone.set_anchors_preset(Control.PRESET_CENTER)
	phone.offset_left = -width * 0.5
	phone.offset_right = width * 0.5
	phone.offset_top = -height * 0.5
	phone.offset_bottom = height * 0.5


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
	var contract: Dictionary = Simulation.ascension_boss_contract()
	var progress: Dictionary = Simulation.ascension_progress()
	var replacements: Dictionary = {
		"{burn}": str(contract.get("burn_label", NumberFormat.format(
			float(contract.get("total_burn", 0.0))
		))),
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


## Which version of himself he shows up as. The run already knows the answer to
## every one of these, so the callers do not have to.
func _variant_for(trigger: String, context: Dictionary) -> String:
	match trigger:
		"run_intro", "ascension_complete":
			return MetaProgress.selected_location()
		"terms":
			var progress: Dictionary = Simulation.ascension_progress()
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
