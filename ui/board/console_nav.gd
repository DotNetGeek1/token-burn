class_name ConsoleNav
extends RefCounted

## The main menu of the game, as notes on the whiteboard.
##
## There is no navigation bar bolted under the room, and no menu strip across
## the bottom of the laptop either: getting to the job board, the market, the
## build sheet or the contract is something the player does by taking the note
## off the wall. The board is the one surface every room hangs, so the menu is
## in the same place whatever premises the operation is working out of, and the
## machine's glass is left for what the machine is actually reporting.

## Menu key to the word written on its note, in the order they are stuck up.
const ENTRIES: Array[Dictionary] = [
	{"key": "jobs", "headline": "JOBS"},
	{"key": "build", "headline": "BUILD"},
	{"key": "market", "headline": "MARKET"},
	{"key": "ascend", "headline": "TERMS"},
	{"key": "menu", "headline": "MENU"},
]


## Writes the menu onto the board. `host` is what the notes route through: it
## only has to be inside the tree, because every destination is reached by
## calling the shell.
static func mount(notes: BoardNotes, host: Node) -> void:
	var rows: Array = []
	for entry in ENTRIES:
		var key: String = str(entry["key"])
		rows.append({
			"key": key,
			"headline": str(entry["headline"]),
			"pressed": func() -> void: _go(host, key),
		})
	notes.set_entries(rows)


## The market is the only note with news to report: cash that can be spent is
## the one thing the player is likely to have forgotten about.
static func refresh(notes: BoardNotes) -> void:
	var cash: float = float(Simulation.run_state.economy.get("cash", 0.0))
	var owned: Array = Simulation.run_state.build.get("upgrades", [])
	var affordable: bool = false
	for upgrade in ContentDatabase.upgrades:
		if not (upgrade.id in owned) and upgrade.cost > 0.0 and upgrade.cost <= cash:
			affordable = true
			break
	notes.set_flag("market", affordable)


static func _go(host: Node, key: String) -> void:
	if not host.is_inside_tree():
		return
	if key == "ascend":
		host.get_tree().call_group("main_ui", "open_ascension_select")
		return
	host.get_tree().call_group("main_ui", "switch_tab", key)
