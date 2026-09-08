extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var unit := preload("res://scenes/main/prototype_unit.tscn").instantiate() as PrototypeUnit
	root.add_child(unit)
	await process_frame
	unit.configure(Vector3i.ZERO, &"player", Color.CYAN, null, load("res://resources/weapons/assault_rifle.tres"))
	var robot := unit.robot_visual
	robot.set_process(false)
	for clip in [&"idle", &"walk", &"shoot", &"hit", &"death"]:
		check(robot.animation_player.has_animation(clip), "missing clip: " + clip)
	var initial := unit.global_transform
	var torso := robot.find_child("Torso", true, false) as Node3D
	var rest := torso.transform
	robot.set_reaction(1, true)
	check(unit.global_transform.is_equal_approx(initial), "death moved gameplay root")
	robot.reset_pose()
	check(torso.transform.is_equal_approx(rest), "joint pose not restored after death")
	robot.set_cover(1, Vector3.BACK)
	robot.set_attack_pose(0, Vector3.ZERO, Vector3(0, 1, 5))
	var rig := robot.find_child("RobotRig", true, false) as Node3D
	check(rig.position.y < -0.2, "low cover must lower silhouette")
	robot.set_attack_pose(1, Vector3(2, 0, 0), Vector3(0, 1, 5))
	robot.sync_weapon(unit.weapon_pivot)
	check(unit.global_transform.is_equal_approx(initial), "peek must not move gameplay root")
	check(rig.position.y > -0.01, "firing must rise above low cover")
	check(unit.weapon_pivot.global_basis.z.dot((Vector3(0, 1, 5) - unit.weapon_pivot.global_position).normalized()) > 0.999, "weapon must aim at target from peek position")
	robot.set_attack_pose(0, Vector3.ZERO, Vector3.ZERO)
	check(robot.position.is_zero_approx(), "return must clear peek displacement")
	robot.set_cover(2, Vector3.BACK)
	robot.set_attack_pose(0, Vector3.ZERO, Vector3.ZERO)
	check(absf(rig.rotation.y) > 1.0, "full cover must turn sideways")
	robot.set_cover(0, Vector3.BACK)
	robot.reset_pose()
	check((robot.find_child("LegL", true, false) as Node3D).rotation.is_zero_approx(), "leaving cover must restore legs")
	robot.set_reaction(1, true, Vector3.RIGHT)
	check(rig.position.x > 0.2, "right impact must fall right")
	robot.set_reaction(1, true, Vector3.LEFT)
	check(rig.position.x < -0.2, "left impact must fall left")
	robot.reset_pose()
	check(ImpactAudio.stream(&"normal").data != ImpactAudio.stream(&"armor").data, "normal and armor sounds must differ")
	check(ImpactAudio.stream(&"fatal").get_length() > ImpactAudio.stream(&"armor").get_length(), "fatal sound must have longer decay")
	var controller := PrototypeController.new()
	controller.grid = GridModel.new(Vector2i(3, 3))
	controller.cover_combat_settings = CoverCombatSettings.make_default()
	controller.units_by_id = {&"test": unit}
	var edge := MapEdgeData.new()
	edge.cell_a = Vector3i.ZERO
	edge.cell_b = Vector3i(1, 0, 0)
	edge.cover_a = TacticalEdgeRules.CoverLevel.HALF
	edge.cover_b = TacticalEdgeRules.CoverLevel.FULL
	controller.grid.edge_index.configure([edge])
	controller._refresh_cover_poses()
	check(robot.cover_level == 1, "pose must use the unit-facing edge profile")
	unit.grid_cell = edge.cell_b
	controller._refresh_cover_poses()
	check(robot.cover_level == 2, "opposite edge side must resolve its own profile")
	controller.grid.edge_index.configure([])
	controller._refresh_cover_poses()
	check(robot.cover_level == 0, "destroyed cover must clear pose")
	controller.free()
	for weapon in ["assault_rifle", "shotgun", "carbine"]:
		unit.set_weapon(load("res://resources/weapons/%s.tres" % weapon))
		robot.sync_weapon(unit.weapon_pivot)
		var muzzle := unit.weapon_model_root.find_child("Muzzle", true, false) as Node3D
		check(muzzle != null and muzzle.global_position.distance_to(unit.muzzle_flash.global_position) < 0.001, "muzzle mismatch: " + weapon)
	var vfx := CombatVfx.new()
	root.add_child(vfx)
	vfx.shot(Vector3.ZERO, Vector3(0, 0, 5), 0.1)
	await process_frame
	check(vfx.particles[0].age == 0, "particles advanced outside presentation clock")
	vfx.advance(0.025)
	check(is_equal_approx(vfx.particles[0].age, 0.025), "local clock not respected")
	for i in range(20):
		vfx.explosion(Vector3.ZERO)
	check(vfx.particles.size() <= vfx.particle_budget, "particle budget exceeded")
	vfx.clear()
	check(vfx.get_child_count() == 0 and vfx.particles.is_empty(), "effects leaked after clear")
	vfx.explosion(Vector3.ZERO)
	vfx.advance(2)
	check(vfx.particles.is_empty(), "particles did not expire")
	unit.free()
	vfx.free()
	for failure in failures:
		push_error(failure)
	print("SENTINEL_ASSETS_TEST: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
