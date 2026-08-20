@tool
class_name TacticalObjectDefinition
extends TacticalPlaceableDefinition

## Stable object palette entry. Runtime object state remains in the session.

@export var object_kind: StringName = &"generic"
@export var category: StringName = &"对象"
@export_multiline var description: String = ""
@export var scene: PackedScene
@export var footprint: Vector3i = Vector3i.ONE
@export var blocks_movement: bool = false
@export var blocks_los: bool = false
@export var loot_table: LootTableDefinition
@export var loot_seed: int = -1


func _init() -> void:
	placement_kind = PlacementKind.OBJECT


func is_valid() -> bool:
	return super.is_valid() \
		and placement_kind == PlacementKind.OBJECT \
		and footprint.x > 0 and footprint.y > 0 and footprint.z > 0
