extends TestCase

## The two things a machine is for beyond raw throughput: it works a second
## contract at the same time, and getting work back early is worth more money.


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_one_machine_works_one_contract()
	_test_a_second_machine_opens_a_second_lane()
	_test_parallel_lanes_split_one_batch()
	_test_parallel_lanes_move_two_deadlines_at_once()
	_test_peak_prompt_tokens_sums_every_lane()
	_test_two_contracts_run_through_two_workflows_in_one_prompt()
	_test_early_delivery_pays_a_bonus()
	_test_shipping_unfinished_earns_no_early_bonus()
	_test_the_prompt_that_finishes_a_contract_still_costs_a_deadline()


func _sim(seed_value: int) -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(seed_value)
	sim.run_state.economy["cash"] = 10000000.0
	return sim


## Two contracts big enough that neither finishes in one prompt, so the lanes are
## still open when they are inspected.
func _load_two_contracts(sim: Node) -> Array:
	var rate: float = maxf(1.0, float(sim.run_state.compute.get("token_rate", 1.0)))
	var jobs: Array = []
	for i in range(2):
		jobs.append({
			"id": "job.parallel_%d" % i,
			"name": "Parallel %d" % i,
			"token_requirement": rate * 50.0,
			"tokens_remaining": rate * 50.0,
			"deadline_prompts": 60,
			"prompts_remaining": 60,
			"reward": 500.0,
			"quality": 0.0,
			"quality_threshold": 0.0,
			"revision_risk": 0.0,
			"bug_chance": 0.0,
		})
	sim.run_state.business["active_jobs"] = jobs
	sim.run_state.business["focused_job_id"] = "job.parallel_0"
	sim.phase = sim.Phase.IN_ROUND
	# Stands in for start_work_sync: the round is under way and the board has
	# modules on it, which is what BURN TOKENS checks before it will run.
	sim._work_running = true
	sim._board_system.ensure_board(sim.run_state, ContentDatabase)
	sim.auto_arrange_board()
	return jobs


func _test_one_machine_works_one_contract() -> void:
	var sim: Node = _sim(4101)
	assert_eq(sim.job_slots(), 1, "A run starts with one machine on the floor")
	_load_two_contracts(sim)
	assert_eq(sim.burn_lanes().size(), 1, "So a prompt advances one contract and the other waits")
	sim.free()


func _test_a_second_machine_opens_a_second_lane() -> void:
	var sim: Node = _sim(4102)
	assert_true(sim.buy_upgrade("upgrade.custom_desktop"), "A desktop fits beside the laptop")
	assert_eq(sim.job_slots(), 2, "Two machines on the floor is two job slots")
	_load_two_contracts(sim)
	var lanes: Array = sim.burn_lanes()
	assert_eq(lanes.size(), 2, "And a prompt now advances both contracts")
	assert_eq(
		str(lanes[0].get("id", "")),
		"job.parallel_0",
		"The focused contract always takes the first lane"
	)
	sim.free()


## Machines are lanes, not multipliers: the rig's output for a prompt is the same
## however it is divided, so a second machine buys concurrency rather than speed.
func _test_parallel_lanes_split_one_batch() -> void:
	var solo: Node = _sim(4103)
	_load_two_contracts(solo)
	var solo_burn: Dictionary = solo.preview_burn()
	assert_true(solo_burn.get("ok", false), "A single-lane burn previews")
	var solo_progress: float = float(solo_burn.get("progress_tokens", 0.0))
	assert_eq(int(solo_burn.get("lane_count", 0)), 1, "One machine reports one lane")
	solo.free()

	var pair: Node = _sim(4103)
	assert_true(pair.buy_upgrade("upgrade.custom_desktop"), "Add a second machine")
	# Match the solo rig's throughput so the comparison is about the split alone
	# rather than about the desktop being a faster machine.
	pair.run_state.compute["token_rate"] = float(solo_progress)
	_load_two_contracts(pair)
	var pair_burn: Dictionary = pair.preview_burn()
	assert_true(pair_burn.get("ok", false), "A two-lane burn previews")
	assert_eq(int(pair_burn.get("lane_count", 0)), 2, "Two machines report two lanes")
	var lanes: Array = pair_burn.get("lanes", [])
	assert_eq(lanes.size(), 2, "With a report for each contract worked")
	assert_almost_eq(
		float(lanes[0].get("progress_tokens", 0.0)),
		float(lanes[1].get("progress_tokens", 0.0)),
		float(lanes[0].get("progress_tokens", 1.0)) * 0.35,
		"The batch is shared roughly evenly rather than doubled"
	)
	pair.free()


