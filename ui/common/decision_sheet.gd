class_name DecisionSheet
extends PhoneOverlay

## The handset's answer to `ConsoleSheet`: the long text, the full numbers and
## the confirm/walk-away pair, printed on the phone rather than the phosphor
## glass.
##
## It keeps `ConsoleSheet`'s call signature so the screens that open one did not
## have to be rewritten to change their looks — the same `show_detail` arguments
## print as phone rows here. The row vocabulary is `ConsoleStyle.detail_line`'s:
## - `"plain text"` or `{"text": "…"}`         a wrapped paragraph
## - `{"warn": "…"}`                           a paragraph in the danger colour
## - `{"stat": "Cost", "value": "$8", "role"}` a key on the left, value right
## - `{"rule": "Name", "text": "…", "role"}`   a heading and its consequence

signal action_confirmed
## Second way out of the same decision. A sheet that offers only one action makes
## the alternative invisible, which is wrong when the alternative is "walk away".
signal secondary_confirmed

const CHIP_SEPARATION := 6

var _chips: HFlowContainer = null
var _lines: VBoxContainer = null


func _ready() -> void:
	super._ready()
	setup("detail")
	# A sheet is a decision, so it is dismissed deliberately rather than by a
	# stray tap on the room behind it.
	dismiss_on_scrim = false
	_build_body()


func _build_body() -> void:
	if _lines != null:
		return
	var body: VBoxContainer = content()

	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", CHIP_SEPARATION)
	_chips.add_theme_constant_override("v_separation", CHIP_SEPARATION)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chips.visible = false
	body.add_child(_chips)

	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", BODY_SEPARATION)
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_lines)


## `rows` takes the shared detail vocabulary from `ConsoleStyle.detail_line`,
## plus the `role` key that colours a value. `accent` lights the kicker and
## picks the primary key's variation.
func show_detail(
	title: String,
	kicker: String,
	rows: Array,
	chips: Array = [],
	action_text: String = "",
	accent: Color = Color.TRANSPARENT,
	secondary_text: String = ""
) -> void:
	_build_body()
	setup(title)
	set_kicker(kicker.to_upper())
	if accent != Color.TRANSPARENT:
		_kicker.add_theme_color_override("font_color", accent)
	else:
		_kicker.add_theme_color_override("font_color", ConsoleStyle.PHOSPHOR)
	set_context("")
	_set_chips(chips)
	_set_rows(rows)
	_set_actions(action_text, secondary_text, accent)
	open()


## A sheet that is only a block of text — a cost forecast, a note — with no
## decision attached to it.
func show_content(title: String, body: String) -> void:
	show_detail(title, "", [{"text": body}])


## Kept so the screens that spoke to `ConsoleSheet` can still dismiss the sheet
## by the name they know.
func hide_sheet() -> void:
	hide_overlay()


func _set_chips(chips: Array) -> void:
	for child in _chips.get_children():
		_chips.remove_child(child)
		child.queue_free()
	for chip in chips:
		var text: String = str(chip.get("text", "")) if chip is Dictionary else str(chip)
		if text.strip_edges() == "":
			continue
		var role: String = str(chip.get("role", "neutral")) if chip is Dictionary else "neutral"
		var filled: bool = bool(chip.get("filled", false)) if chip is Dictionary else false
		_chips.add_child(UiChip.create(text, role, null, filled))
	_chips.visible = _chips.get_child_count() > 0


func _set_rows(rows: Array) -> void:
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	for row in rows:
		for line in _row_controls(row):
			_lines.add_child(line)


## One row dictionary becomes one or two phone rows.
func _row_controls(row: Variant) -> Array[Control]:
	var out: Array[Control] = []
	if not row is Dictionary:
		var plain: String = str(row)
		if plain.strip_edges() != "":
			out.append(PhoneRows.paragraph(plain))
		return out
	var entry: Dictionary = row
	var role: String = str(entry.get("role", ""))
	if entry.has("warn"):
		out.append(PhoneRows.paragraph(str(entry["warn"]), "danger"))
		return out
	if entry.has("stat"):
		out.append(PhoneRows.stat_row(str(entry["stat"]), str(entry.get("value", "")), role))
		return out
	var text: String = str(entry.get("text", ""))
	if entry.has("rule"):
		var heading: String = str(entry["rule"])
		if heading.strip_edges() != "":
			out.append(PhoneRows.heading(heading, role))
		if text.strip_edges() != "":
			out.append(PhoneRows.paragraph(text))
		return out
	if text.strip_edges() != "":
		out.append(PhoneRows.paragraph(text, role))
	return out


func _set_actions(action_text: String, secondary_text: String, accent: Color) -> void:
	var entries: Array = []
	if secondary_text != "":
		entries.append({
			"headline": secondary_text.to_upper(),
			"destructive": true,
			"pressed": func() -> void:
				secondary_confirmed.emit()
				hide_sheet(),
		})
	if action_text != "":
		var accent_key: String = _accent_role(accent)
		entries.append({
			"headline": action_text.to_upper(),
			"variation": _variation_for(accent_key),
			"accent_key": accent_key,
			"pressed": func() -> void:
				action_confirmed.emit()
				hide_sheet(),
		})
	# The primary key sits last, at the bottom of the phone.
	set_actions(entries)


## The semantic role whose colour the accent is, or "action" when it is none
## of the ones a key is coloured by.
static func _accent_role(accent: Color) -> String:
	if accent == Color.TRANSPARENT:
		return "action"
	for role in ["money", "warning", "energy", "danger", "perk"]:
		if accent.is_equal_approx(UiThemeBuilder.semantic(role)):
			return role
	return "action"


static func _variation_for(accent_key: String) -> String:
	match accent_key:
		"money":
			return "MoneyButton"
		"warning", "energy", "perk":
			return "BoostButton"
		"danger":
			return "DangerButton"
		_:
			return "PrimaryButton"
