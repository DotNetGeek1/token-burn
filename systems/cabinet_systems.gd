class_name CabinetSystems
extends RefCounted

## The five purchasable cabinet systems — compute, cooling, power, backplane and
## control — each owned at a tier from 1 to 4 and stored on the run as
## `build.cabinet_systems`. This is the one place a tier is turned into a
## number: the board asks it how many bays it backs, the rig asks it how much
## floor and cooling the room has, and the Market asks it what the next tier
## costs and why it cannot be bought yet.
##
## The tier is the primary source of every capacity; the chapter table
## (`dwelling_costs.json`, keyed by `build.dwelling`) is a permanent floor
## beneath it for the stats chapters out-size the tier table on: floor slots,
## cooling and heat capacity. The datacentre, the grid and the moon hand out
## forty, eighty and a hundred and sixty slots against the Unstable Core's
## sixteen, so those capacities are `max(tier value, chapter floor)` and never
## decrease when a run moves up a chapter.
##
## Bays are the exception: the Workflow Backplane tier is the *only* source of
## safe pipeline capacity. No chapter floor, no bonus stacks on top. A chapter
## move still lifts the tier itself (`raise_to_dwelling`), which is how a
## warehouse run opens with a 7-Bay Rail. Anything the room, a perk or an
## unlock adds arrives as overflow allowance instead (see BoardSystem).
##
## Everything here is static and reads content through `ContentDatabase`
## unless a database is passed in, the same way the other systems do.

const SYSTEM_IDS := ["compute", "cooling", "power", "backplane", "control"]
const MIN_TIER := 1
const MAX_TIER := 4

## Which chapter-table column each floored stat is read from.
const CHAPTER_STATS := ["hardware_slots", "cooling_capacity", "heat_capacity"]
## The one stat that is never floored: the backplane tier is authoritative.
const BACKPLANE_STAT := "bays"

const REASON_MAXED := "MAXED OUT"
const REASON_UNKNOWN := "UNKNOWN SYSTEM"


# --- Content -----------------------------------------------------------------

static func data(content_db: Node = null) -> Dictionary:
	var db: Node = content_db if content_db != null else ContentDatabase
	var stored: Variant = db.get("cabinet_systems")
	return stored if stored is Dictionary else {}


static func tier_range(content_db: Node = null) -> Array:
	var stored: Variant = data(content_db).get("tier_range", null)
	if stored is Array and Array(stored).size() == 2:
		var lo: int = int(Array(stored)[0])
		var hi: int = int(Array(stored)[1])
		if lo >= 1 and hi >= lo:
			return [lo, hi]
	return [MIN_TIER, MAX_TIER]


static func min_tier(content_db: Node = null) -> int:
	return int(tier_range(content_db)[0])


static func max_tier(content_db: Node = null) -> int:
	return int(tier_range(content_db)[1])


## System ids in the authored order, which is also the order migration rows
## are written in. Falls back to the built-in list if content is unavailable.
static func system_ids(content_db: Node = null) -> Array:
	var order: Variant = data(content_db).get("migration_value_order", null)
	if order is Array and not Array(order).is_empty():
		var ids: Array = []
		for entry in Array(order):
			ids.append(str(entry))
		return ids
	var ids_from_systems: Array = []
	for system in Array(data(content_db).get("systems", [])):
		if system is Dictionary:
			ids_from_systems.append(str(system.get("id", "")))
	if not ids_from_systems.is_empty():
		return ids_from_systems
	return SYSTEM_IDS.duplicate()


static func definition(system_id: String, content_db: Node = null) -> Dictionary:
	for system in Array(data(content_db).get("systems", [])):
		if system is Dictionary and str(system.get("id", "")) == system_id:
			return system
	return {}


static func system_name(system_id: String, content_db: Node = null) -> String:
	var found: Dictionary = definition(system_id, content_db)
	return str(found.get("name", system_id.capitalize()))


static func tier_name(system_id: String, tier: int, content_db: Node = null) -> String:
	var names: Array = Array(definition(system_id, content_db).get("tier_names", []))
	var index: int = tier - min_tier(content_db)
	if index < 0 or index >= names.size():
		return "Tier %d" % tier
	return str(names[index])


