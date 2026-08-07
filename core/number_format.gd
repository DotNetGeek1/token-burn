class_name NumberFormat
extends RefCounted

const SUFFIXES := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc"]


static func format(value: float, decimals: int = 1) -> String:
	if is_nan(value) or is_inf(value):
		return "???"
	if absf(value) < 1000.0:
		return str(int(value)) if value == int(value) else ("%%.%df" % decimals) % value
	var tier: int = int(floor(log(absf(value)) / log(1000.0)))
	tier = clampi(tier, 0, SUFFIXES.size() - 1)
	var scaled: float = value / pow(1000.0, tier)
	return ("%%.%df%s" % [decimals, SUFFIXES[tier]]) % scaled


static func format_tokens(value: float) -> String:
	return "%s tokens" % format(value)


static func format_token_rate(value: float) -> String:
	return "%s/s" % format(value)


static func format_cash(value: float) -> String:
	return "$%s" % format(value)


static func format_percent(value: float, decimals: int = 0) -> String:
	return ("%%.%df%%" % decimals) % (value * 100.0)


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
