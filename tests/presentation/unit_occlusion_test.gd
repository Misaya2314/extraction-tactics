extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := preload("res://scenes/main/prototype_unit.tscn")
	var unit := scene.instantiate() as PrototypeUnit
	var other := scene.instantiate() as PrototypeUnit
	root.add_child(unit)
	root.add_child(other)
	unit.configure(Vector3i.ZERO, &"player", Color.CYAN)
	other.configure(Vector3i.ONE, &"enemy", Color.ORANGE)
	assert(unit._occlusion_material != other._occlusion_material)
	var meshes := unit.robot_visual.find_children("*", "MeshInstance3D", true, false)
	assert(not meshes.is_empty())
	for mesh in meshes:
		assert(mesh.material_overlay == unit._occlusion_material)
	unit.set_selected(true)
	assert(unit._occlusion_material.get_shader_parameter("emphasis") == 1.0)
	assert(other._occlusion_material.get_shader_parameter("emphasis") == 0.0)
	unit.hide()
	for mesh in meshes:
		assert(not mesh.is_visible_in_tree(), "fog-hidden actor must not render an overlay")
	unit.show()
	unit._refresh_weapon_model()
	for mesh in unit.weapon_model_root.find_children("*", "MeshInstance3D", true, false):
		assert(mesh.material_overlay == unit._occlusion_material)
	unit.take_damage(100, false)
	assert(not unit._occlusion_material.get_shader_parameter("active"))
	unit.free()
	other.free()
	await process_frame
	print("UNIT_OCCLUSION_TEST: PASS")
	quit()
