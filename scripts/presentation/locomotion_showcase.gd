extends "res://scripts/presentation/sentinel_showcase.gd"

var busy := false

func _ready() -> void:
	super._ready()
	units[1].hide()
	units[2].hide()
	units[0].position = Vector3(-3, 0, 0)
	for i in range(2):
		var cover := MeshInstance3D.new()
		var box := BoxMesh.new()
		var height := 0.85 if i == 0 else 1.8
		box.size = Vector3(1.4, height, 0.3)
		cover.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("456274")
		cover.material_override = material
		add_child(cover)
		cover.position = Vector3(-3 if i == 0 else 3, height / 2, 0.9)
	units[0].robot_visual.set_cover(1, Vector3.BACK)
	var camera := get_viewport().get_camera_3d()
	camera.position = Vector3(7, 5, -9)
	camera.look_at(Vector3(0, 0.7, 0))
	camera.size = 9
	for label in find_children("*", "Label", true, false):
		label.text = "LOCOMOTION / COVER\n\n1 移至高掩体   2 返回低掩体\n起身 → 连续移动与脚步 → 减速入掩体"
	if "--locomotion-capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.5).timeout
		_move(true)
		await get_tree().create_timer(0.8).timeout
		await _capture("stride")
		while busy:
			await get_tree().process_frame
		await _capture("high-cover")
		await _move(false)
		await _capture("low-cover")
		get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if busy or not event.is_pressed() or event.is_echo() or not event is InputEventKey:
		return
	if event.physical_keycode in [KEY_1, KEY_2]:
		_move(event.physical_keycode == KEY_1)

func _move(to_high: bool) -> void:
	busy = true
	var destination := Vector3(3 if to_high else -3, 0, 0)
	var points: Array[Vector3] = [Vector3(0, 0, 0), destination]
	await units[0].move_along_world_path(points, Vector3i.ZERO, {"level": 2 if to_high else 1, "direction": Vector3.BACK})
	busy = false

func _capture(suffix: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/locomotion-%s.png" % suffix)
