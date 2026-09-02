class_name DetectionRules
extends RefCounted

const TacticalLineQueryScript = preload("res://scripts/core/cover/tactical_line_query.gd")

enum DetectionTier {
	NONE = 0,
	OUTER_ALERT = 1,
	INNER_DISCOVERY = 2,
}


static func is_in_range(observer: Vector3i, target: Vector3i, vision_range: int) -> bool:
	if vision_range < 0:
		return false
	if observer == target:
		return true
	return GridVisibility.tactical_distance(observer, target) <= vision_range


static func can_detect(
	observer: Vector3i,
	target: Vector3i,
	vision_range: int,
	opaque_cells: Dictionary = {},
	grid: GridModel = null,
	edge_index: TacticalEdgeIndex = null
) -> bool:
	return is_in_range(observer, target, vision_range) \
		and _has_line_of_sight(observer, target, opaque_cells, vision_range, grid, edge_index)


static func evaluate_detection_tier(
	observer: Vector3i,
	target: Vector3i,
	inner_vision_range: int,
	outer_vision_range: int,
	opaque_cells: Dictionary = {},
	grid: GridModel = null,
	edge_index: TacticalEdgeIndex = null
) -> DetectionTier:
	if can_detect(observer, target, inner_vision_range, opaque_cells, grid, edge_index):
		return DetectionTier.INNER_DISCOVERY
	if can_detect(observer, target, outer_vision_range, opaque_cells, grid, edge_index):
		return DetectionTier.OUTER_ALERT
	return DetectionTier.NONE


static func can_player_see(
	observer: Vector3i,
	target: Vector3i,
	vision_range: int,
	_opaque_cells: Dictionary = {},
	_grid: GridModel = null,
	_edge_index: TacticalEdgeIndex = null
) -> bool:
	if vision_range < 0:
		return false
	return GridVisibility.tactical_distance(observer, target) <= vision_range


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
