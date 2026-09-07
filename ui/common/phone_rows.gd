class_name PhoneRows
extends RefCounted

## Rows printed on a handset screen.
##
## `ConsoleStyle.detail_line` prints the phosphor console's lines; these are the
## same jobs — a paragraph, a labelled figure, a heading, a hairline — in the
## phone's language: Inter body copy, muted labels, a monospace figure on the
## right, and colour that comes from a semantic role so "money" stays green and
## "danger" stays red wherever a row is printed.
##
## Every helper returns a fresh Control ready to be added to a `PhoneOverlay`'s
## `content()`.

const RULE_HEIGHT := 1.0
const STAT_SEPARATION := 12


## A sentence or two of body copy, wrapped to the phone's width. `role` tints
## the text when the paragraph carries a meaning (a warning, a payout); blank
## leaves it in primary text.
static func paragraph(text: String, role: String = "") -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body: Font = UiThemeBuilder.body_font()
	if body != null:
		label.add_theme_font_override("font", body)
	if role != "":
		label.add_theme_color_override("font_color", UiThemeBuilder.semantic(role))
	return label


## A labelled figure: the label muted on the left, the value in the machine's
## monospace on the right. `role` colours the value ("money", "warning",
## "danger", "perk", "energy"...); blank keeps the value in primary text.
static func stat_row(label_text: String, value_text: String, role: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", STAT_SEPARATION)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var key := Label.new()
	key.text = label_text
	key.theme_type_variation = &"MutedLabel"
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(key)

	var value := Label.new()
	value.text = value_text
	value.theme_type_variation = &"MoneyLabel"
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_horizontal = Control.SIZE_SHRINK_END
	var mono: Font = UiThemeBuilder.mono_font()
	if mono != null:
		value.add_theme_font_override("font", mono)
	# MoneyLabel is green by default; anything that is not money says so.
	value.add_theme_color_override(
		"font_color",
		UiThemeBuilder.semantic(role) if role != "" else Color(UiThemeBuilder.TEXT_PRIMARY)
	)
	row.add_child(value)
	return row


## A kicker over a group of rows, in the terminal face the phone's own status
## line uses. `role` lights it in a semantic colour; blank leaves it muted.
static func heading(text: String, role: String = "") -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.theme_type_variation = &"SectionLabel"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if role != "":
		label.add_theme_color_override("font_color", UiThemeBuilder.semantic(role))
	return label


## A one-pixel hairline between groups of rows.
static func rule() -> ColorRect:
	var line := ColorRect.new()
	line.color = UiThemeBuilder.color("stroke_dim")
	line.custom_minimum_size = Vector2(0.0, RULE_HEIGHT)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return line
