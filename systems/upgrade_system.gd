class_name UpgradeSystem
extends RefCounted

## What a machine fetches second-hand once it has been racked, powered and run
## hot for a few rounds. Half is generous enough that trading up is a real option and
## mean enough that churning kit is never free.
const SELL_REFUND_RATIO := 0.5


static func upgrade_level(run_state: RunState, upgrade_id: String) -> int:
	var levels: Dictionary = run_state.build.get("upgrade_levels", {})
	return int(levels.get(upgrade_id, 0))


static func purchase_cost(upgrade: UpgradeDefinition, level: int) -> float:
	if upgrade.repeatable:
		return upgrade.cost * pow(upgrade.cost_growth, float(level))
	return upgrade.cost


static func is_maxed(run_state: RunState, upgrade: UpgradeDefinition) -> bool:
	if not upgrade.repeatable or upgrade.max_level <= 0:
		return false
	return upgrade_level(run_state, upgrade.id) >= upgrade.max_level


## The key an upgrade writes into `build.hardware` when it is bought. Machines
## and the components bolted to them both live in that list, which is what lets
## ComputeSystem add up throughput and draw without knowing the difference.
static func installed_key(upgrade: UpgradeDefinition) -> String:
	if upgrade.category == "component":
		return upgrade.component_key
	if upgrade.category == "hardware":
		return upgrade.hardware_key
	return ""


## Whether the run has the thing this upgrade sits on top of: premises at least
## as serious as it needs, the machine it bolts onto, or the cloud account the
## rest of that shelf is billed against. Property names the rung below it, which
## makes the ladder climbable only one step at a time; a rack names the smallest
## room that can hold it.
static func prerequisites_met(run_state: RunState, upgrade: UpgradeDefinition, content_db: Node) -> bool:
	if upgrade.requires_dwelling != "":
		var have: int = dwelling_tier(str(run_state.build.get("dwelling", "")), content_db)
		if have < dwelling_tier(upgrade.requires_dwelling, content_db):
			return false
	if upgrade.requires_upgrade != "":
		if not (upgrade.requires_upgrade in run_state.build.get("upgrades", [])):
			return false
	if upgrade.requires_hardware != "":
		if installed_count(run_state, upgrade.requires_hardware) <= 0:
			return false
	return true


static func dwelling_tier(key: String, content_db: Node) -> int:
	var tiers: Dictionary = content_db.balance.get("economy", {}).get("infrastructure_tiers", {})
	return int(Dictionary(tiers.get("dwelling", {})).get(key, 0))


static func installed_count(run_state: RunState, key: String) -> int:
	if key == "":
		return 0
	var count: int = 0
	for entry in run_state.build.get("hardware", []):
		if str(entry) == key:
			count += 1
	return count


## Only machines that produce tokens under their own name stand on the floor.
## An air conditioner does not, and neither does a graphics card that went
## inside a desktop already standing there.
static func occupies_floor(curves: Dictionary, key: String) -> bool:
	var entry: Dictionary = Dictionary(curves.get(key, {}))
	if bool(entry.get("component", false)):
		return false
	return float(entry.get("token_rate", 0.0)) > 0.0


static func hardware_slots_used(run_state: RunState, content_db: Node) -> int:
	var curves: Dictionary = content_db.balance.get("hardware_curves", {})
	var used: int = 0
	for key in run_state.build.get("hardware", []):
		if occupies_floor(curves, str(key)):
			used += 1
	return used


static func hardware_slots_total(run_state: RunState, content_db: Node) -> int:
	var dwelling: String = str(run_state.build.get("dwelling", "bedroom"))
	var costs: Dictionary = content_db.balance.get("dwelling_costs", {}).get(dwelling, {})
	return int(costs.get("hardware_slots", 0))


