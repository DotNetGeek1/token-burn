extends Node

## Cross-run progression. Everything else in the game is scoped to a single run
## and thrown away; this is the one file that remembers.
##
## A victory banks one pick. Spending that pick buys a permanent unlock from
## content/meta/unlocks.json, which is applied to every run from then on.

const DEFAULT_PROFILE_PATH := "user://profile.json"
const CATALOG_PATH := "res://content/meta/unlocks.json"
const PROFILE_VERSION := 3

## Where a run that has unlocked nothing takes place. The campaign always has at
## least this rung, so no profile can ever end up with nowhere to play.
const DEFAULT_LOCATION := "bedroom"

## Used only if the balance data cannot be read. The order matters: it is what
## "the next location" means when one is cleared.
const FALLBACK_LOCATION_ORDER := [
	"bedroom",
	"garage",
	"office_unit",
	"warehouse",
	"datacentre_campus",
	"private_power_grid",
	"moon_facility",
]

## Cumulative counters that outlive a run, so an achievement can ask for ten
## losses or a lifetime of tokens rather than only what one run managed.
const LIFETIME_KEYS := [
	"runs",
	"losses",
	"tokens_burned",
	"completed_jobs",
	"failed_jobs",
	"hidden_bugs_shipped",
	"modules_drafted",
]

signal profile_changed
signal pick_banked(total_pending: int)

## Switched off by the test suites and the batch runner, so a developer's own
## victories cannot quietly change what the tests measure.
var enabled: bool = true
## Redirected by tests onto a scratch file, so running the suite never writes to
## the profile the developer is actually playing.
var profile_path: String = DEFAULT_PROFILE_PATH

var _profile: Dictionary = {}
var _catalog: Array = []
var _catalog_by_id: Dictionary = {}
var _loaded: bool = false


func _ready() -> void:
	enabled = FeatureFlags.is_enabled("meta_progression_enabled")
	_ensure_loaded()


func victories() -> int:
	_ensure_loaded()
	return int(_profile.get("victories", 0))


func pending_picks() -> int:
	_ensure_loaded()
	return int(_profile.get("pending_picks", 0))


func unlock_count(unlock_id: String) -> int:
	_ensure_loaded()
	return int(Dictionary(_profile.get("unlocks", {})).get(unlock_id, 0))


func catalog() -> Array:
	_ensure_loaded()
	return _catalog.duplicate(true)


func get_unlock(unlock_id: String) -> Dictionary:
	_ensure_loaded()
	return Dictionary(_catalog_by_id.get(unlock_id, {})).duplicate(true)


## Whether this unlock can still be bought: one-offs only once, and extra slots
## only until the board hits the width the resolver can lay out.
func is_available(unlock_id: String) -> bool:
	var unlock: Dictionary = get_unlock(unlock_id)
	if unlock.is_empty():
		return false
	var owned: int = unlock_count(unlock_id)
	if not bool(unlock.get("repeatable", false)):
		return owned == 0
	if str(unlock.get("kind", "")) == "extra_slot":
		return BoardSystem.DEFAULT_SLOT_COUNT + owned < BoardSystem.MAX_SLOT_COUNT
	if str(unlock.get("kind", "")) == "workflow_slot":
		return BoardSystem.DEFAULT_WORKFLOW_CAPACITY + owned < BoardSystem.MAX_WORKFLOW_COUNT
	return true


## Three unlocks to choose between, drawn deterministically from the run's seed
## so a debrief cannot be rerolled by leaving and coming back. Reward-only
## unlocks (granted automatically by a specific Ascension ending) never show
## up here — the debrief is for picks, not for prizes already handed out.
func draw_choices(rng: DeterministicRng, count: int = 3) -> Array:
	_ensure_loaded()
	var pool: Array = []
	for unlock in _catalog:
		if bool(unlock.get("reward_only", false)):
			continue
		if is_available(str(unlock.get("id", ""))):
			pool.append(unlock.duplicate(true))
	if pool.size() <= count:
		return pool
	var picked: Array = []
	while picked.size() < count and not pool.is_empty():
		var index: int = rng.next_int_range(0, pool.size() - 1)
		picked.append(pool[index])
		pool.remove_at(index)
	return picked


