@tool
class_name TacticalEdgeDefinition
extends TacticalPlaceableDefinition

## Palette definition for a first-class edge. Edge placement is intentionally
## separate from cell cover calculation in Phase A.

@export var edge_rules: TacticalEdgeRules
@export var scene: PackedScene
@export var mesh_item_id: int = -1


func _init() -> void:
	placement_kind = PlacementKind.EDGE


func is_valid() -> bool:
	return super.is_valid() and placement_kind == PlacementKind.EDGE

