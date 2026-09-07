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

## How long the TOKENS figure takes to climb to a higher reading.
const RATE_CLIMB_SECONDS := 0.6

var _drum: MultiplierDrum = null
var _heat: HeatMeter = null
var _feed: BurnFeed = null
var _status: SystemStatus = null
var _screen: CabinetScreen = null

## The tokens-per-minute figure as the panel currently prints it, and where it
## is heading. They differ only while a climb is running.
var _rate_shown: float = 0.0
var _rate_target: float = 0.0
var _rate_tween: Tween = null
## The ledger below the rate rows, kept so a climb re-prints only the figure.
var _ledger_tail: Array = []
var _rig_rate: float = 0.0
## `[Signal, Callable]` pairs hooked up in `_init`, undone when the panel leaves
## the tree so a rebuilt cabinet does not leave a stale readout listening.
var _hooks: Array = []


func _init(drum: MultiplierDrum, heat: HeatMeter, feed: BurnFeed, status: SystemStatus, screen: CabinetScreen) -> void:
	_drum = drum
	_heat = heat
	_feed = feed
	_status = status
	_screen = screen
	_hook_rate_events()


## Everything that can move the tokens-per-minute figure: a burn (mastery may
## have trained the workflow), a perk, a module seated or bought, a cabinet
## system tier, a hardware purchase, a cascade. Each one re-reads the rate and
## the figure climbs to it. `burn_cabinet` refreshes the whole panel on most of
## these too; the deferred call folds the two into one rebuild a frame later.
func _hook_rate_events() -> void:
	var listeners: Array = [
		[EventBus.tokens_generated, func(_amount: float) -> void: _on_rate_event()],
		[EventBus.perk_acquired, func(_perk_id: String) -> void: _on_rate_event()],
		[EventBus.module_acquired, func(_module_id: String) -> void: _on_rate_event()],
		[EventBus.cabinet_system_upgraded, func(_system_id: String, _tier: int) -> void: _on_rate_event()],
		[EventBus.upgrade_purchased, func(_upgrade_id: String) -> void: _on_rate_event()],
		[EventBus.cascade_triggered, func(_module_id: String) -> void: _on_rate_event()],
		[Simulation.burn_resolved, func(_burn: Dictionary) -> void: _on_rate_event()],
	]
	for pair in listeners:
		var sig: Signal = pair[0]
		var callable: Callable = pair[1]
		sig.connect(callable)
		_hooks.append([sig, callable])
	if _status != null:
		_status.tree_exiting.connect(_unhook_rate_events)


func _unhook_rate_events() -> void:
	for pair in _hooks:
		var sig: Signal = pair[0]
		var callable: Callable = pair[1]
		if sig.is_connected(callable):
			sig.disconnect(callable)
	_hooks.clear()


func _on_rate_event() -> void:
	if _status == null or not is_instance_valid(_status) or not _status.is_inside_tree():
		return
	refresh_status.call_deferred()


## Tokens per minute as the player experiences them: the rig's rate through
## the active workflow's projected multiplier, so a ×1.5 module or a trained
## workflow shows up on the figure and not only on the drum. Falls back to the
## workflow's own earned multiplier when there is no contract to preview.
func effective_token_rate() -> float:
	var rig: float = rig_token_rate()
	var multiplier: float = float(Simulation.active_workflow().get("output_mult", 1.0))
	var preview: Dictionary = Simulation.preview_next_burn()
	if preview.get("ok", false):
		multiplier = float(preview.get("output_mult", multiplier))
	return rig * maxf(0.0, multiplier)


## What the hardware alone pushes, before the pipeline has its say.
func rig_token_rate() -> float:
	return maxf(0.0, float(Simulation.run_state.compute.get("token_rate", 0.0)))


## The figure the panel is printing right now (mid-climb, this trails the target).
func shown_token_rate() -> float:
	return _rate_shown


func is_rate_climbing() -> bool:
	return _rate_tween != null and _rate_tween.is_valid() and _rate_tween.is_running()


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
	_ledger_tail = entries
	_rig_rate = rig_token_rate()
	_retarget_rate(effective_token_rate())


## The rate rows sit at the top of the ledger: TOKENS is the effective
## tokens-per-minute figure in amber (white while it is climbing), RIG the raw
## hardware rate under it in dim phosphor so the gap between them is the
## pipeline's doing.
func _rate_rows() -> Array:
	var climbing: bool = is_rate_climbing()
	return [
		{
			"key": "TOKENS",
			"value": NumberFormat.format_token_rate(_rate_shown),
			"color": CabinetStyle.WHITE if climbing else CabinetStyle.AMBER,
		},
		{
			"key": "RIG",
			"value": NumberFormat.format_token_rate(_rig_rate),
			"color": CabinetStyle.PHOSPHOR_DIM,
		},
	]


func _print_ledger() -> void:
	if _status == null or not is_instance_valid(_status):
		return
	var entries: Array = _rate_rows()
	entries.append_array(_ledger_tail)
	_status.set_entries(entries)


## Moves the TOKENS figure to `target`. A rise climbs over RATE_CLIMB_SECONDS,
## easing out so the leading digits jump and the trailing ones settle; a fall
## snaps, because a drop is not something to savour.
func _retarget_rate(target: float) -> void:
	target = maxf(0.0, target)
	# A refresh that lands on the same figure mid-climb re-prints the ledger
	# around the climb rather than restarting it, or a run of refreshes would
	# keep the last digits counting forever.
	if is_rate_climbing() and is_equal_approx(target, _rate_target):
		_print_ledger()
		return
	_rate_target = target
	if _rate_tween != null and _rate_tween.is_valid():
		_rate_tween.kill()
	_rate_tween = null
	var can_animate: bool = (
		_status != null and is_instance_valid(_status) and _status.is_inside_tree()
		and _rate_target > _rate_shown and not is_equal_approx(_rate_target, _rate_shown)
	)
	if not can_animate:
		_rate_shown = _rate_target
		_print_ledger()
		return
	_rate_tween = _status.create_tween()
	_rate_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_rate_tween.tween_method(_show_rate, _rate_shown, _rate_target, RATE_CLIMB_SECONDS)
	_rate_tween.finished.connect(_on_rate_settled)
	_print_ledger()


func _show_rate(value: float) -> void:
	_rate_shown = value
	_print_ledger()


func _on_rate_settled() -> void:
	_rate_shown = _rate_target
	_rate_tween = null
	_print_ledger()


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