## Banks `picks` unlock picks for completing an Ascension Contract. Higher-tier
## contracts bank more picks, which is the entire reward for reaching for one
## instead of just outlasting the year.
func bank_victory(picks: int = 1) -> void:
	if not enabled:
		return
	_ensure_loaded()
	_profile["victories"] = victories() + 1
	_profile["pending_picks"] = pending_picks() + maxi(0, picks)
	_save()
	pick_banked.emit(pending_picks())


## Surviving the year without ascending. Recorded so the profile can tell the
## two endings apart, but it banks nothing to spend.
func record_retirement() -> void:
	if not enabled:
		return
	_ensure_loaded()
	_profile["retirements"] = int(_profile.get("retirements", 0)) + 1
	_save()


func retirements() -> int:
	_ensure_loaded()
	return int(_profile.get("retirements", 0))


## The Compute Age a fresh run starts in. Advances one step the first time a
## Tier 3 Ascension Contract that unlocks the next age is completed.
func age() -> int:
	_ensure_loaded()
	return int(_profile.get("age", 0))


func advance_age(max_age: int) -> void:
	if not enabled:
		return
	_ensure_loaded()
	_profile["age"] = mini(int(_profile.get("age", 0)) + 1, maxi(0, max_age))
	_save()
	profile_changed.emit()


## Grants an unlock outright rather than through the pick economy: this is how
## a specific Ascension ending hands over the one permanent mechanic it
## promised, the first time (and only the first time) it is completed.
func grant_ending_unlock(unlock_id: String) -> void:
	if not enabled:
		return
	_ensure_loaded()
	var unlock: Dictionary = get_unlock(unlock_id)
	if unlock.is_empty():
		return
	var unlocks: Dictionary = _profile.get("unlocks", {})
	if int(unlocks.get(unlock_id, 0)) > 0:
		return
	unlocks[unlock_id] = 1
	_profile["unlocks"] = unlocks
	_save()
	profile_changed.emit()


func ascension_completions(contract_id: String) -> int:
	_ensure_loaded()
	return int(Dictionary(_profile.get("ascensions", {})).get(contract_id, 0))


func record_ascension(contract_id: String) -> void:
	if not enabled:
		return
	_ensure_loaded()
	var ascensions: Dictionary = _profile.get("ascensions", {})
	ascensions[contract_id] = int(ascensions.get(contract_id, 0)) + 1
	_profile["ascensions"] = ascensions
	_save()


## The best of what a player has burned, for the meta hub. Only ever moves up.
func record_best_score(score: Dictionary) -> void:
	if not enabled:
		return
	_ensure_loaded()
	var best: Dictionary = _profile.get("best_scores", {})
	for key in ["total_tokens_burned", "peak_prompt_tokens", "peak_token_rate"]:
		best[key] = maxf(float(best.get(key, 0.0)), float(score.get(key, 0.0)))
	_profile["best_scores"] = best
	_save()


func best_scores() -> Dictionary:
	_ensure_loaded()
	return Dictionary(_profile.get("best_scores", {})).duplicate(true)


# --- Achievements ------------------------------------------------------------

func has_achievement(achievement_id: String) -> bool:
	_ensure_loaded()
	return Dictionary(_profile.get("achievements", {})).has(achievement_id)


func achievements() -> Dictionary:
	_ensure_loaded()
	return Dictionary(_profile.get("achievements", {})).duplicate(true)


func achievement_count() -> int:
	_ensure_loaded()
	return Dictionary(_profile.get("achievements", {})).size()


## Records an achievement the first time it is earned. Returns false if it was
## already in the cabinet, so the caller knows whether to celebrate.
func grant_achievement(achievement_id: String) -> bool:
	if not enabled:
		return false
	_ensure_loaded()
	var earned: Dictionary = _profile.get("achievements", {})
	if earned.has(achievement_id):
		return false
	earned[achievement_id] = int(Time.get_unix_time_from_system())
	_profile["achievements"] = earned
	_save()
	profile_changed.emit()
	return true


func lifetime_stats() -> Dictionary:
	_ensure_loaded()
	return Dictionary(_profile.get("lifetime_stats", {})).duplicate(true)


func lifetime_stat(key: String) -> float:
	_ensure_loaded()
	return float(Dictionary(_profile.get("lifetime_stats", {})).get(key, 0.0))


