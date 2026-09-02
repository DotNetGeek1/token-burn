class_name RunLifecycle
extends RefCounted

## Start/end of a run, round boundaries, angel draft, victory/chapters, and
## save/load. Owned by Simulation as `_life`. Public `phase` / `pending_choices`
## stay on the facade (too many callers).
##
## `sim` is the owning Simulation node, taken as a plain `Node` to avoid a
## circular class reference. Cross-concern calls (end session) go back through
## Simulation routing methods, not to WorkSession directly.

var round_end_pending: bool = false
var settling_victory: bool = false
var settling_depth: bool = false


func reset() -> void:
	round_end_pending = false
	settling_victory = false
	settling_depth = false


func ensure_job_board(sim: Node) -> void:
	repair_after_load(sim)


func repair_after_load(sim: Node) -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	sim._work_running = false
	var saved_policy: String = str(sim.run_state.flags.get("work_policy", WorkSession.POLICY_MANUAL))
	if saved_policy == WorkSession.POLICY_MANUAL or saved_policy == WorkSession.POLICY_AUTO or saved_policy == WorkSession.POLICY_YOLO:
		sim._work.work_policy = saved_policy
	sim.debug_invalidate_subscriptions()
	sim.board_system().ensure_board(sim.run_state, ContentDatabase)
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)

	match sim.phase:
		sim.Phase.IN_ROUND:
			if sim.run_state.business.get("active_jobs", []).is_empty():
				sim.phase = sim.Phase.ROUND_PREP
			else:
				# The running flag is transient, but the round it belonged to is
				# in the save. Without resuming the session the loaded board
				# prints no BURN line and DELIVER silently refuses.
				sim._work_running = sim.job_system().begin_work_session(sim.run_state, ContentDatabase)
		sim.Phase.ROUND_END:
			sim.phase = sim.Phase.ROUND_PREP
		sim.Phase.ANGEL_ROUND:
			if sim.pending_choices.is_empty():
				present_angel_offers(sim)
			if sim.pending_choices.is_empty():
				sim.phase = sim.Phase.ROUND_PREP

	_ensure_job_offers(sim)


func _ensure_job_offers(sim: Node) -> void:
	if sim.phase != sim.Phase.ROUND_PREP:
		return
	if sim.run_state.has_active_job() or sim._work_running:
		return
	# The board is stable for a given round: UI refreshes must not reroll it
	# (that churned the offers and let the simulation rng advance on taps).
	var stamp: String = _board_stamp(sim)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	if not offers.is_empty() and str(sim.run_state.business.get("job_board_stamp", "")) == stamp:
		return
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	sim.job_system().refresh_contract_board(
		sim.run_state, sim.rng.derive("job_board.%s" % stamp), ContentDatabase, sim.tuning
	)
	sim.run_state.business["job_board_stamp"] = stamp


## Stable per work session rather than per prompt, which would otherwise reroll
## the board mid-round.
func _board_stamp(sim: Node) -> String:
	return "%d.%d" % [
		int(sim.run_state.calendar.get("round", 1)),
		int(sim.run_state.business.get("job_board_seq", 0)),
	]


func ensure_job_offers(sim: Node) -> void:
	_ensure_job_offers(sim)


func reset_run(sim: Node, p_seed: int = 0, difficulty_override: String = "") -> void:
	sim.run_seed = p_seed if p_seed != 0 else int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	sim.rng.set_seed(sim.run_seed)
	var difficulty_id: String = difficulty_override if difficulty_override != "" else MetaProgress.difficulty()
	var difficulty_profiles: Dictionary = ContentDatabase.balance.get("difficulty_profiles", {})
	var profile: Dictionary = difficulty_profiles.get(difficulty_id, difficulty_profiles.get("normal", {}))
	sim.run_state.reset(profile)
	# Contract scaling reads this back rather than the profile dictionary
	# directly, so the difficulty a run started on cannot drift once it is
	# under way — and so an offer scaled mid-run still asks the questions the
	# player actually agreed to.
	sim.run_state.flags["difficulty"] = difficulty_id
	sim.effect_resolver.clear_trace()
	sim.effect_resolver.clear_guard()
	sim.phase = sim.Phase.IDLE
	sim.round_log.clear()
	sim.pending_choices.clear()
	sim.reset_session_ephemerals()
	round_end_pending = false
	settling_victory = false
	settling_depth = false
	sim.last_round_statement = {}
	sim.debug_invalidate_subscriptions()
	# Where the run happens is decided before it starts and never moves again,
	# so rent and floor space are settled before anything is bought.
	apply_run_location(sim, sim.run_state, MetaProgress.selected_location())
	# Permanent unlocks land before the board is sized, so an unlocked slot is
	# there to be filled rather than turning up a round late.
	MetaProgress.apply_to_run(sim.run_state)
	_install_permanent_rig(sim)
	sim.board_system().ensure_board(sim.run_state, ContentDatabase)
	# The location's contract is the run's win condition, not something taken on
	# part-way through, so it is live before the first prompt is spent.
	sim.ascension_system().activate(sim.run_state, ContentDatabase)
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)


