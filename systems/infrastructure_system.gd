class_name InfrastructureSystem
extends RefCounted

## The machine's scale, bought in the Market as a tier from 0 to 6 and stored
## on the run as `build.infrastructure_tier`. Each tier carries the cabinet
## scale profile (base rate, draw, work tier, cooling, heat capacity, cost
## scale), the cabinet tier cap, the cabinet tiers the scale opens with, the
## capacity floors, the facility cost the rent is set from, and the overflow
## allowance. Progression is the investor's business (`InvestorProgression`);
## scale is bought here whenever the run can afford it.
##
## The room is derived presentation: `room_id()` is the art and the investor
## line for the tier, and nothing in gameplay reads a room key for a number.
## Everything here is static and reads content through `ContentDatabase`
## unless a database is passed in, the same way `CabinetSystems` does.

const MIN_TIER := 0
const STATE_KEY := "infrastructure_tier"

const REASON_MAXED := "MAXED OUT"
const REASON_MISSING := "NO INFRASTRUCTURE DATA"

## The stats a tier's `floors` block carries; `CabinetSystems.capacity` reads
## them as a permanent floor beneath the cabinet tier.
const FLOOR_STATS := ["hardware_slots", "cooling_capacity", "heat_capacity"]


# --- Content -----------------------------------------------------------------

static func data(content_db: Node = null) -> Dictionary:
	var db: Node = content_db if content_db != null else ContentDatabase
	var stored: Variant = db.get("infrastructure")
	return stored if stored is Dictionary else {}


## Every tier in ascending order. Empty when the content is missing.
static func entries(content_db: Node = null) -> Array:
	var stored: Variant = data(content_db).get("tiers", [])
	return Array(stored) if stored is Array else []


static func max_tier(content_db: Node = null) -> int:
	return maxi(MIN_TIER, entries(content_db).size() - 1)


## The authored entry for a tier, clamped into range. Empty when there is no
## content at all, so callers fall back to their defaults rather than crash.
static func entry(tier: int, content_db: Node = null) -> Dictionary:
	var all: Array = entries(content_db)
	if all.is_empty():
		return {}
	var found: Variant = all[clampi(tier, MIN_TIER, all.size() - 1)]
	return Dictionary(found) if found is Dictionary else {}


## The tier whose presentation room is `room_id`, or MIN_TIER when no tier
## claims it. Tests and the v23 save migration use it to speak in room names.
static func tier_for_room(room_id: String, content_db: Node = null) -> int:
	var all: Array = entries(content_db)
	for index in range(all.size()):
		var candidate: Variant = all[index]
		if candidate is Dictionary and str(Dictionary(candidate).get("room", "")) == room_id:
			return index
	return MIN_TIER


## The lowest tier whose cabinet cap admits `cabinet_tier`, or the top tier if
## none does. Used to word the Market's "NEEDS INFRASTRUCTURE TIER n" reason.
static func tier_required_for_cabinet(cabinet_tier: int, content_db: Node = null) -> int:
	var all: Array = entries(content_db)
	for index in range(all.size()):
		var candidate: Variant = all[index]
		if candidate is Dictionary and int(Dictionary(candidate).get("cabinet_max_tier", 0)) >= cabinet_tier:
			return index
	return max_tier(content_db)


static func tier_name(tier: int, content_db: Node = null) -> String:
	return str(entry(tier, content_db).get("name", "Tier %d" % tier))


# --- Run state ---------------------------------------------------------------

## The run's tier, clamped into the authored range. Missing reads as tier 0.
static func tier(run_state: RunState, content_db: Node = null) -> int:
	return clampi(int(run_state.build.get(STATE_KEY, MIN_TIER)), MIN_TIER, max_tier(content_db))


## Writes the tier. Nothing else changes here: rent, cabinet tiers and compute
## are the purchase flow's business, and the room is read off the tier
## (`room_id`) rather than stored.
static func set_tier(run_state: RunState, new_tier: int, content_db: Node = null) -> int:
	var clamped: int = clampi(new_tier, MIN_TIER, max_tier(content_db))
	run_state.build[STATE_KEY] = clamped
	return clamped


## Clamps the stored tier into the authored range, writing tier 0 for a run
## that has none. Called on load and reset. (A pre-v26 save that only knew its
## room has its tier derived in `RunState.from_dict` before this runs.)
static func ensure_state(run_state: RunState, content_db: Node = null) -> int:
	return set_tier(run_state, int(run_state.build.get(STATE_KEY, MIN_TIER)), content_db)


static func current(run_state: RunState, content_db: Node = null) -> Dictionary:
	return entry(tier(run_state, content_db), content_db)


