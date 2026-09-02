extends TestCase

const WorkflowMastery := preload("res://systems/workflow_mastery_system.gd")


func run() -> void:
	if ContentDatabase.jobs.is_empty():
		ContentDatabase.reload()
	_test_quality_mult_scales_only_positive_quality()
	_test_thermal_mult_divides_only_positive_heat()
	_test_created_then_fixed_is_not_clean()
	_test_preview_does_not_train_a_workflow()
	_test_first_try_trains_output_once()
	_test_knowledge_sharing_copies_and_silos_do_not()
	_test_golden_path_strips_a_real_stack()
	_test_no_free_lunch_heats_trained_output()
	_test_angel_offers_skip_undraftable_perks()
	_test_axis_and_combo_mastery_perks()
	_test_created_then_fixed_contract_is_not_clean()
	_test_mastery_trains_the_assigned_workflow()
	_test_blocked_benchmark_harness_does_not_discount_hardware()
	_test_mastery_trace_names_its_workflow_and_evidence()
	_test_preview_leaves_job_evidence_unchanged()
	_test_inspect_burn_does_not_mutate_statistics()
	_test_golden_path_does_not_strip_same_evaluation_gain()
	_test_benchmark_harness_coupon_does_not_stack()


class Harness:
	extends RefCounted

	var board := BoardSystem.new()
	var jobs := JobSystem.new()
	var heat := HeatSystem.new()
	var economy := EconomySystem.new()
	var compute := ComputeSystem.new()
	var resolver := EffectResolver.new()
	var state := RunState.new()
	var rng: DeterministicRng
	var job: Dictionary

	func _init(seed_value: int = 2026) -> void:
		rng = DeterministicRng.new(seed_value)
		board.ensure_board(state, ContentDatabase)
		job = {
			"id": "job.mastery",
			"name": "Mastery Contract",
			"token_requirement": 100.0,
			"tokens_remaining": 100.0,
			"quality": 0.0,
			"quality_threshold": 40.0,
			"known_bugs": 0,
			"hidden_bugs": 0,
			"blocked_slots": 0,
			"board_rules": [],
			"tags": [],
			"bug_chance": 0.0,
			"revision_risk": 0.0,
			"deadline_prompts": 6,
			"prompts_remaining": 6,
			"workflow_id": "workflow.1",
		}
		JobSystem.normalize_job_evidence(job)
		state.business["active_jobs"] = [job]
		state.business["focused_job_id"] = "job.mastery"

	func pipeline(module_ids: Array) -> void:
		var owned: Array = board.owned_modules(state)
		for id in module_ids:
			if not (str(id) in owned):
				owned.append(str(id))
		state.build["modules"] = owned
		var slots: Array = board.slots(state)
		for i in range(slots.size()):
			slots[i] = str(module_ids[i]) if i < module_ids.size() else ""

	func equip(perk_id: String) -> Array:
		var perk: PerkDefinition = ContentDatabase.get_perk(perk_id)
		assert(perk != null)
		if not (perk_id in Array(state.build.get("perk_inventory", []))):
			state.build["perk_inventory"] = Array(state.build.get("perk_inventory", [])) + [perk_id]
		if not (perk_id in Array(state.build.get("perks", []))):
			state.build["perks"] = Array(state.build.get("perks", [])) + [perk_id]
		var subs: Array = []
		for sub in perk.subscriptions:
			var copy: Dictionary = sub.duplicate(true)
			copy["source_id"] = perk.id
			copy["parameters"] = perk.parameters.duplicate(true)
			subs.append(copy)
		return subs

	func resolve(tokens: float = 1000.0, subscriptions: Array = []) -> Dictionary:
		return board.resolve_burn(state, job, tokens, rng, resolver, subscriptions)

	func commit(tokens: float = 1000.0, subscriptions: Array = []) -> Dictionary:
		state.compute["token_rate"] = tokens
		return jobs.run_burn(
			state, rng, resolver, subscriptions, {}, compute, heat, economy, board
		)

	func finish_clean(subscriptions: Array) -> Dictionary:
		pipeline(["op.prompt"])
		job["token_requirement"] = 1.0
		job["tokens_remaining"] = 1.0
		return commit(1_000_000.0, subscriptions)

	func evaluate_now(subscriptions: Array, remaining_before: float = 1.0) -> Dictionary:
		return WorkflowMastery.evaluate(
			state, job, {}, remaining_before, resolver, subscriptions, rng, ResolveMode.COMMIT
		)


