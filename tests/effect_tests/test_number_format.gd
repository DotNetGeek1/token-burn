extends TestCase


func run() -> void:
	assert_eq(NumberFormat.format(1500.0), "1.5K", "Formats thousands")
	assert_eq(
		NumberFormat.format_token_rate(1_000_000.0), "1.0M/min",
		"Token rate reads per minute of rig time, with suffixes below a billion"
	)
	_test_scientific_notation()
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
	_assert_absurd(1e30, "1.00e+30")
	_assert_absurd(1e100, "1.00e+100")
	_test_run_score_stays_float_past_int64()


## The notation rule: rates at or past 1e9 print as `m.mme+NN`; plain
## quantities keep their suffixes until the suffix table runs out.
func _test_scientific_notation() -> void:
	assert_eq(NumberFormat.format_scientific(1e10), "1.00e+10", "Two-decimal mantissa, signed exponent")
	assert_eq(NumberFormat.format_scientific(2.5e9), "2.50e+9", "Exponent is not zero-padded")
	assert_eq(NumberFormat.format_scientific(123456.0), "1.23e+5", "Mantissa rounds to two decimals")
	assert_eq(NumberFormat.format_scientific(-4.2e12), "-4.20e+12", "Sign stays on the mantissa")
	assert_eq(NumberFormat.format_scientific(0.001), "1.00e-3", "Small values get a negative exponent")
	assert_eq(NumberFormat.format_scientific(0.0), "0.00e+0", "Zero has a home")
	assert_eq(NumberFormat.format_scientific(9.999e9), "1.00e+10", "A 9.999 mantissa rolls over rather than printing 10.00")
	assert_eq(NumberFormat.format_scientific(NAN), "???", "NaN is still ???")

	assert_eq(NumberFormat.format_compact(999_999_999.0), "1000.0M", "Just under the threshold keeps the suffix")
	assert_eq(NumberFormat.format_compact(1e9), "1.00e+9", "The threshold itself switches to scientific")
	assert_eq(NumberFormat.format_compact(1500.0), "1.5K", "Small compact values are the plain format")

	assert_eq(NumberFormat.format_token_rate(1e10), "1.00e+10/min", "Rates go scientific at a billion")
	assert_eq(NumberFormat.format_token_rate(3.6e9), "3.60e+9/min", "A ×1.5 module on 2.40e+9 reads as 3.60e+9")
	assert_eq(NumberFormat.format_token_rate(0.0), "0/min", "An idle rig reads zero per minute")
	assert_true(NumberFormat.format_token_rate(1.0).ends_with(NumberFormat.RATE_UNIT), "Every rate carries the unit")
	assert_eq(NumberFormat.format(1e9), "1.0B", "Plain quantities keep suffixes past a billion")
	assert_eq(NumberFormat.format_cash(1e12), "$1.0T", "Cash keeps suffixes past a billion")


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