## The dwelling only has so much floor, and every machine standing on it counts,
## including the second and third of the same model.
static func hardware_space_full(run_state: RunState, upgrade: UpgradeDefinition, content_db: Node) -> bool:
	var curves: Dictionary = content_db.balance.get("hardware_curves", {})
	if not occupies_floor(curves, installed_key(upgrade)):
		return false
	var total: int = hardware_slots_total(run_state, content_db)
	if total <= 0:
		return false
	return hardware_slots_used(run_state, content_db) >= total


## A component goes inside a machine, so the run can only fit as many as it has
## machines to fit them to.
static func component_capacity_reached(run_state: RunState, upgrade: UpgradeDefinition, content_db: Node) -> bool:
	if upgrade.category != "component":
		return false
	var hosts: int = installed_count(run_state, upgrade.requires_hardware)
	return installed_count(run_state, upgrade.component_key) >= hosts


func purchase(run_state: RunState, upgrade_id: String, content_db: Node, effect_resolver: EffectResolver, economy_system: EconomySystem) -> bool:
	var upgrade: UpgradeDefinition = content_db.get_upgrade(upgrade_id)
	if upgrade == null:
		return false
	if not _passes_gates(run_state, upgrade, content_db):
		return false
	var level: int = upgrade_level(run_state, upgrade_id)
	var cost: float = purchase_cost(upgrade, level)
	if not economy_system.purchase(run_state, cost, "upgrade:%s" % upgrade_id):
		return false
	run_state.economy["recurring_costs"] = float(run_state.economy.get("recurring_costs", 0.0)) + upgrade.recurring_cost_delta
	if upgrade.repeatable:
		if not run_state.build.has("upgrade_levels"):
			run_state.build["upgrade_levels"] = {}
		run_state.build["upgrade_levels"][upgrade_id] = level + 1
	match upgrade.category:
		"hardware", "component":
			# Workspace upgrades sit in the hardware category without being
			# machines; they change the board rather than the rig.
			var key: String = installed_key(upgrade)
			if key != "":
				run_state.build["hardware"].append(key)
		"dwelling":
			_move_in(run_state, upgrade, content_db)
		"cloud":
			run_state.build["cloud_tier"] = upgrade_id
		"advertising":
			run_state.build["advertising_tier"] = upgrade_id
	if not upgrade.repeatable:
		run_state.build["upgrades"].append(upgrade_id)
	effect_resolver.apply_effects(run_state, upgrade.effects, "upgrade.%s" % upgrade_id)
	return true


func _move_in(run_state: RunState, upgrade: UpgradeDefinition, content_db: Node) -> void:
	var dwelling_key: String = upgrade.dwelling_key if upgrade.dwelling_key != "" else upgrade.id
	run_state.build["dwelling"] = dwelling_key
	var dwelling_costs: Dictionary = content_db.balance.get("dwelling_costs", {})
	if not dwelling_costs.has(dwelling_key):
		return
	var dwelling: Dictionary = dwelling_costs[dwelling_key]
	var rent_multiplier: float = float(run_state.economy.get("rent_multiplier", 1.0))
	run_state.economy["round_rent"] = float(dwelling.get("rent", run_state.economy["round_rent"])) * rent_multiplier
	run_state.compute["cooling"] = float(run_state.compute.get("cooling", 0.0)) + float(dwelling.get("cooling_capacity", 0.0))


func can_purchase(run_state: RunState, upgrade_id: String, content_db: Node) -> bool:
	var upgrade: UpgradeDefinition = content_db.get_upgrade(upgrade_id)
	if upgrade == null:
		return false
	if not _passes_gates(run_state, upgrade, content_db):
		return false
	var level: int = upgrade_level(run_state, upgrade_id)
	return float(run_state.economy.get("cash", 0.0)) >= purchase_cost(upgrade, level)


## Every refusal that is not about cash, shared by the check and the purchase so
## the Market can never offer a button the sim would decline.
func _passes_gates(run_state: RunState, upgrade: UpgradeDefinition, content_db: Node) -> bool:
	if is_maxed(run_state, upgrade):
		return false
	if not upgrade.repeatable and upgrade.id in run_state.build["upgrades"]:
		return false
	if not prerequisites_met(run_state, upgrade, content_db):
		return false
	if hardware_space_full(run_state, upgrade, content_db):
		return false
	if component_capacity_reached(run_state, upgrade, content_db):
		return false
	return true