func _test_quality_mult_scales_only_positive_quality() -> void:
	var harness := Harness.new()
	harness.pipeline(["op.prompt"])
	BoardSystem.normalize_workflow_fields(harness.board.active_workflow(harness.state))
	harness.board.active_workflow(harness.state)["quality_mult"] = 2.0
	var burn: Dictionary = harness.resolve(100.0)
	assert_true(float(burn.get("quality", 0.0)) > 4.0, "Positive pipeline quality is multiplied")
	harness = Harness.new(7)
	harness.pipeline(["op.liquid_cooling"])
	harness.board.active_workflow(harness.state)["thermal_mult"] = 2.0
	var cool: Dictionary = harness.resolve(100.0)
	assert_true(float(cool.get("heat", 0.0)) < 0.0, "Cooling stays negative under THERMAL")


func _test_thermal_mult_divides_only_positive_heat() -> void:
	var harness := Harness.new(8)
	harness.pipeline(["op.overclock"])
	BoardSystem.normalize_workflow_fields(harness.board.active_workflow(harness.state))
	var hot: Dictionary = harness.resolve(100.0)
	harness.board.active_workflow(harness.state)["thermal_mult"] = 2.0
	var cooler: Dictionary = harness.resolve(100.0)
	assert_true(
		float(cooler.get("heat", 0.0)) < float(hot.get("heat", 0.0)),
		"THERMAL divides positive pipeline heat"
	)


func _test_created_then_fixed_is_not_clean() -> void:
	var harness := Harness.new(9)
	harness.pipeline(["op.cheap_model", "op.unit_tests"])
	var result: Dictionary = harness.resolve(200.0)
	assert_true(int(result.get("bugs_created", 0)) > 0, "A bug-creating stage increments bugs_created")
	assert_true(int(result.get("fixed", 0)) > 0, "A later stage fixes the created bug")
	assert_eq(int(result.get("bugs_added", -1)), 0, "Net bug delta is clean after the repair")
	var buried := Harness.new(12)
	buried.pipeline(["op.crash_dump"])
	var hidden: Dictionary = buried.resolve(200.0)
	assert_true(
		int(hidden.get("hidden_bugs_created", 0)) > 0,
		"A hidden-bug stage increments hidden_bugs_created"
	)


func _test_preview_does_not_train_a_workflow() -> void:
	var harness := Harness.new(12)
	harness.pipeline(["op.prompt"])
	harness.job["token_requirement"] = 1.0
	harness.job["tokens_remaining"] = 1.0
	var before: float = float(harness.board.active_workflow(harness.state).get("output_mult", 1.0))
	harness.jobs.run_burn(
		harness.state, harness.rng, harness.resolver, harness.equip("perk.first_try"),
		{}, harness.compute, harness.heat, harness.economy, harness.board, -1, ResolveMode.PREVIEW
	)
	assert_almost_eq(
		float(harness.board.active_workflow(harness.state).get("output_mult", 1.0)),
		before,
		0.001,
		"Preview burns do not train mastery"
	)


func _test_first_try_trains_output_once() -> void:
	var harness := Harness.new(13)
	var subs: Array = harness.equip("perk.first_try")
	harness.finish_clean(subs)
	assert_almost_eq(
		float(harness.board.active_workflow(harness.state).get("output_mult", 1.0)),
		1.08,
		0.001,
		"A one-shot trains First Try +0.08 OUTPUT"
	)
	assert_true(bool(harness.job.get("mastery_evaluated", false)), "Mastery evaluates on token complete")
	harness.job["tokens_remaining"] = 0.0
	harness.commit(1_000_000.0, subs)
	assert_almost_eq(
		float(harness.board.active_workflow(harness.state).get("output_mult", 1.0)),
		1.08,
		0.001,
		"A later polish burn does not train again"
	)


