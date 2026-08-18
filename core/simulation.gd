extends Node

## Autoload facade over game state. UI, tests, and tools call `Simulation.*`.
## Orchestration lives in collaborators: `SimulationPreview` (read-only
## forecasts), `WorkSession` (in-round ticks), `RunLifecycle` (start/end run,
## rounds, angel draft, save/load), and `MarketService` (buy/sell). Domain
## systems stay in `systems/` on `RunState`.

## A round is the whole cycle: ROUND_PREP is where contracts are taken and the
## Market is open, IN_ROUND is the work itself (one prompt per burn or cool, for
## as many prompts as the contracts need), and ROUND_END is where the bills land.
enum Phase {
	IDLE,
	ROUND_PREP,
	IN_ROUND,
	ROUND_END,
	## An angel investor draft: free picks only. Paid upgrades live on the Market.
	ANGEL_ROUND,
	RUN_END,
}

## Rounds in the year. The location's contract is the win condition and this is
## its deadline: finishing the contract wins the run, and reaching the end of
## the year without it ends the run. There is no overtime.
const ROUNDS_PER_RUN := 12

## Stands in for "this layout never delivers" when scoring pipelines.
const MAX_ESTIMATED_BURNS := 99.0

## Cloud burst is bought, not given: the account below unlocks the key, and the
## multiplier starts low enough that the repeatable upgrade is the way to power.
const CLOUD_ACCOUNT_UPGRADE := "upgrade.cloud_account"
const CLOUD_BURST_UPGRADE := "upgrade.cloud_compute"
const CLOUD_BURST_BASE_MULTIPLIER := 1.5
const CLOUD_BURST_PER_LEVEL := 0.5
const DRAFT_ANGEL := "angel"
const ENDLESS_COST_ESCALATION := 1.08

signal work_tick_completed
signal work_session_finished(result: Dictionary)
signal round_statement_ready(statement: Dictionary)
signal burn_resolved(burn: Dictionary)

var run_state: RunState = RunState.new()
var rng: DeterministicRng = DeterministicRng.new()
var effect_resolver: EffectResolver = EffectResolver.new()
var phase: int = Phase.IDLE
var run_seed: int = 0
var round_log: Array[String] = []
var pending_choices: Array = []
var autosave_enabled: bool = true
var tuning: Dictionary = {
	"economy_multiplier": 1.0,
	"token_multiplier": 1.0,
	"cloud_cost_multiplier": 1.0,
	"event_probability_multiplier": 1.0,
}

var _job_system := JobSystem.new()
var _economy_system := EconomySystem.new()
var _compute_system := ComputeSystem.new()
var _heat_system := HeatSystem.new()
var _demand_system := DemandSystem.new()
var _progression_system := ProgressionSystem.new()
var _event_system := EventSystem.new()
var _perk_system := PerkSystem.new()
var _upgrade_system := UpgradeSystem.new()
var _board_system := BoardSystem.new()
var _ascension_system := AscensionSystem.new()
var _achievement_system := AchievementSystem.new()
var _work := WorkSession.new()
var _life := RunLifecycle.new()
var last_round_statement: Dictionary = {}

var queued_boost: bool:
	get:
		return _work.queued_boost
	set(value):
		_work.queued_boost = value

var queued_cloud: bool:
	get:
		return _work.queued_cloud
	set(value):
		_work.queued_cloud = value

var last_session_summary: Dictionary:
	get:
		return _work.last_session_summary
	set(value):
		_work.last_session_summary = value

var _work_running: bool:
	get:
		return _work.work_running
	set(value):
		_work.work_running = value

var _session_cash_start: float:
	get:
		return _work.session_cash_start
	set(value):
		_work.session_cash_start = value

var _round_end_pending: bool:
	get:
		return _life.round_end_pending
	set(value):
		_life.round_end_pending = value

var _settling_victory: bool:
	get:
		return _life.settling_victory
	set(value):
		_life.settling_victory = value
var _subscriptions_cache: Array = []
var _subscriptions_dirty: bool = true

var _action_counter: int:
	get:
		return _work.action_counter
	set(value):
		_work.action_counter = value

var _work_tick: int:
	get:
		return _work.work_tick
	set(value):
		_work.work_tick = value

var _auto_arrange_signature: String = ""


func _ready() -> void:
	pass


# --- Test seams --------------------------------------------------------------
# Deliberate public surface onto internals that tests otherwise have to reach
# into by underscore-prefixed name. Kept together and named `debug_*`/system
# accessors so RunLifecycle/WorkSession/SimulationPreview/MarketService only
# have to move what is behind them, rather than hunt down every test that
# poked a private field directly.

func compute_system() -> ComputeSystem:
	return _compute_system


func heat_system() -> HeatSystem:
	return _heat_system


func economy_system() -> EconomySystem:
	return _economy_system


func job_system() -> JobSystem:
	return _job_system


func upgrade_system() -> UpgradeSystem:
	return _upgrade_system


func perk_system() -> PerkSystem:
	return _perk_system


func ascension_system() -> AscensionSystem:
	return _ascension_system


func achievement_system() -> AchievementSystem:
	return _achievement_system


func demand_system() -> DemandSystem:
	return _demand_system


func event_system() -> EventSystem:
	return _event_system


func progression_system() -> ProgressionSystem:
	return _progression_system


func board_system() -> BoardSystem:
	return _board_system


func debug_collect_subscriptions() -> Array:
	return _collect_subscriptions()


func debug_invalidate_subscriptions() -> void:
	_invalidate_subscriptions()


func debug_finish_prompt(result: Dictionary) -> void:
	_finish_prompt(result)


func debug_end_session(reason: String) -> void:
	_end_session(reason)


func debug_end_round() -> void:
	_end_round()


