@tool
class_name MapPatrolRouteData
extends Resource

## Sparse waypoint route.  Waypoints are key turning points only; movement
## between them is filled by runtime pathfinding.

@export var route_id: StringName = &"route"
@export var points: Array[Vector3i] = []
## Parallel to points: how many exploration ticks the guard stays idle after
## arriving at each waypoint (0 = no stop).
@export var dwell_ticks: Array[int] = []
@export var loop: bool = true


func get_dwell_ticks_at(index: int) -> int:
	if index < 0 or index >= dwell_ticks.size():
		return 0
	return maxi(int(dwell_ticks[index]), 0)