# --- Selling -----------------------------------------------------------------

## The upgrade that installed a given machine or component, or null for kit the
## run began with.
static func upgrade_for_installed(content_db: Node, key: String) -> UpgradeDefinition:
	for upgrade in content_db.upgrades:
		if installed_key(upgrade) == key:
			return upgrade
	return null


## What the run gets back for one unit of `key`, priced off the copy most
## recently bought so scaling up and then down is not an arbitrage.
static func sell_refund(run_state: RunState, key: String, content_db: Node) -> float:
	var upgrade: UpgradeDefinition = upgrade_for_installed(content_db, key)
	if upgrade == null:
		return 0.0
	var level: int = maxi(0, upgrade_level(run_state, upgrade.id) - 1)
	return purchase_cost(upgrade, level) * SELL_REFUND_RATIO


## Why this unit cannot go, as a sentence for the player, or "" when it can.
static func sell_reason(run_state: RunState, key: String, content_db: Node) -> String:
	if installed_count(run_state, key) <= 0:
		return "You do not own one of those."
	var upgrade: UpgradeDefinition = upgrade_for_installed(content_db, key)
	if upgrade == null:
		return "That came with the run. Nobody will take it off your hands."
	var curves: Dictionary = content_db.balance.get("hardware_curves", {})
	if occupies_floor(curves, key):
		if hardware_slots_used(run_state, content_db) <= 1:
			return "This is the only machine you have. Selling it leaves nothing to burn with."
		var orphan: String = _orphaned_component(run_state, key, content_db)
		if orphan != "":
			return "Take the %s out of it first." % orphan
	return ""


## A component with nowhere left to live if one of its hosts goes.
static func _orphaned_component(run_state: RunState, host_key: String, content_db: Node) -> String:
	var hosts_after: int = installed_count(run_state, host_key) - 1
	for upgrade in content_db.upgrades:
		if upgrade.category != "component" or upgrade.requires_hardware != host_key:
			continue
		if installed_count(run_state, upgrade.component_key) > hosts_after:
			return upgrade.name
	return ""


## Decommissions one unit: it comes off the books, out of the floor plan, and
## whatever cooling and standing bill it brought with it goes too.
func sell(run_state: RunState, key: String, content_db: Node, economy_system: EconomySystem) -> bool:
	if sell_reason(run_state, key, content_db) != "":
		return false
	var upgrade: UpgradeDefinition = upgrade_for_installed(content_db, key)
	if upgrade == null:
		return false
	var refund: float = sell_refund(run_state, key, content_db)
	var hardware: Array = run_state.build["hardware"]
	hardware.remove_at(hardware.find(key))
	run_state.build["hardware"] = hardware
	if upgrade.repeatable:
		var level: int = maxi(0, upgrade_level(run_state, upgrade.id) - 1)
		if level <= 0:
			run_state.build.get("upgrade_levels", {}).erase(upgrade.id)
		else:
			run_state.build["upgrade_levels"][upgrade.id] = level
	else:
		run_state.build["upgrades"].erase(upgrade.id)
	run_state.economy["recurring_costs"] = maxf(
		0.0,
		float(run_state.economy.get("recurring_costs", 0.0)) - upgrade.recurring_cost_delta
	)
	run_state.compute["cooling"] = maxf(
		0.0, float(run_state.compute.get("cooling", 0.0)) - _cooling_from(upgrade)
	)
	# Credited rather than booked as income: selling the furniture is not the
	# business earning, and ascension qualification reads income.
	economy_system.credit(run_state, refund, "hardware_sale:%s" % key)
	return true


static func _cooling_from(upgrade: UpgradeDefinition) -> float:
	var total: float = 0.0
	for effect in upgrade.effects:
		if effect.target == "compute.cooling":
			total += float(effect.value)
	return total
