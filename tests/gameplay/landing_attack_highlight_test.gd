extends "res://tests/gameplay/tactical_undo_controller_test.gd"

## Hovering a movable cell in move mode highlights enemies attackable from that
## landing cell: weapon distance only, attack AP ignored, fog-hidden enemies
## never leak.
func _run() -> void:
	_build_fixture()
	_controller._init_hover_cursor()
	var destination := Vector3i(2, 0, 1)

	var targets: Array = _controller.query_landing_attack_targets(destination)
	_expect(targets.has(_enemy), "visible enemy within weapon range should be previewed")
	_controller._update_landing_attack_highlights(destination)
	_expect(_visible_landing_attack_cells() == [ENEMY_CELL], "highlight renders on the attackable enemy cell")

	var ap: int = _player.current_action_points
	_player.runtime_state.current_action_points = 1
	_expect(_controller.query_landing_attack_targets(destination).has(_enemy), "preview must ignore attack AP")
	_expect(_controller.query_landing_preview(destination).targets.is_empty(), "landing panel keeps its AP gate")
	_player.runtime_state.current_action_points = ap

	_enemy.hide()
	_expect(_controller.query_landing_attack_targets(destination).is_empty(), "hidden enemy must not leak")
	_controller._update_landing_attack_highlights(destination)
	_expect(_visible_landing_attack_cells().is_empty(), "hidden enemy highlight must clear")
	_enemy.show()

	_weapon_definition.range = 1
	_player._apply_weapon_stats()
	_expect(_controller.query_landing_attack_targets(destination).is_empty(), "out of weapon range enemy excluded")
	_weapon_definition.range = 6
	_player._apply_weapon_stats()

	_expect(_controller.query_landing_attack_targets(START_CELL).is_empty(), "current cell is not a landing cell")
	_expect(_controller.query_landing_attack_targets(ENEMY_CELL).is_empty(), "occupied landing cell invalid")
	_expect(_controller.query_landing_attack_targets(Vector3i(7, 0, 7)).is_empty(), "unreachable landing cell invalid")

	_controller.input_locked = true
	_expect(_controller.query_landing_attack_targets(destination).is_empty(), "locked presentation disables preview")
	_controller.input_locked = false
	_controller.action_mode = _controller.ACTION_MODE_ATTACK
	_expect(_controller.query_landing_attack_targets(destination).is_empty(), "attack mode disables the landing preview")
	_controller.action_mode = _controller.ACTION_MODE_MOVE

	_controller._update_landing_attack_highlights(destination)
	_controller._hide_cover_preview()
	_expect(_visible_landing_attack_cells().is_empty(), "leaving hover clears the highlight")

	_free_fixture_ui(_controller)
	_controller.free()
	_view_root.free()
	for failure in _failures:
		push_error(failure)
	print("LANDING_ATTACK_HIGHLIGHT_TEST: " + ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _visible_landing_attack_cells() -> Array:
	var cells: Array = []
	for highlight in _controller._landing_attack_mesh_pool:
		if is_instance_valid(highlight) and highlight.visible:
			cells.append(highlight.get_meta(&"grid_cell"))
	return cells
