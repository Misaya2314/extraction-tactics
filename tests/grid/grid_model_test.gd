extends SceneTree

const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_flat_compatibility_and_coordinates()
	_test_sparse_height_and_transitions()
	_test_weighted_routing()
	_test_occupancy_per_level()
	_test_definition_loading()
	_test_invalid_inputs()
	_finish()


func _test_flat_compatibility_and_coordinates() -> void:
	var grid = GridModelScript.new()
	grid.configure(Vector2i(4, 3), 2.0, Vector3(10.0, 4.0, -6.0))
	_expect(grid.is_initialized(), "flat: grid should initialize")
	_expect(grid.grid_size == Vector2i(4, 3), "flat: footprint should remain compatible")
	_expect(grid.get_level_count() == 1, "flat: compatibility grid should have one level")
	_expect(grid.in_bounds(Vector3i(3, 0, 2)), "flat: last level-zero cell should exist")
	_expect(grid.in_bounds(Vector2i(3, 2)), "flat: Vector2i query should map to level zero")
	_expect(not grid.in_bounds(Vector3i(3, 1, 2)), "flat: an unconfigured upper surface must not exist")
	var cell := Vector3i(2, 0, 3)
	var world := grid.cell_to_world(cell)
	_expect(world.is_equal_approx(Vector3(15.0, 5.0, 1.0)), "flat: cell center should include the GridMap half-cell offset")
	_expect(grid.world_to_cell(world) == cell, "flat: coordinate conversion should round-trip")
	_expect(grid.world_to_cell(Vector3(12.0, 4.0, -4.0)) == Vector3i(1, 0, 1), "flat: GridMap cell boundaries should use floor coordinates")


func _test_sparse_height_and_transitions() -> void:
	var definition := _definition(Vector2i(3, 2), 2, Vector3(2.0, 3.0, 2.0))
	_add_cell(definition, Vector3i(0, 0, 0))
	_add_cell(definition, Vector3i(1, 0, 0))
	_add_cell(definition, Vector3i(1, 1, 0))
	_add_cell(definition, Vector3i(2, 1, 0))
	var grid = GridModelScript.new()
	_expect(grid.configure_from_definition(definition), "height: sparse definition should load")
	_expect(grid.cell_to_world(Vector3i(1, 1, 0)).is_equal_approx(Vector3(3.0, 4.5, 1.0)), "height: level center should include the half-cell offset")
	_expect(grid.world_to_cell(Vector3(3.0, 4.5, 1.0)) == Vector3i(1, 1, 0), "height: world Y should map back to level")
	_expect(grid.find_path(Vector3i(0, 0, 0), Vector3i(2, 1, 0)).is_empty(), "height: stacked surfaces must not auto-connect")
	_expect(grid.add_transition(Vector3i(1, 0, 0), Vector3i(1, 1, 0), 2, true), "height: explicit stairs should be accepted")
	var path := grid.find_path(Vector3i(0, 0, 0), Vector3i(2, 1, 0))
	_expect(path == [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(2, 1, 0)], "height: path should cross only the explicit stairs")
	_expect(grid.get_path_cost(path) == 4, "height: stair cost should contribute to path cost")
	_expect(grid.find_path_limited(path[0], path[-1], 3).is_empty(), "height: weighted budget should reject expensive route")
	_expect(not grid.find_path_limited(path[0], path[-1], 4).is_empty(), "height: exact weighted budget should pass")


func _test_weighted_routing() -> void:
	var grid = GridModelScript.new(Vector2i(3, 2))
	grid.set_move_cost(Vector3i(1, 0, 0), 9)
	var path := grid.find_path(Vector3i(0, 0, 0), Vector3i(2, 0, 0))
	_expect(path == [Vector3i(0, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(2, 0, 1), Vector3i(2, 0, 0)], "cost: Dijkstra should prefer a longer but cheaper route")
	_expect(grid.get_path_cost(path) == 4, "cost: selected route should report total movement cost")
	var reachable := grid.get_reachable_cells(Vector3i(0, 0, 0), 2)
	_expect(reachable.has(Vector3i(1, 0, 1)), "cost: reachable set should follow cumulative cost")
	_expect(not reachable.has(Vector3i(1, 0, 0)), "cost: expensive terrain should remain outside the budget")


func _test_occupancy_per_level() -> void:
	var definition := _definition(Vector2i(1, 1), 2)
	_add_cell(definition, Vector3i(0, 0, 0))
	_add_cell(definition, Vector3i(0, 1, 0))
	var grid = GridModelScript.new()
	grid.configure_from_definition(definition)
	_expect(grid.occupy(Vector3i(0, 0, 0), &"lower"), "occupancy: lower surface should accept an occupant")
	_expect(grid.occupy(Vector3i(0, 1, 0), &"upper"), "occupancy: same XZ on another level should be independent")
	_expect(grid.get_occupant(Vector3i(0, 0, 0)) == &"lower", "occupancy: lower occupant should remain isolated")
	_expect(grid.get_occupant(Vector3i(0, 1, 0)) == &"upper", "occupancy: upper occupant should remain isolated")
	_expect(not grid.occupy(Vector3i(0, 1, 0), &"third"), "occupancy: one surface still permits only one occupant")
	_expect(grid.release_occupant(&"upper"), "occupancy: occupant should be releasable by id")


func _test_definition_loading() -> void:
	var definition := _definition(Vector2i(2, 1), 2)
	_add_cell(definition, Vector3i(0, 0, 0))
	_add_cell(definition, Vector3i(1, 1, 0))
	var link := MapTransitionData.new()
	link.from_cell = Vector3i(0, 0, 0)
	link.to_cell = Vector3i(1, 1, 0)
	link.move_cost = 3
	definition.transitions.append(link)
	var grid = GridModelScript.new()
	_expect(grid.configure_from_definition(definition), "definition: valid resource should compile")
	_expect(grid.get_edge_cost(link.from_cell, link.to_cell) == 3, "definition: transition cost should compile")
	_expect(grid.get_path_cost(grid.find_path(link.from_cell, link.to_cell)) == 3, "definition: compiled transition should be traversable")


func _test_invalid_inputs() -> void:
	var grid = GridModelScript.new()
	_expect(not grid.is_initialized(), "invalid: default model should be empty")
	_expect(not grid.initialize(Vector2i.ZERO), "invalid: zero footprint should fail")
	_expect(not grid.initialize(Vector2i(2, 2), 0.0), "invalid: zero cell size should fail")
	_expect(not grid.configure_from_definition(null), "invalid: missing definition should fail")
	_expect(grid.find_path(Vector3i.ZERO, Vector3i.ONE).is_empty(), "invalid: empty grid should have no path")
	_expect(grid.get_reachable_cells(Vector3i.ZERO, -1).is_empty(), "invalid: negative movement budget should fail")


func _definition(size: Vector2i, levels: int, dimensions: Vector3 = Vector3(2.0, 2.0, 2.0)) -> TacticalMapDefinition:
	var result := TacticalMapDefinition.new()
	result.footprint_size = size
	result.level_count = levels
	result.cell_size = dimensions
	return result


func _add_cell(definition: TacticalMapDefinition, coordinate: Vector3i, walkable: bool = true, cost: int = 1) -> void:
	var data := MapCellData.new()
	data.coordinate = coordinate
	data.walkable = walkable
	data.move_cost = cost
	definition.cells.append(data)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("GRID_MODEL_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("GRID_MODEL_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
