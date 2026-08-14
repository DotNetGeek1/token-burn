class_name UpgradeSystem
extends RefCounted

## What a machine fetches second-hand once it has been racked, powered and run
## hot for a few rounds. Half is generous enough that trading up is a real option and
## mean enough that churning kit is never free.
const SELL_REFUND_RATIO := 0.5


static func upgrade_level(run_state: RunState, upgrade_id: String) -> int:
	var levels: Dictionary = run_state.build.get("upgrade_levels", {})
	return int(levels.get(upgrade_id, 0))


## The one ledger of how many of each upgrade id this run owns, one-offs
## included at a count of 1. Everything that only needs "how many" — rather
## than the older split of a hardware array, a one-off list and a repeatable
## level map — should read this instead.
static func upgrade_counts(run_state: RunState) -> Dictionary:
	return Dictionary(run_state.build.get("upgrade_counts", {}))


static func _set_upgrade_count(run_state: RunState, upgrade_id: String, count: int) -> void:
	if not run_state.build.has("upgrade_counts") or not (run_state.build["upgrade_counts"] is Dictionary):
		run_state.build["upgrade_counts"] = {}
	if count <= 0:
		run_state.build["upgrade_counts"].erase(upgrade_id)
	else:
		run_state.build["upgrade_counts"][upgrade_id] = count


static func _increment_upgrade_count(run_state: RunState, upgrade_id: String) -> void:
	_set_upgrade_count(run_state, upgrade_id, int(upgrade_counts(run_state).get(upgrade_id, 0)) + 1)


## For the rare grant that is not a purchase — a meta unlock handing over an
## upgrade for free — so the ledger still knows about kit the run owns
## without pretending `EconomySystem` ever charged for it.
static func record_free_grant(run_state: RunState, upgrade_id: String) -> void:
	_increment_upgrade_count(run_state, upgrade_id)


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
## rest of that shelf is billed against. A rack names the smallest room that can
## hold it, and since a run never moves, that is really a statement about which
## chapter of the campaign the rack belongs to.
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
	return int(_location_stats(run_state, content_db).get("hardware_slots", 0))


## What the run's location keeps cool on its own, before anything is installed.
## Read from the location every time rather than banked into a running total, so
## it can only ever count once however often the rig is recalculated.
static func location_cooling(run_state: RunState, content_db: Node) -> float:
	return float(_location_stats(run_state, content_db).get("cooling_capacity", 0.0))


## Cooling from kit the run has bought, summed from what is actually installed.
## Derived rather than accumulated: a cooler that was sold takes its cooling with
## it without anyone having to remember to subtract it.
static func installed_cooling(run_state: RunState, content_db: Node) -> float:
	var total: float = 0.0
	for key in run_state.build.get("hardware", []):
		var upgrade: UpgradeDefinition = upgrade_for_installed(content_db, str(key))
		if upgrade != null:
			total += cooling_from(upgrade)
	return total


static func _location_stats(run_state: RunState, content_db: Node) -> Dictionary:
	var dwelling: String = str(run_state.build.get("dwelling", "bedroom"))
	return Dictionary(content_db.balance.get("dwelling_costs", {}).get(dwelling, {}))


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
	run_state.economy["recurring_costs_base"] = (
		float(run_state.economy.get("recurring_costs_base", 0.0)) + upgrade.recurring_cost_delta
	)
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
		"cloud":
			run_state.build["cloud_tier"] = upgrade_id
		"advertising":
			run_state.build["advertising_tier"] = upgrade_id
	if not upgrade.repeatable:
		run_state.build["upgrades"].append(upgrade_id)
	_increment_upgrade_count(run_state, upgrade_id)
	effect_resolver.apply_effects(run_state, upgrade.effects, "upgrade.%s" % upgrade_id)
	return true


