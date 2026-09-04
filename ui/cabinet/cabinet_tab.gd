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


## Tones the commit button can take: a plain red face, or the hazard-framed
## face that asks for a hold.
const TONE_NORMAL := "normal"
const TONE_DANGER := "danger"

## How the button confirms: a single press, or a hold of `hold_seconds`.
const CONFIRM_PRESS := "press"
const CONFIRM_HOLD := "hold"

## The default hold, matching HoldGesture.
const DEFAULT_HOLD_SECONDS := 0.65

## Blockers the tabs share, so the button says the same thing for the same
## reason everywhere. A disabled action always carries one in `sub`.
const BLOCK_SELECT_ITEM := "SELECT ITEM"
const BLOCK_SELECT_BAY := "SELECT A BAY"
const BLOCK_COOL_FIRST := "COOL FIRST"
const BLOCK_MARKET_CLOSED := "MARKET CLOSED"
const BLOCK_TAKE_CONTRACT := "TAKE A CONTRACT FIRST"

## Blockers that mean "nothing is picked yet" rather than "the pick cannot be
## acted on". The commit button shows the shutter (idle) for these and the dark
## face with the reason (blocked) for everything else.
const SELECTION_BLOCKERS: Array[String] = [BLOCK_SELECT_ITEM, BLOCK_SELECT_BAY, BLOCK_TAKE_CONTRACT]


## What the commit button does while this tab is up. The full shape:
##
##   {
##     "label": String,        # the verb on the face: "ACCEPT", "SEAT", "SELL"
##     "enabled": bool,        # false → the button is idle/blocked and `sub` is the reason
##     "sub": String,          # consequence when enabled ("$570 · 7 prompts"),
##                             # plain-language blocker when not ("NEED $240 MORE")
##     "tone": String,         # TONE_NORMAL (red face) | TONE_DANGER (hazard frame)
##     "confirm": String,      # CONFIRM_PRESS (single press) | CONFIRM_HOLD (hold to fire)
##     "hold_seconds": float,  # length of the hold when `confirm` is hold
##     "pressed": Callable,    # fired once on press, or once when the hold completes
##   }
##
## Tabs may return the old `{label, enabled, sub, pressed}` shape, with or
## without the ad-hoc `danger: true`; `normalize_action` fills the rest in
## (missing tone → normal, missing confirm → press, `danger` → danger + hold).
## An empty dictionary hands the button back to the shell's own BURN.
func primary_action() -> Dictionary:
	return {}


## Fills a `primary_action` dictionary out to the full contract so the shell
## and the button only ever read one shape. Idempotent on a full one.
static func normalize_action(action: Dictionary) -> Dictionary:
	if action.is_empty():
		return {}
	var out: Dictionary = action.duplicate()
	out["label"] = str(out.get("label", ""))
	out["enabled"] = bool(out.get("enabled", false))
	out["sub"] = str(out.get("sub", ""))
	var legacy_danger: bool = bool(out.get("danger", false))
	var tone: String = str(out.get("tone", TONE_DANGER if legacy_danger else TONE_NORMAL))
	if tone != TONE_DANGER:
		tone = TONE_NORMAL
	out["tone"] = tone
	var confirm: String = str(out.get("confirm", CONFIRM_HOLD if legacy_danger else CONFIRM_PRESS))
	if confirm != CONFIRM_HOLD:
		confirm = CONFIRM_PRESS
	out["confirm"] = confirm
	out["hold_seconds"] = maxf(0.05, float(out.get("hold_seconds", DEFAULT_HOLD_SECONDS)))
	if not (out.get("pressed") is Callable):
		out["pressed"] = Callable()
	out["danger"] = tone == TONE_DANGER
	return out


## A disabled action that explains itself. `label` keeps the verb the player
## would see once the blocker clears so the face does not go blank.
static func blocked_action(label: String, reason: String) -> Dictionary:
	return normalize_action({
		"label": label,
		"enabled": false,
		"sub": reason,
		"pressed": Callable(),
	})


## The blocker for a purchase the player cannot afford yet.
static func need_more_blocker(shortfall: int) -> String:
	return "NEED %s MORE" % NumberFormat.format_cash(float(maxi(1, shortfall)))


## Scroll positions of every ScrollContainer under `root`, keyed by node
## path, so a refresh that rebuilds the cards can put the shelf back where the
## player left it. Pair with `restore_scroll`.
static func capture_scroll(root: Node) -> Dictionary:
	var out: Dictionary = {}
	_walk_scrolls(root, root, out)
	return out


static func restore_scroll(root: Node, saved: Dictionary) -> void:
	if saved.is_empty():
		return
	for key in saved:
		var node: Node = root.get_node_or_null(NodePath(str(key)))
		if node is ScrollContainer:
			var at: Vector2 = saved[key]
			(node as ScrollContainer).set_deferred("scroll_horizontal", int(at.x))
			(node as ScrollContainer).set_deferred("scroll_vertical", int(at.y))


static func _walk_scrolls(root: Node, node: Node, out: Dictionary) -> void:
	if node is ScrollContainer:
		var scroll := node as ScrollContainer
		out[str(root.get_path_to(scroll))] = Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
	for child in node.get_children():
		_walk_scrolls(root, child, out)


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
##
## A sideways ScrollContainer grows to its cards' minimum height, so measuring
## the scroll alone would let one tall card make the next batch taller still;
## the room the tab itself has under the scroll's top edge is the real cap.
static func shelf_card_height(scroll: ScrollContainer, floor_height: float = 110.0) -> float:
	var bar: float = scroll.get_h_scroll_bar().get_combined_minimum_size().y
	var available: float = scroll.size.y
	var tab: Node = scroll.get_parent()
	while tab != null and not (tab is CabinetTab):
		tab = tab.get_parent()
	if tab is Control and scroll.is_inside_tree() and (tab as Control).size.y > 0.0:
		var top: float = scroll.global_position.y - (tab as Control).global_position.y
		available = minf(available, (tab as Control).size.y - top - 6.0)
	return maxf(floor_height, available - bar - 4.0)


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
## heading, in the cabinet's palette. These rows are body copy, so they never
## print under the body floor.
static func detail_rows(host: VBoxContainer, rows: Array, font: int = CabinetStyle.FONT_MIN_BODY) -> void:
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
