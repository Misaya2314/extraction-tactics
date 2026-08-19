@tool
class_name TacticalCellTileDefinition
extends TacticalPlaceableDefinition

## A stable cell/tile definition. The numeric mesh item is only a binding.

@export var tile_id: StringName = &"tile"
@export var target_layer: MapTileRule.Layer = MapTileRule.Layer.FLOOR
@export var mesh_item_id: int = -1
@export var mesh_library: MeshLibrary
@export var footprint: Vector3i = Vector3i.ONE
@export var rule_contribution: TacticalCellRules


func _init() -> void:
	placement_kind = PlacementKind.CELL


func is_valid() -> bool:
	return super.is_valid() \
		and placement_kind == PlacementKind.CELL \
		and mesh_item_id >= 0 \
		and footprint.x > 0 and footprint.y > 0 and footprint.z > 0 \
		and (rule_contribution == null or rule_contribution.is_valid())

