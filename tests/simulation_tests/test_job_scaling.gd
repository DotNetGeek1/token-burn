extends TestCase


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	var job_system := JobSystem.new()
	var state := RunState.new()
	var job_def: JobDefinition = ContentDatabase.get_job("job.product_descriptions")
	assert_true(job_def != null, "Test job exists")

	var round1: Dictionary = job_system._scale_job(job_def, 1, ContentDatabase, {}, state)
	var round6: Dictionary = job_system._scale_job(job_def, 6, ContentDatabase, {}, state)
	assert_true(
		float(round6.get("token_requirement", 0.0)) > float(round1.get("token_requirement", 0.0)),
		"Token requirement grows across a location's own year"
	)

	var queued: Dictionary = round1.duplicate(true)
	state.business["job_queue"] = [queued]
	var requirement_before: float = float(state.business["job_queue"][0].get("token_requirement", 0.0))
	job_system.refresh_contract_board(state, DeterministicRng.new(1), ContentDatabase, {})
	var requirement_after: float = float(state.business["job_queue"][0].get("token_requirement", 0.0))
	assert_eq(requirement_before, requirement_after, "Accepted contracts are not rescaled")

	_test_the_board_follows_the_location(job_system)
	_test_upgrades_are_not_matched_by_the_work(job_system)
	_test_rewards_follow_the_hardware_ladder(job_system)
	_test_hard_pays_less_for_more_work(job_system)
	_test_strong_rigs_open_authored_work_without_rescaling_local_jobs(job_system)
	_test_late_bands_have_distinct_ordinary_work(job_system)
	_test_offer_count_is_the_larger_of_demand_and_slots(job_system)
	_test_a_large_board_keeps_one_local_posting(job_system)


## The whole point of the seven-chapter ladder: the garage must not be handed the
## contracts the moon was written for. Tier used to be read off a round counter
## with a location offset bolted on, which put every location from the garage up
## permanently at the top tier from its first round.
func _test_the_board_follows_the_location(job_system: JobSystem) -> void:
	var bands: Array = JobSystem.location_bands(ContentDatabase)
	assert_true(bands.size() >= 7, "Every location has a band of its own")
	for tier in range(bands.size()):
		var state := RunState.new()
		state.build["dwelling"] = str(Dictionary(bands[tier]).get("location", ""))
		assert_eq(
			JobSystem.location_tier(state, ContentDatabase),
			tier,
			"%s reads as tier %d" % [str(Dictionary(bands[tier]).get("location", "")), tier]
		)
		# Reputation starts far below the stretch threshold, so a fresh run in
		# the room sees only the room's own work.
		state.business["reputation"] = 0.0
		for candidate in job_system._collect_eligible_jobs(ContentDatabase, 1, tier):
			assert_true(
				job_system._job_tier(candidate, ContentDatabase) <= tier,
				"%s is not offered work from above its band" % str(state.build["dwelling"])
			)


## A rig that has grown ten times over must destroy the work that used to be
## hard, rather than being handed a contract ten times bigger.
func _test_upgrades_are_not_matched_by_the_work(job_system: JobSystem) -> void:
	var job_def: JobDefinition = ContentDatabase.get_job("job.product_descriptions")
	var weak := RunState.new()
	weak.compute["token_rate"] = 1_000_000.0
	var strong := RunState.new()
	strong.compute["token_rate"] = 100_000_000.0

	var weak_job: Dictionary = job_system._scale_job(job_def, 3, ContentDatabase, {}, weak)
	var strong_job: Dictionary = job_system._scale_job(job_def, 3, ContentDatabase, {}, strong)
	assert_almost_eq(
		float(strong_job.get("token_requirement", 0.0)),
		float(weak_job.get("token_requirement", 0.0)),
		1.0,
		"The same posting asks for the same work however good the rig reading it is"
	)
	assert_eq(
		int(strong_job.get("deadline_prompts", 0)),
		int(weak_job.get("deadline_prompts", 0)),
		"And allows the same time, so the fast rig delivers early"
	)


func _test_strong_rigs_open_authored_work_without_rescaling_local_jobs(job_system: JobSystem) -> void:
	var state := RunState.new()
	state.build["dwelling"] = "garage"
	state.build["hardware"] = ["custom_desktop", "gpu_rack"]
	state.business["demand"] = 3.0
	state.business["reputation"] = 0.0
	job_system.generate_offers(state, DeterministicRng.new(4040), ContentDatabase, {})
	var offers: Array = state.business.get("job_offers", [])
	assert_eq(offers.size(), 3, "The stronger rig still receives a full board")
	var matched: int = 0
	var local: int = 0
	for offer in offers:
		if int(offer.get("tier", -1)) == 2 and bool(offer.get("rig_matched", false)):
			matched += 1
		if int(offer.get("tier", -1)) <= 1:
			local += 1
	assert_eq(matched, 2, "Two offers come from the GPU rack's authored work tier")
	assert_eq(local, 1, "One familiar local posting remains on the board")


