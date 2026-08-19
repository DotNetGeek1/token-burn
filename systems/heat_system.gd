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


static func heat_config() -> Dictionary:
	return Dictionary(ContentDatabase.balance.get("economy", {}).get("heat", {}))


static func work_tier(run_state: RunState) -> int:
	return JobSystem.rig_work_tier(run_state, ContentDatabase)


static func heat_ratio(run_state: RunState) -> float:
	return float(run_state.compute.get("heat", 0.0)) / maxf(
		1.0, float(run_state.compute.get("heat_capacity", 100.0))
	)


static func generation(power_draw: float, cfg: Dictionary = {}) -> float:
	if cfg.is_empty():
		cfg = heat_config()
	return power_draw * float(cfg.get("gain_per_power", 0.06))


static func sink(cooling: float, cfg: Dictionary = {}) -> float:
	if cfg.is_empty():
		cfg = heat_config()
	return cooling * float(cfg.get("cooling_factor", 0.25))


## Bedroom and garage keep the old absolute ambient model. From GPU Rack onward
## ambient heat is a slice of the local bar, so megawatt cooling cannot erase
## an Overclock-sized kick.
static func uses_thermal_load(tier: int) -> bool:
	return FeatureFlags.is_enabled("thermal_load_enabled") and tier >= 2


static func ambient_delta_for(
	power_draw: float, cooling: float, capacity: float, tier: int
) -> float:
	var cfg: Dictionary = heat_config()
	var gen: float = generation(power_draw, cfg)
	var snk: float = sink(cooling, cfg)
	if not uses_thermal_load(tier):
		return gen - snk
	var load_ratio: float = gen / maxf(snk, 0.001)
	var equilibrium: float = 1.0 - float(cfg.get("era_heat_bias", 0.09)) * float(maxi(0, tier - 1))
	var stress: float = load_ratio - equilibrium
	return maxf(1.0, capacity) * float(cfg.get("ambient_rate", 0.10)) * stress


static func ambient_delta(run_state: RunState) -> float:
	return ambient_delta_for(
		float(run_state.compute.get("power_draw", 0.0)),
		float(run_state.compute.get("cooling", 0.0)),
		maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0))),
		work_tier(run_state)
	)


static func cooling_needed_for(power_draw: float, tier: int) -> float:
	var cfg: Dictionary = heat_config()
	var gen: float = generation(power_draw, cfg)
	var factor: float = maxf(0.0001, float(cfg.get("cooling_factor", 0.25)))
	if not uses_thermal_load(tier):
		return gen / factor
	var equilibrium: float = 1.0 - float(cfg.get("era_heat_bias", 0.09)) * float(maxi(0, tier - 1))
	return gen / (maxf(0.05, equilibrium) * factor)


static func scale_pipeline_heat(run_state: RunState, authored: float) -> float:
	if not uses_thermal_load(work_tier(run_state)):
		return authored
	var ref: float = maxf(1.0, float(heat_config().get("pipeline_heat_ref_capacity", 100.0)))
	var capacity: float = maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))
	return authored * (capacity / ref)


static func apply_pipeline_heat(heat_system: HeatSystem, run_state: RunState, authored: float) -> float:
	return heat_system.add_heat(run_state, scale_pipeline_heat(run_state, authored))


static func instability_from_ratio(ratio: float, tier: int) -> float:
	if not FeatureFlags.is_enabled("instability_enabled") or tier < 2:
		return 0.0
	if ratio < 0.70:
		return 0.0
	if ratio < 0.85:
		return lerpf(0.00, 0.25, (ratio - 0.70) / 0.15)
	if ratio < 1.00:
		return lerpf(0.25, 0.55, (ratio - 0.85) / 0.15)
	if ratio < 1.40:
		return lerpf(0.55, 0.85, (ratio - 1.00) / 0.40)
	return 1.0


static func catastrophe_ratio(tier: int) -> float:
	if not FeatureFlags.is_enabled("instability_enabled") or tier < 2:
		return 1.0
	return float(heat_config().get("catastrophe_ratio", 1.5))


static func fire_risk_ratio(tier: int) -> float:
	if not FeatureFlags.is_enabled("instability_enabled") or tier < 2:
		return 1.0
	return float(heat_config().get("fire_risk_ratio", 1.4))


static func overclock_band_bonus(ratio: float, tier: int) -> float:
	if not FeatureFlags.is_enabled("instability_enabled") or tier < 2:
		return 1.0
	if ratio < 0.70 or ratio >= 0.85:
		return 1.0
	return 1.0 + 0.15 * ((ratio - 0.70) / 0.15)