func _test_knowledge_sharing_copies_and_silos_do_not() -> void:
	var harness := Harness.new(14)
	harness.state.build["meta_workflow_bonus"] = 1
	harness.board.ensure_board(harness.state, ContentDatabase)
	harness.board.create_workflow(harness.state, "Second Opinion", ContentDatabase)
	harness.board.set_active_workflow(harness.state, 0)
	var subs: Array = harness.equip("perk.first_try")
	subs.append_array(harness.equip("perk.knowledge_sharing"))
	harness.finish_clean(subs)
	var source: Dictionary = harness.board.workflow_at(harness.state, 0)
	var other: Dictionary = harness.board.workflow_at(harness.state, 1)
	assert_almost_eq(float(source.get("output_mult", 1.0)), 1.08, 0.001, "Source workflow trains +0.08")
	assert_almost_eq(float(other.get("output_mult", 1.0)), 1.04, 0.001, "Knowledge Sharing copies half")

	var silo := Harness.new(15)
	silo.state.build["meta_workflow_bonus"] = 1
	silo.board.ensure_board(silo.state, ContentDatabase)
	silo.board.create_workflow(silo.state, "Second Opinion", ContentDatabase)
	silo.board.set_active_workflow(silo.state, 0)
	var silo_subs: Array = silo.equip("perk.first_try")
	silo_subs.append_array(silo.equip("perk.specialist_silos"))
	silo.finish_clean(silo_subs)
	assert_almost_eq(
		float(silo.board.workflow_at(silo.state, 0).get("output_mult", 1.0)),
		1.12,
		0.001,
		"Specialist Silos grows the source by 50%"
	)
	assert_almost_eq(
		float(silo.board.workflow_at(silo.state, 1).get("output_mult", 1.0)),
		1.0,
		0.001,
		"Specialist Silos blocks propagation"
	)


func _test_golden_path_strips_a_real_stack() -> void:
	var harness := Harness.new(16)
	var subs: Array = harness.equip("perk.first_try")
	subs.append_array(harness.equip("perk.clean_compile"))
	subs.append_array(harness.equip("perk.golden_path"))
	harness.finish_clean(subs)
	assert_almost_eq(
		float(harness.board.active_workflow(harness.state).get("output_mult", 1.0)),
		1.16,
		0.001,
		"Golden Path doubles a clean one-shot First Try"
	)
	harness.job["mastery_evaluated"] = false
	harness.job["burn_count"] = 2
	harness.job["bugs_created"] = 1
	harness.job["hidden_bugs_created"] = 0
	harness.job["tokens_remaining"] = 0.0
	harness.evaluate_now(subs, 10.0)
	assert_almost_eq(
		float(harness.board.active_workflow(harness.state).get("output_mult", 1.0)),
		1.0,
		0.001,
		"A dirty completion peels the latest OUTPUT stack"
	)
	assert_almost_eq(
		float(harness.board.active_workflow(harness.state).get("quality_mult", 1.0)),
		1.0,
		0.001,
		"A dirty completion peels the latest QUALITY stack"
	)


func _test_no_free_lunch_heats_trained_output() -> void:
	var harness := Harness.new(17)
	harness.pipeline(["op.overclock"])
	BoardSystem.normalize_workflow_fields(harness.board.active_workflow(harness.state))
	var baseline: Dictionary = harness.resolve(100.0)
	harness.board.active_workflow(harness.state)["output_mult"] = 3.0
	var lunch: Dictionary = harness.resolve(100.0, harness.equip("perk.no_free_lunch"))
	assert_true(
		float(lunch.get("heat", 0.0)) > float(baseline.get("heat", 0.0)),
		"No Free Lunch adds heat from whole OUTPUT stacks"
	)


func _test_angel_offers_skip_undraftable_perks() -> void:
	var rng := DeterministicRng.new(99)
	var state := RunState.new()
	state.reset()
	var blocked: Array = ["perk.first_try"]
	var offers: Array = ContentDatabase.draw_angel_offers(rng, state, 8, [], 0.0, blocked)
	for offer in offers:
		assert_false(
			str(offer.get("id", "")) == "perk.first_try",
			"Blocked perk ids stay out of the angel table"
		)


