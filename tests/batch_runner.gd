class_name BatchRunner
extends RefCounted

## Plays whole runs headlessly under a fixed policy and reports how they ended.
##
## The point is not the win rate on its own — a run that limps to the end of the
## calendar used to count as a win, which hid the fact that nobody was reaching
## the endgame. What matters is the *shape* of the outcomes: how many ascended,
## how many collapsed, and how many never terminated at all.
##
## Every location has one contract and it is live from the first prompt, so the
## thing to read is how close the sample got: `avg_burn_ratio` is the share of
## the contract an average run finished. A sample that lands well under 1.0 means
## the contract is priced above what the chapter can build.

## A run that has not resolved in this many policy steps is stuck, not slow, and
## is reported as such rather than being quietly dropped from the sample.
const SAFETY_STEPS := 500

## Share of heat capacity the builder refuses to let the next burn land above.
## Venting costs a prompt and prompts are deadlines, so it vents only when the
## next burn would actually set the rig on fire.
const BUILDER_COOL_AT := 1.0

const PROFILE_RIG := [
	"upgrade.custom_desktop",
	"upgrade.gpu_rack",
	"upgrade.compute_cluster",
	"upgrade.garage_datacentre",
	"upgrade.compute_warehouse",
]

var invalid_number_count: int = 0
var guard_limit_count: int = 0

## Prints a line per run while the sweep is going. A sweep that stalls on one
## seed is otherwise indistinguishable from a sweep that is merely large.
var verbose: bool = false
var _active_metrics: Dictionary = {}


## `location` is the chapter of the campaign every run in the sweep is set in.
## A run can no longer buy its way to bigger premises, so the sweep has to be
## told where it is happening the same way the campaign would tell it.
func run(count: int = 1000, policy: String = "random", location: String = MetaProgress.DEFAULT_LOCATION) -> Dictionary:
	var wins: int = 0
	var total_rounds: int = 0
	var stuck: int = 0
	var outcomes: Dictionary = {}
	var peak_token_rates: Array[float] = []
	var peak_cash: Array[float] = []
	var perk_counts: Dictionary = {}
	var expired_runs: int = 0
	var lifetime_tokens: Array[float] = []
	var burn_ratios: Array[float] = []
	invalid_number_count = 0
	guard_limit_count = 0
	# Balance numbers describe a first run from nothing, so unlocks stay out.
	MetaProgress.enabled = false

	for i in range(count):
		var sim := _create_headless_sim()
		var seed_value: int = 1000 + i
		var started_at: int = Time.get_ticks_msec()
		sim.start_run(seed_value)
		sim.apply_run_location(sim.run_state, location)
		var safety: int = 0
		while sim.phase != sim.Phase.RUN_END and safety < SAFETY_STEPS:
			safety += 1
			_play_policy_step(sim, policy)
			total_rounds += 1
			if _has_invalid_numbers(sim.run_state):
				invalid_number_count += 1
				break
			var guard: ChainGuard = sim.effect_resolver.get_guard()
			if guard != null and guard.terminated:
				guard_limit_count += 1
		var outcome: String = str(sim.run_state.flags.get("outcome", ""))
		if sim.phase != sim.Phase.RUN_END:
			stuck += 1
			outcome = "stuck"
		elif outcome == "":
			outcome = "ascended" if sim.run_state.flags.get("victory", false) else "lost"
		outcomes[outcome] = int(outcomes.get(outcome, 0)) + 1
		if verbose:
			print("    seed %d [%s]: %s in %d steps, %d ms" % [
				seed_value, policy, outcome, safety, Time.get_ticks_msec() - started_at,
			])
		if sim.run_state.flags.get("victory", false):
			wins += 1
		if outcome == "contract_expired":
			expired_runs += 1
		# What the run actually burned against what its contract asked for, which
		# is the number `total_burn` has to be priced against.
		var burned: float = float(sim.run_state.statistics.get("lifetime_tokens", 0.0))
		lifetime_tokens.append(burned)
		var target: float = float(sim.ascension_boss_contract().get("total_burn", 0.0))
		if target > 0.0:
			burn_ratios.append(burned / target)
		peak_token_rates.append(float(sim.run_state.statistics.get("peak_token_rate", 0.0)))
		peak_cash.append(float(sim.run_state.statistics.get("peak_cash", 0.0)))
		for perk_id in sim.run_state.build.get("perks", []):
			perk_counts[perk_id] = int(perk_counts.get(perk_id, 0)) + 1
		sim.free()

	var runs: int = maxi(count, 1)
	return {
		"runs": count,
		"policy": policy,
		"location": location,
		"win_rate": float(wins) / float(runs),
		"ascended_rate": float(int(outcomes.get("ascended", 0))) / float(runs),
		"expired_rate": float(expired_runs) / float(runs),
		"stuck_count": stuck,
		"outcomes": outcomes,
		"avg_rounds": float(total_rounds) / float(runs),
		"avg_peak_token_rate": _average(peak_token_rates),
		"avg_lifetime_tokens": _average(lifetime_tokens),
		"avg_burn_ratio": _average(burn_ratios),
		"max_burn_ratio": _maximum(burn_ratios),
		"avg_peak_cash": _average(peak_cash),
		"invalid_number_count": invalid_number_count,
		"guard_limit_count": guard_limit_count,
		"perk_counts": perk_counts,
	}


