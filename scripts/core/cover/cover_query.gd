class_name CoverQuery
extends RefCounted

const TacticalLineQueryScript = preload("res://scripts/core/cover/tactical_line_query.gd")

## Reads only the target-side profile of the final incoming edge.  For a
## supercover corner, all incoming candidates are considered and the strongest
## reduction wins; ties use cover level and then canonical EdgeKey.
static func query(
	attacker_cell: Vector3i,
	target_cell: Vector3i,
	grid: GridModel,
	edge_index: TacticalEdgeIndex = null,
	settings: CoverCombatSettings = null,
	opaque_cells: Dictionary = {}
) -> CoverQueryResult:
	var result := CoverQueryResult.new()
	result.attacker_cell = attacker_cell
	result.target_cell = target_cell
	result.cross_level = attacker_cell.y != target_cell.y
	var line := TacticalLineQueryScript.query(attacker_cell, target_cell, grid, edge_index, opaque_cells)
	result.valid = line.valid
	result.reason = line.reason
	result.cells_crossed = line.cells_crossed.duplicate()
	result.edges_crossed = line.edges_crossed.duplicate()
	result.target_incoming_edges = line.target_incoming_edges.duplicate()
	result.candidate_edges = result.target_incoming_edges.duplicate()
	result.los_blocked = line.los_blocked
	result.projectile_blocked = line.projectile_blocked
	result.sight_blocking_cell = line.sight_blocking_cell
	result.projectile_blocking_cell = line.projectile_blocking_cell
	result.sight_blocking_edge = line.sight_blocking_edge
	result.projectile_blocking_edge = line.projectile_blocking_edge
	result.sight_blocking_edge_key = line.sight_blocking_edge_key
	result.projectile_blocking_edge_key = line.projectile_blocking_edge_key
	result.blocking_cell = line.blocking_cell
	result.blocking_edge = line.blocking_edge
	result.blocking_edge_key = line.blocking_edge_key
	result.block_reason = line.reason if line.is_blocked() else &""
	if not line.valid:
		return result

	var resolved_settings := settings if settings != null else CoverCombatSettings.make_default()
	var none_profile := resolved_settings.get_profile_for_level(0)
	result.profile = none_profile
	result.cover_profile_id = none_profile.cover_id if none_profile != null else &"cover.none"
	if result.cross_level:
		result.reason = &"unsupported_height_relation" if not result.is_blocked() else result.reason
		return result

	if result.target_incoming_edges.is_empty():
		result.reason = &"no_edge" if not result.is_blocked() else result.reason
		return result

	var best_edge: MapEdgeData
	var best_profile: TacticalCoverProfile
	var best_side := -1
	for edge in result.target_incoming_edges:
		var side := 0 if edge.cell_a == target_cell else 1
		var legacy_level := edge.cover_a if side == 0 else edge.cover_b
		var authored_profile := edge.cover_profile_a if side == 0 else edge.cover_profile_b
		var candidate := resolved_settings.resolve_profile(authored_profile, legacy_level)
		if candidate == null or not candidate.is_valid():
			candidate = TacticalCoverProfile.default_for_level(legacy_level)
		if _is_better_candidate(candidate, edge, best_profile, best_edge):
			best_edge = edge
			best_profile = candidate
			best_side = side

	if best_edge == null or best_profile == null:
		result.reason = &"no_cover"
		return result
	result.source_edge = best_edge
	result.source_edge_key = best_edge.key_string()
	result.target_side = &"a" if best_side == 0 else &"b"
	result.profile = best_profile
	result.cover_level = best_profile.cover_level
	result.cover_profile_id = best_profile.cover_id
	result.reduction_ratio = clampf(best_profile.damage_reduction_ratio, 0.0, 1.0)
	result.damage_reduction_ratio = result.reduction_ratio
	result.has_cover = result.cover_level > 0 and result.reduction_ratio > 0.0 and result.source_edge != null
	result.reason = &"cover" if result.cover_level > 0 else &"no_cover"
	return result


static func get_cover(
	attacker_cell: Vector3i,
	target_cell: Vector3i,
	grid: GridModel,
	edge_index: TacticalEdgeIndex = null,
	settings: CoverCombatSettings = null,
	opaque_cells: Dictionary = {}
) -> CoverQueryResult:
	return query(attacker_cell, target_cell, grid, edge_index, settings, opaque_cells)


static func _is_better_candidate(
	candidate: TacticalCoverProfile,
	edge: MapEdgeData,
	current: TacticalCoverProfile,
	current_edge: MapEdgeData
) -> bool:
	if current == null or current_edge == null:
		return true
	var candidate_ratio := clampf(candidate.damage_reduction_ratio, 0.0, 1.0)
	var current_ratio := clampf(current.damage_reduction_ratio, 0.0, 1.0)
	if not is_equal_approx(candidate_ratio, current_ratio):
		return candidate_ratio > current_ratio
	if candidate.cover_level != current.cover_level:
		return candidate.cover_level > current.cover_level
	return edge.key_string() < current_edge.key_string()