## The reason to buy the second machine: one prompt now moves two contracts closer
## to delivery instead of leaving one of them ageing in a queue.
func _test_parallel_lanes_move_two_deadlines_at_once() -> void:
	var sim: Node = _sim(4104)
	assert_true(sim.buy_upgrade("upgrade.custom_desktop"), "Two machines on the floor")
	_load_two_contracts(sim)
	var before: Array = []
	for job in sim.run_state.business["active_jobs"]:
		before.append(float(job.get("tokens_remaining", 0.0)))

	sim.burn_batch()

	for i in range(2):
		var job: Dictionary = sim.run_state.business["active_jobs"][i]
		assert_true(
			float(job.get("tokens_remaining", 0.0)) < before[i],
			"Contract %d made progress on the same prompt" % i
		)
	sim.free()


func _test_peak_prompt_tokens_sums_every_lane() -> void:
	var sim: Node = _sim(4106)
	assert_true(sim.buy_upgrade("upgrade.custom_desktop"), "Two machines on the floor")
	_load_two_contracts(sim)
	var lifetime_before: float = float(sim.run_state.statistics.get("lifetime_tokens", 0.0))
	sim.run_state.statistics["peak_prompt_tokens"] = 0.0
	var result: Dictionary = sim.burn_batch()
	assert_true(result.get("ok", false), "A two-lane prompt lands")
	var lanes: Array = Dictionary(result.get("burn", {})).get("lanes", [])
	assert_eq(lanes.size(), 2, "Both lanes report")
	var lane_total: float = (
		float(Dictionary(lanes[0]).get("tokens", 0.0))
		+ float(Dictionary(lanes[1]).get("tokens", 0.0))
	)
	assert_true(lane_total > 0.0, "The prompt produced tokens")
	assert_almost_eq(
		float(sim.run_state.statistics.get("lifetime_tokens", 0.0)) - lifetime_before,
		lane_total,
		0.01,
		"Lifetime tokens count every lane of the prompt"
	)
	assert_almost_eq(
		float(sim.run_state.statistics.get("peak_prompt_tokens", 0.0)),
		lane_total,
		0.01,
		"Peak burn in one prompt is the sum, not the busiest lane"
	)
	sim.free()


## Parallel work used to share one global pipeline. Now each contract carries
## its own assignment, so one prompt can run a cheap build and an expensive one
## side by side.
func _test_two_contracts_run_through_two_workflows_in_one_prompt() -> void:
	var sim: Node = _sim(4105)
	assert_true(sim.buy_upgrade("upgrade.custom_desktop"), "Two machines on the floor")
	sim.run_state.build["meta_workflow_bonus"] = 1
	var jobs: Array = _load_two_contracts(sim)
	sim.run_state.build["modules"] = ["op.prompt", "op.cheap_model", "op.premium_model"]

	var first: Dictionary = sim.workflows()[0]
	first["slots"] = ["op.prompt", "op.cheap_model", ""]
	var second: Dictionary = sim.create_workflow("Expensive")
	assert_false(second.is_empty(), "The run has room for a second workflow")
	second["slots"] = ["op.prompt", "op.premium_model", ""]

	assert_true(sim.assign_workflow("job.parallel_0", str(first.get("id", ""))), "The first contract is routed")
	assert_true(sim.assign_workflow("job.parallel_1", str(second.get("id", ""))), "And the second somewhere else")

	var burn: Dictionary = sim.preview_burn()
	var lanes: Array = burn.get("lanes", [])
	assert_eq(lanes.size(), 2, "Both contracts are worked this prompt")
	assert_eq(str(lanes[0].get("workflow_name", "")), str(first.get("name", "")), "Each lane reports its own workflow")
	assert_eq(str(lanes[1].get("workflow_name", "")), "Expensive", "Including the one that was reassigned")

	assert_false(sim.assign_workflow("job.parallel_0", "workflow.nope"), "A workflow that does not exist is refused")
	assert_eq(
		str(jobs[0].get("workflow_id", "")), str(first.get("id", "")),
		"So the contract keeps the pipeline it had"
	)
	sim.free()


## Beating a deadline used to be worth nothing beyond the prompts it saved, which
## made throughput pointless past "fast enough".
func _test_early_delivery_pays_a_bonus() -> void:
	var cfg: Dictionary = ContentDatabase.balance.get("job_scaling", {}).get("early_delivery_bonus", {})
	var per_prompt: float = float(cfg.get("per_spare_prompt", 0.0))
	var cap: float = float(cfg.get("cap", 0.0))
	assert_true(per_prompt > 0.0, "Content sets a per-prompt early bonus")
	assert_true(cap > 0.0, "And a ceiling on it")

	var on_time: Dictionary = {"prompts_remaining": 0}
	assert_almost_eq(
		JobSystem.early_delivery_bonus(on_time), 0.0, 0.0001,
		"Delivering on the last prompt earns no premium"
	)
	var early: Dictionary = {"prompts_remaining": 3}
	assert_almost_eq(
		JobSystem.early_delivery_bonus(early), per_prompt * 3.0, 0.0001,
		"Every spare prompt is worth more fee"
	)
	var very_early: Dictionary = {"prompts_remaining": 1000}
	assert_almost_eq(
		JobSystem.early_delivery_bonus(very_early), cap, 0.0001,
		"But the premium is capped, so a huge rig cannot farm one small contract"
	)


