extends TestCase


func run() -> void:
	assert_eq(NumberFormat.format(1500.0), "1.5K", "Formats thousands")
	assert_eq(NumberFormat.format_token_rate(1_000_000.0), "1.0M/s", "Token rate uses single suffix")
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
