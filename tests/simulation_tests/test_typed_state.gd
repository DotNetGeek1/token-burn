extends TestCase

## First increment of the typed-state refactor: `EconomyState`/`ComputeState`
## are snapshots taken off the live dictionaries, so the round trip through
## them has to be lossless in both directions before anything is allowed to
## build on top of them.


func run() -> void:
	_test_economy_state_round_trips()
	_test_compute_state_round_trips()
	_test_apply_writes_back_to_the_dictionary()


func _test_economy_state_round_trips() -> void:
	var state := RunState.new()
	state.economy["cash"] = 4321.0
	state.economy["debt"] = 88.0
	state.economy["cloud_surcharge_liability"] = 12.5
	state.economy["pending_bills"] = [{"amount": 10.0, "prompts_until_due": 2}]

	var economy := state.economy_state()
	assert_eq(economy.cash, 4321.0, "EconomyState reads cash off the dictionary")
	assert_eq(economy.debt, 88.0, "EconomyState reads debt off the dictionary")
	assert_eq(economy.cloud_surcharge_liability, 12.5, "EconomyState reads the renamed cloud field")
	assert_eq(economy.pending_bills.size(), 1, "EconomyState carries pending bills")

	var round_tripped: Dictionary = EconomyState.from_dict(economy.to_dict()).to_dict()
	assert_eq(round_tripped, economy.to_dict(), "EconomyState.to_dict() -> from_dict() -> to_dict() is stable")


func _test_compute_state_round_trips() -> void:
	var state := RunState.new()
	state.compute["token_rate"] = 5_000_000.0
	state.compute["heat"] = 42.0
	state.compute["rate_modifiers"] = [{"multiplier": 2.0, "prompts_remaining": 1, "source": "boost"}]

	var compute := state.compute_state()
	assert_eq(compute.token_rate, 5_000_000.0, "ComputeState reads token_rate off the dictionary")
	assert_eq(compute.heat, 42.0, "ComputeState reads heat off the dictionary")
	assert_eq(compute.rate_modifiers.size(), 1, "ComputeState carries rate modifiers")

	var round_tripped: Dictionary = ComputeState.from_dict(compute.to_dict()).to_dict()
	assert_eq(round_tripped, compute.to_dict(), "ComputeState.to_dict() -> from_dict() -> to_dict() is stable")


## `apply_*_state` is a form submission, not a live binding: editing the
## snapshot must do nothing until it is handed back.
func _test_apply_writes_back_to_the_dictionary() -> void:
	var state := RunState.new()
	var economy := state.economy_state()
	economy.cash = 7777.0
	assert_eq(float(state.economy.get("cash", 0.0)), RunState.DEFAULT_STARTING_CASH, "Editing the snapshot alone leaves the dictionary untouched")

	state.apply_economy_state(economy)
	assert_eq(float(state.economy.get("cash", 0.0)), 7777.0, "Applying the snapshot writes it back")

	var compute := state.compute_state()
	compute.heat = 55.0
	state.apply_compute_state(compute)
	assert_eq(float(state.compute.get("heat", 0.0)), 55.0, "Applying a compute snapshot writes it back too")