## Settles the run into its location. A location is a chapter, not a purchase:
## its rent, floor space and environmental cooling replace the defaults once,
## at the start, rather than being added to whatever was already there.
## `grant_starter_rig` is only turned off by tests that are measuring the room
## itself — its cooling, its floor space, its shelves — where the machine the
## room comes with would be counted as part of the answer.
func apply_run_location(
	sim: Node, state: RunState, location_id: String, grant_starter_rig: bool = true
) -> void:
	var dwelling_costs: Dictionary = ContentDatabase.balance.get("dwelling_costs", {})
	var location: String = location_id
	if not dwelling_costs.has(location):
		location = MetaProgress.DEFAULT_LOCATION
	state.build["dwelling"] = location
	if not dwelling_costs.has(location):
		return
	var stats: Dictionary = dwelling_costs[location]
	var rent_multiplier: float = float(state.economy.get("rent_multiplier", 1.0))
	state.economy["round_rent"] = float(
		stats.get("rent", state.economy.get("round_rent", 0.0))
	) * rent_multiplier
	# The stake the investor puts in when he buys the room. A chapter whose rent
	# is three times the last one's cannot be started on the last one's float.
	if stats.has("starting_cash"):
		state.economy["cash"] = float(stats["starting_cash"]) * float(
			state.economy.get("cash_multiplier", 1.0)
		)
	# A bigger room takes longer to cook. Heat is measured against this rather
	# than a fixed hundred, so moving up buys headroom as well as floor space.
	state.compute["heat_capacity"] = float(
		stats.get("heat_capacity", state.compute.get("heat_capacity", 100.0))
	)
	if grant_starter_rig:
		_grant_location_starter_rig(sim, state, stats)
	state.compute["cooling"] = ComputeSystem.derive_cooling(state)
	# The contract belongs to the location, so moving the run moves the contract
	# with it. Nothing else can set it: a run measured against the chapter it is
	# no longer in has no way to be won.
	sim.ascension_system().activate(state, ContentDatabase)


## The machine the room comes with. Contracts are sized against the rig a
## location expects rather than against whatever the player happens to own, so a
## run that starts in the warehouse on a second-hand laptop would be handed work
## a thousand times beyond it.
func _grant_location_starter_rig(sim: Node, state: RunState, stats: Dictionary) -> void:
	for upgrade_id in Array(stats.get("starting_hardware", [])):
		var upgrade: UpgradeDefinition = ContentDatabase.get_upgrade(str(upgrade_id))
		if upgrade == null:
			continue
		if UpgradeSystem.installed_count(state, UpgradeSystem.installed_key(upgrade)) > 0:
			continue
		sim.upgrade_system().install_carried(state, str(upgrade_id), ContentDatabase, sim.effect_resolver)


## Racks the machines earned through the permanent starting-rig unlock ladder.
## A fresh run is otherwise a fresh game from the start — nothing a previous run
## bought arrives — so this is the one place hardware crosses runs, and only
## because a pick was spent on it after beating the whole campaign.
##
## Free of charge but not of floor space: a small room racks what fits, and the
## call from `advance_to_next_chapter` racks the rest once a bigger room opens.
## That second call is why a rung already standing is skipped rather than
## installed again.
func _install_permanent_rig(sim: Node) -> void:
	var installed: int = 0
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	for upgrade_id in MetaProgress.starting_rig():
		var upgrade: UpgradeDefinition = ContentDatabase.get_upgrade(str(upgrade_id))
		if upgrade == null:
			continue
		# Permanent ownership does not make an industrial campus fit in a
		# garage. The rung waits until the campaign reaches the premises it was
		# authored for, just as a newly purchased copy would.
		if not UpgradeSystem.prerequisites_met(sim.run_state, upgrade, ContentDatabase):
			continue
		if UpgradeSystem.installed_key(upgrade) in Array(sim.run_state.build.get("hardware", [])):
			continue
		var curve: Dictionary = Dictionary(
			ContentDatabase.balance.get("hardware_curves", {}).get(upgrade.hardware_key, {})
		)
		var startup: Dictionary = sim.heat_outlook(
			float(curve.get("power_draw", 0.0)),
			UpgradeSystem.cooling_from(upgrade),
			int(curve.get("work_tier", 0))
		)
		# A permanent unlock is never allowed to turn a cold chapter start into
		# an already-cooking rig. Ambient ticks are a fraction of the bar, so
		# skip on sustainability rather than on one prompt overflowing capacity.
		if not bool(startup.get("sustainable", true)):
			continue
		if sim.upgrade_system().install_carried(
			sim.run_state, str(upgrade_id), ContentDatabase, sim.effect_resolver
		):
			installed += 1
			sim.compute_system().recalculate(
				sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
			)
	if installed > 0:
		sim.round_log.append("Your permanent rig is already racked: %d machine(s)." % installed)


func start_run(sim: Node, p_seed: int = 0, difficulty_override: String = "") -> void:
	reset_run(sim, p_seed, difficulty_override)
	sim.phase = sim.Phase.ROUND_PREP
	EventBus.emit_event(EventBus.EVENT_RUN_STARTED)
	_begin_round(sim)


## Opens a fresh round: a clean prompt counter, a new contract board, and the
## Market open. Nothing carries over from the last round except what the player
## owns, because a round only ends once its contracts have all resolved.
func _begin_round(sim: Node) -> void:
	EventBus.emit_event(EventBus.EVENT_ROUND_STARTED)
	sim.run_state.calendar["prompt"] = 1
	sim.run_state.business["job_board_seq"] = 0
	sim.run_state.economy["costs_this_round"] = 0.0
	sim.effect_resolver.begin_action("round.started")
	var mod_ctx := ModifierContext.new("round.started", sim.run_state)
	mod_ctx.rng = sim.rng.derive("round.started")
	sim.effect_resolver.dispatch("round.started", mod_ctx, sim.debug_collect_subscriptions())
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	sim.job_system().generate_offers(sim.run_state, sim.rng.derive("job_offers"), ContentDatabase, sim.tuning)
	sim.run_state.business["job_board_stamp"] = _board_stamp(sim)
	sim.phase = sim.Phase.ROUND_PREP


