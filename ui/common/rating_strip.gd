class_name RatingStrip
extends HBoxContainer

## Five-dot rating row ("PAY ●●●○○") for at-a-glance comparison between
## contracts. Flat by design: no container, so it reads as an information strip
## rather than another bordered box.

const DOT_COUNT := 5


static func create(label_text: String, filled: int, role: String) -> RatingStrip:
	var strip := RatingStrip.new()
	strip._build(label_text, filled, UiThemeBuilder.semantic(role))
	return strip


func _build(label_text: String, filled: int, accent: Color) -> void:
	add_theme_constant_override("separation", UiThemeBuilder.SPACE_SM)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = label_text.to_upper()
	label.custom_minimum_size = Vector2(150, 0)
	label.theme_type_variation = &"SectionLabel"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)
	var dots := Label.new()
	var dot_count: int = clampi(filled, 0, DOT_COUNT)
	dots.text = "●".repeat(dot_count) + "○".repeat(DOT_COUNT - dot_count)
	dots.add_theme_font_size_override("font_size", UiThemeBuilder.FONT_BODY)
	dots.add_theme_color_override("font_color", accent)
	dots.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(dots)
