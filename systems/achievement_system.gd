class_name AchievementSystem
extends RefCounted

## Permanent awards, and the modules some of them hand over.
##
## An achievement is a condition read against a flat snapshot of the run and the
## profile. Two moments are checked: `tick`, after every work session and round
## end, for the things you have to *be* doing (heat pinned at a hundred percent,
## a board full of modules); and `run_end`, for the things only a finished run
## can prove (how it ended, how long it lasted, what it never shipped).
##
## Earning one is the point: a reward of `unlock_module` puts a module into the
## angel draft pool for every run from then on, so the pool a veteran drafts
## from is deeper than the one a first run sees.

const TRIGGER_TICK := "tick"
const TRIGGER_RUN_END := "run_end"

## Deltas a finished run contributes to the cumulative counters in the profile.
static func lifetime_deltas(run_state: RunState, victory: bool) -> Dictionary:
	var stats: Dictionary = run_state.statistics
	return {
		"runs": 1,
		"losses": 0 if victory else 1,
		"tokens_burned": float(stats.get("lifetime_tokens", 0.0)),
		"completed_jobs": int(stats.get("completed_jobs", 0)),
		"failed_jobs": int(stats.get("failed_jobs", 0)),
		"hidden_bugs_shipped": int(stats.get("hidden_bugs_shipped", 0)),
		"modules_drafted": int(stats.get("modules_drafted", 0)),
	}


## Checks the mid-run awards. Returns the ids earned by this call, which is
## empty on almost every call and is the normal case.
func evaluate_tick(run_state: RunState, content_db: Node) -> Array[String]:
	return _evaluate(TRIGGER_TICK, _context(run_state, {}), content_db)


## Checks the end-of-run awards. `score` is the debrief scoreboard, which
## already knows the things the raw statistics do not (infrastructure tier, how
## the run ended, how many rounds it lasted).
func evaluate_run_end(run_state: RunState, score: Dictionary, content_db: Node) -> Array[String]:
	return _evaluate(TRIGGER_RUN_END, _context(run_state, score), content_db)


func _evaluate(trigger: String, context: Dictionary, content_db: Node) -> Array[String]:
	var earned: Array[String] = []
	for achievement in content_db.achievements:
		var id: String = str(achievement.get("id", ""))
		if id == "" or MetaProgress.has_achievement(id):
			continue
		var condition: Dictionary = Dictionary(achievement.get("condition", {}))
		if str(condition.get("trigger", TRIGGER_RUN_END)) != trigger:
			continue
		if not _matches(Array(condition.get("checks", [])), context):
			continue
		if not MetaProgress.grant_achievement(id):
			continue
		earned.append(id)
		# So an award for collecting awards can be earned by the one that
		# completes the set rather than by the run after it.
		context["meta.achievements"] = MetaProgress.achievement_count()
		EventBus.emit_event(EventBus.EVENT_ACHIEVEMENT_UNLOCKED, {"achievement_id": id})
	return earned


## Every check has to pass. An unknown stat never matches, so a typo in content
## makes the award unearnable rather than instantly earned.
func _matches(checks: Array, context: Dictionary) -> bool:
	for check in checks:
		if not check is Dictionary:
			return false
		var key: String = str(check.get("stat", ""))
		if not context.has(key):
			return false
		if not _compare(context[key], str(check.get("op", "==")), check.get("value")):
			return false
	return not checks.is_empty()


func _compare(actual: Variant, op: String, expected: Variant) -> bool:
	if actual is String or expected is String:
		match op:
			"==":
				return str(actual) == str(expected)
			"!=":
				return str(actual) != str(expected)
			_:
				return false
	var left: float = float(actual)
	var right: float = float(expected)
	match op:
		"==":
			return is_equal_approx(left, right)
		"!=":
			return not is_equal_approx(left, right)
		"<":
			return left < right
		"<=":
			return left <= right
		">":
			return left > right
		">=":
			return left >= right
		_:
			return false


## One flat dictionary of everything an achievement is allowed to ask about.
## Flat rather than nested so a content author writes `"stat": "run.peak_cash"`
## and nothing has to walk a path at evaluation time.
func _context(run_state: RunState, score: Dictionary) -> Dictionary:
	var stats: Dictionary = run_state.statistics
	var heat_capacity: float = maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))
	var board: Dictionary = run_state.build.get("board", {})
	var filled_slots: int = 0
	for slot in Array(board.get("slots", [])):
		if str(slot) != "":
			filled_slots += 1
	var context: Dictionary = {
		"run.round": int(run_state.calendar.get("round", 1)),
		"run.cash": float(run_state.economy.get("cash", 0.0)),
		"run.debt": float(run_state.economy.get("debt", 0.0)),
		"run.tokens_burned": float(stats.get("lifetime_tokens", 0.0)),
		"run.completed_jobs": int(stats.get("completed_jobs", 0)),
		"run.failed_jobs": int(stats.get("failed_jobs", 0)),
		"run.hidden_bugs_shipped": int(stats.get("hidden_bugs_shipped", 0)),
		"run.peak_cash": float(stats.get("peak_cash", 0.0)),
		"run.peak_debt": float(stats.get("peak_debt", 0.0)),
		"run.peak_token_rate": float(stats.get("peak_token_rate", 0.0)),
		"run.peak_prompt_tokens": float(stats.get("peak_prompt_tokens", 0.0)),
		"run.endless_rounds": int(stats.get("endless_rounds", 0)),
		"run.heat_ratio": float(run_state.compute.get("heat", 0.0)) / heat_capacity,
		"run.max_heat_ratio": float(stats.get("max_heat_ratio", 0.0)),
		"run.jobs_accepted": int(stats.get("jobs_accepted", 0)),
		"run.angel_offers_taken": int(stats.get("angel_offers_taken", 0)),
		"run.angel_offers_declined": int(stats.get("angel_offers_declined", 0)),
		"run.hardware_sold": int(stats.get("hardware_sold", 0)),
		"run.modules_drafted": int(stats.get("modules_drafted", 0)),
		"run.modules_owned": Array(run_state.build.get("operations", [])).size(),
		"run.perks_owned": Array(run_state.build.get("perks", [])).size(),
		"run.hardware_owned": Array(run_state.build.get("hardware", [])).size(),
		"run.board_slots": int(board.get("slot_count", 0)),
		"run.board_filled": filled_slots,
		"run.dwelling": str(run_state.build.get("dwelling", "bedroom")),
		"run.outcome": str(run_state.flags.get("outcome", "")),
		"run.ascension_tier": int(run_state.flags.get("ascension_tier", 0)),
		"run.rounds_survived": int(score.get("rounds_survived", run_state.calendar.get("round", 1))),
		"run.infrastructure_tier": int(score.get("infrastructure_tier", 0)),
		"meta.achievements": MetaProgress.achievement_count(),
		"meta.victories": MetaProgress.victories(),
		"meta.retirements": MetaProgress.retirements(),
	}
	for key in MetaProgress.LIFETIME_KEYS:
		context["lifetime.%s" % key] = MetaProgress.lifetime_stat(str(key))
	return context
