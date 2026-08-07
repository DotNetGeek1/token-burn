class_name JobDefinition
extends Resource

## Static definition for a job encounter.

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var reward: float = 0.0
@export var token_requirement: float = 0.0
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
		"reward": reward,
		"token_requirement": token_requirement,
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