func accept_job(sim: Node, job_id: String) -> bool:
	if sim.phase != sim.Phase.ROUND_PREP or sim._work_running:
		return false
	if not can_accept_offer(sim, job_id):
		return false
	if not sim.job_system().accept_job(sim.run_state, job_id):
		return false
	sim.run_state.statistics["jobs_accepted"] = int(sim.run_state.statistics.get("jobs_accepted", 0)) + 1
	EventBus.emit_event(EventBus.EVENT_JOB_ACCEPTED, {"job_id": job_id})
	sim._autosave()
	return true


## Offers may load the queue up to (or slightly over) throughput capacity,
## but not so far past it that the deadline is hopeless.
func can_accept_offer(sim: Node, job_id: String) -> bool:
	if sim.phase != sim.Phase.ROUND_PREP or sim._work_running:
		return false
	var offer: Dictionary = sim.job_system().find_offer(sim.run_state, job_id)
	if offer.is_empty():
		return false
	if sim.run_state.business.get("job_queue", []).is_empty():
		return true
	var info: Dictionary = sim.queue_load_info(offer)
	return float(info.get("ratio", 0.0)) <= sim.queue_capacity_cap()


## The location's boss has cleared: the game is beaten. The run is not thrown away
## with it. The round it happened in is settled properly — the work pays out, the
## bills land, the angels call if the rent cleared — and the phase that would have
## come next is remembered, so continuing into endless mode resumes from a clean
## round boundary instead of the middle of a burn.
func reach_victory(sim: Node, contract: Dictionary) -> void:
	sim.ascension_system().record_final(sim.run_state, contract)
	sim.run_state.flags["victory"] = true
	sim.run_state.flags["outcome"] = "ascended"
	sim.run_state.flags["ascension_tier"] = int(contract.get("tier", 1))
	sim.round_log.append("%s is complete. You have ascended." % str(contract.get("name", "The contract")))
	MetaProgress.record_best_score(RunScore.compute(sim.run_state, ContentDatabase))
	MetaProgress.record_ascension(str(contract.get("id", "")))
	_complete_run_location(sim)
	# Permanence is the reward for finishing the whole campaign. A chapter goal
	# cleared on the way up is a level-up inside the run — it banks no picks,
	# advances no age and hands over no rule unlocks; only the summit pays.
	if _run_is_final_chapter(sim):
		MetaProgress.bank_victory(
			maxi(1, int(contract.get("picks", 1))),
			str(sim.run_state.flags.get("difficulty", "normal"))
		)
		if bool(contract.get("unlocks_age", false)):
			MetaProgress.advance_age(Ages.max_age_index())
		var ending_unlock: String = str(contract.get("ending_unlock", ""))
		if ending_unlock != "":
			MetaProgress.grant_ending_unlock(ending_unlock)
	_bank_run_legacy(sim, true)
	_pay_ascension_bonus(sim, contract)
	settling_victory = true
	sim._end_session("ascended")
	settling_victory = false
	# Settling normally leaves the round closed out into either a draft or the next
	# round's prep, but a loss check swallowed mid-settle can leave it in neither.
	# The phase to resume on is therefore taken from what is actually on the table
	# rather than from wherever the settle happened to stop.
	sim.run_state.flags["post_victory_phase"] = sim._phase_name(
		sim.Phase.ANGEL_ROUND if not sim.pending_choices.is_empty() else sim.Phase.ROUND_PREP
	)
	sim.phase = sim.Phase.RUN_END
	EventBus.emit_event(EventBus.EVENT_RUN_ENDED, {"victory": true})
	sim._autosave()


## The investor pays for the contract on delivery, and pays more for delivering
## early: every round left on the deadline is worth another round's rent. Rent is
## the scale because it is the one figure that already tracks the chapter — the
## same formula is pocket money in the bedroom and a fortune on the moon, without
## a table of per-location numbers to keep in step.
func _pay_ascension_bonus(sim: Node, contract: Dictionary) -> void:
	var cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("ascension_bonus", {})
	var rent: float = float(sim.run_state.economy.get("round_rent", 400.0))
	var rounds_spare: int = maxi(
		0, sim.ascension_system().deadline_round(contract) - int(sim.run_state.calendar.get("round", 1))
	)
	var multiple: float = (
		float(cfg.get("base_multiple", 1.0))
		+ float(cfg.get("per_round_multiple", 1.0)) * float(rounds_spare)
	)
	var bonus: float = rent * multiple
	if bonus <= 0.0:
		return
	sim.economy_system().credit(sim.run_state, bonus, "ascension_bonus", {
		"contract": str(contract.get("id", "")),
		"rounds_spare": rounds_spare,
		"multiple": multiple,
	})
	sim.run_state.statistics["ascension_bonus"] = (
		float(sim.run_state.statistics.get("ascension_bonus", 0.0)) + bonus
	)
	if rounds_spare > 0:
		sim.round_log.append(
			"The investor pays %s for delivering with %d round%s to spare."
			% [NumberFormat.format_cash(bonus), rounds_spare, "" if rounds_spare == 1 else "s"]
		)
	else:
		sim.round_log.append(
			"The investor pays %s on delivery." % NumberFormat.format_cash(bonus)
		)


