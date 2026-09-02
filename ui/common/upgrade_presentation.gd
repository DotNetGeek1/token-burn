class_name UpgradePresentation
extends RefCounted

## Turns an upgrade definition into a compact market card: which shelf it sits
## on, its colour, the one-line effect summary, and — when it is out of reach —
## the reason, so a locked item explains itself instead of just going grey.

const GROUPS := {
	"cooling": {"label": "Cooling", "color": "blue"},
	"workspace": {"label": "Workspace", "color": "purple"},
	"hardware": {"label": "Hardware", "color": "orange"},
	"component": {"label": "Components", "color": "yellow"},
	"dwelling": {"label": "Property", "color": "green"},
}

const GROUP_ORDER := ["hardware", "component", "cooling", "workspace"]

## The Market's hardware counters. Where the run happens is a chapter rather
## than a purchase, so there is no property shelf: everything here fills the
## space the run already has.
const TABS := [
	{"key": "hardware", "label": "HARDWARE", "groups": ["hardware", "component", "cooling", "workspace"]},
]


static func tab_for_group(key: String) -> String:
	for tab in TABS:
		if key in Array(tab["groups"]):
			return str(tab["key"])
	return "hardware"


## Shelf for an upgrade. Cooling and board upgrades are hardware by category but
## are separate purchases in the player's head, so they get their own shelves.
static func group_key(upgrade: UpgradeDefinition) -> String:
	var tags: Array = Array(upgrade.tags)
	if "cooling" in tags:
		return "cooling"
	if "board" in tags:
		return "workspace"
	if GROUPS.has(upgrade.category):
		return upgrade.category
	return "hardware"


static func group_label(key: String) -> String:
	return str(GROUPS.get(key, {}).get("label", key.to_upper()))


static func group_color(key: String) -> Color:
	return UiThemeBuilder.color(str(GROUPS.get(key, {}).get("color", "grey")))


## One line of consequence, built from the effects the upgrade actually applies.
static func effect_line(upgrade: UpgradeDefinition) -> String:
	var parts: PackedStringArray = []
	var hardware: Dictionary = _curve(upgrade)
	var token_line: String = token_rate_text(float(hardware.get("token_rate", 0.0)))
	if token_line != "":
		parts.append(token_line)
	if float(hardware.get("power_draw", 0.0)) > 0.0:
		parts.append("%dW draw" % int(hardware["power_draw"]))
	for effect in upgrade.effects:
		var line: String = _effect_text(effect)
		if line != "":
			parts.append(line)
	if upgrade.recurring_cost_delta > 0.0:
		parts.append("%s/round" % NumberFormat.format_cash(upgrade.recurring_cost_delta))
	if upgrade.category == "component" and upgrade.requires_hardware != "":
		var fitted: int = UpgradeSystem.installed_count(Simulation.run_state, upgrade.component_key)
		var hosts: int = UpgradeSystem.installed_count(Simulation.run_state, upgrade.requires_hardware)
		parts.append("%d of %d fitted" % [fitted, hosts])
	elif UpgradeSystem.occupies_floor(ContentDatabase.balance.get("hardware_curves", {}), upgrade.hardware_key):
		parts.append("1 floor slot")
	if parts.is_empty():
		return upgrade.description
	return " · ".join(parts)


## Stats for whatever this upgrade installs, machine or component.
static func curve(upgrade: UpgradeDefinition) -> Dictionary:
	var key: String = UpgradeSystem.installed_key(upgrade)
	if key == "":
		return {}
	return Dictionary(ContentDatabase.balance.get("hardware_curves", {}).get(key, {}))


static func _curve(upgrade: UpgradeDefinition) -> Dictionary:
	return curve(upgrade)


## Whether the thing this upgrade installs stands on the floor rather than
## fitting inside a machine that is already there.
static func occupies_floor(upgrade: UpgradeDefinition) -> bool:
	return UpgradeSystem.occupies_floor(
		ContentDatabase.balance.get("hardware_curves", {}), upgrade.hardware_key
	)


## Raw curve rate plus, when modifiers are active, what that adds to the HUD.
static func token_rate_text(raw_rate: float) -> String:
	if raw_rate <= 0.0:
		return ""
	var line: String = "%s token rate" % NumberFormat.format_token_rate(raw_rate)
	var scale: float = ComputeSystem.current_rate_scale(Simulation.run_state)
	if absf(scale - 1.0) > 0.001:
		line += " (%s now)" % NumberFormat.format_token_rate(raw_rate * scale)
	return line


static func _effect_text(effect: EffectDefinition) -> String:
	var amount: float = float(effect.value) if effect.value is float or effect.value is int else 0.0
	match effect.target:
		"compute.cooling":
			return "+%d cooling" % int(amount)
		"build.board.slot_count":
			return "+%d pipeline slot" % int(amount)
		_:
			return ""


## Why the player cannot have this yet, as short chips rather than sentences.
static func blockers(upgrade: UpgradeDefinition, affordable: bool) -> Array:
	var chips: Array = []
	var level: int = UpgradeSystem.upgrade_level(Simulation.run_state, upgrade.id)
	var cost: float = UpgradeSystem.purchase_cost(upgrade, level)
	if not affordable:
		var shortfall: float = cost - float(Simulation.run_state.economy.get("cash", 0.0))
		chips.append({
			"text": "Need %s more" % NumberFormat.format_cash(maxf(0.0, shortfall)),
			"role": "danger",
		})
	var cooling: Dictionary = cooling_shortfall(upgrade)
	if not cooling.is_empty():
		chips.append({
			"text": "Cooling %d / %d" % [int(cooling["have"]), int(cooling["need"])],
			"role": "heat",
		})
	if hardware_space_full(upgrade):
		chips.append({"text": "No hardware space", "role": "danger"})
	if component_capacity_reached(upgrade):
		chips.append({"text": "Every %s already has one" % _host_name(upgrade), "role": "warning"})
	var prerequisite: String = prerequisite_text(upgrade)
	if prerequisite != "":
		chips.append({"text": prerequisite, "role": "warning"})
	return chips


