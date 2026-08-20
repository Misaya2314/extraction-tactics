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
	if _is_native_navigation_key(event):
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


static func _is_native_navigation_key(event: InputEventKey) -> bool:
	return _is_physical_key(event, KEY_W) or _is_physical_key(event, KEY_A) or _is_physical_key(event, KEY_S) or _is_physical_key(event, KEY_D) or _is_physical_key(event, KEY_F)


static func _is_physical_key(event: InputEventKey, keycode: Key) -> bool:
	return event.physical_keycode == keycode or (event.physical_keycode == 0 and event.keycode == keycode)


static func _is_unmodified_physical_key(event: InputEventKey, keycode: Key) -> bool:
	return _is_physical_key(event, keycode) and not event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed
