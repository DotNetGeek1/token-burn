class_name EconomySystem
extends RefCounted

const LEDGER_TYPE_CREDIT := "credit"
const LEDGER_TYPE_DEBIT := "debit"


## Every primitive here takes a non-negative, finite amount: `debit` and
## `credit` are which direction cash moves, not a signed delta, and letting a
## negative slip through would let a "cost" top up the till or a "purchase"
## pay the player to buy something. NaN/inf are rejected for the same reason —
## once one lands in `cash` every comparison against it starts lying.
static func _is_valid_amount(amount: float) -> bool:
	return is_finite(amount) and amount >= 0.0


func can_afford(run_state: RunState, amount: float) -> bool:
	if not _is_valid_amount(amount):
		return false
	return float(run_state.economy.get("cash", 0.0)) >= amount


func credit(run_state: RunState, amount: float, reason: String, metadata: Dictionary = {}) -> void:
	if not _is_valid_amount(amount):
		push_error("EconomySystem.credit: rejected invalid amount %s (%s)" % [amount, reason])
		return
	if amount == 0.0:
		return
	var cash: float = float(run_state.economy.get("cash", 0.0)) + amount
	run_state.economy["cash"] = cash
	_append_ledger_entry(run_state, LEDGER_TYPE_CREDIT, amount, reason, cash, metadata)


func debit(run_state: RunState, amount: float, reason: String, metadata: Dictionary = {}) -> void:
	if not _is_valid_amount(amount):
		push_error("EconomySystem.debit: rejected invalid amount %s (%s)" % [amount, reason])
		return
	if amount == 0.0:
		return
	var cash: float = float(run_state.economy.get("cash", 0.0)) - amount
	run_state.economy["cash"] = cash
	_append_ledger_entry(run_state, LEDGER_TYPE_DEBIT, amount, reason, cash, metadata)


func purchase(run_state: RunState, cost: float, reason: String) -> bool:
	if not _is_valid_amount(cost):
		push_error("EconomySystem.purchase: rejected invalid cost %s (%s)" % [cost, reason])
		return false
	if not can_afford(run_state, cost):
		return false
	debit(run_state, cost, reason)
	return true


## The debt side of an effect that lets a run spend cash it does not have.
## Kept separate from `debit`/`credit` since borrowing does not move cash by
## itself — the effect that calls this also credits the amount to whatever it
## borrowed into — but the debt it creates is exactly as real as any other
## ledgered liability, so it gets the same validation and the same ledger.
static func record_debt(run_state: RunState, amount: float, reason: String) -> void:
	if not _is_valid_amount(amount):
		push_error("EconomySystem.record_debt: rejected invalid amount %s (%s)" % [amount, reason])
		return
	if amount == 0.0:
		return
	run_state.economy["debt"] = float(run_state.economy.get("debt", 0.0)) + amount
	_append_ledger_entry(run_state, "borrow", amount, reason, float(run_state.economy.get("cash", 0.0)))


## Metered costs land per prompt, so a long round genuinely costs more to run
## than a short one even though the rent on it is the same.
func accrue_prompt_costs(run_state: RunState, tuning: Dictionary) -> void:
	var power_cost: float = float(run_state.economy.get("power_cost_per_prompt", 0.0))
	var cloud_cost: float = float(run_state.economy.get("cloud_cost_per_prompt", 0.0)) * float(tuning.get("cloud_cost_multiplier", 1.0))
	var total: float = power_cost + cloud_cost
	if total > 0.0:
		debit(run_state, total, "prompt_costs", {
			"power_cost": power_cost,
			"cloud_cost": cloud_cost,
		})
	# Running total for the round, so the player can watch the burn build up
	# before the bills land.
	run_state.economy["costs_this_round"] = float(run_state.economy.get("costs_this_round", 0.0)) + total
	# The multiplier is already folded into `cloud_cost` above — applying it
	# again at round-end billing double-charged every cloud-heavy build.
	run_state.economy["cloud_surcharge_liability"] = (
		float(run_state.economy.get("cloud_surcharge_liability", 0.0)) + cloud_cost * 0.25
	)


