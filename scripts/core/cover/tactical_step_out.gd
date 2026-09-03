class_name TacticalStepOut
extends RefCounted

const TacticalLineQueryScript = preload("res://scripts/core/cover/tactical_line_query.gd")
const CoverQueryScript = preload("res://scripts/core/cover/cover_query.gd")
const CoverQueryResultScript = preload("res://scripts/core/cover/cover_query_result.gd")
const TacticalEdgeRulesScript = preload("res://scripts/core/map/tactical_edge_rules.gd")

const CARDINAL_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1)
]


## Checks whether the unit cell is hugging full cover or a wall.
## This requires at least one adjacent cardinal edge to provide full cover / solid obstruction,
## or an adjacent cardinal cell to be an obstacle/opaque wall.
static func is_hugging_full_cover(
	cell: Vector3i,
	grid: GridModel,
	edge_index: TacticalEdgeIndex = null,
	opaque_cells: Dictionary = {}
) -> bool:
	if grid == null or not grid.is_initialized():
		return false
	var index := edge_index if edge_index != null else grid.get_edge_index()
	for offset in CARDINAL_OFFSETS:
		var neighbor := cell + offset
		if index != null:
			var edge := index.get_edge(cell, neighbor)
			if edge != null:
				if edge.cover_a >= TacticalEdgeRulesScript.CoverLevel.FULL or edge.cover_b >= TacticalEdgeRulesScript.CoverLevel.FULL:
					return true
				if (edge.cover_profile_a != null and edge.cover_profile_a.cover_level >= 2) or (edge.cover_profile_b != null and edge.cover_profile_b.cover_level >= 2):
					return true
				if edge.sight_block >= 1.0 or edge.projectile_block >= 1.0 or edge.blocks_movement:
					return true
		if opaque_cells.has(neighbor):
			return true
		if grid.has_cell(neighbor) and (grid.cell_blocks_los(neighbor) or grid.cell_blocks_projectile(neighbor) or not grid.is_walkable(neighbor)):
			return true
	return false


## Searches for an optimal adjacent step-out cell when the direct shot is blocked.
## Returns a CoverQueryResult evaluated from the chosen step-out cell with `is_step_out = true`,
## or null if no valid step-out position is available.
static func find_step_out(
	attacker_cell: Vector3i,
	target_cell: Vector3i,
	attack_range: int,
	grid: GridModel,
	edge_index: TacticalEdgeIndex = null,
	settings: CoverCombatSettings = null,
	opaque_cells: Dictionary = {}
) -> CoverQueryResult:
	if grid == null or not grid.is_initialized():
		return null
	if not grid.has_cell(attacker_cell) or not grid.has_cell(target_cell):
		return null

	var index := edge_index if edge_index != null else grid.get_edge_index()

	# Unit must be hugging full cover or a wall to be eligible for step-out
	if not is_hugging_full_cover(attacker_cell, grid, index, opaque_cells):
		return null

	var candidates: Array[Dictionary] = []

	for offset in CARDINAL_OFFSETS:
		var candidate_cell := attacker_cell + offset

		# Candidate must be a valid, same-elevation floor cell
		if candidate_cell.y != attacker_cell.y:
			continue
		if not grid.has_cell(candidate_cell):
			continue
		if not grid.is_walkable(candidate_cell) or grid.cell_blocks_los(candidate_cell):
			continue
		if opaque_cells.has(candidate_cell):
			continue

		# Candidate cell must be unoccupied (free tile)
		if grid.is_occupied(candidate_cell):
			continue

		# The path from attacker_cell to candidate_cell must be unblocked
		if index != null:
			var step_edge := index.get_edge(attacker_cell, candidate_cell)
			if step_edge != null:
				if step_edge.blocks_movement or step_edge.sight_block >= 1.0 or step_edge.projectile_block >= 1.0:
					continue

		# Range check: target must be within attack_range from the candidate cell (and attacker cell)
		if attack_range >= 0:
			var dist_from_step := _manhattan(candidate_cell, target_cell)
			var dist_from_attacker := _manhattan(attacker_cell, target_cell)
			if dist_from_step > attack_range or dist_from_attacker > attack_range:
				continue

		# Line of Sight / Cover check from candidate_cell to target_cell
		var query := CoverQueryScript.query(
			candidate_cell,
			target_cell,
			grid,
			index,
			settings,
			opaque_cells
		)
		if query != null and query.can_attack():
			candidates.append({
				&"cell": candidate_cell,
				&"query": query,
				&"reduction_ratio": query.damage_reduction_ratio,
				&"distance": _manhattan(candidate_cell, target_cell),
			})

	if candidates.is_empty():
		return null

	# Sort candidates:
	# 1. Lower damage reduction ratio on target (flanking / clearer shot)
	# 2. Shorter distance to target
	# 3. Deterministic coordinate order
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a[&"reduction_ratio"], b[&"reduction_ratio"]):
			return a[&"reduction_ratio"] < b[&"reduction_ratio"]
		if a[&"distance"] != b[&"distance"]:
			return a[&"distance"] < b[&"distance"]
		var ca: Vector3i = a[&"cell"]
		var cb: Vector3i = b[&"cell"]
		if ca.x != cb.x:
			return ca.x < cb.x
		return ca.z < cb.z
	)

	var chosen: Dictionary = candidates[0]
	var chosen_query: CoverQueryResult = chosen[&"query"]
	chosen_query.is_step_out = true
	chosen_query.step_out_cell = chosen[&"cell"]
	chosen_query.original_attacker_cell = attacker_cell

	return chosen_query


static func _manhattan(a: Vector3i, b: Vector3i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z)
