@tool
class_name TacticalEdgePlacement
extends Resource

@export var edge_key: TacticalEdgeKey
@export var placeable_id: StringName = &""
@export var rules: TacticalEdgeRules
@export_range(0, 270, 90) var rotation_degrees: int = 0
@export var enabled: bool = true
@export var metadata: Dictionary = {}


func is_valid() -> bool:
	return edge_key != null and edge_key.is_valid() \
		and TacticalPlaceableDefinition.is_valid_id(placeable_id) \
		and (rules == null or rules.is_valid())


func is_active() -> bool:
	return enabled and is_valid()


func key_string() -> String:
	return "" if edge_key == null else edge_key.key_string()