func _test_axis_and_combo_mastery_perks() -> void:
	var clean := Harness.new(21)
	clean.finish_clean(clean.equip("perk.clean_compile"))
	assert_almost_eq(
		float(clean.board.active_workflow(clean.state).get("quality_mult", 1.0)),
		1.08,
		0.001,
		"Clean Compile trains QUALITY"
	)
	var cool := Harness.new(22)
	cool.finish_clean(cool.equip("perk.cool_operator"))
	assert_almost_eq(
		float(cool.board.active_workflow(cool.state).get("thermal_mult", 1.0)),
		1.08,
		0.001,
		"Cool Operator trains THERMAL"
	)
	var golden := Harness.new(23)
	golden.finish_clean(golden.equip("perk.golden_run"))
	assert_almost_eq(
		float(golden.board.active_workflow(golden.state).get("output_mult", 1.0)),
		1.05,
		0.001,
		"Golden Run trains OUTPUT"
	)
	assert_almost_eq(
		float(golden.board.active_workflow(golden.state).get("quality_mult", 1.0)),
		1.05,
		0.001,
		"Golden Run trains QUALITY"
	)
	var sustainable := Harness.new(24)
	sustainable.finish_clean(sustainable.equip("perk.sustainable_engineering"))
	assert_almost_eq(
		float(sustainable.board.active_workflow(sustainable.state).get("quality_mult", 1.0)),
		1.05,
		0.001,
		"Sustainable Engineering trains QUALITY"
	)
	assert_almost_eq(
		float(sustainable.board.active_workflow(sustainable.state).get("thermal_mult", 1.0)),
		1.05,
		0.001,
		"Sustainable Engineering trains THERMAL"
	)
	var benchmark := Harness.new(25)
	benchmark.finish_clean(benchmark.equip("perk.benchmark_chaser"))
	assert_almost_eq(
		float(benchmark.board.active_workflow(benchmark.state).get("output_mult", 1.0)),
		1.05,
		0.001,
		"Benchmark Chaser trains on a 2× overkill"
	)
	var perpetual := Harness.new(26)
	perpetual.finish_clean(perpetual.equip("perk.perpetual_benchmark"))
	assert_almost_eq(
		float(perpetual.board.active_workflow(perpetual.state).get("output_mult", 1.0)),
		1.08,
		0.001,
		"Perpetual Benchmark adds an extra First Try-sized gain"
	)
	var redline := Harness.new(27)
	redline.state.compute["heat_capacity"] = 100.0
	redline.state.compute["heat"] = 90.0
	redline.finish_clean(redline.equip("perk.redline_graduate"))
	assert_almost_eq(
		float(redline.board.active_workflow(redline.state).get("output_mult", 1.0)),
		1.12,
		0.001,
		"Redline Graduate trains OUTPUT from a hot one-shot"
	)


func _test_created_then_fixed_contract_is_not_clean() -> void:
	var harness := Harness.new(28)
	harness.pipeline(["op.cheap_model", "op.unit_tests"])
	harness.job["token_requirement"] = 1.0
	harness.job["tokens_remaining"] = 1.0
	harness.commit(1_000_000.0, harness.equip("perk.clean_compile"))
	assert_true(int(harness.job.get("bugs_created", 0)) > 0, "The job remembers the repaired bug")
	assert_almost_eq(
		float(harness.board.active_workflow(harness.state).get("quality_mult", 1.0)),
		1.0,
		0.001,
		"Created-then-fixed is still dirty for mastery"
	)


func _test_mastery_trains_the_assigned_workflow() -> void:
	var harness := Harness.new(29)
	harness.state.build["meta_workflow_bonus"] = 1
	harness.board.ensure_board(harness.state, ContentDatabase)
	var second: Dictionary = harness.board.create_workflow(
		harness.state, "Second Opinion", ContentDatabase
	)
	harness.job["workflow_id"] = str(second.get("id", ""))
	harness.finish_clean(harness.equip("perk.first_try"))
	assert_almost_eq(
		float(harness.board.workflow_at(harness.state, 0).get("output_mult", 1.0)),
		1.0,
		0.001,
		"The editor's first workflow is unchanged"
	)
	assert_almost_eq(
		float(harness.board.workflow_at(harness.state, 1).get("output_mult", 1.0)),
		1.08,
		0.001,
		"The workflow assigned to the contract receives mastery"
	)


