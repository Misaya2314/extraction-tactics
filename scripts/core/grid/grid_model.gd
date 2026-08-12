class_name GridModel
extends RefCounted

## Runtime logical grid for standable 3D tactical surfaces.
##
## A cell is Vector3i(x, level, z). Horizontal neighbors are inferred only on
## the same level. Stairs, ramps, ladders and drops are explicit transitions,
## so sharing X/Z never permits a unit to move vertically through a floor.

const DEFAULT_CELL_SIZE: float = 2.0
const DEFAULT_LEVEL_HEIGHT: float = 2.0
const CARDINAL_DIRECTIONS: Array[Vector3i] = [
	Vector3i(0, 0, -1),
	Vector3i(1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(-1, 0, 0),
]

var _grid_size: Vector2i = Vector2i.ZERO
var _level_count: int = 0
var _cell_size: Vector3 = Vector3(DEFAULT_CELL_SIZE, DEFAULT_LEVEL_HEIGHT, DEFAULT_CELL_SIZE)
var _origin: Vector3 = Vector3.ZERO
var _cells: Dictionary = {}
var _transitions: Dictionary = {}
var _occupants: Dictionary = {}
var _initialized: bool = false


func _init(initial_size: Vector2i = Vector2i.ZERO, initial_cell_size: float = DEFAULT_CELL_SIZE, initial_origin: Vector3 = Vector3.ZERO) -> void:
	if initial_size != Vector2i.ZERO:
		initialize(initial_size, initial_cell_size, initial_origin)


## Backwards-compatible flat-map constructor. Every generated cell is level 0.
func configure(grid_size: Vector2i, cell_size: float = DEFAULT_CELL_SIZE, origin: Vector3 = Vector3.ZERO) -> void:
	initialize(grid_size, cell_size, origin)


func initialize(grid_size: Vector2i, cell_size: float = DEFAULT_CELL_SIZE, origin: Vector3 = Vector3.ZERO) -> bool:
	if grid_size.x <= 0 or grid_size.y <= 0:
		return false
	if not _valid_dimension(cell_size):
		return false

	_reset(grid_size, 1, Vector3(cell_size, DEFAULT_LEVEL_HEIGHT, cell_size), origin)
	for z in range(grid_size.y):
		for x in range(grid_size.x):
			add_cell(Vector3i(x, 0, z), true, 1)
	_initialized = true
	return true


## Loads sparse surfaces and explicit vertical connections from baked map data.
func configure_from_definition(definition: TacticalMapDefinition) -> bool:
	if definition == null or definition.schema_version != TacticalMapDefinition.CURRENT_SCHEMA_VERSION:
		return false
	if definition.footprint_size.x <= 0 or definition.footprint_size.y <= 0:
		return false
	if not _valid_cell_size(definition.cell_size) or definition.level_count <= 0:
		return false

	_reset(definition.footprint_size, definition.level_count, definition.cell_size, definition.origin)
	for cell_data in definition.cells:
		if cell_data == null or not _coordinate_in_volume(cell_data.coordinate):
			continue
		add_cell(cell_data.coordinate, cell_data.walkable, cell_data.move_cost)
	for transition in definition.transitions:
		if transition == null or not transition.enabled:
			continue
		add_transition(
			transition.from_cell,
			transition.to_cell,
			transition.move_cost,
			transition.bidirectional
		)
	_initialized = not _cells.is_empty()
	return _initialized


func _reset(grid_size: Vector2i, level_count: int, cell_size: Vector3, origin: Vector3) -> void:
	_grid_size = grid_size
	_level_count = level_count
	_cell_size = cell_size
	_origin = origin
	_cells.clear()
	_transitions.clear()
	_occupants.clear()
	_initialized = false


func is_initialized() -> bool:
	return _initialized


func get_grid_size() -> Vector2i:
	return _grid_size


func get_level_count() -> int:
	return _level_count


var grid_size: Vector2i:
	get:
		return _grid_size


## Horizontal size retained for flat-map integrations.
var cell_size: float:
	get:
		return _cell_size.x


var cell_dimensions: Vector3:
	get:
		return _cell_size


var origin: Vector3:
	get:
		return _origin


func cell_to_world(cell: Variant) -> Vector3:
	var coordinate := _as_cell3(cell)
	# `origin` is the GridMap corner for logical cell (0, 0, 0). Godot's
	# GridMap.map_to_local() returns the centre of a cell, so every axis needs
	# the same half-cell offset (including the vertical level axis).
	return _origin + Vector3(
		(float(coordinate.x) + 0.5) * _cell_size.x,
		(float(coordinate.y) + 0.5) * _cell_size.y,
		(float(coordinate.z) + 0.5) * _cell_size.z
	)


func world_to_cell(world_position: Vector3) -> Vector3i:
	if not _valid_cell_size(_cell_size):
		return Vector3i.ZERO
	var local := world_position - _origin
	# GridMap.local_to_map() selects the containing cell from the corner-based
	# local coordinate. This is the inverse of cell_to_world(), not nearest-cell
	# rounding around the old corner coordinates.
	return Vector3i(
		int(floor(local.x / _cell_size.x)),
		int(floor(local.y / _cell_size.y)),
		int(floor(local.z / _cell_size.z))
	)


## Finds the existing surface nearest a world point. Useful after a physics-ray hit.
func world_to_existing_cell(world_position: Vector3, vertical_tolerance: float = -1.0) -> Vector3i:
	var estimated := world_to_cell(world_position)
	if has_cell(estimated):
		return estimated
	var best := invalid_cell()
	var best_distance := INF
	var tolerance := vertical_tolerance
	if tolerance < 0.0:
		tolerance = _cell_size.y * 0.55
	for cell_variant in _cells.keys():
		var cell: Vector3i = cell_variant
		var center := cell_to_world(cell)
		if absf(center.y - world_position.y) > tolerance:
			continue
		var horizontal_distance := Vector2(center.x, center.z).distance_squared_to(Vector2(world_position.x, world_position.z))
		if horizontal_distance < best_distance:
			best_distance = horizontal_distance
			best = cell
	return best


func add_cell(cell: Vector3i, walkable: bool = true, move_cost: int = 1) -> bool:
	if not _coordinate_in_volume(cell) or move_cost <= 0:
		return false
	_cells[cell] = {
		&"walkable": walkable,
		&"move_cost": move_cost,
	}
	return true


func has_cell(cell: Variant) -> bool:
	return _cells.has(_as_cell3(cell))


func is_in_bounds(cell: Variant) -> bool:
	return _initialized and has_cell(cell)


func in_bounds(cell: Variant) -> bool:
	return is_in_bounds(cell)


func set_walkable(cell: Variant, walkable: bool) -> bool:
	var coordinate := _as_cell3(cell)
	if not has_cell(coordinate):
		return false
	if not walkable and _occupants.has(coordinate):
		return false
	var data: Dictionary = _cells[coordinate]
	data[&"walkable"] = walkable
	_cells[coordinate] = data
	return true


func set_move_cost(cell: Variant, move_cost: int) -> bool:
	var coordinate := _as_cell3(cell)
	if not has_cell(coordinate) or move_cost <= 0:
		return false
	var data: Dictionary = _cells[coordinate]
	data[&"move_cost"] = move_cost
	_cells[coordinate] = data
	return true


func get_move_cost(cell: Variant) -> int:
	var coordinate := _as_cell3(cell)
	if not has_cell(coordinate):
		return -1
	return int((_cells[coordinate] as Dictionary).get(&"move_cost", 1))


func is_walkable(cell: Variant) -> bool:
	var coordinate := _as_cell3(cell)
	return has_cell(coordinate) and bool((_cells[coordinate] as Dictionary).get(&"walkable", false))


## Returns same-level horizontal neighbors plus explicit transitions.
func get_neighbors(cell: Variant) -> Array[Vector3i]:
	var coordinate := _as_cell3(cell)
	var neighbors: Array[Vector3i] = []
	if not is_in_bounds(coordinate):
		return neighbors
	for direction in CARDINAL_DIRECTIONS:
		var neighbor := coordinate + direction
		if has_cell(neighbor):
			neighbors.append(neighbor)
	for edge_value in _transitions.get(coordinate, []):
		var edge: Dictionary = edge_value
		var target: Vector3i = edge[&"to"]
		if has_cell(target) and not neighbors.has(target):
			neighbors.append(target)
	return neighbors


func get_walkable_neighbors(cell: Variant) -> Array[Vector3i]:
	var neighbors: Array[Vector3i] = []
	for neighbor in get_neighbors(cell):
		if is_walkable(neighbor):
			neighbors.append(neighbor)
	return neighbors


func add_transition(from_cell: Vector3i, to_cell: Vector3i, move_cost: int = 1, bidirectional: bool = true) -> bool:
	if from_cell == to_cell or move_cost <= 0 or not has_cell(from_cell) or not has_cell(to_cell):
		return false
	_set_directed_transition(from_cell, to_cell, move_cost)
	if bidirectional:
		_set_directed_transition(to_cell, from_cell, move_cost)
	return true


func set_transition_enabled(from_cell: Vector3i, to_cell: Vector3i, enabled: bool, bidirectional: bool = true) -> bool:
	if enabled:
		return add_transition(from_cell, to_cell, 1, bidirectional)
	var changed := _remove_directed_transition(from_cell, to_cell)
	if bidirectional:
		changed = _remove_directed_transition(to_cell, from_cell) or changed
	return changed


func get_edge_cost(from_cell: Vector3i, to_cell: Vector3i) -> int:
	if from_cell.y == to_cell.y and _is_horizontal_neighbor(from_cell, to_cell):
		return get_move_cost(to_cell)
	for edge_value in _transitions.get(from_cell, []):
		var edge: Dictionary = edge_value
		if edge[&"to"] == to_cell:
			return int(edge[&"cost"])
	return -1


func occupy(cell: Variant, occupant_id: StringName) -> bool:
	var coordinate := _as_cell3(cell)
	if occupant_id == &"" or not is_walkable(coordinate):
		return false
	if _occupants.has(coordinate):
		return _occupants[coordinate] == occupant_id
	if _contains_occupant(occupant_id):
		return false
	_occupants[coordinate] = occupant_id
	return true


func occupy_cell(cell: Variant, occupant_id: StringName) -> bool:
	return occupy(cell, occupant_id)


func vacate(cell: Variant, occupant_id: StringName = &"") -> bool:
	var coordinate := _as_cell3(cell)
	if not is_in_bounds(coordinate) or not _occupants.has(coordinate):
		return false
	if occupant_id != &"" and _occupants[coordinate] != occupant_id:
		return false
	_occupants.erase(coordinate)
	return true


func release(cell: Variant, expected_occupant: StringName = &"") -> bool:
	return vacate(cell, expected_occupant)


func release_cell(cell: Variant, expected_occupant: StringName = &"") -> bool:
	return vacate(cell, expected_occupant)


func release_occupant(occupant_id: StringName) -> bool:
	if occupant_id == &"":
		return false
	for cell_variant in _occupants.keys():
		if _occupants[cell_variant] == occupant_id:
			return vacate(cell_variant, occupant_id)
	return false


func is_occupied(cell: Variant) -> bool:
	var coordinate := _as_cell3(cell)
	return is_in_bounds(coordinate) and _occupants.has(coordinate)


func get_occupant(cell: Variant) -> StringName:
	var coordinate := _as_cell3(cell)
	if not is_in_bounds(coordinate):
		return &""
	return _occupants.get(coordinate, &"")


func query_occupant(cell: Variant) -> StringName:
	return get_occupant(cell)


## Dijkstra pathfinding: cell and transition costs are movement-point costs.
func find_path(start: Variant, goal: Variant) -> Array[Vector3i]:
	return _find_path(_as_cell3(start), _as_cell3(goal), -1)


func find_path_limited(start: Variant, goal: Variant, max_cost: int) -> Array[Vector3i]:
	return _find_path(_as_cell3(start), _as_cell3(goal), max_cost)


func get_path_cost(path: Array[Vector3i]) -> int:
	if path.is_empty():
		return -1
	var total := 0
	for index in range(1, path.size()):
		var edge_cost := get_edge_cost(path[index - 1], path[index])
		if edge_cost <= 0:
			return -1
		total += edge_cost
	return total


func get_reachable_cells(start: Variant, movement_points: int) -> Array[Vector3i]:
	var coordinate := _as_cell3(start)
	var reachable: Array[Vector3i] = []
	if not is_walkable(coordinate) or movement_points < 0:
		return reachable
	var costs := _calculate_costs(coordinate, movement_points)
	var ordered: Array = costs.keys()
	ordered.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		var cost_a: int = costs[a]
		var cost_b: int = costs[b]
		return cost_a < cost_b or (cost_a == cost_b and _cell_less(a, b))
	)
	for cell_variant in ordered:
		reachable.append(cell_variant)
	return reachable