## Plays the actual campaign continuation path rather than seven unrelated
## rooms. A victory carries the bought rig, cash, workflows, perks and modules
## into the next chapter exactly as the UI does. Permanent-power profiles are
## deterministic fixtures from pacing_targets.json, never the developer's save.
func run_campaign(
	count: int = 50,
	policy: String = "builder",
	profile_id: String = "fresh",
	difficulty: String = "normal",
	seed_start: int = 1000
) -> Dictionary:
	MetaProgress.enabled = false
	var summary: Dictionary = {
		"runs": count,
		"policy": policy,
		"profile": profile_id,
		"difficulty": difficulty,
		"chapters": {},
		"outcomes": {},
		"stuck_count": 0,
		"invalid_number_count": 0,
		"fires": 0,
		"acceptance_failures": [],
	}
	for run_index in range(count):
		var sim := _create_headless_sim()
		sim.start_run(seed_start + run_index, difficulty)
		_apply_profile(sim, profile_id)
		_active_metrics = _new_chapter_metrics()
		_record_hardware_round(sim)
		var safety: int = 0
		var finished: bool = false
		# A full campaign needs more room than one chapter, but a phase that has
		# not advanced in a thousand policy decisions is a bug, not a slow build.
		while safety < 400:
			safety += 1
			if _has_invalid_numbers(sim.run_state):
				summary["invalid_number_count"] = int(summary["invalid_number_count"]) + 1
				_finalize_campaign_chapter(summary, sim, "invalid")
				finished = true
				break
			if sim.phase == sim.Phase.RUN_END:
				var won: bool = bool(sim.run_state.flags.get("victory", false))
				var outcome: String = str(sim.run_state.flags.get("outcome", ""))
				if outcome == "":
					outcome = "ascended" if won else "lost"
				_finalize_campaign_chapter(summary, sim, outcome)
				if not won or sim.next_location_unlocked() == "":
					summary["outcomes"][outcome] = int(summary["outcomes"].get(outcome, 0)) + 1
					finished = true
					break
				if not sim.advance_to_next_chapter():
					summary["outcomes"]["advance_failed"] = int(
						summary["outcomes"].get("advance_failed", 0)
					) + 1
					finished = true
					break
				_install_profile_rig(sim, profile_id)
				sim.board_system().ensure_board(sim.run_state, ContentDatabase)
				sim._compute_system.recalculate(
					sim.run_state, sim.effect_resolver, sim._collect_subscriptions(), sim.rng
				)
				sim._job_system.refresh_contract_board(
					sim.run_state, sim.rng, ContentDatabase, sim.tuning
				)
				_active_metrics = _new_chapter_metrics()
				_record_hardware_round(sim)
				continue
			_play_policy_step(sim, policy)
			_record_hardware_round(sim)
		if not finished:
			if verbose:
				print("    campaign seed %d stuck in %s / phase %d after %d steps" % [
					seed_start + run_index,
					str(sim.run_state.build.get("dwelling", "")),
					int(sim.phase),
					safety,
				])
			summary["stuck_count"] = int(summary["stuck_count"]) + 1
			_finalize_campaign_chapter(summary, sim, "stuck")
			summary["outcomes"]["stuck"] = int(summary["outcomes"].get("stuck", 0)) + 1
		sim.free()
	_active_metrics = {}
	_finalize_campaign_averages(summary)
	_evaluate_campaign_acceptance(summary)
	return summary


