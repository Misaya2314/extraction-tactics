extends SceneTree

## Pure input-policy coverage.  This deliberately never instantiates
## EditorPlugin; ordinary headless runs can therefore exercise the same
## classification used by the 3D editor hook.

const Strategy := preload("res://addons/tactical_map_editor/editing/tactical_map_input_strategy.gd")
const SessionScript := preload("res://addons/tactical_map_editor/editing/map_edit_session.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_edit_toggle_key()
	_test_native_navigation_pass_policy()
	_test_left_button_policy()
	_test_camera_pan_helpers()
	_finish()


func _test_edit_toggle_key() -> void:
	var toggle := _key(KEY_M, KEY_M)
	_expect(Strategy.classify_key(toggle, true, false) == Strategy.Action.TOGGLE_EDIT_MODE, "input: unmodified physical M should toggle edit mode with an active author")
	_expect(Strategy.classify_key(toggle, true, true) == Strategy.Action.TOGGLE_EDIT_MODE, "input: unmodified physical M should also toggle edit mode off")
	_expect(Strategy.classify_key(toggle, false, false) == Strategy.Action.PASS, "input: M without an active author must remain native")
	var modified := _key(KEY_M, KEY_M)
	modified.shift_pressed = true
	_expect(Strategy.classify_key(modified, true, false) == Strategy.Action.PASS, "input: Shift+M must not toggle edit mode")
	modified = _key(KEY_M, KEY_M)
	modified.ctrl_pressed = true
	_expect(Strategy.classify_key(modified, true, true) == Strategy.Action.PASS, "input: Ctrl+M must not toggle edit mode")
	var echoed := _key(KEY_M, KEY_M)
	echoed.echo = true
	_expect(Strategy.classify_key(echoed, true, false) == Strategy.Action.PASS, "input: echoed M must not toggle edit mode")
	_expect(Strategy.classify_key(_key(KEY_R, KEY_R), false, false) == Strategy.Action.PASS, "input: R outside edit mode must pass")
	_expect(Strategy.classify_key(_key(KEY_R, KEY_R), true, true) == Strategy.Action.ROTATE, "input: R in edit mode should rotate the selected material")


func _test_native_navigation_pass_policy() -> void:
	var right_press := _mouse_button(MOUSE_BUTTON_RIGHT, true)
	var right_release := _mouse_button(MOUSE_BUTTON_RIGHT, false)
	var middle_press := _mouse_button(MOUSE_BUTTON_MIDDLE, true)
	_expect(Strategy.classify_mouse_button(right_press, true, SessionScript.Tool.PAINT, SessionScript.Tool.SELECT, SessionScript.Tool.PICK) == Strategy.Action.NATIVE_NAVIGATION, "input: RMB press must be classified as native navigation")
	_expect(Strategy.classify_mouse_button(right_release, true, SessionScript.Tool.PAINT, SessionScript.Tool.SELECT, SessionScript.Tool.PICK) == Strategy.Action.NATIVE_NAVIGATION, "input: RMB release must be classified as native navigation")
	_expect(Strategy.classify_mouse_button(middle_press, true, SessionScript.Tool.PAINT, SessionScript.Tool.SELECT, SessionScript.Tool.PICK) == Strategy.Action.NATIVE_NAVIGATION, "input: MMB must remain native navigation")
	_expect(Strategy.is_native_navigation_event(right_press), "input: RMB press should be native-passable")
	_expect(Strategy.is_native_navigation_event(right_release), "input: RMB release should be native-passable")
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	_expect(Strategy.is_native_navigation_event(motion), "input: mouse motion during RMB navigation should be native-passable")
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	_expect(Strategy.is_native_navigation_event(motion), "input: mouse motion during MMB navigation should be native-passable")
	_expect(Strategy.classify_key(_key(KEY_W, KEY_W), true, true) == Strategy.Action.CAMERA_PAN_FORWARD, "input: W in edit mode should pan camera forward")
	_expect(Strategy.classify_key(_key(KEY_A, KEY_A), true, true) == Strategy.Action.CAMERA_PAN_LEFT, "input: A in edit mode should pan camera left")
	_expect(Strategy.classify_key(_key(KEY_S, KEY_S), true, true) == Strategy.Action.CAMERA_PAN_BACKWARD, "input: S in edit mode should pan camera backward")
	_expect(Strategy.classify_key(_key(KEY_D, KEY_D), true, true) == Strategy.Action.CAMERA_PAN_RIGHT, "input: D in edit mode should pan camera right")
	_expect(Strategy.classify_key(_key(KEY_W, KEY_W), true, false) == Strategy.Action.PASS, "input: W outside edit mode must remain native pass")
	_expect(Strategy.classify_key(_key(KEY_S, KEY_S), true, false) == Strategy.Action.PASS, "input: S outside edit mode must remain native pass")
	var ctrl_w := _key(KEY_W, KEY_W)
	ctrl_w.ctrl_pressed = true
	_expect(Strategy.classify_key(ctrl_w, true, true) == Strategy.Action.PASS, "input: Ctrl+W must not pan camera")
	var ctrl_s := _key(KEY_S, KEY_S)
	ctrl_s.ctrl_pressed = true
	_expect(Strategy.classify_key(ctrl_s, true, true) == Strategy.Action.PASS, "input: Ctrl+S must not pan camera")
	var shift_w := _key(KEY_W, KEY_W)
	shift_w.shift_pressed = true
	_expect(Strategy.classify_key(shift_w, true, true) == Strategy.Action.CAMERA_PAN_FORWARD, "input: Shift+W should pan camera forward with boost")
	_expect(Strategy.classify_key(_key(KEY_F, KEY_F), true, true) == Strategy.Action.NATIVE_NAVIGATION, "input: Shift+F/native focus key must pass to Godot")


func _test_left_button_policy() -> void:
	var ctrl_left := _mouse_button(MOUSE_BUTTON_LEFT, true)
	ctrl_left.ctrl_pressed = true
	_expect(Strategy.classify_mouse_button(ctrl_left, true, SessionScript.Tool.SELECT, SessionScript.Tool.SELECT, SessionScript.Tool.PICK) == Strategy.Action.LEFT_TEMP_ERASE, "input: Ctrl+LMB should temporarily erase regardless of selected tool")
	var normal_left := _mouse_button(MOUSE_BUTTON_LEFT, true)
	_expect(Strategy.classify_mouse_button(normal_left, true, SessionScript.Tool.SELECT, SessionScript.Tool.SELECT, SessionScript.Tool.PICK) == Strategy.Action.LEFT_SELECT, "input: normal LMB Select behavior must remain selection")
	_expect(Strategy.classify_mouse_button(normal_left, true, SessionScript.Tool.PAINT, SessionScript.Tool.SELECT, SessionScript.Tool.PICK) == Strategy.Action.LEFT_STROKE, "input: normal LMB Paint behavior must remain a stroke")
	_expect(Strategy.classify_mouse_button(normal_left, true, SessionScript.Tool.PICK, SessionScript.Tool.SELECT, SessionScript.Tool.PICK) == Strategy.Action.LEFT_PICK, "input: normal LMB Pick behavior must remain picking")
	var release := _mouse_button(MOUSE_BUTTON_LEFT, false)
	_expect(Strategy.classify_mouse_button(release, true, SessionScript.Tool.ERASE, SessionScript.Tool.SELECT, SessionScript.Tool.PICK) == Strategy.Action.LEFT_RELEASE, "input: LMB release should close the active stroke")
	var right := _mouse_button(MOUSE_BUTTON_RIGHT, true)
	_expect(Strategy.classify_mouse_button(right, true, SessionScript.Tool.ERASE, SessionScript.Tool.SELECT, SessionScript.Tool.PICK) == Strategy.Action.NATIVE_NAVIGATION, "input: Shift/Alt+RMB remains native rather than erase")


func _test_camera_pan_helpers() -> void:
	# is_camera_pan_key tests
	_expect(Strategy.is_camera_pan_key(_key(KEY_W, KEY_W)), "is_camera_pan_key: W is pan key")
	_expect(Strategy.is_camera_pan_key(_key(KEY_A, KEY_A)), "is_camera_pan_key: A is pan key")
	_expect(Strategy.is_camera_pan_key(_key(KEY_S, KEY_S)), "is_camera_pan_key: S is pan key")
	_expect(Strategy.is_camera_pan_key(_key(KEY_D, KEY_D)), "is_camera_pan_key: D is pan key")
	var shift_w := _key(KEY_W, KEY_W)
	shift_w.shift_pressed = true
	_expect(Strategy.is_camera_pan_key(shift_w), "is_camera_pan_key: Shift+W is allowed (boost)")
	var ctrl_w := _key(KEY_W, KEY_W)
	ctrl_w.ctrl_pressed = true
	_expect(not Strategy.is_camera_pan_key(ctrl_w), "is_camera_pan_key: Ctrl+W is not pan key")
	var alt_s := _key(KEY_S, KEY_S)
	alt_s.alt_pressed = true
	_expect(not Strategy.is_camera_pan_key(alt_s), "is_camera_pan_key: Alt+S is not pan key")
	_expect(not Strategy.is_camera_pan_key(_key(KEY_R, KEY_R)), "is_camera_pan_key: R is not pan key")

	# get_camera_pan_input_direction tests
	var dir_w := Strategy.get_camera_pan_input_direction(true, false, false, false)
	_expect(dir_w.is_equal_approx(Vector2(0, 1)), "pan dir W: expected (0, 1)")
	var dir_s := Strategy.get_camera_pan_input_direction(false, false, true, false)
	_expect(dir_s.is_equal_approx(Vector2(0, -1)), "pan dir S: expected (0, -1)")
	var dir_a := Strategy.get_camera_pan_input_direction(false, true, false, false)
	_expect(dir_a.is_equal_approx(Vector2(-1, 0)), "pan dir A: expected (-1, 0)")
	var dir_d := Strategy.get_camera_pan_input_direction(false, false, false, true)
	_expect(dir_d.is_equal_approx(Vector2(1, 0)), "pan dir D: expected (1, 0)")
	var dir_none := Strategy.get_camera_pan_input_direction(false, false, false, false)
	_expect(dir_none == Vector2.ZERO, "pan dir none: expected ZERO")
	var dir_wd := Strategy.get_camera_pan_input_direction(true, false, false, true)
	_expect(dir_wd.is_equal_approx(Vector2(1, 1).normalized()), "pan dir W+D: expected normalized (1, 1)")

	# calculate_camera_pan_xz tests
	# 1. Camera facing -Z, pitched 45 degrees down:
	var basis_45 := Basis(Vector3(1, 0, 0), -PI / 4.0)
	var t_45 := Transform3D(basis_45, Vector3(0, 10, 10))
	var move_w := Strategy.calculate_camera_pan_xz(t_45, Vector2(0, 1), 10.0, 0.1)
	_expect(is_zero_approx(move_w.y), "camera pan W: Y must be 0 on XZ plane")
	_expect(move_w.z < -0.9, "camera pan W: Z should move forward towards -Z")
	_expect(is_zero_approx(move_w.x), "camera pan W: X should be 0")

	var move_s := Strategy.calculate_camera_pan_xz(t_45, Vector2(0, -1), 10.0, 0.1)
	_expect(is_zero_approx(move_s.y), "camera pan S: Y must be 0 on XZ plane")
	_expect(move_s.z > 0.9, "camera pan S: Z should move backward towards +Z")

	var move_d := Strategy.calculate_camera_pan_xz(t_45, Vector2(1, 0), 10.0, 0.1)
	_expect(is_zero_approx(move_d.y), "camera pan D: Y must be 0 on XZ plane")
	_expect(move_d.x > 0.9, "camera pan D: X should move right towards +X")

	var move_a := Strategy.calculate_camera_pan_xz(t_45, Vector2(-1, 0), 10.0, 0.1)
	_expect(is_zero_approx(move_a.y), "camera pan A: Y must be 0 on XZ plane")
	_expect(move_a.x < -0.9, "camera pan A: X should move left towards -X")

	# 2. Camera yawed 90 degrees (facing +X, looking right), pitched 45 degrees down:
	var basis_yaw90 := Basis(Vector3(0, 1, 0), -PI / 2.0) * Basis(Vector3(1, 0, 0), -PI / 4.0)
	var t_yaw90 := Transform3D(basis_yaw90, Vector3(0, 10, 0))
	var move_yaw_w := Strategy.calculate_camera_pan_xz(t_yaw90, Vector2(0, 1), 10.0, 0.1)
	_expect(is_zero_approx(move_yaw_w.y), "yaw camera pan W: Y must be 0")
	_expect(move_yaw_w.x > 0.9, "yaw camera pan W: forward should point along +X")
	_expect(is_zero_approx(move_yaw_w.z), "yaw camera pan W: Z should be 0")

	# 3. Top-down camera (pitch -90 degrees, looking straight down):
	var basis_topdown := Basis(Vector3(1, 0, 0), -PI / 2.0)
	var t_topdown := Transform3D(basis_topdown, Vector3(0, 20, 0))
	var move_top_w := Strategy.calculate_camera_pan_xz(t_topdown, Vector2(0, 1), 10.0, 0.1)
	_expect(is_zero_approx(move_top_w.y), "topdown camera pan W: Y must be 0")
	_expect(move_top_w.z < -0.9, "topdown camera pan W: forward should point along -Z")
	var move_top_d := Strategy.calculate_camera_pan_xz(t_topdown, Vector2(1, 0), 10.0, 0.1)
	_expect(is_zero_approx(move_top_d.y), "topdown camera pan D: Y must be 0")
	_expect(move_top_d.x > 0.9, "topdown camera pan D: right should point along +X")

	# 4. Diagonal and zero tests:
	var move_diag := Strategy.calculate_camera_pan_xz(t_45, Vector2(1, 1).normalized(), 10.0, 0.1)
	_expect(is_zero_approx(move_diag.y), "diagonal camera pan: Y must be 0")
	_expect(move_diag.x > 0.5 and move_diag.z < -0.5, "diagonal camera pan: should move along +X and -Z")
	_expect(is_equal_approx(move_diag.length(), 1.0), "diagonal camera pan: length should match speed * delta")

	var move_zero := Strategy.calculate_camera_pan_xz(t_45, Vector2.ZERO, 10.0, 0.1)
	_expect(move_zero == Vector3.ZERO, "zero input: should return Vector3.ZERO")
	var move_zero_dt := Strategy.calculate_camera_pan_xz(t_45, Vector2(0, 1), 10.0, 0.0)
	_expect(move_zero_dt == Vector3.ZERO, "zero delta: should return Vector3.ZERO")


func _key(keycode: Key, physical_keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = physical_keycode
	event.pressed = true
	event.echo = false
	return event


func _mouse_button(button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_MAP_INPUT_STRATEGY_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_MAP_INPUT_STRATEGY_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
