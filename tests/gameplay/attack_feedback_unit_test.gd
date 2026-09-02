extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/main/prototype_unit.tscn")
const ASSAULT_RIFLE: WeaponDefinition = preload("res://resources/weapons/assault_rifle.tres")
const SHOTGUN: WeaponDefinition = preload("res://resources/weapons/shotgun.tres")

var _failures: Array[String] = []
var _started_count := 0
var _finished_count := 0
var _started_profiles: Array[StringName] = []
var _finished_profiles: Array[StringName] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_authored_profiles()
	await _test_runtime_feedback()
	await _test_exit_tree_cancels_feedback()
	await _test_missing_feedback_is_safe()
	_finish()


func _test_authored_profiles() -> void:
	_expect(ASSAULT_RIFLE.attack_feedback_profile != null, "profile: assault rifle profile should be authored")
	_expect(SHOTGUN.attack_feedback_profile != null, "profile: shotgun profile should be authored")
	if ASSAULT_RIFLE.attack_feedback_profile == null or SHOTGUN.attack_feedback_profile == null:
		return
	var rifle := ASSAULT_RIFLE.attack_feedback_profile
	var shotgun := SHOTGUN.attack_feedback_profile
	_expect(rifle.profile_id == &"rifle", "profile: rifle ID should be stable")
	_expect(shotgun.profile_id == &"shotgun", "profile: shotgun ID should be stable")
	_expect(SHOTGUN.ap_cost == 1, "profile: shotgun AP must remain one")
	_expect(shotgun.recoil_distance > rifle.recoil_distance, "profile: shotgun recoil distance should be larger")
	_expect(shotgun.weapon_kick_degrees > rifle.weapon_kick_degrees, "profile: shotgun weapon kick should be larger")
	_expect(shotgun.muzzle_flash_scale > rifle.muzzle_flash_scale, "profile: shotgun muzzle flash should be larger")
	_expect(shotgun.total_duration() > rifle.total_duration(), "profile: shotgun total duration should be longer")