func get_reachable(start: Variant, movement_points: int) -> Array[Vector3i]:
	return get_reachable_cells(start, movement_points)


func invalid_cell() -> Vector3i:
	return Vector3i(-1, -1, -1)


func _find_path(start: Vector3i, goal: Vector3i, max_cost: int) -> Array[Vector3i]:
	var empty: Array[Vector3i] = []
	if not is_walkable(start) or not is_walkable(goal) or is_occupied(goal):
		return empty
	if start == goal:
		return [start]
	if max_cost == 0:
		return empty

	var frontier: Array[Vector3i] = [start]
	var costs: Dictionary = {start: 0}
	var came_from: Dictionary = {}
	while not frontier.is_empty():
		var current := _pop_lowest_cost(frontier, costs)
		if current == goal:
			return _reconstruct_path(start, goal, came_from)
		for neighbor in get_neighbors(current):
			if not _can_enter_for_movement(neighbor, start):
				continue
			var edge_cost := get_edge_cost(current, neighbor)
			if edge_cost <= 0:
				continue
			var new_cost: int = int(costs[current]) + edge_cost
			if max_cost >= 0 and new_cost > max_cost:
				continue
			if costs.has(neighbor) and int(costs[neighbor]) <= new_cost:
				continue
			costs[neighbor] = new_cost
			came_from[neighbor] = current
			if not frontier.has(neighbor):
				frontier.append(neighbor)
	return empty


