class_name NumberFormat
extends RefCounted

const SUFFIXES := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc"]


static func format(value: float, decimals: int = 1) -> String:
	if is_nan(value) or is_inf(value):
		return "???"
	var magnitude: float = absf(value)
	if magnitude < 1000.0:
		return str(int(value)) if value == int(value) else ("%%.%df" % decimals) % value
	var tier: int = int(floor(log(magnitude) / log(1000.0)))
	if tier >= SUFFIXES.size():
		return _scientific(value)
	var scaled: float = value / pow(1000.0, float(tier))
	return ("%%.%df%s" % [decimals, SUFFIXES[tier]]) % scaled


static func _scientific(value: float) -> String:
	var magnitude: float = absf(value)
	var exponent: int = int(floor(log(magnitude) / log(10.0) + 1e-12))
	var mantissa: float = value / pow(10.0, float(exponent))
	while absf(mantissa) >= 10.0:
		mantissa /= 10.0
		exponent += 1
	while absf(mantissa) < 1.0 and mantissa != 0.0:
		mantissa *= 10.0
		exponent -= 1
	# 1e100 is not an exact float; the mantissa can sit at 9.999… and then
	# two-decimal rounding would print 10.00e99.
	if absf(mantissa) + 0.005 >= 10.0:
		mantissa /= 10.0
		exponent += 1
	return "%.2fe%d" % [mantissa, exponent]


static func format_tokens(value: float) -> String:
	return "%s tokens" % format(value)


## Tokens burned by one batch — a prompt, not a second. There is no clock
## behind it: throughput is measured in prompts because that is the unit the
## deadline, the deck and the RNG all use.
static func format_token_rate(value: float) -> String:
	return "%s/prompt" % format(value)


static func format_cash(value: float) -> String:
	return "$%s" % format(value)


static func format_percent(value: float, decimals: int = 0) -> String:
	return "%s%%" % format(value * 100.0, decimals)


static func comparison(value: float, comparisons: Array) -> String:
	if comparisons.is_empty():
		return ""
	var best: Dictionary = comparisons[0]
	var best_ratio: float = 0.0
	for entry in comparisons:
		if not entry is Dictionary:
			continue
		var threshold: float = float(entry.get("threshold", 0.0))
		if threshold <= 0.0:
			continue
		var ratio: float = value / threshold
		if ratio >= 1.0 and ratio > best_ratio:
			best = entry
			best_ratio = ratio
	if best_ratio <= 0.0:
		return ""
	var amount: float = value / float(best.get("threshold", 1.0))
	var template: String = str(best.get("template", "{value} units"))
	return template.replace("{value}", format(amount, 1))
