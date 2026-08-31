@tool
class_name GameContentManifest
extends Resource

## Explicit content inventory. Runtime code must consume these references and
## must not recursively scan res:// for Definitions.

const CURRENT_SCHEMA_VERSION := 1

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var item_definitions: Array[ItemDefinition] = []
@export var weapon_definitions: Array[WeaponDefinition] = []
@export var unit_archetypes: Array[UnitArchetype] = []
@export var map_definitions: Array[TacticalMapDefinition] = []
@export var placeable_definitions: Array[TacticalPlaceableDefinition] = []
@export var cover_profiles: Array[TacticalCoverProfile] = []
@export var aliases: Array[Resource] = []


func get_definition_groups() -> Array[Dictionary]:
	return [
		{&"definition_type": &"item", &"definitions": item_definitions},
		{&"definition_type": &"weapon", &"definitions": weapon_definitions},
		{&"definition_type": &"unit_archetype", &"definitions": unit_archetypes},
		{&"definition_type": &"map", &"definitions": map_definitions},
		{&"definition_type": &"placeable", &"definitions": placeable_definitions},
		{&"definition_type": &"cover", &"definitions": cover_profiles},
	]


func is_schema_compatible() -> bool:
	return schema_version == CURRENT_SCHEMA_VERSION
