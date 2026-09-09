extends Node

## Cross-run progression. Everything else in the game is scoped to a single run
## and thrown away; this is the one file that remembers.
##
## Only completing the game — the final Investor Target — banks picks. Spending
## a pick buys a Permanent Unlock from content/meta/unlocks.json, which is
## applied to every run from then on. Targets cleared on the way up are
## level-ups inside a run, not sources of permanent power. The profile also
## keeps the player's records: deepest Deep Burn, biggest batch, richest run,
## fastest completion.

const DEFAULT_PROFILE_PATH := "user://profile.json"
const CATALOG_PATH := "res://content/meta/unlocks.json"
const PROFILE_VERSION := 8

## The player's bests across every run, for the records sheet. Every entry only
## ever moves up (or, for the fastest completion, down).
const RECORD_KEYS: Array[String] = [
	"games_completed",
	"highest_depth",
	"highest_multiplier",
	"highest_single_batch",
	"highest_profit",
	"fastest_completion_rounds",
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


func sound_muted() -> bool:
	_ensure_loaded()
	return bool(_settings().get("sound_muted", false))


func set_sound_muted(muted: bool) -> void:
	_ensure_loaded()
	var settings: Dictionary = _settings()
	settings["sound_muted"] = muted
	_profile["settings"] = settings
	_save()
	profile_changed.emit()


func sound_volume() -> float:
	_ensure_loaded()
	return clampf(float(_settings().get("sound_volume", 1.0)), 0.0, 1.0)


func set_sound_volume(volume: float) -> void:
	_ensure_loaded()
	var settings: Dictionary = _settings()
	settings["sound_volume"] = clampf(volume, 0.0, 1.0)
	_profile["settings"] = settings
	_save()
	profile_changed.emit()


func toggle_sound_muted() -> void:
	set_sound_muted(not sound_muted())


## The profile's reduced-motion choice, or null when the player has never set
## it (the project default then applies; see `UiFx.reduced_motion`).
func reduced_motion_setting() -> Variant:
	_ensure_loaded()
	var settings: Dictionary = _settings()
	if not settings.has("reduced_motion"):
		return null
	return bool(settings["reduced_motion"])


func reduced_motion() -> bool:
	var stored: Variant = reduced_motion_setting()
	if stored == null:
		return UiFx.reduced_motion()
	return bool(stored)


func set_reduced_motion(value: bool) -> void:
	_ensure_loaded()
	var settings: Dictionary = _settings()
	settings["reduced_motion"] = value
	_profile["settings"] = settings
	_save()
	profile_changed.emit()


func seen_onboarding() -> bool:
	_ensure_loaded()
	return bool(_settings().get("seen_onboarding", false))


func mark_onboarding_seen() -> void:
	_ensure_loaded()
	var settings: Dictionary = _settings()
	settings["seen_onboarding"] = true
	_profile["settings"] = settings
	_save()


func _settings() -> Dictionary:
	return _merge_settings(_profile.get("settings", {}))


func _default_settings() -> Dictionary:
	return {
		"sound_muted": false,
		"sound_volume": 1.0,
		"seen_onboarding": false,
	}


## Settings the profile only stores once the player has chosen them; absent
## means "use the project default" (see `reduced_motion_setting`).
const OPTIONAL_SETTINGS: Array[String] = ["reduced_motion"]


func _merge_settings(raw: Variant) -> Dictionary:
	var settings: Dictionary = _default_settings()
	if raw is Dictionary:
		for key in settings.keys():
			if raw.has(key):
				settings[key] = raw[key]
		for key in OPTIONAL_SETTINGS:
			if raw.has(key):
				settings[key] = raw[key]
	return settings


func victories() -> int:
	_ensure_loaded()
	return int(_profile.get("victories", 0))


func pending_picks() -> int:
	_ensure_loaded()
	return int(_profile.get("pending_picks", 0))


func unlock_count(unlock_id: String) -> int:
	_ensure_loaded()
	return int(Dictionary(_profile.get("unlocks", {})).get(unlock_id, 0))


## Cloud unlocks used to grant a free account. After those unlocks were retired
## the ranks come back as picks, but a pre-v19 run save still has to know the
## account was never paid for.
func retired_cloud_unlocks() -> bool:
	_ensure_loaded()
	return bool(_profile.get("retired_cloud_unlocks", false))


func catalog() -> Array:
	_ensure_loaded()
	return _catalog.duplicate(true)


func get_unlock(unlock_id: String) -> Dictionary:
	_ensure_loaded()
	return Dictionary(_catalog_by_id.get(unlock_id, {})).duplicate(true)


## Whether this unlock can still be bought: one-offs only once, and extra slots
## only until the board hits the width the resolver can lay out.
func victories_on(difficulty_id: String) -> int:
	_ensure_loaded()
	return int(Dictionary(_profile.get("victories_by_difficulty", {})).get(difficulty_id, 0))


## Extra cards on the investor's table, from Rolodex ranks. The draft is three
## cards by default; ranks add one each, capped so the table never shows more
## than five.
const BASE_DRAFT_OPTIONS := 3
const MAX_DRAFT_OPTIONS := 5


func draft_option_bonus() -> int:
	var rank: int = unlock_count("unlock.rolodex")
	if rank <= 0:
		return 0
	var bonus: int = int(_rank_value(get_unlock("unlock.rolodex"), rank))
	return clampi(bonus, 0, MAX_DRAFT_OPTIONS - BASE_DRAFT_OPTIONS)


## How many perks the investor lays out when a goal is met.
func draft_option_count() -> int:
	return BASE_DRAFT_OPTIONS + draft_option_bonus()


func completion_summary() -> Dictionary:
	_ensure_loaded()
	var achievements_earned: int = achievement_count()
	var achievements_total: int = ContentDatabase.achievements.size()
	var perks_unlocked: int = 0
	var perks_total: int = ContentDatabase.perks.size()
	for perk in ContentDatabase.perks:
		if ContentDatabase.perk_is_unlocked(perk):
			perks_unlocked += 1
	var modules_unlocked: int = 0
	var modules_total: int = ContentDatabase.modules.size()
	for module in ContentDatabase.modules:
		if ContentDatabase.module_is_unlocked(module):
			modules_unlocked += 1
	var permanent_owned: int = 0
	var permanent_total: int = 0
	for unlock in _catalog:
		var ranks: Array = Array(unlock.get("ranks", []))
		if ranks.is_empty():
			continue
		permanent_total += ranks.size()
		permanent_owned += mini(unlock_count(str(unlock.get("id", ""))), ranks.size())
	var parts: Array[float] = []
	if achievements_total > 0:
		parts.append(float(achievements_earned) / float(achievements_total))
	if perks_total > 0:
		parts.append(float(perks_unlocked) / float(perks_total))
	if modules_total > 0:
		parts.append(float(modules_unlocked) / float(modules_total))
	if permanent_total > 0:
		parts.append(float(permanent_owned) / float(permanent_total))
	var percent: float = 0.0
	for part in parts:
		percent += part
	if not parts.is_empty():
		percent = (percent / float(parts.size())) * 100.0
	var overall: bool = achievements_earned >= achievements_total \
		and perks_unlocked >= perks_total \
		and modules_unlocked >= modules_total \
		and permanent_owned >= permanent_total \
		and achievements_total > 0 and perks_total > 0 and modules_total > 0 and permanent_total > 0
	return {
		"achievements": {"earned": achievements_earned, "total": achievements_total},
		"perks": {"unlocked": perks_unlocked, "total": perks_total},
		"modules": {"unlocked": modules_unlocked, "total": modules_total},
		"permanent_unlocks": {"ranks_owned": permanent_owned, "total_ranks": permanent_total},
		"overall_complete": overall,
		"percent": percent,
	}


func _legacy_rank_total(unlock_id: String) -> int:
	var unlock: Dictionary = get_unlock(unlock_id)
	var ranks: Array = Array(unlock.get("ranks", []))
	if ranks.is_empty():
		return 0
	var owned: int = unlock_count(unlock_id)
	var total: int = 0
	for i in range(mini(owned, ranks.size())):
		total += int(ranks[i])
	return total


func _rank_value(unlock: Dictionary, rank: int) -> float:
	var ranks: Array = Array(unlock.get("ranks", []))
	if ranks.is_empty():
		return float(unlock.get("amount", 0.0))
	var index: int = clampi(rank - 1, 0, ranks.size() - 1)
	return float(ranks[index])


func is_available(unlock_id: String) -> bool:
	var unlock: Dictionary = get_unlock(unlock_id)
	if unlock.is_empty():
		return false
	var owned: int = unlock_count(unlock_id)
	var ranks: Array = Array(unlock.get("ranks", []))
	if not ranks.is_empty():
		if owned >= ranks.size():
			return false
		var required: Array = Array(unlock.get("hard_victories_required", []))
		if owned < required.size() and int(required[owned]) > victories_on("hard"):
			return false
		return true
	if not bool(unlock.get("repeatable", false)):
		return owned == 0
	if str(unlock.get("kind", "")) in ["overflow_capacity", "extra_slot"]:
		return owned < BoardSystem.MAX_META_OVERFLOW_BONUS
	if str(unlock.get("kind", "")) == "workflow_slot":
		return BoardSystem.DEFAULT_WORKFLOW_CAPACITY + owned < BoardSystem.MAX_WORKFLOW_COUNT
	# A tiered ladder runs out when its last rung is owned.
	if str(unlock.get("kind", "")) == "starting_hardware":
		return owned < Array(unlock.get("ladder", [])).size()
	return true


## Every unlock a banked pick could buy right now. Picks are rare — one batch
## per completion of the whole game — so the player chooses freely between all
## the areas rather than being dealt a random hand. Reward-only unlocks
## (granted automatically by completing the game) never show up here — picks
## are choices, not prizes already handed out.
func available_choices() -> Array:
	_ensure_loaded()
	var pool: Array = []
	for unlock in _catalog:
		if bool(unlock.get("reward_only", false)):
			continue
		if is_available(str(unlock.get("id", ""))):
			pool.append(unlock.duplicate(true))
	return pool


## Banks `picks` unlock picks for completing the game's final Investor Target.
## Only the summit pays permanence: a target cleared on the way up is progress
## inside the run, not a source of unlocks.
func bank_victory(picks: int = 1, difficulty_id: String = "normal") -> void:
	if not enabled:
		return
	_ensure_loaded()
	_profile["victories"] = victories() + 1
	var by_difficulty: Dictionary = Dictionary(_profile.get("victories_by_difficulty", {}))
	by_difficulty[difficulty_id] = int(by_difficulty.get(difficulty_id, 0)) + 1
	_profile["victories_by_difficulty"] = by_difficulty
	_profile["pending_picks"] = pending_picks() + maxi(0, picks)
	var bests: Dictionary = _records()
	bests["games_completed"] = maxi(int(bests.get("games_completed", 0)), victories())
	_profile["records"] = bests
	_save()
	pick_banked.emit(pending_picks())


# --- Records -----------------------------------------------------------------

func records() -> Dictionary:
	_ensure_loaded()
	return _records().duplicate(true)


## Folds one run's bests into the profile's records. Safe to call on every
## ending — each record only ever improves, so a run banked twice cannot move a
## record the wrong way. The fastest completion is taken only at the moment the
## final target is met (before the run carries on into Deep Burn), so the rounds
## spent burning afterwards never count against it. `highest_multiplier` is the
## Deep Burn score multiplier, the one multiplier the run tracks.
func record_run_records(run_state: RunState) -> void:
	if not enabled or run_state == null:
		return
	_ensure_loaded()
	var bests: Dictionary = _records()
	var stats: Dictionary = run_state.statistics
	bests["highest_depth"] = maxi(
		int(bests.get("highest_depth", 0)),
		maxi(int(stats.get("depth_reached", 0)), int(run_state.depth.get("level", 0)))
	)
	bests["highest_multiplier"] = maxf(
		float(bests.get("highest_multiplier", 1.0)), float(run_state.depth.get("score_mult", 1.0))
	)
	bests["highest_single_batch"] = maxf(
		float(bests.get("highest_single_batch", 0.0)), float(stats.get("peak_prompt_tokens", 0.0))
	)
	bests["highest_profit"] = maxf(
		float(bests.get("highest_profit", 0.0)),
		maxf(float(stats.get("peak_cash", 0.0)), float(run_state.economy.get("cash", 0.0)))
	)
	var completed_now: bool = bool(run_state.flags.get("game_completed", false)) \
		and bool(run_state.flags.get("victory", false)) \
		and not bool(run_state.flags.get("post_victory", false))
	if completed_now:
		var rounds: int = maxi(1, int(run_state.calendar.get("round", 1)))
		var fastest: int = int(bests.get("fastest_completion_rounds", 0))
		bests["fastest_completion_rounds"] = rounds if fastest <= 0 else mini(fastest, rounds)
	_profile["records"] = bests
	_save()
	profile_changed.emit()


func _records() -> Dictionary:
	var stored: Dictionary = Dictionary(_profile.get("records", {}))
	var bests: Dictionary = _default_records()
	for key in RECORD_KEYS:
		if stored.has(key):
			bests[key] = stored[key]
	return bests


func _default_records() -> Dictionary:
	return {
		"games_completed": 0,
		"highest_depth": 0,
		"highest_multiplier": 1.0,
		"highest_single_batch": 0.0,
		"highest_profit": 0.0,
		"fastest_completion_rounds": 0,
	}


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


## The Compute Age a fresh run starts in. Advances one step the first time the
## game is completed while the next age is still unreached.
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
## completing the game hands over the one permanent mechanic the final target
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


## The machines a fresh run starts with, earned one rung at a time through the
## "starting_hardware" unlock ladder: the first pick is the desktop, the next is
## the GPU rack, and so on. This is the only kit that crosses runs — everything
## a run bought dies with the run, exactly like a fresh game from the start.
func starting_rig() -> Array:
	if not enabled:
		return []
	_ensure_loaded()
	var earned: Array = []
	var unlocks: Dictionary = _profile.get("unlocks", {})
	for unlock_id in unlocks.keys():
		var unlock: Dictionary = _catalog_by_id.get(unlock_id, {})
		if str(unlock.get("kind", "")) != "starting_hardware":
			continue
		var ladder: Array = Array(unlock.get("ladder", []))
		for i in range(mini(int(unlocks[unlock_id]), ladder.size())):
			earned.append(str(ladder[i]))
	return earned


## Endless mode unlocks the first time the game's final target is completed:
## proof the build can already reach the real finish line, so an infinite tail
## past the calendar is a bonus rather than a way to dodge it.
func endless_unlocked() -> bool:
	_ensure_loaded()
	var ascensions: Dictionary = _profile.get("ascensions", {})
	for contract in ContentDatabase.investor_targets:
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
## sized, so overflow allowance is already in place when the slots are laid out.
func apply_to_run(run_state: RunState) -> void:
	if not enabled:
		return
	_ensure_loaded()
	var unlocks: Dictionary = _profile.get("unlocks", {})
	for unlock_id in unlocks.keys():
		var unlock: Dictionary = _catalog_by_id.get(unlock_id, {})
		if unlock.is_empty():
			continue
		var rank: int = int(unlocks[unlock_id])
		if rank <= 0:
			continue
		_apply_rank(run_state, unlock, rank)
	_apply_age(run_state)
	_apply_legacy_multipliers(run_state)


## Folds one owned unlock into the run at the rank the profile has reached.
##
## A `ranks` table is a table of *totals*, so rank three is read once and is the
## whole value — stacking them would compound the very thing the table exists to
## bound. The older `amount` entries have no table and are still per-pick, so
## those multiply out by rank to keep what an existing profile already bought.
func _apply_rank(run_state: RunState, unlock: Dictionary, rank: int) -> void:
	var kind: String = str(unlock.get("kind", ""))
	var ranks: Array = Array(unlock.get("ranks", []))
	var value: float = _rank_value(unlock, rank)
	if ranks.is_empty() and rank > 1:
		match kind:
			"overflow_capacity", "extra_slot", "workflow_slot", "cooling", "efficiency_base", "passive_income", "starting_module":
				value = float(unlock.get("amount", 1.0)) * float(rank)
	match kind:
		"overflow_capacity", "extra_slot":
			# Safe capacity belongs to the backplane alone; a permanent slot is
			# permission to bolt one more overflow stage on. `extra_slot` is the
			# pre-v25 spelling of the same kind, kept so an old catalog entry in
			# a profile still applies.
			var board: Dictionary = run_state.build.get("board", {})
			board["meta_overflow_bonus"] = int(board.get("meta_overflow_bonus", 0)) + int(value)
			run_state.build["board"] = board
		"starting_module":
			var module_id: String = str(unlock.get("module_id", ""))
			var owned: Array = run_state.build.get("modules", [])
			if module_id != "" and not (module_id in owned):
				owned.append(module_id)
				run_state.build["modules"] = owned
		"cooling":
			# Kept apart from the run's own cooling, which is derived from the
			# Infrastructure Tier and the kit in it and would overwrite anything added here.
			run_state.compute["meta_cooling"] = float(run_state.compute.get("meta_cooling", 0.0)) + value
		"starting_cash":
			run_state.economy["cash"] = float(run_state.economy.get("cash", 0.0)) + value
		"efficiency_base":
			run_state.compute["efficiency_base"] = float(run_state.compute.get("efficiency_base", 1.0)) + value
		"passive_income":
			run_state.economy["passive_income_per_round"] = (
				float(run_state.economy.get("passive_income_per_round", 0.0)) + value
			)
		"workflow_slot":
			run_state.build["meta_workflow_bonus"] = int(run_state.build.get("meta_workflow_bonus", 0)) + maxi(1, int(value))
		"rule_flag":
			var flags: Array = Array(run_state.build.get("meta_unlocks", []))
			var unlock_id: String = str(unlock.get("id", ""))
			if unlock_id != "" and not (unlock_id in flags):
				flags.append(unlock_id)
				run_state.build["meta_unlocks"] = flags
		"token_multiplier", "income_multiplier":
			# Read straight off the profile by `_apply_legacy_multipliers`, which
			# has to run after `_apply_age` writes the age's own multipliers.
			pass
		"draft_options", "perk_slots":
			# Read live by `draft_option_bonus` when the investor deals, so
			# there is nothing to write onto the run. `perk_slots` is the
			# pre-v25 spelling of the same unlock.
			pass
		"starting_hardware":
			# Installed by the Simulation via the upgrade pipeline, which owns
			# hardware slots, recurring bills and effects. Nothing to do here.
			pass


func _apply_legacy_multipliers(run_state: RunState) -> void:
	var token_rank: int = unlock_count("unlock.old_silicon")
	if token_rank > 0:
		run_state.business["legacy_token_multiplier"] = _rank_value(get_unlock("unlock.old_silicon"), token_rank)
	var income_rank: int = unlock_count("unlock.recurring_revenue")
	if income_rank > 0:
		run_state.business["legacy_income_multiplier"] = _rank_value(get_unlock("unlock.recurring_revenue"), income_rank)


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
		"victories_by_difficulty": {"normal": 0, "hard": 0},
		"unlocks": {},
		"pending_picks": 0,
		"retired_cloud_unlocks": false,
		"retirements": 0,
		"age": 0,
		"ascensions": {},
		"best_scores": {},
		"achievements": {},
		"lifetime_stats": {},
		"difficulty": "normal",
		"endless_enabled": false,
		"records": _default_records(),
		"settings": _default_settings(),
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
	var bests: Dictionary = _default_records()
	if loaded.get("records", null) is Dictionary:
		var stored: Dictionary = loaded["records"]
		for key in RECORD_KEYS:
			if not stored.has(key):
				continue
			if bests[key] is int:
				bests[key] = int(stored[key])
			else:
				bests[key] = float(stored[key])
	_profile = {
		"version": PROFILE_VERSION,
		"victories": int(loaded.get("victories", 0)),
		"victories_by_difficulty": Dictionary(loaded.get("victories_by_difficulty", {"normal": 0, "hard": 0})),
		"unlocks": unlocks,
		"pending_picks": int(loaded.get("pending_picks", 0)),
		"retired_cloud_unlocks": bool(loaded.get("retired_cloud_unlocks", false)),
		"retirements": int(loaded.get("retirements", 0)),
		"age": int(loaded.get("age", 0)),
		"ascensions": ascensions,
		"best_scores": best_scores,
		"achievements": earned,
		"lifetime_stats": lifetime,
		"difficulty": str(loaded.get("difficulty", "normal")),
		"endless_enabled": bool(loaded.get("endless_enabled", false)),
		"records": bests,
		"settings": _merge_settings(loaded.get("settings", {})),
	}
	# The v8 profile has no `locations` block: anything an older profile kept
	# there is dropped on load rather than carried as dead weight.
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
	# v3 and v4 shaped the campaign `locations` block; v8 removed it, so there
	# is nothing left for those steps to do.
	if from_version < 5:
		if not _profile.has("victories_by_difficulty"):
			_profile["victories_by_difficulty"] = {"normal": 0, "hard": 0}
		var unlocks: Dictionary = Dictionary(_profile.get("unlocks", {}))
		var refunded: int = 0
		for unlock in _catalog:
			var ranks: Array = Array(unlock.get("ranks", []))
			if ranks.is_empty():
				continue
			var unlock_id: String = str(unlock.get("id", ""))
			var owned: int = int(unlocks.get(unlock_id, 0))
			if owned > ranks.size():
				refunded += owned - ranks.size()
				unlocks[unlock_id] = ranks.size()
		if refunded > 0:
			_profile["unlocks"] = unlocks
			_profile["pending_picks"] = int(_profile.get("pending_picks", 0)) + refunded
	if from_version < 6:
		_profile["settings"] = _merge_settings(_profile.get("settings", {}))
	if from_version < 7:
		var cloud_unlocks: Dictionary = Dictionary(_profile.get("unlocks", {}))
		var returned: int = 0
		for unlock_id in ["unlock.cloud_account", "unlock.starting_cloud"]:
			var owned: int = int(cloud_unlocks.get(unlock_id, 0))
			if owned > 0:
				returned += owned
				cloud_unlocks.erase(unlock_id)
		if returned > 0:
			_profile["unlocks"] = cloud_unlocks
			_profile["pending_picks"] = int(_profile.get("pending_picks", 0)) + returned
			_profile["retired_cloud_unlocks"] = true
	if from_version < 8:
		# Rooms stopped being progression: the campaign `locations` block is
		# gone (dropped on load). The records sheet is new; every game an older
		# profile completed was a victory, so that record is seeded from them.
		var bests: Dictionary = _records()
		bests["games_completed"] = maxi(int(bests.get("games_completed", 0)), int(_profile.get("victories", 0)))
		_profile["records"] = bests
	_save()


func _save() -> void:
	var file := FileAccess.open(profile_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_profile, "\t"))
	file.close()