func debug_end_run(victory: bool, outcome: String = "") -> void:
	_end_run(victory, outcome)


func debug_settle_reputation(completed: Array, failed: Array) -> float:
	return _settle_reputation(completed, failed)


func debug_apply_cloud_burst() -> bool:
	return _apply_cloud_burst()


func debug_present_angel_offers() -> void:
	_present_angel_offers()


func debug_expire_status_effects() -> void:
	_expire_status_effects()


func debug_set_work_running(value: bool) -> void:
	_work_running = value


func debug_set_round_end_pending(value: bool) -> void:
	_round_end_pending = value


func debug_round_end_pending() -> bool:
	return _round_end_pending


func reset_session_ephemerals() -> void:
	_work.reset()
	_auto_arrange_signature = ""


func ensure_job_board() -> void:
	_life.ensure_job_board(self)


func repair_after_load() -> void:
	_life.repair_after_load(self)


func _ensure_job_offers() -> void:
	_life._ensure_job_offers(self)


## Stable per work session rather than per prompt, which would otherwise reroll
## the board mid-round.
func _board_stamp() -> String:
	return _life._board_stamp(self)


## Refreshes the job board when in ROUND_PREP. Safe for UI to call on tab open.
func ensure_job_offers() -> void:
	_life.ensure_job_offers(self)


func reset_run(p_seed: int = 0, difficulty_override: String = "") -> void:
	_life.reset_run(self, p_seed, difficulty_override)


## Settles the run into its location. A location is a chapter, not a purchase:
## its rent, floor space and environmental cooling replace the defaults once,
## at the start, rather than being added to whatever was already there.
## `grant_starter_rig` is only turned off by tests that are measuring the room
## itself — its cooling, its floor space, its shelves — where the machine the
## room comes with would be counted as part of the answer.
func apply_run_location(state: RunState, location_id: String, grant_starter_rig: bool = true) -> void:
	_life.apply_run_location(self, state, location_id, grant_starter_rig)


## The machine the room comes with. Contracts are sized against the rig a
## location expects rather than against whatever the player happens to own, so a
## run that starts in the warehouse on a second-hand laptop would be handed work
## a thousand times beyond it.
func _grant_location_starter_rig(state: RunState, stats: Dictionary) -> void:
	_life._grant_location_starter_rig(self, state, stats)


## Racks the machines earned through the permanent starting-rig unlock ladder.
## A fresh run is otherwise a fresh game from the start — nothing a previous run
## bought arrives — so this is the one place hardware crosses runs, and only
## because a pick was spent on it after beating the whole campaign.
##
## Free of charge but not of floor space: a small room racks what fits, and the
## call from `advance_to_next_chapter` racks the rest once a bigger room opens.
## That second call is why a rung already standing is skipped rather than
## installed again.
func _install_permanent_rig() -> void:
	_life._install_permanent_rig(self)


func start_run(p_seed: int = 0, difficulty_override: String = "") -> void:
	_life.start_run(self, p_seed, difficulty_override)


## Opens a fresh round: a clean prompt counter, a new contract board, and the
## Market open. Nothing carries over from the last round except what the player
## owns, because a round only ends once its contracts have all resolved.
func _begin_round() -> void:
	_life._begin_round(self)


func accept_job(job_id: String) -> bool:
	return _life.accept_job(self, job_id)


## How loaded the round's slate is relative to its tightest deadline.
## Pass an offer to preview the load if that offer were also accepted.
## ratio 1.0 means the slate needs exactly every prompt its tightest deadline
## allows. Parallel lanes do not make the slate lighter — they share one batch —
## so throughput is measured against the rig's rate either way.
func queue_load_info(extra_offer: Dictionary = {}) -> Dictionary:
	return SimulationPreview.queue_load_info(self, extra_offer)


## Live picture of the round's costs: the flat charges that fall due when the
## round ends, and the metered ones that have already been paid prompt by prompt.
## Rent does not grow with a long round; the power bill does.
func cost_forecast() -> Dictionary:
	return SimulationPreview.cost_forecast(self)


## What this round still owes and therefore what is genuinely free to spend, so
## the player is never surprised by a bill they had already spent.
func bills_outlook() -> Dictionary:
	return SimulationPreview.bills_outlook(self)


## Warning text for a purchase that would leave this round's bills unpayable.
func purchase_bill_warning(cost: float) -> String:
	return SimulationPreview.purchase_bill_warning(self, cost)


## Cooling an upgrade brings with it, for previewing a purchase.
func _cooling_from_effects(effects: Array) -> float:
	return SimulationPreview.cooling_from_effects(effects)


## Whether cooling can keep up with a given power draw, and by how much. Used to
## warn the player before they buy hardware their space cannot cool.
func heat_outlook(extra_power: float = 0.0, extra_cooling: float = 0.0) -> Dictionary:
	return SimulationPreview.heat_outlook(self, extra_power, extra_cooling)


## Warning text for a hardware purchase that cooling could not keep up with.
func upgrade_heat_warning(upgrade_id: String) -> String:
	return SimulationPreview.upgrade_heat_warning(self, upgrade_id)


## The cooling on sale right now that would close a shortfall, named and
## counted. A warning that only says "not enough cooling" leaves the player
## hunting the Market for a shelf that may look empty; this says what to buy.
func cooling_remedy(shortfall: float) -> String:
	return SimulationPreview.cooling_remedy(self, shortfall)


func queue_capacity_cap() -> float:
	return SimulationPreview.queue_capacity_cap()


## Offers may load the queue up to (or slightly over) throughput capacity,
## but not so far past it that the deadline is hopeless.
func can_accept_offer(job_id: String) -> bool:
	return _life.can_accept_offer(self, job_id)


func can_start_work() -> bool:
	return _work.can_start_work(self)