func _calculate_costs(start: Vector3i, max_cost: int) -> Dictionary:
	var frontier: Array[Vector3i] = [start]
	var costs: Dictionary = {start: 0}
	while not frontier.is_empty():
		var current := _pop_lowest_cost(frontier, costs)
		for neighbor in get_neighbors(current):
			if not _can_enter_for_movement(neighbor, start):
				continue
			var edge_cost := get_edge_cost(current, neighbor)
			if edge_cost <= 0:
				continue
			var new_cost: int = int(costs[current]) + edge_cost
			if new_cost > max_cost:
				continue
			if costs.has(neighbor) and int(costs[neighbor]) <= new_cost:
				continue
			costs[neighbor] = new_cost
			if not frontier.has(neighbor):
				frontier.append(neighbor)
	return costs


func _pop_lowest_cost(frontier: Array[Vector3i], costs: Dictionary) -> Vector3i:
	var best_index := 0
	for index in range(1, frontier.size()):
		var candidate := frontier[index]
		var best := frontier[best_index]
		if int(costs[candidate]) < int(costs[best]) or (
			int(costs[candidate]) == int(costs[best]) and _cell_less(candidate, best)
		):
			best_index = index
	return frontier.pop_at(best_index)


func _can_enter_for_movement(cell: Vector3i, start: Vector3i) -> bool:
	return is_walkable(cell) and (cell == start or not is_occupied(cell))


