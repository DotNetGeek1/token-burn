class_name RunLifecycle
extends RefCounted

## Start/end of a run, round boundaries, the investor's perk draft, targets /
## victory / Deep Burn, and save/load. Owned by Simulation as `_life`. Public
## `phase` / `pending_choices` stay on the facade (too many callers).
##
## Perks are drafted once per target, when the investor's figure is met: the
## table is dealt in `reach_target_complete` and has to be taken or declined
## before the company can move on. The old round-end angel draft is gone;
## `ANGEL_ROUND` survives only so a save written with one open can still
## resolve it.
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
	# Lazily create module-market state so old saves get a shelf without a
	# save-version bump. An already-current empty shelf is left alone.
	MarketService.ensure_module_stock(sim)

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
			# A pre-v25 save mid-draft. Let it finish the table it was dealt;
			# an empty table is simply closed.
			if sim.pending_choices.is_empty():
				after_angel_round(sim)

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
	# Every run starts on the starting rig. Machine scale is bought in the
	# Market from here; nothing about where the run "is" is decided up front.
	apply_infrastructure_tier(sim, sim.run_state, InfrastructureSystem.MIN_TIER)
	# Permanent unlocks land before the board is sized, so an unlocked slot is
	# there to be filled rather than turning up a round late.
	MetaProgress.apply_to_run(sim.run_state)
	_install_permanent_rig(sim)
	sim.board_system().ensure_board(sim.run_state, ContentDatabase)
	# The investor's first target is the run's win condition, not something
	# taken on part-way through, so it is live before the first prompt is spent.
	sim.investor_progression().activate_level(
		sim.run_state, InvestorProgression.FIRST_LEVEL, ContentDatabase
	)
	sim.compute_system().recalculate(
		sim.run_state, sim.effect_resolver, sim.debug_collect_subscriptions(), sim.rng
	)


## Settles the run onto an Infrastructure Tier: the cabinet systems are raised
## to the tier's entry tiers (never lowered — anything already bought above
## them stays), the rent becomes the tier's facility cost, and heat capacity
## and cooling are re-derived from the new floors. Nothing is granted and no
## cash moves; the purchase flow and the investor's target are separate.
func apply_infrastructure_tier(sim: Node, state: RunState, new_tier: int) -> void:
	InfrastructureSystem.set_tier(state, new_tier, ContentDatabase)
	CabinetSystems.raise_to_infrastructure(state, ContentDatabase)
	InfrastructureSystem.apply_rent(state, ContentDatabase)
	# A bigger cooling loop takes longer to cook. Heat is measured against this
	# rather than a fixed hundred, so a higher tier buys headroom as well as
	# cooling. Read from the Cooling Loop tier, floored by the tier's own row.
	state.compute["heat_capacity"] = CabinetSystems.capacity(state, "cooling", "heat_capacity")
	state.compute["cooling"] = ComputeSystem.derive_cooling(state)
	if sim != null:
		sim.debug_invalidate_subscriptions()


## Racks the machines earned through the permanent starting-rig unlock ladder.
## A fresh run is otherwise a fresh game from the start — nothing a previous run
## bought arrives — so this is the one place hardware crosses runs, and only
## because a pick was spent on it after beating the whole campaign.
##
## Free of charge but not of floor space: a small rig racks what fits, and the
## call from `purchase_infrastructure` racks the rest once a bigger tier opens.
## That second call is why a rung already standing is skipped rather than
## installed again.
func _install_permanent_rig(sim: Node) -> void:
	for upgrade_id in MetaProgress.starting_rig():
		var upgrade: UpgradeDefinition = ContentDatabase.get_upgrade(str(upgrade_id))
		if upgrade != null:
			CabinetSystems.grant_permanent_upgrade(sim.run_state, upgrade)



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
	# Module shelf restocks once per round and scale stamp (Investor Level and
	# Infrastructure Tier), after the calendar is settled. Opening the Market
	# never regenerates it.
	MarketService.ensure_module_stock(sim)
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


