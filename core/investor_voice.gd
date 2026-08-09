class_name InvestorVoice
extends RefCounted

## The Angel Investor's script.
##
## He is the only person in the game the player ever hears from: he sets the
## terms at the start of a run, weighs in on every round, decides when the
## Ascension Contract is on the table, and either invests again or walks away at
## the end. Everything he says lives in `content/narrative/investor.json` so his
## voice can be rewritten without touching the UI that delivers it.
##
## A "call" is one dict: a subject line and the paragraphs he says, in order. A
## trigger can have several variants keyed by situation ("strong", "rent_missed",
## a location id, ...) and each variant can hold several calls so he does not
## repeat himself word for word every round.

const SCRIPT_PATH := "res://content/narrative/investor.json"

static var _data: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(SCRIPT_PATH):
		push_warning("InvestorVoice: missing %s" % SCRIPT_PATH)
		return
	var file := FileAccess.open(SCRIPT_PATH, FileAccess.READ)
	if file == null:
		push_warning("InvestorVoice: could not open %s" % SCRIPT_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_data = parsed if parsed is Dictionary else {}


## Reloads the script from disk. Only the content tests need this.
static func reload() -> void:
	_loaded = false
	_data = {}
	_ensure_loaded()


static func persona() -> Dictionary:
	_ensure_loaded()
	var entry: Variant = _data.get("investor")
	return Dictionary(entry) if entry is Dictionary else {}


static func investor_name() -> String:
	return str(persona().get("name", "The Angel Investor"))


## One thing for him to say. `variant` picks the situation; anything unknown
## falls back to "default", and a trigger with nothing behind it returns empty
## so callers can stay quiet rather than show a blank phone.
##
## `seed` chooses between the variants he has for the same situation, and is
## normally something stable about the moment (the round number, the reward) so
## reopening a call does not reword it.
static func call_for(trigger: String, variant: String = "default", seed: int = 0) -> Dictionary:
	_ensure_loaded()
	var calls: Variant = _data.get("calls")
	if not calls is Dictionary:
		return {}
	var group: Variant = Dictionary(calls).get(trigger)
	if not group is Dictionary:
		return {}
	var options: Variant = Dictionary(group).get(variant)
	if not options is Array or Array(options).is_empty():
		options = Dictionary(group).get("default")
	if not options is Array or Array(options).is_empty():
		return {}
	var pool: Array = Array(options)
	var chosen: Variant = pool[absi(seed) % pool.size()]
	if not chosen is Dictionary:
		return {}
	var call: Dictionary = Dictionary(chosen)
	return {
		"subject": str(call.get("subject", "")),
		"lines": Array(call.get("lines", [])),
	}


## Whether he has something to say for exactly this variant. Unlike `call_for`
## this does not fall back to "default", so a caller can pick between variants
## rather than always being told yes.
static func has_call(trigger: String, variant: String = "default") -> bool:
	_ensure_loaded()
	var calls: Variant = _data.get("calls")
	if not calls is Dictionary:
		return false
	var group: Variant = Dictionary(calls).get(trigger)
	if not group is Dictionary:
		return false
	var options: Variant = Dictionary(group).get(variant)
	return options is Array and not Array(options).is_empty()


## His pitch on a free offer. Rotated by index so a table of three reads as one
## man making three different noises rather than the same line three times.
static func offer_patter(index: int) -> String:
	_ensure_loaded()
	var calls: Variant = _data.get("calls")
	if not calls is Dictionary:
		return ""
	var pool: Variant = Dictionary(calls).get("offer_patter")
	if not pool is Array or Array(pool).is_empty():
		return ""
	var lines: Array = Array(pool)
	return str(lines[absi(index) % lines.size()])


## Which mood the round earned. One rule, used by both the debrief panel and the
## phone call, so the quote under the numbers and the call that follows it never
## disagree about how the round went.
##
## The worst thing that happened wins: a round that delivered beautifully and
## then missed the rent is a round about the rent.
static func debrief_variant(summary: Dictionary, statement: Dictionary = {}) -> String:
	if not statement.is_empty() and not bool(statement.get("paid_in_full", true)):
		return "rent_missed"
	if bool(summary.get("near_fire", false)):
		return "near_fire"
	# Behind on the contract with the year running down outranks a tidy round:
	# delivering well and still not finishing is the failure he cares about.
	if bool(summary.get("behind_on_contract", false)):
		return "behind"
	var completed: int = int(summary.get("completed", 0))
	if completed <= 0:
		return "failed"
	var quality: float = float(summary.get("avg_quality", 0.0))
	var bar: float = maxf(1.0, float(summary.get("avg_quality_threshold", 1.0)))
	if not bool(summary.get("success", false)) or quality < bar:
		return "poor"
	if quality >= bar * 1.2:
		return "strong"
	return "good"


## The verdict he prints under a round's numbers: the first line of the call he
## would make about it, so the debrief and the phone are the same man.
static func debrief_quip(summary: Dictionary, statement: Dictionary = {}) -> String:
	var variant: String = debrief_variant(summary, statement)
	var seed: int = int(summary.get("round", 0)) + int(summary.get("completed", 0))
	var call: Dictionary = call_for("round_debrief", variant, seed)
	var lines: Array = Array(call.get("lines", []))
	return str(lines[0]) if not lines.is_empty() else ""
