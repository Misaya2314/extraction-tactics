@tool
class_name TacticalEdgeKey
extends Resource

## Canonical key for one horizontal edge. The pair is ordered so the same
## physical edge cannot be authored twice in opposite directions.

@export var cell_a: Vector3i = Vector3i.ZERO
@export var cell_b: Vector3i = Vector3i(1, 0, 0)


static func from_cells(first: Vector3i, second: Vector3i) -> TacticalEdgeKey:
	var result := TacticalEdgeKey.new()
	if _cell_less(first, second):
		result.cell_a = first
		result.cell_b = second
	else:
		result.cell_a = second
		result.cell_b = first
	return result


func canonicalized() -> TacticalEdgeKey:
	return from_cells(cell_a, cell_b)


func is_valid() -> bool:
	if cell_a.y < 0 or cell_b.y < 0 or cell_a.y != cell_b.y:
		return false
	return absi(cell_a.x - cell_b.x) + absi(cell_a.z - cell_b.z) == 1


func key_string() -> String:
	var canonical := canonicalized()
	return "%d,%d,%d|%d,%d,%d" % [
		canonical.cell_a.x, canonical.cell_a.y, canonical.cell_a.z,
		canonical.cell_b.x, canonical.cell_b.y, canonical.cell_b.z,
	]


func equals_other(other: TacticalEdgeKey) -> bool:
	return other != null and key_string() == other.key_string()


static func _cell_less(first: Vector3i, second: Vector3i) -> bool:
	if first.y != second.y:
		return first.y < second.y
	if first.z != second.z:
		return first.z < second.z
	return first.x < second.x

