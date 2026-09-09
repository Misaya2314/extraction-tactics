extends "res://scripts/presentation/sentinel_showcase.gd"

var wall: MeshInstance3D

func _ready() -> void:
	super._ready()
	var camera := get_viewport().get_camera_3d()
	camera.position = Vector3(0, 2.8, 9)
	camera.look_at(Vector3(0, 0.9, 0))
	camera.size = 8
	wall = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(7, 2.7, 0.35)
	wall.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("354757")
	wall.material_override = material
	add_child(wall)
	wall.position = Vector3(0, 1.35, 1.5)
	units[0].set_selected(true)
	for label in find_children("*", "Label", true, false):
		label.text = "OCCLUSION / VISIBILITY\n\n1 切换遮挡墙   2 隐藏/显示敌人   3 切换选中单位\n左：选中友军   中：已发现敌人   右：普通友军"
	if "--occlusion-capture" in OS.get_cmdline_user_args():
		await _capture("blocked")
		units[1].hide()
		await _capture("hidden")
		units[1].show()
		wall.scale.y = 0.38
		wall.position.y = 1.35 * 0.38
		await _capture("partial")
		wall.hide()
		units[1].show()
		await _capture("clear")
		get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	match event.physical_keycode:
		KEY_1:
			wall.visible = not wall.visible
		KEY_2:
			units[1].visible = not units[1].visible
		KEY_3:
			units[0].set_selected(not units[0].selection_marker.visible)

func _capture(suffix: String) -> void:
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/occlusion-%s.png" % suffix)
