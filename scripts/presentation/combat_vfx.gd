class_name CombatVfx
extends Node3D

## Bounded analytical particles, stepped ONLY by the combat presentation clock.
## Independent visual RNG; no collision bodies, damage or gameplay random draws.
@export_range(32, 512) var particle_budget: int = 256
var particles: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _sphere: SphereMesh
var _cube: BoxMesh


func _init() -> void:
	_rng.randomize()
	_sphere = SphereMesh.new()
	_sphere.radial_segments = 8
	_sphere.rings = 4
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_cube = BoxMesh.new()
	_cube.size = Vector3.ONE


func _particle(position: Vector3, velocity: Vector3, size: Vector3, color: Color, life: float, kind: StringName, ground: float) -> void:
	if particles.size() >= particle_budget:
		return
	var mesh := MeshInstance3D.new()
	mesh.mesh = _sphere if kind in [&"smoke", &"flash"] else _cube
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if kind in [&"spark", &"flash", &"tracer"] else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.roughness = 0.9
	mesh.material_override = material
	add_child(mesh)
	mesh.global_position = position
	mesh.scale = size.max(Vector3.ONE * 0.001)
	particles.append({"node": mesh, "origin": position, "velocity": velocity, "size": size,
		"color": color, "age": 0.0, "life": maxf(life, 0.01), "kind": kind, "ground": ground,
		"spin": Vector3(_rng.randf_range(-5, 5), _rng.randf_range(-5, 5), _rng.randf_range(-5, 5))})


func shot(source: Vector3, target: Vector3, flight_time: float, shotgun: bool = false) -> void:
	var shots := 3 if shotgun else 1
	for i in range(shots):
		var endpoint := target + Vector3(_rng.randf_range(-0.08, 0.08), _rng.randf_range(-0.08, 0.08), 0) if shotgun else target
		var before := particles.size()
		_particle(source, Vector3.ZERO, Vector3.ONE, Color(1, 0.83, 0.36), maxf(flight_time, 0.03), &"tracer", source.y)
		if particles.size() > before:
			particles.back()["target"] = endpoint
			particles.back()["node"].visible = false
	for i in range(4):
		_particle(source, Vector3(_rng.randf_range(-0.15, 0.15), 0.3, _rng.randf_range(-0.15, 0.15)), Vector3.ONE * 0.045, Color(0.55, 0.58, 0.60, 0.28), 0.5, &"smoke", source.y - 0.2)
	_particle(source, Vector3.ZERO, Vector3.ONE * (0.22 if shotgun else 0.14), Color(1, 0.8, 0.3, 0.9), 0.045, &"flash", source.y)


func impact(position: Vector3, incoming: Vector3, ground: float) -> void:
	var backward := -incoming.normalized()
	for i in range(10):
		var velocity := (backward + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.1, 1), _rng.randf_range(-1, 1))).normalized() * _rng.randf_range(1.2, 3.0)
		_particle(position, velocity, Vector3(0.025, 0.025, 0.10), Color(1, 0.65, 0.16), 0.28 + _rng.randf() * 0.18, &"spark", ground)
	for i in range(5):
		_particle(position, Vector3(_rng.randf_range(-0.3, 0.3), 0.4, _rng.randf_range(-0.3, 0.3)), Vector3.ONE * 0.10, Color(0.32, 0.36, 0.39, 0.35), 0.6, &"smoke", ground)
	for i in range(4):
		_particle(position, backward * 0.6 + Vector3(_rng.randf_range(-1, 1), 1, _rng.randf_range(-1, 1)), Vector3(0.045, 0.025, 0.055), Color(0.40, 0.46, 0.48), 0.6, &"debris", ground)


func explosion(position: Vector3, radius: float = 1.5) -> void:
	_particle(position + Vector3.UP * 0.3, Vector3.ZERO, Vector3.ONE * 0.3, Color(1, 0.49, 0.10, 0.7), 0.23, &"flash", position.y)
	for i in range(24):
		var angle := _rng.randf() * TAU
		var velocity := Vector3(cos(angle), _rng.randf_range(0.3, 1.3), sin(angle)) * _rng.randf_range(2.0, 4.5) * radius / 1.5
		_particle(position + Vector3.UP * 0.25, velocity, Vector3(0.03, 0.03, 0.13), Color(1, 0.65, 0.19), _rng.randf_range(0.3, 0.55), &"spark", position.y)
	for i in range(12):
		var angle := TAU * i / 12.0
		var velocity := Vector3(cos(angle) * 1.1, _rng.randf_range(0.4, 1.0), sin(angle) * 1.1)
		_particle(position + Vector3.UP * 0.3, velocity, Vector3.ONE * _rng.randf_range(0.22, 0.38), Color(0.23, 0.25, 0.28, 0.5), 0.85, &"smoke", position.y)
	for i in range(12):
		_particle(position + Vector3.UP * 0.3, Vector3(_rng.randf_range(-2, 2), _rng.randf_range(1.5, 3), _rng.randf_range(-2, 2)), Vector3.ONE * _rng.randf_range(0.04, 0.10), Color(0.34, 0.30, 0.25), 0.8, &"debris", position.y)
	# Expanding dust ring, no giant opaque sphere hiding the tactical result.
	for i in range(16):
		var angle := TAU * i / 16.0
		_particle(position + Vector3.UP * 0.08, Vector3(cos(angle), 0.08, sin(angle)) * radius * 2.0, Vector3(0.15, 0.08, 0.15), Color(0.53, 0.48, 0.39, 0.38), 0.55, &"smoke", position.y)


func advance(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p := particles[i]
		p.age += maxf(delta, 0.0)
		var mesh: MeshInstance3D = p.node
		if p.age >= p.life:
			mesh.free()
			particles.remove_at(i)
			continue
		var t: float = p.age / p.life
		var material := mesh.material_override as StandardMaterial3D
		material.albedo_color.a = p.color.a * (1.0 - t)
		if p.kind == &"tracer":
			var head: Vector3 = p.origin.lerp(p.target, t)
			var tail: Vector3 = p.origin.lerp(p.target, maxf(0, t - 0.23))
			_orient_segment(mesh, tail, head, 0.016)
		elif p.kind == &"flash":
			mesh.scale = p.size * (1.0 + 5.0 * t)
		elif p.kind == &"smoke":
			mesh.global_position = p.origin + p.velocity * p.age
			mesh.scale = p.size * (1.0 + 3.0 * t)
		else:
			var point: Vector3 = p.origin + p.velocity * p.age + Vector3.DOWN * 4.9 * p.age * p.age
			point.y = maxf(point.y, p.ground + 0.03)
			mesh.global_position = point
			mesh.rotation += p.spin * delta


func _orient_segment(mesh: MeshInstance3D, start: Vector3, end: Vector3, width: float) -> void:
	var length := start.distance_to(end)
	mesh.visible = length > 0.001
	if not mesh.visible:
		return
	mesh.global_position = (start + end) * 0.5
	var direction := (end - start).normalized()
	mesh.look_at(end, Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.95 else Vector3.UP)
	mesh.scale = Vector3(width, width, length)


func clear() -> void:
	for p in particles:
		if is_instance_valid(p.node):
			p.node.free()
	particles.clear()
