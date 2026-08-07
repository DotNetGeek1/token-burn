class_name AchievementSplash
extends Control

## The award celebration.
##
## Awards used to arrive as a quiet banner parented inside the shell, which put
## them *underneath* the flow overlays: most achievements land at run end or
## during a debrief, so the one moment the player earned something was the one
## moment the notice was covered. This lives on its own CanvasLayer above
## everything, and it performs — drop, punch, sparks, sheen — because a trophy
## that fades in and out reads as a status line.
##
## It still never takes input. An achievement is something that happened, not a
## decision, so it must not interrupt the burn that earned it: every part of it
## ignores the mouse and it dismisses itself.

## Distance from the top of the screen the card settles at. Clear of the status
## bar's chips, high enough to leave the board readable underneath.
const TOP_OFFSET := 150.0
## Fraction of the screen left free either side, before the content-column cap.
const SIDE_MARGIN := 0.06
const DROP_HEIGHT := 90.0
const DROP_SECONDS := 0.42
const FADE_IN_SECONDS := 0.18
const ICON_SECONDS := 0.4
const ICON_TILT := -0.35
const SHEEN_SECONDS := 0.7
const HOLD_SECONDS := 2.5
const EXIT_SECONDS := 0.35
const EXIT_RISE := 40.0
const ICON_SIZE := 76.0
## How far the icon's bloom spills past the icon art itself.
const GLOW_BLEED := 34.0
const FLARE_SIZE := 460.0
const SPARK_COUNT := 48

var _queue: Array[String] = []
var _playing: bool = false
var _card: PanelContainer = null
var _icon: TextureRect = null
var _icon_glow: TextureRect = null
var _title: Label = null
var _reward: Label = null
var _sheen: TextureRect = null
var _flare: TextureRect = null
var _sparks: CPUParticles2D = null


## Mounts the splash on its own layer above `host`, which is the main shell. The
## layer is what guarantees it draws over the flow overlays; the theme is copied
## across because a CanvasLayer breaks the chain a Control would inherit it by.
static func mount(host: Control) -> AchievementSplash:
	var layer := CanvasLayer.new()
	layer.name = "AchievementLayer"
	layer.layer = 100
	var splash := AchievementSplash.new()
	splash.name = "AchievementSplash"
	splash.theme = host.theme
	layer.add_child(splash)
	host.add_child(layer)
	return splash


## Shows `achievement_id`, or lines it up behind whatever is already on screen.
## Several awards can land on the same tick, and the one that unlocked a module
## must not be the one that flashed past.
func enqueue(achievement_id: String) -> void:
	_queue.append(achievement_id)
	if not _playing:
		_play()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	get_viewport().size_changed.connect(_layout_card)
	_layout_card()