func is_work_running() -> bool:
	return _work.is_work_running(self)


## How many contracts the rig works at once, and which ones a burn would advance.
func job_slots() -> int:
	return ComputeSystem.job_slots(run_state)


func burn_lanes() -> Array:
	return _job_system.burn_lane_jobs(run_state)


## Prompts spent on the round so far. Open-ended: a round lasts as long as its
## contracts do, so this is a tally rather than a budget.
func prompts_used_this_round() -> int:
	return maxi(0, int(run_state.calendar.get("prompt", 1)) - 1)


## Queues BOOST to fire as soon as work starts. Only allowed pre-session.
func set_queued_boost(enabled: bool) -> void:
	_work.set_queued_boost(self, enabled)


## Queues a cloud burst to fire as soon as work starts. Only allowed pre-session,
## and only once the run has an account to bill it to.
func set_queued_cloud(enabled: bool) -> void:
	_work.set_queued_cloud(self, enabled)


## Opens the Burn Board. Nothing is produced until the player burns a batch:
## from here the session waits on burn_batch / cool_hardware / ship_focused_job.
func start_work() -> void:
	_work.start_work(self)


func _fire_queued_options() -> void:
	_work._fire_queued_options(self)


func start_work_sync() -> Dictionary:
	return _work.start_work_sync(self)


# --- Burn Board actions ------------------------------------------------------

## What BURN TOKENS would produce right now, resolved on a throwaway copy of the
## state so the board screen can show the outcome without causing it.
##
## `burn.heat` is only the pipeline's own stage heat. Every prompt — burn or
## cool — also gains ambient heat from powered-on hardware and loses some to
## cooling capacity (`HeatSystem.process_prompt`), which `run_burn` applies too.
## `total_heat` is the two combined: the number the heat bar will actually move
## by, which is what the UI should show instead of the stage heat alone.
func preview_burn(stage_limit: int = -1) -> Dictionary:
	return SimulationPreview.preview_burn(self, stage_limit)


## The authoritative next-click forecast. Unlike `preview_burn`, this also works
## while accepted work is still queued, before the first BURN has opened the
## session. The throwaway state follows the same preparation order as
## `start_work`: recalculate, promote queued jobs, apply queued surges, burn.
## Nothing touches the live phase, state, RNG counters, signals, trace, or save.
func preview_next_burn(stage_limit: int = -1) -> Dictionary:
	return SimulationPreview.preview_next_burn(self, stage_limit)


func _decorate_burn_outlook(burn: Dictionary, heat_before: float, state: RunState) -> void:
	SimulationPreview._decorate_burn_outlook(burn, heat_before, state)


func _apply_queued_preview_options(state: RunState) -> void:
	SimulationPreview._apply_queued_preview_options(self, state)


## What COOL would actually do to the heat bar right now: the vent, plus the
## same ambient heat/cooling pass a burn prompt gets, since `end_prompt` runs
## either way. This is what makes COOL sometimes barely move the bar — the
## ambient gain can eat most or all of the vent.
func preview_cool() -> Dictionary:
	return SimulationPreview.preview_cool(self)


## Burns one batch through the pipeline, which spends one prompt.
##
## `stage_limit` is how KILL PROCESS lands: the stages that had already fired
## keep their output and the rest of the batch is lost.
func burn_batch(stage_limit: int = -1) -> Dictionary:
	return _work.burn_batch(self, stage_limit)


## Spends a prompt on the hardware rather than the work.
func cool_hardware() -> Dictionary:
	return _work.cool_hardware(self)


## Delivers the focused contract now, finished or not.
func ship_focused_job() -> bool:
	return _work.ship_focused_job(self)


func abandon_focused_job() -> bool:
	return _work.abandon_focused_job(self)


func focus_job(job_id: String) -> bool:
	return _work.focus_job(self, job_id)


## The Burn Board edits whichever workflow is active, so focusing a contract
## points the editor at the pipeline that contract is actually worked through.
## Without this, tuning the board mid-job would quietly edit someone else's.
func _follow_focused_workflow() -> void:
	_work._follow_focused_workflow(self)


func focused_job() -> Dictionary:
	return _work.focused_job(self)


## The contract the machine will boot with when the first BURN opens the
## session: the head of the accepted queue, prepared exactly as `start_work`
## will prepare it. Display only — nothing in the queue is mutated. Empty when
## nothing has been accepted, or once the session is running and `focused_job`
## is the real answer.
func queued_job_preview() -> Dictionary:
	return _work.queued_job_preview(self)


func can_burn() -> bool:
	return _work.can_burn(self)


func board_slots() -> Array:
	return _board_system.slots(run_state)


func owned_modules() -> Array:
	return _board_system.owned_modules(run_state)


func filled_slot_count() -> int:
	return _board_system.filled_slot_count(run_state)


## Slots a contract has taken over are locked only on the workflow that contract
## is being worked through. Editing a different workflow is unconstrained: it is
## not the pipeline the legacy code is sitting in.
func _editing_job() -> Dictionary:
	var job: Dictionary = focused_job()
	if job.is_empty():
		return {}
	var editing_id: String = str(_board_system.active_workflow(run_state).get("id", ""))
	return job if str(job.get("workflow_id", "")) == editing_id else {}


func place_module(module_id: String, slot_index: int) -> bool:
	if not _board_system.place_module(run_state, _editing_job(), module_id, slot_index):
		return false
	_autosave()
	return true


func clear_slot(slot_index: int) -> bool:
	if not _board_system.clear_slot(run_state, _editing_job(), slot_index):
		return false
	_autosave()
	return true


func swap_slots(from_index: int, to_index: int) -> bool:
	if not _board_system.swap_slots(run_state, _editing_job(), from_index, to_index):
		return false
	_autosave()
	return true