## Installs an upgrade the run did not pay for: the kit carried over from the
## location the player just beat. It is otherwise a purchase — the standing bill,
## the floor space and the effects all land the same way — because a machine that
## costs nothing to keep would make moving up strictly free.
##
## The affordability and one-per-run gates are deliberately skipped: this kit was
## already bought and already passed them, and re-checking cash against a stake
## that has not been paid in yet would drop half the rig on the way.
func install_carried(
	run_state: RunState, upgrade_id: String, content_db: Node, effect_resolver: EffectResolver
) -> bool:
	var upgrade: UpgradeDefinition = content_db.get_upgrade(upgrade_id)
	if upgrade == null or upgrade.category == "dwelling":
		return false
	# Floor space is the one gate that still applies: it belongs to the new room
	# rather than to the kit, and every location has at least as much as the last.
	if hardware_space_full(run_state, upgrade, content_db):
		return false
	run_state.economy["recurring_costs_base"] = (
		float(run_state.economy.get("recurring_costs_base", 0.0)) + upgrade.recurring_cost_delta
	)
	if upgrade.repeatable:
		if not run_state.build.has("upgrade_levels"):
			run_state.build["upgrade_levels"] = {}
		run_state.build["upgrade_levels"][upgrade_id] = upgrade_level(run_state, upgrade_id) + 1
	match upgrade.category:
		"hardware", "component":
			var key: String = installed_key(upgrade)
			if key != "":
				run_state.build["hardware"].append(key)
		"cloud":
			run_state.build["cloud_tier"] = upgrade_id
		"advertising":
			run_state.build["advertising_tier"] = upgrade_id
	if not upgrade.repeatable and not (upgrade_id in run_state.build["upgrades"]):
		run_state.build["upgrades"].append(upgrade_id)
	_increment_upgrade_count(run_state, upgrade_id)
	effect_resolver.apply_effects(run_state, upgrade.effects, "upgrade.%s" % upgrade_id)
	return true


## Everything the run bought, as a level count per upgrade id, in the order the
## campaign has to reinstall it: a component cannot go into a machine that has
## not been racked yet.
##
## Only hardware and the components that bolt onto it are rig: cash, modules
## and perks reset every chapter by design, and so must anything else the
## Market sells — cloud tiers, advertising tiers, workspace upgrades — or it
## arrives in the next location already installed and already billing.
static func carriable_rig_levels(run_state: RunState, content_db: Node) -> Dictionary:
	var levels: Dictionary = upgrade_counts(run_state).duplicate(true)
	for upgrade_id in levels.keys():
		var upgrade: UpgradeDefinition = content_db.get_upgrade(str(upgrade_id))
		if upgrade == null or not (upgrade.category == "hardware" or upgrade.category == "component"):
			levels.erase(upgrade_id)
	return levels


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
	# Premises are a chapter of the campaign, not stock. They still exist as
	# content — the location a run happens in is described by one — but no run
	# can buy its way from one to another.
	if upgrade.category == "dwelling":
		return false
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
		_set_upgrade_count(run_state, upgrade.id, level)
	else:
		run_state.build["upgrades"].erase(upgrade.id)
		_set_upgrade_count(run_state, upgrade.id, 0)
	run_state.economy["recurring_costs_base"] = maxf(
		0.0,
		float(run_state.economy.get("recurring_costs_base", 0.0)) - upgrade.recurring_cost_delta
	)
	# Nothing is done about cooling here: it is derived from what is installed,
	# so removing the unit has already removed its contribution.
	# Credited rather than booked as income: selling the furniture is not the
	# business earning, and ascension qualification reads income.
	economy_system.credit(run_state, refund, "hardware_sale:%s" % key)
	return true


## Cooling one unit of this upgrade provides, read off the effects it declares.
static func cooling_from(upgrade: UpgradeDefinition) -> float:
	var total: float = 0.0
	for effect in upgrade.effects:
		if effect.target == "compute.cooling":
			total += float(effect.value)
	return total
