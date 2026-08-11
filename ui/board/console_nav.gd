class_name ConsoleNav
extends RefCounted

## The main menu of the game, as rows on the laptop.
##
## There is no navigation bar bolted under the room any more: getting to the job
## board, the market, the build sheet or the contract is something the player
## does on the machine on their desk, in the same phosphor type as everything
## else the machine prints. Both desk consoles share this so the menu is in the
## same place whether or not a burn is running.

## Menu key to the letter printed in its bracket and the label beside it.
const ENTRIES: Array[Dictionary] = [
	{"key": "jobs", "index": "J", "headline": "JOBS"},
	{"key": "build", "index": "B", "headline": "BUILD"},
	{"key": "market", "index": "M", "headline": "MARKET"},
	{"key": "ascend", "index": "A", "headline": "TERMS"},
	{"key": "menu", "index": "X", "headline": "MENU"},
]


## Prints the menu onto a console. `host` is the screen the rows route through:
## it only has to be inside the tree, because every destination is reached by
## calling the shell.
static func mount(laptop: LaptopScreen, host: Node) -> void:
	var rows: Array = []
	for entry in ENTRIES:
		var key: String = str(entry["key"])
		rows.append({
			"key": key,
			"index": str(entry["index"]),
			"headline": str(entry["headline"]),
			"pressed": func() -> void: _go(host, key),
		})
	laptop.set_nav(rows)


## The market is the only line with news to report: cash that can be spent is
## the one thing the player is likely to have forgotten about.
static func refresh(laptop: LaptopScreen) -> void:
	var cash: float = float(Simulation.run_state.economy.get("cash", 0.0))
	var owned: Array = Simulation.run_state.build.get("upgrades", [])
	var affordable: bool = false
	for upgrade in ContentDatabase.upgrades:
		if not (upgrade.id in owned) and upgrade.cost > 0.0 and upgrade.cost <= cash:
			affordable = true
			break
	laptop.set_nav_flag("market", affordable)


static func _go(host: Node, key: String) -> void:
	if not host.is_inside_tree():
		return
	if key == "ascend":
		host.get_tree().call_group("main_ui", "open_ascension_select")
		return
	host.get_tree().call_group("main_ui", "switch_tab", key)