func _reconstruct_path(start: Vector3i, goal: Vector3i, came_from: Dictionary) -> Array[Vector3i]:
	var path: Array[Vector3i] = [goal]
	var cursor := goal
	while cursor != start:
		if not came_from.has(cursor):
			return []
		cursor = came_from[cursor]
		path.push_front(cursor)
	return path


func _set_directed_transition(from_cell: Vector3i, to_cell: Vector3i, move_cost: int) -> void:
	var edges: Array = _transitions.get(from_cell, [])
	for index in range(edges.size()):
		if (edges[index] as Dictionary)[&"to"] == to_cell:
			edges[index] = {&"to": to_cell, &"cost": move_cost}
			_transitions[from_cell] = edges
			return
	edges.append({&"to": to_cell, &"cost": move_cost})
	edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _cell_less(a[&"to"], b[&"to"]))
	_transitions[from_cell] = edges


func _remove_directed_transition(from_cell: Vector3i, to_cell: Vector3i) -> bool:
	if not _transitions.has(from_cell):
		return false
	var edges: Array = _transitions[from_cell]
	for index in range(edges.size()):
		if (edges[index] as Dictionary)[&"to"] == to_cell:
			edges.remove_at(index)
			if edges.is_empty():
				_transitions.erase(from_cell)
			else:
				_transitions[from_cell] = edges
			return true
	return false


func _is_horizontal_neighbor(a: Vector3i, b: Vector3i) -> bool:
	return a.y == b.y and absi(a.x - b.x) + absi(a.z - b.z) == 1


func _cell_less(a: Vector3i, b: Vector3i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	if a.z != b.z:
		return a.z < b.z
	return a.x < b.x


func _coordinate_in_volume(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.z >= 0 and cell.y >= 0 \
		and cell.x < _grid_size.x and cell.z < _grid_size.y and cell.y < _level_count


func _contains_occupant(occupant_id: StringName) -> bool:
	for value in _occupants.values():
		if value == occupant_id:
			return true
	return false


func _as_cell3(cell: Variant) -> Vector3i:
	if cell is Vector3i:
		return cell
	if cell is Vector2i:
		return Vector3i(cell.x, 0, cell.y)
	return invalid_cell()


func _valid_dimension(value: float) -> bool:
	return not is_nan(value) and not is_inf(value) and value > 0.0


func _valid_cell_size(value: Vector3) -> bool:
	return _valid_dimension(value.x) and _valid_dimension(value.y) and _valid_dimension(value.z)
