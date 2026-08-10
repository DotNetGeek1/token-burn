extends Node

## Global event bus for simulation lifecycle and domain events.
##
## Event names are typed-signal vocabulary duplicated as strings for
## `emit_event`/`EffectResolver.dispatch`: these constants are the one place
## that vocabulary is spelled, so a typo at a call site fails to compile
## instead of silently mismatching the string this file matches against.

const EVENT_RUN_STARTED := "run.started"
const EVENT_ROUND_STARTED := "round.started"
const EVENT_JOB_OFFERED := "job.offered"
const EVENT_JOB_ACCEPTED := "job.accepted"
const EVENT_JOB_STARTED := "job.started"
const EVENT_TOKENS_GENERATED := "tokens.generated"
const EVENT_TOKENS_CONSUMED := "tokens.consumed"
const EVENT_QUALITY_CALCULATED := "quality.calculated"
const EVENT_BUG_GENERATED := "bug.generated"
const EVENT_JOB_COMPLETED := "job.completed"
const EVENT_JOB_FAILED := "job.failed"
const EVENT_REWARD_CALCULATED := "reward.calculated"
const EVENT_BILL_DUE := "bill.due"
const EVENT_UPGRADE_PURCHASED := "upgrade.purchased"
const EVENT_HARDWARE_SOLD := "hardware.sold"
const EVENT_PERK_ACQUIRED := "perk.acquired"
const EVENT_OPERATION_ACQUIRED := "operation.acquired"
const EVENT_HEAT_THRESHOLD_CROSSED := "heat.threshold_crossed"
const EVENT_ACHIEVEMENT_UNLOCKED := "achievement.unlocked"
const EVENT_RUN_ENDED := "run.ended"

## Not fired through `emit_event`/`EventBus` — `EffectResolver.dispatch()` is
## called with these directly from `JobSystem`/`ComputeSystem` — but the same
## typo risk applies, so they get the same treatment here.
const EVENT_PROMPT_STARTED := "prompt.started"
const EVENT_ROUND_ENDED := "round.ended"
const EVENT_COMPUTE_RECALCULATE := "compute.recalculate"

signal run_started
signal round_started
signal job_offered(job_id: String)
signal job_accepted(job_id: String)
signal job_started(job_id: String)
signal tokens_generated(amount: float)
signal tokens_consumed(amount: float)
signal quality_calculated(value: float)
signal bug_generated
signal job_completed(job_id: String)
signal job_failed(job_id: String)
signal reward_calculated(amount: float)
signal bill_due(bill_type: String, amount: float)
signal upgrade_purchased(upgrade_id: String)
signal hardware_sold(hardware_key: String)
signal perk_acquired(perk_id: String)
signal operation_acquired(operation_id: String)
signal heat_threshold_crossed(level: float)
signal achievement_unlocked(achievement_id: String)
signal run_ended(victory: bool)


func emit_event(event_name: String, payload: Dictionary = {}) -> void:
	match event_name:
		EVENT_RUN_STARTED:
			run_started.emit()
		EVENT_ROUND_STARTED:
			round_started.emit()
		EVENT_JOB_OFFERED:
			job_offered.emit(payload.get("job_id", ""))
		EVENT_JOB_ACCEPTED:
			job_accepted.emit(payload.get("job_id", ""))
		EVENT_JOB_STARTED:
			job_started.emit(payload.get("job_id", ""))
		EVENT_TOKENS_GENERATED:
			tokens_generated.emit(payload.get("amount", 0.0))
		EVENT_TOKENS_CONSUMED:
			tokens_consumed.emit(payload.get("amount", 0.0))
		EVENT_QUALITY_CALCULATED:
			quality_calculated.emit(payload.get("value", 0.0))
		EVENT_BUG_GENERATED:
			bug_generated.emit()
		EVENT_JOB_COMPLETED:
			job_completed.emit(payload.get("job_id", ""))
		EVENT_JOB_FAILED:
			job_failed.emit(payload.get("job_id", ""))
		EVENT_REWARD_CALCULATED:
			reward_calculated.emit(payload.get("amount", 0.0))
		EVENT_BILL_DUE:
			bill_due.emit(payload.get("bill_type", ""), payload.get("amount", 0.0))
		EVENT_UPGRADE_PURCHASED:
			upgrade_purchased.emit(payload.get("upgrade_id", ""))
		EVENT_HARDWARE_SOLD:
			hardware_sold.emit(payload.get("hardware_key", ""))
		EVENT_PERK_ACQUIRED:
			perk_acquired.emit(payload.get("perk_id", ""))
		EVENT_OPERATION_ACQUIRED:
			operation_acquired.emit(payload.get("operation_id", ""))
		EVENT_HEAT_THRESHOLD_CROSSED:
			heat_threshold_crossed.emit(payload.get("level", 0.0))
		EVENT_ACHIEVEMENT_UNLOCKED:
			achievement_unlocked.emit(payload.get("achievement_id", ""))
		EVENT_RUN_ENDED:
			run_ended.emit(payload.get("victory", false))
		_:
			push_warning("EventBus: unknown event '%s'" % event_name)
