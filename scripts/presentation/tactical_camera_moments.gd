class_name TacticalCameraMoments
extends RefCounted

## Presentation-only shots. Callers supply already-visible actors and legal paths.
enum Mode { NONE, SPRINT, DISCOVERY, RETURN }
var mode: Mode = Mode.NONE
var elapsed := 0.0
var source: Node3D
var subjects: Array[Node3D] = []
var direction := Vector3.RIGHT
var start_frame := Transform3D.IDENTITY
var last_frame := Transform3D.IDENTITY
var goal_frame := Transform3D.IDENTITY
var last_sprint_round: int = -1
var last_moment_time: int = -10000
var last_discovery_time: int = -10000
var duration := 1.0

func visible_actor(actor: Variant) -> bool:
	return is_instance_valid(actor) and actor.is_inside_tree() and actor.is_visible_in_tree() and (not actor is PrototypeUnit or actor.is_alive())

func request_sprint(rig: Node3D, actor: Node3D, path: Array[Vector3], round_id: int) -> bool:
	if mode != Mode.NONE or not visible_actor(actor) or path.size() < 5 or last_sprint_round == round_id or Time.get_ticks_msec() - last_moment_time < 8000:
		return false
	var heading: Vector3 = path.back() - actor.global_position
	if heading.length() < 8.0 or absf(heading.y) > 0.3:
		return false
	heading.y = 0
	heading = heading.normalized()
	var previous := actor.global_position
	# Reject winding routes and check the entire route before lowering the camera.
	for point in path:
		var segment := point - previous
		if segment.length_squared() > 0.001 and (segment.normalized().dot(heading) < 0.85 or absf(segment.y) > 0.3):
			return false
		var aim := point + Vector3.UP * 0.9 + heading * 1.1
		var candidate := _sprint_position(point, heading)
		if not clear_view(rig, candidate, [aim]):
			return false
		previous = point
	source = actor
	direction = heading
	_start(Mode.SPRINT, rig.camera.global_transform, 1.0)
	last_sprint_round = round_id
	last_moment_time = Time.get_ticks_msec()
	return true

func request_discovery(rig: Node3D, observer: Node3D, enemies: Array[Node3D]) -> bool:
	if not visible_actor(observer) or Time.get_ticks_msec() - last_discovery_time < 1500:
		return false
	var accepted: Array[Node3D] = [observer]
	for enemy in enemies:
		if visible_actor(enemy) and enemy != observer and not accepted.has(enemy):
			accepted.append(enemy)
	if accepted.size() < 2:
		return false
	var minimum := observer.global_position
	var maximum := minimum
	for actor in accepted:
		minimum = minimum.min(actor.global_position)
		maximum = maximum.max(actor.global_position)
	var center := (minimum + maximum) * 0.5 + Vector3.UP * 0.8
	var radius := 0.8
	var points: Array[Vector3] = []
	for actor in accepted:
		var point := actor.global_position + Vector3.UP * 0.8
		points.append(point)
		radius = maxf(radius, point.distance_to(center) + 0.8)
	var aspect: float = rig.get_viewport().get_visible_rect().size.aspect()
	var half_angle := deg_to_rad(float(rig.camera.fov)) * 0.5
	half_angle = minf(half_angle, atan(tan(half_angle) * aspect)) * 0.8
	var distance := maxf(float(rig._current_zoom), radius / sin(half_angle))
	if distance > float(rig.zoom_max):
		return false
	var pitch := deg_to_rad(absf(float(rig.camera_pitch_degrees)))
	var candidate := center + Vector3(0, sin(pitch), cos(pitch)) * distance
	if not clear_view(rig, candidate, points):
		return false
	subjects = accepted
	goal_frame = Transform3D(Basis.looking_at(center - candidate), candidate)
	_start(Mode.DISCOVERY, rig.camera.global_transform, 1.0)
	last_moment_time = Time.get_ticks_msec()
	last_discovery_time = last_moment_time
	return true

func _start(next: Mode, frame: Transform3D, seconds: float) -> void:
	mode = next
	elapsed = 0.0
	start_frame = frame
	last_frame = frame
	duration = seconds

func finish_sprint() -> void:
	if mode == Mode.SPRINT:
		_start(Mode.RETURN, last_frame, 0.25)

func cancel() -> void:
	mode = Mode.NONE
	source = null
	subjects.clear()
	elapsed = 0.0

func update(rig: Node3D, tactical: Transform3D, delta: float) -> Transform3D:
	if mode == Mode.NONE:
		return tactical
	elapsed += delta
	var goal := tactical
	var points: Array[Vector3] = []
	if mode == Mode.SPRINT:
		if not visible_actor(source):
			cancel()
			return tactical
		var aim := source.global_position + Vector3.UP * 0.9 + direction * 1.1
		var candidate := _sprint_position(source.global_position, direction)
		goal = Transform3D(Basis.looking_at(aim - candidate), candidate)
		points.append(source.global_position + Vector3.UP * 0.9)
	elif mode == Mode.DISCOVERY:
		for actor in subjects:
			if not visible_actor(actor):
				cancel()
				return tactical
			points.append(actor.global_position + Vector3.UP * 0.8)
		goal = goal_frame
	var blend := smoothstep(0.0, 1.0, minf(elapsed / (duration if mode == Mode.RETURN else 0.2), 1.0))
	var frame := start_frame.interpolate_with(goal, blend)
	# Check the actual interpolated camera as well as its destination, every frame.
	if not clear_view(rig, goal.origin, points) or not clear_view(rig, frame.origin, points) or not clear_segment(rig, last_frame.origin, frame.origin):
		cancel()
		return tactical
	last_frame = frame
	if elapsed >= duration:
		if mode == Mode.RETURN:
			cancel()
			return tactical
		_start(Mode.RETURN, frame, 0.25)
	return frame

func _sprint_position(point: Vector3, heading: Vector3) -> Vector3:
	return point - heading * 4.2 + heading.cross(Vector3.UP) * 2.4 + Vector3.UP * 2.8

func clear_segment(rig: Node3D, from: Vector3, to: Vector3) -> bool:
	if from.distance_squared_to(to) < 0.0001:
		return true
	var ray := PhysicsRayQueryParameters3D.create(from, to, 3)
	return rig.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func clear_view(rig: Node3D, position: Vector3, points: Array[Vector3]) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = 0.22
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform.origin = position
	query.collision_mask = 3
	if not rig.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	for point in points:
		if not clear_segment(rig, position, point):
			return false
	return true