## Folds one run's contribution into the cumulative counters. Called once, when
## the run ends, so a reloaded save cannot bank the same run twice.
func add_lifetime_stats(deltas: Dictionary) -> void:
	if not enabled:
		return
	_ensure_loaded()
	var stats: Dictionary = _profile.get("lifetime_stats", {})
	for key in deltas.keys():
		if not (key in LIFETIME_KEYS):
			continue
		stats[str(key)] = float(stats.get(key, 0.0)) + float(deltas[key])
	_profile["lifetime_stats"] = stats
	_save()


## The difficulty a fresh run starts on. Persisted across runs like everything
## else here — it is a player preference, not something a single run owns.
func difficulty() -> String:
	_ensure_loaded()
	return str(_profile.get("difficulty", "normal"))


func set_difficulty(difficulty_id: String) -> void:
	_ensure_loaded()
	_profile["difficulty"] = difficulty_id
	_save()
	profile_changed.emit()


# --- Campaign locations ------------------------------------------------------

## The campaign is a list of places rather than a ladder bought during a run:
## a run happens in exactly one of them, and clearing it is what opens the next.
## With the meta layer switched off — the test suite, balance sweeps — every run
## starts from the first rung, for the same reason Endless is forced off there.

## The full campaign in order, from content so the order and the balance data
## that describes each location cannot drift apart.
func location_order() -> Array:
	var order: Array = Array(
		ContentDatabase.balance.get("economy", {}).get("location_order", [])
	)
	if order.is_empty():
		return FALLBACK_LOCATION_ORDER.duplicate()
	var ids: Array = []
	for entry in order:
		ids.append(str(entry))
	return ids


func unlocked_locations() -> Array:
	if not enabled:
		return [DEFAULT_LOCATION]
	_ensure_loaded()
	return Array(_locations().get("unlocked", [])).duplicate()


func is_location_unlocked(location_id: String) -> bool:
	return location_id in unlocked_locations()


func completed_locations() -> Array:
	if not enabled:
		return []
	_ensure_loaded()
	return Array(_locations().get("completed", [])).duplicate()


## Where the next run will take place.
func selected_location() -> String:
	if not enabled:
		return DEFAULT_LOCATION
	_ensure_loaded()
	var selected: String = str(_locations().get("selected", DEFAULT_LOCATION))
	if not is_location_unlocked(selected):
		return DEFAULT_LOCATION
	return selected


## Chooses where the next run happens. Refuses rather than silently falling back
## so a stale menu cannot start a run somewhere the player has not earned.
func select_location(location_id: String) -> bool:
	if not enabled:
		return false
	_ensure_loaded()
	if not is_location_unlocked(location_id):
		return false
	var locations: Dictionary = _locations()
	locations["selected"] = location_id
	_profile["locations"] = locations
	_save()
	profile_changed.emit()
	return true


## Opens a location permanently. Returns false when it was already open, so a
## caller can tell a first clear from a replay.
func unlock_location(location_id: String) -> bool:
	if not enabled:
		return false
	if not (location_id in location_order()):
		return false
	_ensure_loaded()
	var locations: Dictionary = _locations()
	var unlocked: Array = Array(locations.get("unlocked", []))
	if location_id in unlocked:
		return false
	unlocked.append(location_id)
	locations["unlocked"] = _sorted_by_campaign_order(unlocked)
	_profile["locations"] = locations
	_save()
	profile_changed.emit()
	return true


## Records a location as beaten and opens whatever follows it. Replaying a
## cleared location is allowed, so completion is a set rather than a counter.
func complete_location(location_id: String) -> void:
	if not enabled:
		return
	_ensure_loaded()
	var locations: Dictionary = _locations()
	var completed: Array = Array(locations.get("completed", []))
	if not (location_id in completed):
		completed.append(location_id)
		locations["completed"] = _sorted_by_campaign_order(completed)
		_profile["locations"] = locations
		_save()
	var next_id: String = next_location_after(location_id)
	if next_id != "":
		unlock_location(next_id)
	profile_changed.emit()


## The rung above this one, or "" at the top of the campaign.
func next_location_after(location_id: String) -> String:
	var order: Array = location_order()
	var index: int = order.find(location_id)
	if index < 0 or index + 1 >= order.size():
		return ""
	return str(order[index + 1])


## A location id as a player-facing name. Derived rather than authored: the ids
## are already readable words, and a second list of them would only drift.
func location_name(location_id: String) -> String:
	if location_id == "":
		return ""
	return location_id.replace("_", " ").capitalize()


