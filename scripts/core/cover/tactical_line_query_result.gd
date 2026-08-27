class_name TacticalLineQueryResult
extends RefCounted

## Deterministic result of tracing one attack line through the logical grid.

var valid: bool = false
var reason: StringName = &""
var attacker_cell: Vector3i = Vector3i(-1, -1, -1)
var target_cell: Vector3i = Vector3i(-1, -1, -1)
var cross_level: bool = false
var cells_crossed: Array[Vector3i] = []
var edges_crossed: Array[MapEdgeData] = []
var target_incoming_edges: Array[MapEdgeData] = []
var los_blocked: bool = false
var projectile_blocked: bool = false
## Independent obstruction sources.  These are intentionally separate when
## one cell/edge blocks both channels.
var sight_blocking_cell: Vector3i = Vector3i(-1, -1, -1)
var projectile_blocking_cell: Vector3i = Vector3i(-1, -1, -1)
var sight_blocking_edge: MapEdgeData
var projectile_blocking_edge: MapEdgeData
var sight_blocking_edge_key: String = ""
var projectile_blocking_edge_key: String = ""
## Compatibility aggregate: the first blocking cell in trace order and the
## minimum canonical edge key among all actual edge blockers.
var blocking_cell: Vector3i = Vector3i(-1, -1, -1)
var blocking_edge: MapEdgeData
var blocking_edge_key: String = ""


func can_attack() -> bool:
	return valid and not los_blocked and not projectile_blocked


func has_line_of_sight() -> bool:
	return valid and not los_blocked


func is_projectile_blocked() -> bool:
	return projectile_blocked


func is_blocked() -> bool:
	return los_blocked or projectile_blocked
