extends TestCase


func run() -> void:
	var economy := EconomySystem.new()
	var state := RunState.new()
	state.economy["cash"] = 1000.0
	state.economy["power_cost_per_prompt"] = 10.0
	state.economy["cloud_cost_per_prompt"] = 5.0
	economy.accrue_prompt_costs(state, {})
	assert_eq(state.economy.get("cash", 0.0), 985.0, "Prompt costs accrue")

	state.economy["cash"] = 100.0
	state.economy["round_rent"] = 400.0
	state.economy["recurring_costs"] = 50.0
	state.economy["cloud_surcharge_liability"] = 200.0
	economy.apply_round_bills(state, {"cloud_cost_multiplier": 1.0})
	assert_eq(state.economy.get("cash", 0.0), 0.0, "Unpaid bills drain cash")
	assert_true(float(state.economy.get("debt", 0.0)) > 0.0, "Unpaid bills add debt")
	assert_eq(state.economy.get("rent_unpaid_streak", 0), 1, "Rent unpaid streak increments")

	var progression := ProgressionSystem.new()
	state.economy["cash"] = -6000.0
	assert_true(progression.check_loss(state), "Bankruptcy triggers loss")
	state.reset()
	state.economy["rent_unpaid_streak"] = 2
	assert_true(progression.check_loss(state), "Eviction triggers loss")

	_test_can_afford(economy)
	_test_purchase_atomicity(economy)
	_test_ledger_entries(economy)
	_test_pending_bills_processing(economy)
	_test_round_cost_accrual(economy)
	_test_round_statement(economy)
	_test_rent_is_flat_however_long_the_round_runs(economy)
	_test_power_scales_with_hardware()
	_test_rent_scales_with_dwelling()


func _test_can_afford(economy: EconomySystem) -> void:
	var state := RunState.new()
	state.economy["cash"] = 500.0
	assert_true(economy.can_afford(state, 500.0), "Exact balance is affordable")
	assert_true(economy.can_afford(state, 100.0), "Partial balance is affordable")
	assert_false(economy.can_afford(state, 500.01), "Over balance is not affordable")
	assert_true(economy.can_afford(state, 0.0), "Zero cost is affordable")
	state.economy["cash"] = 0.0
	assert_false(economy.can_afford(state, 1.0), "Empty wallet cannot afford")


func _test_purchase_atomicity(economy: EconomySystem) -> void:
	var state := RunState.new()
	state.economy["cash"] = 200.0
	assert_true(economy.purchase(state, 150.0, "test_purchase"), "Purchase succeeds when affordable")
	assert_eq(state.economy.get("cash", 0.0), 50.0, "Purchase deducts cost")
	assert_false(economy.purchase(state, 100.0, "failed_purchase"), "Purchase fails when unaffordable")
	assert_eq(state.economy.get("cash", 0.0), 50.0, "Failed purchase leaves balance unchanged")


func _test_ledger_entries(economy: EconomySystem) -> void:
	var state := RunState.new()
	state.economy["cash"] = 1000.0
	state.calendar["round"] = 3
	state.calendar["prompt"] = 2
	economy.credit(state, 100.0, "test_credit", {"source": "unit_test"})
	economy.debit(state, 50.0, "test_debit")
	var ledger: Array = state.economy.get("ledger", [])
	assert_eq(ledger.size(), 2, "Credit and debit create ledger entries")
	assert_eq(ledger[0].get("type", ""), "credit", "Credit entry type")
	assert_eq(ledger[0].get("amount", 0.0), 100.0, "Credit entry amount")
	assert_eq(ledger[0].get("reason", ""), "test_credit", "Credit entry reason")
	assert_eq(ledger[0].get("balance_after", 0.0), 1100.0, "Credit balance after")
	assert_eq(ledger[0].get("metadata", {}).get("source", ""), "unit_test", "Credit metadata preserved")
	assert_eq(ledger[0].get("round", 0), 3, "Credit entry round")
	assert_eq(ledger[0].get("prompt", 0), 2, "Credit entry prompt")
	assert_eq(ledger[1].get("type", ""), "debit", "Debit entry type")
	assert_eq(ledger[1].get("balance_after", 0.0), 1050.0, "Debit balance after")

	state.economy["cash"] = 500.0
	state.economy["power_cost_per_prompt"] = 10.0
	state.economy["cloud_cost_per_prompt"] = 0.0
	economy.accrue_prompt_costs(state, {})
	ledger = state.economy.get("ledger", [])
	var prompt_entry: Dictionary = ledger[ledger.size() - 1]
	assert_eq(prompt_entry.get("reason", ""), "prompt_costs", "Prompt costs logged in ledger")

	state.economy["cash"] = 200.0
	economy.add_income(state, 100.0, {"economy_multiplier": 1.5})
	ledger = state.economy.get("ledger", [])
	var income_entry: Dictionary = ledger[ledger.size() - 1]
	assert_eq(income_entry.get("type", ""), "credit", "Income logged as credit")
	assert_eq(income_entry.get("amount", 0.0), 150.0, "Income multiplier applied in ledger")
	assert_eq(state.economy.get("income", 0.0), 150.0, "Income stat updated")