## Brings the profile up to date with a location the player is demonstrably in:
## a save from before the campaign existed can be mid-warehouse, and everything
## below that rung must count as already earned.
func ensure_location_unlocked_through(location_id: String) -> void:
	if not enabled:
		return
	var order: Array = location_order()
	var index: int = order.find(location_id)
	if index < 0:
		return
	for i in range(index + 1):
		unlock_location(str(order[i]))


func _locations() -> Dictionary:
	var locations: Dictionary = Dictionary(_profile.get("locations", {}))
	if locations.is_empty():
		locations = _default_locations()
		_profile["locations"] = locations
	return locations


func _default_locations() -> Dictionary:
	return {
		"unlocked": [DEFAULT_LOCATION],
		"selected": DEFAULT_LOCATION,
		"completed": [],
	}


func _sorted_by_campaign_order(ids: Array) -> Array:
	var order: Array = location_order()
	var sorted: Array = []
	for entry in order:
		if str(entry) in ids:
			sorted.append(str(entry))
	# Anything the campaign no longer lists is kept rather than dropped: a
	# renamed location should not quietly cost the player an unlock.
	for entry in ids:
		if not (str(entry) in sorted):
			sorted.append(str(entry))
	return sorted


## Endless mode unlocks the first time any Tier 3 Ascension Contract is
## completed once: proof the build can already reach the real finish line, so
## an infinite tail past round 12 is a bonus rather than a way to dodge it.
func endless_unlocked() -> bool:
	_ensure_loaded()
	var ascensions: Dictionary = _profile.get("ascensions", {})
	for contract in ContentDatabase.ascension_contracts:
		if int(contract.get("tier", 1)) >= 3 and int(ascensions.get(str(contract.get("id", "")), 0)) > 0:
			return true
	return false


## With the meta layer switched off — balance sweeps, the test suite — the run
## must behave like a first run from nothing. Reading the developer's own
## profile here let a saved Endless toggle change what the sample measured.
func endless_enabled() -> bool:
	if not enabled:
		return false
	_ensure_loaded()
	return endless_unlocked() and bool(_profile.get("endless_enabled", false))


func set_endless_enabled(value: bool) -> void:
	_ensure_loaded()
	_profile["endless_enabled"] = value
	_save()
	profile_changed.emit()


## Spends one banked pick. Returns false rather than half-applying if there is
## nothing to spend or the unlock is no longer available.
func spend_pick(unlock_id: String) -> bool:
	if not enabled:
		return false
	_ensure_loaded()
	if pending_picks() <= 0:
		return false
	if not is_available(unlock_id):
		return false
	var unlocks: Dictionary = _profile.get("unlocks", {})
	unlocks[unlock_id] = unlock_count(unlock_id) + 1
	_profile["unlocks"] = unlocks
	_profile["pending_picks"] = pending_picks() - 1
	_save()
	profile_changed.emit()
	return true


## Cooling every owned unlock is worth. A function of the profile alone, so a
## run being loaded can recover it without replaying the whole unlock list.
func cooling_bonus() -> float:
	if not enabled:
		return 0.0
	_ensure_loaded()
	var total: float = 0.0
	var unlocks: Dictionary = _profile.get("unlocks", {})
	for unlock_id in unlocks.keys():
		var unlock: Dictionary = _catalog_by_id.get(unlock_id, {})
		if str(unlock.get("kind", "")) == "cooling":
			total += float(unlock.get("amount", 0.0)) * float(int(unlocks[unlock_id]))
	return total


## Folds every owned unlock into a freshly reset run. Called before the board is
## sized, so an extra slot is already in place when the slots are laid out.
func apply_to_run(run_state: RunState) -> void:
	if not enabled:
		return
	_ensure_loaded()
	var unlocks: Dictionary = _profile.get("unlocks", {})
	for unlock_id in unlocks.keys():
		var unlock: Dictionary = _catalog_by_id.get(unlock_id, {})
		if unlock.is_empty():
			continue
		for _i in range(int(unlocks[unlock_id])):
			_apply_one(run_state, unlock)
	_apply_age(run_state)