## Beating the boss retires the chapter and opens the next one. Guarded once-only
## because `_end_run`'s "ascended" branch settles the same victory from the other
## direction, and a location must not be completed twice.
##
## The profile records the clear, but the campaign selection stays put: the win
## continues in place through `advance_to_next_chapter`, and a run started fresh
## afterwards is a fresh game from the bedroom, not a resume.
func _complete_run_location(sim: Node) -> void:
	if bool(sim.run_state.flags.get("location_completed", false)):
		return
	sim.run_state.flags["location_completed"] = true
	var location: String = str(sim.run_state.build.get("dwelling", ""))
	if location == "":
		return
	sim.run_state.flags["next_location"] = MetaProgress.next_location_after(location)
	MetaProgress.complete_location(location)


## Whether the run is being played in the campaign's last location — the only
## place a victory is the end of the game rather than of a chapter, and so the
## only place permanent rewards are paid out.
func _run_is_final_chapter(sim: Node) -> bool:
	return MetaProgress.next_location_after(str(sim.run_state.build.get("dwelling", ""))) == ""


## The location this victory opened up, empty if the run was played in the last
## chapter there is.
func next_location_unlocked(sim: Node) -> String:
	return str(sim.run_state.flags.get("next_location", ""))


## True while a victory is being settled: the bills landing in that window cannot
## take the win back, and no overlay should open in front of the verdict.
func is_settling_victory() -> bool:
	return settling_victory


## Carries a won run on rather than starting over. Everything the run owns stays
## put; from here the calendar is behind it and the costs climb every round, so
## the tail lasts exactly as long as the build can hold it up.
##
## Only the last chapter offers this. A mid-campaign win is a level-up — the next
## location is the continuation, and an endless tail there would just be a bigger
## bedroom. The tail exists for the run with nowhere further up to go.
func continue_after_victory(sim: Node) -> bool:
	if sim.phase != sim.Phase.RUN_END or not bool(sim.run_state.flags.get("victory", false)):
		return false
	if next_location_unlocked(sim) != "":
		return false
	sim.run_state.flags["post_victory"] = true
	sim.run_state.flags["victory"] = false
	sim.run_state.flags["outcome"] = ""
	sim.phase = sim._phase_from_name(str(sim.run_state.flags.get("post_victory_phase", "ROUND_PREP")))
	if sim.phase == sim.Phase.RUN_END or sim.phase == sim.Phase.IDLE:
		sim.phase = sim.Phase.ROUND_PREP
	sim.round_log.append(
		"The contract is signed and the company does not stop. "
		+ "From here the bills climb every round and nothing is left to prove."
	)
	_ensure_job_offers(sim)
	sim._autosave()
	return true


## A Deep Burn target was met. Called after the current session has already
## been settled: contracts never cross a depth boundary. Chapter bonuses stay
## put — this is not `_reach_victory`.
func reach_depth_complete(sim: Node) -> void:
	sim._work_running = false
	sim.run_state.flags["depth_complete_pending"] = false
	sim.run_state.flags["outcome"] = "depth_complete"
	sim.run_state.flags["depth_complete"] = true
	# Settlement already closed the desk into the next calendar. Resume is
	# always a fresh ROUND_PREP so Depth N+1 contracts are generated after
	# the affix pick, not leftover Depth N work.
	sim.run_state.flags["post_victory_phase"] = sim._phase_name(sim.Phase.ROUND_PREP)
	sim.pending_choices.clear()
	sim.round_log.append(
		"Depth %d complete. The next contract is waiting."
		% int(sim.run_state.depth.get("level", 0))
	)
	sim.phase = sim.Phase.RUN_END
	sim._autosave()


## Resume after a Deep Burn pick that was not the first one. The first pick
## still goes through `continue_after_victory` because that is the Moon win
## becoming endless; later rungs are already in that tail.
func continue_after_depth(sim: Node) -> bool:
	if sim.phase != sim.Phase.RUN_END:
		return false
	if not bool(sim.run_state.flags.get("depth_complete", false)) and str(
		sim.run_state.flags.get("outcome", "")
	) != "depth_complete":
		return false
	sim.run_state.flags["depth_complete"] = false
	sim.run_state.flags["depth_complete_pending"] = false
	if str(sim.run_state.flags.get("outcome", "")) == "depth_complete":
		sim.run_state.flags["outcome"] = ""
	sim.pending_choices.clear()
	# Settlement may have already stamped a board at the old requirement_mult.
	# The affix pick is what starts Depth N+1, so the offers have to be
	# rebuilt against that multiplier.
	sim.run_state.business["job_offers"] = []
	sim.run_state.business["job_queue"] = []
	sim.run_state.business["job_board_stamp"] = ""
	sim.phase = sim.Phase.ROUND_PREP
	_ensure_job_offers(sim)
	sim._autosave()
	return true


## Whether the run has already beaten a Tier 3 contract and chosen to carry on.
func in_post_victory(sim: Node) -> bool:
	return bool(sim.run_state.flags.get("post_victory", false))