## Charges rent and the other end-of-round bills, and returns the statement so
## the UI can show the player exactly what they just paid for. Rent is a flat
## charge per round however many prompts the round took.
func apply_round_bills(run_state: RunState, tuning: Dictionary) -> Dictionary:
	# Rule-changer: a client retainer or subscription line lands before the
	# bills do, so it is real income rather than a discount on rent.
	var passive: float = float(run_state.economy.get("passive_income_per_round", 0.0))
	passive *= float(run_state.business.get("legacy_income_multiplier", 1.0))
	if passive > 0.0:
		add_income(run_state, passive, tuning)
	var rent: float = float(run_state.economy.get("round_rent", 400.0))
	var recurring: float = float(run_state.economy.get("recurring_costs", 0.0))
	# `cloud_surcharge_liability` already carries the multiplier from accrual
	# — billed at face value here, exactly once.
	var cloud_bill: float = float(run_state.economy.get("cloud_surcharge_liability", 0.0))
	var operating: float = float(run_state.economy.get("costs_this_round", 0.0))
	var total: float = rent + recurring + cloud_bill
	var bill_metadata: Dictionary = {
		"round": int(run_state.calendar.get("round", 1)),
		"prompts_used": maxi(0, int(run_state.calendar.get("prompt", 1)) - 1),
		"rent": rent,
		"recurring": recurring,
		"cloud_bill": cloud_bill,
		"operating": operating,
		"bill_total": total,
		"round_total": total + operating,
	}
	EventBus.emit_event(EventBus.EVENT_BILL_DUE, {"bill_type": "round", "amount": total})
	var cash: float = float(run_state.economy.get("cash", 0.0))
	if cash >= total:
		bill_metadata["paid_in_full"] = true
		debit(run_state, total, "round_bills", bill_metadata)
		run_state.economy["rent_unpaid_streak"] = 0
	else:
		var debt_added: float = total - cash
		bill_metadata["paid_in_full"] = false
		bill_metadata["debt_added"] = debt_added
		if cash > 0.0:
			debit(run_state, cash, "round_bills", bill_metadata)
		else:
			_append_ledger_entry(run_state, LEDGER_TYPE_DEBIT, 0.0, "round_bills", 0.0, bill_metadata)
		run_state.economy["debt"] = float(run_state.economy.get("debt", 0.0)) + debt_added
		run_state.economy["cash"] = 0.0
		run_state.economy["rent_unpaid_streak"] = int(run_state.economy.get("rent_unpaid_streak", 0)) + 1
	# The surcharge has been billed in full above — either paid out of cash or
	# rolled into debt with the rest of the bill — so nothing of it survives
	# into the next round. Carrying a fraction forward re-charged a settled
	# debt every round until it rounded away, roughly doubling its true cost.
	run_state.economy["cloud_surcharge_liability"] = 0.0
	run_state.economy["last_round_costs"] = total + operating
	bill_metadata["cash_after"] = float(run_state.economy.get("cash", 0.0))
	bill_metadata["debt"] = float(run_state.economy.get("debt", 0.0))
	bill_metadata["unpaid_streak"] = int(run_state.economy.get("rent_unpaid_streak", 0))
	return bill_metadata