func _test_round_cost_accrual(economy: EconomySystem) -> void:
	var state := RunState.new()
	state.economy["cash"] = 1000.0
	state.economy["power_cost_per_prompt"] = 12.0
	state.economy["cloud_cost_per_prompt"] = 8.0
	assert_eq(state.economy.get("costs_this_round", 0.0), 0.0, "A round starts with no accrued costs")
	economy.accrue_prompt_costs(state, {})
	economy.accrue_prompt_costs(state, {})
	assert_eq(state.economy.get("costs_this_round", 0.0), 40.0, "Operating costs accrue prompt by prompt")
	assert_eq(state.economy.get("cash", 0.0), 960.0, "Accrued costs come out of cash as they happen")


func _test_round_statement(economy: EconomySystem) -> void:
	var state := RunState.new()
	state.calendar["round"] = 4
	state.calendar["prompt"] = 6
	state.economy["cash"] = 5000.0
	state.economy["round_rent"] = 400.0
	state.economy["recurring_costs"] = 70.0
	state.economy["cloud_surcharge_liability"] = 0.0
	state.economy["costs_this_round"] = 150.0
	var statement: Dictionary = economy.apply_round_bills(state, {"cloud_cost_multiplier": 1.0})
	assert_eq(statement.get("round", 0), 4, "Statement reports the round that closed")
	assert_eq(statement.get("prompts_used", -1), 5, "Statement reports how many prompts the round took")
	assert_eq(statement.get("rent", 0.0), 400.0, "Statement itemises rent")
	assert_eq(statement.get("recurring", 0.0), 70.0, "Statement itemises subscriptions")
	assert_eq(statement.get("bill_total", 0.0), 470.0, "Statement totals the end-of-round bills")
	assert_eq(statement.get("operating", 0.0), 150.0, "Statement carries the operating costs already paid")
	assert_eq(statement.get("round_total", 0.0), 620.0, "Statement totals everything the round cost")
	assert_true(bool(statement.get("paid_in_full", false)), "Affordable bills are paid in full")
	assert_eq(state.economy.get("cash", 0.0), 4530.0, "Only the end-of-round bills are charged again")
	assert_eq(statement.get("cash_after", 0.0), 4530.0, "Statement reports the balance after paying")

	state.economy["cash"] = 100.0
	var short: Dictionary = economy.apply_round_bills(state, {"cloud_cost_multiplier": 1.0})
	assert_false(bool(short.get("paid_in_full", true)), "Unaffordable bills are flagged as unpaid")
	assert_true(float(short.get("debt_added", 0.0)) > 0.0, "Statement reports the shortfall as debt")
	assert_eq(short.get("unpaid_streak", 0), 1, "Statement reports the eviction streak")


