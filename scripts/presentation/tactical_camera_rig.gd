class_name TacticalCameraRig
extends Node3D

signal dynamic_moments_changed(enabled: bool)

## A self-contained presentation camera for the prototype grid.
## The rig's global position is the world-space focus point.
## Keyboard and mouse handling is intentionally direct so no project input actions are required.

@export_category("Movement")
@export var movement_speed: float = 10.0
@export var map_world_min: Vector2 = Vector2(0.0, 0.0)
@export var map_world_max: Vector2 = Vector2(22.0, 18.0)
@export var navigation_margin: float = 3.0
@export_range(0.0, 5.0, 0.25) var board_margin_cells: float = 1.5
var _walkable_bounds: Array[Rect2] = []
var _board_margin := 0.0
@export var follow_smoothing: float = 7.0
@export var focus_smoothing: float = 10.0
@export_range(0.2, 0.9) var follow_safe_fraction: float = 0.6
@export var look_ahead_distance: float = 1.4
@export var dynamic_moments_enabled: bool = true
@export var sprint_moments_enabled: bool = true:
	set(value):
		sprint_moments_enabled = value
		if not sprint_moments_enabled and is_instance_valid(moments) and moments.mode == TacticalCameraMoments.Mode.SPRINT:
			_restore_tactical_camera()
var moments := preload("res://scripts/presentation/tactical_camera_moments.gd").new()

@export_category("Zoom")
@export_range(8.0, 32.0, 0.5) var zoom_distance: float = 16.0
@export var zoom_min: float = 9.0
@export var zoom_max: float = 24.0
@export var zoom_step: float = 2.0
@export var zoom_smoothing: float = 30.0

@export_category("View")
@export var camera_pitch_degrees: float = -55.0

@onready var camera: Camera3D = $Camera3D

var cinematic_active: bool = false

var _target_zoom: float
var _current_zoom: float
var focus_target: Node3D
var moving_target: Node3D
var manual_override: bool = false
var _focus_active := false
var _focus_goal := Vector3.ZERO
var _follow_engaged := false
var _last_actor_position := Vector3.ZERO
var _look_ahead := Vector3.ZERO
var _dragging := false


func _ready() -> void:
	_target_zoom = clampf(zoom_distance, zoom_min, zoom_max)
	_current_zoom = _target_zoom
	_clamp_to_map()
	_apply_zoom(_current_zoom)


func _process(delta: float) -> void:
	if cinematic_active:
		return
	var input_vector := _read_keyboard_vector()
	if input_vector.length_squared() > 0.0:
		take_manual_control()
		var movement := Vector3(input_vector.x, 0.0, input_vector.y)
		position += movement * movement_speed * delta
		_clamp_to_map()
	_update_automatic_camera(delta)
	_clamp_to_map()

	_current_zoom = move_toward(_current_zoom, _target_zoom, zoom_smoothing * delta)
	_apply_zoom(_current_zoom)
	camera.global_transform = moments.update(self, camera.global_transform, delta)


func _unhandled_input(event: InputEvent) -> void:
	if cinematic_active:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_HOME:
		refocus_selected()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _dragging:
		var previous: Variant = _screen_ground(event.position - event.relative)
		var current: Variant = _screen_ground(event.position)
		if previous != null and current != null:
			global_position += previous - current
			_clamp_to_map()
		get_viewport().set_input_as_handled()
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button == null:
		return
	if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging = mouse_button.pressed
		if _dragging:
			take_manual_control()
		get_viewport().set_input_as_handled()
		return
	if not mouse_button.pressed:
		return

	match mouse_button.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			take_manual_control()
			_target_zoom = clampf(_target_zoom - zoom_step, zoom_min, zoom_max)
		MOUSE_BUTTON_WHEEL_DOWN:
			take_manual_control()
			_target_zoom = clampf(_target_zoom + zoom_step, zoom_min, zoom_max)


