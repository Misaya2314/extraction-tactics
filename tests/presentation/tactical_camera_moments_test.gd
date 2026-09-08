extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var rig := preload("res://scenes/presentation/tactical_camera_rig.tscn").instantiate() as TacticalCameraRig
	root.add_child(rig)
	rig.set_map_bounds(Vector2(-40, -40), Vector2(40, 40))
	rig.focus_world_position(Vector3.ZERO, true)
	rig.set_process(false)
	var actor := Node3D.new()
	var enemy := Node3D.new()
	root.add_child(actor)
	root.add_child(enemy)
	enemy.position = Vector3(6, 0, 2)
	var path: Array[Vector3] = [Vector3(2, 0, 0), Vector3(4, 0, 0), Vector3(6, 0, 0), Vector3(8, 0, 0), Vector3(10, 0, 0)]
	var moments := rig.moments
	check(not moments.request_sprint(rig, actor, [Vector3.RIGHT], 1), "short move cannot trigger sprint")
	check(moments.request_sprint(rig, actor, path, 1), "open route should trigger sprint")
	var tactical := rig.camera.global_transform
	var dynamic_frame: Transform3D = moments.update(rig, tactical, 0.3)
	check(dynamic_frame.origin.y < tactical.origin.y, "sprint should lower camera")
	check(actor.position == Vector3.ZERO, "camera cannot move actors")
	rig.take_manual_control()
	check(moments.mode == TacticalCameraMoments.Mode.NONE, "manual input cancels dynamic shot")
	moments.last_moment_time = -10000
	check(not moments.request_sprint(rig, actor, path, 1), "sprint limited to once per round")
	check(moments.request_sprint(rig, actor, path, 2), "new round allows sprint")
	rig.camera.global_transform = moments.update(rig, tactical, 0.3)
	var restored := rig.begin_cinematic()
	check(restored.is_equal_approx(tactical) and moments.mode == TacticalCameraMoments.Mode.NONE, "attack must start from tactical baseline")
	rig.end_cinematic(restored)
	rig.manual_override = false
	enemy.hide()
	check(not rig.show_discovery(actor, [enemy]), "hidden target must never trigger discovery")
	enemy.show()
	check(rig.show_discovery(actor, [enemy, enemy]), "visible discovery should frame both actors")
	check(moments.subjects.size() == 2, "discovery must deduplicate subjects")
	check(not rig.show_discovery(actor, [enemy]), "discovery cooldown prevents repeated cuts")
	dynamic_frame = moments.update(rig, tactical, 0.3)
	rig.camera.global_transform = dynamic_frame
	check(rig._inside_screen(actor.position, 0.9) and rig._inside_screen(enemy.position, 0.9), "discovery should include both actors")
	enemy.hide()
	check(moments.update(rig, tactical, 0.01).is_equal_approx(tactical), "losing visibility returns to tactical view")
	enemy.show()
	rig.camera.global_transform = tactical
	var wall := StaticBody3D.new()
	wall.collision_layer = 2
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 6, 0.5)
	collision.shape = box
	wall.add_child(collision)
	root.add_child(wall)
	wall.position = Vector3(0, 3, 1.5)
	await physics_frame
	await physics_frame
	moments.last_moment_time = -10000
	check(not moments.request_sprint(rig, actor, path, 3), "obstructed route must keep tactical view")
	wall.collision_layer = 0
	await physics_frame
	check(moments.request_sprint(rig, actor, path, 3), "removing obstruction allows shot")
	wall.collision_layer = 2
	await physics_frame
	check(moments.update(rig, tactical, 0.3).is_equal_approx(tactical), "new obstruction aborts ongoing shot")
	wall.free()
	moments.last_moment_time = -10000
	check(moments.request_sprint(rig, actor, path, 4), "sprint can start again")
	actor.free()
	check(moments.update(rig, tactical, 0.01).is_equal_approx(tactical), "deleted subject must safely release shot")
	enemy.free()
	# Exercise the actual controller visibility adapter, including debug reveal.
	var controller := PrototypeController.new()
	controller.grid = GridModel.new(Vector2i(10, 5))
	controller.turn_manager = TurnManager.new()
	controller.camera_rig = rig
	var player := preload("res://scenes/main/prototype_unit.tscn").instantiate() as PrototypeUnit
	var target := preload("res://scenes/main/prototype_unit.tscn").instantiate() as PrototypeUnit
	root.add_child(player)
	root.add_child(target)
	player.configure(Vector3i.ZERO, &"player", Color.CYAN)
	target.configure(Vector3i(3, 0, 0), &"enemy", Color.ORANGE)
	target.position = Vector3(6, 0, 0)
	controller.units_by_id = {&"p": player, &"e": target}
	controller.all_player_ids = [&"p"]
	controller.all_enemy_ids = [&"e"]
	controller.debug_reveal_all = true
	player.vision_range = 1
	controller._update_enemy_visibility()
	check(target.visible and controller._camera_known_enemies.is_empty(), "debug reveal must not count as actual discovery")
	moments.last_discovery_time = -10000
	rig.manual_override = false
	player.vision_range = 8
	controller._update_enemy_visibility()
	check(moments.mode == TacticalCameraMoments.Mode.DISCOVERY and controller._camera_known_enemies.has(&"e"), "actual sight transition must trigger discovery")
	moments.cancel()
	moments.last_discovery_time = -10000
	controller._update_enemy_visibility()
	check(moments.mode == TacticalCameraMoments.Mode.NONE, "repeated visibility refresh must not retrigger")
	controller._camera_known_enemies.clear()
	controller._camera_visibility_initialized = false
	controller._update_enemy_visibility()
	check(moments.mode == TacticalCameraMoments.Mode.NONE, "initial or restored visibility must not trigger")
	controller.free()
	player.free()
	target.free()
	rig.free()
	for failure in failures:
		push_error(failure)
	print("TACTICAL_CAMERA_MOMENTS_TEST: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
