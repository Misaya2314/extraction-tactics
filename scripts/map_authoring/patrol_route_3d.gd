@tool
class_name PatrolRoute3D
extends Node3D

@export var route_id: StringName = &"route"
## Sparse key waypoints.  Cells between waypoints are filled by pathfinding
## at runtime, so a 2-4 point route is enough for a full patrol circuit.
@export var points: Array[Vector3i] = []
## Parallel to points: exploration ticks the guard idles after arriving.
@export var dwell_ticks: Array[int] = []
@export var loop: bool = true


func to_data() -> MapPatrolRouteData:
	var data := MapPatrolRouteData.new()
	data.route_id = route_id
	data.points = points.duplicate()
	data.dwell_ticks = dwell_ticks.duplicate()
	data.loop = loop
	return data
