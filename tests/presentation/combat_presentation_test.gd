extends SceneTree

var failures: Array[String] = []
var done := false

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var rig := (load("res://scenes/presentation/tactical_camera_rig.tscn") as PackedScene).instantiate() as TacticalCameraRig
	world.add_child(rig)
	var director := CombatPresentationDirector.new()
	world.add_child(director)
	director.mode = CombatPresentationDirector.Mode.FULL
	director.slow_motion_enabled = true
	var attacker := _unit(world, Vector3(7, 0, 7), &"player")
	var victim := _unit(world, Vector3(7, 0, 10), &"enemy")
	var second := _unit(world, Vector3(6, 0, 10), &"enemy")
	var hidden := _unit(world, Vector3(8, 0, 10), &"enemy")
	hidden.visible = false
	attacker.look_at_cell(Vector3i(7, 0, 10))
	var environment := (load("res://scenes/prototype/environment/prototype_explosive_barrel.tscn") as PackedScene).instantiate() as EnvironmentObjectView
	world.add_child(environment)
	environment.position = Vector3(8, 0, 10)
	await process_frame
	var camera_before := rig.camera.global_transform
	var pose := victim.visual_root.transform
	var cell := victim.grid_cell
	var hp := attacker.current_hp
	var ap := attacker.current_action_points
	director.begin({1: attacker, 2: victim, 3: hidden, 4: second}, rig)
	director.retain_environment(environment, true)
	victim.take_damage(100, false)
	second.take_damage(100, false)
	hidden.take_damage(100, false)
	environment.set_runtime_active(false)
	_expect(environment.visible, "destroyed prop retained until impact")
	_expect(environment.get_node("BarrelBody").collision_layer == 0, "logical prop collision immediately removed")
	_expect(director.active and rig.cinematic_active, "camera input held during action")
	var started := Time.get_ticks_msec()
	await director.play(attacker, victim.position, true, true)
	_expect(Time.get_ticks_msec() - started >= 450, "highlight has a real presentation interval")
	_expect(director.impacts.size() == 2, "multiple visible kills grouped; hidden victim excluded")
	_expect(not victim.visible and not hidden.visible and not environment.visible, "dead views cleaned after action")
	_expect(director.remains.size() == 2, "only visible kills leave remains")
	for entry in director.remains:
		_expect(entry.node.find_children("*", "CollisionObject3D", true, false).is_empty(), "remains cannot block movement or bullets")
	_expect(camera_before.is_equal_approx(rig.camera.global_transform), "camera restored exactly")
	_expect(not rig.cinematic_active and not director.active, "camera and presentation unlocked")
	_expect(victim.visual_root.transform.is_equal_approx(pose), "pose reset for undo")
	_expect(victim.grid_cell == cell and attacker.current_hp == hp and attacker.current_action_points == ap, "presentation cannot mutate gameplay")
	_expect(is_equal_approx(Engine.time_scale, 1.0), "global clock untouched")
	# Skip must release everything without awaiting an abandoned tween.
	victim.current_hp = victim.max_hp
	victim.visible = true
	victim.process_mode = Node.PROCESS_MODE_INHERIT
	director.prune_remains()
	_expect(director.remains.size() == 1, "reviving a unit removes its remains")
	director.begin({1: attacker, 2: victim}, rig)
	victim.take_damage(1, false)
	director.skip()
	victim.robot_visual.set_attack_pose(0.5, Vector3.RIGHT, Vector3.ZERO)
	director._posed_attacker = victim
	started = Time.get_ticks_msec()
	await director.play(attacker, victim.position)
	_expect(Time.get_ticks_msec() - started < 100, "skip completes immediately")
	_expect(victim.visible and victim.visual_root.transform.is_equal_approx(pose), "survivor restored after skip")
	_expect(victim.robot_visual.position.is_zero_approx(), "skip clears partially completed peek")
	# Every candidate blocked: retain the tactical camera, including wall layer 2.
	var wall := StaticBody3D.new()
	wall.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 30, 30)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.position = victim.position
	await physics_frame
	await physics_frame
	director.begin({1: attacker}, rig)
	director._choose_camera(attacker.position, victim.position, false)
	_expect(director._camera_goal.is_equal_approx(camera_before), "blocked closeups fall back to tactical camera")
	director.finish()
	wall.queue_free()
	await process_frame
	for mode_value in [CombatPresentationDirector.Mode.KILLS_ONLY, CombatPresentationDirector.Mode.OFF]:
		director.mode = mode_value
		director.begin({1: attacker, 2: victim}, rig)
		victim.take_damage(1, false)
		_render_play(director, attacker, victim)
		await create_timer(0.1).timeout
		_expect(camera_before.is_equal_approx(rig.camera.global_transform), "ordinary hit does not cut in reduced modes")
		while director.active:
			await process_frame
	director.mode = CombatPresentationDirector.Mode.FULL
	director.camera_rig = rig
	var captured: Array = []
	director.mode_changed.connect(func(m: CombatPresentationDirector.Mode) -> void:
		captured.append(m)
	)
	director.mode = CombatPresentationDirector.Mode.OFF
	_expect(captured.size() == 1 and captured[0] == CombatPresentationDirector.Mode.OFF, "mode_changed should emit on mode change")
	_expect(not rig.sprint_moments_enabled, "Mode.OFF must disable camera rig sprint moments")
	director.mode = CombatPresentationDirector.Mode.FULL
	_expect(captured.size() == 2 and captured[1] == CombatPresentationDirector.Mode.FULL, "mode_changed should emit when restored to FULL")
	_expect(rig.sprint_moments_enabled, "Mode.FULL must re-enable camera rig sprint moments")
	done = false
	# Render an optional visual fixture with the real unit and camera assets.
	if "--visual" in OS.get_cmdline_user_args():
		var ground := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(30, 30)
		ground.mesh = plane
		world.add_child(ground)
		ground.position = Vector3(7, -0.01, 7)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-60, -30, 0)
		world.add_child(light)
		victim.current_hp = victim.max_hp
		victim.visible = true
		director.begin({1: attacker, 2: victim}, rig)
		victim.take_damage(100, false)
		_render_play(director, attacker, victim)
		await create_timer(0.35).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/combat-preview.png")
		while not done:
			await process_frame
	world.queue_free()
	await process_frame
	if "--main-preview" in OS.get_cmdline_user_args():
		var main := (load("res://scenes/main/prototype_main.tscn") as PackedScene).instantiate()
		root.add_child(main)
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/combat-main-preview.png")
		main.queue_free()
		await process_frame
	for failure in failures:
		push_error(failure)
	print("COMBAT_PRESENTATION_TEST: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _render_play(director: CombatPresentationDirector, attacker: PrototypeUnit, victim: PrototypeUnit) -> void:
	await director.play(attacker, victim.position, false, true)
	done = true

func _unit(world: Node3D, position: Vector3, faction: StringName) -> PrototypeUnit:
	var unit := (load("res://scenes/main/prototype_unit.tscn") as PackedScene).instantiate() as PrototypeUnit
	world.add_child(unit)
	unit.configure(Vector3i(position), faction, Color.DODGER_BLUE if faction == &"player" else Color.ORANGE_RED, null, load("res://resources/weapons/assault_rifle.tres"))
	unit.position = position
	return unit

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
