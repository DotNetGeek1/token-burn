class_name CabinetTab
extends Control

## One screen of the cabinet's central CRT. The shell shows one at a time and
## asks the live one what the big red button should say.

## Something the player picked changed: the shell re-reads `primary_action`.
signal changed

## The shell, for anything a tab needs done on the machine rather than the glass.
var shell: Node = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Shelves size their cards off the glass they are given, and the first
	# refresh lands before the glass has a size. Lay out again once it has.
	resized.connect(_on_resized)


func _on_resized() -> void:
	if is_visible_in_tree() and shell != null:
		call_deferred("refresh")


func tab_key() -> String:
	return ""


func tab_title() -> String:
	return tab_key()


func refresh() -> void:
	pass


## What the BURN button does while this tab is up:
## `{"label": String, "enabled": bool, "sub": String, "pressed": Callable}`.
## An empty dictionary hands the button back to the shell's own BURN.
func primary_action() -> Dictionary:
	return {}


## Called when the tab is brought to the front. Refreshed twice: once now, and
## once after the frame in which its containers, hidden until this moment, get
## their real sizes — the shelves cut their cards to fit those.
func activated() -> void:
	refresh()
	if is_inside_tree():
		await get_tree().process_frame
		if is_visible_in_tree():
			refresh()


## Creates a screen-local sub-tab strip; returns the HBox so callers can append.
func make_strip() -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 2)
	strip.mouse_filter = Control.MOUSE_FILTER_PASS
	return strip


## The height a card on a sideways shelf may take: the scroll's height minus
## the scrollbar that runs under the cards. Cards cut taller than this push the
## shelf past the glass and clip whatever sits beneath it.
static func shelf_card_height(scroll: ScrollContainer, floor_height: float = 110.0) -> float:
	var bar: float = scroll.get_h_scroll_bar().get_combined_minimum_size().y
	return maxf(floor_height, scroll.size.y - bar - 4.0)


## A caption + value pair stacked, for status grids.
static func stat_cell(caption: String) -> Dictionary:
	var cell := VBoxContainer.new()
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_theme_constant_override("separation", 0)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head: Label = CabinetStyle.caption(caption, CabinetStyle.FONT_TINY, CabinetStyle.AMBER_DIM)
	cell.add_child(head)
	var value: Label = CabinetStyle.mono("—", CabinetStyle.FONT_SMALL, CabinetStyle.PHOSPHOR)
	cell.add_child(value)
	return {"cell": cell, "caption": head, "value": value}


## A detail column: a scrolling list of `ConsoleStyle.detail_line` rows under a
## heading, in the cabinet's palette.
static func detail_rows(host: VBoxContainer, rows: Array, font: int = CabinetStyle.FONT_TINY) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()
	for raw in rows:
		var row: Variant = raw
		if row is Dictionary and row.has("role") and not row.has("color"):
			var entry: Dictionary = (row as Dictionary).duplicate()
			match str(entry["role"]):
				"danger", "red", "heat":
					entry["color"] = CabinetStyle.RED
				"warning", "risk":
					entry["color"] = CabinetStyle.AMBER
				"money", "success":
					entry["color"] = CabinetStyle.PHOSPHOR
				_:
					entry["color"] = CabinetStyle.WHITE
			row = entry
		var line: Control = ConsoleStyle.detail_line(row, font, 6)
		if line != null:
			host.add_child(line)
