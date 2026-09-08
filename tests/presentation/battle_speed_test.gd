extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var previous := Engine.time_scale
	var button := Button.new()
	button.set_script(preload("res://scripts/gameplay/ui/battle_speed_button.gd"))
	root.add_child(button)
	assert(Engine.time_scale == 1.0)
	var unit := preload("res://scenes/main/prototype_unit.tscn").instantiate() as PrototypeUnit
	root.add_child(unit)
	unit.configure(Vector3i.ZERO, &"player", Color.CYAN)
	var hp := unit.current_hp
	var ap := unit.current_action_points
	var start := Time.get_ticks_msec()
	await unit.move_along_world_path([Vector3(3, 0, 0)], Vector3i(1, 0, 0))
	var normal := Time.get_ticks_msec() - start
	button.pressed.emit()
	assert(Engine.time_scale == 2.0 and button.text.contains("2×"))
	button.pressed.emit()
	assert(Engine.time_scale == 4.0)
	start = Time.get_ticks_msec()
	await unit.move_along_world_path([Vector3.ZERO], Vector3i.ZERO)
	var fast := Time.get_ticks_msec() - start
	assert(fast < normal * 0.5, "4x movement must substantially reduce real waiting time")
	assert(unit.global_position == Vector3.ZERO and unit.current_hp == hp and unit.current_action_points == ap)
	button.pressed.emit()
	assert(Engine.time_scale == 1.0)
	button.pressed.emit()
	button.free()
	assert(Engine.time_scale == previous, "leaving battle must restore clock")
	unit.free()
	await process_frame
	await process_frame
	print("BATTLE_SPEED_TEST: PASS (1x=%d ms, 4x=%d ms)" % [normal, fast])
	quit()