## The cabinet scale profile: base_token_rate, power_draw, work_tier,
## cooling_capacity, heat_capacity, cost_scale.
static func profile(run_state: RunState, content_db: Node = null) -> Dictionary:
	return profile_at(tier(run_state, content_db), content_db)


static func profile_at(at_tier: int, content_db: Node = null) -> Dictionary:
	var stored: Variant = entry(at_tier, content_db).get("profile", {})
	return Dictionary(stored) if stored is Dictionary else {}


## The capacity floors: hardware_slots, cooling_capacity, heat_capacity.
static func floors(run_state: RunState, content_db: Node = null) -> Dictionary:
	var stored: Variant = current(run_state, content_db).get("floors", {})
	return Dictionary(stored) if stored is Dictionary else {}


## One floor stat, or 0 for a stat the tier table does not carry.
static func floor_value(run_state: RunState, stat_key: String, content_db: Node = null) -> float:
	if not stat_key in FLOOR_STATS:
		return 0.0
	return float(floors(run_state, content_db).get(stat_key, 0.0))


## The highest cabinet tier this infrastructure admits.
static func cabinet_max_tier(run_state: RunState, content_db: Node = null) -> int:
	return cabinet_max_tier_at(tier(run_state, content_db), content_db)


static func cabinet_max_tier_at(at_tier: int, content_db: Node = null) -> int:
	var found: Dictionary = entry(at_tier, content_db)
	if found.is_empty():
		return CabinetSystems.max_tier(content_db)
	return clampi(
		int(found.get("cabinet_max_tier", CabinetSystems.max_tier(content_db))),
		CabinetSystems.min_tier(content_db),
		CabinetSystems.max_tier(content_db)
	)


## The cabinet tiers this infrastructure opens with, by system id. The scale
## profile's numbers are stated at these tiers, so `CabinetSystems.capacity`
## scales a bought tier relative to them.
static func cabinet_entry_tiers(run_state: RunState, content_db: Node = null) -> Dictionary:
	return cabinet_entry_tiers_at(tier(run_state, content_db), content_db)


static func cabinet_entry_tiers_at(at_tier: int, content_db: Node = null) -> Dictionary:
	var result: Dictionary = CabinetSystems.default_tiers(content_db)
	var row: Variant = entry(at_tier, content_db).get("cabinet_entry_tiers", null)
	if not row is Array:
		return result
	var order: Array = _entry_tier_order(content_db)
	var values: Array = row
	var lo: int = CabinetSystems.min_tier(content_db)
	var hi: int = CabinetSystems.max_tier(content_db)
	for i in range(mini(order.size(), values.size())):
		result[str(order[i])] = clampi(int(values[i]), lo, hi)
	return result


static func cabinet_entry_tier(run_state: RunState, system_id: String, content_db: Node = null) -> int:
	return int(cabinet_entry_tiers(run_state, content_db).get(system_id, CabinetSystems.min_tier(content_db)))


## The system order `cabinet_entry_tiers` rows are written in.
static func _entry_tier_order(content_db: Node = null) -> Array:
	var order: Variant = data(content_db).get("cabinet_entry_tier_order", null)
	if order is Array and not Array(order).is_empty():
		var ids: Array = []
		for system_id in Array(order):
			ids.append(str(system_id))
		return ids
	return CabinetSystems.system_ids(content_db)


## Overflow stages the scale itself grants before perks, unlocks and monitors.
static func overflow_allowance(run_state: RunState, content_db: Node = null) -> int:
	return maxi(0, int(current(run_state, content_db).get("overflow_allowance", 0)))


## What the facility costs a round before the run's rent multiplier.
static func facility_cost(run_state: RunState, content_db: Node = null) -> float:
	return facility_cost_at(tier(run_state, content_db), content_db)


static func facility_cost_at(at_tier: int, content_db: Node = null) -> float:
	var db: Node = content_db if content_db != null else ContentDatabase
	var fallback: float = float(Dictionary(db.balance.get("economy", {})).get("starting_rent", 400.0))
	return float(entry(at_tier, content_db).get("facility_cost", fallback))


## Sets `economy.round_rent` from the tier's facility cost and the run's rent
## multiplier. Called at run start and after every purchase.
static func apply_rent(run_state: RunState, content_db: Node = null) -> float:
	var rent: float = facility_cost(run_state, content_db) * float(run_state.economy.get("rent_multiplier", 1.0))
	run_state.economy["round_rent"] = rent
	return rent


## The presentation room for the run's tier ("bedroom" … "moon_facility").
static func room_id(run_state: RunState, content_db: Node = null) -> String:
	return room_id_at(tier(run_state, content_db), content_db)


static func room_id_at(at_tier: int, content_db: Node = null) -> String:
	return str(entry(at_tier, content_db).get("room", "bedroom"))