## Moves a mid-campaign win into the next chapter as the same business. The
## angel's goal is the end of a chapter, not the end of the game: cash, perks,
## modules, workflows, upgrades and reputation all carry forward — what changes
## is the room, the rent, and the contract the run is measured against, which
## is the next location's bigger one. Only the last chapter has no next room;
## its continuation is `continue_after_victory`.
func advance_to_next_chapter(sim: Node) -> bool:
	if sim.phase != sim.Phase.RUN_END or not bool(sim.run_state.flags.get("victory", false)):
		return false
	var next_location: String = next_location_unlocked(sim)
	if next_location == "":
		return false
	sim.run_state.flags["victory"] = false
	sim.run_state.flags["outcome"] = ""
	sim.run_state.flags["location_completed"] = false
	sim.run_state.flags["next_location"] = ""
	sim.run_state.flags["post_victory_phase"] = ""
	# A new room comes with a new landlord. Arrears from the chapter just cleared
	# do not follow the company through the door, and neither does a loss reason
	# a suppressed mid-victory check may have left lying around — carried over,
	# either one could evict the run on its first prompt in the new chapter.
	sim.run_state.economy["rent_unpaid_streak"] = 0
	sim.run_state.flags["loss_reason"] = ""
	# The investor's stake pays for the room, but the company keeps its own
	# float: the stake is a floor under the new rent, not a replacement for
	# what the last chapter earned.
	var cash_carried: float = float(sim.run_state.economy.get("cash", 0.0))
	# The next room's own machine is a stake for a run that starts there. A run
	# that won its way up arrives with the rig it won on, and nothing else.
	apply_run_location(sim, sim.run_state, next_location, false)
	sim.run_state.economy["cash"] = maxf(cash_carried, float(sim.run_state.economy.get("cash", 0.0)))
	# A permanent rig rung the old room had no floor for is racked now that
	# there is a room that fits it.
	_install_permanent_rig(sim)
	# A new room starts cold, and the new chapter starts its year at round one.
	sim.run_state.compute["heat"] = 0.0
	sim.run_state.flags["fire_risk"] = false
	sim.run_state.calendar["round"] = 1
	sim.round_log.append(
		"Moved into the %s. Everything comes with you — the contract is bigger."
		% MetaProgress.location_name(next_location)
	)
	_begin_round(sim)
	# A draft pick earned on the winning round is still on the table; the new
	# chapter opens once it has been taken, exactly as a round boundary would.
	if not sim.pending_choices.is_empty():
		sim.phase = sim.Phase.ANGEL_ROUND
	sim._autosave()
	return true


## Takes one of the angel's offers. Everything on the table is free, so the only
## question is which one, and the draft closes either way.
func accept_offer(sim: Node, offer_type: String, offer_id: String) -> bool:
	match offer_type:
		"perk":
			return _accept_perk(sim, offer_id)
		"module":
			return _accept_module(sim, offer_id)
		_:
			return false


## Walks away with nothing. Always allowed: a full board and a bad offer is a
## real situation.
func decline_offers(sim: Node) -> void:
	if sim.phase != sim.Phase.ANGEL_ROUND:
		return
	sim.run_state.statistics["angel_offers_declined"] = int(
		sim.run_state.statistics.get("angel_offers_declined", 0)
	) + 1
	after_angel_round(sim)


## Spends the draft's one pick and closes it.
func _spend_draft_pick(sim: Node, _offer_type: String, _offer_id: String) -> void:
	after_angel_round(sim)


func _accept_perk(sim: Node, perk_id: String) -> bool:
	if sim.phase != sim.Phase.ANGEL_ROUND:
		return false
	if not sim.perk_system().collect_perk(sim.run_state, perk_id, ContentDatabase):
		return false
	if sim.perk_system().can_equip(sim.run_state, perk_id, ContentDatabase):
		sim.perk_system().equip_perk(sim.run_state, perk_id, ContentDatabase)
	sim.run_state.statistics["angel_offers_taken"] = int(
		sim.run_state.statistics.get("angel_offers_taken", 0)
	) + 1
	sim.debug_invalidate_subscriptions()
	EventBus.emit_event(EventBus.EVENT_PERK_ACQUIRED, {"perk_id": perk_id})
	sim._dispatch_perk_acquired(perk_id)
	sim.board_system().ensure_board(sim.run_state, ContentDatabase)
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	_spend_draft_pick(sim, "perk", perk_id)
	return true


## Drafts a pipeline module. Unlike a perk it changes nothing on its own: it has
## to be placed on the board to do anything, and on a full board that means
## taking something else out.
func _accept_module(sim: Node, module_id: String) -> bool:
	if sim.phase != sim.Phase.ANGEL_ROUND:
		return false
	if not sim.board_system().grant_module(sim.run_state, module_id):
		return false
	sim.run_state.statistics["angel_offers_taken"] = int(
		sim.run_state.statistics.get("angel_offers_taken", 0)
	) + 1
	sim.run_state.statistics["modules_drafted"] = int(
		sim.run_state.statistics.get("modules_drafted", 0)
	) + 1
	EventBus.emit_event(EventBus.EVENT_MODULE_ACQUIRED, {"module_id": module_id})
	sim.achievement_system().evaluate_tick(sim.run_state, ContentDatabase)
	_spend_draft_pick(sim, "module", module_id)
	return true


func _draft_state(sim: Node) -> Dictionary:
	var state: Dictionary = sim.run_state.build.get("draft_state", {})
	if not state is Dictionary:
		state = {"sequence": 0, "rerolls": 0}
	sim.run_state.build["draft_state"] = state
	return state


func _angel_draw_rng(sim: Node) -> DeterministicRng:
	var draft: Dictionary = _draft_state(sim)
	var sequence: int = int(draft.get("sequence", 0))
	var rerolls: int = int(draft.get("rerolls", 0))
	return sim.rng.derive("angel.%d.reroll.%d" % [sequence, rerolls])


func angel_reroll_cost(sim: Node) -> float:
	var draft: Dictionary = _draft_state(sim)
	var rerolls: int = int(draft.get("rerolls", 0))
	var base_cost: float = maxf(
		float(sim.run_state.economy.get("round_rent", 0.0)) * 0.5,
		_location_base_job_reward(sim) * 0.10
	)
	return base_cost * pow(2.0, float(rerolls))


