class_name TacticalCameraRig
extends Node3D

## A self-contained presentation camera for the prototype grid.
## The rig's global position is the world-space focus point.
## Keyboard and mouse handling is intentionally direct so no project input actions are required.

@export_category("Movement")
@export var movement_speed: float = 10.0
@export var map_world_min: Vector2 = Vector2(0.0, 0.0)
@export var map_world_max: Vector2 = Vector2(22.0, 18.0)
@export var navigation_margin: float = 3.0

@export_category("Zoom")
@export_range(8.0, 32.0, 0.5) var zoom_distance: float = 16.0
@export var zoom_min: float = 9.0
@export var zoom_max: float = 24.0
@export var zoom_step: float = 2.0
@export var zoom_smoothing: float = 30.0

@export_category("View")
@export var camera_pitch_degrees: float = -55.0

@onready var camera: Camera3D = $Camera3D

var _target_zoom: float
var _current_zoom: float


func _ready() -> void:
	_target_zoom = clampf(zoom_distance, zoom_min, zoom_max)
	_current_zoom = _target_zoom
	_clamp_to_map()
	_apply_zoom(_current_zoom)


func _process(delta: float) -> void:
	var input_vector := _read_keyboard_vector()
	if input_vector.length_squared() > 0.0:
		var movement := Vector3(input_vector.x, 0.0, input_vector.y)
		position += movement * movement_speed * delta
		_clamp_to_map()

	_current_zoom = move_toward(_current_zoom, _target_zoom, zoom_smoothing * delta)
	_apply_zoom(_current_zoom)


func _unhandled_input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button == null or not mouse_button.pressed:
		return

	match mouse_button.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_target_zoom = clampf(_target_zoom - zoom_step, zoom_min, zoom_max)
		MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom = clampf(_target_zoom + zoom_step, zoom_min, zoom_max)


func _read_keyboard_vector() -> Vector2:
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


func focus_world_position(world_position: Vector3) -> void:
	var focused_position := global_position
	focused_position.x = world_position.x
	focused_position.z = world_position.z
	global_position = focused_position
	_clamp_to_map()


func set_map_bounds(minimum: Vector2, maximum: Vector2) -> void:
	map_world_min = minimum
	map_world_max = maximum
	_clamp_to_map()
