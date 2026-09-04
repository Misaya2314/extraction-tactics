class_name EnemyTacticalAI
extends RefCounted

const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")
const AlertStateScript = preload("res://scripts/core/encounter/alert_state.gd")
const PatrolRouteScript = preload("res://scripts/core/encounter/patrol_route.gd")

enum IntentType {
	NONE,
	PASS,
	MOVE,
	ATTACK,
	PATROL_STEP,
	INVESTIGATE_STEP,
	CALM_DOWN,
}


## Calculates a path towards a target cell, intelligently handling cases where
## the goal cell itself is occupied (e.g. by a player or obstacle).
static func find_path_towards(start_cell: Vector3i, target_cell: Vector3i, grid: GridModel) -> Array[Vector3i]:
	if not is_instance_valid(grid) or start_cell == target_cell:
		return [start_cell]

	# If target_cell is walkable and free, find direct path
	if grid.is_walkable(target_cell) and not grid.is_occupied(target_cell):
		var direct_path := grid.find_path(start_cell, target_cell)
		if not direct_path.is_empty():
			return direct_path

	# If target_cell is occupied or blocked, find best unoccupied standable neighbor
	var best_neighbor := grid.invalid_cell()
	var best_dist := INF
	for neighbor in grid.get_neighbors(target_cell):
		if grid.is_walkable(neighbor) and not grid.is_occupied(neighbor):
			var dist := manhattan_distance(start_cell, neighbor)
			if dist < best_dist:
				best_dist = dist
				best_neighbor = neighbor

	if best_neighbor != grid.invalid_cell():
		var neighbor_path := grid.find_path(start_cell, best_neighbor)
		if not neighbor_path.is_empty():
			return neighbor_path

	# Fallback: step from start_cell towards target_cell
	var best_step := start_cell
	var best_step_dist := manhattan_distance(start_cell, target_cell)
	for neighbor in grid.get_neighbors(start_cell):
		if grid.is_walkable(neighbor) and not grid.is_occupied(neighbor):
			var dist := manhattan_distance(neighbor, target_cell)
			if dist < best_step_dist:
				best_step_dist = dist
				best_step = neighbor
	if best_step != start_cell:
		return [start_cell, best_step]
	return []


## Evaluates and returns the best reachable combat movement destination for an enemy.
## If can_attack_from_cell_fn is provided (func(cell: Vector3i, target_cell: Vector3i) -> bool),
## prioritizes valid firing positions that minimize move distance.
static func find_best_combat_move_cell(
	origin: Vector3i,
	target_cell: Vector3i,
	move_range: int,
	grid: GridModel,
	can_attack_from_cell_fn: Callable = Callable()
) -> Vector3i:
	if not is_instance_valid(grid) or move_range <= 0:
		return origin

	var reachable := grid.get_reachable_cells(origin, move_range)
	if reachable.is_empty():
		return origin

	# If attack check is supplied, look for valid attack positions
	if can_attack_from_cell_fn.is_valid():
		var best_attack_cell := grid.invalid_cell()
		var best_attack_dist_from_origin := INF
		var best_attack_target_dist := INF
		for cell in reachable:
			if cell == origin:
				continue
			if can_attack_from_cell_fn.call(cell, target_cell):
				var dist_origin := manhattan_distance(origin, cell)
				var dist_target := manhattan_distance(cell, target_cell)
				if dist_origin < best_attack_dist_from_origin or (
					dist_origin == best_attack_dist_from_origin and dist_target < best_attack_target_dist
				):
					best_attack_dist_from_origin = dist_origin
					best_attack_target_dist = dist_target
					best_attack_cell = cell
		if best_attack_cell != grid.invalid_cell():
			return best_attack_cell

	# Fallback: find reachable cell minimizing distance to target
	var best_cell := origin
	var best_distance := manhattan_distance(origin, target_cell)
	for cell in reachable:
		if cell == origin:
			continue
		var distance := manhattan_distance(cell, target_cell)
		if distance < best_distance:
			best_distance = distance
			best_cell = cell
		elif distance == best_distance and _cell_less(cell, best_cell):
			best_cell = cell
	return best_cell