func can_reroll_angel(sim: Node) -> bool:
	if sim.phase != sim.Phase.ANGEL_ROUND:
		return false
	return sim.economy_system().can_afford(sim.run_state, angel_reroll_cost(sim))


func reroll_angel_offers(sim: Node) -> bool:
	if sim.phase != sim.Phase.ANGEL_ROUND:
		return false
	var cost: float = angel_reroll_cost(sim)
	if not sim.economy_system().purchase(sim.run_state, cost, "angel_reroll"):
		return false
	var draft: Dictionary = _draft_state(sim)
	draft["rerolls"] = int(draft.get("rerolls", 0)) + 1
	sim.run_state.build["draft_state"] = draft
	_redraw_angel_offers(sim)
	sim._autosave()
	return true


func _location_base_job_reward(sim: Node) -> float:
	var dwelling: String = str(sim.run_state.build.get("dwelling", "bedroom"))
	for job in ContentDatabase.jobs:
		if str(job.id).contains(dwelling) or job.tier == 0:
			return float(job.reward_units) * float(sim.run_state.economy.get("cash_multiplier", 1.0)) * 100.0
	return float(sim.run_state.economy.get("round_rent", 400.0))


func _redraw_angel_offers(sim: Node) -> void:
	sim.pending_choices = []
	for offer in ContentDatabase.draw_angel_offers(
		_angel_draw_rng(sim),
		sim.run_state,
		3,
		sim.perk_system().owned_tags(sim.run_state, ContentDatabase),
		0.0
	):
		var offer_type: String = str(offer.get("type", ""))
		var offer_id: String = str(offer.get("id", ""))
		var description: String = ""
		if offer_type == "perk":
			description = sim.get_perk_description(offer_id)
		elif offer_type == "module":
			description = sim.get_module_description(offer_id)
		sim.pending_choices.append({
			"type": offer_type,
			"id": offer_id,
			"label": str(offer.get("label", "")),
			"description": description,
			"cost": 0.0,
		})


## The round's angel draft. Everything here is free: somebody with more money
## than sense is handing out modules and perks. Anything with a price tag is sold
## on the Market tab instead, where the player goes looking for it.
func present_angel_offers(sim: Node) -> void:
	var draft: Dictionary = _draft_state(sim)
	draft["sequence"] = int(draft.get("sequence", 0)) + 1
	draft["rerolls"] = 0
	sim.run_state.build["draft_state"] = draft
	_redraw_angel_offers(sim)
	if sim.pending_choices.is_empty():
		after_angel_round(sim)
		return
	sim.run_state.flags["draft_kind"] = sim.DRAFT_ANGEL
	sim.phase = sim.Phase.ANGEL_ROUND


## Which draft is on the table, so a screen can title itself.
func draft_kind(sim: Node) -> String:
	if sim.phase != sim.Phase.ANGEL_ROUND:
		return ""
	return str(sim.run_state.flags.get("draft_kind", sim.DRAFT_ANGEL))


## Picks still to spend on the draft. An angel draft is always worth exactly one.
func draft_picks_remaining(sim: Node) -> int:
	return 1 if sim.phase == sim.Phase.ANGEL_ROUND else 0


## Closes the round: the bills land, the rig cools off, and — if the rent
## cleared — the angels call. Reached only once every contract has resolved, so
## the player is never billed in the middle of a job.
func end_round(sim: Node) -> void:
	sim.phase = sim.Phase.ROUND_END
	# The round a contract was completed in is settled by the investor, not the
	# landlord. Charging it could evict a player on the same screen that told
	# them they had won.
	var statement: Dictionary
	if settling_victory:
		statement = sim.economy_system().waive_round_bills(sim.run_state)
		sim.round_log.append("The investor covers this round's bills.")
	else:
		statement = sim.economy_system().apply_round_bills(sim.run_state, sim.tuning)
	expire_status_effects(sim)
	var event: EventDefinition = sim.event_system().maybe_trigger(
		sim.run_state, sim.rng.derive("events"), ContentDatabase, sim.effect_resolver, sim.tuning
	)
	if event != null:
		statement["event"] = event.name
		sim.round_log.append("Event: %s" % event.name)
		# An event may have spawned a status effect, which only reaches the
		# dispatcher once the cached subscription list is rebuilt.
		sim.debug_invalidate_subscriptions()
	# The shed runs after the event so a spike the event just caused is cooled
	# by the same downtime as the heat the round itself made. Shedding first
	# left a fresh +25 sitting on the rig with nothing to take it back off.
	sim.heat_system().shed_between_rounds(sim.run_state)
	sim.last_round_statement = statement
	# Deferred so the statement screen opens on a settled state: the round
	# rollover below happens first.
	sim.round_statement_ready.emit.call_deferred(statement)
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)
	# A completed contract cannot be lost on the way out of the round it was
	# completed in, and the year cannot run out on work that is already done.
	# Both checks would only stamp a loss reason onto a won run.
	if not settling_victory:
		if sim.progression_system().check_loss(sim.run_state):
			end_run(sim, false)
			return
		if int(sim.run_state.calendar["round"]) >= _contract_deadline_round(sim):
			if in_post_victory(sim) or MetaProgress.endless_enabled():
				# Endless keeps going instead of stopping: the bills get harder
				# every round past the twelfth, so staying alive is the challenge
				# rather than survival being a foregone conclusion.
				_escalate_endless_costs(sim)
			else:
				# The terms were stated before the first prompt: the contract is
				# done inside the year or it is not done at all. Completing it
				# ends the run the moment it happens, mid-round, well before this
				# check is reached.
				sim.ascension_system().fail_on_deadline(sim.run_state)
				sim.run_state.flags["loss_reason"] = "The year ran out with the contract unfinished."
				sim.round_log.append(
					"The year is up and the contract is not complete. The investor is done with you."
				)
				end_run(sim, false, "contract_expired")
				return
	sim.run_state.calendar["round"] = int(sim.run_state.calendar["round"]) + 1
	sim.achievement_system().evaluate_tick(sim.run_state, ContentDatabase)
	_begin_round(sim)
	# Angels only call on a tenant in good standing. Clearing the round's bills
	# is the price of admission; miss the rent and nobody with money wants to be
	# seen anywhere near the operation. `_begin_round` has already opened round
	# prep, which is where a defaulting run stays.
	if bool(statement.get("paid_in_full", false)) and not settling_depth:
		present_angel_offers(sim)


