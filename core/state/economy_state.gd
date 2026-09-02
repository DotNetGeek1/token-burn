class_name EconomyState
extends RefCounted

## Typed read/write view onto `RunState.economy`. First step of the Phase 5
## "typed state" refactor: the dictionary stays the actual storage for now
## (every effect target path and save file already addresses it that way),
## but code that wants economy fields with real property names and static
## types — rather than `.get("cash", 0.0)` scattered everywhere — can go
## through here instead. Future increments (ComputeState, JobState,
## InventoryState, AscensionState) follow the same shape.

var cash: float = RunState.DEFAULT_STARTING_CASH
var cash_multiplier: float = 1.0
var debt: float = 0.0
var recurring_costs_base: float = 0.0
var recurring_costs: float = 0.0
var income: float = 0.0
var pending_bills: Array = []
var rent_unpaid_streak: int = 0
var rent_multiplier: float = 1.0
var round_rent: float = 400.0
var power_base_cost_per_prompt: float = 10.0
var power_cost_per_prompt: float = 10.0
var costs_this_round: float = 0.0
var last_round_costs: float = 0.0


static func from_dict(data: Dictionary) -> EconomyState:
	var state := EconomyState.new()
	state.cash = float(data.get("cash", state.cash))
	state.cash_multiplier = float(data.get("cash_multiplier", state.cash_multiplier))
	state.debt = float(data.get("debt", state.debt))
	state.recurring_costs_base = float(data.get("recurring_costs_base", state.recurring_costs_base))
	state.recurring_costs = float(data.get("recurring_costs", state.recurring_costs))
	state.income = float(data.get("income", state.income))
	state.pending_bills = Array(data.get("pending_bills", state.pending_bills)).duplicate(true)
	state.rent_unpaid_streak = int(data.get("rent_unpaid_streak", state.rent_unpaid_streak))
	state.rent_multiplier = float(data.get("rent_multiplier", state.rent_multiplier))
	state.round_rent = float(data.get("round_rent", state.round_rent))
	state.power_base_cost_per_prompt = float(data.get("power_base_cost_per_prompt", state.power_base_cost_per_prompt))
	state.power_cost_per_prompt = float(data.get("power_cost_per_prompt", state.power_cost_per_prompt))
	state.costs_this_round = float(data.get("costs_this_round", state.costs_this_round))
	state.last_round_costs = float(data.get("last_round_costs", state.last_round_costs))
	return state


func to_dict() -> Dictionary:
	return {
		"cash": cash,
		"cash_multiplier": cash_multiplier,
		"debt": debt,
		"recurring_costs_base": recurring_costs_base,
		"recurring_costs": recurring_costs,
		"income": income,
		"pending_bills": pending_bills.duplicate(true),
		"rent_unpaid_streak": rent_unpaid_streak,
		"rent_multiplier": rent_multiplier,
		"round_rent": round_rent,
		"power_base_cost_per_prompt": power_base_cost_per_prompt,
		"power_cost_per_prompt": power_cost_per_prompt,
		"costs_this_round": costs_this_round,
		"last_round_costs": last_round_costs,
	}