## The stat keys a system's tiers move: `bays`, `workflows`, `hardware_slots`,
## `cooling_capacity` + `heat_capacity`, `base_token_rate`.
static func stat_keys(system_id: String, content_db: Node = null) -> Array:
	var values: Variant = definition(system_id, content_db).get("tier_values", {})
	return Dictionary(values).keys() if values is Dictionary else []


## The authored value of one stat at one tier, without the chapter floor.
static func tier_value(system_id: String, stat_key: String, tier: int, content_db: Node = null) -> float:
	var values: Variant = definition(system_id, content_db).get("tier_values", {})
	if not values is Dictionary:
		return 0.0
	var column: Variant = Dictionary(values).get(stat_key, null)
	if not column is Array or Array(column).is_empty():
		return 0.0
	var table: Array = column
	var index: int = clampi(tier - min_tier(content_db), 0, table.size() - 1)
	return float(table[index])


static func stat_label(stat_key: String, content_db: Node = null) -> String:
	var labels: Variant = data(content_db).get("stat_labels", {})
	if labels is Dictionary and Dictionary(labels).has(stat_key):
		return str(Dictionary(labels)[stat_key])
	return stat_key.replace("_", " ").to_upper()


# --- Run state ---------------------------------------------------------------

## Every system at the bottom tier: what a run that has bought nothing owns.
static func default_tiers(content_db: Node = null) -> Dictionary:
	var tiers_out: Dictionary = {}
	for system_id in system_ids(content_db):
		tiers_out[str(system_id)] = min_tier(content_db)
	return tiers_out


## A clean copy of the run's tiers: every known system present, integer, and
## inside the tier range. Missing systems read as tier 1. Does not write back.
static func tiers(run_state: RunState, content_db: Node = null) -> Dictionary:
	var stored: Variant = run_state.build.get("cabinet_systems", null)
	var source: Dictionary = stored if stored is Dictionary else {}
	var lo: int = min_tier(content_db)
	var hi: int = max_tier(content_db)
	var result: Dictionary = {}
	for system_id in system_ids(content_db):
		result[str(system_id)] = clampi(int(source.get(str(system_id), lo)), lo, hi)
	return result


static func tier(run_state: RunState, system_id: String, content_db: Node = null) -> int:
	return int(tiers(run_state, content_db).get(system_id, min_tier(content_db)))


static func set_tier(run_state: RunState, system_id: String, new_tier: int, content_db: Node = null) -> void:
	var current: Dictionary = tiers(run_state, content_db)
	current[system_id] = clampi(new_tier, min_tier(content_db), max_tier(content_db))
	run_state.build["cabinet_systems"] = current


## Writes the normalised tiers back onto the run. With `warn` on, a value that
## had to be clamped or invented is reported, which is what a migration wants.
## A run with no tiers at all is derived from the chapter it is in, so a save
## that somehow lost the block still opens with its room's capacities.
static func ensure_state(run_state: RunState, warn: bool = false, content_db: Node = null) -> Dictionary:
	var stored: Variant = run_state.build.get("cabinet_systems", null)
	if not stored is Dictionary or Dictionary(stored).is_empty():
		var derived: Dictionary = derive_from_dwelling(str(run_state.build.get("dwelling", "")), content_db)
		run_state.build["cabinet_systems"] = derived
		return derived
	var source: Dictionary = stored
	var normalised: Dictionary = tiers(run_state, content_db)
	if warn:
		for system_id in normalised.keys():
			if not source.has(system_id):
				push_warning("CabinetSystems: '%s' missing from save, set to tier %d" % [
					system_id, int(normalised[system_id]),
				])
			elif int(source[system_id]) != int(normalised[system_id]):
				push_warning("CabinetSystems: '%s' tier %s clamped to %d" % [
					system_id, str(source[system_id]), int(normalised[system_id]),
				])
	run_state.build["cabinet_systems"] = normalised
	return normalised


static func tier_sum(run_state: RunState, content_db: Node = null) -> int:
	var total: int = 0
	for value in tiers(run_state, content_db).values():
		total += int(value)
	return total


