class_name HeatSystem
extends RefCounted


## The one place heat is written. Every gain and every loss — pipeline burn
## heat, cooling vents, BOOST, ambient gain — comes through here, clamped once
## against the room's own capacity rather than each caller inventing its own
## ceiling. Returns the heat value after the clamp.
##
## Authored bedroom-point amounts (pipeline cards, BOOST, event spikes) must be
## scaled with `scale_authored_heat` *before* they arrive here. Ambient ticks
## are already in bar units. Do not scale inside this method, or ambient would
## be counted twice.
func add_heat(run_state: RunState, amount: float) -> float:
	return set_heat(run_state, float(run_state.compute.get("heat", 0.0)) + amount)


## Writes an absolute heat value through the same clamp, for the few callers
## that replace the reading rather than move it. Keeps `add_heat`'s promise of
## being the only place the ceiling is decided literally true.
func set_heat(run_state: RunState, value: float) -> float:
	var capacity: float = maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))
	# Capped at twice the room's tolerance rather than a fixed number, so a
	# location with more headroom does not silently lose it to the clamp.
	run_state.compute["heat"] = clampf(value, 0.0, capacity * 2.0)
	return float(run_state.compute["heat"])


func process_prompt(
	run_state: RunState,
	subscriptions: Array,
	effect_resolver: EffectResolver,
	rng: DeterministicRng,
	mode: int = ResolveMode.COMMIT
) -> Array[String]:
	var messages: Array[String] = []
	var heat_cfg: Dictionary = config()
	var throttle_ratio: float = float(heat_cfg.get("throttle_ratio", 0.8))
	var throttle_mult: float = float(heat_cfg.get("throttle_multiplier", 0.75))

	var capacity: float = maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))
	var tick: Dictionary = outlook(
		float(run_state.compute.get("power_draw", 0.0)),
		float(run_state.compute.get("cooling", 0.0)),
		capacity
	)
	add_heat(run_state, float(tick.get("heat_per_prompt", 0.0)))
	var heat_ratio: float = float(run_state.compute["heat"]) / capacity
	if heat_ratio >= throttle_ratio:
		# The throttle is added to the modifier list here, but `end_prompt`
		# only recalculates the sustained rate afterwards — this prompt's
		# batch was already resolved before heat was processed, so the
		# slowdown is what the *next* prompt will run at, not this one.
		run_state.add_rate_modifier(throttle_mult, 1, "heat_throttle")
		messages.append("Heat throttling engaged at %d%%." % int(heat_ratio * 100.0))
		if mode == ResolveMode.COMMIT:
			EventBus.emit_event(EventBus.EVENT_HEAT_THRESHOLD_CROSSED, {"level": heat_ratio})
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
	var heat_cfg: Dictionary = config()
	var retained: float = clampf(float(heat_cfg.get("round_end_retained", 0.5)), 0.0, 1.0)
	set_heat(run_state, float(run_state.compute.get("heat", 0.0)) * retained)
	var capacity: float = maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))
	if float(run_state.compute["heat"]) < capacity:
		run_state.flags["fire_risk"] = false


static func config() -> Dictionary:
	return ContentDatabase.balance.get("economy", {}).get("heat", {})


## Thermal load vs cooling power, and how that gap moves the stored-heat bar.
## `sustainable` and `cooling_needed` stay watt-vs-cooling. `heat_per_prompt`
## is the load-normalized bar tick, so a megawatt surplus cannot dump the
## gauge many times over in one prompt.
static func outlook(power_draw: float, cooling: float, heat_capacity: float) -> Dictionary:
	var heat_cfg: Dictionary = config()
	var gain_factor: float = float(heat_cfg.get("gain_per_power", 0.06))
	var cooling_factor: float = float(heat_cfg.get("cooling_factor", 0.25))
	var load_pressure: float = float(heat_cfg.get("load_pressure", 0.15))
	var thermal_load: float = power_draw * gain_factor
	var shed: float = cooling * cooling_factor
	return {
		"power_draw": power_draw,
		"cooling": cooling,
		"heat_per_prompt": ambient_delta(thermal_load, shed, heat_capacity, load_pressure),
		"sustainable": shed >= thermal_load,
		"cooling_needed": thermal_load / maxf(0.0001, cooling_factor),
	}


## imbalance = (load − shed) / max(load, shed, eps)  →  about −1 .. +1
## ambient   = imbalance × heat_capacity × load_pressure
static func ambient_delta(
	thermal_load: float, shed: float, heat_capacity: float, load_pressure: float
) -> float:
	var denom: float = maxf(maxf(thermal_load, shed), 0.0001)
	var imbalance: float = (thermal_load - shed) / denom
	return imbalance * maxf(1.0, heat_capacity) * load_pressure


## Pipeline cards, BOOST and event spikes are authored in bedroom points
## (capacity 100). Scale them so Overclock stays ~18% of the bar in every room.
static func scale_authored_heat(amount: float, heat_capacity: float) -> float:
	var reference: float = maxf(1.0, float(config().get("reference_capacity", 100.0)))
	return amount * maxf(1.0, heat_capacity) / reference


static func boost_heat_for(heat_capacity: float) -> float:
	return scale_authored_heat(float(config().get("boost_heat", 12.0)), heat_capacity)
