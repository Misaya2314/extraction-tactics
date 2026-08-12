extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main/prototype_main.tscn")

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var prototype := MAIN_SCENE.instantiate() as PrototypeController
	get_root().add_child(prototype)
	await process_frame

	_expect(is_instance_valid(prototype.grid), "main: grid model should be created")
	_expect(prototype.grid.grid_size == Vector2i(12, 10), "main: grid size should be 12x10")
	_expect(prototype.units_root.get_child_count() == 4, "main: two players and two enemy markers should spawn")
	_expect(get_nodes_in_group(&"grid_blocker").size() == 18, "main: environment should expose 18 logical blockers")
	_expect(is_instance_valid(prototype.selected_unit), "main: first player should be selected")
	_expect(prototype.highlights_root.get_child_count() > 0, "main: selected unit should show reachable cells")

	var moving_unit := prototype.selected_unit
	var start_cell := moving_unit.grid_cell
	var destination := Vector2i(1, 2)
	await prototype._move_selected_unit(destination)

	_expect(moving_unit.grid_cell == destination, "movement: unit logical cell should update")
	_expect(prototype.grid.get_occupant(start_cell) == &"", "movement: start cell should be released")
	_expect(prototype.grid.get_occupant(destination) == moving_unit.unit_id, "movement: destination should be occupied")
	_expect(moving_unit.current_action_points == 1, "movement: standard move should cost one AP")
	_expect(moving_unit.global_position.is_equal_approx(prototype.grid.cell_to_world(destination)), "movement: visual position should match the grid center")

	prototype._on_end_turn_pressed()
	_expect(prototype.world_tick == 1, "turn: ending the turn should advance the world tick")
	_expect(moving_unit.current_action_points == moving_unit.max_action_points, "turn: player AP should reset")

	prototype.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PROTOTYPE_MAIN_TEST: PASS")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	print("PROTOTYPE_MAIN_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
