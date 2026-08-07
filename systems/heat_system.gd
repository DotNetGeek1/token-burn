class_name HeatSystem
extends RefCounted


func process_prompt(run_state: RunState, subscriptions: Array, effect_resolver: EffectResolver, rng: DeterministicRng) -> Array[String]:
	var messages: Array[String] = []
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	var gain_factor: float = float(heat_cfg.get("gain_per_power", 0.025))
	var cooling_factor: float = float(heat_cfg.get("cooling_factor", 0.35))
	var throttle_ratio: float = float(heat_cfg.get("throttle_ratio", 0.8))
	var throttle_mult: float = float(heat_cfg.get("throttle_multiplier", 0.75))

	var heat_gain: float = float(run_state.compute.get("power_draw", 0.0)) * gain_factor
	var cooling: float = float(run_state.compute.get("cooling", 0.0))
	run_state.compute["heat"] = clampf(float(run_state.compute.get("heat", 0.0)) + heat_gain - cooling * cooling_factor, 0.0, 200.0)
	var heat_ratio: float = float(run_state.compute["heat"]) / maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))
	if heat_ratio >= throttle_ratio:
		run_state.add_rate_modifier(throttle_mult, 1, "heat_throttle")
		messages.append("Heat throttling engaged at %d%%." % int(heat_ratio * 100.0))
		EventBus.emit_event("heat.threshold_crossed", {"level": heat_ratio})
		effect_resolver.begin_action("heat.threshold_crossed")
		var mod_ctx := ModifierContext.new("heat.threshold_crossed", run_state)
		mod_ctx.rng = rng.derive("heat.threshold_crossed")
		mod_ctx.set_value("compute.heat", run_state.compute["heat"])
		effect_resolver.dispatch("heat.threshold_crossed", mod_ctx, subscriptions)
	# Re-evaluated every prompt rather than latched, so a rig that cools back
	# down is out of danger instead of staying one spike away from a fire.
	run_state.flags["fire_risk"] = heat_ratio >= 1.0
	if heat_ratio >= 1.0:
		messages.append("Hardware is dangerously hot!")
	return messages


## Downtime between rounds lets the hardware cool off, so one bad round is
## recoverable instead of a one-way trip to a fire.
func shed_between_rounds(run_state: RunState) -> void:
	var heat_cfg: Dictionary = ContentDatabase.balance.get("economy", {}).get("heat", {})
	var retained: float = clampf(float(heat_cfg.get("round_end_retained", 0.5)), 0.0, 1.0)
	run_state.compute["heat"] = maxf(0.0, float(run_state.compute.get("heat", 0.0)) * retained)
	var capacity: float = maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))
	if float(run_state.compute["heat"]) < capacity:
		run_state.flags["fire_risk"] = false
