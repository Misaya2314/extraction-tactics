@tool
class_name MapSpawnData
extends Resource

@export var unit_name: StringName = &"Unit"
@export var faction: StringName = &"player"
@export var cell: Vector3i = Vector3i.ZERO
@export var facing: Vector2i = Vector2i.DOWN
@export var visual_color: Color = Color.WHITE
@export var patrol_route_id: StringName = &""

