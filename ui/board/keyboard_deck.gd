class_name KeyboardDeck
extends PanelContainer

## The keyboard the player is typing on.
##
## The board's actions used to be four full-width rows floating on the page
## background, which read as a settings form parked under a picture of a computer.
## Mounting them in a plate fixed that and introduced a new problem: a bordered
## panel under a bordered bay cut the screen into thirds. So the plate and its tray
## are gone and the caps sit straight on the scene, over nothing but a fade that
## keeps them legible against the room.
##
## Keys are ranked by size the way a real board ranks them: BURN is the enter key,
## the surges and the vent are ordinary caps beside it, and the keys you press once
## a contract — read the brief, arrange the pipeline, ship it — sit in a function
## row above. The deck owns the lamps and the layout; what the keys *do* stays with
## the board, because that is where the simulation is.
##
## The caps are styled here rather than through the app's button variations. The
## variations carry an accent glow and a large clipped corner, which is right for a
## call to action floating on a page and wrong for a key milled into a machine.

## Lit lamps for surges armed for the next batch. Without them the surge keys had
## to rewrite their own sub-text ("ARMED FOR THIS BATCH"), which threw away the
## line that says what the surge costs.
const LAMPS := [
	{"key": "boost", "label": "BOOST", "accent": "heat"},
	{"key": "cloud", "label": "CLOUD", "accent": "compute"},
]

## What each button variation means as a cap: its accent, and whether the cap is
## driven (a live action) or unlit (available but not the thing to press). The
## board already flips variations to say this, so reading them keeps one source of
## truth for which key is hot.
const VARIATION_ACCENTS := {
	&"PrimaryButton": "action",
	&"MoneyButton": "money",
	&"DangerButton": "danger",
	&"BoostButton": "heat",
}

const KEY_ROWS := "Margin/VBox/KeyRows"

@onready var job_key: GameButton = get_node(KEY_ROWS + "/FnRow/JobKey")
@onready var edit_key: GameButton = get_node(KEY_ROWS + "/FnRow/EditKey")
@onready var deliver_key: GameButton = get_node(KEY_ROWS + "/FnRow/DeliverKey")
@onready var cool_key: GameButton = get_node(KEY_ROWS + "/MainRow/LeftStack/TopRow/CoolKey")
@onready var boost_key: GameButton = get_node(KEY_ROWS + "/MainRow/LeftStack/TopRow/BoostKey")
@onready var cloud_key: GameButton = get_node(KEY_ROWS + "/MainRow/LeftStack/CloudKey")
@onready var burn_key: GameButton = get_node(KEY_ROWS + "/MainRow/BurnKey")
@onready var kill_key: GameButton = get_node(KEY_ROWS + "/MainRow/KillKey")

var _lamp_row: HBoxContainer = null
var _lit: Dictionary = {}
var _lamps: Dictionary = {}
var _scrim: TextureRect = null


func _ready() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_mount_scrim()
	_lamp_row = $Margin/VBox/LampRow
	_build_lamps()
	restyle_keys()


## The keys stand in the shadow under the machine rather than on a plate. It starts
## at the field colour the artwork's own floor is painted, so there is no seam where
## the machine ends, and thins toward the bottom so the room is still faintly there
## behind the thumb instead of a black slab.
func _mount_scrim() -> void:
	_scrim = TextureRect.new()
	_scrim.texture = UiFx.scrim(UiThemeBuilder.color("bay"), 1.0, 0.55, 0.0, 1.0)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.stretch_mode = TextureRect.STRETCH_SCALE
	# The gradient is a tall thin strip, and a container that respected its size
	# would make the deck 256 pixels tall before a single key was laid out.
	_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(_scrim)
	move_child(_scrim, 0)


func keys() -> Array:
	return [job_key, edit_key, deliver_key, cool_key, boost_key, cloud_key, burn_key, kill_key]


## Re-cuts every cap from its current variation. Called after the board has set
## which keys are live, because the variation is the input.
func restyle_keys() -> void:
	for key in keys():
		_style_key(key)


