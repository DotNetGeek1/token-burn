extends TestCase


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	assert_true(ContentDatabase.jobs.size() > 0, "Job content loaded")

	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(42)
	assert_true(sim.phase == sim.Phase.ROUND_PREP, "Run starts in round prep")
	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(offers.size() > 0, "Job offers generated")
	if offers.is_empty():
		sim.free()
		return

	var starting_cash: float = float(sim.run_state.economy.get("cash", 0.0))
	var offer: Dictionary = offers[0]
	for candidate in offers:
		if JobSystem.definition_id_of(candidate) == "job.product_descriptions":
			offer = candidate
			break
	# Deadlines are measured in burns, not in bare prompts: a batch is worth more
	# than its token count once it has been through a pipeline.
	var deadline_prompts: int = int(offer.get("deadline_prompts", 0))
	var token_requirement: float = float(offer.get("token_requirement", 0.0))
	var token_rate: float = float(sim.run_state.compute.get("token_rate", 1.0))
	var board_multiplier: float = float(
		ContentDatabase.balance.get("job_scaling", {}).get("board", {}).get("expected_progress_multiplier", 2.0)
	)
	var burns_needed: float = ceil(token_requirement / maxf(1.0, token_rate * board_multiplier))
	assert_true(deadline_prompts >= int(burns_needed), "Deadline allows job completion")
	assert_true(burns_needed >= 1.0 and burns_needed <= 5.0, "A contract takes a handful of deliberate burns")

	sim.accept_job(str(offer.get("id", "")))
	assert_true(sim.run_state.has_queued_jobs(), "Accepted job enters queue")
	var result: Dictionary = sim.start_work_sync()
	assert_true(result.get("ok", false), "The round's work executes")
	assert_false(sim.last_round_statement.is_empty(), "Resolving the work closes the round with the bills")

	# Measured at the statement rather than after it: the round's random event
	# lands on the same cash and is a separate system with its own tests, so
	# reading the live balance made this assertion a coin toss on the draw.
	var ending_cash: float = float(sim.last_round_statement.get("cash_after", 0.0))
	assert_true(ending_cash > starting_cash, "Completing a job increases cash")

	var refreshed_offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(refreshed_offers.size() > 0, "Job board refreshes for the next round")

	_test_angels_call_only_once_the_rent_has_cleared()
	_test_multi_job_session_resolves()
	_test_queued_options_and_summary()
	_test_queue_capacity_limits()
	_test_offer_variety()
	_test_prompts_advance_per_tick()
	_test_a_round_ends_only_when_every_contract_resolves()
	_test_round_end_bills_once()
	_test_bills_outlook_guides_spending()

	sim.free()


func _test_prompts_advance_per_tick() -> void:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(311)
	assert_eq(sim.prompts_used_this_round(), 0, "A fresh round has spent no prompts")

	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(offers.size() > 0, "Offers available for prompt advance test")
	sim.accept_job(str(offers[0].get("id", "")))
	sim.start_work_sync()
	# The statement signal is deferred so the UI opens on a settled state; the
	# statement itself is on the simulation the moment the round closes.
	var statement: Dictionary = sim.last_round_statement
	var summary_prompts: int = int(statement.get("prompts_used", 0))
	var accrued: float = float(statement.get("operating", 0.0))
	assert_eq(
		summary_prompts,
		int(sim.last_session_summary.get("ticks", 0)),
		"Each production tick spends exactly one prompt"
	)
	assert_true(accrued > 0.0, "And every prompt meters some running cost")
	sim.free()


## The whole point of the redesign: a round is however many prompts its contracts
## need. Rent cannot land while work is outstanding, so a contract far too big for
## a handful of prompts still gets worked to a conclusion inside its own round.
func _test_a_round_ends_only_when_every_contract_resolves() -> void:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(312)
	sim.run_state.economy["cash"] = 500000.0
	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(offers.size() > 0, "Offers available for round-length test")
	sim.accept_job(str(offers[0].get("id", "")))
	var queued: Dictionary = sim.run_state.business["job_queue"][0]
	var rate: float = float(sim.run_state.compute.get("token_rate", 1.0))
	queued["token_requirement"] = rate * 40.0
	queued["tokens_remaining"] = rate * 40.0
	queued["deadline_prompts"] = 80

	sim.start_work_sync()

	var statement: Dictionary = sim.last_round_statement
	assert_false(statement.is_empty(), "The round closes with a bill statement")
	assert_eq(
		int(statement.get("round", 0)), 1,
		"The bills land once, for the round that just finished rather than mid-contract"
	)
	assert_eq(sim.run_state.business.get("active_jobs", []).size(), 0, "Nothing is left outstanding")
	assert_true(
		int(sim.last_session_summary.get("prompts_used", 0)) > 12,
		"A big contract simply makes for a longer round rather than being cut off"
	)
	assert_false(sim.last_session_summary.has("carried"), "There is no carried state left to report")
	assert_eq(
		int(sim.last_session_summary.get("completed", 0)) + int(sim.last_session_summary.get("failed", 0)),
		1,
		"Every contract the round took is accounted for as delivered or missed"
	)
	assert_eq(int(sim.run_state.calendar.get("round", 0)), 2, "And the calendar moves on to the next round")
	assert_eq(float(sim.run_state.economy.get("costs_this_round", 0.0)), 0.0, "Accrued costs reset for the new round")
	sim.free()


