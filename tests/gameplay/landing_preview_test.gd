extends "res://tests/gameplay/tactical_undo_controller_test.gd"

func _run() -> void:
	_build_fixture()
	var destination := Vector3i(2, 0, 1)
	var ap: int = _player.current_action_points
	var before: Vector3 = _player.global_position
	var preview: Dictionary = _controller.query_landing_preview(destination)
	_expect(preview.valid and preview.remaining_ap == ap - 1, "valid move predicts remaining AP")
	_expect(preview.targets.has(_enemy.name), "reachable known enemy should be listed")
	_expect(_player.current_action_points == ap and _player.grid_cell == START_CELL and _player.global_position == before, "preview cannot mutate unit")
	_expect(_controller.grid.get_occupant(START_CELL) == PLAYER_ID and not _controller.grid.is_occupied(destination), "preview cannot mutate occupancy")
	_enemy.hide()
	_expect(_controller.query_landing_preview(destination).targets.is_empty(), "hidden enemy must not leak")
	_enemy.show()
	_player.runtime_state.current_action_points = 1
	preview = _controller.query_landing_preview(destination)
	_expect(preview.valid and preview.remaining_ap == 0 and preview.targets.is_empty() and preview.reason.contains("AP"), "insufficient attack AP must be explicit")
	_player.runtime_state.current_action_points = ap
	_expect(not _controller.query_landing_preview(START_CELL).valid, "current cell is not a move")
	_expect(not _controller.query_landing_preview(ENEMY_CELL).valid, "occupied destination invalid")
	_expect(not _controller.query_landing_preview(Vector3i(7, 0, 7)).valid, "out of movement range invalid")
	_controller.input_locked = true
	_expect(not _controller.query_landing_preview(destination).valid, "locked presentation disables preview")
	_controller.input_locked = false
	_controller.action_mode = _controller.ACTION_MODE_ATTACK
	_expect(not _controller.query_landing_preview(destination).valid, "attack mode disables landing preview")
	_controller.action_mode = _controller.ACTION_MODE_MOVE
	_weapon_definition.range = 0
	_player._apply_weapon_stats()
	_expect(_controller.query_landing_preview(destination).targets.is_empty(), "out of weapon range target excluded")
	_free_fixture_ui(_controller)
	_controller.free()
	_view_root.free()
	for failure in _failures:
		push_error(failure)
	print("LANDING_PREVIEW_TEST: " + ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)