func process_prompt(
	run_state: RunState,
	subscriptions: Array,
	effect_resolver: EffectResolver,
	rng: DeterministicRng,
	mode: int = ResolveMode.COMMIT
) -> Array[String]:
	var messages: Array[String] = []
	var heat_cfg: Dictionary = heat_config()
	var throttle_ratio: float = float(heat_cfg.get("throttle_ratio", 0.8))
	var throttle_mult: float = float(heat_cfg.get("throttle_multiplier", 0.75))
	var capacity: float = maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))
	var tier: int = work_tier(run_state)

	add_heat(run_state, ambient_delta(run_state))
	var ratio: float = float(run_state.compute["heat"]) / capacity
	run_state.compute["instability"] = instability_from_ratio(ratio, tier)
	run_state.statistics["max_instability"] = maxf(
		float(run_state.statistics.get("max_instability", 0.0)),
		float(run_state.compute["instability"])
	)
	if ratio >= throttle_ratio:
		# The throttle is added to the modifier list here, but `end_prompt`
		# only recalculates the sustained rate afterwards — this prompt's
		# batch was already resolved before heat was processed, so the
		# slowdown is what the *next* prompt will run at, not this one.
		run_state.add_rate_modifier(throttle_mult, 1, "heat_throttle")
		messages.append("Heat throttling engaged at %d%%." % int(ratio * 100.0))
		if mode == ResolveMode.COMMIT:
			EventBus.emit_event(EventBus.EVENT_HEAT_THRESHOLD_CROSSED, {"level": ratio})
		effect_resolver.begin_action("heat.threshold_crossed")
		var mod_ctx := ModifierContext.new("heat.threshold_crossed", run_state)
		mod_ctx.rng = rng.derive("heat.threshold_crossed")
		mod_ctx.set_value("compute.heat", run_state.compute["heat"])
		mod_ctx.extras["heat_ratio"] = ratio
		mod_ctx.extras["instability"] = float(run_state.compute["instability"])
		effect_resolver.dispatch("heat.threshold_crossed", mod_ctx, subscriptions)
	var risk_line: float = fire_risk_ratio(tier)
	# Re-evaluated every prompt rather than latched, so a rig that cools back
	# down is out of danger instead of staying one spike away from a fire.
	run_state.flags["fire_risk"] = ratio >= risk_line
	if ratio >= risk_line:
		messages.append("Hardware is dangerously hot!")
	if mode == ResolveMode.COMMIT:
		messages.append_array(_maybe_fault(run_state, rng, ratio, tier))
	return messages


func _maybe_fault(
	run_state: RunState, rng: DeterministicRng, ratio: float, tier: int
) -> Array[String]:
	var messages: Array[String] = []
	if not FeatureFlags.is_enabled("instability_enabled") or tier < 3:
		return messages
	if ratio < 0.85:
		return messages
	if _has_status(run_state, "status.fault.dead_rack"):
		return messages
	var band_t: float = 1.0 if ratio >= 1.0 else (ratio - 0.85) / 0.15
	if rng.derive("compute.fault").next_float() >= 0.08 * band_t:
		return messages
	if not (run_state.build.get("status_effects") is Array):
		run_state.build["status_effects"] = []
	run_state.build["status_effects"].append({
		"id": "status.fault.dead_rack",
		"name": "Rack offline",
		"rounds": 2,
		"subscriptions": [{
			"event": "compute.recalculate",
			"priority": 0,
			"conditions": [],
			"effects": [
				{"operation": "multiply", "target": "compute.local_rate", "value": 0.82},
			],
		}],
	})
	run_state.statistics["faults_suffered"] = int(run_state.statistics.get("faults_suffered", 0)) + 1
	EventBus.emit_event(EventBus.EVENT_FAULT_STARTED, {"id": "status.fault.dead_rack"})
	messages.append("A rack went offline — lose 18% capacity until it comes back.")
	return messages


static func _has_status(run_state: RunState, status_id: String) -> bool:
	for status in Array(run_state.build.get("status_effects", [])):
		if status is Dictionary and str(status.get("id", "")) == status_id:
			return true
	return false


## Downtime between rounds lets the hardware cool off, so one bad round is
## recoverable instead of a one-way trip to a fire.
func shed_between_rounds(run_state: RunState) -> void:
	var heat_cfg: Dictionary = heat_config()
	var retained: float = clampf(float(heat_cfg.get("round_end_retained", 0.5)), 0.0, 1.0)
	set_heat(run_state, float(run_state.compute.get("heat", 0.0)) * retained)
	var capacity: float = maxf(1.0, float(run_state.compute.get("heat_capacity", 100.0)))
	var ratio: float = float(run_state.compute["heat"]) / capacity
	if ratio < fire_risk_ratio(work_tier(run_state)):
		run_state.flags["fire_risk"] = false
	run_state.compute["instability"] = instability_from_ratio(ratio, work_tier(run_state))


## Watt-vs-cooling sustainability plus the bar tick for this room and era.
static func outlook(
	power_draw: float, cooling: float, heat_capacity: float, tier: int = 0
) -> Dictionary:
	var delta: float = ambient_delta_for(power_draw, cooling, heat_capacity, tier)
	var needed: float = cooling_needed_for(power_draw, tier)
	return {
		"power_draw": power_draw,
		"cooling": cooling,
		"heat_per_prompt": delta,
		"sustainable": delta <= 0.0,
		"cooling_needed": needed,
	}


## Event spikes and BOOST are authored in bedroom points (capacity 100).
## Scale them so Overclock stays ~18% of the bar in every room.
static func scale_authored_heat(amount: float, heat_capacity: float) -> float:
	var cfg: Dictionary = heat_config()
	var reference: float = maxf(1.0, float(cfg.get(
		"reference_capacity", cfg.get("pipeline_heat_ref_capacity", 100.0)
	)))
	return amount * maxf(1.0, heat_capacity) / reference


static func boost_heat_for(heat_capacity: float) -> float:
	return scale_authored_heat(float(heat_config().get("boost_heat", 12.0)), heat_capacity)
