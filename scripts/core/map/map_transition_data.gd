@tool
class_name MapTransitionData
extends Resource

## Explicit connection between standable surfaces. Vertical movement is never
## inferred merely because two cells share the same X/Z coordinate.

enum Kind {
	STAIRS,
	RAMP,
	LADDER,
	DROP,
	CUSTOM,
}

@export var from_cell: Vector3i = Vector3i.ZERO
@export var to_cell: Vector3i = Vector3i.ZERO
@export_range(1, 99, 1) var move_cost: int = 1
@export var bidirectional: bool = true
@export var enabled: bool = true
@export var kind: Kind = Kind.STAIRS

