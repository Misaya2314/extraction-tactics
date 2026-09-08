extends SceneTree

var failures: Array[String] = []
var contacts: Array[int] = []
var completed := false

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := UnitMovementPath.new()
	path.build(Vector3.ZERO, [Vector3(2, 0, 0), Vector3(4, 0, 0), Vector3(6, 0, 0)])
	check(path.sample(0).speed == 0 and path.sample(path.duration).speed == 0, "route must start and stop at rest")
	var boundary: float = path.segments[1].time
	check(path.sample(boundary).speed > 3.0, "straight waypoint must not restart acceleration")
	check(absf(path.sample(boundary - 0.0001).speed - path.sample(boundary + 0.0001).speed) < 0.01, "speed must be continuous at waypoint")
	var same_route := UnitMovementPath.new()
	same_route.build(Vector3.ZERO, [Vector3(6, 0, 0)])
	check(is_equal_approx(path.duration, same_route.duration), "subdividing straight route must not change duration")
	for i in range(51):
		var t := path.duration * i / 50.0
		check(path.sample(t).position.distance_to(same_route.sample(t).position) < 0.001, "route samples must be independent of waypoint subdivision")
	path.build(Vector3.ZERO, [Vector3(2, 0, 0), Vector3(2, 0, 2)])
	check(path.sample(path.segments[1].time).speed < 2, "sharp turn must reduce speed")
	check(path.sample(path.duration).position == Vector3(2, 0, 2), "route endpoint must be exact")
	path.build(Vector3.ZERO, [Vector3.ZERO, Vector3.ZERO])
	check(path.duration == 0, "duplicate route points must be harmless")
	var unit := preload("res://scenes/main/prototype_unit.tscn").instantiate() as PrototypeUnit
	root.add_child(unit)
	unit.configure(Vector3i.ZERO, &"player", Color.CYAN)
	unit.robot_visual.set_cover(1, Vector3.BACK)
	unit.robot_visual.set_attack_pose(0, Vector3.ZERO, Vector3.ZERO)
	unit.footstep.connect(func(side: int, _point: Vector3) -> void: contacts.append(side))
	var hp := unit.current_hp
	var ap := unit.current_action_points
	_run_move(unit)
	await create_timer(0.08).timeout
	check(unit.position.is_zero_approx() and unit.is_moving, "leaving cover must rise before translation")
	var rig := unit.robot_visual.find_child("RobotRig", true, false) as Node3D
	check(rig.position.y > -0.30, "departure should blend out of crouch")
	while not completed:
		await process_frame
	check(unit.position == Vector3(3, 0, 0), "movement must finish at exact destination")
	check(unit.current_hp == hp and unit.current_action_points == ap, "presentation cannot change HP or AP")
	check(not unit.is_moving and not unit.robot_visual.locomotion_active, "arrival must release locomotion")
	check(unit.robot_visual.cover_level == 2 and rig.global_basis.z.dot(Vector3.RIGHT) > 0.99, "arrival must settle into destination cover")
	check(contacts.size() >= 4, "movement should emit distance-based contacts")
	for i in range(1, contacts.size()):
		check(contacts[i] != contacts[i - 1], "normal-rate contacts must alternate feet")
	await create_timer(0.4).timeout
	check(unit._footsteps.particles.is_empty(), "foot dust must expire after stopping")
	check(not unit.audio_move.playing, "movement audio must stop at arrival")
	contacts.clear()
	unit.hide()
	await unit.move_along_world_path([Vector3(4, 0, 0)], Vector3i(2, 0, 0))
	check(contacts.is_empty(), "hidden movement must emit no footsteps")
	unit.show()
	unit.move_along_world_path([Vector3(8, 0, 0)], Vector3i(4, 0, 0))
	await create_timer(0.1).timeout
	unit.cancel_movement()
	var stopped := unit.position
	await create_timer(0.2).timeout
	check(unit.position == stopped and not unit.is_moving, "canceled movement must not keep translating")
	check(unit._footsteps.particles.is_empty(), "cancel must clear dust")
	unit.free()
	for failure in failures:
		push_error(failure)
	print("UNIT_LOCOMOTION_TEST: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _run_move(unit: PrototypeUnit) -> void:
	await unit.move_along_world_path([Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)], Vector3i(1, 0, 0), {"level": 2, "direction": Vector3.BACK})
	completed = true

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