## Ages the run's status effects by one round and drops the ones that have run
## out. A status that declares no `rounds` is permanent by design — that is what
## a perk's standing bonus is — so only the ones with a stated duration expire.
## Without this, an event that hangs a per-prompt cost on the rig (a fan dying,
## an incident war room) charged it for the rest of the run.
func expire_status_effects(sim: Node) -> void:
	var statuses: Array = Array(sim.run_state.build.get("status_effects", []))
	var surviving: Array = []
	var expired: Array = []
	for status in statuses:
		if not status is Dictionary or not status.has("rounds"):
			surviving.append(status)
			continue
		var remaining: int = int(status.get("rounds", 0)) - 1
		if remaining <= 0:
			expired.append(str(status.get("name", status.get("id", "A status effect"))))
			if str(status.get("id", "")).begins_with("status.fault."):
				EventBus.emit_event(EventBus.EVENT_FAULT_CLEARED, {"id": str(status.get("id", ""))})
			continue
		var aged: Dictionary = status.duplicate(true)
		aged["rounds"] = remaining
		surviving.append(aged)
	sim.run_state.build["status_effects"] = surviving
	if expired.is_empty():
		return
	sim.debug_invalidate_subscriptions()
	for name in expired:
		sim.round_log.append("%s has worn off." % name)


## Each round past the twelfth, rent and power creep up 8%: the same rig that
## coasted through the final act starts to strain again, keeping an endless
## run a real challenge instead of a victory lap.
func _escalate_endless_costs(sim: Node) -> void:
	sim.run_state.economy["round_rent"] = float(sim.run_state.economy.get("round_rent", 400.0)) * sim.ENDLESS_COST_ESCALATION
	sim.run_state.economy["power_base_cost_per_prompt"] = float(
		sim.run_state.economy.get("power_base_cost_per_prompt", 10.0)
	) * sim.ENDLESS_COST_ESCALATION
	sim.run_state.statistics["endless_rounds"] = int(sim.run_state.statistics.get("endless_rounds", 0)) + 1


## The last round the contract can be finished in. A won run carrying on into
## endless mode is past its deadline by definition, so the calendar length is
## used there instead.
func _contract_deadline_round(sim: Node) -> int:
	var contract: Dictionary = sim.ascension_system().current_contract(sim.run_state, ContentDatabase)
	if contract.is_empty():
		contract = sim.ascension_system().location_contract(sim.run_state, ContentDatabase)
	if contract.is_empty():
		return sim.ROUNDS_PER_RUN
	return sim.ascension_system().deadline_round(contract)


## Rounds left before the contract's deadline, this round included.
func rounds_remaining(sim: Node) -> int:
	return maxi(0, _contract_deadline_round(sim) - int(sim.run_state.calendar.get("round", 1)) + 1)


func after_angel_round(sim: Node) -> void:
	sim.pending_choices.clear()
	sim.run_state.flags["draft_kind"] = ""
	if sim.progression_system().check_loss(sim.run_state):
		end_run(sim, false)
		return
	if round_end_pending:
		round_end_pending = false
		end_round(sim)
		return
	sim.phase = sim.Phase.ROUND_PREP
	_ensure_job_offers(sim)


## `outcome` names how the run ended. "ascended" is the only way to win: an
## Ascension Contract completed. "retired" survives only for saves and profiles
## written before overtime existed — the calendar no longer ends a run, so
## nothing reaches it any more. Left blank it falls back to the old two-state
## behaviour ("ascended" on victory, "lost" otherwise), which is what the batch
## runner, screenshot tool, and older tests still call.
func end_run(sim: Node, victory: bool, outcome: String = "") -> void:
	# Bills landing while an ascension is being settled cannot take the win back.
	# The endless tail the player is about to be offered may be short, but the
	# contract was completed and the run was won.
	if settling_victory and not victory:
		return
	if outcome == "":
		outcome = "ascended" if victory else "lost"
	sim.run_state.flags["victory"] = victory
	sim.run_state.flags["outcome"] = outcome
	if not victory and sim.run_state.flags.get("loss_reason", "") == "":
		sim.run_state.flags["loss_reason"] = "Run collapsed."
	sim.phase = sim.Phase.RUN_END
	MetaProgress.record_best_score(RunScore.compute(sim.run_state, ContentDatabase))
	match outcome:
		"ascended":
			var contract: Dictionary = sim.ascension_system().current_contract(sim.run_state, ContentDatabase)
			sim.run_state.flags["ascension_tier"] = int(contract.get("tier", 1))
			MetaProgress.record_ascension(str(contract.get("id", "")))
			_complete_run_location(sim)
			# Same rule as `_reach_victory`: only finishing the campaign's last
			# chapter pays out anything permanent.
			if _run_is_final_chapter(sim):
				MetaProgress.bank_victory(
					maxi(1, int(contract.get("picks", 1))),
					str(sim.run_state.flags.get("difficulty", "normal"))
				)
				if bool(contract.get("unlocks_age", false)):
					MetaProgress.advance_age(Ages.max_age_index())
				var ending_unlock: String = str(contract.get("ending_unlock", ""))
				if ending_unlock != "":
					MetaProgress.grant_ending_unlock(ending_unlock)
		"retired":
			MetaProgress.record_retirement()
		_:
			pass
	_bank_run_legacy(sim, victory)
	EventBus.emit_event(EventBus.EVENT_RUN_ENDED, {"victory": victory})
	sim._autosave()