func _build() -> void:
	_sparks = CPUParticles2D.new()
	_sparks.name = "Sparks"
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.amount = SPARK_COUNT
	_sparks.lifetime = 1.1
	# The whole shower has to leave the emitter at once, or it reads as a leak
	# rather than a pop.
	_sparks.explosiveness = 0.88
	_sparks.texture = UiFx.radial_dot(32, 0.4)
	_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_sparks.direction = Vector2.UP
	_sparks.spread = 165.0
	_sparks.initial_velocity_min = 220.0
	_sparks.initial_velocity_max = 470.0
	_sparks.gravity = Vector2(0.0, 430.0)
	_sparks.damping_min = 20.0
	_sparks.damping_max = 60.0
	_sparks.angular_velocity_min = -220.0
	_sparks.angular_velocity_max = 220.0
	# The dot is 32px, so these are roughly 15 to 40 across: big enough to read as
	# thrown confetti over the office art rather than as dust on the lens.
	_sparks.scale_amount_min = 0.48
	_sparks.scale_amount_max = 1.2
	# Two ramps: one picks each spark's colour out of the award palette, the
	# other burns it out over its life so nothing hangs on screen.
	_sparks.color_initial_ramp = UiFx.ramp(
		[0.0, 0.5, 1.0],
		[
			UiThemeBuilder.semantic("energy"),
			UiThemeBuilder.color("white"),
			UiThemeBuilder.semantic("perk"),
		]
	)
	_sparks.color_ramp = UiFx.ramp(
		[0.0, 0.6, 1.0],
		[Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)]
	)
	add_child(_sparks)

	_card = PanelContainer.new()
	_card.name = "Card"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	_card.modulate.a = 0.0
	_card.add_theme_stylebox_override(
		"panel", UiThemeBuilder.card_style_accent(UiThemeBuilder.semantic("energy"))
	)
	# The sheen is a child of the card rather than an overlay on top of it, so
	# the card's own corners cut it off.
	_card.clip_contents = true
	add_child(_card)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, UiThemeBuilder.SPACE_MD)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, UiThemeBuilder.SPACE_MD)
	_card.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiThemeBuilder.SPACE_MD)
	margin.add_child(row)

	# A plain Control rather than a container, so the bloom can hang outside the
	# icon's box without the row reserving room for it.
	var icon_stack := Control.new()
	icon_stack.name = "IconStack"
	icon_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_stack.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon_stack)

	_icon_glow = TextureRect.new()
	_icon_glow.name = "IconGlow"
	_icon_glow.texture = UiFx.radial_dot(64, 0.45)
	_icon_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_icon_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_glow.modulate = UiThemeBuilder.semantic("energy")
	_icon_glow.modulate.a = 0.0
	_icon_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top"]:
		_icon_glow.set("offset_%s" % side, -GLOW_BLEED)
	for side in ["right", "bottom"]:
		_icon_glow.set("offset_%s" % side, GLOW_BLEED)
	_icon_glow.pivot_offset = Vector2(ICON_SIZE, ICON_SIZE) * 0.5 + Vector2(GLOW_BLEED, GLOW_BLEED)
	icon_stack.add_child(_icon_glow)

	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.pivot_offset = Vector2(ICON_SIZE, ICON_SIZE) * 0.5
	icon_stack.add_child(_icon)

	var text_box := VBoxContainer.new()
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text_box)

	var kicker := Label.new()
	kicker.text = "ACHIEVEMENT UNLOCKED"
	kicker.theme_type_variation = &"SectionLabel"
	kicker.add_theme_color_override("font_color", UiThemeBuilder.semantic("energy"))
	text_box.add_child(kicker)

	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(_title)

	_reward = Label.new()
	_reward.theme_type_variation = &"MutedLabel"
	_reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward.add_theme_color_override("font_color", UiThemeBuilder.semantic("perk"))
	text_box.add_child(_reward)

	# Swept by moving the gradient's fill points rather than the node, because
	# the card sizes this child to fill it and would undo any position tween.
	var sheen_texture := GradientTexture2D.new()
	sheen_texture.gradient = UiFx.ramp(
		[0.0, 0.5, 1.0],
		[Color(1, 1, 1, 0), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0)]
	)
	sheen_texture.width = 128
	sheen_texture.height = 8
	_sheen = TextureRect.new()
	_sheen.name = "Sheen"
	_sheen.texture = sheen_texture
	_sheen.stretch_mode = TextureRect.STRETCH_SCALE
	_sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheen.modulate.a = 0.0
	_card.add_child(_sheen)

	# Built last so it draws over the card: behind it, the card's own fill hid all
	# but the corners of the flash, which is the opposite of a flash.
	_flare = TextureRect.new()
	_flare.name = "Flare"
	_flare.texture = UiFx.radial_dot(96, 0.1)
	_flare.stretch_mode = TextureRect.STRETCH_SCALE
	_flare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flare.modulate = UiThemeBuilder.semantic("energy")
	_flare.modulate.a = 0.0
	_flare.size = Vector2(FLARE_SIZE, FLARE_SIZE)
	_flare.pivot_offset = _flare.size * 0.5
	add_child(_flare)


## The card is positioned by hand rather than by a container, because the drop is
## a position tween and a container would overwrite it every layout pass. Its
## height is left to the layout pass, which grows the card to whatever its title
## wrapped to. It spans the screen up to the content column's width, so a desktop
## window does not stretch a one-line award across a metre of glass.
##
## The width comes from the viewport and not from this control: a Control parented
## to a CanvasLayer reports a zero rect, and a zero-width card collapses its
## wrapping title into a column one character wide.
func _layout_card() -> void:
	if _card == null:
		return
	var view: Vector2 = get_viewport_rect().size
	var width: float = minf(
		view.x * (1.0 - SIDE_MARGIN * 2.0), UiThemeBuilder.CONTENT_MAX_WIDTH
	)
	_card.offset_left = (view.x - width) * 0.5
	_card.offset_right = _card.offset_left + width
	if not _playing:
		_card.offset_top = TOP_OFFSET
		_card.offset_bottom = TOP_OFFSET


