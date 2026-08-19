class_name ComputeState
extends RefCounted

## Typed read/write view onto `RunState.compute`. See `EconomyState` for why
## this sits alongside the dictionary rather than replacing it yet.

var local_capacity: float = 1_000_000.0
var cloud_capacity: float = 0.0
var cloud_burst: float = 0.0
var cloud_burst_prompts: int = 0
var token_rate: float = 1_000_000.0
var prompt_rate: float = 1_000_000.0
var power_draw: float = 65.0
var cooling: float = 0.0
var meta_cooling: float = 0.0
var heat: float = 0.0
var heat_capacity: float = 100.0
var instability: float = 0.0
var efficiency: float = 1.0
var efficiency_base: float = 1.0
var rate_modifiers: Array = []


static func from_dict(data: Dictionary) -> ComputeState:
	var state := ComputeState.new()
	state.local_capacity = float(data.get("local_capacity", state.local_capacity))
	state.cloud_capacity = float(data.get("cloud_capacity", state.cloud_capacity))
	state.cloud_burst = float(data.get("cloud_burst", state.cloud_burst))
	state.cloud_burst_prompts = int(data.get("cloud_burst_prompts", state.cloud_burst_prompts))
	state.token_rate = float(data.get("token_rate", state.token_rate))
	state.prompt_rate = float(data.get("prompt_rate", state.prompt_rate))
	state.power_draw = float(data.get("power_draw", state.power_draw))
	state.cooling = float(data.get("cooling", state.cooling))
	state.meta_cooling = float(data.get("meta_cooling", state.meta_cooling))
	state.heat = float(data.get("heat", state.heat))
	state.heat_capacity = float(data.get("heat_capacity", state.heat_capacity))
	state.instability = float(data.get("instability", state.instability))
	state.efficiency = float(data.get("efficiency", state.efficiency))
	state.efficiency_base = float(data.get("efficiency_base", state.efficiency_base))
	state.rate_modifiers = Array(data.get("rate_modifiers", state.rate_modifiers)).duplicate(true)
	return state


func to_dict() -> Dictionary:
	return {
		"local_capacity": local_capacity,
		"cloud_capacity": cloud_capacity,
		"cloud_burst": cloud_burst,
		"cloud_burst_prompts": cloud_burst_prompts,
		"token_rate": token_rate,
		"prompt_rate": prompt_rate,
		"power_draw": power_draw,
		"cooling": cooling,
		"meta_cooling": meta_cooling,
		"heat": heat,
		"heat_capacity": heat_capacity,
		"instability": instability,
		"efficiency": efficiency,
		"efficiency_base": efficiency_base,
		"rate_modifiers": rate_modifiers.duplicate(true),
	}
