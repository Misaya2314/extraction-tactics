class_name TacticalLineQuery
extends RefCounted

const GridVisibilityScript = preload("res://scripts/core/perception/grid_visibility.gd")

## Authoritative same-level attack trace.  The cell sequence comes directly
## from GridVisibility.line_cells(), so corner/supercover behavior cannot
## diverge between perception and combat.
static func query(
	attacker_cell: Vector3i,
	target_cell: Vector3i,
	grid: GridModel,
	edge_index: TacticalEdgeIndex = null,
	opaque_cells: Dictionary = {}
) -> TacticalLineQueryResult:
	var result := TacticalLineQueryResult.new()
	result.attacker_cell = attacker_cell
	result.target_cell = target_cell
	result.cross_level = attacker_cell.y != target_cell.y
	if grid == null or not grid.is_initialized():
		result.reason = &"invalid_grid"
		return result
	if not grid.has_cell(attacker_cell) or not grid.has_cell(target_cell):
		result.reason = &"invalid_cell"
		return result

	result.valid = true
	result.cells_crossed = GridVisibilityScript.line_cells(attacker_cell, target_cell)
	if result.cells_crossed.is_empty():
		result.cells_crossed = [attacker_cell, target_cell] if attacker_cell != target_cell else [attacker_cell]
	var resolved_index := edge_index
	if resolved_index == null:
		resolved_index = grid.get_edge_index()

	# The first/last cell are visible targets by the existing LOS contract;
	# only intermediate cells can block.  Edge blocks are evaluated separately.
	for index in range(1, result.cells_crossed.size() - 1):
		var cell := result.cells_crossed[index]
		var cell_blocks_sight := opaque_cells.has(cell) or grid.cell_blocks_los(cell)
		var cell_blocks_projectile := grid.cell_blocks_projectile(cell)
		if cell_blocks_sight:
			result.los_blocked = true
			if result.sight_blocking_cell == Vector3i(-1, -1, -1):
				result.sight_blocking_cell = cell
			if result.blocking_cell == Vector3i(-1, -1, -1):
				result.blocking_cell = cell
		if cell_blocks_projectile:
			result.projectile_blocked = true
			if result.projectile_blocking_cell == Vector3i(-1, -1, -1):
				result.projectile_blocking_cell = cell
			if result.blocking_cell == Vector3i(-1, -1, -1):
				result.blocking_cell = cell
		if result.sight_blocking_cell != Vector3i(-1, -1, -1) and result.projectile_blocking_cell != Vector3i(-1, -1, -1):
			break

	if resolved_index != null:
		_collect_crossed_edges(result, resolved_index)
		_collect_target_incoming_edges(result, resolved_index)
		result.edges_crossed.sort_custom(func(a: MapEdgeData, b: MapEdgeData) -> bool:
			return a.key_string() < b.key_string()
		)
		_check_edge_blocks(result)

	if result.los_blocked:
		result.reason = &"sight_blocked"
	elif result.projectile_blocked:
		result.reason = &"projectile_blocked"
	elif result.cross_level:
		result.reason = &"unsupported_height_relation"
	else:
		result.reason = &"clear"
	return result


static func trace(
	attacker_cell: Vector3i,
	target_cell: Vector3i,
	grid: GridModel,
	edge_index: TacticalEdgeIndex = null,
	opaque_cells: Dictionary = {}
) -> TacticalLineQueryResult:
	return query(attacker_cell, target_cell, grid, edge_index, opaque_cells)


static func _collect_crossed_edges(result: TacticalLineQueryResult, index: TacticalEdgeIndex) -> void:
	# GridVisibility emits both corner cells and the diagonal cell. Looking at
	# only adjacent array entries would miss the other branch (for example
	# corner_x -> diagonal and start -> corner_y). Consider the small local
	# neighborhood around every emitted cell and retain only cardinal pairs.
	for first_index in range(result.cells_crossed.size()):
		var last_index := mini(first_index + 2, result.cells_crossed.size() - 1)
		for second_index in range(first_index + 1, last_index + 1):
			var first := result.cells_crossed[first_index]
			var second := result.cells_crossed[second_index]
			if first.y != second.y or absi(first.x - second.x) + absi(first.z - second.z) != 1:
				continue
			_append_edge(result.edges_crossed, index.get_edge(first, second))


static func _collect_target_incoming_edges(result: TacticalLineQueryResult, index: TacticalEdgeIndex) -> void:
	if result.cells_crossed.size() <= 1:
		return
	var candidates: Array[MapEdgeData] = []
	for cursor in range(result.cells_crossed.size() - 1):
		var candidate := result.cells_crossed[cursor]
		if candidate.y != result.target_cell.y:
			continue
		if absi(candidate.x - result.target_cell.x) + absi(candidate.z - result.target_cell.z) != 1:
			continue
		_append_edge(candidates, index.get_edge(candidate, result.target_cell))
	candidates.sort_custom(func(a: MapEdgeData, b: MapEdgeData) -> bool:
		return a.key_string() < b.key_string()
	)
	for edge in candidates:
		_append_edge(result.target_incoming_edges, edge)
		_append_edge(result.edges_crossed, edge)
	result.edges_crossed.sort_custom(func(a: MapEdgeData, b: MapEdgeData) -> bool:
		return a.key_string() < b.key_string()
	)


static func _check_edge_blocks(result: TacticalLineQueryResult) -> void:
	for edge in result.edges_crossed:
		if edge == null:
			continue
		if edge.sight_block >= 1.0:
			result.los_blocked = true
			if result.sight_blocking_edge == null or edge.key_string() < result.sight_blocking_edge.key_string():
				result.sight_blocking_edge = edge
				result.sight_blocking_edge_key = edge.key_string()
		if edge.projectile_block >= 1.0:
			result.projectile_blocked = true
			if result.projectile_blocking_edge == null or edge.key_string() < result.projectile_blocking_edge.key_string():
				result.projectile_blocking_edge = edge
				result.projectile_blocking_edge_key = edge.key_string()

	# Keep the old aggregate deterministic while retaining the channel-specific
	# sources above.  The aggregate edge is the canonical minimum of both sets.
	if result.sight_blocking_edge != null:
		result.blocking_edge = result.sight_blocking_edge
		result.blocking_edge_key = result.sight_blocking_edge_key
	if result.projectile_blocking_edge != null and (result.blocking_edge == null or result.projectile_blocking_edge_key < result.blocking_edge_key):
		result.blocking_edge = result.projectile_blocking_edge
		result.blocking_edge_key = result.projectile_blocking_edge_key


static func _append_edge(edges: Array[MapEdgeData], edge: MapEdgeData) -> void:
	if edge == null:
		return
	for existing in edges:
		if existing.key_string() == edge.key_string():
			return
	edges.append(edge)