## The cabinet's generation — Improvised Cabinet through Impossible Engine — is
## presentation only. It is a function of the tier sum and nothing else, and
## nothing reads a number back out of it.
static func generation(run_state: RunState, content_db: Node = null) -> Dictionary:
	return generation_for_sum(tier_sum(run_state, content_db), content_db)


static func generation_for_sum(total: int, content_db: Node = null) -> Dictionary:
	var thresholds: Array = Array(data(content_db).get("generation_thresholds", []))
	var index: int = 0
	var name: String = "Improvised Cabinet"
	for i in range(thresholds.size()):
		var entry: Variant = thresholds[i]
		if not entry is Dictionary:
			continue
		if total >= int(entry.get("min_sum", 0)):
			index = i
			name = str(entry.get("name", name))
	return {"index": index, "name": name, "sum": total}


# --- Capacities --------------------------------------------------------------

## What the run's tier is worth for one stat, with the chapter table as a
## floor beneath it (see the class note).
static func capacity(run_state: RunState, system_id: String, stat_key: String, content_db: Node = null) -> float:
	return capacity_at_tier(run_state, system_id, stat_key, tier(run_state, system_id, content_db), content_db)


static func chapter_profile(run_state: RunState, content_db: Node = null) -> Dictionary:
	var profiles: Dictionary = data(content_db).get("chapter_profiles", {})
	return Dictionary(profiles.get(str(run_state.build.get("dwelling", "bedroom")), profiles.get("bedroom", {})))


static func capacity_at_tier(run_state: RunState, system_id: String, stat_key: String, level: int, content_db: Node = null) -> float:
	var value: float = tier_value(system_id, stat_key, level, content_db)
	var profile: Dictionary = chapter_profile(run_state, content_db)
	var entry_tier: int = int(derive_from_dwelling(str(run_state.build.get("dwelling", "bedroom")), content_db).get(system_id, 1))
	if stat_key == "base_token_rate":
		value = float(profile.get(stat_key, 1000000.0)) * value / maxf(1.0, tier_value(system_id, stat_key, entry_tier, content_db))
	elif stat_key == "cooling_capacity" or stat_key == "heat_capacity":
		# Chapter scale cannot mask a purchase: every tier adds 35% cooling and
		# 15% heat headroom relative to that chapter's starting tier.
		var step: float = 0.35 if stat_key == "cooling_capacity" else 0.15
		value = float(profile.get(stat_key, value)) * (1.0 + step * float(level - 1)) / (1.0 + step * float(entry_tier - 1))
	elif stat_key == "hardware_slots":
		value = maxf(float([2, 4, 8, 16][clampi(level - 1, 0, 3)]), chapter_floor(run_state, stat_key, content_db))
	elif stat_key == BACKPLANE_STAT:
		# Bays are the tier's number and nothing else. A legacy save that was
		# demonstrably running a wider pipeline keeps those stages as overflow
		# (BoardSystem._migrate_legacy_board_bonuses), so no floor — chapter or
		# `cabinet_legacy_floor` — is needed to preserve what the player had, and
		# applying one would put the safe figure out of step with the tier the
		# Market row says the run owns.
		return value
	else:
		value = maxf(value, chapter_floor(run_state, stat_key, content_db))
	return maxf(value, float(Dictionary(run_state.build.get("cabinet_legacy_floor", {})).get(stat_key, 0.0)))