## The contract whose constraints the workflow editor should honour: the focused
## one only while its own pipeline is on screen.
func editing_job() -> Dictionary:
	return _editing_job()


## Greedily improves the pipeline by trying each benched module in each usable
## slot and keeping any swap that scores better. Used by the auto-drive and
## offered to the player as a starting point; a human can always do better by
## caring about heat, cash and the contract's rules.
func auto_arrange_board(max_passes: int = 2) -> bool:
	if phase != Phase.IN_ROUND:
		return false
	var job: Dictionary = focused_job()
	if job.is_empty():
		return false
	var slots: Array = _board_system.slots(run_state)
	# Scoring a layout means resolving a burn, so skip the work entirely when
	# neither the modules nor the contract have changed since the last pass.
	var signature: String = "%s|%s|%s" % [
		str(_board_system.owned_modules(run_state)), str(slots), str(job.get("id", ""))
	]
	if signature == _auto_arrange_signature:
		return false
	var changed: bool = false
	for _pass in range(max_passes):
		var best_score: float = _layout_score(job)
		var best_slot: int = -1
		var best_module: String = ""
		for module_id in _board_system.owned_modules(run_state):
			if str(module_id) in slots:
				continue
			for index in range(slots.size()):
				if not _board_system.is_slot_usable(run_state, job, index):
					continue
				var displaced: String = str(slots[index])
				slots[index] = str(module_id)
				var score: float = _layout_score(job)
				slots[index] = displaced
				if score > best_score + 0.001:
					best_score = score
					best_slot = index
					best_module = str(module_id)
		if best_slot < 0:
			break
		slots[best_slot] = best_module
		changed = true
	_auto_arrange_signature = "%s|%s|%s" % [
		str(_board_system.owned_modules(run_state)), str(slots), str(job.get("id", ""))
	]
	if changed:
		_autosave()
	return changed


## Scores a layout by the cash it would earn per prompt spent, which is the thing
## that actually keeps a run alive. Everything else folds into that: bugs shrink
## the fee, tokens and quality set how many burns delivery takes, and heat adds
## the cooling prompts needed to survive them.
func _layout_score(job: Dictionary) -> float:
	var preview: Dictionary = preview_burn()
	if not preview.get("ok", false):
		return -MAX_ESTIMATED_BURNS
	if float(preview.get("cost", 0.0)) > float(run_state.economy.get("cash", 0.0)):
		return -MAX_ESTIMATED_BURNS

	# A contract needs its tokens and its quality gate, so the binding constraint
	# is whichever is further away. Quality past the threshold buys nothing.
	var remaining: float = maxf(1.0, float(job.get("tokens_remaining", 1.0)))
	var burns: float = remaining / maxf(1.0, float(preview.get("progress_tokens", 0.0)))
	var quality_gap: float = maxf(
		0.0, float(job.get("quality_threshold", 0.0)) - float(job.get("quality", 0.0))
	)
	if quality_gap > 0.0:
		var quality_per_burn: float = float(preview.get("quality", 0.0))
		burns = maxf(burns, (
			quality_gap / quality_per_burn if quality_per_burn > 0.0 else MAX_ESTIMATED_BURNS
		))
	burns = minf(maxf(1.0, burns), MAX_ESTIMATED_BURNS)

	# `total_heat` is the authoritative figure the burn would actually put on
	# the bar — ambient gain and cooling already netted against each other by
	# HeatSystem — rather than the stage's own heat re-derived by hand against
	# a cooling factor this scorer used to ignore entirely.
	var net_heat: float = maxf(0.0, float(preview.get("total_heat", 0.0)))
	var prompts: float = burns * (
		1.0 + net_heat / maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))
	)

	# What the client will actually pay for what this pipeline delivers.
	var known: float = float(preview.get("bugs_added", 0)) * burns + float(job.get("known_bugs", 0))
	var hidden: float = float(preview.get("hidden_added", 0)) * burns + float(job.get("hidden_bugs", 0))
	var fee: float = float(job.get("reward", 0.0))
	fee *= maxf(0.3, 1.0 - 0.08 * known)
	fee *= maxf(0.25, 1.0 - 0.06 * hidden)

	# Metered running costs, not just power: a cloud-heavy layout's per-prompt
	# bill is what `cost_forecast` already tracks for the bills screen, so the
	# same figure — power and cloud metering both — is what should be scored.
	var operating_per_prompt: float = float(cost_forecast().get("operating_per_prompt", 0.0))
	# Pipeline stage costs are only paid on a burn, but the metered power and
	# cloud bills land on every prompt the run spends — cooling prompts
	# included. Charging them per burn alone made hot layouts look cheaper
	# than the cooling they force.
	var outgoings: float = burns * float(preview.get("cost", 0.0)) + prompts * operating_per_prompt
	return (fee - outgoings) / prompts


# --- Ascension ----------------------------------------------------------

func infrastructure_tier() -> int:
	return _ascension_system.infrastructure_tier(run_state, ContentDatabase)


func ascension_active() -> bool:
	return _ascension_system.is_active(run_state)


func ascension_active_contract() -> Dictionary:
	return _ascension_system.active_contract(run_state, ContentDatabase)


func ascension_progress() -> Dictionary:
	return _ascension_system.progress(run_state, ContentDatabase)


## Where the run stands against the contract of the location it is being played
## in, for the readouts that have to say so without re-deriving any of the rules.
func ascension_summary() -> Dictionary:
	return _ascension_system.summary(run_state, ContentDatabase)


## The contract this run is being played for.
func ascension_boss_contract() -> Dictionary:
	return _ascension_system.location_contract(run_state, ContentDatabase)


