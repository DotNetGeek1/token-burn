class_name CalibrationSystem
extends RefCounted

## Module calibration: the late-game sink that turns spare modules and cash
## into a bounded upgrade on one owned module. Each rank runs the module's
## stage a little cooler (`stage.heat`), a little cheaper (`stage.cost`, the
## per-stage power bill) and a little stronger (`stage.token_mult`), capped at
## `max_rank`. Tuning lives in `economy.json` under `calibration`.
##
## Storage. Owned modules are plain id strings in `build["modules"]` (one copy
## of each id, see `BoardSystem.grant_module`), so ranks live beside them in
## `build["module_calibration"]: { module_id: rank }`. No save migration is
## needed: `RunState.from_dict` merges the whole `build` section, and a save
## without the key simply has no calibrated modules.
##
## Application. The board reads a module's numbers inside
## `BoardSystem._dispatch_stage`, where the module's own slot effects are
## dispatched together with the run's perk/status subscriptions. Rather than
## hooking that read site, calibration projects each rank into one permanent
## status effect (`status.calibration.<module_id>`, no `rounds` so it never
## expires) whose subscription is gated on `$module_id`. The simulation's
## existing `_collect_subscriptions` picks it up like any other status effect,
## so the multipliers reach the burn, the preview and the resolver trace
## (source_id `calibration.<module_id>`) without a second code path.
## `multiplier()` is the same arithmetic for anything that wants to *display*
## the effect (UI, tests) without running a burn.

const BUILD_KEY := "module_calibration"
const STATUS_PREFIX := "status.calibration."
const STAGE_EVENT := "board.stage_resolved"
## Above every module's own priority (≤ 99) so the discounts land after the
## module has added its heat and cost in the additive phase.
const PRIORITY := 900

const STAT_HEAT := "heat"
const STAT_POWER := "power"
const STAT_EFFECT := "effect"

const REASON_NOT_OWNED := "NOT OWNED"
const REASON_MAX_RANK := "FULLY CALIBRATED"
const REASON_NEED_MODULES := "PICK %d MODULES TO CONSUME"
const REASON_CONSUME_TARGET := "CANNOT CONSUME THE TARGET"
const REASON_CONSUME_NOT_OWNED := "%s IS NOT OWNED"
const REASON_CONSUME_SEATED := "UNSEAT %s FIRST"
const REASON_DUPLICATE := "PICK DIFFERENT MODULES"


static func tuning() -> Dictionary:
	return Dictionary(ContentDatabase.balance.get("economy", {}).get("calibration", {}))


static func max_rank() -> int:
	return maxi(1, int(tuning().get("max_rank", 3)))


static func modules_consumed() -> int:
	return maxi(1, int(tuning().get("modules_consumed", 2)))


static func cost_ratio() -> float:
	return maxf(0.0, float(tuning().get("cost_major_purchase_ratio", 0.25)))


## The per-rank multiplier for one stat: `heat`, `power` or `effect`.
static func per_rank(stat: String) -> float:
	var ranks: Dictionary = Dictionary(tuning().get("per_rank", {}))
	match stat:
		STAT_HEAT:
			return maxf(0.0, float(ranks.get("heat_mult", 0.92)))
		STAT_POWER:
			return maxf(0.0, float(ranks.get("power_mult", 0.94)))
		STAT_EFFECT:
			return maxf(0.0, float(ranks.get("effect_mult", 1.06)))
	return 1.0


static func ranks(run_state: RunState) -> Dictionary:
	var stored: Variant = run_state.build.get(BUILD_KEY, {})
	if not stored is Dictionary:
		stored = {}
		run_state.build[BUILD_KEY] = stored
	return stored


static func rank(run_state: RunState, module_id: String) -> int:
	return clampi(int(ranks(run_state).get(module_id, 0)), 0, max_rank())


## The multiplier a calibrated module applies to one of its stats: the per-rank
## figure compounded `rank` times. 1.0 for an uncalibrated module.
static func multiplier(run_state: RunState, module_id: String, stat: String) -> float:
	var current: int = rank(run_state, module_id)
	if current <= 0:
		return 1.0
	return pow(per_rank(stat), float(current))


## What the next rank costs: a share of the chapter's `major_purchase`, growing
## linearly with the rank being bought. Zero once the cap is reached.
static func cost(run_state: RunState, major_purchase: float, module_id: String) -> float:
	var current: int = rank(run_state, module_id)
	if current >= max_rank():
		return 0.0
	return snappedf(maxf(0.0, major_purchase) * cost_ratio() * float(current + 1), 1.0)


static func owned(run_state: RunState, module_id: String) -> bool:
	return module_id in Array(run_state.build.get("modules", []))


## Whether the module sits in any workflow's slots. Consumed modules must be
## benched first, so the player never loses a stage out of a live pipeline
## without seeing it happen.
static func is_seated(run_state: RunState, module_id: String) -> bool:
	if module_id == "":
		return false
	for workflow in Array(run_state.build.get("workflows", [])):
		if not workflow is Dictionary:
			continue
		for entry in Array(Dictionary(workflow).get("slots", [])):
			if str(entry) == module_id:
				return true
	var legacy: Variant = Dictionary(run_state.build.get("board", {})).get("slots", null)
	if legacy is Array:
		for entry in legacy:
			if str(entry) == module_id:
				return true
	return false