## The investor's target has been met. The run is not thrown away with it. The
## round it happened in is settled properly — the work pays out, the bills are
## waived — and then the investor deals his perks: one draft per target, taken
## or declined before the company moves on. The phase that would have come next
## is remembered, so continuing resumes from a clean round boundary instead of
## the middle of a burn.
##
## Only the target marked `final` is the end of the game: that is the one that
## sets `game_completed`, pays out Permanent Unlocks, and whose continuation is
## Deep Burn. Every other target is a level-up inside the run, continued in
## place through `continue_after_target`.
func reach_target_complete(sim: Node, target: Dictionary) -> void:
	var investor: InvestorProgression = sim.investor_progression()
	var level: int = investor.level(sim.run_state)
	var is_final: bool = bool(target.get("final", false))
	investor.record_final(sim.run_state, target)
	sim.run_state.flags["victory"] = true
	sim.run_state.flags["outcome"] = "ascended"
	sim.run_state.flags["target_complete"] = true
	if is_final:
		sim.run_state.flags["game_completed"] = true
		sim.round_log.append("%s is complete. Token Burn is complete." % str(target.get("name", "The target")))
	else:
		sim.round_log.append("%s is complete. Investor Level %d." % [str(target.get("name", "The target")), level + 1])
	MetaProgress.record_best_score(RunScore.compute(sim.run_state, ContentDatabase))
	MetaProgress.record_ascension(str(target.get("id", "")))
	# Permanence is the reward for finishing the whole game. A target cleared on
	# the way up is a level-up inside the run — it banks no picks, advances no
	# age and hands over no rule unlocks; only the final target pays.
	if is_final:
		_pay_permanent_unlocks(sim, target)
	_bank_run_legacy(sim, true)
	_pay_ascension_bonus(sim, target)
	settling_victory = true
	sim._end_session("ascended")
	settling_victory = false
	# The reward for the target. Dealt exactly once here, whatever the target
	# says about picks — those are the profile's, paid at the final only.
	present_investor_draft(sim)
	# Settling leaves the round closed out into the next round's prep, but a
	# loss check swallowed mid-settle can leave it elsewhere. Continuing always
	# resumes on a clean round boundary.
	sim.run_state.flags["post_victory_phase"] = sim._phase_name(sim.Phase.ROUND_PREP)
	sim.phase = sim.Phase.RUN_END
	EventBus.emit_event(EventBus.EVENT_INVESTOR_TARGET_COMPLETED, {
		"level": level, "target_id": str(target.get("id", "")), "final": is_final,
	})
	EventBus.emit_event(EventBus.EVENT_RUN_ENDED, {"victory": true})
	sim._autosave()


## The Permanent Unlocks for completing the game: picks on the profile's
## unlock ladder, the age, and any ending the target opens.
func _pay_permanent_unlocks(sim: Node, target: Dictionary) -> void:
	MetaProgress.bank_victory(
		maxi(1, int(target.get("picks", 1))),
		str(sim.run_state.flags.get("difficulty", "normal"))
	)
	if bool(target.get("unlocks_age", false)):
		MetaProgress.advance_age(Ages.max_age_index())
	var ending_unlock: String = str(target.get("ending_unlock", ""))
	if ending_unlock != "":
		MetaProgress.grant_ending_unlock(ending_unlock)


