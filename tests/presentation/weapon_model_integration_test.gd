extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/main/prototype_unit.tscn")
const ASSAULT_RIFLE: WeaponDefinition = preload("res://resources/weapons/assault_rifle.tres")
const CARBINE: WeaponDefinition = preload("res://resources/weapons/carbine.tres")
const SHOTGUN: WeaponDefinition = preload("res://resources/weapons/shotgun.tres")

const EXPECTED_MODEL_PATHS := {
	&"assault_rifle": "res://kenney_blaster-kit_2.1/Models/GLB format/blaster-e.glb",
	&"carbine": "res://kenney_blaster-kit_2.1/Models/GLB format/blaster-n.glb",
	&"shotgun": "res://kenney_blaster-kit_2.1/Models/GLB format/blaster-l.glb",
}

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_authored_models()
	await _test_runtime_replacement_and_missing_model()
	await _test_feedback_follows_model_and_resets()
	await _test_exit_tree_resets_feedback()
	_finish()


func _test_authored_models() -> void:
	var rifle := await _spawn_unit("PlayerAlpha", &"player", Vector3i(1, 0, 1), ASSAULT_RIFLE)
	var carbine := await _spawn_unit("EnemyRifleman", &"enemy", Vector3i(4, 0, 1), CARBINE)
	var shotgun := await _spawn_unit("PlayerBravo", &"player", Vector3i(1, 0, 4), SHOTGUN)
	_assert_model(rifle, ASSAULT_RIFLE, "PlayerAlpha rifle")
	_assert_model(carbine, CARBINE, "EnemyRifleman carbine")
	_assert_model(shotgun, SHOTGUN, "PlayerBravo shotgun")
	_expect(rifle.attack_damage == 4 and rifle.attack_range == 5 and rifle.attack_ap_cost == 1, "content: rifle combat values should remain unchanged")
	_expect(carbine.attack_damage == 3 and carbine.attack_range == 7 and carbine.attack_ap_cost == 1, "content: carbine combat values should remain unchanged")
	_expect(shotgun.attack_damage == 5 and shotgun.attack_range == 3 and shotgun.attack_ap_cost == 1, "content: shotgun combat values should remain unchanged")
	await _free_unit(rifle)
	await _free_unit(carbine)
	await _free_unit(shotgun)


func _test_runtime_replacement_and_missing_model() -> void:
	var unit := await _spawn_unit("RuntimeWeaponUnit", &"player", Vector3i(2, 0, 2), ASSAULT_RIFLE)
	var old_model := _current_model(unit)
	_expect(old_model != null, "replacement: initial rifle model should exist")
	unit.set_weapon(SHOTGUN)
	await process_frame
	var new_model := _current_model(unit)
	_assert_model(unit, SHOTGUN, "replacement shotgun")
	_expect(new_model != old_model, "replacement: set_weapon should replace the model instance")
	_expect(not is_instance_valid(old_model), "replacement: old model should be freed immediately")

	unit.set_weapon(null)
	await process_frame
	var model_root := unit.get_node("VisualRoot/WeaponPivot/WeaponModelRoot") as Node3D
	_expect(model_root != null and model_root.get_child_count() == 0, "replacement: null weapon should leave model root empty")
	_expect(unit.attack_damage == 0 and unit.attack_range == 0 and unit.attack_ap_cost == 1, "replacement: explicit null weapon should be unable to attack without a free AP action")
	var play_count_before := unit.attack_feedback_play_count
	await unit.play_attack_feedback()
	_expect(unit.attack_feedback_play_count == play_count_before and not unit.is_attack_feedback_playing, "replacement: missing model/profile should be safe")

	unit.set_weapon(CARBINE)
	await process_frame
	_assert_model(unit, CARBINE, "replacement carbine")
	_expect(unit.attack_damage == 3 and unit.attack_range == 7 and unit.attack_ap_cost == 1, "replacement: assigning a new weapon should restore its authored combat values")
	await _free_unit(unit)


func _test_feedback_follows_model_and_resets() -> void:
	var unit := await _spawn_unit("FeedbackModelUnit", &"player", Vector3i(3, 0, 2), SHOTGUN)
	var model := _current_model(unit)
	var weapon_pivot := unit.get_node("VisualRoot/WeaponPivot") as Node3D
	var muzzle_flash := unit.get_node("VisualRoot/WeaponPivot/MuzzleFlash") as MeshInstance3D
	var root_position := unit.global_position
	var pivot_rest_position := weapon_pivot.position
	var pivot_rest_rotation := weapon_pivot.rotation
	var model_rest_position := model.global_position
	var play_count_before := unit.attack_feedback_play_count
	unit.play_attack_feedback()
	var model_moved := false
	var pivot_moved := false
	for _frame in range(24):
		await process_frame
		model_moved = model_moved or not model.global_position.is_equal_approx(model_rest_position)
		pivot_moved = pivot_moved or not weapon_pivot.position.is_equal_approx(pivot_rest_position)
	_expect(model_moved, "feedback: weapon model should follow WeaponPivot recoil")
	_expect(pivot_moved, "feedback: WeaponPivot should move during recoil")
	_expect(muzzle_flash.visible, "feedback: muzzle flash should be visible during shotgun feedback")
	_expect(unit.global_position.is_equal_approx(root_position), "feedback: model feedback must not move unit root")
	await unit.attack_feedback_finished
	_expect(unit.attack_feedback_play_count == play_count_before + 1, "feedback: one playback should count once")
	_expect(unit.global_position.is_equal_approx(root_position), "feedback: root should remain at its grid position after playback")
	_expect(weapon_pivot.position.is_equal_approx(pivot_rest_position), "feedback: WeaponPivot position should reset")
	_expect(weapon_pivot.rotation.is_equal_approx(pivot_rest_rotation), "feedback: WeaponPivot rotation should reset")
	_expect(model.global_position.is_equal_approx(model_rest_position), "feedback: model should return with WeaponPivot")
	_expect(not muzzle_flash.visible, "feedback: muzzle flash should hide after playback")

	unit.play_attack_feedback()
	await process_frame
	unit.play_attack_feedback()
	await unit.attack_feedback_finished
	_expect(unit.attack_feedback_play_count == play_count_before + 3, "feedback: interrupted playback should start a fresh generation")
	_expect(unit.global_position.is_equal_approx(root_position), "feedback: interrupted playback must not move root")
	_expect(model.global_position.is_equal_approx(model_rest_position), "feedback: interrupted playback should reset model")
	await _free_unit(unit)


