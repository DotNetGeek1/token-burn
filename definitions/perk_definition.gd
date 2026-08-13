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
@export var min_location_tier: int = 0
@export var max_location_tier: int = -1
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
		"min_location_tier": min_location_tier,
		"max_location_tier": max_location_tier,
		"draft_weight": draft_weight,
		"difficulty": Array(difficulty),
		"grants": grants,
	}
