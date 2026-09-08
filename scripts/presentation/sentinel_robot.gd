class_name SentinelRobot
extends Node3D

## Rigid joints are sampled locally. Animation never changes the actor's grid root.
var animation_player: AnimationPlayer
var weapon_socket: Node3D
var _rest: Dictionary = {}
var _clip: StringName = &""
var _time: float = 0.0
var _shot: float = 0.0
var _motion: float = 0.0
var _reaction: bool = false
var _last_position := Vector3.ZERO
var _target_yaw: float = 0.0
var _preview: StringName = &""
var _team_color := Color.TRANSPARENT


func _ready() -> void:
	animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	weapon_socket = find_child("WeaponSocket", true, false) as Node3D
	_cache_pose(get_node("Model"))
	_last_position = _actor_position()
	reset_pose()


func _cache_pose(node: Node) -> void:
	if node is Node3D:
		_rest[node] = node.transform
	for child in node.get_children():
		_cache_pose(child)


func _restore_joints() -> void:
	if animation_player != null:
		animation_player.stop()
	for node in _rest:
		if is_instance_valid(node):
			node.transform = _rest[node]


func _actor_position() -> Vector3:
	var actor := get_parent().get_parent() as Node3D
	return actor.global_position if actor != null else global_position


func _process(delta: float) -> void:
	var actor_position := _actor_position()
	var moved := actor_position.distance_to(_last_position)
	_last_position = actor_position
	if _reaction:
		return
	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-18.0 * delta))
	_motion = 0.14 if moved > 0.001 else maxf(0.0, _motion - delta)
	_shot = maxf(0.0, _shot - delta)
	var clip: StringName = _preview if not _preview.is_empty() else (&"shoot" if _shot > 0.0 else (&"walk" if _motion > 0.0 else &"idle"))
	if clip != _clip:
		_start_clip(clip)
	_time += delta
	_sample(_time, clip == &"idle" or clip == &"walk")
	var actor := get_parent().get_parent()
	if actor is PrototypeUnit and not actor.is_attack_feedback_playing:
		sync_weapon(actor.weapon_pivot)
		actor._weapon_pivot_rest_position = actor.weapon_pivot.position


func face_direction(direction: Vector2i, immediate: bool = false) -> void:
	_target_yaw = atan2(float(direction.x), float(direction.y))
	if immediate:
		rotation.y = _target_yaw


func _start_clip(clip: StringName) -> void:
	_restore_joints()
	_clip = clip
	_time = 0.0
	if animation_player != null and animation_player.has_animation(clip):
		animation_player.play(clip)
		animation_player.pause()


func _sample(time: float, loop: bool = false) -> void:
	if animation_player == null or not animation_player.has_animation(_clip):
		return
	var length := animation_player.get_animation(_clip).length
	animation_player.seek(fmod(time, length) if loop else minf(time, length), true)


func play_shot() -> void:
	rotation.y = _target_yaw
	_shot = 0.24
	_start_clip(&"shoot")


func set_reaction(progress: float, killed: bool) -> void:
	var clip: StringName = &"death" if killed else &"hit"
	if not _reaction or _clip != clip:
		_start_clip(clip)
		_reaction = true
	if animation_player != null:
		_sample(clampf(progress, 0.0, 1.0) * animation_player.get_animation(clip).length)


func reset_pose() -> void:
	_reaction = false
	_shot = 0.0
	_motion = 0.0
	_preview = &""
	rotation.y = _target_yaw
	_start_clip(&"idle")
	_sample(0.0)


func preview_animation(clip: StringName) -> void:
	reset_pose()
	_preview = clip
	_start_clip(clip)


func sync_weapon(pivot: Node3D) -> void:
	if is_instance_valid(weapon_socket) and is_instance_valid(pivot):
		pivot.global_transform = weapon_socket.global_transform


func set_team_color(color: Color) -> void:
	if color == _team_color:
		return
	_team_color = color
	_apply_palette(self, color)


func _apply_palette(node: Node, color: Color) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for index in range(node.mesh.get_surface_count()):
			var source := node.mesh.surface_get_material(index) as StandardMaterial3D
			if source == null or source.resource_name not in ["TeamPaint", "Sensor"]:
				continue
			var paint := source.duplicate() as StandardMaterial3D
			if source.resource_name == "TeamPaint":
				paint.albedo_color = color.darkened(0.2)
			else:
				paint.albedo_color = Color(1.0, 0.30, 0.06) if color.r > color.b else Color(0.12, 0.8, 1.0)
				paint.emission = paint.albedo_color
			node.set_surface_override_material(index, paint)
	for child in node.get_children():
		_apply_palette(child, color)
