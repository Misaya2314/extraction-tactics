extends SceneTree

const AUTHOR_SCENE = preload("res://scenes/map_authoring/prototype_map_authoring.tscn")
const MAP_DEFINITION = preload("res://resources/maps/prototype_map.tres")
const GRID_MODEL_SCRIPT = preload("res://scripts/core/grid/grid_model.gd")

var _failures: Array[String] = []


func _init() -> void:
	var author := AUTHOR_SCENE.instantiate() as TacticalMapAuthor
	root.add_child(author)
	var floor_grid := author.get_node("FloorGrid") as GridMap
	var grid = GRID_MODEL_SCRIPT.new()
	_expect(floor_grid != null, "authoring: FloorGrid should instantiate")
	_expect(grid.configure_from_definition(MAP_DEFINITION), "runtime: baked map should configure GridModel")

	for cell in [Vector3i(1, 0, 1), Vector3i(7, 0, 2), Vector3i(10, 1, 1)]:
		var gridmap_center := floor_grid.map_to_local(cell)
		var author_center := author.cell_to_local(cell)
		var runtime_center := grid.cell_to_world(cell)
		_expect(author_center.is_equal_approx(gridmap_center), "center: author conversion must match GridMap.map_to_local(%s)" % cell)
		_expect(runtime_center.is_equal_approx(gridmap_center), "center: GridModel conversion must match GridMap.map_to_local(%s)" % cell)
		_expect(grid.world_to_cell(runtime_center) == cell, "center: runtime conversion must round-trip %s" % cell)
		_expect(grid.world_to_existing_cell(gridmap_center) == cell, "center: existing-cell lookup must find %s" % cell)

	var player_alpha := author.get_node("Spawns/PlayerAlpha") as Node3D
	_expect(player_alpha.position.is_equal_approx(author.cell_to_local(Vector3i(1, 0, 1))), "marker: PlayerAlpha should be centered on its cell")
	var upper_loot := author.get_node("Objects/loot_high") as Node3D
	_expect(upper_loot.position.is_equal_approx(author.cell_to_local(Vector3i(10, 1, 1))), "marker: upper-platform object should use the level center")

	if _failures.is_empty():
		print("COORDINATE_ALIGNMENT_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("COORDINATE_ALIGNMENT_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
