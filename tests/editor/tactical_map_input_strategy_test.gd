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
	_expect(Strategy.classify_key(_key(KEY_W, KEY_W), true, true) == Strategy.Action.NATIVE_NAVIGATION, "input: WASD navigation must pass to Godot")
	_expect(Strategy.classify_key(_key(KEY_A, KEY_A), true, true) == Strategy.Action.NATIVE_NAVIGATION, "input: A navigation must pass to Godot")
	_expect(Strategy.classify_key(_key(KEY_S, KEY_S), true, true) == Strategy.Action.NATIVE_NAVIGATION, "input: S navigation must pass to Godot")
	_expect(Strategy.classify_key(_key(KEY_D, KEY_D), true, true) == Strategy.Action.NATIVE_NAVIGATION, "input: D navigation must pass to Godot")
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
