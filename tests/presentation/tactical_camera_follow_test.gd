extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var rig := preload("res://scenes/presentation/tactical_camera_rig.tscn").instantiate() as TacticalCameraRig
	root.add_child(rig)
	rig.set_map_bounds(Vector2(-50, -50), Vector2(50, 50))
	rig.set_process(false)
	rig.focus_world_position(Vector3.ZERO, true)
	var actor := Node3D.new()
	root.add_child(actor)
	var rest := rig.global_position
	rig.set_focus_target(actor)
	check(rig.global_position == rest and not rig._focus_active, "selecting on-screen actor should not recenter")
	rig.begin_movement(actor)
	actor.position.x = 0.5
	rig._update_automatic_camera(0.1)
	check(rig.global_position == rest, "short central movement should keep camera still")
	actor.position.x = 15
	rig._update_automatic_camera(0.1)
	check(rig.position.x > 0 and rig.position.x < 15, "offscreen movement should smoothly follow")
	check(rig._look_ahead.x > 0, "follow must leave space ahead")
	rig.take_manual_control()
	rest = rig.position
	actor.position.x = 20
	rig._update_automatic_camera(0.1)
	check(rig.position == rest, "manual control must suspend tracking")
	var home := InputEventKey.new()
	home.keycode = KEY_HOME
	home.pressed = true
	rig._unhandled_input(home)
	check(not rig.manual_override and rig._focus_active, "Home must restore focus")
	rig._update_automatic_camera(0.1)
	check(rig.position.x > rest.x and rig.position.x < actor.position.x, "refocus must interpolate")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	var zoom_before := rig._target_zoom
	rig._unhandled_input(wheel)
	check(rig.manual_override and rig._target_zoom < zoom_before, "wheel must zoom and take control")
	rig.end_movement(actor)
	check(not rig._focus_active, "finishing movement must respect manual control")
	var drag := InputEventMouseButton.new()
	drag.button_index = MOUSE_BUTTON_MIDDLE
	drag.pressed = true
	rig._unhandled_input(drag)
	rest = rig.position
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(640, 400)
	motion.relative = Vector2(40, 0)
	rig._unhandled_input(motion)
	check(rig.manual_override and not rig.position.is_equal_approx(rest), "middle drag must pan immediately")
	drag.pressed = false
	rig._input(drag)
	check(not rig._dragging, "release over UI must terminate dragging")
	rig.begin_movement(actor)
	rig._follow_engaged = true
	rig.end_movement(actor)
	check(rig._focus_active, "tracked movement should settle at destination")
	var frame := rig.begin_cinematic()
	rig.camera.position += Vector3(3, 2, 1)
	rig._update_automatic_camera(1)
	rig.end_cinematic(frame)
	rig._process(0.016)
	check(rig.camera.global_transform.is_equal_approx(frame), "cinematic return must not drift on next frame")
	check(not rig._focus_active and rig.moving_target == null, "cinematic must cancel stale tracking")
	actor.hide()
	rig.begin_movement(actor)
	check(rig.moving_target == null, "hidden units must not attract camera")
	actor.show()
	rig.begin_movement(actor)
	actor.free()
	rig._update_automatic_camera(0.1)
	check(rig.moving_target == null, "removed target must release tracking")
	rig.focus_world_position(Vector3(100, 0, 100))
	for i in range(30):
		rig._update_automatic_camera(0.1)
	check(rig.position.x <= 47 and rig.position.z <= 47 and not rig._focus_active, "focus must settle within map bounds")
	rig.free()
	for failure in failures:
		push_error(failure)
	print("TACTICAL_CAMERA_FOLLOW_TEST: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
