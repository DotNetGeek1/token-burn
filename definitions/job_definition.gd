class_name JobDefinition
extends Resource

## Static definition for a job encounter.

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
## Which location's band this contract belongs to, as an index into
## job_scaling.location_bands. A contract is sized and paid by its band, so this
## is the single thing that decides how big a piece of work it is.
@export var tier: int = 0
## Workload relative to the band's target burn count. 1.0 is an ordinary
## contract for the location; 0.6 is a quick one, 1.5 a slog.
@export var work_units: float = 1.0
## Fee relative to the band's base reward, on the same scale.
@export var reward_units: float = 1.0
## Above 1.0 the deadline is tighter than the work would suggest.
@export var deadline_pressure: float = 1.0
## A contract that can pay for a whole rung of the hardware ladder in one go.
## Flagged so the board can advertise it and so balance checks can exempt it.
@export var windfall: bool = false
@export var quality_threshold: float = 0.0
@export var deadline_days: float = 0.0
@export var context_requirement: String = ""
@export var revision_risk: float = 0.0
@export var tags: PackedStringArray = []
@export var complications: Array[Dictionary] = []
@export var stretch_goals: Array[Dictionary] = []
## Constraints this contract imposes on the Burn Board. See BoardSystem.RULE_*.
@export var board_rules: Array[Dictionary] = []
## What this contract needs from the workflow assigned to it, by id into
## content/balance/job_demands.json. A workflow that answers a demand is paid
## for it; one that ignores it is punished for that too.
@export var demands: PackedStringArray = []


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"description": description,
		"tier": tier,
		"work_units": work_units,
		"reward_units": reward_units,
		"deadline_pressure": deadline_pressure,
		"windfall": windfall,
		"quality_threshold": quality_threshold,
		"deadline_days": deadline_days,
		"context_requirement": context_requirement,
		"revision_risk": revision_risk,
		"tags": Array(tags),
		"complications": complications,
		"stretch_goals": stretch_goals,
		"board_rules": board_rules,
		"demands": Array(demands),
	}
