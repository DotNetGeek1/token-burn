class_name EffectOps
extends RefCounted

## Effect operation identifiers used by the effect resolver.

enum Operation {
	ADD,
	MULTIPLY,
	SET,
	CAP_MIN,
	CAP_MAX,
	CONVERT,
	COPY,
	SPAWN,
	REMOVE,
	REROLL,
	REPEAT,
	DISCOUNT,
	DEFER_COST,
	BORROW,
	TRIGGER,
}

## Resolution order phases for deterministic effect application.
enum ResolutionPhase {
	BASE,
	ADDITIVE,
	MULTIPLICATIVE,
	CONVERSION,
	CAPS,
	TRIGGERS,
	FINALISE,
}

## Safety limits for trigger-chain guards.
const MAX_TRIGGER_DEPTH := 32
const MAX_EFFECTS_PER_ACTION := 10000
const MAX_SAME_EVENT_RECURSION := 8
const MAX_SPAWNED_ENTITIES := 256


static func operation_from_string(value: String) -> int:
	var normalized := value.strip_edges().to_upper()
	match normalized:
		"ADD": return Operation.ADD
		"MULTIPLY": return Operation.MULTIPLY
		"SET": return Operation.SET
		"CAP_MIN": return Operation.CAP_MIN
		"CAP_MAX": return Operation.CAP_MAX
		"CONVERT": return Operation.CONVERT
		"COPY": return Operation.COPY
		"SPAWN": return Operation.SPAWN
		"REMOVE": return Operation.REMOVE
		"REROLL": return Operation.REROLL
		"REPEAT": return Operation.REPEAT
		"DISCOUNT": return Operation.DISCOUNT
		"DEFER_COST": return Operation.DEFER_COST
		"BORROW": return Operation.BORROW
		"TRIGGER": return Operation.TRIGGER
		_: return Operation.ADD


static func phase_for_operation(operation: String) -> int:
	match operation.to_lower():
		"add", "discount", "defer_cost", "borrow":
			return ResolutionPhase.ADDITIVE
		"multiply":
			return ResolutionPhase.MULTIPLICATIVE
		"convert", "copy":
			return ResolutionPhase.CONVERSION
		"cap_min", "cap_max", "set":
			return ResolutionPhase.CAPS
		"trigger":
			return ResolutionPhase.TRIGGERS
		"spawn", "remove", "reroll", "repeat":
			return ResolutionPhase.FINALISE
		_:
			return ResolutionPhase.BASE