func _test_round_end_bills_once() -> void:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(313)
	sim.run_state.economy["cash"] = 50000.0
	var rent: float = float(sim.run_state.economy.get("round_rent", 0.0))
	assert_true(rent > 0.0, "A run starts with rent to pay")

	var offers: Array = sim.run_state.business.get("job_offers", [])
	sim.accept_job(str(offers[0].get("id", "")))
	var cash_before: float = float(sim.run_state.economy.get("cash", 0.0))
	sim.start_work_sync()
	# The shop must not open on a balance that rent has already claimed.
	assert_false(sim.last_round_statement.is_empty(), "Bills settle before the shop opens")

	var statement: Dictionary = sim.last_round_statement
	assert_eq(statement.get("rent", 0.0), rent, "Statement charges the run's rent")
	assert_eq(statement.get("round", 0), 1, "Statement reports the round that just closed")
	assert_true(float(statement.get("operating", 0.0)) > 0.0, "Statement includes the operating costs burned")
	var cash_after: float = float(sim.run_state.economy.get("cash", 0.0))
	var reward: float = float(sim.last_session_summary.get("reward", 0.0))
	var expected: float = cash_before + reward - float(statement.get("round_total", 0.0))
	assert_true(absf(cash_after - expected) < 1.0, "Rent and running costs are each charged exactly once")
	assert_eq(sim.run_state.calendar.get("round", 0), 2, "The shop that follows the bills belongs to the new round")
	sim.free()


## The angel phase is the reward for keeping the lights on, so it hangs off the
## round's bills clearing rather than off finishing a contract. A run that
## defaults on the rent gets the next round's job board and nothing else.
func _test_angels_call_only_once_the_rent_has_cleared() -> void:
	var paid: Node = _sim_at_round_end(315, 50000.0)
	paid.start_work_sync()
	assert_true(
		bool(paid.last_round_statement.get("paid_in_full", false)),
		"A solvent run clears its bills"
	)
	assert_true(paid.phase == paid.Phase.ANGEL_ROUND, "And the angels call once it has")
	assert_true(paid.pending_choices.size() > 0, "With offers on the table")
	assert_eq(paid.draft_picks_remaining(), 1, "And is worth exactly one pick")
	# Angels give things away; anything with a price tag belongs on the Market.
	for offer in paid.pending_choices:
		assert_almost_eq(float(offer.get("cost", 0.0)), 0.0, 0.001, "Angel offers are free")
		assert_true(
			str(offer.get("type", "")) in ["perk", "module"],
			"An angel offers perks and modules, not purchases (%s)" % str(offer.get("type", ""))
		)
		assert_true(
			not offer.has("investor"),
			"Offers carry no persona of their own — the table belongs to the one investor"
		)
	paid.decline_offers()
	assert_true(paid.phase == paid.Phase.ROUND_PREP, "Declining them opens the next round's prep")
	paid.free()

	var accepted: Node = _sim_at_round_end(317, 50000.0)
	accepted.start_work_sync()
	if accepted.phase == accepted.Phase.ANGEL_ROUND and accepted.pending_choices.size() > 0:
		var taken: Dictionary = accepted.pending_choices[0]
		accepted.accept_offer(str(taken.get("type", "")), str(taken.get("id", "")))
		assert_true(
			accepted.phase != accepted.Phase.ANGEL_ROUND,
			"Taking an angel's offer closes the draft on the first pick"
		)
	accepted.free()

	var missed: Node = _sim_at_round_end(315, 0.0)
	missed.start_work_sync()
	assert_false(
		bool(missed.last_round_statement.get("paid_in_full", true)),
		"A broke run cannot cover the rent"
	)
	assert_true(missed.phase != missed.Phase.ANGEL_ROUND, "So no angel comes calling")
	assert_true(missed.pending_choices.is_empty(), "And there is nothing free to take")
	assert_eq(int(missed.run_state.calendar.get("round", 0)), 2, "The round still rolls over")
	missed.free()


