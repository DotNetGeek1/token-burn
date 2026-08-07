extends Node

## Global event bus for simulation lifecycle and domain events.

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
## A Tier 1 or 2 Ascension Contract completed: a level-up mid-run, not an ending.
signal ascension_rung_completed(contract_id: String, tier: int)
signal run_ended(victory: bool)


func emit_event(event_name: String, payload: Dictionary = {}) -> void:
	match event_name:
		"run.started":
			run_started.emit()
		"round.started":
			round_started.emit()
		"job.offered":
			job_offered.emit(payload.get("job_id", ""))
		"job.accepted":
			job_accepted.emit(payload.get("job_id", ""))
		"job.started":
			job_started.emit(payload.get("job_id", ""))
		"tokens.generated":
			tokens_generated.emit(payload.get("amount", 0.0))
		"tokens.consumed":
			tokens_consumed.emit(payload.get("amount", 0.0))
		"quality.calculated":
			quality_calculated.emit(payload.get("value", 0.0))
		"bug.generated":
			bug_generated.emit()
		"job.completed":
			job_completed.emit(payload.get("job_id", ""))
		"job.failed":
			job_failed.emit(payload.get("job_id", ""))
		"reward.calculated":
			reward_calculated.emit(payload.get("amount", 0.0))
		"bill.due":
			bill_due.emit(payload.get("bill_type", ""), payload.get("amount", 0.0))
		"upgrade.purchased":
			upgrade_purchased.emit(payload.get("upgrade_id", ""))
		"hardware.sold":
			hardware_sold.emit(payload.get("hardware_key", ""))
		"perk.acquired":
			perk_acquired.emit(payload.get("perk_id", ""))
		"operation.acquired":
			operation_acquired.emit(payload.get("operation_id", ""))
		"heat.threshold_crossed":
			heat_threshold_crossed.emit(payload.get("level", 0.0))
		"achievement.unlocked":
			achievement_unlocked.emit(payload.get("achievement_id", ""))
		"ascension.rung_completed":
			ascension_rung_completed.emit(
				payload.get("contract_id", ""), int(payload.get("tier", 1))
			)
		"run.ended":
			run_ended.emit(payload.get("victory", false))
		_:
			push_warning("EventBus: unknown event '%s'" % event_name)