func _style_key(key: GameButton) -> void:
	var variation: StringName = key.theme_type_variation
	var filled: bool = VARIATION_ACCENTS.has(variation)
	# A resting cap is cut from the case, not from its accent: only the key that is
	# the live action is allowed to be coloured, or every cap looks armed. The
	# button still tints its own glyph and legend, so the identity survives.
	var accent: Color = UiThemeBuilder.semantic(
		str(VARIATION_ACCENTS.get(variation, "neutral"))
	)
	for state in ["normal", "hover", "pressed", "disabled"]:
		key.add_theme_stylebox_override(
			state, UiThemeBuilder.deck_key_style(accent, filled, state)
		)
	# Focus reuses the resting cap: a keyboard-focused key that lit up would read
	# as the live action.
	key.add_theme_stylebox_override(
		"focus", UiThemeBuilder.deck_key_style(accent, filled, "normal")
	)


func _build_lamps() -> void:
	for spec in LAMPS:
		var lamp := DeckLamp.new()
		lamp.setup(str(spec["label"]), UiThemeBuilder.semantic(str(spec["accent"])))
		_lamp_row.add_child(lamp)
		_lamps[str(spec["key"])] = lamp


## Lights the lamps for surges armed for the next batch.
func set_indicators(boost: bool, cloud: bool) -> void:
	_set_lamp("boost", boost)
	_set_lamp("cloud", cloud)


func _set_lamp(key: String, on: bool) -> void:
	if bool(_lit.get(key, false)) == on:
		return
	_lit[key] = on
	var lamp: DeckLamp = _lamps.get(key)
	if lamp != null:
		lamp.set_lit(on)


## Swaps the enter key between burning and killing. They share the slot because
## only one of them is ever the live action, and mid-batch the big key under the
## thumb should be the one that stops it.
func set_burning(burning: bool) -> void:
	burn_key.visible = not burning
	kill_key.visible = burning


## One indicator: a dot and a stencilled legend, like the caps-lock cluster on a
## real board. Drawn rather than built from nodes because it is a circle and five
## letters.
class DeckLamp:
	extends Control

	const RADIUS := 7.0
	const LEGEND_SIZE := 22

	var _label: String = ""
	var _accent: Color = Color.WHITE
	var _on: bool = false
	var _tween: Tween = null
	var _glow: float = 0.0

	func setup(label: String, accent: Color) -> void:
		_label = label
		_accent = accent
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(112, 26)

	func set_lit(on: bool) -> void:
		_on = on
		if _tween != null and _tween.is_valid():
			_tween.kill()
		if not on:
			_tween = create_tween()
			_tween.tween_method(_set_glow, _glow, 0.0, 0.2)
			return
		# Armed surges pulse, because they expire after one batch and a steady
		# lamp would read as a permanent purchase.
		_tween = create_tween().set_loops()
		_tween.tween_method(_set_glow, 0.55, 1.0, 0.6).set_trans(Tween.TRANS_SINE)
		_tween.tween_method(_set_glow, 1.0, 0.55, 0.6).set_trans(Tween.TRANS_SINE)

	func _set_glow(value: float) -> void:
		_glow = value
		queue_redraw()

	func _draw() -> void:
		var font: Font = UiThemeBuilder.mono_font()
		if font == null:
			font = ThemeDB.fallback_font
		var centre := Vector2(RADIUS + 2.0, size.y * 0.5)
		draw_circle(centre, RADIUS + 2.0, Color(0, 0, 0, 0.6))
		var lamp: Color = _accent if _on else UiThemeBuilder.color("grey")
		var alpha: float = (0.22 + 0.78 * _glow) if _on else 0.3
		draw_circle(centre, RADIUS, Color(lamp.r, lamp.g, lamp.b, alpha))
		draw_string(
			font,
			Vector2(centre.x + RADIUS + 8.0, size.y * 0.5 + float(LEGEND_SIZE) * 0.36),
			_label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			LEGEND_SIZE,
			Color(lamp.r, lamp.g, lamp.b, 0.95 if _on else 0.4)
		)