func _test_runtime_feedback() -> void:
	var unit := UNIT_SCENE.instantiate() as PrototypeUnit
	get_root().add_child(unit)
	await process_frame
	unit.configure(Vector3i(2, 0, 3), &"player", Color("4f9dff"), null, ASSAULT_RIFLE)
	unit.global_position = Vector3(4.0, 0.0, 6.0)
	unit.attack_feedback_started.connect(_on_feedback_started)
	unit.attack_feedback_finished.connect(_on_feedback_finished)

	var visual_root := unit.get_node("VisualRoot") as Node3D
	var weapon_pivot := unit.get_node("VisualRoot/WeaponPivot") as Node3D
	var weapon_model_root := unit.get_node("VisualRoot/WeaponPivot/WeaponModelRoot") as Node3D
	var muzzle_flash := unit.get_node("VisualRoot/WeaponPivot/MuzzleFlash") as MeshInstance3D
	_expect(visual_root != null, "scene: VisualRoot should exist")
	_expect(weapon_pivot != null, "scene: WeaponPivot should exist")
	_expect(weapon_model_root != null, "scene: WeaponModelRoot should exist")
	_expect(muzzle_flash != null, "scene: MuzzleFlash should exist")
	if weapon_model_root != null:
		_expect(weapon_model_root.get_child_count() == 1, "scene: configured weapon should instantiate one model")
	if visual_root == null or weapon_pivot == null or weapon_model_root == null or muzzle_flash == null:
		await _free_unit(unit)
		return

	var root_position := unit.global_position
	var visual_rest_position := visual_root.position
	var visual_rest_rotation := visual_root.rotation
	var visual_rest_scale := visual_root.scale
	var pivot_rest_position := weapon_pivot.position
	var pivot_rest_rotation := weapon_pivot.rotation
	var pivot_rest_scale := weapon_pivot.scale
	var play_count_before := unit.attack_feedback_play_count
	unit.play_attack_feedback()
	await process_frame
	_expect(unit.is_attack_feedback_playing, "runtime: feedback should report active during playback")
	_expect(muzzle_flash.visible, "runtime: muzzle flash should be visible during playback")
	_expect(unit.global_position.is_equal_approx(root_position), "runtime: active feedback must not move unit root")
	await unit.attack_feedback_finished
	_expect(_started_count == 1 and _finished_count == 1, "runtime: one feedback should emit start and finish once")
	_expect(_started_profiles == [&"rifle"] and _finished_profiles == [&"rifle"], "runtime: signal profile IDs should match")
	_expect(unit.attack_feedback_play_count == play_count_before + 1, "runtime: one feedback should increment play count once")
	_expect(not unit.is_attack_feedback_playing, "runtime: feedback should be idle after await")
	_expect(unit.last_attack_feedback_profile_id == &"rifle", "runtime: last profile ID should be observable")
	_expect(is_equal_approx(unit.last_attack_feedback_duration, ASSAULT_RIFLE.attack_feedback_profile.total_duration()), "runtime: duration should be observable")
	_expect(unit.global_position.is_equal_approx(root_position), "runtime: attack feedback must not move unit root")
	_expect(visual_root.position.is_equal_approx(visual_rest_position), "runtime: VisualRoot position should reset")
	_expect(visual_root.rotation.is_equal_approx(visual_rest_rotation), "runtime: VisualRoot rotation should reset")
	_expect(visual_root.scale.is_equal_approx(visual_rest_scale), "runtime: VisualRoot scale should reset")
	_expect(weapon_pivot.position.is_equal_approx(pivot_rest_position), "runtime: WeaponPivot position should reset")
	_expect(weapon_pivot.rotation.is_equal_approx(pivot_rest_rotation), "runtime: WeaponPivot rotation should reset")
	_expect(weapon_pivot.scale.is_equal_approx(pivot_rest_scale), "runtime: WeaponPivot scale should reset")
	_expect(not muzzle_flash.visible, "runtime: muzzle flash should be hidden after feedback")

	_started_count = 0
	_finished_count = 0
	_started_profiles.clear()
	_finished_profiles.clear()
	unit.play_attack_feedback()
	await process_frame
	await unit.play_attack_feedback()
	_expect(_started_count == 2 and _finished_count == 2, "runtime: interrupted feedback should finish before restart without duplication")
	_expect(unit.attack_feedback_play_count == play_count_before + 3, "runtime: continuous feedback should count each restart")
	_expect(unit.global_position.is_equal_approx(root_position), "runtime: interrupted feedback must not drift root")
	_expect(visual_root.position.is_equal_approx(visual_rest_position), "runtime: interrupted feedback should reset VisualRoot")
	_expect(weapon_pivot.position.is_equal_approx(pivot_rest_position), "runtime: interrupted feedback should reset WeaponPivot")
	_expect(not muzzle_flash.visible, "runtime: interrupted feedback should hide muzzle flash")
	await _free_unit(unit)


func _test_missing_feedback_is_safe() -> void:
	var unit := UNIT_SCENE.instantiate() as PrototypeUnit
	get_root().add_child(unit)
	await process_frame
	_expect(unit.attack_damage == 4 and unit.attack_range == 5 and unit.attack_ap_cost == 1, "safe fallback: initial scene combat defaults should remain unchanged")
	unit.configure(Vector3i.ZERO, &"player", Color.WHITE)
	unit.play_attack_feedback()
	await process_frame
	_expect(not unit.is_attack_feedback_playing, "safe fallback: missing weapon/profile should finish immediately")
	_expect(unit.attack_feedback_play_count == 0, "safe fallback: missing profile should not count a visual play")
	await _free_unit(unit)


