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
	}