## The investor pays for the target on delivery, and pays more for delivering
## early: every round left on the deadline is worth another round's rent. Rent is
## the scale because it is the one figure that already tracks the machine's
## scale — the same formula is pocket money on the starting rig and a fortune
## at planetary scale, without a table of per-tier numbers to keep in step.
func _pay_ascension_bonus(sim: Node, contract: Dictionary) -> void:
	var cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("ascension_bonus", {})
	var rent: float = float(sim.run_state.economy.get("round_rent", 400.0))
	var rounds_spare: int = maxi(
		0, sim.investor_progression().deadline_round(sim.run_state, contract) - int(sim.run_state.calendar.get("round", 1))
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


## Whether the target the run is playing for (or has just completed) is the one
## whose completion is the end of the game — the only place permanent rewards
## are paid out. Read off the target's own `final` flag.
func _run_is_final_target(sim: Node) -> bool:
	return bool(sim.investor_progression().current_target(sim.run_state, ContentDatabase).get("final", false))


## True while a victory is being settled: the bills landing in that window cannot
## take the win back, and no overlay should open in front of the verdict.
func is_settling_victory() -> bool:
	return settling_victory


## Carries a completed game on into Deep Burn rather than starting over.
## Everything the run owns stays put; from here the calendar is behind it and
## the costs climb every round, so the tail lasts exactly as long as the build
## can hold it up.
##
## Only the final target offers this. Any other target is a level-up — the next
## target is the continuation (`continue_after_target`), and an endless tail
## there would just be a bigger starting rig.
func continue_after_victory(sim: Node) -> bool:
	if sim.phase != sim.Phase.RUN_END or not bool(sim.run_state.flags.get("victory", false)):
		return false
	if not bool(sim.run_state.flags.get("game_completed", false)):
		return false
	# The investor's table is still on the desk. Take a card or turn them all
	# down first; the run does not carry on with the draft unresolved.
	if investor_draft_pending(sim):
		return false
	sim.run_state.flags["post_victory"] = true
	sim.run_state.flags["victory"] = false
	sim.run_state.flags["outcome"] = ""
	sim.run_state.flags["target_complete"] = false
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
## been settled: contracts never cross a depth boundary. Target bonuses stay
## put — this is not `reach_target_complete`.
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


## Whether the run has already completed the game and chosen to carry on into
## Deep Burn.
func in_post_victory(sim: Node) -> bool:
	return bool(sim.run_state.flags.get("post_victory", false))


## Takes the next target after a non-final one is met: the same business,
## the same room, the same calendar, one Investor Level higher. Cash, perks,
## modules, workflows, upgrades and machine all carry forward untouched; the
## only thing that changes is the figure the run is measured against and the
## deadline it has to hit it by. The final target has no next; its
## continuation is `continue_after_victory` (Deep Burn).
func continue_after_target(sim: Node) -> bool:
	if sim.phase != sim.Phase.RUN_END or not bool(sim.run_state.flags.get("victory", false)):
		return false
	if not bool(sim.run_state.flags.get("target_complete", false)):
		return false
	if bool(sim.run_state.flags.get("game_completed", false)):
		return false
	# The perk draft the target earned is settled before moving on, not
	# carried into the next level as a loose end.
	if investor_draft_pending(sim):
		return false
	sim.run_state.flags["investor_draft_resolved"] = false
	sim.run_state.flags["victory"] = false
	sim.run_state.flags["outcome"] = ""
	sim.run_state.flags["target_complete"] = false
	sim.run_state.flags["post_victory_phase"] = ""
	# The run is continuous, so the rent record carries over: arrears owed
	# before the target stand after it. Only a loss reason a suppressed
	# mid-victory check may have left lying around is cleared — carried over,
	# it could end the run on its first prompt at the new level.
	sim.run_state.flags["loss_reason"] = ""
	var investor: InvestorProgression = sim.investor_progression()
	investor.advance(sim.run_state, ContentDatabase)
	var level: int = investor.level(sim.run_state)
	var target: Dictionary = investor.active_target(sim.run_state, ContentDatabase)
	sim.round_log.append(
		"Investor Level %d. %s: %s by round %d."
		% [
			level,
			str(target.get("name", "The next target")),
			str(target.get("burn_label", NumberFormat.format(float(target.get("total_burn", 0.0))))),
			investor.deadline_round(sim.run_state, target),
		]
	)
	EventBus.emit_event(EventBus.EVENT_INVESTOR_LEVEL_ADVANCED, {
		"level": level, "target_id": str(target.get("id", "")),
	})
	# Settlement already rolled the round over into the next one's prep, so
	# the run resumes there; nothing on the calendar moves.
	sim.phase = sim.Phase.ROUND_PREP
	_ensure_job_offers(sim)
	sim._autosave()
	return true


## Takes one of the investor's perk offers. Everything on the table is free, so
## the only question is which one, and the draft closes either way.
func accept_offer(sim: Node, offer_type: String, offer_id: String) -> bool:
	if offer_type != "perk":
		return false
	if not _pending_contains(sim, "perk", offer_id):
		return false
	return _accept_perk(sim, offer_id)


## Whether a perk table is on the desk and can be answered: the investor's
## draft on a won run, or a legacy save's round-end angel draft.
func draft_open(sim: Node) -> bool:
	if sim.pending_choices.is_empty():
		return false
	if sim.phase == sim.Phase.ANGEL_ROUND:
		return true
	return investor_draft_pending(sim)


## The investor's own draft: dealt on the victory screen, resolved before the
## company moves on.
func investor_draft_pending(sim: Node) -> bool:
	return (
		sim.phase == sim.Phase.RUN_END
		and not sim.pending_choices.is_empty()
		and str(sim.run_state.flags.get("draft_kind", "")) == sim.DRAFT_INVESTOR
	)


func _pending_contains(sim: Node, offer_type: String, offer_id: String) -> bool:
	for choice in sim.pending_choices:
		if not choice is Dictionary:
			continue
		if str(choice.get("type", "")) == offer_type and str(choice.get("id", "")) == offer_id:
			return true
	return false


## Walks away with nothing. Always allowed: a full board and a bad offer is a
## real situation.
func decline_offers(sim: Node) -> void:
	if not draft_open(sim):
		return
	sim.run_state.statistics["angel_offers_declined"] = int(
		sim.run_state.statistics.get("angel_offers_declined", 0)
	) + 1
	after_angel_round(sim)


## Spends the draft's one pick and closes it.
func _spend_draft_pick(sim: Node, _offer_type: String, _offer_id: String) -> void:
	after_angel_round(sim)


func _accept_perk(sim: Node, perk_id: String) -> bool:
	if not draft_open(sim):
		return false
	if not sim.grant_perk(perk_id):
		return false
	sim.run_state.statistics["angel_offers_taken"] = int(
		sim.run_state.statistics.get("angel_offers_taken", 0)
	) + 1
	_spend_draft_pick(sim, "perk", perk_id)
	return true


## Modules are no longer free angel rewards. Kept as a hard reject so old callers
## and saves cannot grant a free module through this path.
func _accept_module(_sim: Node, _module_id: String) -> bool:
	return false


func _draft_state(sim: Node) -> Dictionary:
	var state: Dictionary = sim.run_state.build.get("draft_state", {})
	if not state is Dictionary:
		state = {"sequence": 0, "rerolls": 0}
	sim.run_state.build["draft_state"] = state
	return state


func _angel_draw_rng(sim: Node) -> DeterministicRng:
	var draft: Dictionary = _draft_state(sim)
	var sequence: int = int(draft.get("sequence", 0))
	# Angel rerolls are removed; the key stays sequence-only for determinism.
	return sim.rng.derive("angel.%d.reroll.0" % sequence)


## Deals the table: three cards, plus one per Rolodex rank the profile holds.
func _redraw_angel_offers(sim: Node) -> void:
	sim.pending_choices = []
	for offer in ContentDatabase.draw_angel_perks(
		_angel_draw_rng(sim),
		sim.run_state,
		MetaProgress.BASE_DRAFT_OPTIONS + MetaProgress.draft_option_bonus(),
		sim.perk_system().owned_tags(sim.run_state, ContentDatabase),
		sim.perk_system().undraftable_ids(sim.run_state, ContentDatabase)
	):
		var offer_id: String = str(offer.get("id", ""))
		sim.pending_choices.append({
			"type": "perk",
			"id": offer_id,
			"label": str(offer.get("label", "")),
			"description": sim.get_perk_description(offer_id),
			"cost": 0.0,
		})


## Deals a fresh table and stamps it with `kind`. False when nothing could be
## dealt — every perk owned or blocked — so the caller can skip the draft.
func _deal_draft(sim: Node, kind: String) -> bool:
	var draft: Dictionary = _draft_state(sim)
	draft["sequence"] = int(draft.get("sequence", 0)) + 1
	draft["rerolls"] = 0
	sim.run_state.build["draft_state"] = draft
	_redraw_angel_offers(sim)
	if sim.pending_choices.is_empty():
		sim.run_state.flags["draft_kind"] = ""
		return false
	sim.run_state.flags["draft_kind"] = kind
	return true


## The investor's draft, dealt when a target is met. Everything on it
## is free and permanent; the phase stays wherever the victory left it
## (`RUN_END`), and the table is answered from the verdict screen. A goal with
## nothing left to offer is marked resolved straight away so nothing waits on
## an empty table.
func present_investor_draft(sim: Node) -> void:
	if _deal_draft(sim, sim.DRAFT_INVESTOR):
		sim.run_state.flags["investor_draft_resolved"] = false
		return
	sim.run_state.flags["investor_draft_resolved"] = true


## The pre-v25 round-end angel draft, kept only so a save that was written
## mid-table can be resolved and so tests can open a table between rounds.
## Nothing in the round loop calls this any more.
func present_legacy_angel_draft(sim: Node) -> void:
	if not _deal_draft(sim, sim.DRAFT_ANGEL):
		after_angel_round(sim)
		return
	sim.phase = sim.Phase.ANGEL_ROUND


## Which draft is on the table, so a screen can title itself. Empty when none.
func draft_kind(sim: Node) -> String:
	if not draft_open(sim):
		return ""
	return str(sim.run_state.flags.get("draft_kind", sim.DRAFT_ANGEL))


## Picks still to spend on the draft. A draft is always worth exactly one.
func draft_picks_remaining(sim: Node) -> int:
	return 1 if draft_open(sim) else 0


## Closes the round: the bills land and the rig cools off. Reached only once
## every contract has resolved, so the player is never billed in the middle of
## a job. Nothing is drafted here — perks come from the investor's goal.
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
				# Deep Burn keeps going instead of stopping: the bills get harder
				# every round past the deadline, so staying alive is the challenge
				# rather than survival being a foregone conclusion.
				_escalate_endless_costs(sim)
			else:
				# The terms were stated when the target went live: it is done by
				# its deadline or it is not done at all. Completing it ends the
				# round the moment it happens, mid-burn, well before this check
				# is reached.
				sim.investor_progression().fail_on_deadline(sim.run_state)
				sim.run_state.flags["loss_reason"] = "The deadline passed with the investor's target unmet."
				sim.round_log.append(
					"The deadline is up and the target is not met. The investor is done with you."
				)
				end_run(sim, false, "contract_expired")
				return
	sim.run_state.calendar["round"] = int(sim.run_state.calendar["round"]) + 1
	sim.achievement_system().evaluate_tick(sim.run_state, ContentDatabase)
	_begin_round(sim)


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


## Each round past the twelfth, rent and power creep up 8%, and the room runs
## hotter and the racks flakier (`HeatSystem.escalate_endless`): the same rig
## that coasted through the final act starts to strain again, keeping an
## endless run a real challenge instead of a victory lap.
func _escalate_endless_costs(sim: Node) -> void:
	sim.run_state.economy["round_rent"] = float(sim.run_state.economy.get("round_rent", 400.0)) * sim.ENDLESS_COST_ESCALATION
	sim.run_state.economy["power_base_cost_per_prompt"] = float(
		sim.run_state.economy.get("power_base_cost_per_prompt", 10.0)
	) * sim.ENDLESS_COST_ESCALATION
	HeatSystem.escalate_endless(sim.run_state, Dictionary(ContentDatabase.balance.get("economy", {})))
	sim.run_state.statistics["endless_rounds"] = int(sim.run_state.statistics.get("endless_rounds", 0)) + 1


## The last round the live target can be finished in, on the run's continuous
## calendar. A run with no target at all (content missing) falls back to the
## old calendar length.
func _contract_deadline_round(sim: Node) -> int:
	var investor: InvestorProgression = sim.investor_progression()
	var target: Dictionary = investor.current_target(sim.run_state, ContentDatabase)
	if target.is_empty():
		return sim.ROUNDS_PER_RUN
	return investor.deadline_round(sim.run_state, target)


## Rounds left before the contract's deadline, this round included.
func rounds_remaining(sim: Node) -> int:
	return maxi(0, _contract_deadline_round(sim) - int(sim.run_state.calendar.get("round", 1)) + 1)


## Closes whichever draft was open. The investor's draft leaves the phase
## alone — the run is still on its verdict screen, now free to move on — while
## a legacy angel draft rolls the round over the way it always did.
func after_angel_round(sim: Node) -> void:
	var was_investor: bool = investor_draft_pending(sim) or (
		sim.phase == sim.Phase.RUN_END
		and str(sim.run_state.flags.get("draft_kind", "")) == sim.DRAFT_INVESTOR
	)
	sim.pending_choices.clear()
	sim.run_state.flags["draft_kind"] = ""
	if was_investor:
		sim.run_state.flags["investor_draft_resolved"] = true
		sim._autosave()
		return
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
## Investor Target completed. "retired" survives only for saves and profiles
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
			var target: Dictionary = sim.investor_progression().current_target(sim.run_state, ContentDatabase)
			sim.run_state.flags["target_complete"] = true
			MetaProgress.record_ascension(str(target.get("id", "")))
			# Same rule as `reach_target_complete`: only the final target pays
			# out anything permanent.
			if bool(target.get("final", false)):
				sim.run_state.flags["game_completed"] = true
				_pay_permanent_unlocks(sim, target)
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
##
## The profile's records (deepest Deep Burn, biggest batch, richest run, fastest
## completion) only ever move up, so they are taken on every ending — a run
## that completed the game and went on into Deep Burn sets its depth record on
## the ending that finally closes it, not the one that banked its picks.
func _bank_run_legacy(sim: Node, victory: bool) -> void:
	MetaProgress.record_run_records(sim.run_state)
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
	var phase_name: String = str(data.get("phase", "IDLE"))
	sim.phase = sim._phase_from_name(phase_name)
	var saved_choices = data.get("pending_choices", [])
	sim.pending_choices = saved_choices if saved_choices is Array else []
	_migrate_pending_choices(sim)
	sim._work_running = false
	# Saves written before the redesign called the round a month.
	round_end_pending = bool(data.get("round_end_pending", data.get("month_end_pending", false)))
	sim.debug_invalidate_subscriptions()
	# The tier is the authority and the room is derived from it. The v26
	# migration has already read a room-only save back into its tier; this only
	# refreshes the derived room cache against the content that is loaded.
	InfrastructureSystem.ensure_state(sim.run_state, ContentDatabase)
	# Cooling from permanent unlocks is a function of the profile, not of the
	# run, so it is read back rather than restored from the save.
	sim.run_state.compute["meta_cooling"] = MetaProgress.cooling_bonus()
	if sim.phase == sim.Phase.IDLE:
		start_run(sim, sim.run_seed)
		return true
	repair_after_load(sim)
	return true


## Angel drafts used to offer modules (and even older saves used `operation`).
## Keep valid perks, drop free module choices, and redraw if the table emptied.
func _migrate_pending_choices(sim: Node) -> void:
	var kept: Array = []
	var blocked_perks: Array = sim.perk_system().undraftable_ids(
		sim.run_state, ContentDatabase
	)
	for choice in sim.pending_choices:
		if not choice is Dictionary:
			continue
		var offer_type: String = str(choice.get("type", ""))
		if offer_type == "operation":
			# Legacy operation cards were modules; those are no longer free.
			continue
		if offer_type == "module":
			continue
		if offer_type == "perk":
			var perk_id: String = str(choice.get("id", ""))
			if ContentDatabase.get_perk(perk_id) != null and perk_id not in blocked_perks:
				kept.append(choice)
	sim.pending_choices = kept
	if sim.phase == sim.Phase.RUN_END:
		# An investor draft whose every card has since become illegal is
		# simply over; the verdict screen has nothing to wait for.
		if sim.pending_choices.is_empty() and str(
			sim.run_state.flags.get("draft_kind", "")
		) == sim.DRAFT_INVESTOR:
			sim.run_state.flags["draft_kind"] = ""
			sim.run_state.flags["investor_draft_resolved"] = true
		return
	if sim.phase != sim.Phase.ANGEL_ROUND:
		return
	if not sim.pending_choices.is_empty():
		return
	# Mixed saves that lost every module card need a fresh perk-only table.
	_redraw_angel_offers(sim)
	if sim.pending_choices.is_empty():
		sim.phase = sim.Phase.ROUND_PREP
		sim.run_state.flags["draft_kind"] = ""
		MarketService.ensure_module_stock(sim)


func board_stamp(sim: Node) -> String:
	return _board_stamp(sim)


func install_permanent_rig(sim: Node) -> void:
	_install_permanent_rig(sim)


func begin_round(sim: Node) -> void:
	_begin_round(sim)


func pay_ascension_bonus(sim: Node, contract: Dictionary) -> void:
	_pay_ascension_bonus(sim, contract)


func run_is_final_target(sim: Node) -> bool:
	return _run_is_final_target(sim)


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
