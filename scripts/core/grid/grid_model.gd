class_name GridModel
extends RefCounted

## Runtime-only logical grid used by movement, pathfinding and occupancy systems.
##
## Logical coordinates are Vector2i(x, z). The y component of a world position is
## preserved from `origin` when converting a cell to world space, but ignored when
## converting world space back to a cell.

const DEFAULT_CELL_SIZE: float = 2.0
const CARDINAL_DIRECTIONS := [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

var _grid_size: Vector2i = Vector2i.ZERO
var _cell_size: float = DEFAULT_CELL_SIZE
var _origin: Vector3 = Vector3.ZERO
var _walkable: Dictionary = {}
var _occupants: Dictionary = {}
var _initialized: bool = false


## Creates an empty model. Passing a non-zero size also initializes it.
func _init(initial_size: Vector2i = Vector2i.ZERO, initial_cell_size: float = DEFAULT_CELL_SIZE, initial_origin: Vector3 = Vector3.ZERO) -> void:
	if initial_size != Vector2i.ZERO:
		initialize(initial_size, initial_cell_size, initial_origin)


## Configures a rectangular grid. Newly configured cells are walkable.
##
## This is the primary integration API. Invalid sizes or cell sizes are ignored
## and leave the previous model intact because the contract returns void.
func configure(grid_size: Vector2i, cell_size: float = DEFAULT_CELL_SIZE, origin: Vector3 = Vector3.ZERO) -> void:
	_apply_configuration(grid_size, cell_size, origin)


## Initializes a rectangular grid and reports whether the configuration was valid.
## This compatibility helper is useful for callers that want validation feedback.
func initialize(grid_size: Vector2i, cell_size: float = DEFAULT_CELL_SIZE, origin: Vector3 = Vector3.ZERO) -> bool:
	return _apply_configuration(grid_size, cell_size, origin)


func _apply_configuration(grid_size: Vector2i, cell_size: float, origin: Vector3) -> bool:
	if grid_size.x <= 0 or grid_size.y <= 0:
		return false
	if is_nan(cell_size) or is_inf(cell_size) or cell_size <= 0.0:
		return false

	_grid_size = grid_size
	_cell_size = cell_size
	_origin = origin
	_walkable.clear()
	_occupants.clear()

	for z in range(_grid_size.y):
		for x in range(_grid_size.x):
			_walkable[Vector2i(x, z)] = true

	_initialized = true
	return true


## Returns whether initialize() has successfully configured the model.
func is_initialized() -> bool:
	return _initialized


## Returns the configured logical size as (width, height), where height is z.
func get_grid_size() -> Vector2i:
	return _grid_size


## Read-only property-style accessors for integrations that prefer fields.
var grid_size: Vector2i:
	get:
		return _grid_size

var cell_size: float:
	get:
		return _cell_size

var origin: Vector3:
	get:
		return _origin


## Converts a logical cell center to the corresponding world-space center.
## The mapping is valid even for an uninitialized model and does not clamp cells.
func cell_to_world(cell: Vector2i) -> Vector3:
	return _origin + Vector3(float(cell.x) * _cell_size, 0.0, float(cell.y) * _cell_size)


## Converts an XZ world position to the containing logical cell.
## Cell centers are at origin + cell * cell_size; y is intentionally ignored.
func world_to_cell(world_position: Vector3) -> Vector2i:
	if is_nan(_cell_size) or is_inf(_cell_size) or _cell_size <= 0.0:
		return Vector2i.ZERO

	var local_x: float = (world_position.x - _origin.x) / _cell_size
	var local_z: float = (world_position.z - _origin.z) / _cell_size
	return Vector2i(int(floor(local_x + 0.5)), int(floor(local_z + 0.5)))


## Returns true only for cells inside the initialized rectangle.
func is_in_bounds(cell: Vector2i) -> bool:
	return _initialized and cell.x >= 0 and cell.y >= 0 and cell.x < _grid_size.x and cell.y < _grid_size.y


## Fixed contract alias for bounds checks.
func in_bounds(cell: Vector2i) -> bool:
	return is_in_bounds(cell)


## Sets whether a cell can be entered. A cell occupied by a unit cannot be made
## non-walkable, preserving the invariant that units never stand on a wall.
func set_walkable(cell: Vector2i, walkable: bool) -> bool:
	if not is_in_bounds(cell):
		return false
	if not walkable and _occupants.has(cell):
		return false

	_walkable[cell] = walkable
	return true


## Returns false for out-of-bounds or uninitialized cells.
func is_walkable(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return false
	return _walkable.get(cell, false)


## Returns all in-bounds cardinal neighbors in a stable order.
func get_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	if not is_in_bounds(cell):
		return neighbors

	for direction: Vector2i in CARDINAL_DIRECTIONS:
		var neighbor: Vector2i = cell + direction
		if not is_in_bounds(neighbor):
			continue
		neighbors.append(neighbor)

	return neighbors


## Convenience alias for callers that only need traversable neighbors.
func get_walkable_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for neighbor in get_neighbors(cell):
		if is_walkable(neighbor):
			neighbors.append(neighbor)
	return neighbors


## Places one non-empty StringName occupant on a walkable cell.
## A cell has at most one occupant, and one occupant cannot occupy two cells.
## Repeating occupy() with the same occupant in the same cell is idempotent.
func occupy(cell: Vector2i, occupant_id: StringName) -> bool:
	if occupant_id == &"" or not is_in_bounds(cell) or not is_walkable(cell):
		return false

	if _occupants.has(cell):
		return _same_value(_occupants[cell], occupant_id)
	if _contains_occupant(occupant_id):
		return false

	_occupants[cell] = occupant_id
	return true


## Explicitly named alias for integrations that use cell terminology.
func occupy_cell(cell: Vector2i, occupant_id: StringName) -> bool:
	return occupy(cell, occupant_id)


## Releases the occupant at a cell. An empty expected id releases any occupant;
## otherwise the id must match the current occupant.
func vacate(cell: Vector2i, occupant_id: StringName = &"") -> bool:
	if not is_in_bounds(cell) or not _occupants.has(cell):
		return false
	if occupant_id != &"" and not _same_value(_occupants[cell], occupant_id):
		return false

	_occupants.erase(cell)
	return true


## Compatibility alias for callers that use release terminology.
func release(cell: Vector2i, expected_occupant: StringName = &"") -> bool:
	return vacate(cell, expected_occupant)


## Compatibility alias for integrations that use cell terminology.
func release_cell(cell: Vector2i, expected_occupant: StringName = &"") -> bool:
	return vacate(cell, expected_occupant)


## Releases the first cell occupied by occupant.
func release_occupant(occupant_id: StringName) -> bool:
	if occupant_id == &"":
		return false

	for cell_variant in _occupants.keys():
		if _same_value(_occupants[cell_variant], occupant_id):
			return vacate(cell_variant, occupant_id)
	return false


func is_occupied(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and _occupants.has(cell)


## Returns &"" for an invalid or unoccupied cell.
func get_occupant(cell: Vector2i) -> StringName:
	if not is_in_bounds(cell):
		return &""
	return _occupants.get(cell, &"")


## Alias for code that prefers query-style naming.
func query_occupant(cell: Vector2i) -> StringName:
	return get_occupant(cell)


## Finds a deterministic shortest four-direction path.
##
## The returned array contains both start and goal. The start cell is allowed to
## be occupied because it is the moving unit's current position. Other occupied
## cells, including an occupied goal, block traversal.
func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	return _find_path(start, goal, -1)


## Optional helper for movement controllers that need a path constrained by AP.
## max_steps counts edges; negative values mean no distance limit.
func find_path_limited(start: Vector2i, goal: Vector2i, max_steps: int) -> Array[Vector2i]:
	return _find_path(start, goal, max_steps)


func _find_path(start: Vector2i, goal: Vector2i, max_steps: int) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	if not is_walkable(start) or not is_walkable(goal):
		return empty_path
	if start == goal:
		var same_cell_path: Array[Vector2i] = []
		same_cell_path.append(start)
		return same_cell_path
	if is_occupied(goal):
		return empty_path
	if max_steps == 0:
		return empty_path

	var queue: Array[Vector2i] = [start]
	var queue_index: int = 0
	var distances: Dictionary = {start: 0}
	var came_from: Dictionary = {}

	while queue_index < queue.size():
		var current: Vector2i = queue[queue_index]
		queue_index += 1
		var next_distance: int = int(distances[current]) + 1

		for neighbor in get_neighbors(current):
			if distances.has(neighbor):
				continue
			if max_steps >= 0 and next_distance > max_steps:
				continue
			if not _can_enter_for_movement(neighbor, start):
				continue

			distances[neighbor] = next_distance
			came_from[neighbor] = current
			if neighbor == goal:
				return _reconstruct_path(start, goal, came_from)
			queue.append(neighbor)

	return empty_path


## Returns every traversable cell whose shortest path from start costs at most
## movement_points. The start cell is included when valid, even if occupied.
func get_reachable_cells(start: Vector2i, movement_points: int) -> Array[Vector2i]:
	var reachable: Array[Vector2i] = []
	if not is_walkable(start) or movement_points < 0:
		return reachable

	reachable.append(start)
	if movement_points == 0:
		return reachable

	var queue: Array[Vector2i] = [start]
	var queue_index: int = 0
	var distances: Dictionary = {start: 0}

	while queue_index < queue.size():
		var current: Vector2i = queue[queue_index]
		queue_index += 1
		var next_distance: int = int(distances[current]) + 1
		if next_distance > movement_points:
			continue

		for neighbor in get_neighbors(current):
			if distances.has(neighbor):
				continue
			if not _can_enter_for_movement(neighbor, start):
				continue

			distances[neighbor] = next_distance
			reachable.append(neighbor)
			queue.append(neighbor)

	return reachable


## Short alias for common movement-controller call sites.
func get_reachable(start: Vector2i, movement_points: int) -> Array[Vector2i]:
	return get_reachable_cells(start, movement_points)


func _can_enter_for_movement(cell: Vector2i, start: Vector2i) -> bool:
	if not is_walkable(cell):
		return false
	if cell == start:
		return true
	return not is_occupied(cell)


func _reconstruct_path(start: Vector2i, goal: Vector2i, came_from: Dictionary) -> Array[Vector2i]:
	var path: Array[Vector2i] = [goal]
	var cursor: Vector2i = goal

	while cursor != start:
		if not came_from.has(cursor):
			return []
		cursor = came_from[cursor]
		path.push_front(cursor)

	return path


func _contains_occupant(occupant: Variant) -> bool:
	for cell_variant in _occupants.keys():
		if _same_value(_occupants[cell_variant], occupant):
			return true
	return false


func _same_value(left: Variant, right: Variant) -> bool:
	return left == right