func _profile(profile_id: String) -> Dictionary:
	return Dictionary(
		ContentDatabase.balance.get("pacing_targets", {}).get("profiles", {}).get(profile_id, {})
	)


func _apply_profile(sim: Node, profile_id: String) -> void:
	var profile: Dictionary = _profile(profile_id)
	var state: RunState = sim.run_state
	state.compute["efficiency_base"] = float(state.compute.get("efficiency_base", 1.0)) + float(
		profile.get("efficiency_bonus", 0.0)
	)
	state.compute["meta_cooling"] = float(state.compute.get("meta_cooling", 0.0)) + float(
		profile.get("cooling_bonus", 0.0)
	)
	state.business["legacy_token_multiplier"] = float(
		profile.get("old_silicon_multiplier", 1.0)
	)
	state.economy["cash"] = float(state.economy.get("cash", 0.0)) + float(
		profile.get("starting_cash_bonus", 0.0)
	)
	var board: Dictionary = Dictionary(state.build.get("board", {}))
	board["meta_slot_bonus"] = int(profile.get("extra_pipeline_slots", 0))
	state.build["board"] = board
	_install_profile_rig(sim, profile_id)
	sim.board_system().ensure_board(state, ContentDatabase)
	sim._compute_system.recalculate(state, sim.effect_resolver, sim._collect_subscriptions(), sim.rng)
	sim._job_system.refresh_contract_board(state, sim.rng, ContentDatabase, sim.tuning)


func _install_profile_rig(sim: Node, profile_id: String) -> void:
	var ranks: int = int(_profile(profile_id).get("starting_rig_ranks", 0))
	sim._compute_system.recalculate(
		sim.run_state, sim.effect_resolver, sim._collect_subscriptions(), sim.rng
	)
	for index in range(mini(ranks, PROFILE_RIG.size())):
		var upgrade: UpgradeDefinition = ContentDatabase.get_upgrade(PROFILE_RIG[index])
		if upgrade == null:
			continue
		if not UpgradeSystem.prerequisites_met(sim.run_state, upgrade, ContentDatabase):
			continue
		if UpgradeSystem.installed_key(upgrade) in Array(sim.run_state.build.get("hardware", [])):
			continue
		var curve: Dictionary = Dictionary(
			ContentDatabase.balance.get("hardware_curves", {}).get(upgrade.hardware_key, {})
		)
		var startup: Dictionary = sim.heat_outlook(
			float(curve.get("power_draw", 0.0)), UpgradeSystem.cooling_from(upgrade)
		)
		if float(startup.get("heat_per_prompt", 0.0)) >= float(
			sim.run_state.compute.get("heat_capacity", 100.0)
		):
			continue
		if sim._upgrade_system.install_carried(
			sim.run_state, upgrade.id, ContentDatabase, sim.effect_resolver
		):
			sim._compute_system.recalculate(
				sim.run_state, sim.effect_resolver, sim._collect_subscriptions(), sim.rng
			)


func _new_chapter_metrics() -> Dictionary:
	return {
		"burns": 0,
		"cooling_prompts": 0,
		"prompts": 0,
		"round_sessions": 0,
		"dangerous_forecasts": 0,
		"fires": 0,
		"peak_heat_ratio": 0.0,
		"job_burns": {},
		"matched_burn_samples": [],
		"hardware_acquisition_round": {},
	}


func _record_hardware_round(sim: Node) -> void:
	if _active_metrics.is_empty():
		return
	var rounds: Dictionary = _active_metrics["hardware_acquisition_round"]
	var current_round: int = int(sim.run_state.calendar.get("round", 1))
	for key in sim.run_state.build.get("hardware", []):
		var text_key: String = str(key)
		if not rounds.has(text_key):
			rounds[text_key] = current_round