func _read_keyboard_vector() -> Vector2:
	var control := get_viewport().gui_get_focus_owner()
	if control is LineEdit or control is TextEdit:
		return Vector2.ZERO
	var horizontal := 0.0
	var vertical := 0.0

	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		horizontal -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		horizontal += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		vertical -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		vertical += 1.0

	return Vector2(horizontal, vertical).normalized()


func _apply_zoom(distance: float) -> void:
	var safe_distance := clampf(distance, zoom_min, zoom_max)
	var pitch_radians := deg_to_rad(absf(camera_pitch_degrees))
	var horizontal_distance := safe_distance * cos(pitch_radians)
	var vertical_distance := safe_distance * sin(pitch_radians)
	camera.position = Vector3(0.0, vertical_distance, horizontal_distance)
	camera.look_at(global_position, Vector3.UP)


func _clamp_to_map() -> void:
	if not _walkable_bounds.is_empty():
		global_position = constrain_board_focus(global_position)
		return
	var minimum_x := map_world_min.x + navigation_margin
	var maximum_x := map_world_max.x - navigation_margin
	var minimum_z := map_world_min.y + navigation_margin
	var maximum_z := map_world_max.y - navigation_margin

	if minimum_x > maximum_x:
		var center_x := (map_world_min.x + map_world_max.x) * 0.5
		minimum_x = center_x
		maximum_x = center_x
	if minimum_z > maximum_z:
		var center_z := (map_world_min.y + map_world_max.y) * 0.5
		minimum_z = center_z
		maximum_z = center_z

	var clamped_position := global_position
	clamped_position.x = clampf(clamped_position.x, minimum_x, maximum_x)
	clamped_position.y = 0.0
	clamped_position.z = clampf(clamped_position.z, minimum_z, maximum_z)
	global_position = clamped_position


func focus_world_position(world_position: Vector3, immediate: bool = false) -> void:
	if cinematic_active:
		return
	manual_override = false
	_focus_goal = Vector3(world_position.x, 0.0, world_position.z)
	_focus_goal = constrain_board_focus(_focus_goal)
	_focus_active = not immediate
	if not immediate:
		return
	var focused_position := global_position
	focused_position.x = world_position.x
	focused_position.z = world_position.z
	global_position = focused_position
	_clamp_to_map()


func set_focus_target(target: Node3D, auto_focus: bool = true) -> void:
	if target != focus_target:
		_restore_tactical_camera()
	focus_target = target
	if auto_focus and _target_visible(target) and not _inside_screen(target.global_position, 0.9):
		focus_world_position(target.global_position)


func refocus_selected() -> void:
	_restore_tactical_camera()
	if _target_visible(focus_target):
		focus_world_position(focus_target.global_position)
		_follow_engaged = moving_target == focus_target


func begin_movement(target: Node3D, path: Array[Vector3] = [], round_id: int = -1) -> void:
	if not _target_visible(target) or cinematic_active:
		return
	moving_target = target
	_last_actor_position = target.global_position
	manual_override = false
	_follow_engaged = false
	_focus_active = false
	_look_ahead = Vector3.ZERO
	if dynamic_moments_enabled and sprint_moments_enabled and round_id >= 0 and not _dragging and _read_keyboard_vector().is_zero_approx():
		moments.request_sprint(self, target, path, round_id)


func end_movement(target: Node3D) -> void:
	if moving_target != target:
		return
	moments.finish_sprint()
	if _target_visible(target) and _follow_engaged and not manual_override and not cinematic_active:
		focus_world_position(target.global_position)
	moving_target = null
	_follow_engaged = false
	_look_ahead = Vector3.ZERO


func take_manual_control() -> void:
	_restore_tactical_camera()
	manual_override = true
	_focus_active = false
	_follow_engaged = false