## Convert old kit once, preserving actual capacity and its standing bill.
## Floors replace hardware contributions; they never stack with the new base.
static func absorb_legacy_rig(run_state: RunState) -> void:
	var hardware: Array = run_state.build.get("hardware", [])
	if hardware.is_empty():
		return
	var floor_stats: Dictionary = Dictionary(run_state.build.get("cabinet_legacy_floor", {})).duplicate(true)
	var rate: float = 0.0
	var draw: float = 0.0
	var lanes: int = 0
	var work: int = 0
	for key in hardware:
		var curve: Dictionary = ContentDatabase.balance.get("hardware_curves", {}).get(str(key), {})
		rate += float(curve.get("token_rate", 0.0))
		draw += float(curve.get("power_draw", 0.0))
		work = maxi(work, int(curve.get("work_tier", 0)))
		if UpgradeSystem.occupies_floor(ContentDatabase.balance.get("hardware_curves", {}), str(key)):
			lanes += 1
	var old_bonus: Array = [0.0, 2000000.0, 20000000.0, 200000000.0]
	floor_stats["base_token_rate"] = maxf(float(floor_stats.get("base_token_rate", 0.0)), rate + float(old_bonus[tier(run_state, "compute") - 1]))
	floor_stats["power_draw"] = maxf(float(floor_stats.get("power_draw", 0.0)), draw)
	floor_stats["job_slots"] = maxi(int(floor_stats.get("job_slots", 0)), lanes)
	floor_stats["work_tier"] = maxi(int(floor_stats.get("work_tier", 0)), work)
	floor_stats["cooling_capacity"] = maxf(float(floor_stats.get("cooling_capacity", 0.0)),
		maxf(chapter_floor(run_state, "cooling_capacity"), tier_value("cooling", "cooling_capacity", tier(run_state, "cooling"))) + UpgradeSystem.installed_cooling(run_state, ContentDatabase))
	floor_stats["heat_capacity"] = maxf(float(floor_stats.get("heat_capacity", 0.0)), float(run_state.compute.get("heat_capacity", 100.0)))
	run_state.build["cabinet_legacy_floor"] = floor_stats
	run_state.build["hardware"] = []
	run_state.build.erase("migration_debug")


static func power_draw(run_state: RunState) -> float:
	var draw: float = float(chapter_profile(run_state).get("power_draw", 65.0))
	return maxf(draw, float(Dictionary(run_state.build.get("cabinet_legacy_floor", {})).get("power_draw", 0.0)))


static func work_tier(run_state: RunState, content_db: Node = null) -> int:
	return maxi(int(chapter_profile(run_state, content_db).get("work_tier", 0)),
		int(Dictionary(run_state.build.get("cabinet_legacy_floor", {})).get("work_tier", 0)))


## Permanent unlock ids stay valid, but install capacity rather than machines.
## A chapter that already supplies the earned machine is not charged its draw twice.
static func grant_permanent_upgrade(state: RunState, upgrade: UpgradeDefinition) -> bool:
	if int(UpgradeSystem.upgrade_counts(state).get(upgrade.id, 0)) > 0:
		return false
	if not UpgradeSystem.prerequisites_met(state, upgrade, ContentDatabase):
		return false
	var grants: Array = Array(state.build.get("cabinet_permanent_grants", [])).duplicate()
	grants.append(upgrade.id)
	var rate: float = 1000000.0
	var draw: float = 65.0
	var cooling: float = 0.0
	var band: int = 0
	for id in grants:
		var item: UpgradeDefinition = ContentDatabase.get_upgrade(str(id))
		if item == null:
			continue
		var curve: Dictionary = ContentDatabase.balance.hardware_curves.get(item.hardware_key, {})
		rate += float(curve.get("token_rate", 0.0))
		draw += float(curve.get("power_draw", 0.0))
		cooling += UpgradeSystem.cooling_from(item)
		band = maxi(band, int(curve.get("work_tier", 0)))
	var floor_stats: Dictionary = Dictionary(state.build.get("cabinet_legacy_floor", {})).duplicate(true)
	var actual_draw: float = maxf(power_draw(state), draw)
	var actual_cooling: float = maxf(capacity(state, "cooling", "cooling_capacity"), float(chapter_profile(state).get("cooling_capacity", 0.0)) + cooling)
	if actual_cooling + float(state.compute.get("meta_cooling", 0.0)) < HeatSystem.cooling_needed_for(actual_draw, maxi(work_tier(state), band)):
		return false
	floor_stats["base_token_rate"] = maxf(float(floor_stats.get("base_token_rate", 0.0)), rate)
	floor_stats["power_draw"] = maxf(float(floor_stats.get("power_draw", 0.0)), draw)
	floor_stats["work_tier"] = maxi(int(floor_stats.get("work_tier", 0)), band)
	floor_stats["cooling_capacity"] = actual_cooling
	state.build["cabinet_legacy_floor"] = floor_stats
	state.build["cabinet_permanent_grants"] = grants
	UpgradeSystem.record_free_grant(state, upgrade.id, ContentDatabase)
	return true