## Lifetime counters and end-of-run awards, folded in once per run whatever
## finally closes it. A won run can carry on into endless and end again later, so
## banking on every ending would count the same run's legacy twice.
##
## Lifetime counters are folded in before the awards are judged, so an achievement
## that asks for ten losses can be earned by the tenth loss rather than the
## eleventh.
func _bank_run_legacy(sim: Node, victory: bool) -> void:
	if bool(sim.run_state.flags.get("legacy_banked", false)):
		return
	sim.run_state.flags["legacy_banked"] = true
	MetaProgress.add_lifetime_stats(AchievementSystem.lifetime_deltas(sim.run_state, victory))
	sim.achievement_system().evaluate_run_end(
		sim.run_state, RunScore.compute(sim.run_state, ContentDatabase), ContentDatabase
	)


## The permanent unlocks on offer after beating the campaign. Picks are rare —
## one batch per completion — so the debrief lays out every area still open
## (rig, cooling, cash, workflows, board width) and the player chooses
## which to boost permanently, rather than being dealt three at random.
func debrief_choices() -> Array:
	if MetaProgress.pending_picks() <= 0:
		return []
	return MetaProgress.available_choices()


func spend_debrief_pick(unlock_id: String) -> bool:
	return MetaProgress.spend_pick(unlock_id)


func load_saved_run(sim: Node) -> bool:
	var data: Dictionary = SaveManager.load_run()
	if data.is_empty():
		return false
	sim.run_seed = int(data.get("seed", 0))
	sim.rng.set_seed(sim.run_seed)
	sim.run_state.from_dict(data.get("run_state", {}))
	var saved_choices = data.get("pending_choices", [])
	sim.pending_choices = saved_choices if saved_choices is Array else []
	_migrate_pending_choices(sim)
	var phase_name: String = str(data.get("phase", "IDLE"))
	sim.phase = sim._phase_from_name(phase_name)
	sim._work_running = false
	# Saves written before the redesign called the round a month.
	round_end_pending = bool(data.get("round_end_pending", data.get("month_end_pending", false)))
	sim.debug_invalidate_subscriptions()
	# A save from before the campaign existed can be mid-warehouse, having
	# climbed there with cash. That rung and everything under it is earned, so
	# the profile catches up rather than stranding the run somewhere it is no
	# longer allowed to be.
	MetaProgress.ensure_location_unlocked_through(str(sim.run_state.build.get("dwelling", "")))
	# Cooling from permanent unlocks is a function of the profile, not of the
	# run, so it is read back rather than restored from the save.
	sim.run_state.compute["meta_cooling"] = MetaProgress.cooling_bonus()
	if sim.phase == sim.Phase.IDLE:
		start_run(sim, sim.run_seed)
		return true
	repair_after_load(sim)
	return true


## Angel drafts used to offer `type: operation`. accept_offer only understands
## perk / module, so a save taken on that wording would present a card nothing
## could take.
func _migrate_pending_choices(sim: Node) -> void:
	for choice in sim.pending_choices:
		if choice is Dictionary and str(choice.get("type", "")) == "operation":
			choice["type"] = "module"


func board_stamp(sim: Node) -> String:
	return _board_stamp(sim)


func grant_location_starter_rig(sim: Node, state: RunState, stats: Dictionary) -> void:
	_grant_location_starter_rig(sim, state, stats)


func install_permanent_rig(sim: Node) -> void:
	_install_permanent_rig(sim)


func begin_round(sim: Node) -> void:
	_begin_round(sim)


func pay_ascension_bonus(sim: Node, contract: Dictionary) -> void:
	_pay_ascension_bonus(sim, contract)


func complete_run_location(sim: Node) -> void:
	_complete_run_location(sim)


func run_is_final_chapter(sim: Node) -> bool:
	return _run_is_final_chapter(sim)


func spend_draft_pick(sim: Node, offer_type: String, offer_id: String) -> void:
	_spend_draft_pick(sim, offer_type, offer_id)


func accept_perk(sim: Node, perk_id: String) -> bool:
	return _accept_perk(sim, perk_id)


func accept_module(sim: Node, module_id: String) -> bool:
	return _accept_module(sim, module_id)


func draft_state(sim: Node) -> Dictionary:
	return _draft_state(sim)


func angel_draw_rng(sim: Node) -> DeterministicRng:
	return _angel_draw_rng(sim)


func location_base_job_reward(sim: Node) -> float:
	return _location_base_job_reward(sim)


func redraw_angel_offers(sim: Node) -> void:
	_redraw_angel_offers(sim)


func escalate_endless_costs(sim: Node) -> void:
	_escalate_endless_costs(sim)


func contract_deadline_round(sim: Node) -> int:
	return _contract_deadline_round(sim)


func bank_run_legacy(sim: Node, victory: bool) -> void:
	_bank_run_legacy(sim, victory)


func migrate_pending_choices(sim: Node) -> void:
	_migrate_pending_choices(sim)