func _test_blocked_benchmark_harness_does_not_discount_hardware() -> void:
	var blocked := Harness.new(30)
	blocked.pipeline(["op.benchmark_harness", "op.prompt"])
	blocked.job["blocked_slots"] = 1
	blocked.job["token_requirement"] = 1.0
	blocked.job["tokens_remaining"] = 1.0
	blocked.commit(1_000_000.0)
	assert_almost_eq(
		float(blocked.state.build.get("hardware_discount", 0.0)),
		0.0,
		0.001,
		"A completion module in a blocked slot does not fire"
	)
	var reached := Harness.new(31)
	reached.pipeline(["op.prompt", "op.benchmark_harness"])
	reached.job["token_requirement"] = 1.0
	reached.job["tokens_remaining"] = 1.0
	reached.commit(1_000_000.0)
	assert_almost_eq(
		float(reached.state.build.get("hardware_discount", 0.0)),
		0.1,
		0.001,
		"A reached Benchmark Harness discounts the next hardware purchase"
	)
	var hardware: UpgradeDefinition = null
	for upgrade in ContentDatabase.upgrades:
		if upgrade.category == "hardware":
			hardware = upgrade
			break
	assert_true(hardware != null, "The catalog has hardware to discount")
	if hardware != null:
		var base: float = UpgradeSystem.purchase_cost(hardware, 0)
		assert_almost_eq(
			UpgradeSystem.quoted_cost(reached.state, hardware, 0),
			base * 0.9,
			0.01,
			"The discount reaches the hardware quote"
		)
		UpgradeSystem.consume_hardware_discount(reached.state)
		assert_almost_eq(
			UpgradeSystem.quoted_cost(reached.state, hardware, 0),
			base,
			0.01,
			"The one-shot discount is consumed"
		)


func _test_mastery_trace_names_its_workflow_and_evidence() -> void:
	var harness := Harness.new(32)
	harness.finish_clean(harness.equip("perk.first_try"))
	var found: bool = false
	for entry in harness.resolver.get_trace():
		if str(entry.get("event_name", "")) != WorkflowMastery.EVENT_EVALUATED:
			continue
		var metadata: Dictionary = Dictionary(entry.get("metadata", {}))
		if str(metadata.get("workflow_id", "")) == "workflow.1" \
				and bool(metadata.get("one_shot", false)) \
				and bool(metadata.get("clean", false)):
			found = true
			break
	assert_true(found, "Mastery traces include workflow and completion evidence")


func _test_preview_leaves_job_evidence_unchanged() -> void:
	var harness := Harness.new(33)
	harness.pipeline(["op.overclock"])
	harness.state.compute["heat"] = 40.0
	var before: Dictionary = {
		"burn_count": harness.job.get("burn_count"),
		"bugs_created": harness.job.get("bugs_created"),
		"hidden_bugs_created": harness.job.get("hidden_bugs_created"),
		"peak_heat_ratio": harness.job.get("peak_heat_ratio"),
	}
	harness.jobs.run_burn(
		harness.state, harness.rng, harness.resolver, [],
		{}, harness.compute, harness.heat, harness.economy, harness.board, -1, ResolveMode.PREVIEW
	)
	for key in before:
		assert_eq(harness.job.get(key), before[key], "Preview leaves %s unchanged" % key)


func _test_inspect_burn_does_not_mutate_statistics() -> void:
	var harness := Harness.new(36)
	harness.pipeline(["op.cheap_model", "op.agent_swarm"])
	harness.state.compute["token_rate"] = 1000.0
	var repeats_before: int = int(harness.state.statistics.get("stage_repeats", 0))
	var cascades_before: int = int(harness.state.statistics.get("cascades_triggered", 0))
	var inspected: Dictionary = harness.jobs.inspect_burn(
		harness.state, harness.rng, harness.resolver, [], {}, harness.compute, harness.board
	)
	assert_true(inspected.get("ok", false), "Inspection resolves a repeating pipeline")
	assert_eq(
		int(harness.state.statistics.get("stage_repeats", 0)),
		repeats_before,
		"inspect_burn does not increment stage_repeats"
	)
	assert_eq(
		int(harness.state.statistics.get("cascades_triggered", 0)),
		cascades_before,
		"inspect_burn does not increment cascades_triggered"
	)
	var committed: Dictionary = harness.resolve(1000.0)
	assert_true(
		int(committed.get("bugs_created", 0)) > 0,
		"The same pipeline creates bugs when committed"
	)
	assert_true(
		int(harness.state.statistics.get("stage_repeats", 0)) > repeats_before,
		"A committed repeat still records telemetry"
	)