func _test_exit_tree_resets_feedback() -> void:
	var unit := await _spawn_unit("ExitTreeWeaponUnit", &"player", Vector3i(5, 0, 2), ASSAULT_RIFLE)
	var model := _current_model(unit)
	unit.play_attack_feedback()
	await process_frame
	_expect(unit.is_attack_feedback_playing, "exit tree: feedback should be active before removal")
	get_root().remove_child(unit)
	_expect(not unit.is_attack_feedback_playing, "exit tree: feedback state should reset on removal")
	_expect(model != null and model.get_parent() == unit.get_node("VisualRoot/WeaponPivot/WeaponModelRoot"), "exit tree: model hierarchy should remain owned by the unit")
	unit.queue_free()
	await process_frame


func _spawn_unit(unit_name: String, faction: StringName, cell: Vector3i, weapon: WeaponDefinition) -> PrototypeUnit:
	var unit := UNIT_SCENE.instantiate() as PrototypeUnit
	unit.name = unit_name
	unit.configure(cell, faction, Color("4f9dff") if faction == &"player" else Color("ff6b6b"), null, weapon)
	get_root().add_child(unit)
	unit.global_position = Vector3(cell.x * 2.0, 0.0, cell.z * 2.0)
	await process_frame
	return unit


func _assert_model(unit: PrototypeUnit, weapon: WeaponDefinition, label: String) -> void:
	var model_root := unit.get_node_or_null("VisualRoot/WeaponPivot/WeaponModelRoot") as Node3D
	_expect(model_root != null, "%s: WeaponModelRoot should exist" % label)
	if model_root == null:
		return
	_expect(model_root.get_child_count() == 1, "%s: WeaponModelRoot should contain exactly one model" % label)
	if model_root.get_child_count() != 1:
		return
	var model := model_root.get_child(0) as Node3D
	_expect(model != null, "%s: current model should be Node3D" % label)
	if model == null:
		return
	_expect(model.scene_file_path == EXPECTED_MODEL_PATHS[weapon.weapon_id], "%s: scene_file_path should match WeaponDefinition" % label)
	_expect(model.position.is_equal_approx(weapon.world_model_position), "%s: model position should use resource data" % label)
	_expect(model.rotation_degrees.is_equal_approx(weapon.world_model_rotation_degrees), "%s: model rotation should use resource data" % label)
	_expect(model.scale.is_equal_approx(weapon.world_model_scale), "%s: model scale should use resource data" % label)
	var muzzle_flash := unit.get_node("VisualRoot/WeaponPivot/MuzzleFlash") as MeshInstance3D
	_expect(muzzle_flash.position.is_equal_approx(weapon.muzzle_position), "%s: muzzle position should use resource data" % label)
	_expect(not _contains_collision_object(model), "%s: model hierarchy must not contain CollisionObject3D" % label)
	var aabb_size := _world_aabb_size(model)
	print("WEAPON_MODEL_AABB: %s path=%s size=%s transform_pos=%s scale=%s muzzle=%s" % [label, model.scene_file_path, aabb_size, model.position, model.scale, muzzle_flash.position])
	_expect(aabb_size.z > 0.6 and aabb_size.z < 0.9, "%s: authored model length should be approximately 0.7-0.8 on +Z" % label)


func _current_model(unit: PrototypeUnit) -> Node3D:
	var model_root := unit.get_node_or_null("VisualRoot/WeaponPivot/WeaponModelRoot") as Node3D
	if model_root == null or model_root.get_child_count() != 1:
		return null
	return model_root.get_child(0) as Node3D


func _contains_collision_object(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	for child in node.get_children():
		if _contains_collision_object(child):
			return true
	return false


func _world_aabb_size(model: Node3D) -> Vector3:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	if meshes.is_empty():
		return Vector3.ZERO
	var minimum := Vector3(1.0e20, 1.0e20, 1.0e20)
	var maximum := Vector3(-1.0e20, -1.0e20, -1.0e20)
	for mesh_instance in meshes:
		var local_aabb := mesh_instance.get_aabb()
		for x in [local_aabb.position.x, local_aabb.end.x]:
			for y in [local_aabb.position.y, local_aabb.end.y]:
				for z in [local_aabb.position.z, local_aabb.end.z]:
					var point := mesh_instance.global_transform * Vector3(x, y, z)
					minimum.x = minf(minimum.x, point.x)
					minimum.y = minf(minimum.y, point.y)
					minimum.z = minf(minimum.z, point.z)
					maximum.x = maxf(maximum.x, point.x)
					maximum.y = maxf(maximum.y, point.y)
					maximum.z = maxf(maximum.z, point.z)
	return maximum - minimum


func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, meshes)


func _free_unit(unit: PrototypeUnit) -> void:
	if is_instance_valid(unit):
		unit.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("WEAPON_MODEL_INTEGRATION_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WEAPON_MODEL_INTEGRATION_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
