extends "res://tests/gameplay/tactical_undo_controller_test.gd"

## Hovering a movable cell in move mode previews enemy gun-lines: a red line
## connects each enemy that the selected unit can see and whose weapon line can
## reach the landing cell. Fog-hidden enemies never leak.
func _run() -> void:
	_build_fixture()
	_controller._init_hover_cursor()
	var destination := Vector3i(2, 0, 1)

	var sources: Array = _controller.query_enemy_gunline_sources(destination)
	_expect(sources.has(_enemy), "visible enemy able to hit the landing cell should be previewed")

	var ap: int = _player.current_action_points
	var before: Vector3 = _player.global_position
	_controller.query_enemy_gunline_sources(destination)
	_expect(_player.current_action_points == ap and _player.grid_cell == START_CELL and _player.global_position == before, "gun-line query cannot mutate unit")
	_expect(_controller.grid.get_occupant(START_CELL) == PLAYER_ID and not _controller.grid.is_occupied(destination), "gun-line query cannot mutate occupancy")

	_controller._update_enemy_gunline_preview(destination)
	var lines := _visible_gunlines()
	_expect(lines.size() == 1, "one enemy gun-line should render")
	if lines.size() == 1:
		var expected_mid: Vector3 = (_controller.grid.cell_to_world(_enemy.grid_cell) + _controller.grid.cell_to_world(destination)) * 0.5 + Vector3.UP * _controller.ENEMY_GUNLINE_HEIGHT
		_expect(lines[0].position.distance_to(expected_mid) < 0.01, "gun-line must connect enemy and landing cell")
		var expected_delta: Vector3 = _controller.grid.cell_to_world(destination) - _controller.grid.cell_to_world(_enemy.grid_cell)
		_expect(lines[0].transform.basis.z.distance_to(expected_delta) < 0.01, "gun-line must be oriented and scaled to span enemy to landing cell")
		_expect(absf(lines[0].transform.basis.x.length() - _controller.ENEMY_GUNLINE_WIDTH) < 0.001, "gun-line width must stay thin")

	_enemy.hide()
	_expect(_controller.query_enemy_gunline_sources(destination).is_empty(), "hidden enemy must not leak")
	_controller._update_enemy_gunline_preview(destination)
	_expect(_visible_gunlines().is_empty(), "hidden enemy gun-line must clear")
	_enemy.show()

	_weapon_definition.range = 1
	_player._apply_weapon_stats()
	_expect(_controller.query_enemy_gunline_sources(destination).is_empty(), "enemy out of weapon range excluded")
	_weapon_definition.range = 6
	_player._apply_weapon_stats()

	_archetype.vision_range = 2
	_expect(_controller.query_enemy_gunline_sources(destination).is_empty(), "enemy outside the unit's vision excluded")
	_expect(_controller.query_current_enemy_gunline_sources().is_empty(), "current-position preview also respects vision")
	_archetype.vision_range = 6

	var current_sources: Array = _controller.query_current_enemy_gunline_sources()
	_expect(current_sources.has(_enemy), "enemy able to hit the unit where it stands should be previewed")
	_controller._update_enemy_gunline_preview(START_CELL)
	lines = _visible_gunlines()
	_expect(lines.size() == 1, "current-position gun-line should render without a hovered landing cell")
	if lines.size() == 1:
		var current_mid: Vector3 = (_controller.grid.cell_to_world(_enemy.grid_cell) + _controller.grid.cell_to_world(START_CELL)) * 0.5 + Vector3.UP * _controller.ENEMY_GUNLINE_HEIGHT
		_expect(lines[0].position.distance_to(current_mid) < 0.01, "current-position gun-line must connect enemy and the unit")

	_expect(_controller.query_enemy_gunline_sources(START_CELL).is_empty(), "current cell is not a landing cell")
	_expect(_controller.query_enemy_gunline_sources(ENEMY_CELL).is_empty(), "occupied landing cell invalid")
	_expect(_controller.query_enemy_gunline_sources(Vector3i(7, 0, 7)).is_empty(), "unreachable landing cell invalid")

	_controller.input_locked = true
	_expect(_controller.query_enemy_gunline_sources(destination).is_empty(), "locked presentation disables preview")
	_controller.input_locked = false
	_controller.action_mode = _controller.ACTION_MODE_ATTACK
	_expect(_controller.query_enemy_gunline_sources(destination).is_empty(), "attack mode disables the gun-line preview")
	_controller.action_mode = _controller.ACTION_MODE_MOVE

	_controller._update_enemy_gunline_preview(destination)
	_controller._hide_cover_preview()
	_expect(_visible_gunlines().is_empty(), "leaving hover clears the gun-line")

	_free_fixture_ui(_controller)
	_controller.free()
	_view_root.free()
	for failure in _failures:
		push_error(failure)
	print("ENEMY_GUNLINE_PREVIEW_TEST: " + ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _visible_gunlines() -> Array:
	var lines: Array = []
	for line in _controller._gunline_mesh_pool:
		if is_instance_valid(line) and line.visible:
			lines.append(line)
	return lines
