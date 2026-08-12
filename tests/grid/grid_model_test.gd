extends SceneTree

const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_coordinate_conversion()
	_test_wall_routing()
	_test_unreachable_area()
	_test_occupancy_blocking()
	_test_movement_range_and_boundaries()
	_test_invalid_inputs()

	if _failures.is_empty():
		print("GRID_MODEL_TEST: PASS")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	print("GRID_MODEL_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)


func _test_coordinate_conversion() -> void:
	var grid = GridModelScript.new()
	grid.configure(Vector2i(4, 3), 2.0, Vector3(10.0, 4.0, -6.0))
	_expect(grid.is_initialized(), "coordinate: grid should initialize")
	_expect(grid.get_grid_size() == Vector2i(4, 3), "coordinate: size should be retained")
	_expect(grid.in_bounds(Vector2i(3, 2)), "coordinate: in_bounds should accept the last cell")
	_expect(not grid.in_bounds(Vector2i(4, 2)), "coordinate: in_bounds should reject the first cell outside")

	var cell := Vector2i(-2, 3)
	var world := grid.cell_to_world(cell)
	_expect(world.is_equal_approx(Vector3(6.0, 4.0, 0.0)), "coordinate: cell center should map on XZ")
	_expect(grid.world_to_cell(world) == cell, "coordinate: cell/world conversion should round-trip")
	_expect(grid.world_to_cell(Vector3(11.9, 999.0, -4.1)) == Vector2i(1, 1), "coordinate: world y should be ignored")


func _test_wall_routing() -> void:
	var grid = GridModelScript.new(Vector2i(5, 5))
	for z in range(1, 4):
		_expect(grid.set_walkable(Vector2i(2, z), false), "routing: wall cell should be configurable")

	var start := Vector2i(0, 2)
	var goal := Vector2i(4, 2)
	var path: Array[Vector2i] = grid.find_path(start, goal)
	var repeated_path: Array[Vector2i] = grid.find_path(start, goal)

	_expect(not path.is_empty(), "routing: wall should be bypassable")
	_expect(path == repeated_path, "routing: path should be deterministic")
	_expect(path[0] == start and path[path.size() - 1] == goal, "routing: path should include endpoints")
	_expect(path.size() == 9, "routing: shortest detour should have expected length")
	for index in range(path.size()):
		var current: Vector2i = path[index]
		_expect(grid.is_walkable(current), "routing: path must use walkable cells")
		_expect(current.x != 2 or current.y == 0 or current.y == 4, "routing: path must go around the wall")
		if index > 0:
			var previous: Vector2i = path[index - 1]
			_expect(abs(current.x - previous.x) + abs(current.y - previous.y) == 1, "routing: path must not move diagonally")

	_expect(grid.find_path_limited(start, goal, 7).is_empty(), "routing: distance limit should reject a too-short path")
	_expect(not grid.find_path_limited(start, goal, 8).is_empty(), "routing: distance limit should allow an exact path")


func _test_unreachable_area() -> void:
	var grid = GridModelScript.new(Vector2i(3, 3))
	var start := Vector2i(1, 1)
	for blocker in [Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0), Vector2i(1, 2)]:
		_expect(grid.set_walkable(blocker, false), "unreachable: surrounding wall should be configurable")

	_expect(grid.find_path(start, Vector2i(0, 0)).is_empty(), "unreachable: enclosed goal should have no path")
	var reachable: Array[Vector2i] = grid.get_reachable_cells(start, 10)
	_expect(reachable == [start], "unreachable: only the start cell should be reachable")