func _test_exit_tree_cancels_feedback() -> void:
	_started_count = 0
	_finished_count = 0
	_started_profiles.clear()
	_finished_profiles.clear()
	var unit := UNIT_SCENE.instantiate() as PrototypeUnit
	get_root().add_child(unit)
	await process_frame
	unit.configure(Vector3i(3, 0, 2), &"player", Color("4f9dff"), null, ASSAULT_RIFLE)
	unit.global_position = Vector3(6.0, 0.0, 4.0)
	unit.attack_feedback_started.connect(_on_feedback_started)
	unit.attack_feedback_finished.connect(_on_feedback_finished)
	var visual_root := unit.get_node("VisualRoot") as Node3D
	var weapon_pivot := unit.get_node("VisualRoot/WeaponPivot") as Node3D
	var muzzle_flash := unit.get_node("VisualRoot/WeaponPivot/MuzzleFlash") as MeshInstance3D
	var root_position := unit.global_position
	var visual_rest_position := visual_root.position
	var visual_rest_rotation := visual_root.rotation
	var visual_rest_scale := visual_root.scale
	var pivot_rest_position := weapon_pivot.position
	var pivot_rest_rotation := weapon_pivot.rotation
	var pivot_rest_scale := weapon_pivot.scale
	var root_local_position := unit.position

	unit.play_attack_feedback()
	await process_frame
	_expect(unit.is_attack_feedback_playing, "exit tree: feedback should be active before removal")
	_expect(muzzle_flash.visible, "exit tree: muzzle flash should be visible before removal")
	get_root().remove_child(unit)
	_expect(not unit.is_inside_tree(), "exit tree: unit should leave the scene tree")
	_expect(not unit.is_attack_feedback_playing, "exit tree: feedback state should be reset")
	_expect(unit.position.is_equal_approx(root_local_position), "exit tree: root position should remain unchanged")
	_expect(visual_root.position.is_equal_approx(visual_rest_position), "exit tree: VisualRoot position should reset")
	_expect(visual_root.rotation.is_equal_approx(visual_rest_rotation), "exit tree: VisualRoot rotation should reset")
	_expect(visual_root.scale.is_equal_approx(visual_rest_scale), "exit tree: VisualRoot scale should reset")
	_expect(weapon_pivot.position.is_equal_approx(pivot_rest_position), "exit tree: WeaponPivot position should reset")
	_expect(weapon_pivot.rotation.is_equal_approx(pivot_rest_rotation), "exit tree: WeaponPivot rotation should reset")
	_expect(weapon_pivot.scale.is_equal_approx(pivot_rest_scale), "exit tree: WeaponPivot scale should reset")
	_expect(not muzzle_flash.visible, "exit tree: muzzle flash should be hidden")
	_expect(_finished_count == 0, "exit tree: teardown should not emit finished feedback")

	get_root().add_child(unit)
	await process_frame
	unit.set_weapon(SHOTGUN)
	unit.play_attack_feedback()
	await process_frame
	_expect(unit.is_attack_feedback_playing, "exit tree: re-entered unit should start new feedback")
	await create_timer(0.25).timeout
	_expect(unit.is_attack_feedback_playing, "exit tree: old timer must not finish new feedback")
	_expect(_finished_count == 0, "exit tree: old timer must not emit finished feedback")
	await unit.attack_feedback_finished
	_expect(_finished_count == 1 and _finished_profiles == [&"shotgun"], "exit tree: only new feedback should finish")
	_expect(not unit.is_attack_feedback_playing, "exit tree: new feedback should finish normally")
	_expect(unit.global_position.is_equal_approx(root_position), "exit tree: re-entry must not move root")
	_expect(visual_root.position.is_equal_approx(visual_rest_position), "exit tree: re-entry VisualRoot should reset")
	_expect(visual_root.rotation.is_equal_approx(visual_rest_rotation), "exit tree: re-entry VisualRoot rotation should reset")
	_expect(visual_root.scale.is_equal_approx(visual_rest_scale), "exit tree: re-entry VisualRoot scale should reset")
	_expect(weapon_pivot.position.is_equal_approx(pivot_rest_position), "exit tree: re-entry WeaponPivot should reset")
	_expect(weapon_pivot.rotation.is_equal_approx(pivot_rest_rotation), "exit tree: re-entry WeaponPivot rotation should reset")
	_expect(weapon_pivot.scale.is_equal_approx(pivot_rest_scale), "exit tree: re-entry WeaponPivot scale should reset")
	_expect(not muzzle_flash.visible, "exit tree: re-entry muzzle flash should be hidden")
	await _free_unit(unit)


func _on_feedback_started(_unit: PrototypeUnit, profile_id: StringName) -> void:
	_started_count += 1
	_started_profiles.append(profile_id)


func _on_feedback_finished(_unit: PrototypeUnit, profile_id: StringName) -> void:
	_finished_count += 1
	_finished_profiles.append(profile_id)


func _free_unit(unit: PrototypeUnit) -> void:
	unit.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("ATTACK_FEEDBACK_UNIT_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ATTACK_FEEDBACK_UNIT_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
