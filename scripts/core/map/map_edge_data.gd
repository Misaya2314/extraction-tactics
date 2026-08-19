@tool
class_name MapEdgeData
extends Resource

## Baked/runtime representation of one canonical edge. It intentionally does
## not convert legacy cover_mask automatically; Phase A keeps both contracts.

@export var cell_a: Vector3i = Vector3i.ZERO
@export var cell_b: Vector3i = Vector3i(1, 0, 0)
@export var placeable_id: StringName = &""
@export var cover_a: TacticalEdgeRules.CoverLevel = TacticalEdgeRules.CoverLevel.NONE
@export var cover_b: TacticalEdgeRules.CoverLevel = TacticalEdgeRules.CoverLevel.NONE
@export var blocks_movement: bool = false
@export_range(0.0, 1.0, 0.01) var sight_block: float = 0.0
@export_range(0.0, 1.0, 0.01) var projectile_block: float = 0.0
@export_range(0.0, 20.0, 0.05) var height: float = 0.0
@export var destructible: bool = false
@export var runtime_state_id: StringName = &""


static func from_placement(placement: TacticalEdgePlacement) -> MapEdgeData:
	var result := MapEdgeData.new()
	if placement == null or placement.edge_key == null:
		return result
	# TacticalEdgeRules.cover_a/cover_b are authored against the original
	# placement.edge_key.cell_a/cell_b endpoints. The baked edge uses the
	# canonical endpoint order, so preserve the physical side by swapping the
	# two cover values when authoring order is reversed.
	var source_a := placement.edge_key.cell_a
	var source_b := placement.edge_key.cell_b
	var key := placement.edge_key.canonicalized()
	result.cell_a = key.cell_a
	result.cell_b = key.cell_b
	result.placeable_id = placement.placeable_id
	if placement.rules != null:
		var source_is_reversed := source_a == key.cell_b and source_b == key.cell_a
		if source_is_reversed:
			result.cover_a = placement.rules.cover_b
			result.cover_b = placement.rules.cover_a
		else:
			result.cover_a = placement.rules.cover_a
			result.cover_b = placement.rules.cover_b
		result.blocks_movement = placement.rules.blocks_movement
		result.sight_block = placement.rules.sight_block
		result.projectile_block = placement.rules.projectile_block
		result.height = placement.rules.height
		result.destructible = placement.rules.destructible
		result.runtime_state_id = placement.rules.runtime_state_id
	return result


func get_key() -> TacticalEdgeKey:
	return TacticalEdgeKey.from_cells(cell_a, cell_b)


func key_string() -> String:
	return get_key().key_string()