## The round the contract was completed in is on the investor. Nothing is
## charged and nothing is owed: the statement still itemises what the round
## would have cost so the player can see what was covered, and the unpaid
## streak is wiped so a chapter cleared with empty pockets cannot be evicted
## for it afterwards.
func waive_round_bills(run_state: RunState) -> Dictionary:
	var rent: float = float(run_state.economy.get("round_rent", 400.0))
	var recurring: float = float(run_state.economy.get("recurring_costs", 0.0))
	var cloud_bill: float = float(run_state.economy.get("cloud_surcharge_liability", 0.0))
	var operating: float = float(run_state.economy.get("costs_this_round", 0.0))
	var total: float = rent + recurring + cloud_bill
	var bill_metadata: Dictionary = {
		"round": int(run_state.calendar.get("round", 1)),
		"prompts_used": maxi(0, int(run_state.calendar.get("prompt", 1)) - 1),
		"rent": 0.0,
		"recurring": 0.0,
		"cloud_bill": 0.0,
		"operating": operating,
		"bill_total": 0.0,
		"round_total": operating,
		"paid_in_full": true,
		"waived": true,
		"waived_total": total,
	}
	_append_ledger_entry(run_state, LEDGER_TYPE_DEBIT, 0.0, "round_bills_waived", float(run_state.economy.get("cash", 0.0)), bill_metadata)
	run_state.economy["cloud_surcharge_liability"] = 0.0
	run_state.economy["rent_unpaid_streak"] = 0
	run_state.economy["last_round_costs"] = operating
	bill_metadata["cash_after"] = float(run_state.economy.get("cash", 0.0))
	bill_metadata["debt"] = float(run_state.economy.get("debt", 0.0))
	bill_metadata["unpaid_streak"] = 0
	return bill_metadata


func add_income(run_state: RunState, amount: float, tuning: Dictionary) -> void:
	var adjusted: float = amount * float(tuning.get("economy_multiplier", 1.0))
	credit(run_state, adjusted, "income", {
		"base_amount": amount,
		"multiplier": tuning.get("economy_multiplier", 1.0),
	})
	run_state.economy["income"] = float(run_state.economy.get("income", 0.0)) + adjusted


func process_pending_bills(run_state: RunState) -> void:
	var bills: Array = run_state.economy.get("pending_bills", [])
	if bills.is_empty():
		return
	var remaining: Array = []
	for bill in bills:
		if not bill is Dictionary:
			continue
		var prompts_left: int = int(bill.get("prompts_until_due", 0)) - 1
		if prompts_left <= 0:
			_apply_pending_bill(run_state, bill)
		else:
			var copy: Dictionary = bill.duplicate(true)
			copy["prompts_until_due"] = prompts_left
			remaining.append(copy)
	run_state.economy["pending_bills"] = remaining


func _apply_pending_bill(run_state: RunState, bill: Dictionary) -> void:
	var amount: float = float(bill.get("amount", 0.0))
	if amount <= 0.0:
		return
	var target: String = str(bill.get("target", "economy.cash"))
	var source: String = str(bill.get("source_event", "deferred"))
	var metadata: Dictionary = bill.duplicate(true)
	metadata.erase("amount")
	metadata.erase("target")
	metadata.erase("prompts_until_due")
	var reason: String = "deferred:%s" % source
	if target == "economy.cash":
		debit(run_state, amount, reason, metadata)
	else:
		var current: float = float(run_state.get_value_at_path(target))
		run_state.set_value_at_path(target, current - amount)
		_append_ledger_entry(
			run_state,
			LEDGER_TYPE_DEBIT,
			amount,
			reason,
			float(run_state.economy.get("cash", 0.0)),
			metadata
		)


static func _append_ledger_entry(
	run_state: RunState,
	entry_type: String,
	amount: float,
	reason: String,
	balance_after: float,
	metadata: Dictionary = {}
) -> void:
	_ensure_ledger(run_state)
	var entry: Dictionary = {
		"type": entry_type,
		"amount": amount,
		"reason": reason,
		"balance_after": balance_after,
		"metadata": metadata.duplicate(true),
		"round": int(run_state.calendar.get("round", 1)),
		"prompt": int(run_state.calendar.get("prompt", 1)),
	}
	run_state.economy["ledger"].append(entry)


static func _ensure_ledger(run_state: RunState) -> void:
	if not run_state.economy.has("ledger") or not run_state.economy["ledger"] is Array:
		run_state.economy["ledger"] = []