## The location's boss has cleared: the game is beaten. The run is not thrown away
## with it. The round it happened in is settled properly — the work pays out, the
## bills land, the angels call if the rent cleared — and the phase that would have
## come next is remembered, so continuing into endless mode resumes from a clean
## round boundary instead of the middle of a burn.
func _reach_victory(contract: Dictionary) -> void:
	_life.reach_victory(self, contract)


## The investor pays for the contract on delivery, and pays more for delivering
## early: every round left on the deadline is worth another round's rent. Rent is
## the scale because it is the one figure that already tracks the chapter — the
## same formula is pocket money in the bedroom and a fortune on the moon, without
## a table of per-location numbers to keep in step.
func _pay_ascension_bonus(contract: Dictionary) -> void:
	_life._pay_ascension_bonus(self, contract)


## Beating the boss retires the chapter and opens the next one. Guarded once-only
## because `_end_run`'s "ascended" branch settles the same victory from the other
## direction, and a location must not be completed twice.
##
## The profile records the clear, but the campaign selection stays put: the win
## continues in place through `advance_to_next_chapter`, and a run started fresh
## afterwards is a fresh game from the bedroom, not a resume.
func _complete_run_location() -> void:
	_life._complete_run_location(self)


## Whether the run is being played in the campaign's last location — the only
## place a victory is the end of the game rather than of a chapter, and so the
## only place permanent rewards are paid out.
func _run_is_final_chapter() -> bool:
	return _life._run_is_final_chapter(self)


## The location this victory opened up, empty if the run was played in the last
## chapter there is.
func next_location_unlocked() -> String:
	return _life.next_location_unlocked(self)


## True while a victory is being settled: the bills landing in that window cannot
## take the win back, and no overlay should open in front of the verdict.
func is_settling_victory() -> bool:
	return _life.is_settling_victory()


## Carries a won run on rather than starting over. Everything the run owns stays
## put; from here the calendar is behind it and the costs climb every round, so
## the tail lasts exactly as long as the build can hold it up.
##
## Only the last chapter offers this. A mid-campaign win is a level-up — the next
## location is the continuation, and an endless tail there would just be a bigger
## bedroom. The tail exists for the run with nowhere further up to go.
func continue_after_victory() -> bool:
	return _life.continue_after_victory(self)


## Whether the run has already beaten a Tier 3 contract and chosen to carry on.
func in_post_victory() -> bool:
	return _life.in_post_victory(self)


## Moves a mid-campaign win into the next chapter as the same business. The
## angel's goal is the end of a chapter, not the end of the game: cash, perks,
## modules, workflows, upgrades and reputation all carry forward — what changes
## is the room, the rent, and the contract the run is measured against, which
## is the next location's bigger one. Only the last chapter has no next room;
## its continuation is `continue_after_victory`.
func advance_to_next_chapter() -> bool:
	return _life.advance_to_next_chapter(self)


# --- Workflows ----------------------------------------------------------

func workflows() -> Array:
	return _board_system.workflows(run_state)


func workflow_count() -> int:
	return _board_system.workflow_count(run_state)


func workflow_capacity() -> int:
	return _board_system.workflow_capacity(run_state, ContentDatabase)


func active_workflow_index() -> int:
	return _board_system.active_workflow_index(run_state)


func active_workflow() -> Dictionary:
	return _board_system.active_workflow(run_state)


## Points the workflow editor at another pipeline. Purely a view change: which
## workflow a contract burns through is set by its assignment.
func set_active_workflow(index: int) -> bool:
	if not _board_system.set_active_workflow(run_state, index):
		return false
	_autosave()
	return true


func create_workflow(name: String = "") -> Dictionary:
	var created: Dictionary = _board_system.create_workflow(run_state, name, ContentDatabase)
	if created.is_empty():
		return {}
	_autosave()
	return created


func rename_workflow(index: int, name: String) -> bool:
	if not _board_system.rename_workflow(run_state, index, name):
		return false
	_autosave()
	return true


func delete_workflow(index: int) -> bool:
	if not _board_system.delete_workflow(run_state, index):
		return false
	_autosave()
	return true


## The pipeline a contract will actually be worked through, which is what the
## Burn Board shows rather than whatever the editor was last pointed at.
func workflow_for_job(job: Dictionary) -> Dictionary:
	return _board_system.workflow_for_job(run_state, job)


func assign_workflow(job_id: String, workflow_id: String) -> bool:
	if not _job_system.assign_workflow(run_state, job_id, workflow_id):
		return false
	_autosave()
	return true


## How every workflow the run owns scores against one contract's demands, in
## editor order, for the assignment picker.
func workflow_matches(job: Dictionary) -> Array:
	var matches: Array = []
	for workflow in _board_system.workflows(run_state):
		matches.append(_board_system.workflow_match(run_state, job, workflow))
	return matches


## What a contract is asking for, judged against the workflow it is assigned.
func job_demands(job: Dictionary) -> Array:
	return _board_system.demand_report(
		job, _board_system.slots_for_job(run_state, job), _board_system.blocked_slots(job)
	)


func get_module_description(module_id: String) -> String:
	var module: ModuleDefinition = ContentDatabase.get_module(module_id)
	if module == null:
		return ""
	return ExpressionEvaluator.new().render_template(module.description_template, module.parameters)


## Seeded from the run and the exact prompt, so a preview and the burn it
## previewed roll the same numbers.
func _burn_rng() -> DeterministicRng:
	return _work.burn_rng(self)


## Folds any job that finished this prompt into the contract's quality average,
## exactly once each. Called both mid-session (so the ordinary evaluate/expire
## path always sees settled quality) and again from `_end_session` for jobs
## shipped or abandoned without going through `_finish_prompt` — the guard
## flag is what keeps a job from being counted by both.
func _record_completed_quality(run_state: RunState) -> void:
	_work.record_completed_quality(self, run_state)


