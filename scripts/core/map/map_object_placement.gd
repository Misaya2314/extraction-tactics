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
@export var kind: Kind = Kind.GENERIC
@export var cell: Vector3i = Vector3i.ZERO
@export var facing: Vector2i = Vector2i.DOWN
@export var scene: PackedScene
@export var blocks_movement: bool = false
@export var blocks_los: bool = false