## Owned, unseated modules other than the target: everything the player could
## feed into a calibration right now.
static func consumable_modules(run_state: RunState, target: String) -> Array:
	var out: Array = []
	for module_id in Array(run_state.build.get("modules", [])):
		var text_id: String = str(module_id)
		if text_id == "" or text_id == target:
			continue
		if is_seated(run_state, text_id):
			continue
		out.append(text_id)
	return out


## "" when the calibration can go ahead, otherwise the blocker the button
## prints. `cash` and `major_purchase` are passed in so this stays a pure
## function of state the caller already has.
static func block_reason(
	run_state: RunState, target: String, consumed: Array, cash: float, major_purchase: float
) -> String:
	if target == "" or not owned(run_state, target):
		return REASON_NOT_OWNED
	if rank(run_state, target) >= max_rank():
		return REASON_MAX_RANK
	var needed: int = modules_consumed()
	if consumed.size() != needed:
		return REASON_NEED_MODULES % needed
	var seen: Dictionary = {}
	for raw in consumed:
		var module_id: String = str(raw)
		if module_id == target:
			return REASON_CONSUME_TARGET
		if seen.has(module_id):
			return REASON_DUPLICATE
		seen[module_id] = true
		if not owned(run_state, module_id):
			return REASON_CONSUME_NOT_OWNED % _module_name(module_id)
		if is_seated(run_state, module_id):
			return REASON_CONSUME_SEATED % _module_name(module_id)
	var price: float = cost(run_state, major_purchase, target)
	if cash < price:
		return "NEED %s MORE" % NumberFormat.format_cash(maxf(1.0, ceilf(price - cash)))
	return ""


static func can_calibrate(
	run_state: RunState, target: String, consumed: Array, cash: float, major_purchase: float
) -> bool:
	return block_reason(run_state, target, consumed, cash, major_purchase) == ""


## Charges the cost, removes the consumed modules from the inventory (and any
## calibration they carried), raises the target's rank by one and rewrites the
## status-effect projection. Returns false, changing nothing, when blocked.
static func calibrate(
	run_state: RunState,
	target: String,
	consumed: Array,
	economy: EconomySystem,
	major_purchase: float
) -> bool:
	var cash: float = float(run_state.economy.get("cash", 0.0))
	if not can_calibrate(run_state, target, consumed, cash, major_purchase):
		return false
	var price: float = cost(run_state, major_purchase, target)
	if not economy.purchase(run_state, price, "calibration:%s" % target):
		return false
	var owned_ids: Array = Array(run_state.build.get("modules", []))
	var rank_table: Dictionary = ranks(run_state)
	for raw in consumed:
		var module_id: String = str(raw)
		owned_ids.erase(module_id)
		rank_table.erase(module_id)
	run_state.build["modules"] = owned_ids
	rank_table[target] = mini(max_rank(), int(rank_table.get(target, 0)) + 1)
	run_state.build[BUILD_KEY] = rank_table
	run_state.statistics["modules_calibrated"] = int(
		run_state.statistics.get("modules_calibrated", 0)
	) + 1
	sync_status_effects(run_state)
	return true


## The subscription one calibrated module contributes on `board.stage_resolved`,
## gated to its own stage. `discount` leaves credits alone, so a cooling
## module's negative heat is not shrunk by its own calibration.
static func subscription(run_state: RunState, module_id: String) -> Dictionary:
	var heat_off: float = clampf(1.0 - multiplier(run_state, module_id, STAT_HEAT), 0.0, 1.0)
	var power_off: float = clampf(1.0 - multiplier(run_state, module_id, STAT_POWER), 0.0, 1.0)
	var effect: float = multiplier(run_state, module_id, STAT_EFFECT)
	return {
		"event": STAGE_EVENT,
		"priority": PRIORITY,
		"source_id": "calibration.%s" % module_id,
		"conditions": [{"left": "$module_id", "operator": "in", "right": [module_id]}],
		"effects": [
			{"operation": "discount", "target": "stage.heat", "value": heat_off},
			{"operation": "discount", "target": "stage.cost", "value": power_off},
			{"operation": "multiply", "target": "stage.token_mult", "value": effect},
		],
	}


## Every calibration subscription the run currently carries.
static func subscriptions(run_state: RunState) -> Array:
	var out: Array = []
	for module_id in ranks(run_state).keys():
		if rank(run_state, str(module_id)) > 0 and owned(run_state, str(module_id)):
			out.append(subscription(run_state, str(module_id)))
	return out


## Rewrites the `status.calibration.*` entries in `build.status_effects` from
## the rank table. Idempotent: stale entries for modules no longer owned or
## calibrated are dropped, everything else in the list is left untouched.
static func sync_status_effects(run_state: RunState) -> void:
	var statuses: Array = []
	var existing: Variant = run_state.build.get("status_effects", [])
	if existing is Array:
		for status in existing:
			if status is Dictionary and str(Dictionary(status).get("id", "")).begins_with(STATUS_PREFIX):
				continue
			statuses.append(status)
	for module_id in ranks(run_state).keys():
		var text_id: String = str(module_id)
		var current: int = rank(run_state, text_id)
		if current <= 0 or not owned(run_state, text_id):
			continue
		statuses.append({
			"id": STATUS_PREFIX + text_id,
			"name": "%s calibrated" % _module_name(text_id),
			"calibration_rank": current,
			"module_id": text_id,
			"subscriptions": [subscription(run_state, text_id)],
		})
	run_state.build["status_effects"] = statuses


static func _module_name(module_id: String) -> String:
	var module: ModuleDefinition = ContentDatabase.get_module(module_id)
	return module.name.to_upper() if module != null else module_id.to_upper()
