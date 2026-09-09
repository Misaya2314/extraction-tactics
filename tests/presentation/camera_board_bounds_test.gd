extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var rig := preload("res://scenes/presentation/tactical_camera_rig.tscn").instantiate() as TacticalCameraRig
	root.add_child(rig)
	rig.set_process(false)
	rig.board_margin_cells = 1.5
	var tiles: Array[Rect2] = [Rect2(-12, -4, 2, 2), Rect2(-10, -4, 2, 2), Rect2(12, 6, 2, 2)]
	rig.set_walkable_bounds(tiles, 2.0)
	assert(rig.map_world_min == Vector2(-12, -4) and rig.map_world_max == Vector2(14, 8))
	assert(rig.constrain_board_focus(Vector3(-11, 0, -3)) == Vector3(-11, 0, -3))
	assert(rig.constrain_board_focus(Vector3(-14, 0, -3)) == Vector3(-14, 0, -3), "exterior buffer remains usable")
	for point in [Vector3(1000, 0, 1000), Vector3(-1000, 0, -1000), Vector3.ZERO, Vector3(0, 0, 1000)]:
		var result := rig.constrain_board_focus(point)
		var nearest := INF
		for rect in tiles:
			var horizontal := Vector2(result.x, result.z)
			nearest = minf(nearest, horizontal.distance_to(horizontal.clamp(rect.position, rect.end)))
		assert(nearest <= 3.001, "all directions and sparse holes must stay near actual tiles")
	rig.focus_world_position(Vector3(1000, 0, 1000), true)
	assert(rig.global_position.is_equal_approx(rig.constrain_board_focus(rig.global_position)))
	rig.focus_world_position(Vector3(-1000, 0, -1000))
	assert(rig._focus_goal.is_equal_approx(rig.constrain_board_focus(rig._focus_goal)))
	# Removing walkable regions must immediately bring an old focus back inside.
	rig.set_walkable_bounds([Rect2(-12, -4, 2, 2)], 2.0)
	assert(rig.global_position.x <= -7.0)
	rig.board_margin_cells = 0
	rig.set_walkable_bounds([Rect2(20, 30, 2, 4)], 2.0)
	assert(rig.constrain_board_focus(Vector3(99, 0, 99)) == Vector3(22, 0, 34))
	rig.free()
	print("CAMERA_BOARD_BOUNDS_TEST: PASS")
	quit()