func _test_golden_path_does_not_strip_same_evaluation_gain() -> void:
	var harness := Harness.new(37)
	var subs: Array = harness.equip("perk.first_try")
	subs.append_array(harness.equip("perk.golden_path"))
	harness.finish_clean(subs)
	assert_almost_eq(
		float(harness.board.active_workflow(harness.state).get("output_mult", 1.0)),
		1.16,
		0.001,
		"A clean one-shot trains the doubled First Try stack"
	)
	harness.job["mastery_evaluated"] = false
	harness.job["burn_count"] = 1
	harness.job["bugs_created"] = 1
	harness.job["hidden_bugs_created"] = 0
	harness.job["tokens_remaining"] = 0.0
	var report: Dictionary = harness.evaluate_now(subs, 10.0)
	assert_almost_eq(
		float(report.get("stripped_output", 0.0)),
		0.16,
		0.001,
		"Golden Path peels the stack that existed before this evaluation"
	)
	assert_almost_eq(
		float(report.get("output_gain", 0.0)),
		0.08,
		0.001,
		"First Try still awards this dirty one-shot"
	)
	assert_almost_eq(
		float(harness.board.active_workflow(harness.state).get("output_mult", 1.0)),
		1.08,
		0.001,
		"The new First Try gain survives Golden Path"
	)
	var ledger: Array = Array(harness.board.active_workflow(harness.state).get("gain_ledger", []))
	assert_eq(ledger.size(), 1, "Only the current evaluation's OUTPUT gain remains")
	assert_almost_eq(
		float(Dictionary(ledger[0]).get("amount", 0.0)),
		0.08,
		0.001,
		"The surviving ledger entry is the same-evaluation First Try gain"
	)


func _test_benchmark_harness_coupon_does_not_stack() -> void:
	var harness := Harness.new(38)
	harness.pipeline(["op.prompt", "op.benchmark_harness"])
	for index in range(2):
		harness.job = {
			"id": "job.coupon.%d" % index,
			"name": "Coupon Contract",
			"token_requirement": 1.0,
			"tokens_remaining": 1.0,
			"quality": 0.0,
			"quality_threshold": 40.0,
			"known_bugs": 0,
			"hidden_bugs": 0,
			"blocked_slots": 0,
			"board_rules": [],
			"tags": [],
			"bug_chance": 0.0,
			"revision_risk": 0.0,
			"deadline_prompts": 6,
			"prompts_remaining": 6,
			"workflow_id": "workflow.1",
		}
		JobSystem.normalize_job_evidence(harness.job)
		harness.state.business["active_jobs"] = [harness.job]
		harness.state.business["focused_job_id"] = str(harness.job.get("id", ""))
		harness.commit(1_000_000.0)
	assert_almost_eq(
		float(harness.state.build.get("hardware_discount", 0.0)),
		0.1,
		0.001,
		"A second clean one-shot does not stack another 10% coupon"
	)
	var hardware: UpgradeDefinition = null
	for upgrade in ContentDatabase.upgrades:
		if upgrade.category == "hardware":
			hardware = upgrade
			break
	assert_true(hardware != null, "The catalog has hardware to discount")
	if hardware != null:
		var base: float = UpgradeSystem.purchase_cost(hardware, 0)
		assert_almost_eq(
			UpgradeSystem.quoted_cost(harness.state, hardware, 0),
			base * 0.9,
			0.01,
			"The pending coupon stays a single 10% off"
		)
		UpgradeSystem.consume_hardware_discount(harness.state)
		assert_almost_eq(
			UpgradeSystem.quoted_cost(harness.state, hardware, 0),
			base,
			0.01,
			"Buying hardware still consumes the coupon"
		)
