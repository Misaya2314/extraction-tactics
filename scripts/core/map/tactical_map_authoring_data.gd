@tool
class_name TacticalMapAuthoringData
extends Resource

## Optional external authoring data. Existing scenes can continue to use only
## GridMap + MapTileCatalog; an absent resource means no overrides/edges.

const CURRENT_SCHEMA_VERSION: int = 1

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var cell_overrides: Array[TacticalCellOverride] = []
@export var edge_placements: Array[TacticalEdgePlacement] = []


func find_cell_override(coordinate: Vector3i) -> TacticalCellOverride:
	for override in cell_overrides:
		if override != null and override.coordinate == coordinate:
			return override
	return null


func get_cell_override_map() -> Dictionary:
	var result: Dictionary = {}
	for override in cell_overrides:
		if override != null:
			result[override.coordinate] = override
	return result


func get_edge_map() -> Dictionary:
	var result: Dictionary = {}
	for placement in edge_placements:
		if placement != null and placement.edge_key != null:
			result[placement.key_string()] = placement
	return result


func is_empty() -> bool:
	return cell_overrides.is_empty() and edge_placements.is_empty()

