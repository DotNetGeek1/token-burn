class_name UpgradeDefinition
extends Resource

## Static definition for hardware, dwelling, cloud, or advertising upgrades.

@export var id: String = ""
@export var name: String = ""
@export var category: String = ""
@export var description: String = ""
@export var cost: float = 0.0
@export var tags: PackedStringArray = []
@export var effects: Array[EffectDefinition] = []
@export var recurring_cost_delta: float = 0.0
@export var hardware_key: String = ""
@export var dwelling_key: String = ""
## Component upgrades bolt onto a machine that is already installed: extra RAM,
## another graphics card, a shelf in a rack. They carry their own entry in
## hardware_curves but take no floor space, and one can be fitted per host owned.
@export var component_key: String = ""
@export var requires_hardware: String = ""
## Dwelling the player must already occupy. Property upgrades form a chain, so a
## warehouse cannot be leased straight out of the bedroom.
@export var requires_dwelling: String = ""
## Upgrade that must already be owned. Cloud stock hangs off the cloud account.
@export var requires_upgrade: String = ""
@export var repeatable: bool = false
@export var cost_growth: float = 1.35
@export var max_level: int = 0


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"category": category,
		"description": description,
		"cost": cost,
		"tags": Array(tags),
		"effects": effects.map(func(e: EffectDefinition) -> Dictionary: return e.to_dict()),
		"recurring_cost_delta": recurring_cost_delta,
		"hardware_key": hardware_key,
		"dwelling_key": dwelling_key,
		"component_key": component_key,
		"requires_hardware": requires_hardware,
		"requires_dwelling": requires_dwelling,
		"requires_upgrade": requires_upgrade,
		"repeatable": repeatable,
		"cost_growth": cost_growth,
		"max_level": max_level,
	}