## Plans a single exploration tick decision for an enemy unit.
## Returns a Dictionary with:
## - intent: IntentType (INVESTIGATE_STEP, PATROL_STEP, CALM_DOWN, PASS)
## - destination: Vector3i
## - path: Array[Vector3i]
## - should_calm_down: bool
## - updated_investigation: Dictionary
static func plan_exploration_step(
	enemy_cell: Vector3i,
	alert_or_facing: Variant,
	patrol_or_alert: Variant = null,
	investigation_or_route: Variant = null,
	grid_or_investigation: Variant = null,
	move_range_or_grid: Variant = null,
	legacy_move_range: Variant = null
) -> Dictionary:
	var alert: AlertState = null
	var patrol_route: PatrolRoute = null
	var investigation_data: Dictionary = {}
	var grid: GridModel = null
	var move_range: int = 1

	if alert_or_facing is Vector2i:
		# Legacy signature: (enemy_cell, enemy_facing, alert, patrol_route, investigation_data, grid, move_range)
		alert = patrol_or_alert as AlertState
		patrol_route = investigation_or_route as PatrolRoute
		if grid_or_investigation is Dictionary:
			investigation_data = grid_or_investigation
		grid = move_range_or_grid as GridModel
		if legacy_move_range is int:
			move_range = legacy_move_range
	else:
		# Standard signature: (enemy_cell, alert, patrol_route, investigation_data, grid, move_range)
		alert = alert_or_facing as AlertState
		patrol_route = patrol_or_alert as PatrolRoute
		if investigation_or_route is Dictionary:
			investigation_data = investigation_or_route
		grid = grid_or_investigation as GridModel
		if move_range_or_grid is int:
			move_range = move_range_or_grid

	var result := {
		&"intent": IntentType.PASS,
		&"destination": enemy_cell,
		&"path": [] as Array[Vector3i],
		&"should_calm_down": false,
		&"updated_investigation": investigation_data.duplicate(),
		&"dwell": false,
		&"waypoint": Vector3i(-1, -1, -1),
	}

	# 1. Suspicious investigation takes priority
	if alert != null and alert.is_suspicious():
		var target_cell := alert.get_last_known_cell()
		if target_cell != AlertState.INVALID_CELL and grid != null:
			var full_path := find_path_towards(enemy_cell, target_cell, grid)
			if full_path.size() >= 2:
				var max_steps := mini(maxi(move_range, 1), full_path.size() - 1)
				var sub_path: Array[Vector3i] = []
				for i in range(max_steps + 1):
					sub_path.append(full_path[i])
				var destination: Vector3i = sub_path.back()
				result[&"intent"] = IntentType.INVESTIGATE_STEP
				result[&"destination"] = destination
				result[&"path"] = sub_path
				return result
			else:
				# Cannot get closer or already at target
				var idle_ticks: int = int(investigation_data.get(&"idle_ticks", 0)) + 1
				result[&"updated_investigation"][&"idle_ticks"] = idle_ticks
				if idle_ticks >= 2:
					result[&"intent"] = IntentType.CALM_DOWN
					result[&"should_calm_down"] = true
					# Re-anchor to the nearest patrol waypoint so the guard
					# seamlessly rejoins its loop after a fruitless search.
					if patrol_route != null:
						patrol_route.set_nearest_waypoint(enemy_cell)
					return result
				result[&"intent"] = IntentType.PASS
				return result

	# 2. Sparse waypoint patrol step.  The route only stores key turning
	#    points; pathfinding fills the cells between them.  `current()` is the
	#    waypoint the unit is anchored to: it pathfinds toward it, and on
	#    arrival consumes the waypoint's dwell ticks before advancing.
	if patrol_route != null and grid != null:
		var target_waypoint := patrol_route.current()
		if target_waypoint == enemy_cell:
			# Arrived at the anchored waypoint.
			if patrol_route.dwell_remaining() > 0:
				patrol_route.spend_dwell_tick()
				result[&"intent"] = IntentType.PASS
				result[&"dwell"] = true
				return result
			patrol_route.advance()
			target_waypoint = patrol_route.current()
			if target_waypoint == enemy_cell:
				# Single-waypoint route: nothing left to walk to.
				return result
		var full_path := find_path_towards(enemy_cell, target_waypoint, grid)
		if full_path.size() < 2:
			# Waypoint unreachable (e.g. blocked by a dynamic obstacle).
			# Skip it and retry with the next waypoint on a later tick.
			patrol_route.advance()
			return result
		var max_steps := mini(maxi(move_range, 1), full_path.size() - 1)
		var sub_path: Array[Vector3i] = []
		for i in range(max_steps + 1):
			sub_path.append(full_path[i])
		var destination: Vector3i = sub_path.back()
		result[&"intent"] = IntentType.PATROL_STEP
		result[&"destination"] = destination
		result[&"path"] = sub_path
		result[&"waypoint"] = target_waypoint
		return result

	return result


