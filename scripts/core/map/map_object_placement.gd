@tool
class_name MapObjectPlacement
extends Resource

enum Kind {
	LOOT,
	EXTRACTION,
	EXPLOSIVE,
	DOOR,
	GENERIC,
}

@export var object_id: StringName = &"object"
## New authoring data records the stable Placeable Definition when available.
## Empty keeps old maps loadable; runtime factories then use their explicit
## unique scene/object-kind compatibility lookup.
@export var definition_id: StringName = &""
@export var kind: Kind = Kind.GENERIC
@export var cell: Vector3i = Vector3i.ZERO
@export var facing: Vector2i = Vector2i.DOWN
@export var scene: PackedScene
@export var blocks_movement: bool = false
@export var blocks_los: bool = false
@export var loot_table: LootTableDefinition
@export var loot_seed: int = -1


func has_definition() -> bool:
	return definition_id != &""


func is_loot_configuration_valid() -> bool:
	return get_loot_configuration_error().is_empty()


func get_loot_configuration_error() -> String:
	if kind == Kind.LOOT:
		if loot_table == null:
			return "LOOT object %s requires a LootTableDefinition." % object_id
		if not loot_table.is_valid():
			return "LOOT object %s references an invalid LootTableDefinition." % object_id
		return ""
	if loot_table != null:
		return "Non-LOOT object %s has a loot_table; the table will be ignored." % object_id
	return ""
