extends Node3D

var units: Array[PrototypeUnit] = []
var effects: CombatVfx

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("101c29")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b6d1e8")
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -30, 0)
	light.light_energy = 2.0
	light.shadow_enabled = true
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 145, 0)
	fill.light_color = Color("85bfff")
	fill.light_energy = 0.7
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("253442")
	material.roughness = 0.85
	floor_mesh.material_override = material
	add_child(floor_mesh)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(5.2, 3.4, 7.2)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.6
	camera.current = true
	var weapons := ["assault_rifle", "shotgun", "carbine"]
	for i in range(3):
		var unit := preload("res://scenes/main/prototype_unit.tscn").instantiate() as PrototypeUnit
		add_child(unit)
		unit.position = Vector3((i - 1) * 2.0, 0, 0)
		unit.configure(Vector3i.ZERO, &"player" if i != 1 else &"enemy", Color("37b9be") if i != 1 else Color("f09a46"), null, load("res://resources/weapons/%s.tres" % weapons[i]))
		unit.robot_visual.face_direction(Vector2i(0, 1), true)
		unit.facing_marker.hide()
		for child in unit.find_children("*", "Label3D", true, false):
			child.hide()
		units.append(unit)
	effects = CombatVfx.new()
	add_child(effects)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var label := Label.new()
	label.position = Vector2(28, 24)
	label.text = "SENTINEL / FIELD SYSTEMS\n\n1 待机   2 行走   3 射击   4 受击   5 倒地\n6 枪火与命中   7 爆炸   8 转向"
	label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(label)
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.5).timeout
		if "--effects" in OS.get_cmdline_user_args():
			set_process(false)
			units[1].robot_visual.set_reaction(0.8, true)
			units[1].robot_visual.sync_weapon(units[1].weapon_pivot)
			effects.explosion(Vector3(0, 0, 1.6))
			effects.impact(Vector3(-2, 1.2, 0), Vector3.FORWARD, 0)
			effects.advance(0.18)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/sentinel-effects.png" if "--effects" in OS.get_cmdline_user_args() else "res://.godot/sentinel-preview.png")
		get_tree().quit()

func _process(delta: float) -> void:
	if effects != null:
		effects.advance(delta)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).physical_keycode
	if key >= KEY_1 and key <= KEY_5:
		var clips := [&"idle", &"walk", &"shoot", &"hit", &"death"]
		for unit in units:
			unit.robot_visual.preview_animation(clips[key - KEY_1])
	elif key == KEY_6:
		var unit := units[0]
		unit.play_attack_feedback()
		var source := unit.muzzle_flash.global_position
		var target := source + Vector3.FORWARD * -2.0
		effects.shot(source, target, 0.12)
		await get_tree().create_timer(0.12).timeout
		effects.impact(target, target - source, 0)
	elif key == KEY_7:
		effects.explosion(Vector3(0, 0, 2.5))
	elif key == KEY_8:
		for unit in units:
			unit.robot_visual.face_direction(Vector2i(1, 0))
