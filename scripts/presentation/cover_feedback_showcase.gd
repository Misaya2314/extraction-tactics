extends "res://scripts/presentation/sentinel_showcase.gd"

var director: CombatPresentationDirector
var busy := false

func _ready() -> void:
	super._ready()
	# This stage demonstrates poses; the game controller supplies actual edge queries.
	units[0].robot_visual.set_cover(1, Vector3.BACK)
	units[1].robot_visual.set_cover(2, Vector3.BACK)
	units[0].position = Vector3(-3, 0, 0)
	units[2].position = Vector3(-2, 0, 4)
	for i in range(2):
		var cover := MeshInstance3D.new()
		var box := BoxMesh.new()
		var height := 0.85 if i == 0 else 1.8
		box.size = Vector3(1.25, height, 0.25)
		cover.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("456274")
		material.roughness = 0.8
		cover.material_override = material
		add_child(cover)
		cover.position = units[i].position + Vector3(0, height * 0.5, 0.9)
	var camera := get_viewport().get_camera_3d()
	camera.position = Vector3(6, 4.5, 8)
	camera.look_at(Vector3(-1, 0.7, 1.8))
	camera.size = 8.5
	for label in find_children("*", "Label", true, false):
		label.text = "COVER / COMBAT FEEDBACK\n\n1 低掩体起身射击   2 高掩体探出射击\n3 定向击杀与残骸   4 恢复目标   空格 / Esc 跳过"
	director = CombatPresentationDirector.new()
	add_child(director)
	director.mode = CombatPresentationDirector.Mode.OFF
	for child in director.get_children():
		if child is CanvasLayer:
			child.hide()
	if "--sequence-capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.5).timeout
		var event := InputEventKey.new()
		event.pressed = true
		event.physical_keycode = KEY_1
		_unhandled_key_input(event)
		await get_tree().create_timer(0.22).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/cover-shot.png")
		while busy:
			await get_tree().process_frame
		event.physical_keycode = KEY_3
		_unhandled_key_input(event)
		while busy:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/cover-remains.png")
		_restore_target()
		assert(director.remains.is_empty(), "Restoring target must remove remains")
		get_tree().quit()
	if "--cover-capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/cover-feedback.png")
		get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or busy:
		return
	var key := (event as InputEventKey).physical_keycode
	if key == KEY_4:
		_restore_target()
	elif key in [KEY_1, KEY_2, KEY_3]:
		busy = true
		_restore_target()
		var shooter := units[0] if key == KEY_1 else units[1]
		var target := units[2]
		shooter.look_at_cell(Vector3i(3, 0, 4))
		director.begin({0: shooter, 1: target}, null)
		target.take_damage(100 if key == KEY_3 else 1, false)
		await director.play(shooter, target.position, false, false, true, Vector3.LEFT * 1.3 if key != KEY_1 else Vector3.ZERO)
		busy = false

func _restore_target() -> void:
	var target := units[2]
	target.current_hp = target.max_hp
	target.visible = true
	target.process_mode = Node.PROCESS_MODE_INHERIT
	target.robot_visual.reset_pose()
	director.prune_remains()