## Bookkeeping shared by every action that consumes a prompt.
func _finish_prompt(result: Dictionary) -> void:
	_work.finish_prompt(self, result)


## Shipping or abandoning the last live contract ends the round there and then,
## without spending another prompt on it.
func _settle_if_resolved() -> void:
	_work._settle_if_resolved(self)


## One burn or cool is one prompt. Prompts are not rationed — the round runs for
## as long as its contracts do — but every one of them ages the deadlines and
## meters the power.
func _advance_prompt(result: Dictionary) -> void:
	_work._advance_prompt(self, result)


## A round ends when there is nothing left on the books, and only then. Rent can
## no longer interrupt a contract halfway through, because the bills wait for the
## work to finish rather than the other way round.
func _session_stop_reason(result: Dictionary) -> String:
	return _work._session_stop_reason(result)


func _execute_tick() -> Dictionary:
	return _work._execute_tick(self)


## Settles the round. Every contract taken this round is resolved here — nothing
## carries into the next round, which is what makes "the round is over" mean the
## same thing every time and lets the bills follow the work rather than cut
## across it.
func _end_session(reason: String) -> void:
	_work.end_session(self, reason)


## What the round did to the run's standing, and the reason it did it. A missed
## deadline still costs a flat two per contract; delivered work is now paid in
## reputation by how good it was, so clearing a client's bar by a mile is worth
## more than scraping under it and taking the reduced fee.
func _settle_reputation(completed: Array, failed: Array) -> float:
	return _work.settle_reputation(self, completed, failed)


## Both surges last one batch, so a second press in the same prompt is refused
## rather than stacked.
func boost() -> bool:
	return _work.boost(self)


func cloud_burst() -> bool:
	return _work.cloud_burst(self)


## Cloud is a capability the run buys, not one it starts with. Without the
## account there is nobody to rent capacity from and nobody to bill.
func cloud_enabled() -> bool:
	return _work.cloud_enabled(self)


func cloud_burst_multiplier() -> float:
	return _work.cloud_burst_multiplier(self)


func _cloud_burst_multiplier_for(state: RunState) -> float:
	return _work.cloud_burst_multiplier_for(self, state)


## Rented tokens are metered, and the provider charges for the privilege of
## turning the tap on at all. The flat fee is what makes an early burst a real
## decision instead of loose change.
func cloud_burst_cost() -> float:
	return _work.cloud_burst_cost(self)


func _cloud_burst_cost_for(state: RunState) -> float:
	return _work.cloud_burst_cost_for(self, state)


func can_afford_cloud_burst() -> bool:
	return _work.can_afford_cloud_burst(self)


## Whether this prompt's batch is already running hot off a boost.
func boost_engaged() -> bool:
	return _work.boost_engaged(self)


func cloud_engaged() -> bool:
	return _work.cloud_engaged(self)


func _apply_boost() -> void:
	_work._apply_boost(self)


## Rents capacity for one prompt. Cash is deducted immediately so the player
## sees the cost land on the balance sheet, not as a hidden end-of-round liability.
func _apply_cloud_burst() -> bool:
	return _work._apply_cloud_burst(self)


## Snapshot of the round just finished, for the debrief screen. Every contract
## the round took is in one of the two lists, so the headline can never claim a
## success the player did not have.
func _build_session_summary(
	completed_jobs: Array, failed_jobs: Array, reward: float, reason: String
) -> void:
	_work._build_session_summary(self, completed_jobs, failed_jobs, reward, reason)


## Whether the contract is further behind than the year has left to give it. A
## run three quarters through the calendar with a quarter of the burn done is
## losing, however well the individual round went, and the debrief says so.
func _behind_on_contract() -> bool:
	return _work._behind_on_contract(self)


## Takes one of the angel's offers. Everything on the table is free, so the only
## question is which one, and the draft closes either way.
func accept_offer(offer_type: String, offer_id: String) -> bool:
	return _life.accept_offer(self, offer_type, offer_id)


## Walks away with nothing. Always allowed: a full board and a bad offer is a
## real situation.
func decline_offers() -> void:
	_life.decline_offers(self)


## Spends the draft's one pick and closes it.
func _spend_draft_pick(_offer_type: String, _offer_id: String) -> void:
	_life._spend_draft_pick(self, _offer_type, _offer_id)


func _accept_perk(perk_id: String) -> bool:
	return _life._accept_perk(self, perk_id)


func collect_perk(perk_id: String) -> bool:
	if not _perk_system.collect_perk(run_state, perk_id, ContentDatabase):
		return false
	_invalidate_subscriptions()
	EventBus.emit_event(EventBus.EVENT_PERK_ACQUIRED, {"perk_id": perk_id})
	_dispatch_perk_acquired(perk_id)
	_board_system.ensure_board(run_state, ContentDatabase)
	_compute_system.recalculate(run_state, effect_resolver, _collect_subscriptions(), rng)
	_autosave()
	return true


func equip_perk(perk_id: String) -> bool:
	if not _perk_system.equip_perk(run_state, perk_id, ContentDatabase):
		return false
	_recalculate_after_perk_loadout_change()
	return true


func bench_perk(perk_id: String) -> bool:
	if not _perk_system.bench_perk(run_state, perk_id, ContentDatabase):
		return false
	_recalculate_after_perk_loadout_change()
	return true


func swap_perk(out_id: String, in_id: String) -> bool:
	if not _perk_system.swap_perk(run_state, out_id, in_id, ContentDatabase):
		return false
	_recalculate_after_perk_loadout_change()
	return true


func can_equip_perk(perk_id: String) -> bool:
	return _perk_system.can_equip(run_state, perk_id, ContentDatabase)