## The narrative key for the investor's line when this tier is bought.
static func investor_line(run_state: RunState, content_db: Node = null) -> String:
	return str(current(run_state, content_db).get("investor_line", ""))


# --- Purchasing --------------------------------------------------------------

static func cost_of_tier(target_tier: int, content_db: Node = null) -> float:
	var found: Dictionary = entry(target_tier, content_db)
	if found.is_empty() or target_tier < MIN_TIER or target_tier > max_tier(content_db):
		return -1.0
	return maxf(0.0, float(found.get("cost", 0.0)))


## What the next tier costs, or -1 at the top.
static func next_tier_cost(run_state: RunState, content_db: Node = null) -> float:
	var current_tier: int = tier(run_state, content_db)
	if current_tier >= max_tier(content_db):
		return -1.0
	return cost_of_tier(current_tier + 1, content_db)


## Whether the next tier can be bought right now, and if not, why, in the
## words the Market prints: "MAXED OUT", "NEED $240 MORE".
static func can_upgrade(run_state: RunState, content_db: Node = null) -> Dictionary:
	if entries(content_db).is_empty():
		return {"ok": false, "reason": REASON_MISSING, "cost": -1.0, "next_tier": MIN_TIER}
	var current_tier: int = tier(run_state, content_db)
	if current_tier >= max_tier(content_db):
		return {"ok": false, "reason": REASON_MAXED, "cost": -1.0, "next_tier": current_tier}
	var next_tier: int = current_tier + 1
	var cost: float = cost_of_tier(next_tier, content_db)
	var cash: float = float(run_state.economy.get("cash", 0.0))
	if cash < cost:
		return {
			"ok": false,
			"reason": "NEED %s MORE" % NumberFormat.format_cash(ceilf(cost - cash)),
			"cost": cost,
			"next_tier": next_tier,
		}
	return {"ok": true, "reason": "", "cost": cost, "next_tier": next_tier}


## "1.0M → 7.0M BASE RATE · 17 → 110 COOLING · 100 → 140 HEAT CAP · CABINET
## CAP 2 → 3 · RENT $400 → $1,400": what moving between two tiers does.
static func effect_text(from_tier: int, to_tier: int, content_db: Node = null) -> String:
	var before: Dictionary = profile_at(from_tier, content_db)
	var after: Dictionary = profile_at(to_tier, content_db)
	var parts: Array[String] = []
	parts.append("%s → %s %s" % [
		NumberFormat.format(float(before.get("base_token_rate", 0.0))),
		NumberFormat.format(float(after.get("base_token_rate", 0.0))),
		CabinetSystems.stat_label("base_token_rate", content_db),
	])
	for key in ["cooling_capacity", "heat_capacity"]:
		parts.append("%d → %d %s" % [
			int(round(float(before.get(key, 0.0)))),
			int(round(float(after.get(key, 0.0)))),
			CabinetSystems.stat_label(key, content_db),
		])
	var cap_before: int = cabinet_max_tier_at(from_tier, content_db)
	var cap_after: int = cabinet_max_tier_at(to_tier, content_db)
	if cap_before != cap_after:
		parts.append("CABINET CAP %d → %d" % [cap_before, cap_after])
	parts.append("RENT %s → %s" % [
		NumberFormat.format_cash(facility_cost_at(from_tier, content_db)),
		NumberFormat.format_cash(facility_cost_at(to_tier, content_db)),
	])
	return " · ".join(parts)


## Everything a Market row needs: the same shape `CabinetSystems.next_tier_info`
## returns, so the INFRASTRUCTURE row is drawn by the same code as a system.
static func next_tier_info(run_state: RunState, content_db: Node = null) -> Dictionary:
	var current_tier: int = tier(run_state, content_db)
	var verdict: Dictionary = can_upgrade(run_state, content_db)
	var maxed: bool = current_tier >= max_tier(content_db)
	var next_tier: int = current_tier if maxed else current_tier + 1
	return {
		"id": "infrastructure",
		"name": "Infrastructure",
		"tier": current_tier,
		"tier_name": tier_name(current_tier, content_db),
		"max_tier": max_tier(content_db),
		"maxed": maxed,
		"next_tier": next_tier,
		"next_tier_name": "" if maxed else tier_name(next_tier, content_db),
		"cost": float(verdict.get("cost", -1.0)),
		"effect": "" if maxed else effect_text(current_tier, next_tier, content_db),
		"can_upgrade": bool(verdict.get("ok", false)),
		"reason": str(verdict.get("reason", "")),
		"room": room_id(run_state, content_db),
		"next_room": room_id_at(next_tier, content_db),
	}