func _finalize_campaign_chapter(summary: Dictionary, sim: Node, outcome: String) -> void:
	var location: String = str(sim.run_state.build.get("dwelling", "bedroom"))
	var chapters: Dictionary = summary["chapters"]
	var aggregate: Dictionary = Dictionary(chapters.get(location, {
		"attempts": 0, "wins": 0, "victory_rounds": [], "burns_per_job": [],
		"prompts": 0, "round_sessions": 0, "cooling_prompts": 0,
		"dangerous_forecasts": 0, "fires": 0, "peak_heat_ratio": 0.0,
		"peak_token_rates": [], "peak_cash": [], "ascension_burn_ratios": [],
		"ascension_qualities": [],
		"hardware_acquisition_rounds": {},
		"outcomes": {},
	}))
	aggregate["attempts"] = int(aggregate["attempts"]) + 1
	aggregate["outcomes"][outcome] = int(aggregate["outcomes"].get(outcome, 0)) + 1
	if bool(sim.run_state.flags.get("victory", false)):
		aggregate["wins"] = int(aggregate["wins"]) + 1
		aggregate["victory_rounds"].append(int(sim.run_state.calendar.get("round", 1)))
	aggregate["burns_per_job"].append_array(_active_metrics.get("matched_burn_samples", []))
	for key in ["prompts", "round_sessions", "cooling_prompts", "dangerous_forecasts", "fires"]:
		aggregate[key] = int(aggregate[key]) + int(_active_metrics.get(key, 0))
	aggregate["peak_heat_ratio"] = maxf(
		float(aggregate["peak_heat_ratio"]), float(_active_metrics.get("peak_heat_ratio", 0.0))
	)
	aggregate["peak_token_rates"].append(float(sim.run_state.statistics.get("peak_token_rate", 0.0)))
	aggregate["peak_cash"].append(float(sim.run_state.statistics.get("peak_cash", 0.0)))
	var progress: Dictionary = sim.ascension_progress()
	aggregate["ascension_burn_ratios"].append(float(progress.get("burn_ratio", 0.0)))
	aggregate["ascension_qualities"].append(float(progress.get("quality_average", 0.0)))
	var acquisition: Dictionary = _active_metrics.get("hardware_acquisition_round", {})
	for hardware_id in acquisition.keys():
		if not aggregate["hardware_acquisition_rounds"].has(hardware_id):
			aggregate["hardware_acquisition_rounds"][hardware_id] = []
		aggregate["hardware_acquisition_rounds"][hardware_id].append(int(acquisition[hardware_id]))
	chapters[location] = aggregate
	summary["fires"] = int(summary["fires"]) + int(_active_metrics.get("fires", 0))


func _finalize_campaign_averages(summary: Dictionary) -> void:
	for location in summary["chapters"].keys():
		var chapter: Dictionary = summary["chapters"][location]
		var samples: Array = chapter.get("burns_per_job", [])
		var one_burn: int = 0
		for sample in samples:
			if int(sample) <= 1:
				one_burn += 1
		chapter["win_rate"] = float(chapter.get("wins", 0)) / maxf(1.0, float(chapter.get("attempts", 0)))
		chapter["avg_victory_round"] = _average(chapter.get("victory_rounds", []))
		chapter["median_victory_round"] = _median(chapter.get("victory_rounds", []))
		chapter["avg_burns_per_completed_job"] = _average(samples)
		chapter["one_burn_job_rate"] = float(one_burn) / maxf(1.0, float(samples.size()))
		chapter["prompts_per_round"] = float(chapter.get("prompts", 0)) / maxf(
			1.0, float(chapter.get("round_sessions", 0))
		)
		chapter["cooling_share"] = float(chapter.get("cooling_prompts", 0)) / maxf(
			1.0, float(chapter.get("prompts", 0))
		)
		chapter["avg_peak_token_rate"] = _average(chapter.get("peak_token_rates", []))
		chapter["avg_peak_cash"] = _average(chapter.get("peak_cash", []))
		chapter["avg_ascension_burn_ratio"] = _average(
			chapter.get("ascension_burn_ratios", [])
		)
		chapter["avg_ascension_quality"] = _average(chapter.get("ascension_qualities", []))
		var acquisition_avg: Dictionary = {}
		for hardware_id in chapter["hardware_acquisition_rounds"].keys():
			acquisition_avg[hardware_id] = _average(chapter["hardware_acquisition_rounds"][hardware_id])
		chapter["avg_hardware_acquisition_round"] = acquisition_avg