## The Compute Age is cosmetic-plus: it scales jobs a little harder and starts
## the player with a little more cash, so a new age visibly feels bigger
## without being a second currency to manage.
func _apply_age(run_state: RunState) -> void:
	var age_data: Dictionary = Ages.get_age(age())
	if age_data.is_empty():
		return
	run_state.economy["cash"] = float(run_state.economy.get("cash", 0.0)) + float(age_data.get("starting_cash_bonus", 0.0))
	run_state.business["age_token_multiplier"] = float(age_data.get("token_scaling_multiplier", 1.0))
	run_state.business["age_reward_multiplier"] = float(age_data.get("reward_scaling_multiplier", 1.0))
	run_state.business["age_name"] = str(age_data.get("name", "Bedroom Age"))


func _apply_one(run_state: RunState, unlock: Dictionary) -> void:
	var amount: float = float(unlock.get("amount", 0.0))
	match str(unlock.get("kind", "")):
		"extra_slot":
			var board: Dictionary = run_state.build.get("board", {})
			board["slot_count"] = mini(
				int(board.get("slot_count", BoardSystem.DEFAULT_SLOT_COUNT)) + int(amount),
				BoardSystem.MAX_SLOT_COUNT
			)
		"starting_module":
			var operation_id: String = str(unlock.get("operation_id", ""))
			var owned: Array = run_state.build.get("operations", [])
			if operation_id != "" and not (operation_id in owned):
				owned.append(operation_id)
				run_state.build["operations"] = owned
		"cooling":
			# Kept apart from the run's own cooling, which is derived from the
			# location and the kit in it and would overwrite anything added here.
			run_state.compute["meta_cooling"] = (
				float(run_state.compute.get("meta_cooling", 0.0)) + amount
			)
		"starting_cash":
			run_state.economy["cash"] = float(run_state.economy.get("cash", 0.0)) + amount
		"efficiency_base":
			run_state.compute["efficiency_base"] = (
				float(run_state.compute.get("efficiency_base", 1.0)) + amount
			)
		"starting_cloud_account":
			_grant_cloud_account(run_state)
		"starting_cloud":
			# Capacity without the account would be tokens nobody is billing for,
			# and would leave the CLOUD key dead on a run that clearly has cloud.
			_grant_cloud_account(run_state)
			run_state.compute["cloud_capacity"] = float(run_state.compute.get("cloud_capacity", 0.0)) + amount
			run_state.economy["cloud_cost_per_prompt"] = (
				float(run_state.economy.get("cloud_cost_per_prompt", 0.0)) + float(unlock.get("recurring_cost", 0.0))
			)
		"passive_income":
			run_state.economy["passive_income_per_round"] = (
				float(run_state.economy.get("passive_income_per_round", 0.0)) + amount
			)
		"workflow_slot":
			run_state.build["workflow_capacity"] = mini(
				int(run_state.build.get("workflow_capacity", BoardSystem.DEFAULT_WORKFLOW_CAPACITY))
					+ maxi(1, int(amount)),
				BoardSystem.MAX_WORKFLOW_COUNT
			)
		"rule_flag":
			var flags: Array = Array(run_state.build.get("meta_unlocks", []))
			var unlock_id: String = str(unlock.get("id", ""))
			if unlock_id != "" and not (unlock_id in flags):
				flags.append(unlock_id)
				run_state.build["meta_unlocks"] = flags


## Marks the cloud account as owned without charging for it. The upgrade is the
## run's record of the capability, so the Market hides it and the board's CLOUD
## key lights up exactly as if it had been bought.
func _grant_cloud_account(run_state: RunState) -> void:
	var owned: Array = run_state.build.get("upgrades", [])
	if not (Simulation.CLOUD_ACCOUNT_UPGRADE in owned):
		owned.append(Simulation.CLOUD_ACCOUNT_UPGRADE)
		run_state.build["upgrades"] = owned
	run_state.build["cloud_tier"] = Simulation.CLOUD_ACCOUNT_UPGRADE


## Wipes the profile. Exposed for tests and for a player who wants the first run
## back the way it was.
func reset_profile() -> void:
	_loaded = true
	if _catalog.is_empty():
		_load_catalog()
	_profile = _default_profile()
	_save()
	profile_changed.emit()


## Points the profile at a scratch file and starts it empty. Tests only.
func use_scratch_profile(path: String) -> void:
	profile_path = path
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_loaded = false
	_ensure_loaded()


func _default_profile() -> Dictionary:
	return {
		"version": PROFILE_VERSION,
		"victories": 0,
		"unlocks": {},
		"pending_picks": 0,
		"retirements": 0,
		"age": 0,
		"ascensions": {},
		"best_scores": {},
		"achievements": {},
		"lifetime_stats": {},
		"difficulty": "normal",
		"endless_enabled": false,
		"locations": _default_locations(),
	}


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_catalog()
	_load_profile()