## The chapter table's value for this stat, or 0 for a stat the chapter table
## does not carry (`bays`, `workflows`, `base_token_rate`).
static func chapter_floor(run_state: RunState, stat_key: String, content_db: Node = null) -> float:
	var db: Node = content_db if content_db != null else ContentDatabase
	var dwelling: String = str(run_state.build.get("dwelling", ""))
	if dwelling == "":
		return 0.0
	if stat_key in CHAPTER_STATS:
		var row: Dictionary = Dictionary(Dictionary(db.balance.get("dwelling_costs", {})).get(dwelling, {}))
		return float(row.get(stat_key, 0.0))
	return 0.0


## Every tiered capacity at once, for before/after deltas.
static func stat_snapshot(run_state: RunState, content_db: Node = null) -> Dictionary:
	var snapshot: Dictionary = {}
	for system_id in system_ids(content_db):
		for stat_key in stat_keys(str(system_id), content_db):
			snapshot[str(stat_key)] = capacity(run_state, str(system_id), str(stat_key), content_db)
	return snapshot


# --- Dwellings and chapters --------------------------------------------------

## The tiers a chapter's room is worth, from the pack's migration table. An
## unknown or missing dwelling is the bottom of everything.
static func derive_from_dwelling(dwelling_key: String, content_db: Node = null) -> Dictionary:
	var result: Dictionary = default_tiers(content_db)
	var table: Variant = data(content_db).get("migration_from_dwelling", {})
	if not table is Dictionary:
		return result
	var row: Variant = Dictionary(table).get(dwelling_key, null)
	if not row is Array:
		return result
	var order: Array = system_ids(content_db)
	var values: Array = row
	var lo: int = min_tier(content_db)
	var hi: int = max_tier(content_db)
	for i in range(mini(order.size(), values.size())):
		result[str(order[i])] = clampi(int(values[i]), lo, hi)
	return result


## Settles a run into a chapter: every system is at least what the room is
## worth. Never lowers a tier, so a system bought in the bedroom survives the
## move to the garage, and a fresh garage run still opens with garage numbers.
static func raise_to_dwelling(run_state: RunState, dwelling_key: String, content_db: Node = null) -> Dictionary:
	var current: Dictionary = tiers(run_state, content_db)
	var floor_tiers: Dictionary = derive_from_dwelling(dwelling_key, content_db)
	for system_id in current.keys():
		current[system_id] = maxi(int(current[system_id]), int(floor_tiers.get(system_id, min_tier(content_db))))
	run_state.build["cabinet_systems"] = current
	return current


## The highest tier the run's chapter allows. Chapters are the meta gate on
## systems: the cabinet grows inside a room, and the next room lifts the cap.
static func max_tier_for_chapter(run_state: RunState, content_db: Node = null) -> int:
	return max_tier_for_dwelling(str(run_state.build.get("dwelling", "")), content_db)


static func max_tier_for_dwelling(dwelling_key: String, content_db: Node = null) -> int:
	var table: Variant = data(content_db).get("chapter_max_tier", {})
	var hi: int = max_tier(content_db)
	if not table is Dictionary or Dictionary(table).is_empty():
		return hi
	var caps: Dictionary = table
	if caps.has(dwelling_key):
		return clampi(int(caps[dwelling_key]), min_tier(content_db), hi)
	# A room the table does not know is treated as the most modest one rather
	# than the most generous, so a stray key cannot open the top tier early.
	var lowest: int = hi
	for value in caps.values():
		lowest = mini(lowest, int(value))
	return clampi(lowest, min_tier(content_db), hi)


# --- Purchasing --------------------------------------------------------------

## What the next tier costs, or -1 when the system is already at the top.
static func next_tier_cost(run_state: RunState, system_id: String, content_db: Node = null) -> float:
	var current: int = tier(run_state, system_id, content_db)
	if current >= max_tier(content_db):
		return -1.0
	var cost: float = cost_of_tier(system_id, current + 1, content_db) * float(chapter_profile(run_state, content_db).get("cost_scale", 1.0))
	return cost * (1.0 - clampf(float(run_state.build.get("system_discount", 0.0)), 0.0, 0.9))


