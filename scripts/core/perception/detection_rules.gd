class_name DetectionRules
extends RefCounted

const TacticalLineQueryScript = preload("res://scripts/core/cover/tactical_line_query.gd")
const _CARDINAL_FACING: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func is_in_vision_cone(observer: Vector3i, target: Vector3i, facing: Vector2i, vision_range: int, half_angle_degrees: float = 60.0) -> bool:
	if vision_range < 0 or half_angle_degrees < 0.0 or is_nan(half_angle_degrees) or is_inf(half_angle_degrees):
		return false
	if not _CARDINAL_FACING.has(facing):
		return false
	if observer == target:
		return true
	if GridVisibility.tactical_distance(observer, target) > vision_range:
		return false
	var offset := Vector2i(target.x - observer.x, target.z - observer.z)
	if offset == Vector2i.ZERO:
		return true
	var dot_product := facing.x * offset.x + facing.y * offset.y
	var cosine_limit := cos(deg_to_rad(minf(half_angle_degrees, 180.0)))
	var normalized_dot := float(dot_product) / sqrt(float(offset.length_squared()))
	return normalized_dot + 0.000001 >= cosine_limit


static func can_detect(
	observer: Vector3i,
	target: Vector3i,
	facing: Vector2i,
	vision_range: int,
	opaque_cells: Dictionary,
	half_angle_degrees: float = 60.0,
	grid: GridModel = null,
	edge_index: TacticalEdgeIndex = null
) -> bool:
	return is_in_vision_cone(observer, target, facing, vision_range, half_angle_degrees) \
		and _has_line_of_sight(observer, target, opaque_cells, vision_range, grid, edge_index)


static func can_player_see(
	observer: Vector3i,
	target: Vector3i,
	vision_range: int,
	opaque_cells: Dictionary,
	grid: GridModel = null,
	edge_index: TacticalEdgeIndex = null
) -> bool:
	return _has_line_of_sight(observer, target, opaque_cells, vision_range, grid, edge_index)


## Compatibility boundary for perception.  With a runtime GridModel, the
## authoritative line query includes explicit Edge.sight_block only; its
## projectile flag is deliberately ignored here.  Without one, preserve the
## original opaque-cell-only behavior and call signature semantics.
static func _has_line_of_sight(
	observer: Vector3i,
	target: Vector3i,
	opaque_cells: Dictionary,
	vision_range: int,
	grid: GridModel = null,
	edge_index: TacticalEdgeIndex = null
) -> bool:
	# DetectionRules historically requires a non-negative vision range even
	# though GridVisibility itself uses -1 to mean unlimited range.
	if vision_range < 0:
		return false
	if vision_range >= 0 and GridVisibility.tactical_distance(observer, target) > vision_range:
		return false
	if grid != null:
		var line := TacticalLineQueryScript.query(observer, target, grid, edge_index, opaque_cells)
		return line.has_line_of_sight()
	return GridVisibility.has_line_of_sight(observer, target, opaque_cells, vision_range)
