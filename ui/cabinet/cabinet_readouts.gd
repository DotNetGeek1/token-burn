class_name CabinetReadouts
extends RefCounted

## What the instruments say when nothing is burning. The drum shows the next
## batch's projected multipliers, the heat bar the current and projected heat,
## the feed its idle line, the status panel the ledger and the workflows, and
## the CRT's tab strip the round and phase. The deck (button, switches, lever,
## lamps) is the cabinet's own; what the machine wants pressed next is what the
## commit button says, so there is no separate NEXT ACTION well any more.
##
## During a burn the `BurnDirector` drives the same instruments beat by beat,
## so the cabinet does not ask for these readings until it hands them back.

var _drum: MultiplierDrum = null
var _heat: HeatMeter = null
var _feed: BurnFeed = null
var _status: SystemStatus = null
var _screen: CabinetScreen = null


func _init(drum: MultiplierDrum, heat: HeatMeter, feed: BurnFeed, status: SystemStatus, screen: CabinetScreen) -> void:
	_drum = drum
	_heat = heat
	_feed = feed
	_status = status
	_screen = screen


## The idle readings: drum, heat, round line on the glass, and the feed.
func refresh_idle() -> void:
	var preview: Dictionary = Simulation.preview_next_burn()
	var boosted: bool = Simulation.boost_engaged() or Simulation.queued_boost
	var workflow: Dictionary = Simulation.active_workflow()
	if preview.get("ok", false):
		_drum.set_projection(
			float(preview.get("output_mult", 1.0)),
			float(preview.get("quality_mult", 1.0)),
			float(preview.get("thermal_mult", 1.0)),
			boosted
		)
	else:
		_drum.set_projection(
			float(workflow.get("output_mult", 1.0)),
			float(workflow.get("quality_mult", 1.0)),
			float(workflow.get("thermal_mult", 1.0)),
			boosted
		)
	var capacity: float = maxf(1.0, float(Simulation.run_state.compute.get("heat_capacity", 100.0)))
	var ratio: float = float(Simulation.run_state.compute.get("heat", 0.0)) / capacity
	var throttle: float = float(HeatSystem.heat_config().get("throttle_ratio", 0.8))
	var state: String = HeatSystem.heat_state(ratio, HeatSystem.work_tier(Simulation.run_state))
	var projected: float = float(preview.get("heat_ratio_after", -1.0)) if preview.get("ok", false) else -1.0
	_heat.set_heat(ratio, throttle, HeatSystem.heat_state_label(state), projected)
	var round_number: int = int(Simulation.run_state.calendar.get("round", 1))
	if not Simulation.is_work_running():
		_feed.set_live(false, "no run active" if Simulation.phase != Simulation.Phase.IN_ROUND else "between prompts")
	else:
		_feed.set_live(false, "prompt %d · ready" % (Simulation.prompts_used_this_round() + 1))
	# The round and phase live in the CRT's tab strip now that the painted
	# header strip is gone.
	_screen.set_hint("ROUND %d · %s" % [round_number, phase_word()])


## The narrow panel on the right: the ledger and the workflows' earned
## multipliers, which is what "system status" means on this machine.
func refresh_status() -> void:
	var state := Simulation.run_state
	var round_number: int = int(state.calendar.get("round", 1))
	var deadline: int = round_number + Simulation.rounds_remaining() - 1
	var cash: float = float(state.economy.get("cash", 0.0))
	var entries: Array = [
		{"key": "CREDITS", "value": NumberFormat.format_cash(cash), "color": CabinetStyle.RED if cash < 0.0 else CabinetStyle.PHOSPHOR},
		{"key": "REP", "value": str(int(state.business.get("reputation", 0.0)))},
		{"key": "ROUND", "value": "%d/%d" % [round_number, deadline], "color": CabinetStyle.RED if Simulation.rounds_remaining() <= 2 else CabinetStyle.PHOSPHOR},
		# "/prompt" is too long for the narrow glass; the key says what the rate is per.
		{"key": "TOK/PROMPT", "value": NumberFormat.format_token_rate(float(state.compute.get("token_rate", 0.0))).replace("/prompt", "")},
	]
	var costs: Dictionary = Simulation.cost_forecast()
	entries.append({"key": "BILLS", "value": NumberFormat.format_cash(float(costs.get("fixed_due", 0.0))), "color": CabinetStyle.AMBER if float(costs.get("fixed_due", 0.0)) > cash else CabinetStyle.PHOSPHOR_DIM})
	# The cabinet's generation, derived from the five system tiers. Ambient:
	# a name on the ledger, never a number anything else reads.
	var generation: Dictionary = Simulation.cabinet_generation()
	entries.append({"key": "CABINET", "value": "GEN %d" % (int(generation.get("index", 0)) + 1), "color": CabinetStyle.AMBER_DIM})
	entries.append({"key": "WORKFLOWS"})
	var active: int = Simulation.active_workflow_index()
	var index: int = 0
	for raw in Simulation.workflows():
		var workflow: Dictionary = raw
		entries.append({
			"key": "%d %s" % [index + 1, str(workflow.get("name", "")).left(6).to_upper()],
			"value": "×%.2f" % float(workflow.get("output_mult", 1.0)),
			"color": CabinetStyle.AMBER if index == active else CabinetStyle.PHOSPHOR,
		})
		index += 1
	_status.set_entries(entries)


func phase_word() -> String:
	match Simulation.phase:
		Simulation.Phase.ROUND_PREP:
			return "PREP"
		Simulation.Phase.IN_ROUND:
			return "IN ROUND"
		Simulation.Phase.ROUND_END:
			return "ROUND END"
		Simulation.Phase.ANGEL_ROUND:
			return "ANGELS"
		Simulation.Phase.RUN_END:
			return "RUN OVER"
	return "IDLE"

