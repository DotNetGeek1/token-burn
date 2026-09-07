extends PlaytestCase

## "I find it hard to know when the quality requirement has been achieved."
##
## The bench used to print the bar on the card (`Q6.0`) and the verdict only in
## the brief, as "6.4 / 10 · bar 6.0", which leaves the player doing the
## comparison. Now the RUN tab carries a QUALITY VS BAR figure and the card a
## verdict line, and both say it outright: amber "x / y · BELOW BAR" while the
## work is under the bar, phosphor "✓ QUALITY MET · x / y" once it is over.
## This persona pushes a contract's quality either side of its bar and reads
## both surfaces.


func play(harness: UiHarness) -> void:
	_readout_rules()
	await harness.boot(31)
	var job_id: String = await accept_first_job(harness)
	assert_true(job_id != "", "A contract is on the slate")
	if job_id == "":
		return
	var shell: Node = harness.current_scene()
	if shell == null:
		return
	if Simulation.can_start_work():
		Simulation.start_work()
	shell.switch_tab("run")
	await harness.settle()
	var run_tab: TabRun = _find_first(shell, func(node: Node) -> bool: return node is TabRun) as TabRun
	assert_true(run_tab != null, "The RUN tab is on the glass")
	if run_tab == null:
		return
	var job: Dictionary = _live_job(job_id)
	assert_false(job.is_empty(), "The accepted contract is in the run state")
	if job.is_empty():
		return
	var focused: Dictionary = Simulation.focused_job()
	if str(focused.get("id", "")) != job_id:
		Simulation.focus_job(job_id)
	# A bar to be judged against, whatever the seed handed out.
	if float(job.get("quality_threshold", 0.0)) <= 0.0:
		job["quality_threshold"] = 60.0
	var threshold: float = float(job["quality_threshold"])
	var readout: Label = run_tab.stat_label("quality")
	var card: ContractCard = run_tab.card()
	assert_true(readout != null and card != null, "The RUN tab has a quality figure and a card")
	if readout == null or card == null:
		return

	# Under the bar: the figure names the bar and says the work is below it.
	job["quality"] = threshold * 0.5
	job["known_bugs"] = 0
	shell.call("refresh_all")
	await harness.settle()
	var unmet: Dictionary = CabinetStyle.quality_readout(job)
	assert_eq(readout.text, str(unmet["text"]), "The RUN tab prints the unmet verdict")
	assert_true(readout.text.ends_with(CabinetStyle.QUALITY_BELOW), "…which says BELOW BAR (got '%s')" % readout.text)
	assert_true(
		readout.text.begins_with(JobPresentation.quality_mark(threshold * 0.5)),
		"…and leads with the work's own mark (got '%s')" % readout.text
	)
	assert_true(
		readout.text.contains(JobPresentation.quality_mark(threshold)),
		"…against the client's bar (got '%s')" % readout.text
	)
	assert_eq(readout.get_theme_color("font_color"), CabinetStyle.AMBER, "The unmet verdict is in the warning colour")
	assert_false(card.quality_met_shown(), "The card does not claim the bar is met")

	# Over the bar: the figure flips to the success colour and says so.
	job["quality"] = threshold + 15.0
	shell.call("refresh_all")
	await harness.settle()
	var met: Dictionary = CabinetStyle.quality_readout(job)
	assert_eq(readout.text, str(met["text"]), "The RUN tab prints the met verdict")
	assert_true(readout.text.contains(CabinetStyle.QUALITY_MET), "…which says QUALITY MET (got '%s')" % readout.text)
	assert_true(readout.text.begins_with(CabinetStyle.check_glyph()), "…with a check mark up front (got '%s')" % readout.text)
	assert_eq(readout.get_theme_color("font_color"), CabinetStyle.PHOSPHOR, "The met verdict is in the success colour")
	assert_true(card.quality_met_shown(), "The card shows the bar as met too")
	harness.driver.audit_screen("run-quality-met", "desk")

	# Exactly on the bar counts as met; a known bug shipped with it does not.
	job["quality"] = threshold
	shell.call("refresh_all")
	await harness.settle()
	assert_true(readout.text.contains(CabinetStyle.QUALITY_MET), "Quality exactly on the bar is met")
	job["known_bugs"] = 1
	shell.call("refresh_all")
	await harness.settle()
	assert_true(
		readout.text.ends_with(CabinetStyle.QUALITY_BELOW),
		"A known bug drags delivered quality under the bar, and the figure says so (got '%s')" % readout.text
	)
	job["known_bugs"] = 0


## The verdict helper on its own, without a run behind it.
func _readout_rules() -> void:
	var unmarked: Dictionary = CabinetStyle.quality_readout({"quality": 42.0, "quality_threshold": 0.0})
	assert_false(bool(unmarked["marked"]), "No bar: the contract is unmarked")
	assert_eq(str(unmarked["text"]), "2.8 / 10", "No bar: the mark alone, out of ten")
	var below: Dictionary = CabinetStyle.quality_readout({"quality": 45.0, "quality_threshold": 60.0})
	assert_false(bool(below["met"]), "45 against 60 is not met")
	assert_eq(str(below["text"]), "3.0 / 4.0 · %s" % CabinetStyle.QUALITY_BELOW, "Unmet: work / bar · BELOW BAR")
	assert_eq(below["color"], CabinetStyle.AMBER, "Unmet is amber")
	var over: Dictionary = CabinetStyle.quality_readout({"quality": 75.0, "quality_threshold": 60.0})
	assert_true(bool(over["met"]), "75 against 60 is met")
	assert_eq(
		str(over["text"]), "%s %s · 5.0 / 4.0" % [CabinetStyle.check_glyph(), CabinetStyle.QUALITY_MET],
		"Met: check, QUALITY MET, work / bar"
	)
	assert_eq(over["color"], CabinetStyle.PHOSPHOR, "Met is phosphor")
	assert_true(str(over["short"]).begins_with(CabinetStyle.check_glyph()), "The card's short form leads with the check")
	var bugged: Dictionary = CabinetStyle.quality_readout({"quality": 60.0, "quality_threshold": 60.0, "known_bugs": 1})
	assert_false(bool(bugged["met"]), "A known bug costs three points, so 60 with one bug misses a bar of 60")


func _live_job(job_id: String) -> Dictionary:
	var business: Dictionary = Simulation.run_state.business
	for key in ["active_jobs", "job_queue"]:
		for job in Array(business.get(key, [])):
			if job is Dictionary and str(job.get("id", "")) == job_id:
				return job
	return {}


func _find_first(node: Node, predicate: Callable) -> Node:
	if node == null:
		return null
	if bool(predicate.call(node)):
		return node
	for child in node.get_children():
		var found: Node = _find_first(child, predicate)
		if found != null:
			return found
	return null