func _update_automatic_camera(delta: float) -> void:
	if cinematic_active or manual_override:
		return
	if _focus_active:
		global_position = global_position.lerp(_focus_goal, 1.0 - exp(-focus_smoothing * delta))
		var before := global_position
		_clamp_to_map()
		if global_position.distance_to(_focus_goal) < 0.02 or not before.is_equal_approx(global_position):
			_focus_active = false
		return
	if not _target_visible(moving_target):
		moving_target = null
		return
	var actor_position := moving_target.global_position
	var motion := actor_position - _last_actor_position
	_last_actor_position = actor_position
	motion.y = 0.0
	if motion.length_squared() > 0.00001:
		_look_ahead = _look_ahead.lerp(motion.normalized() * look_ahead_distance, 1.0 - exp(-5.0 * delta))
	_follow_engaged = _follow_engaged or not _inside_screen(actor_position, follow_safe_fraction)
	if _follow_engaged:
		var goal := actor_position + _look_ahead
		goal.y = 0.0
		global_position = global_position.lerp(goal, 1.0 - exp(-follow_smoothing * delta))
		_clamp_to_map()


func _target_visible(target: Variant) -> bool:
	return is_instance_valid(target) and target.is_inside_tree() and target.is_visible_in_tree() and (not target is PrototypeUnit or target.is_alive())


func _inside_screen(point: Vector3, fraction: float) -> bool:
	if camera.is_position_behind(point):
		return false
	var viewport_size := get_viewport().get_visible_rect().size
	var margin := viewport_size * (1.0 - fraction) * 0.5
	return Rect2(margin, viewport_size * fraction).has_point(camera.unproject_position(point + Vector3.UP * 0.8))


func _screen_ground(point: Vector2) -> Variant:
	return Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))


func begin_cinematic() -> Transform3D:
	_restore_tactical_camera()
	# Commit the current tactical framing; no suspended auto-focus may resume later.
	_focus_active = false
	_follow_engaged = false
	moving_target = null
	_dragging = false
	_target_zoom = _current_zoom
	cinematic_active = true
	return camera.global_transform


func end_cinematic(rest: Transform3D) -> void:
	camera.global_transform = rest
	cinematic_active = false


func cancel_tracking() -> void:
	_restore_tactical_camera()
	moving_target = null
	focus_target = null
	_focus_active = false
	_follow_engaged = false
	_dragging = false


func _restore_tactical_camera() -> void:
	if moments.mode != moments.Mode.NONE:
		moments.cancel()
		if is_instance_valid(camera):
			_apply_zoom(_current_zoom)


func show_discovery(observer: Node3D, enemies: Array[Node3D]) -> bool:
	if not dynamic_moments_enabled or cinematic_active or manual_override:
		return false
	if moments.request_discovery(self, observer, enemies):
		_focus_active = false
		return true
	return false


func _input(event: InputEvent) -> void:
	# A release over UI must still end a drag that started over the battlefield.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		_dragging = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_dragging = false


func set_walkable_bounds(rectangles: Array[Rect2], cell_size: float) -> void:
	_walkable_bounds = rectangles.duplicate()
	_board_margin = maxf(0, board_margin_cells) * maxf(cell_size, 0.01)
	if not _walkable_bounds.is_empty():
		var bounds := _walkable_bounds[0]
		for rect in _walkable_bounds:
			bounds = bounds.merge(rect)
		map_world_min = bounds.position
		map_world_max = bounds.end
	_clamp_to_map()
	_focus_goal = constrain_board_focus(_focus_goal)


## Clamp to the union of standable tile footprints plus an exterior buffer.
## Unlike a bounding rectangle this also excludes large holes in sparse maps.
func constrain_board_focus(point: Vector3) -> Vector3:
	if _walkable_bounds.is_empty():
		return point
	var horizontal := Vector2(point.x, point.z)
	var nearest := horizontal
	var best_distance := INF
	for rect in _walkable_bounds:
		var candidate := horizontal.clamp(rect.position, rect.end)
		var distance := candidate.distance_squared_to(horizontal)
		if distance <= _board_margin * _board_margin:
			return Vector3(point.x, 0, point.z)
		if distance < best_distance:
			best_distance = distance
			nearest = candidate
	var limited := nearest + (horizontal - nearest).normalized() * _board_margin
	return Vector3(limited.x, 0, limited.y)


func set_map_bounds(minimum: Vector2, maximum: Vector2) -> void:
	_walkable_bounds.clear()
	map_world_min = minimum
	map_world_max = maximum
	_clamp_to_map()