func _test_shipping_unfinished_earns_no_early_bonus() -> void:
	var cut_short: Dictionary = {"prompts_remaining": 5, "shipped_unfinished": true}
	assert_almost_eq(
		JobSystem.early_delivery_bonus(cut_short), 0.0, 0.0001,
		"Cutting the scope to hit a date is not the same as being quick"
	)


## A rig, a contract and the systems around them, without the run lifecycle:
## these tests are about what one prompt does to a deadline, so the round-end
## machinery would only get in the way.
class DeadlineRig extends RefCounted:
	var jobs := JobSystem.new()
	var board := BoardSystem.new()
	var compute := ComputeSystem.new()
	var heat := HeatSystem.new()
	var economy := EconomySystem.new()
	var resolver := EffectResolver.new()
	var rng := DeterministicRng.new(8801)
	var state := RunState.new()
	var job: Dictionary

	func _init(deadline: int, requirement: float) -> void:
		board.ensure_board(state, ContentDatabase)
		state.economy["cash"] = 1000000.0
		job = {
			"id": "job.deadline",
			"name": "Deadline Probe",
			"token_requirement": requirement,
			"tokens_remaining": requirement,
			"deadline_prompts": deadline,
			"prompts_remaining": deadline,
			"reward": 500.0,
			"quality": 0.0,
			"quality_threshold": 0.0,
			"revision_risk": 0.0,
			"bug_chance": 0.0,
		}
		state.business["active_jobs"] = [job]
		state.business["focused_job_id"] = "job.deadline"

	func burn() -> Dictionary:
		return jobs.run_burn(
			state, rng, resolver, [], {}, compute, heat, economy, board
		)


## The bug this closes: `end_prompt` skipped finished contracts before taking
## the prompt off their deadline, so work delivered on the last allowed prompt
## looked like it had a prompt in hand and collected an early bonus for it.
func _test_the_prompt_that_finishes_a_contract_still_costs_a_deadline() -> void:
	var last_prompt := DeadlineRig.new(1, 1.0)
	last_prompt.burn()
	assert_eq(
		float(last_prompt.job.get("tokens_remaining", -1.0)), 0.0,
		"One prompt is enough to finish a one-token contract"
	)
	assert_eq(
		int(last_prompt.job.get("prompts_remaining", -1)), 0,
		"And that prompt comes off the deadline like any other"
	)
	assert_almost_eq(
		JobSystem.early_delivery_bonus(last_prompt.job), 0.0, 0.0001,
		"Delivering on the deadline is on time, not early"
	)

	var missed := DeadlineRig.new(1, 1.0e9)
	missed.burn()
	assert_true(
		bool(missed.job.get("shipped_unfinished", false)),
		"A contract far too big for one prompt is still unfinished"
	)
	assert_true(JobSystem.is_shipped(missed.job), "The deadline ships whatever is there")
	assert_eq(int(missed.job.get("prompts_remaining", -1)), 0, "With no prompts left to finish it in")

	var early := DeadlineRig.new(2, 1.0)
	early.burn()
	assert_eq(
		int(early.job.get("prompts_remaining", -1)), 1,
		"Finishing a two-prompt contract on the first prompt leaves one to spare"
	)
	assert_true(
		JobSystem.early_delivery_bonus(early.job) > 0.0,
		"Which is what an early-delivery bonus is for"
	)

	var on_time := DeadlineRig.new(2, 1.0e9)
	on_time.burn()
	assert_eq(int(on_time.job.get("prompts_remaining", -1)), 1, "The first prompt of two is spent")
	on_time.job["tokens_remaining"] = 1.0
	on_time.burn()
	assert_eq(
		float(on_time.job.get("tokens_remaining", -1.0)), 0.0,
		"The second finishes the work"
	)
	assert_eq(int(on_time.job.get("prompts_remaining", -1)), 0, "Using the last prompt to do it")
	assert_almost_eq(
		JobSystem.early_delivery_bonus(on_time.job), 0.0, 0.0001,
		"So there is nothing spare to pay a bonus on"
	)