## A run with one trivial contract on its slate, so working the round resolves it
## in a single prompt and settles the bills immediately.
func _sim_at_round_end(seed_value: int, cash: float) -> Node:
	var sim: Node = load("res://core/simulation.gd").new()
	sim.autosave_enabled = false
	sim.start_run(seed_value)
	sim.run_state.economy["cash"] = cash
	sim.run_state.business["job_queue"] = [{
		"id": "job.product_descriptions",
		"name": "Test",
		"token_requirement": 1.0,
		"tokens_remaining": 1.0,
		"deadline_prompts": 99,
		"prompts_remaining": 99,
		"reward": 20.0,
		"quality_threshold": 0.0,
		"quality": 0.0,
		"revision_risk": 0.0,
		"bug_chance": 0.0,
	}]
	return sim


## The shop is where an unaware player spends rent money, so it has to be able
## to say what is owed and when.
func _test_bills_outlook_guides_spending() -> void:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(314)
	sim.run_state.economy["cash"] = 1000.0
	var outlook: Dictionary = sim.bills_outlook()
	var due: float = float(outlook.get("due", 0.0))
	assert_true(due >= float(sim.run_state.economy.get("round_rent", 0.0)), "Bills due include the rent")
	assert_eq(int(outlook.get("prompts_used", -1)), 0, "A fresh round has not metered anything yet")
	assert_true(
		absf(float(outlook.get("spendable", 0.0)) - maxf(0.0, 1000.0 - due)) < 0.01,
		"Spendable cash holds back what the bills need"
	)

	assert_eq(sim.purchase_bill_warning(0.0), "", "Free choices carry no bill warning")
	assert_true(sim.purchase_bill_warning(1000.0) != "", "Spending the balance warns about the bills")
	sim.run_state.economy["cash"] = 100000.0
	assert_eq(sim.purchase_bill_warning(1000.0), "", "A comfortable balance carries no warning")
	sim.free()


## A fresh bedroom has one machine and therefore one posting. Tests that need
## two contracts install a second laptop so the board widens with the slots.
func _open_two_slots(sim: Node) -> void:
	var hardware: Array = Array(sim.run_state.build.get("hardware", []))
	hardware.append("used_laptop")
	sim.run_state.build["hardware"] = hardware
	var counts: Dictionary = Dictionary(sim.run_state.build.get("upgrade_counts", {}))
	counts["upgrade.used_laptop"] = int(counts.get("upgrade.used_laptop", 0)) + 1
	sim.run_state.build["upgrade_counts"] = counts
	sim.run_state.business["job_offers"] = []
	sim.run_state.business["job_board_stamp"] = ""
	sim.ensure_job_offers()


func _test_queue_capacity_limits() -> void:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(123)

	var empty_info: Dictionary = sim.queue_load_info()
	assert_eq(empty_info.get("jobs", -1), 0, "Empty queue reports no jobs")
	assert_eq(float(empty_info.get("ratio", -1.0)), 0.0, "Empty queue has no load")

	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(offers.size() >= 1, "Need an offer for capacity test")
	var first_id: String = str(offers[0].get("id", ""))
	assert_true(sim.can_accept_offer(first_id), "First offer always acceptable")
	assert_true(sim.accept_job(first_id), "First offer accepted")

	var info: Dictionary = sim.queue_load_info()
	assert_eq(info.get("jobs", -1), 1, "Queue load counts the accepted job")
	var rate: float = float(sim.run_state.compute.get("token_rate", 1.0))
	var expected_prompts: float = float(sim.run_state.business["job_queue"][0].get("token_requirement", 0.0)) / rate
	assert_true(absf(float(info.get("prompts_needed", 0.0)) - expected_prompts) < 0.001, "Prompts needed matches tokens over rate")
	assert_true(float(info.get("ratio", 0.0)) > 0.0, "Queued job produces load")

	# A contract far beyond the remaining deadline must be refused.
	var hopeless: Dictionary = sim.run_state.business["job_queue"][0].duplicate(true)
	hopeless["id"] = "job.test_hopeless"
	hopeless["token_requirement"] = rate * 500.0
	hopeless["deadline_prompts"] = 4
	sim.run_state.business["job_offers"].append(hopeless)
	assert_false(sim.can_accept_offer("job.test_hopeless"), "Hopeless overload is refused")
	assert_false(sim.accept_job("job.test_hopeless"), "Refused offer does not enter the queue")
	assert_eq(sim.run_state.business.get("job_queue", []).size(), 1, "Queue unchanged after refusal")

	# Just over capacity is still allowed.
	var cap: float = sim.queue_capacity_cap()
	var queued_prompts: float = float(info.get("prompts_needed", 0.0))
	var deadline: int = int(info.get("deadline_prompts", 1))
	var slightly_over: Dictionary = hopeless.duplicate(true)
	slightly_over["id"] = "job.test_slightly_over"
	slightly_over["deadline_prompts"] = deadline
	slightly_over["token_requirement"] = maxf(1.0, (float(deadline) * cap - queued_prompts - 0.5) * rate)
	sim.run_state.business["job_offers"].append(slightly_over)
	assert_true(sim.can_accept_offer("job.test_slightly_over"), "Load just under the cap is allowed")
	assert_true(sim.accept_job("job.test_slightly_over"), "Slightly over capacity accepted")
	assert_eq(sim.run_state.business.get("job_queue", []).size(), 2, "Second job queued")
	assert_true(float(sim.queue_load_info().get("ratio", 0.0)) > 1.0, "Queue now over capacity")
	sim.free()


