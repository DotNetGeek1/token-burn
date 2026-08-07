extends RefCounted

## Presentation helper for round-load ("risk") feedback. Keeps the wording and
## severity colors in one place so the Jobs board and Office HUD agree.
##
## Preloaded by consumers rather than registered as a global class, so screens
## resolve it without depending on the editor's script class cache.

const OVER_CAPACITY := [
	"Ohh risky! I like it. One bug and that deadline is toast.",
	"Bold. Without a BOOST this only lands if nothing goes wrong.",
	"Over capacity! No bugs, no scope creep, no mercy. Good luck.",
	"That's more work than prompts. Living dangerously, I respect it.",
	"Cutting it fine. Any scope creep and the client gets excuses.",
]

const TIGHT := "Tight fit — this uses nearly every prompt the deadlines allow."


## Severity label for a load ratio (prompts needed / prompts the deadlines allow).
static func severity(ratio: float) -> String:
	if ratio <= 0.0:
		return "Empty"
	if ratio < 0.75:
		return "Comfortable"
	if ratio <= 1.0:
		return "Tight"
	return "Over capacity"


static func color_key(ratio: float) -> String:
	if ratio < 0.75:
		return "green"
	if ratio <= 1.0:
		return "yellow"
	return "red"


## Warning line for the given load, or "" when the round is comfortable.
## Deterministic for a given load so the text does not flicker between
## refreshes while the same contracts are on the slate.
static func warning(ratio: float, job_count: int) -> String:
	if ratio <= 0.85:
		return ""
	if ratio <= 1.0:
		return TIGHT
	var bucket: int = int(ratio * 10.0) + job_count
	return OVER_CAPACITY[bucket % OVER_CAPACITY.size()]