## The price of reaching `target_tier` from the one below it. The cost array is
## authored for tiers 2..max, so tier 2 is `cost[0]`.
static func cost_of_tier(system_id: String, target_tier: int, content_db: Node = null) -> float:
	var costs: Array = Array(definition(system_id, content_db).get("cost", []))
	var index: int = target_tier - min_tier(content_db) - 1
	if index < 0 or index >= costs.size():
		return -1.0
	return float(costs[index])


## Whether the next tier can be bought right now, and if not, why, in the
## words the Market prints: "MAXED OUT", "NEXT CHAPTER UNLOCKS TIER 3",
## "NEED $240 MORE".
static func can_upgrade(run_state: RunState, system_id: String, content_db: Node = null) -> Dictionary:
	if definition(system_id, content_db).is_empty():
		return {"ok": false, "reason": REASON_UNKNOWN, "cost": -1.0, "next_tier": 0}
	var current: int = tier(run_state, system_id, content_db)
	var next_tier: int = current + 1
	if current >= max_tier(content_db):
		return {"ok": false, "reason": REASON_MAXED, "cost": -1.0, "next_tier": current}
	var cost: float = next_tier_cost(run_state, system_id, content_db)
	if next_tier > max_tier_for_chapter(run_state, content_db):
		return {
			"ok": false,
			"reason": "NEXT CHAPTER UNLOCKS TIER %d" % next_tier,
			"cost": cost,
			"next_tier": next_tier,
		}
	var cash: float = float(run_state.economy.get("cash", 0.0))
	if cash < cost:
		return {
			"ok": false,
			"reason": "NEED %s MORE" % NumberFormat.format_cash(ceilf(cost - cash)),
			"cost": cost,
			"next_tier": next_tier,
		}
	return {"ok": true, "reason": "", "cost": cost, "next_tier": next_tier}


## "7 → 10 BAYS", "97 → 336 COOLING · 140 → 200 HEAT CAP": what moving between
## two tiers does to the numbers, for a Market row or an install reveal.
static func effect_text(run_state: RunState, system_id: String, from_tier: int, to_tier: int, content_db: Node = null) -> String:
	var parts: Array[String] = []
	for stat_key in stat_keys(system_id, content_db):
		var key: String = str(stat_key)
		var before: float = capacity_at_tier(run_state, system_id, key, from_tier, content_db)
		var after: float = capacity_at_tier(run_state, system_id, key, to_tier, content_db)
		parts.append("%s → %s %s" % [
			_format_stat(key, before), _format_stat(key, after), stat_label(key, content_db),
		])
	return " · ".join(parts)


static func _format_stat(stat_key: String, value: float) -> String:
	if stat_key == "base_token_rate":
		return NumberFormat.format(value)
	return str(int(round(value)))


## Everything a Market row needs about one system: where it is, what is next,
## what that costs and does, and whether the button is live.
static func next_tier_info(run_state: RunState, system_id: String, content_db: Node = null) -> Dictionary:
	var current: int = tier(run_state, system_id, content_db)
	var verdict: Dictionary = can_upgrade(run_state, system_id, content_db)
	var maxed: bool = current >= max_tier(content_db)
	var next_tier: int = current if maxed else current + 1
	return {
		"id": system_id,
		"name": system_name(system_id, content_db),
		"tier": current,
		"tier_name": tier_name(system_id, current, content_db),
		"max_tier": max_tier(content_db),
		"chapter_max_tier": max_tier_for_chapter(run_state, content_db),
		"maxed": maxed,
		"next_tier": next_tier,
		"next_tier_name": "" if maxed else tier_name(system_id, next_tier, content_db),
		"cost": float(verdict.get("cost", -1.0)),
		"effect": "" if maxed else effect_text(run_state, system_id, current, next_tier, content_db),
		"can_upgrade": bool(verdict.get("ok", false)),
		"reason": str(verdict.get("reason", "")),
	}
