@tool
class_name TacticalStampDefinition
extends TacticalPlaceableDefinition

## Phase-A stamp skeleton. The editor may later define typed entries and
## transactional painting; the compiler does not expand stamps yet.

@export var footprint: Vector3i = Vector3i.ONE
@export var entries: Array[Dictionary] = []


func _init() -> void:
	placement_kind = PlacementKind.STAMP


func is_valid() -> bool:
	return super.is_valid() \
		and placement_kind == PlacementKind.STAMP \
		and footprint.x > 0 and footprint.y > 0 and footprint.z > 0

