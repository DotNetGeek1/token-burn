class_name ResourceBar
extends Control

var _stat_key: String = ""


func setup(title: String, current: float, maximum: float, stat_key: String = "", value_text: String = "") -> void:
	_stat_key = stat_key
	var title_label: Label = $VBox/Header/TitleLabel
	var value_label: Label = $VBox/Header/ValueLabel
	var bar: ProgressBar = $VBox/Bar
	var icon: TextureRect = $VBox/Header/Icon

	title_label.text = title.to_upper()
	if value_text != "":
		value_label.text = value_text
	else:
		value_label.text = "%s / %s" % [NumberFormat.format(current), NumberFormat.format(maximum)]
	bar.max_value = maxf(1.0, maximum)
	bar.value = clampf(current, 0.0, maximum)

	if stat_key != "":
		var tex: Texture2D = AssetCatalog.stat_icon(stat_key)
		icon.texture = tex
		icon.visible = tex != null
		bar.add_theme_stylebox_override("fill", UiThemeBuilder.progress_fill_for(stat_key))
	else:
		icon.visible = false


## Overrides the fill color, for bars whose severity changes (e.g. risk).
func set_fill_color(fill_color: Color) -> void:
	($VBox/Bar as ProgressBar).add_theme_stylebox_override("fill", UiThemeBuilder.progress_fill(fill_color))


## Flash used when a burn pushes this stat, so heat and quality are felt rather
## than only read.
func pulse() -> void:
	var bar: ProgressBar = $VBox/Bar
	var accent: Color = UiThemeBuilder.progress_fill_for(_stat_key).bg_color
	bar.modulate = accent.lightened(0.6)
	var tween: Tween = create_tween()
	tween.tween_property(bar, "modulate", Color.WHITE, 0.4)