## Turns the data-owned pacing contract into release-gate failures. Keeping the
## thresholds in pacing_targets.json lets design tune them without editing the
## runner, while this function remains the single interpretation of the data.
func _evaluate_campaign_acceptance(summary: Dictionary) -> void:
	var targets: Dictionary = ContentDatabase.balance.get("pacing_targets", {})
	var profile_id: String = str(summary.get("profile", "fresh"))
	var difficulty: String = str(summary.get("difficulty", "normal"))
	var difficulty_targets: Dictionary = Dictionary(targets.get(difficulty, {}))
	var chapter_band: Array = Array(
		difficulty_targets.get("chapter_rounds", {}).get(profile_id, [])
	)
	var one_burn_cap: float = float(
		difficulty_targets.get("one_burn_rate_cap", {}).get(profile_id, 1.0)
	)
	var minimum_campaign_runs: int = int(
		difficulty_targets.get("minimum_campaign_runs_for_pacing_gate", 1)
	)
	var minimum_job_samples: int = int(
		difficulty_targets.get("minimum_matched_jobs_for_rate_gate", 1)
	)
	var safety: Dictionary = Dictionary(targets.get("smoke", {}))
	var failures: Array = []
	if bool(safety.get("require_all_locations", false)):
		for required_location in ContentDatabase.balance.get("economy", {}).get("location_order", []):
			if not summary.get("chapters", {}).has(str(required_location)):
				failures.append("%s was not reached" % str(required_location))
	if bool(safety.get("require_all_locations_cleared", false)):
		for required_location in ContentDatabase.balance.get("economy", {}).get("location_order", []):
			var required_chapter: Dictionary = Dictionary(
				summary.get("chapters", {}).get(str(required_location), {})
			)
			if int(required_chapter.get("wins", 0)) < int(required_chapter.get("attempts", 0)):
				failures.append("%s was not cleared in every campaign" % str(required_location))
	if bool(safety.get("require_no_stuck_runs", false)) and int(summary.get("stuck_count", 0)) > 0:
		failures.append("campaign has stuck runs")
	if bool(safety.get("require_no_invalid_numbers", false)) and int(
		summary.get("invalid_number_count", 0)
	) > 0:
		failures.append("campaign has invalid numbers")
	if bool(safety.get("require_no_safe_policy_fires", false)) and int(summary.get("fires", 0)) > 0:
		failures.append("safe builder policy caused hardware fires")
	var minimum_round: int = int(safety.get("minimum_victory_round", 1))
	for location in summary.get("chapters", {}).keys():
		var chapter: Dictionary = summary["chapters"][location]
		if chapter.get("burns_per_job", []).size() >= minimum_job_samples and float(
			chapter.get("one_burn_job_rate", 0.0)
		) > one_burn_cap:
			failures.append("%s matched one-burn rate exceeds %.0f%%" % [
				str(location), one_burn_cap * 100.0,
			])
		for victory_round in chapter.get("victory_rounds", []):
			if int(victory_round) < minimum_round:
				failures.append("%s cleared before round %d" % [str(location), minimum_round])
		if chapter_band.size() >= 2 and int(chapter.get("attempts", 0)) >= minimum_campaign_runs:
			var median_round: float = float(chapter.get("median_victory_round", 0.0))
			if median_round <= 0.0:
				failures.append("%s was not cleared" % str(location))
			elif median_round < float(chapter_band[0]) or median_round > float(chapter_band[1]):
				failures.append("%s median victory round %.1f is outside %d-%d" % [
					str(location), median_round, int(chapter_band[0]), int(chapter_band[1]),
				])
	summary["acceptance_failures"] = failures
	summary["accepted"] = failures.is_empty()


## The outcome histogram as one line, for the runner's console output.
static func describe_outcomes(summary: Dictionary) -> String:
	var outcomes: Dictionary = Dictionary(summary.get("outcomes", {}))
	var keys: Array = outcomes.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key in keys:
		parts.append("%s=%d" % [str(key), int(outcomes[key])])
	return ", ".join(parts) if parts.size() > 0 else "none"


func export_csv(path: String, summary: Dictionary) -> void:
	var lines: PackedStringArray = ["metric,value"]
	for key in summary.keys():
		if summary[key] is Dictionary:
			continue
		lines.append("%s,%s" % [key, str(summary[key])])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines))
		file.close()


func _create_headless_sim() -> Node:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	return sim


