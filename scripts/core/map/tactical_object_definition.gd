@tool
class_name TacticalObjectDefinition
extends TacticalPlaceableDefinition

## Stable object palette entry. Runtime object state remains in the session.

@export var object_kind: StringName = &"generic"
@export var scene: PackedScene
@export var footprint: Vector3i = Vector3i.ONE
@export var blocks_movement: bool = false
@export var blocks_los: bool = false


func _init() -> void:
	placement_kind = PlacementKind.OBJECT


func is_valid() -> bool:
	return super.is_valid() \
		and placement_kind == PlacementKind.OBJECT \
		and footprint.x > 0 and footprint.y > 0 and footprint.z > 0

