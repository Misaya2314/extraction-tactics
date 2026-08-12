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
	_expect(prototype.map_definition.cells.size() == 129, "main: runtime should load the baked two-level map")
	_expect(prototype.map_definition.transitions.size() == 1, "main: runtime should load the explicit stair connection")
	_expect(prototype.turn_manager.get_phase() == TurnManager.Phase.EXPLORATION, "main: prototype should start in exploration")
	_expect(is_instance_valid(prototype.selected_unit), "main: first player should be selected")
	_expect(prototype.highlights_root.get_child_count() > 0, "main: selected unit should show reachable cells")

	var moving_unit := prototype.selected_unit
	var start_cell := moving_unit.grid_cell
	var destination := Vector3i(1, 0, 2)
	await prototype._move_selected_unit(destination)

	_expect(moving_unit.grid_cell == destination, "movement: unit logical cell should update")
	_expect(prototype.grid.get_occupant(start_cell) == &"", "movement: start cell should be released")
	_expect(prototype.grid.get_occupant(destination) == moving_unit.unit_id, "movement: destination should be occupied")
	_expect(moving_unit.current_action_points == 1, "movement: standard move should cost one AP")
	_expect(moving_unit.global_position.is_equal_approx(prototype.grid.cell_to_world(destination)), "movement: visual position should match the grid center")

	await prototype._on_end_turn_pressed()
	_expect(prototype.world_tick == 1, "turn: ending the turn should advance the world tick")
	_expect(moving_unit.current_action_points == moving_unit.max_action_points, "turn: player AP should reset")

	var enemy := prototype._unit_by_name(&"EnemyScout")
	_expect(is_instance_valid(enemy), "combat: enemy scout should exist")
	if is_instance_valid(enemy):
		var old_player_cell := moving_unit.grid_cell
		prototype.grid.vacate(old_player_cell, moving_unit.unit_id)
		prototype.grid.occupy(Vector3i(5, 0, 1), moving_unit.unit_id)
		moving_unit.grid_cell = Vector3i(5, 0, 1)
		moving_unit.global_position = prototype.grid.cell_to_world(moving_unit.grid_cell)
		moving_unit.reset_action_points()
		var first_attack := await prototype._attack_with_unit(moving_unit, enemy)
		_expect(first_attack.success, "combat: visible in-range enemy should be attackable")
		_expect(prototype.turn_manager.is_player_turn(), "combat: active attack from exploration should give player turn")
		_expect(enemy.current_hp == 6, "combat: attack should apply configured damage")
		moving_unit.reset_action_points()
		await prototype._attack_with_unit(moving_unit, enemy)
		moving_unit.reset_action_points()
		var killing_attack := await prototype._attack_with_unit(moving_unit, enemy)
		_expect(killing_attack.killed, "combat: third attack should kill the scout")
		_expect(not prototype.units_by_id.has(enemy.unit_id), "combat: killed enemy should leave active unit registry")
		_expect(prototype.turn_manager.get_enemy_ids().size() == 1, "combat: turn roster should remove killed enemy")

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