func _test_occupancy_blocking() -> void:
	var grid = GridModelScript.new(Vector2i(5, 1))
	var start := Vector2i(0, 0)
	var goal := Vector2i(4, 0)
	var player: StringName = &"player"
	var blocker: StringName = &"blocker"

	_expect(grid.occupy(start, player), "occupancy: start should be occupiable")
	_expect(grid.occupy(Vector2i(2, 0), blocker), "occupancy: blocker should be occupiable")
	_expect(grid.get_occupant(start) == player, "occupancy: occupant query should return player")
	_expect(grid.is_occupied(Vector2i(2, 0)), "occupancy: blocker cell should report occupied")
	_expect(grid.occupy(start, player), "occupancy: same occupant should be idempotent")
	_expect(not grid.occupy(start, &"other"), "occupancy: a cell should reject a second occupant")
	_expect(not grid.occupy(Vector2i(1, 0), player), "occupancy: one occupant should not occupy two cells")
	_expect(grid.find_path(start, goal).is_empty(), "occupancy: occupied cells should block paths")
	_expect(not grid.vacate(start, &"other"), "occupancy: mismatched release should fail")
	_expect(grid.release_occupant(blocker), "occupancy: blocker should be releasable")
	_expect(not grid.is_occupied(Vector2i(2, 0)), "occupancy: released cell should be empty")
	_expect(not grid.find_path(start, goal).is_empty(), "occupancy: path should open after release")
	_expect(grid.set_walkable(Vector2i(1, 0), false), "occupancy: empty cell should become a wall")
	_expect(not grid.occupy(Vector2i(1, 0), &"wall occupant"), "occupancy: wall should reject occupancy")


func _test_movement_range_and_boundaries() -> void:
	var grid = GridModelScript.new(Vector2i(5, 5))
	var center_reachable: Array[Vector2i] = grid.get_reachable_cells(Vector2i(2, 2), 2)
	_expect(center_reachable.size() == 13, "range: open center with two points should reach 13 cells")
	_expect(center_reachable.has(Vector2i(0, 2)), "range: exact movement boundary should be included")
	_expect(not center_reachable.has(Vector2i(0, 0)), "range: cells beyond movement boundary should be excluded")

	var corner_reachable: Array[Vector2i] = grid.get_reachable_cells(Vector2i.ZERO, 2)
	var expected_corner := [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(2, 0), Vector2i(1, 1), Vector2i(0, 2)]
	_expect(corner_reachable == expected_corner, "range: boundary results should be stable and clipped")
	_expect(grid.get_reachable_cells(Vector2i.ZERO, 0) == [Vector2i.ZERO], "range: zero points should include only start")

	_expect(grid.occupy(Vector2i(1, 0), "range blocker"), "range: blocker should be placed")
	var blocked_corner: Array[Vector2i] = grid.get_reachable_cells(Vector2i.ZERO, 2)
	_expect(not blocked_corner.has(Vector2i(1, 0)), "range: occupied cell should be excluded")
	_expect(blocked_corner.has(Vector2i(0, 1)), "range: alternate route should remain available")


func _test_invalid_inputs() -> void:
	var grid = GridModelScript.new()
	_expect(not grid.is_initialized(), "invalid: default model should be uninitialized")
	grid.configure(Vector2i.ZERO)
	_expect(not grid.is_initialized(), "invalid: zero size should be rejected")
	grid.configure(Vector2i(-1, 3))
	_expect(not grid.is_initialized(), "invalid: negative size should be rejected")
	grid.configure(Vector2i(2, 2), 0.0)
	_expect(not grid.is_initialized(), "invalid: non-positive cell size should be rejected")
	_expect(not grid.is_in_bounds(Vector2i.ZERO), "invalid: empty model should have no bounds")
	_expect(grid.get_neighbors(Vector2i.ZERO).is_empty(), "invalid: empty model should have no neighbors")
	_expect(grid.find_path(Vector2i.ZERO, Vector2i.ONE).is_empty(), "invalid: empty model should have no path")
	_expect(grid.get_reachable_cells(Vector2i.ZERO, -1).is_empty(), "invalid: negative movement points should be rejected")

	_expect(grid.initialize(Vector2i(2, 2)), "invalid: valid initialization should recover the model")
	_expect(not grid.set_walkable(Vector2i(9, 9), false), "invalid: out-of-bounds walkability update should fail")
	_expect(not grid.occupy(Vector2i(9, 9), "invalid"), "invalid: out-of-bounds occupancy should fail")
	_expect(grid.get_occupant(Vector2i(9, 9)) == &"", "invalid: out-of-bounds occupant query should return an empty id")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
