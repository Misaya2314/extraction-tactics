@tool
class_name TacticalMapDefinition
extends Resource

## Generated runtime contract for a tactical map. Authoring scenes are editable;
## this resource is rebuilt by TacticalMapBaker and treated as read-only at run time.

## Schema 1 is the original GridMap/Catalog bake. Schema 2 adds optional
## first-class edges while retaining every legacy field and cover_mask.
const MIN_SUPPORTED_SCHEMA_VERSION: int = 1
const CURRENT_SCHEMA_VERSION: int = 2

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var map_id: StringName = &"tactical_map"
@export var footprint_size: Vector2i = Vector2i.ZERO
@export var level_count: int = 1
@export var cell_size: Vector3 = Vector3(2.0, 2.0, 2.0)
@export var origin: Vector3 = Vector3.ZERO
@export var authoring_scene_path: String = ""
@export var cells: Array[MapCellData] = []
@export var transitions: Array[MapTransitionData] = []
@export var spawns: Array[MapSpawnData] = []
@export var patrol_routes: Array[MapPatrolRouteData] = []
@export var objects: Array[MapObjectPlacement] = []
@export var edges: Array[MapEdgeData] = []


static func is_schema_version_supported(version: int) -> bool:
	return version >= MIN_SUPPORTED_SCHEMA_VERSION and version <= CURRENT_SCHEMA_VERSION


func is_schema_compatible() -> bool:
	return is_schema_version_supported(schema_version)


func find_edge(edge_key: TacticalEdgeKey) -> MapEdgeData:
	if edge_key == null:
		return null
	var wanted := edge_key.key_string()
	for edge in edges:
		if edge != null and edge.key_string() == wanted:
			return edge
	return null


func find_patrol_route(route_id: StringName) -> MapPatrolRouteData:
	for route in patrol_routes:
		if route.route_id == route_id:
			return route
	return null


func get_player_spawn_cells() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for spawn in spawns:
		if spawn.faction == &"player":
			result.append(spawn.cell)
	return result


func get_extraction_cells() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for placement in objects:
		if placement.kind == MapObjectPlacement.Kind.EXTRACTION:
			result.append(placement.cell)
	return result