## Named after the thing the player has to get first, so a locked card reads as
## the next step rather than as a dead one. Premises are the exception: the run
## cannot move, so the card says which chapter this belongs to instead.
static func prerequisite_text(upgrade: UpgradeDefinition) -> String:
	if UpgradeSystem.prerequisites_met(Simulation.run_state, upgrade, ContentDatabase):
		return ""
	if upgrade.requires_dwelling != "":
		return "Needs the %s or better" % _dwelling_name(upgrade.requires_dwelling)
	if upgrade.requires_hardware != "" and UpgradeSystem.installed_count(
		Simulation.run_state, upgrade.requires_hardware
	) <= 0:
		return "Needs a %s to fit it to" % _host_name(upgrade)
	var required: UpgradeDefinition = ContentDatabase.get_upgrade(upgrade.requires_upgrade)
	if required != null:
		return "Requires %s" % required.name
	return "Locked"


static func _dwelling_name(key: String) -> String:
	return key.replace("_", " ").capitalize()


## The machine a component bolts onto, named the way the Market names it.
static func _host_name(upgrade: UpgradeDefinition) -> String:
	return hardware_name(upgrade.requires_hardware)


## Player-facing name for something installed, taken from the upgrade that sold
## it so the Market and the owned list never disagree.
static func hardware_name(key: String) -> String:
	var upgrade: UpgradeDefinition = UpgradeSystem.upgrade_for_installed(ContentDatabase, key)
	if upgrade != null:
		return upgrade.name
	return key.replace("_", " ").capitalize()


## Cooling the upgrade would demand versus what the space provides, or {} when
## the room can keep up.
static func cooling_shortfall(upgrade: UpgradeDefinition) -> Dictionary:
	var hardware: Dictionary = _curve(upgrade)
	if hardware.is_empty():
		return {}
	var extra_cooling: float = 0.0
	for effect in upgrade.effects:
		if effect.target == "compute.cooling":
			extra_cooling += float(effect.value)
	var outlook: Dictionary = Simulation.heat_outlook(
		float(hardware.get("power_draw", 0.0)), extra_cooling, int(hardware.get("work_tier", 0))
	)
	if bool(outlook.get("sustainable", true)):
		return {}
	return {
		"have": int(outlook.get("cooling", 0.0)),
		"need": int(ceil(float(outlook.get("cooling_needed", 0.0)))),
		"heat_per_prompt": float(outlook.get("heat_per_prompt", 0.0)),
	}


## The dwelling has room for a limited amount of compute, and the sim enforces
## it, so a bedroom cannot hold a GPU rack no matter how much cash is in hand.
static func hardware_space_full(upgrade: UpgradeDefinition) -> bool:
	return UpgradeSystem.hardware_space_full(Simulation.run_state, upgrade, ContentDatabase)


## Whether every machine that could take this component already has one.
static func component_capacity_reached(upgrade: UpgradeDefinition) -> bool:
	if upgrade.requires_hardware == "":
		return false
	if UpgradeSystem.installed_count(Simulation.run_state, upgrade.requires_hardware) <= 0:
		# Reported as a missing prerequisite instead, which is the more useful
		# thing to say when there is no host at all.
		return false
	return UpgradeSystem.component_capacity_reached(Simulation.run_state, upgrade, ContentDatabase)


## Hardware slots the dwelling has, and how many are taken. Shown on the
## Hardware counter so "no space" has a number behind it.
static func hardware_space() -> Dictionary:
	return {
		"dwelling": _dwelling_name(str(Simulation.run_state.build.get("dwelling", "bedroom"))),
		"used": UpgradeSystem.hardware_slots_used(Simulation.run_state, ContentDatabase),
		"total": UpgradeSystem.hardware_slots_total(Simulation.run_state, ContentDatabase),
	}


## Everything installed, one row per machine model with the count beside it, so
## the owned list reads as an inventory rather than a repeated list.
static func installed_inventory() -> Array:
	var curves: Dictionary = ContentDatabase.balance.get("hardware_curves", {})
	var order: Array = []
	var counts: Dictionary = {}
	for entry in Simulation.run_state.build.get("hardware", []):
		var key: String = str(entry)
		if not curves.has(key):
			continue
		if not counts.has(key):
			counts[key] = 0
			order.append(key)
		counts[key] = int(counts[key]) + 1
	var rows: Array = []
	for key in order:
		var curve: Dictionary = Dictionary(curves.get(key, {}))
		rows.append({
			"key": key,
			"name": hardware_name(key),
			"count": int(counts[key]),
			"component": bool(curve.get("component", false)),
			"token_rate": float(curve.get("token_rate", 0.0)) * float(counts[key]),
			"power_draw": float(curve.get("power_draw", 0.0)) * float(counts[key]),
			"refund": UpgradeSystem.sell_refund(Simulation.run_state, key, ContentDatabase),
			"sell_reason": UpgradeSystem.sell_reason(Simulation.run_state, key, ContentDatabase),
		})
	return rows