func perk_equip_block_reason(perk_id: String) -> String:
	return _perk_system.equip_block_reason(run_state, perk_id, ContentDatabase)


func perk_bench_block_reason(perk_id: String) -> String:
	return _perk_system.bench_block_reason(run_state, perk_id, ContentDatabase)


func can_bench_perk(perk_id: String) -> bool:
	return _perk_system.can_bench(run_state, perk_id, ContentDatabase)


func perk_swap_block_reason(out_id: String, in_id: String) -> String:
	return _perk_system.swap_block_reason(run_state, out_id, in_id, ContentDatabase)


func can_swap_perk(out_id: String, in_id: String) -> bool:
	return _perk_system.can_swap(run_state, out_id, in_id, ContentDatabase)


func _recalculate_after_perk_loadout_change() -> void:
	_invalidate_subscriptions()
	_board_system.ensure_board(run_state, ContentDatabase)
	_compute_system.recalculate(run_state, effect_resolver, _collect_subscriptions(), rng)
	_autosave()


## Drafts a pipeline module. Unlike a perk it changes nothing on its own: it has
## to be placed on the board to do anything, and on a full board that means
## taking something else out.
func _accept_module(module_id: String) -> bool:
	return _life._accept_module(self, module_id)


## Pickup effects: loans, permanent liabilities, anything the player owns the
## moment they touch the card. Fired once per run, however many times the perk
## is collected, benched, or equipped again.
func _dispatch_perk_acquired(perk_id: String) -> void:
	var perk := ContentDatabase.get_perk(perk_id)
	if perk == null:
		return
	if PerkSystem.liability_taken(run_state, perk_id):
		return
	var subs: Array = []
	for sub in perk.subscriptions:
		if str(sub.get("event", "")) != "perk.acquired":
			continue
		var copy: Dictionary = sub.duplicate(true)
		copy["source_id"] = perk.id
		copy["parameters"] = perk.parameters.duplicate(true)
		subs.append(copy)
	if subs.is_empty():
		return
	PerkSystem.record_liability(run_state, perk_id)
	effect_resolver.begin_action("perk.acquired.%s" % perk_id)
	var mod_ctx := ModifierContext.new("perk.acquired", run_state)
	mod_ctx.rng = rng.derive("perk.acquired")
	effect_resolver.dispatch("perk.acquired", mod_ctx, subs)
	# A pickup effect can spawn a permanent status, which is itself a subscriber.
	_invalidate_subscriptions()


## Market operations (buying, selling, and the "is the counter open" gate
## they share) are pulled out into `MarketService`; these stay as the public
## facade every screen already calls.

func can_buy_upgrade(upgrade_id: String) -> bool:
	return MarketService.can_buy_upgrade(self, upgrade_id)


func buy_upgrade(upgrade_id: String) -> bool:
	return MarketService.buy_upgrade(self, upgrade_id)


func market_open() -> bool:
	return MarketService.market_open(self)


func hardware_sale_reason(hardware_key: String) -> String:
	return MarketService.hardware_sale_reason(self, hardware_key)


func hardware_sale_refund(hardware_key: String) -> float:
	return MarketService.hardware_sale_refund(self, hardware_key)


func can_sell_hardware(hardware_key: String) -> bool:
	return MarketService.can_sell_hardware(self, hardware_key)


func sell_hardware(hardware_key: String) -> bool:
	return MarketService.sell_hardware(self, hardware_key)


func set_tuning(key: String, value: float) -> void:
	if tuning.has(key):
		tuning[key] = value


func set_advertising(amount: float) -> void:
	run_state.business["advertising"] = maxf(0.0, amount)
	_demand_system.refresh_demand(run_state)
	_autosave()




func get_perk_description(perk_id: String) -> String:
	var perk := ContentDatabase.get_perk(perk_id)
	if perk == null:
		return ""
	return _render_perk(perk)


## How many perks the build holds against its ceiling, for screens that need to
## warn the player that picks are running out.
func perk_capacity() -> Dictionary:
	var active: int = run_state.build["perks"].size()
	var collected: int = run_state.build.get("perk_inventory", []).size()
	var cap: int = _perk_system.perk_capacity(run_state, ContentDatabase)
	return {
		"owned": active,
		"active": active,
		"collected": collected,
		"cap": cap,
	}


func get_synergies() -> Array[String]:
	return _perk_system.detect_synergies(run_state, ContentDatabase)


func query_effect_breakdown(target_path: String, chain_id: String = "") -> Dictionary:
	return effect_resolver.query_trace_breakdown(target_path, chain_id)


## The only draft there is: the round's free offer, one pick and out.

func _draft_state() -> Dictionary:
	return _life._draft_state(self)


func _angel_draw_rng() -> DeterministicRng:
	return _life._angel_draw_rng(self)


func angel_reroll_cost() -> float:
	return _life.angel_reroll_cost(self)


func can_reroll_angel() -> bool:
	return _life.can_reroll_angel(self)


func reroll_angel_offers() -> bool:
	return _life.reroll_angel_offers(self)


func _location_base_job_reward() -> float:
	return _life._location_base_job_reward(self)


func _redraw_angel_offers() -> void:
	_life._redraw_angel_offers(self)


## The round's angel draft. Everything here is free: somebody with more money
## than sense is handing out modules and perks. Anything with a price tag is sold
## on the Market tab instead, where the player goes looking for it.
func _present_angel_offers() -> void:
	_life.present_angel_offers(self)


## Which draft is on the table, so a screen can title itself.
func draft_kind() -> String:
	return _life.draft_kind(self)


## Picks still to spend on the draft. An angel draft is always worth exactly one.
func draft_picks_remaining() -> int:
	return _life.draft_picks_remaining(self)