func _play_policy_step(sim: Node, policy: String) -> void:
	match sim.phase:
		sim.Phase.ROUND_PREP:
			if policy == "builder":
				_builder_shop(sim)
			if sim.run_state.has_queued_jobs():
				_work_round(sim, policy)
				return
			var offers: Array = sim.run_state.business.get("job_offers", [])
			if offers.is_empty():
				# A round with nothing to work still owes its rent, so closing it
				# out is the only move rather than a free skip.
				sim._end_round()
				return
			if policy == "builder":
				_builder_take_contracts(sim, offers)
				if sim.run_state.has_queued_jobs():
					_work_round(sim, policy)
				else:
					# A round with nothing worth taking still owes its rent.
					sim._end_round()
				return
			var pick: Dictionary = offers[0]
			if policy == "greedy":
				for offer in offers:
					if float(offer.get("reward", 0.0)) > float(pick.get("reward", 0.0)):
						pick = offer
			sim.accept_job(str(pick.get("id", "")))
			_work_round(sim, policy)
		sim.Phase.ANGEL_ROUND:
			if sim.pending_choices.size() > 0:
				var choice: Dictionary = sim.pending_choices[0]
				# A rejected offer must not wedge the policy on the angel screen.
				if not sim.accept_offer(str(choice.get("type", "")), str(choice.get("id", ""))):
					sim.decline_offers()
			else:
				sim.decline_offers()
		sim.Phase.ROUND_END:
			sim._end_round()
		_:
			pass


## `start_work_sync` auto-burns to the end of the session, which never presses
## COOL. The builder works the round by hand so venting is part of the sample:
## a rig whose cooling has fallen behind shows up here as a run that cooks.
func _work_round(sim: Node, policy: String) -> void:
	if policy != "builder":
		sim.start_work_sync()
		return
	if not sim.can_start_work():
		return
	sim.start_work()
	if not _active_metrics.is_empty():
		_active_metrics["round_sessions"] = int(_active_metrics.get("round_sessions", 0)) + 1
	# Nobody is here to lay out the pipeline, and an empty board cannot burn.
	sim.auto_arrange_board()
	var safety: int = 0
	var consecutive_cools: int = 0
	while sim.phase == sim.Phase.IN_ROUND and safety < SAFETY_STEPS:
		safety += 1
		var capacity: float = maxf(1.0, float(sim.run_state.compute.get("heat_capacity", 100.0)))
		var heat: float = float(sim.run_state.compute.get("heat", 0.0))
		# Burning blind is how a rig catches fire: the next burn's own heat is
		# forecastable, so vent first when it would take the bar over the top.
		var preview: Dictionary = sim.preview_next_burn()
		var projected: float = float(preview.get("heat_after", heat))
		if not _active_metrics.is_empty() and (
			bool(preview.get("crosses_fire", false)) or projected >= capacity
		):
			_active_metrics["dangerous_forecasts"] = int(
				_active_metrics.get("dangerous_forecasts", 0)
			) + 1
		var too_hot: bool = projected >= capacity * BUILDER_COOL_AT
		var acted: bool = false
		if too_hot and consecutive_cools < 8 and float(sim.preview_cool().get("total_heat", 0.0)) < 0.0:
			acted = bool(sim.cool_hardware().get("ok", false))
		if acted:
			_record_prompt_metrics(sim, true)
			consecutive_cools += 1
			continue
		consecutive_cools = 0
		var job_meta: Dictionary = {}
		var current_matched_tier: int = maxi(
			JobSystem.location_tier(sim.run_state, ContentDatabase),
			JobSystem.rig_work_tier(sim.run_state, ContentDatabase)
		)
		for job in sim.run_state.business.get("active_jobs", []):
			if job is Dictionary:
				job_meta[str(job.get("id", ""))] = {
					"rig_matched": int(job.get("tier", -1)) == current_matched_tier,
					"windfall": bool(job.get("windfall", false)),
				}
		var burn_result: Dictionary = sim.burn_batch()
		if not bool(burn_result.get("ok", false)):
			break
		_record_burn_metrics(sim, burn_result, job_meta)
	if sim.phase == sim.Phase.IN_ROUND:
		sim._end_session("stalled")
	if not _active_metrics.is_empty() and str(sim.run_state.flags.get("loss_reason", "")) == "Hardware fire":
		_active_metrics["fires"] = int(_active_metrics.get("fires", 0)) + 1