## Plans a single combat action for an enemy unit during its turn.
## Returns a Dictionary with:
## - intent: IntentType (ATTACK, MOVE, PASS)
## - target_id: StringName (if ATTACK)
## - target_cell: Vector3i (if ATTACK)
## - destination: Vector3i (if MOVE)
## - path: Array[Vector3i] (if MOVE)
## - ap_cost: int
##
## living_targets is an Array of Dictionaries or objects exposing:
##   - id: StringName
##   - cell: Vector3i
##   - alive: bool
static func plan_combat_action(
	enemy_cell: Vector3i,
	enemy_ap: int,
	attack_damage: int,
	attack_range: int,
	attack_ap_cost: int,
	move_range: int,
	move_ap_cost: int,
	living_targets: Array,
	grid: GridModel,
	can_attack_checker: Callable
) -> Dictionary:
	var result := {
		&"intent": IntentType.PASS,
		&"target_id": &"",
		&"target_cell": Vector3i(-1, -1, -1),
		&"destination": enemy_cell,
		&"path": [] as Array[Vector3i],
		&"ap_cost": 0,
	}

	if enemy_ap <= 0 or living_targets.is_empty() or not is_instance_valid(grid):
		return result

	# 1. Select the primary target (nearest living player)
	var best_target_idx := -1
	var best_dist := INF
	for idx in range(living_targets.size()):
		var target = living_targets[idx]
		var target_cell: Vector3i = target[&"cell"] if target is Dictionary else target.grid_cell
		var dist := manhattan_distance(enemy_cell, target_cell)
		if dist < best_dist:
			best_dist = dist
			best_target_idx = idx

	if best_target_idx < 0:
		return result

	var primary_target = living_targets[best_target_idx]
	var primary_id: StringName = primary_target[&"id"] if primary_target is Dictionary else primary_target.unit_id
	var primary_cell: Vector3i = primary_target[&"cell"] if primary_target is Dictionary else primary_target.grid_cell

	# 2. Check if enemy can attack primary target from current cell
	if enemy_ap >= attack_ap_cost and attack_damage > 0 and attack_range > 0:
		if can_attack_checker.is_valid() and can_attack_checker.call(enemy_cell, primary_cell, attack_range):
			result[&"intent"] = IntentType.ATTACK
			result[&"target_id"] = primary_id
			result[&"target_cell"] = primary_cell
			result[&"ap_cost"] = attack_ap_cost
			return result

	# 3. If cannot attack, check if enemy can move closer
	if enemy_ap >= move_ap_cost and move_range > 0:
		var best_destination := find_best_combat_move_cell(
			enemy_cell, primary_cell, move_range, grid
		)
		if best_destination != enemy_cell:
			var path := grid.find_path(enemy_cell, best_destination)
			if path.size() >= 2:
				result[&"intent"] = IntentType.MOVE
				result[&"destination"] = best_destination
				result[&"path"] = path
				result[&"ap_cost"] = move_ap_cost
				return result

	return result


static func manhattan_distance(a: Vector3i, b: Vector3i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z)


static func _cell_less(a: Vector3i, b: Vector3i) -> bool:
	return a.y < b.y or (a.y == b.y and (a.z < b.z or (a.z == b.z and a.x < b.x)))
