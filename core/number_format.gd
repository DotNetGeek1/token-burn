class_name NumberFormat
extends RefCounted

const SUFFIXES := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc"]

## Rates at or past this switch to scientific notation (`1.00e+9`) rather than
## a suffix. A billion is where "1.5B/min" stops reading at a glance and the
## player starts wanting the exponent: a ×1.5 module moving 2.40e+9 to 3.60e+9
## is legible in a way that B/T/Qa hopping is not. Plain quantities (cash,
## contract sizes) keep the suffixes, so a $4.2B invoice still reads as money.
const SCIENTIFIC_THRESHOLD := 1e9

## The rate readouts print per minute of rig time: a prompt is the sim's tick,
## and the cabinet reads one prompt as a minute on the clock.
const RATE_UNIT := "/min"


static func format(value: float, decimals: int = 1) -> String:
	if is_nan(value) or is_inf(value):
		return "???"
	var magnitude: float = absf(value)
	if magnitude < 1000.0:
		return str(int(value)) if value == int(value) else ("%%.%df" % decimals) % value
	var tier: int = int(floor(log(magnitude) / log(1000.0)))
	if tier >= SUFFIXES.size():
		return format_scientific(value)
	var scaled: float = value / pow(1000.0, float(tier))
	return ("%%.%df%s" % [decimals, SUFFIXES[tier]]) % scaled


## Scientific notation with a two-decimal mantissa and a signed exponent:
## `1.00e+10`, `2.50e+9`, `1.00e+100`. Zero prints as `0.00e+0`.
static func format_scientific(value: float) -> String:
	if is_nan(value) or is_inf(value):
		return "???"
	if value == 0.0:
		return "0.00e+0"
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
	# two-decimal rounding would print 10.00e+99.
	if absf(mantissa) + 0.005 >= 10.0:
		mantissa /= 10.0
		exponent += 1
	return "%.2fe%+d" % [mantissa, exponent]


## Suffixes below `SCIENTIFIC_THRESHOLD`, scientific at or past it. This is the
## number the rate readouts use, so a climbing rate never hops between suffix
## families once it is big enough to need the exponent.
static func format_compact(value: float, decimals: int = 1) -> String:
	if is_nan(value) or is_inf(value):
		return "???"
	if absf(value) >= SCIENTIFIC_THRESHOLD:
		return format_scientific(value)
	return format(value, decimals)


static func format_tokens(value: float) -> String:
	return "%s tokens" % format(value)


## Tokens the rig pushes per minute of rig time. The sim ticks in prompts and
## the cabinet reads a prompt as a minute; the figure is `compute.token_rate`
## (or that rate through the pipeline's multipliers), and past a billion it
## goes to scientific notation so a doubling stays readable.
static func format_token_rate(value: float) -> String:
	return "%s%s" % [format_compact(value), RATE_UNIT]


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