func _test_offer_variety() -> void:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(2024)
	_open_two_slots(sim)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(offers.size() >= 2, "Two machines open two postings")
	var unique_ids: Dictionary = {}
	for offer in offers:
		unique_ids[str(offer.get("id", ""))] = true
	assert_eq(unique_ids.size(), offers.size(), "Round 1 offers are distinct contracts")

	# The board must not reroll when the UI asks it to refresh.
	var first_id: String = str(offers[0].get("id", ""))
	var first_tokens: float = float(offers[0].get("token_requirement", 0.0))
	sim.ensure_job_offers()
	sim.ensure_job_offers()
	var again: Array = sim.run_state.business.get("job_offers", [])
	assert_eq(again.size(), offers.size(), "Board size stable across refreshes")
	assert_eq(str(again[0].get("id", "")), first_id, "Board contents stable across refreshes")
	assert_eq(float(again[0].get("token_requirement", 0.0)), first_tokens, "Offer scaling stable across refreshes")
	sim.free()


func _test_queued_options_and_summary() -> void:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(77)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(offers.size() > 0, "Offers available for queued-option test")
	sim.accept_job(str(offers[0].get("id", "")))
	sim.set_queued_boost(true)
	assert_true(sim.queued_boost, "Boost can be queued before starting work")
	var result: Dictionary = sim.start_work_sync()
	assert_true(result.get("ok", false), "A round with armed options runs")
	assert_false(sim.queued_boost, "Armed boost consumed on the round's first prompt")
	var summary: Dictionary = sim.last_session_summary
	assert_false(summary.is_empty(), "Round debrief built after work")
	assert_true(summary.has("reward"), "Debrief reports reward")
	assert_true(summary.has("cash_after"), "Debrief reports cash after")
	assert_true(summary.has("prompts_used"), "Debrief reports how long the round took")
	assert_true(float(summary.get("tokens_processed", 0.0)) > 0.0, "Debrief counts processed tokens")
	# Options can only be armed with contracts waiting to be worked.
	sim.set_queued_boost(true)
	assert_false(sim.queued_boost, "Boost cannot be armed with nothing on the slate")
	sim.free()


func _test_multi_job_session_resolves() -> void:
	var sim_script: GDScript = load("res://core/simulation.gd")
	var sim: Node = sim_script.new()
	sim.autosave_enabled = false
	sim.start_run(99)
	_open_two_slots(sim)
	var offers: Array = sim.run_state.business.get("job_offers", [])
	assert_true(offers.size() >= 2, "Need at least 2 offers for multi-job test")
	var job_count: int = mini(3, offers.size())
	var offer_ids: Array = []
	for i in range(job_count):
		offer_ids.append(str(offers[i].get("id", "")))
	# Queue through the job system directly: this test covers the production
	# tick, not the player-facing queue capacity limit.
	for offer_id in offer_ids:
		sim._job_system.accept_job(sim.run_state, offer_id)
	assert_eq(sim.run_state.business.get("job_queue", []).size(), job_count, "Jobs queued for multi-job test")

	var job_system: JobSystem = JobSystem.new()
	var active_jobs: Array = []
	for offer in sim.run_state.business.get("job_queue", []):
		active_jobs.append(job_system._prepare_job(offer, sim.run_state, ContentDatabase))
	sim.run_state.business["active_jobs"] = active_jobs
	sim.run_state.business["job_queue"] = []

	active_jobs[0]["tokens_remaining"] = 0.0
	active_jobs[0]["shipped"] = true
	for i in range(1, job_count):
		active_jobs[i]["abandoned"] = true

	var result: Dictionary = job_system.run_production_tick(
		sim.run_state,
		sim.rng.derive("multi_job_test"),
		sim.effect_resolver,
		sim._collect_subscriptions(),
		sim.tuning,
		sim._compute_system,
		sim._heat_system,
		sim._economy_system
	)
	assert_true(result.get("all_resolved", false), "Mixed batch resolves when each job completes or fails")
	assert_true(result.get("any_failed", false), "Failed jobs counted")
	assert_eq(int(result.get("completed_count", 0)), 1, "One job completed")
	assert_eq(int(result.get("failed_count", 0)), job_count - 1, "Remaining jobs failed")
	sim.free()