## Rent is per round, not per prompt, so a round that took twelve prompts and one
## that took three owe the same rent — only the metered power differs. This is the
## whole point of the split, so it is asserted directly rather than inferred.
func _test_rent_is_flat_however_long_the_round_runs(economy: EconomySystem) -> void:
	var short_round := RunState.new()
	var long_round := RunState.new()
	for state in [short_round, long_round]:
		state.economy["cash"] = 100000.0
		state.economy["round_rent"] = 400.0
		state.economy["recurring_costs"] = 0.0
		state.economy["cloud_surcharge_liability"] = 0.0
		state.economy["power_cost_per_prompt"] = 10.0
		state.economy["cloud_cost_per_prompt"] = 0.0
	for _i in range(3):
		economy.accrue_prompt_costs(short_round, {})
	for _i in range(12):
		economy.accrue_prompt_costs(long_round, {})

	var short_statement: Dictionary = economy.apply_round_bills(short_round, {"cloud_cost_multiplier": 1.0})
	var long_statement: Dictionary = economy.apply_round_bills(long_round, {"cloud_cost_multiplier": 1.0})
	assert_eq(
		float(short_statement.get("rent", 0.0)),
		float(long_statement.get("rent", 0.0)),
		"A long round pays exactly the same rent as a short one"
	)
	assert_true(
		float(long_statement.get("operating", 0.0)) > float(short_statement.get("operating", 0.0)),
		"But it burns more metered power getting there"
	)
	assert_true(
		float(long_statement.get("round_total", 0.0)) > float(short_statement.get("round_total", 0.0)),
		"So a long round still costs more overall"
	)


func _test_power_scales_with_hardware() -> void:
	var state := RunState.new()
	var compute := ComputeSystem.new()
	var resolver := EffectResolver.new()
	var rng := DeterministicRng.new()
	rng.set_seed(7)
	compute.recalculate(state, resolver, [], rng)
	var laptop_cost: float = float(state.economy.get("power_cost_per_prompt", 0.0))
	var standing: float = float(state.economy.get("power_base_cost_per_prompt", 10.0))
	assert_true(laptop_cost > standing, "Hardware draw adds to the standing charge")

	state.build["hardware"] = ["used_laptop", "gpu_rack"]
	compute.recalculate(state, resolver, [], rng)
	var rack_cost: float = float(state.economy.get("power_cost_per_prompt", 0.0))
	assert_true(rack_cost > laptop_cost * 2.0, "A power-hungry rig costs far more per prompt")
	assert_eq(state.compute.get("power_draw", 0.0), 2065.0, "Power draw sums the installed hardware")


## Rent is a property of the chapter the run is set in, settled when it starts
## and never renegotiated.
func _test_rent_scales_with_dwelling() -> void:
	var state := RunState.new()
	var starting_rent: float = float(state.economy.get("round_rent", 0.0))
	Simulation.apply_run_location(state, "garage")
	var dwelling_rent: float = float(ContentDatabase.balance.get("dwelling_costs", {}).get("garage", {}).get("rent", 0.0))
	var multiplier: float = float(state.economy.get("rent_multiplier", 1.0))
	assert_eq(state.economy.get("round_rent", 0.0), dwelling_rent * multiplier, "Rent follows the location and difficulty")
	assert_true(float(state.economy.get("round_rent", 0.0)) > starting_rent, "A bigger space costs more to keep")


func _test_pending_bills_processing(economy: EconomySystem) -> void:
	var state := RunState.new()
	state.economy["cash"] = 500.0
	state.economy["pending_bills"] = [{
		"amount": 75.0,
		"target": "economy.cash",
		"prompts_until_due": 2,
		"source_event": "bill.due",
	}]
	economy.process_pending_bills(state)
	assert_eq(state.economy.get("cash", 0.0), 500.0, "Bill not due after first tick")
	assert_eq(state.economy.get("pending_bills", []).size(), 1, "Bill remains pending")
	assert_eq(state.economy.get("pending_bills", [])[0].get("prompts_until_due", 0), 1, "Prompts until due decremented")

	economy.process_pending_bills(state)
	assert_eq(state.economy.get("cash", 0.0), 425.0, "Bill applied when due")
	assert_eq(state.economy.get("pending_bills", []).size(), 0, "Processed bill removed")
	var ledger: Array = state.economy.get("ledger", [])
	assert_true(ledger.size() > 0, "Deferred bill creates ledger entry")
	assert_eq(ledger[ledger.size() - 1].get("reason", ""), "deferred:bill.due", "Deferred bill reason")

	state.economy["cash"] = 300.0
	state.economy["pending_bills"] = [{
		"amount": 50.0,
		"target": "economy.cash",
		"prompts_until_due": 1,
		"source_event": "upgrade.test",
	}]
	economy.process_pending_bills(state)
	assert_eq(state.economy.get("cash", 0.0), 250.0, "Single-prompt defer applies on first process")