func _load_catalog() -> void:
	_catalog.clear()
	_catalog_by_id.clear()
	if not FileAccess.file_exists(CATALOG_PATH):
		return
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Array:
		return
	for entry in parsed:
		if not entry is Dictionary:
			continue
		_catalog.append(entry)
		_catalog_by_id[str(entry.get("id", ""))] = entry


func _load_profile() -> void:
	_profile = _default_profile()
	if not FileAccess.file_exists(profile_path):
		return
	var file := FileAccess.open(profile_path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	var loaded: Dictionary = parsed
	# JSON gives back floats, and unlock counts are used as loop bounds.
	var unlocks: Dictionary = {}
	for key in Dictionary(loaded.get("unlocks", {})).keys():
		unlocks[str(key)] = int(loaded["unlocks"][key])
	var ascensions: Dictionary = {}
	for key in Dictionary(loaded.get("ascensions", {})).keys():
		ascensions[str(key)] = int(loaded["ascensions"][key])
	var best_scores: Dictionary = {}
	for key in Dictionary(loaded.get("best_scores", {})).keys():
		best_scores[str(key)] = float(loaded["best_scores"][key])
	var earned: Dictionary = {}
	for key in Dictionary(loaded.get("achievements", {})).keys():
		earned[str(key)] = int(loaded["achievements"][key])
	var lifetime: Dictionary = {}
	for key in Dictionary(loaded.get("lifetime_stats", {})).keys():
		lifetime[str(key)] = float(loaded["lifetime_stats"][key])
	var locations: Dictionary = _default_locations()
	if loaded.get("locations", null) is Dictionary:
		var stored: Dictionary = loaded["locations"]
		var unlocked: Array = [DEFAULT_LOCATION]
		for entry in Array(stored.get("unlocked", [])):
			if not (str(entry) in unlocked):
				unlocked.append(str(entry))
		var completed: Array = []
		for entry in Array(stored.get("completed", [])):
			if not (str(entry) in completed):
				completed.append(str(entry))
		locations = {
			"unlocked": unlocked,
			"selected": str(stored.get("selected", DEFAULT_LOCATION)),
			"completed": completed,
		}
	_profile = {
		"version": PROFILE_VERSION,
		"victories": int(loaded.get("victories", 0)),
		"unlocks": unlocks,
		"pending_picks": int(loaded.get("pending_picks", 0)),
		"retirements": int(loaded.get("retirements", 0)),
		"age": int(loaded.get("age", 0)),
		"ascensions": ascensions,
		"best_scores": best_scores,
		"achievements": earned,
		"lifetime_stats": lifetime,
		"difficulty": str(loaded.get("difficulty", "normal")),
		"endless_enabled": bool(loaded.get("endless_enabled", false)),
		"locations": locations,
	}
	_migrate_profile(int(loaded.get("version", 1)))


## Profiles written before achievements existed simply have none. Their runs
## still happened though, so the counters an achievement reads are seeded from
## the records the old profile did keep rather than starting at zero.
func _migrate_profile(from_version: int) -> void:
	if from_version >= PROFILE_VERSION:
		return
	if from_version < 2:
		var stats: Dictionary = _profile["lifetime_stats"]
		var runs: int = int(_profile.get("victories", 0)) + int(_profile.get("retirements", 0))
		stats["runs"] = maxf(float(stats.get("runs", 0.0)), float(runs))
		stats["tokens_burned"] = maxf(
			float(stats.get("tokens_burned", 0.0)),
			float(Dictionary(_profile.get("best_scores", {})).get("total_tokens_burned", 0.0))
		)
	if from_version < 3:
		# Profiles written before the campaign existed have no record of which
		# premises they reached — that lived in the run save, not here. They
		# start the campaign at the bottom; loading an in-progress run reopens
		# whatever rung it was actually on.
		var locations: Dictionary = _locations()
		locations["unlocked"] = _sorted_by_campaign_order(
			Array(locations.get("unlocked", [DEFAULT_LOCATION]))
		)
		_profile["locations"] = locations
	_save()


func _save() -> void:
	var file := FileAccess.open(profile_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_profile, "\t"))
	file.close()
