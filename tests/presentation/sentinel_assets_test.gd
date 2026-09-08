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