func _record_prompt_metrics(sim: Node, cooling: bool) -> void:
	if _active_metrics.is_empty():
		return
	_active_metrics["prompts"] = int(_active_metrics.get("prompts", 0)) + 1
	if cooling:
		_active_metrics["cooling_prompts"] = int(_active_metrics.get("cooling_prompts", 0)) + 1
	var capacity: float = maxf(1.0, float(sim.run_state.compute.get("heat_capacity", 100.0)))
	_active_metrics["peak_heat_ratio"] = maxf(
		float(_active_metrics.get("peak_heat_ratio", 0.0)),
		float(sim.run_state.compute.get("heat", 0.0)) / capacity
	)


func _record_burn_metrics(sim: Node, result: Dictionary, job_meta: Dictionary) -> void:
	if _active_metrics.is_empty():
		return
	_record_prompt_metrics(sim, false)
	_active_metrics["burns"] = int(_active_metrics.get("burns", 0)) + 1
	var counts: Dictionary = _active_metrics["job_burns"]
	for lane in result.get("burn", {}).get("lanes", []):
		if not lane is Dictionary:
			continue
		var job_id: String = str(lane.get("job_id", ""))
		counts[job_id] = int(counts.get(job_id, 0)) + 1
		if float(lane.get("tokens_remaining", 1.0)) > 0.0:
			continue
		var meta: Dictionary = Dictionary(job_meta.get(job_id, {}))
		if bool(meta.get("rig_matched", false)) and not bool(meta.get("windfall", false)):
			_active_metrics["matched_burn_samples"].append(int(counts[job_id]))


## Reward alone is the wrong thing to chase: the fattest contract on the board is
## usually the one this rig cannot deliver, and a missed deadline costs
## reputation rather than just the fee. The builder takes the best-paying work it
## can finish, then keeps loading the slate while throughput still covers it.
## Taking nothing is better than taking work that will fail.
func _builder_take_contracts(sim: Node, offers: Array) -> void:
	var safety: int = 0
	while safety < 8:
		safety += 1
		var pick: String = ""
		var best_reward: float = -1.0
		var best_priority: int = -1
		var fallback: String = ""
		var lightest: float = INF
		for offer in offers:
			var id: String = str(offer.get("id", ""))
			if not sim.can_accept_offer(id):
				continue
			var ratio: float = float(sim.queue_load_info(offer).get("ratio", 0.0))
			if ratio < lightest:
				lightest = ratio
				fallback = id
			if ratio > 1.0:
				continue
			var fit: String = str(offer.get("fit", "temptation"))
			var priority: int = 2 if fit == "bread_and_butter" else (1 if fit == "stretch" else 0)
			if bool(offer.get("rig_matched", false)):
				priority += 1
			if priority < best_priority:
				continue
			if priority == best_priority and float(offer.get("reward", 0.0)) <= best_reward:
				continue
			pick = id
			best_priority = priority
			best_reward = float(offer.get("reward", 0.0))
		# An empty round earns nothing and still pays rent, so when everything
		# on the board is a stretch, take the least of them rather than none.
		if pick == "" and not sim.run_state.has_queued_jobs():
			pick = fallback
		if pick == "" or not sim.accept_job(pick):
			return
		offers = sim.run_state.business.get("job_offers", [])


## Buys the way a player does: cooling before the machine that needs it, space
## before the machine that will not fit, and never everything at once.
func _builder_shop(sim: Node) -> void:
	if not sim.market_open():
		return
	# Two rounds of bills stay in the bank; the rest is for growth. Holding a
	# fixed share back instead never accumulates enough for the next rung, and
	# spending down to one round's bills bankrupts the run on the standing costs
	# the purchase itself adds.
	var reserve: float = float(sim.cost_forecast().get("fixed_due", 0.0)) * 2.0
	var budget: float = maxf(0.0, float(sim.run_state.economy.get("cash", 0.0)) - reserve) * 0.5
	var safety: int = 0
	while safety < 40:
		safety += 1
		var pick: String = _builder_next_purchase(sim, budget)
		if pick == "":
			return
		var cost: float = _cost_of(sim, pick)
		if not sim.buy_upgrade(pick):
			return
		budget -= cost


