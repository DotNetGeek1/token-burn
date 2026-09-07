class_name ResourceBar
extends Control

var _stat_key: String = ""

@onready var _title_label: Label = $VBox/Header/TitleLabel
@onready var _value_label: Label = $VBox/Header/ValueLabel
@onready var _bar: ProgressBar = $VBox/Bar
@onready var _icon: TextureRect = $VBox/Header/Icon


func setup(title: String, current: float, maximum: float, stat_key: String = "", value_text: String = "") -> void:
	_ensure_nodes()
	_stat_key = stat_key
	_title_label.text = title.to_upper()
	if value_text != "":
		_value_label.text = value_text
	else:
		_value_label.text = "%s / %s" % [NumberFormat.format(current), NumberFormat.format(maximum)]
	_bar.max_value = maxf(1.0, maximum)
	_bar.value = clampf(current, 0.0, maximum)

	if stat_key != "":
		var tex: Texture2D = AssetCatalog.stat_icon(stat_key)
		_icon.texture = tex
		_icon.visible = tex != null
		_bar.add_theme_stylebox_override("fill", UiThemeBuilder.progress_fill_for(stat_key))
	else:
		_icon.visible = false


## Overrides the fill color, for bars whose severity changes (e.g. risk).
func set_fill_color(fill_color: Color) -> void:
	_ensure_nodes()
	_bar.add_theme_stylebox_override("fill", UiThemeBuilder.progress_fill(fill_color))


## Flash used when a burn pushes this stat, so heat and quality are felt rather
## than only read.
func pulse() -> void:
	_ensure_nodes()
	var accent: Color = UiThemeBuilder.progress_fill_for(_stat_key).bg_color
	_bar.modulate = accent.lightened(0.6)
	var tween: Tween = create_tween()
	tween.tween_property(_bar, "modulate", Color.WHITE, 0.4)


## `@onready` only fires once the bar enters the tree; resolve on demand so a
## bar configured before `add_child` still works.
func _ensure_nodes() -> void:
	if _bar != null:
		return
	_title_label = $VBox/Header/TitleLabel
	_value_label = $VBox/Header/ValueLabel
	_bar = $VBox/Bar
	_icon = $VBox/Header/Icon