func _play() -> void:
	if _queue.is_empty():
		_playing = false
		return
	var achievement: Dictionary = ContentDatabase.get_achievement(_queue[0])
	if achievement.is_empty():
		_queue.pop_front()
		_play()
		return
	_playing = true
	_icon.texture = AssetCatalog.achievement_icon(str(achievement.get("icon", "")))
	_title.text = str(achievement.get("name", ""))
	_reward.text = _reward_text(achievement)
	_reward.visible = _reward.text != ""

	# The card is shown transparent rather than hidden, because a hidden container
	# does not lay its children out: measured while hidden, the title has no width
	# to wrap against and the card takes a height of hundreds of lines. Two passes
	# settle it — one hands the label its width, one takes the wrapped height back
	# up to the card — and only then is its rect worth aiming anything at.
	_card.modulate.a = 0.0
	_card.visible = true
	_layout_card()
	# Collapsed first, so the card takes the height of *this* award's title. Left
	# at the last one's pinned height it could only ever grow, and the award after
	# a two-line name would keep its empty second line.
	_card.offset_top = TOP_OFFSET
	_card.offset_bottom = TOP_OFFSET
	for _pass in range(2):
		await get_tree().process_frame
		if not is_inside_tree():
			return
	# Pins the settled height, so the stale minimum from the pass before cannot
	# stretch the card again while the drop is moving it.
	_card.offset_bottom = _card.offset_top + _card.size.y

	# Aimed at where the card lands rather than where it starts, so the sparks
	# still line up with it while it is on its way down.
	var card_rect: Rect2 = Rect2(_card.position, _card.size)
	var icon_center: Vector2 = _icon.global_position - _card.global_position + _icon.size * 0.5
	_sparks.position = card_rect.get_center()
	_sparks.emission_rect_extents = Vector2(card_rect.size.x * 0.4, card_rect.size.y * 0.3)
	_flare.position = card_rect.position + icon_center - _flare.size * 0.5

	_card.position.y = TOP_OFFSET - DROP_HEIGHT
	_icon.scale = Vector2.ZERO
	_icon.rotation = ICON_TILT
	_icon_glow.modulate.a = 0.0
	_icon_glow.scale = Vector2(0.4, 0.4)
	UiSound.play("fanfare")

	var drop: Tween = create_tween()
	drop.tween_property(_card, "position:y", TOP_OFFSET, DROP_SECONDS).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	drop.parallel().tween_property(_card, "modulate:a", 1.0, FADE_IN_SECONDS)
	drop.tween_callback(_burst)
	drop.tween_interval(HOLD_SECONDS)
	drop.tween_property(_card, "modulate:a", 0.0, EXIT_SECONDS).set_ease(Tween.EASE_IN)
	drop.parallel().tween_property(
		_card, "position:y", TOP_OFFSET - EXIT_RISE, EXIT_SECONDS
	).set_ease(Tween.EASE_IN)
	drop.tween_callback(_finish)


## Everything that happens the instant the card lands: the icon punches in out of
## its own bloom, a flash blows out over it, and the sparks go up.
func _burst() -> void:
	_sparks.restart()

	var icon_tween: Tween = create_tween()
	icon_tween.tween_property(_icon, "scale", Vector2.ONE, ICON_SECONDS).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	icon_tween.parallel().tween_property(_icon, "rotation", 0.0, ICON_SECONDS).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)

	var glow_tween: Tween = create_tween()
	glow_tween.tween_property(_icon_glow, "modulate:a", 1.0, 0.12)
	glow_tween.parallel().tween_property(_icon_glow, "scale", Vector2(1.15, 1.15), 0.3)
	# Settles to a steady bloom rather than going out, so the trophy keeps glowing
	# for as long as the card is up.
	glow_tween.tween_property(_icon_glow, "modulate:a", 0.5, 0.5)

	# The flash is bright but brief: it is over the card, so anything that lingers
	# is sitting on top of the award's own name.
	var flare_tween: Tween = create_tween()
	_flare.scale = Vector2(0.35, 0.35)
	flare_tween.tween_property(_flare, "modulate:a", 0.45, 0.1)
	flare_tween.parallel().tween_property(_flare, "scale", Vector2(1.5, 1.5), 0.5).set_ease(
		Tween.EASE_OUT
	)
	flare_tween.tween_property(_flare, "modulate:a", 0.0, 0.35)

	_sheen.modulate.a = 1.0
	var sweep: Tween = create_tween()
	sweep.tween_method(_set_sheen, -0.55, 1.55, SHEEN_SECONDS).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	sweep.tween_callback(func() -> void: _sheen.modulate.a = 0.0)


## `head` is where the bright middle of the band sits across the card, running
## from just off one edge to just off the other.
func _set_sheen(head: float) -> void:
	var texture: GradientTexture2D = _sheen.texture as GradientTexture2D
	if texture == null:
		return
	texture.fill_from = Vector2(head - 0.25, 0.0)
	texture.fill_to = Vector2(head + 0.25, 0.0)


func _finish() -> void:
	_card.visible = false
	_card.position.y = TOP_OFFSET
	if not _queue.is_empty():
		_queue.pop_front()
	_playing = false
	_play()


func _reward_text(achievement: Dictionary) -> String:
	var reward: Dictionary = Dictionary(achievement.get("reward", {}))
	if str(reward.get("type", "none")) != "unlock_module":
		return ""
	var operation: OperationDefinition = ContentDatabase.get_operation(
		str(reward.get("operation_id", ""))
	)
	if operation == null:
		return ""
	return "New module in the draft pool · %s" % operation.name
