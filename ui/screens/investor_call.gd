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

@onready var backdrop: ColorRect = $Backdrop
@onready var phone: PanelContainer = $Phone
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


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	add_to_group("flow_overlay")
	phone.add_theme_stylebox_override("panel", _phone_style())
	continue_button.pressed.connect(_on_continue)
	backdrop.gui_input.connect(_on_backdrop_input)
	var persona: Dictionary = InvestorVoice.persona()
	name_label.text = str(persona.get("name", "The Angel Investor"))
	title_label.text = "%s · %s" % [
		str(persona.get("title", "Angel Investor")), str(persona.get("fund", "")),
	]
	portrait.texture = AssetCatalog.investor_texture("portrait")
	portrait.visible = portrait.texture != null
	# The status light and the alert line are the phone's own screen, so they
	# burn in the same two colours the room's other screens use.
	call_state.add_theme_color_override("font_color", ConsoleStyle.PHOSPHOR)
	subject_label.add_theme_color_override("font_color", ConsoleStyle.DANGER)
	body_label.add_theme_font_override("font", UiThemeBuilder.body_font())


## A handset, not a card: a dark moulded case with a machined bezel, held up in
## front of the room. It carries no colour of its own — like every other piece
## of hardware in the room, the only light on the object comes from what is
## printed on its screen.
func _phone_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.065, 0.070, 0.98)
	style.set_border_width_all(2)
	style.border_color = Color(0.16, 0.19, 0.20)
	# A handset really is a rounded object, but only just: enough to read as
	# moulded plastic, not enough to read as one of the old rounded cards.
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 22
	return style


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
## the line being typed, the next moves him on.
func _on_backdrop_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if tapped:
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
