extends "res://scripts/presentation/sentinel_showcase.gd"

var rig: TacticalCameraRig
var director: CombatPresentationDirector
var moving := false
var demo_round := 0
var blocker: StaticBody3D

func _ready() -> void:
	super._ready()
	get_viewport().get_camera_3d().current = false
	rig = preload("res://scenes/presentation/tactical_camera_rig.tscn").instantiate()
	add_child(rig)
	rig.set_map_bounds(Vector2(-18, -12), Vector2(24, 15))
	units[0].position = Vector3(-8, 0, 0)
	units[1].position = Vector3(16, 0, 2)
	units[2].hide()
	rig.set_focus_target(units[0], false)
	rig.focus_world_position(units[0].position, true)
	director = CombatPresentationDirector.new()
	director.camera_rig = rig
	add_child(director)
	director.mode = CombatPresentationDirector.Mode.FULL
	for child in director.get_children():
		if child is CanvasLayer:
			child.hide()
	for label in find_children("*", "Label", true, false):
		label.text = "MOVEMENT / CAMERA\n\n1 普通跟随   2 攻击   3 冲刺跟拍   4 发现敌人   5 遮挡墙开关\nWASD / 中键 / 滚轮 接管   Home 聚焦"
	blocker = StaticBody3D.new()
	blocker.collision_layer = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(8, 2.6, 0.5)
	collision.shape = shape
	blocker.add_child(collision)
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = shape.size
	wall.mesh = wall_mesh
	blocker.add_child(wall)
	add_child(blocker)
	blocker.position = Vector3(-3, 1.3, 2.4)
	blocker.hide()
	# Ground markers make camera motion legible without changing battle geometry.
	for i in range(-8, 19, 2):
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.08, 0.025, 1.2)
		marker.mesh = box
		add_child(marker)
		marker.position = Vector3(i, 0.02, 0)
	if "--moments-capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.3).timeout
		_move(true)
		await get_tree().create_timer(0.45).timeout
		assert(rig.moments.mode == TacticalCameraMoments.Mode.SPRINT)
		await _capture("camera-sprint")
		while moving:
			await get_tree().process_frame
		await get_tree().create_timer(0.4).timeout
		_discover()
		await get_tree().create_timer(0.4).timeout
		assert(rig.moments.mode == TacticalCameraMoments.Mode.DISCOVERY)
		await _capture("camera-discovery")
		await get_tree().create_timer(1.0).timeout
		_toggle_wall()
		await get_tree().physics_frame
		await get_tree().physics_frame
		_move(true)
		await get_tree().create_timer(0.45).timeout
		assert(rig.moments.mode == TacticalCameraMoments.Mode.NONE)
		await _capture("camera-obstruction")
		while moving:
			await get_tree().process_frame
		get_tree().quit()
	elif "--follow-capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.3).timeout
		_move()
		await get_tree().create_timer(2.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/camera-follow.png")
		while moving:
			await get_tree().process_frame
		await get_tree().create_timer(0.8).timeout
		var frame := rig.camera.global_transform
		await _attack()
		await get_tree().process_frame
		assert(frame.is_equal_approx(rig.camera.global_transform), "Attack must restore movement framing")
		get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or moving or director.active:
		return
	var key := (event as InputEventKey).physical_keycode
	if key == KEY_1:
		_move()
	elif key == KEY_2:
		_attack()
	elif key == KEY_3:
		_move(true)
	elif key == KEY_4:
		_discover()
	elif key == KEY_5:
		_toggle_wall()

func _move(dynamic: bool = false) -> void:
	moving = true
	units[0].position = Vector3(-8, 0, 0)
	rig.focus_world_position(units[0].position, true)
	var points: Array[Vector3] = []
	for i in range(1, 41):
		points.append(Vector3(-8 + i * 0.5, 0, 2 * sin(float(i) / 40 * PI)))
	demo_round += 1
	# Only the showcase resets the cooldown so each key press can demonstrate it.
	rig.moments.last_moment_time = -10000
	rig.begin_movement(units[0], points if dynamic else [], demo_round)
	await units[0].move_along_world_path(points, Vector3i(6, 0, 0))
	rig.end_movement(units[0])
	moving = false

func _attack() -> void:
	director.begin({0: units[0], 1: units[1]}, rig)
	units[1].take_damage(1, false)
	await director.play(units[0], units[1].position)

func _discover() -> void:
	units[2].position = units[1].position + Vector3(1, 0, 3)
	units[2].show()
	rig.show_discovery(units[0], [units[1], units[2]])

func _toggle_wall() -> void:
	blocker.visible = not blocker.visible
	blocker.collision_layer = 2 if blocker.visible else 0

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/%s.png" % filename)
