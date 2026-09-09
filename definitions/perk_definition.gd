class_name PerkDefinition
extends Resource

## Static definition for a build-altering perk.

@export var id: String = ""
@export var name: String = ""
@export var rarity: String = "common"
@export var tags: PackedStringArray = []
@export var description_template: String = ""
@export var parameters: Dictionary = {}
@export var subscriptions: Array[Dictionary] = []
@export var requires_tags: PackedStringArray = []
@export var excludes_tags: PackedStringArray = []
@export var incompatible_ids: PackedStringArray = []
@export var stacking: Dictionary = {}
@export var unlock_achievement: String = ""
## The lowest Investor Level (1-based) the perk can be drafted at. 0 or 1
## means from the first target.
@export var min_investor_level: int = 0
## The highest Investor Level the perk can be drafted at; -1 for no ceiling.
@export var max_investor_level: int = -1
@export var draft_weight: float = 1.0
@export var difficulty: PackedStringArray = ["normal", "hard"]
@export var grants: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"rarity": rarity,
		"tags": Array(tags),
		"description_template": description_template,
		"parameters": parameters,
		"subscriptions": subscriptions,
		"requires_tags": Array(requires_tags),
		"excludes_tags": Array(excludes_tags),
		"incompatible_ids": Array(incompatible_ids),
		"stacking": stacking,
		"unlock_achievement": unlock_achievement,
		"min_investor_level": min_investor_level,
		"max_investor_level": max_investor_level,
		"draft_weight": draft_weight,
		"difficulty": Array(difficulty),
		"grants": grants,
	}