## Closes the round: the bills land, the rig cools off, and — if the rent
## cleared — the angels call. Reached only once every contract has resolved, so
## the player is never billed in the middle of a job.
func _end_round() -> void:
	_life.end_round(self)


## Ages the run's status effects by one round and drops the ones that have run
## out. A status that declares no `rounds` is permanent by design — that is what
## a perk's standing bonus is — so only the ones with a stated duration expire.
## Without this, an event that hangs a per-prompt cost on the rig (a fan dying,
## an incident war room) charged it for the rest of the run.
func _expire_status_effects() -> void:
	_life.expire_status_effects(self)


## Each round past the twelfth, rent and power creep up 8%: the same rig that
## coasted through the final act starts to strain again, keeping an endless
## run a real challenge instead of a victory lap.
func _escalate_endless_costs() -> void:
	_life._escalate_endless_costs(self)


## The last round the contract can be finished in. A won run carrying on into
## endless mode is past its deadline by definition, so the calendar length is
## used there instead.
func _contract_deadline_round() -> int:
	return _life._contract_deadline_round(self)


## Rounds left before the contract's deadline, this round included.
func rounds_remaining() -> int:
	return _life.rounds_remaining(self)


func _after_angel_round() -> void:
	_life.after_angel_round(self)


## `outcome` names how the run ended. "ascended" is the only way to win: an
## Ascension Contract completed. "retired" survives only for saves and profiles
## written before overtime existed — the calendar no longer ends a run, so
## nothing reaches it any more. Left blank it falls back to the old two-state
## behaviour ("ascended" on victory, "lost" otherwise), which is what the batch
## runner, screenshot tool, and older tests still call.
func _end_run(victory: bool, outcome: String = "") -> void:
	_life.end_run(self, victory, outcome)


## Lifetime counters and end-of-run awards, folded in once per run whatever
## finally closes it. A won run can carry on into endless and end again later, so
## banking on every ending would count the same run's legacy twice.
##
## Lifetime counters are folded in before the awards are judged, so an achievement
## that asks for ten losses can be earned by the tenth loss rather than the
## eleventh.
func _bank_run_legacy(victory: bool) -> void:
	_life._bank_run_legacy(self, victory)


## The permanent unlocks on offer after beating the campaign. Picks are rare —
## one batch per completion — so the debrief lays out every area still open
## (rig, cooling, cloud, cash, workflows, board width) and the player chooses
## which to boost permanently, rather than being dealt three at random.
func debrief_choices() -> Array:
	return _life.debrief_choices()


func spend_debrief_pick(unlock_id: String) -> bool:
	return _life.spend_debrief_pick(unlock_id)


func _invalidate_subscriptions() -> void:
	_subscriptions_dirty = true


func _collect_subscriptions() -> Array:
	if not _subscriptions_dirty:
		return _subscriptions_cache
	var subs: Array = []
	for perk_id in run_state.build["perks"]:
		var perk := ContentDatabase.get_perk(str(perk_id))
		if perk != null:
			for sub in perk.subscriptions:
				var copy: Dictionary = sub.duplicate(true)
				copy["source_id"] = perk.id
				copy["parameters"] = perk.parameters.duplicate(true)
				subs.append(copy)
	# A completed set pays out for itself. Without this a synergy was a caption
	# on the build screen telling the player something had happened when nothing
	# had.
	for synergy in _perk_system.active_synergies(run_state, ContentDatabase):
		for sub in synergy.get("subscriptions", []):
			if sub is Dictionary:
				var synergy_sub: Dictionary = sub.duplicate(true)
				synergy_sub["source_id"] = "synergy.%s" % str(synergy.get("name", "set"))
				synergy_sub["parameters"] = synergy.get("parameters", {})
				subs.append(synergy_sub)
	for status in run_state.build["status_effects"]:
		if status is Dictionary:
			for sub in status.get("subscriptions", []):
				if sub is Dictionary:
					var copy: Dictionary = sub.duplicate(true)
					if not copy.has("parameters"):
						copy["parameters"] = status.get("parameters", {})
					if not copy.has("source_id"):
						copy["source_id"] = str(status.get("source_perk", status.get("id", "status")))
					subs.append(copy)
	_subscriptions_cache = subs
	_subscriptions_dirty = false
	return subs


func _render_perk(perk: PerkDefinition) -> String:
	return ExpressionEvaluator.new().render_template(perk.description_template, perk.parameters)


const PHASE_NAMES := ["IDLE", "ROUND_PREP", "IN_ROUND", "ROUND_END", "ANGEL_ROUND", "RUN_END"]


func _phase_name(value: int) -> String:
	return PHASE_NAMES[value] if value >= 0 and value < PHASE_NAMES.size() else "IDLE"


func _autosave() -> void:
	if not autosave_enabled:
		return
	SaveManager.save_run(run_state, _phase_name(phase), run_seed, pending_choices, _round_end_pending)


func load_saved_run() -> bool:
	return _life.load_saved_run(self)


## Angel drafts used to offer `type: operation`. accept_offer only understands
## perk / module, so a save taken on that wording would present a card nothing
## could take.
func _migrate_pending_choices() -> void:
	_life._migrate_pending_choices(self)


func _phase_from_name(name: String) -> int:
	match name:
		"ROUND_PREP", "JOB_SELECT": return Phase.ROUND_PREP
		"IN_ROUND", "IN_JOB": return Phase.IN_ROUND
		"ROUND_END", "MONTH_END": return Phase.ROUND_END
		"ANGEL_ROUND": return Phase.ANGEL_ROUND
		# Saves written before the angel draft was split out of the market.
		"UPGRADE_CHOICE": return Phase.ANGEL_ROUND
		"RUN_END": return Phase.RUN_END
		_: return Phase.IDLE


func is_running() -> bool:
	return phase != Phase.IDLE and phase != Phase.RUN_END
