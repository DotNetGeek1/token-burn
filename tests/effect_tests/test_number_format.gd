extends TestCase


func run() -> void:
	assert_eq(NumberFormat.format(1500.0), "1.5K", "Formats thousands")
	assert_eq(
		NumberFormat.format_token_rate(1_000_000.0), "1.0M/prompt",
		"Token rate is per prompt, the unit the sim actually runs on — there is no clock behind it"
	)
	assert_true(NumberFormat.comparison(2_000_000.0, [
		{"threshold": 1000000.0, "template": "Equivalent to {value} novels"},
	]) != "", "Comparison renders template")
	assert_true(
		NumberFormat.comparison(2_000_000.0, [
			{"threshold": 1000000.0, "template": "Equivalent to {value} novels"},
		]).contains("novels"),
		"Comparison includes template text"
	)
	assert_eq(NumberFormat.comparison(500.0, [
		{"threshold": 1000000.0, "template": "Equivalent to {value} novels"},
	]), "", "Comparison hidden below threshold")
	_assert_absurd(1e18, "1.0Qi")
	_assert_absurd(1e21, "1.0Sx")
	_assert_absurd(1e30, "1.00e30")
	_assert_absurd(1e100, "1.00e100")
	_test_run_score_stays_float_past_int64()


func _assert_absurd(value: float, expected: String) -> void:
	assert_false(is_nan(value), "The fixture itself is a real number")
	assert_false(is_inf(value), "The fixture itself is finite")
	var rendered: String = NumberFormat.format(value)
	assert_true(rendered != "???", "Absurd values still format")
	assert_eq(rendered, expected, "Suffixes hold through Oc, then scientific notation")


func _test_run_score_stays_float_past_int64() -> void:
	var state := RunState.new()
	state.statistics["lifetime_tokens"] = 4e17
	state.statistics["lifetime_overkill"] = 1e20
	state.statistics["depth_score"] = 4e17 * 1024.0
	state.statistics["peak_overkill"] = 1e20
	state.depth["score_mult"] = 1025.0
	var score: Dictionary = RunScore.compute(state, ContentDatabase)
	var depth_score: float = float(score.get("depth_score", NAN))
	var overkill_score: float = float(score.get("overkill_score", NAN))
	assert_false(is_nan(depth_score), "Depth score stays a number")
	assert_false(is_inf(depth_score), "Depth score stays finite")
	assert_false(is_nan(overkill_score), "Overkill score stays a number")
	assert_false(is_inf(overkill_score), "Overkill score stays finite")
	assert_almost_eq(depth_score, 4e17 * 1024.0, 1e12, "Accrued depth score is kept as a float")
	assert_almost_eq(overkill_score, 1e22, 1e6, "Overkill score is not floored into int64")
	assert_true(
		NumberFormat.format(depth_score) != "???",
		"The debrief can print a score past octillion"
	)
	var overkill_row := ""
	for row in RunScore.rows(score):
		if str(row.get("label", "")) == "Peak overkill":
			overkill_row = str(row.get("value", ""))
	assert_eq(
		overkill_row, "%s%%" % NumberFormat.format(1e22),
		"Peak overkill is not truncated through int()"
	)