## The next thing worth buying, in the order the game expects: close a live
## cooling shortfall, then take the biggest machine the money reaches — buying
## the cooling it will need first if the shop says it would cook.
func _builder_next_purchase(sim: Node, budget: float) -> String:
	if not bool(sim.heat_outlook().get("sustainable", true)):
		return _affordable(sim, budget, ["cooling"], true)
	# Components are the cheapest throughput in the game and take no floor
	# space: maxing what the run already owns is how the early game gets off the
	# laptop at all, long before it can afford a machine or a bigger room.
	var component: String = _affordable(sim, budget, ["component"], false)
	if component != "" and sim.upgrade_heat_warning(component) == "":
		return component
	var machine: String = _affordable(sim, budget, ["hardware"], false)
	if machine != "" and sim.upgrade_heat_warning(machine) != "":
		# The machine is affordable but the room cannot cool it, which is what
		# the Cooling shelf is for — as long as both still fit in the budget.
		# Buying cooling for a machine the run cannot also afford is how a
		# policy spends every round's profit and never grows.
		var cooler: String = _affordable(sim, budget - _cost_of(sim, machine), ["cooling"], true)
		return cooler
	return machine


func _cost_of(sim: Node, upgrade_id: String) -> float:
	return UpgradeSystem.purchase_cost(
		ContentDatabase.get_upgrade(upgrade_id), UpgradeSystem.upgrade_level(sim.run_state, upgrade_id)
	)


## The most expensive thing on a shelf the run can afford. `cooling_only`
## selects between the Cooling shelf and everything else, since an upgrade can
## carry both tags.
func _affordable(sim: Node, budget: float, tags: Array, cooling_only: bool) -> String:
	var best: String = ""
	var best_cost: float = -1.0
	for upgrade in ContentDatabase.upgrades:
		var tagged: bool = false
		for tag in tags:
			if str(tag) in Array(upgrade.tags):
				tagged = true
		if not tagged:
			continue
		if cooling_only != ("cooling" in Array(upgrade.tags)):
			continue
		if not sim.can_buy_upgrade(upgrade.id):
			continue
		var cost: float = UpgradeSystem.purchase_cost(
			upgrade, UpgradeSystem.upgrade_level(sim.run_state, upgrade.id)
		)
		if cost > budget or cost <= best_cost:
			continue
		# The sticker price is not the commitment: every rung also adds to the
		# standing bill for the rest of the run, which is what actually ends a
		# run that over-bought.
		if upgrade.recurring_cost_delta > _recurring_headroom(sim):
			continue
		best = upgrade.id
		best_cost = cost
	return best


func _recurring_headroom(sim: Node) -> float:
	return maxf(100.0, float(sim.run_state.economy.get("income", 0.0)) * 0.25)


func _has_invalid_numbers(state: RunState) -> bool:
	for section in [state.economy, state.compute, state.business, state.statistics]:
		for value in section.values():
			if value is float and (is_nan(value) or is_inf(value)):
				return true
	return false


func _average(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for v in values:
		total += float(v)
	return total / float(values.size())


func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var ordered: Array = values.duplicate()
	ordered.sort()
	var middle: int = ordered.size() / 2
	if ordered.size() % 2 == 1:
		return float(ordered[middle])
	return (float(ordered[middle - 1]) + float(ordered[middle])) * 0.5


## Headless balance guidance: first reroll should land around 10–25% of a normal
## contract reward at the bedroom tier.
static func angel_reroll_cost_ratio(sim: Node) -> float:
	var contract_reward: float = maxf(1.0, float(sim.run_state.economy.get("round_rent", 400.0)) * 4.0)
	return sim.angel_reroll_cost() / contract_reward


## Draw `tables` angel tables and report how many cards matched `tag`.
static func draft_tag_hit_rate(
	seed_value: int,
	tag: String,
	tables: int = 40,
	owned_tags: Array = []
) -> float:
	var hits: int = 0
	var total: int = 0
	for i in range(tables):
		var rng := DeterministicRng.new(seed_value + i)
		var state := RunState.new()
		state.reset()
		for offer in ContentDatabase.draw_angel_offers(rng, state, 3, owned_tags, 0.0):
			total += 1
			for offer_tag in Array(offer.get("tags", [])):
				if str(offer_tag) == tag:
					hits += 1
					break
	return float(hits) / maxf(1.0, float(total))


## The best run in the sample. A contract nobody averages but the best run
## clears is priced as a stretch; one nothing comes near is priced wrong.
func _maximum(values: Array) -> float:
	var best: float = 0.0
	for v in values:
		best = maxf(best, float(v))
	return best
