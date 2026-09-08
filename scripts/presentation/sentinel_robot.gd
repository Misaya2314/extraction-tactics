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
var cover_level: int = 0
var cover_direction := Vector3.FORWARD
var exposure: float = 0.0
var _stance: float = 0.0
var attack_pose: bool = false
var aim_target := Vector3.ZERO
var reaction_direction := Vector3.BACK


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
	_stance = move_toward(_stance, (1.0 - exposure) if cover_level > 0 and _motion <= 0.0 else 0.0, delta * 7.0)
	_apply_stance()
	var actor := get_parent().get_parent()
	if actor is PrototypeUnit and not actor.is_attack_feedback_playing:
		sync_weapon(actor.weapon_pivot)
		actor._weapon_pivot_rest_position = actor.weapon_pivot.position


func set_cover(level: int, direction: Vector3) -> void:
	cover_level = clampi(level, 0, 2)
	cover_direction = direction


func _apply_stance() -> void:
	if _clip in [&"hit", &"death"]:
		return
	var rig := find_child("RobotRig", true, false) as Node3D
	if rig == null:
		return
	# The rig root has no idle tracks: always assign, never accumulate offsets.
	rig.transform = _rest[rig]
	if _clip != &"walk":
		for leg_name in ["LegL", "LegR"]:
			var leg := find_child(leg_name, true, false) as Node3D
			leg.transform = _rest[leg]
			var knee := leg.find_child("Knee*", false, false) as Node3D
			knee.transform = _rest[knee]
	if cover_level == 1:
		rig.position.y = -0.30 * _stance
		for leg_name in ["LegL", "LegR"]:
			var leg := find_child(leg_name, true, false) as Node3D
			leg.rotation.x = lerpf(leg.rotation.x, -0.85, _stance)
			var knee := leg.find_child("Knee*", false, false) as Node3D
			knee.rotation.x = lerpf(knee.rotation.x, 1.55, _stance)
		var wall_yaw := atan2(cover_direction.x, cover_direction.z)
		rig.rotation.y = wrapf(wall_yaw + PI * 0.5 - rotation.y, -PI, PI) * _stance
	elif cover_level == 2:
		var wall_yaw := atan2(cover_direction.x, cover_direction.z)
		rig.rotation.y = wrapf(wall_yaw + PI * 0.5 - rotation.y, -PI, PI) * _stance
	if attack_pose:
		var heading := aim_target - global_position
		rotation.y = atan2(heading.x, heading.z)
		var torso := find_child("Torso", true, false) as Node3D
		torso.basis = (_rest[torso] as Transform3D).basis
		var direction := torso.to_local(aim_target).normalized()
		torso.rotation.x = clampf(-atan2(direction.y, Vector2(direction.x, direction.z).length()), -0.55, 0.55)


func set_attack_pose(progress: float, offset: Vector3, target: Vector3) -> void:
	attack_pose = progress > 0.0
	exposure = progress
	aim_target = target
	position = get_parent().global_basis.inverse() * offset * progress
	_stance = (1.0 - progress) if cover_level > 0 else 0.0
	_sample(_time, true)
	_apply_stance()


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
	_sample(0.0)
	_apply_stance()


func set_reaction(progress: float, killed: bool, incoming: Vector3 = Vector3.BACK) -> void:
	var clip: StringName = &"death" if killed else &"hit"
	if not _reaction or _clip != clip:
		_start_clip(clip)
		_reaction = true
	if animation_player != null:
		_sample(clampf(progress, 0.0, 1.0) * animation_player.get_animation(clip).length)
	var direction := global_basis.inverse() * incoming
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = Vector3.BACK
	direction = direction.normalized()
	reaction_direction = direction
	var axis := Vector3.UP.cross(direction).normalized()
	var rig := find_child("RobotRig", true, false) as Node3D
	if killed:
		rig.basis = Basis(axis, progress * 1.5)
		rig.position = direction * progress * 0.32 + Vector3.UP * progress * 0.20
	else:
		var torso := find_child("Torso", true, false) as Node3D
		torso.basis = Basis(axis, sin(progress * PI) * 0.22)


func reset_pose() -> void:
	_reaction = false
	_shot = 0.0
	_motion = 0.0
	_preview = &""
	rotation.y = _target_yaw
	_start_clip(&"idle")
	_sample(0.0)
	_apply_stance()


func preview_animation(clip: StringName) -> void:
	reset_pose()
	_preview = clip
	_start_clip(clip)


func sync_weapon(pivot: Node3D) -> void:
	if is_instance_valid(weapon_socket) and is_instance_valid(pivot):
		pivot.global_transform = weapon_socket.global_transform
		if attack_pose and not _reaction and pivot.global_position.distance_to(aim_target) > 0.01:
			pivot.look_at(aim_target, Vector3.UP, true)


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
