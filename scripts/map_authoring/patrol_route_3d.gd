@tool
class_name PatrolRoute3D
extends Node3D

@export var route_id: StringName = &"route"
@export var points: Array[Vector3i] = []
@export var loop: bool = true


func to_data() -> MapPatrolRouteData:
	var data := MapPatrolRouteData.new()
	data.route_id = route_id
	data.points = points.duplicate()
	data.loop = loop
	return data