func _test_offer_count_is_the_larger_of_demand_and_slots(job_system: JobSystem) -> void:
	var modest := RunState.new()
	modest.build["hardware"] = ["used_laptop"]
	modest.business["demand"] = 3.0
	job_system.generate_offers(modest, DeterministicRng.new(11), ContentDatabase, {})
	assert_eq(
		Array(modest.business.get("job_offers", [])).size(), 3,
		"A one-machine rig still sees a demand-sized board"
	)

	var pair := RunState.new()
	pair.build["hardware"] = ["custom_desktop", "gpu_rack"]
	pair.business["demand"] = 3.0
	job_system.generate_offers(pair, DeterministicRng.new(12), ContentDatabase, {})
	assert_eq(
		Array(pair.business.get("job_offers", [])).size(), 3,
		"Two machines and demand 3 still open three postings"
	)

	var fleet := RunState.new()
	fleet.build["hardware"] = ["gpu_rack", "gpu_rack", "gpu_rack", "gpu_rack", "gpu_rack"]
	fleet.business["demand"] = 3.0
	job_system.generate_offers(fleet, DeterministicRng.new(13), ContentDatabase, {})
	assert_eq(
		Array(fleet.business.get("job_offers", [])).size(), 5,
		"Five machines open five postings even when demand is three"
	)

	var advertised := RunState.new()
	advertised.build["hardware"] = ["used_laptop"]
	advertised.business["demand"] = 8.0
	job_system.generate_offers(advertised, DeterministicRng.new(14), ContentDatabase, {})
	assert_eq(
		Array(advertised.business.get("job_offers", [])).size(), 8,
		"Demand at the cap is no longer discarded by a five-offer clamp"
	)


func _test_a_large_board_keeps_one_local_posting(job_system: JobSystem) -> void:
	var state := RunState.new()
	state.build["dwelling"] = "garage"
	state.build["hardware"] = ["gpu_rack", "gpu_rack", "gpu_rack", "gpu_rack"]
	state.business["demand"] = 3.0
	state.business["reputation"] = 0.0
	job_system.generate_offers(state, DeterministicRng.new(4041), ContentDatabase, {})
	var offers: Array = state.business.get("job_offers", [])
	assert_eq(offers.size(), 4, "Four machines beat demand-3 and open a four-card board")
	assert_true(offers.size() > 3, "The board is larger than the old default")
	var matched: int = 0
	var local: int = 0
	for offer in offers:
		if int(offer.get("tier", -1)) == 2 and bool(offer.get("rig_matched", false)):
			matched += 1
		if int(offer.get("tier", -1)) <= 1:
			local += 1
	assert_eq(local, 1, "A stronger rig still keeps exactly one local posting")
	assert_eq(matched, offers.size() - 1, "The rest of the board is the rack's authored work")


func _test_late_bands_have_distinct_ordinary_work(job_system: JobSystem) -> void:
	for tier in [4, 5, 6]:
		var ordinary: int = 0
		for job_def in ContentDatabase.jobs:
			if job_def.tier == tier and not job_def.windfall:
				ordinary += 1
		assert_true(ordinary >= 3, "Tier %d has at least three ordinary authored jobs" % tier)


## A location's ordinary work should be a meaningful chunk of its next machine,
## not the whole shop. Only contracts flagged as windfalls are allowed to buy a
## rung of the ladder outright.
func _test_rewards_follow_the_hardware_ladder(job_system: JobSystem) -> void:
	var bands: Array = JobSystem.location_bands(ContentDatabase)
	for tier in range(bands.size()):
		var band: Dictionary = Dictionary(bands[tier])
		var ceiling: float = float(band.get("major_purchase", 0.0)) * 0.75
		assert_true(ceiling > 0.0, "%s names the machine its work is priced against" % str(band.get("location", "")))
		var state := RunState.new()
		state.build["dwelling"] = str(band.get("location", ""))
		state.business["reputation"] = 0.0
		for job_def in ContentDatabase.jobs:
			if job_def.tier != tier or job_def.windfall:
				continue
			var offer: Dictionary = job_system._scale_job(job_def, 1, ContentDatabase, {}, state)
			assert_true(
				float(offer.get("reward", 0.0)) <= ceiling,
				"%s pays %s, under the %s the %s ladder is priced against" % [
					job_def.name,
					NumberFormat.format_cash(float(offer.get("reward", 0.0))),
					NumberFormat.format_cash(ceiling),
					str(band.get("location", "")),
				]
			)


## Difficulty is snapshotted into the run's flags at reset, and job scaling is
## where it is meant to bite. Easy to reintroduce silently, so the relationship
## is asserted directly: the same contract, the same seed, both difficulties.
func _test_hard_pays_less_for_more_work(job_system: JobSystem) -> void:
	var job_def := JobDefinition.new()
	job_def.id = "job.difficulty_probe"
	job_def.name = "Difficulty Probe"
	job_def.tier = 2
	job_def.work_units = 1.0
	# Well clear of the reward floor that guarantees a contract pays for the
	# round it occupies, which would otherwise hide the multipliers under test.
	job_def.reward_units = 4.0

	var normal := RunState.new()
	normal.flags["difficulty"] = "normal"
	var hard := RunState.new()
	hard.flags["difficulty"] = "hard"
	for state in [normal, hard]:
		state.compute["token_rate"] = 1000000.0

	var normal_job: Dictionary = job_system._scale_job(
		job_def, 8, ContentDatabase, {}, normal, DeterministicRng.new(31337)
	)
	var hard_job: Dictionary = job_system._scale_job(
		job_def, 8, ContentDatabase, {}, hard, DeterministicRng.new(31337)
	)
	assert_true(
		float(hard_job.get("reward", 0.0)) < float(normal_job.get("reward", 0.0)),
		"A hard run is paid less for the same contract"
	)
	assert_true(
		float(hard_job.get("token_requirement", 0.0)) > float(normal_job.get("token_requirement", 0.0)),
		"And has to burn more to deliver it"
	)
