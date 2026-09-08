@tool
class_name TacticalMapInputStrategy
extends RefCounted

## Pure input classification for TacticalMapEditorPlugin.
##
## The editor owns camera navigation (RMB/MMB/WASD/Shift+F).  This helper never
## reads InputMap and never creates a camera, so it is safe to exercise from a
## normal headless SceneTree test.

enum Action {
	PASS,
	TOGGLE_EDIT_MODE,
	ROTATE,
	CANCEL,
	NATIVE_NAVIGATION,
	CAMERA_PAN_FORWARD,
	CAMERA_PAN_BACKWARD,
	CAMERA_PAN_LEFT,
	CAMERA_PAN_RIGHT,
	LEFT_SELECT,
	LEFT_PICK,
	LEFT_STROKE,
	LEFT_TEMP_ERASE,
	LEFT_RELEASE,
}


static func classify_key(event: InputEventKey, has_author: bool, edit_mode: bool) -> int:
	if event == null or not event.pressed or event.echo:
		return Action.PASS
	if has_author and _is_unmodified_physical_key(event, KEY_M):
		return Action.TOGGLE_EDIT_MODE
	if not edit_mode:
		return Action.PASS
	if _is_physical_key(event, KEY_R):
		return Action.ROTATE
	if _is_physical_key(event, KEY_ESCAPE):
		return Action.CANCEL
	if _is_pan_key(event, KEY_W):
		return Action.CAMERA_PAN_FORWARD
	if _is_pan_key(event, KEY_A):
		return Action.CAMERA_PAN_LEFT
	if _is_pan_key(event, KEY_S):
		return Action.CAMERA_PAN_BACKWARD
	if _is_pan_key(event, KEY_D):
		return Action.CAMERA_PAN_RIGHT
	if _is_physical_key(event, KEY_F):
		return Action.NATIVE_NAVIGATION
	return Action.PASS


static func classify_mouse_button(event: InputEventMouseButton, edit_mode: bool, current_tool: int, select_tool: int, pick_tool: int) -> int:
	if event == null or not edit_mode:
		return Action.PASS
	if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
		return Action.NATIVE_NAVIGATION
	if event.button_index != MOUSE_BUTTON_LEFT:
		return Action.PASS
	if not event.pressed:
		return Action.LEFT_RELEASE
	if event.ctrl_pressed:
		return Action.LEFT_TEMP_ERASE
	if current_tool == select_tool:
		return Action.LEFT_SELECT
	if current_tool == pick_tool:
		return Action.LEFT_PICK
	return Action.LEFT_STROKE


static func is_native_navigation_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		return mouse.button_index == MOUSE_BUTTON_RIGHT or mouse.button_index == MOUSE_BUTTON_MIDDLE
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		return (motion.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)) != 0
	return false


static func is_camera_pan_key(event: InputEventKey) -> bool:
	if event == null:
		return false
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return false
	return _is_physical_key(event, KEY_W) or _is_physical_key(event, KEY_A) or _is_physical_key(event, KEY_S) or _is_physical_key(event, KEY_D)


static func get_camera_pan_input_direction(w: bool, a: bool, s: bool, d: bool) -> Vector2:
	var dir := Vector2.ZERO
	if d:
		dir.x += 1.0
	if a:
		dir.x -= 1.0
	if w:
		dir.y += 1.0
	if s:
		dir.y -= 1.0
	return dir.normalized() if dir.length_squared() > 0.0 else Vector2.ZERO


static func calculate_camera_pan_xz(camera_transform: Transform3D, input_dir: Vector2, speed: float, delta: float) -> Vector3:
	if input_dir == Vector2.ZERO or speed <= 0.0 or delta <= 0.0:
		return Vector3.ZERO
	var cam_forward := -camera_transform.basis.z
	var forward_xz := Vector3(cam_forward.x, 0.0, cam_forward.z)
	if forward_xz.length_squared() < 0.0001:
		var cam_up := camera_transform.basis.y
		forward_xz = Vector3(cam_up.x, 0.0, cam_up.z)
	if forward_xz.length_squared() < 0.0001:
		forward_xz = Vector3(0.0, 0.0, -1.0)
	else:
		forward_xz = forward_xz.normalized()

	var cam_right := camera_transform.basis.x
	var right_xz := Vector3(cam_right.x, 0.0, cam_right.z)
	if right_xz.length_squared() < 0.0001:
		right_xz = forward_xz.cross(Vector3.UP)
	if right_xz.length_squared() < 0.0001:
		right_xz = Vector3(1.0, 0.0, 0.0)
	else:
		right_xz = right_xz.normalized()

	var move_dir := (forward_xz * input_dir.y + right_xz * input_dir.x)
	if move_dir.length_squared() > 0.0:
		move_dir = move_dir.normalized()
	return move_dir * (speed * delta)


static func _is_pan_key(event: InputEventKey, keycode: Key) -> bool:
	if event == null:
		return false
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return false
	return _is_physical_key(event, keycode)


static func _is_native_navigation_key(event: InputEventKey) -> bool:
	return _is_physical_key(event, KEY_W) or _is_physical_key(event, KEY_A) or _is_physical_key(event, KEY_S) or _is_physical_key(event, KEY_D) or _is_physical_key(event, KEY_F)


static func _is_physical_key(event: InputEventKey, keycode: Key) -> bool:
	return event.physical_keycode == keycode or (event.physical_keycode == 0 and event.keycode == keycode)


static func _is_unmodified_physical_key(event: InputEventKey, keycode: Key) -> bool:
	return _is_physical_key(event, keycode) and not event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed
