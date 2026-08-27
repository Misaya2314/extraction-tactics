@tool
class_name TacticalLocalEdgeContribution
extends Resource

## A Structure/Cell contribution expressed in the definition's local compass.
## Baker rotates this direction through the placed GridMap Basis.

enum LocalDirection {
	NORTH,
	EAST,
	SOUTH,
	WEST,
}

@export var local_direction: LocalDirection = LocalDirection.NORTH
@export var edge_rules: TacticalEdgeRules
@export var enabled: bool = true


func is_valid() -> bool:
	return local_direction >= LocalDirection.NORTH \
		and local_direction <= LocalDirection.WEST \
		and edge_rules != null \
		and edge_rules.is_valid()


func is_active() -> bool:
	return enabled and is_valid()


func duplicate_contribution() -> TacticalLocalEdgeContribution:
	var result := TacticalLocalEdgeContribution.new()
	result.local_direction = local_direction
	result.edge_rules = edge_rules.duplicate_rules() if edge_rules != null else null
	result.enabled = enabled
	return result
