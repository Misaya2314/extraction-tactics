@tool
class_name TacticalPreviewBuilder
extends RefCounted

## Pure, unsaved viewport-preview construction helpers.  They only attach
## children to the caller-provided preview root; they never set an owner or
## mutate a MeshLibrary/scene resource.


static func build_cell_mesh(parent: Node3D, mesh_library: MeshLibrary, item_id: int, rotation_quarters: int) -> MeshInstance3D:
	if parent == null or mesh_library == null or item_id < 0 or not mesh_library.get_item_list().has(item_id):
		return null
	var mesh := mesh_library.get_item_mesh(item_id)
	if mesh == null:
		return null
	var instance := MeshInstance3D.new()
	instance.name = "CellGhost"
	instance.mesh = mesh
	var base_transform := Transform3D.IDENTITY
	if mesh_library.has_method("get_item_mesh_transform"):
		var transform_value = mesh_library.call("get_item_mesh_transform", item_id)
		if transform_value is Transform3D:
			base_transform = transform_value
	instance.transform = compose_rotation_transform(base_transform, rotation_quarters)
	parent.add_child(instance)
	instance.owner = null
	return instance


static func compose_rotation_transform(base_transform: Transform3D, rotation_quarters: int) -> Transform3D:
	var rotation_basis := Basis(Vector3.UP, PI * 0.5 * float(posmod(rotation_quarters, 4)))
	return Transform3D(rotation_basis * base_transform.basis, rotation_basis * base_transform.origin)


static func build_fallback(parent: Node3D, dimensions: Vector3) -> MeshInstance3D:
	if parent == null:
		return null
	var instance := MeshInstance3D.new()
	instance.name = "CellGhostFallback"
	var box := BoxMesh.new()
	box.size = Vector3(dimensions.x * 0.92, maxf(dimensions.y * 0.28, 0.08), dimensions.z * 0.92)
	instance.mesh = box
	parent.add_child(instance)
	instance.owner = null
	return instance


static func instantiate_scene_preview(parent: Node3D, scene: PackedScene, rotation_quarters: int) -> Node3D:
	if parent == null or scene == null:
		return null
	var instance := scene.instantiate()
	if not instance is Node3D:
		if instance != null:
			instance.free()
		return null
	var node := instance as Node3D
	parent.add_child(node)
	node.owner = null
	node.rotation.y = PI * 0.5 * float(posmod(rotation_quarters, 4))
	disable_collisions(node)
	return node


static func apply_preview_visual_defaults(node: Node, color: Color = Color(0.25, 0.95, 0.4, 0.28)) -> void:
	if node == null:
		return
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		geometry.material_override = material
	for child in node.get_children():
		apply_preview_visual_defaults(child, color)


## Basis whose local +Y axis points along a cardinal facing direction on the
## X/Z ground plane. Shared by the spawn-marker overlay and the placement
## preview so both render the same physical orientation.
static func facing_basis(facing: Vector2i) -> Basis:
	var y := Vector3(float(facing.x), 0.0, float(facing.y)).normalized()
	var z := Vector3.UP
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	return Basis(x, y, z)


## Builds a thin, tapered "needle" arrow (base at origin, tip along +Y) that
## callers can drop into a root and orient with facing_basis(). Reuses
## CylinderMesh with a near-zero top radius so the tip reads clearly as a
## direction indicator without relying on ConeMesh (absent in this engine).
static func build_facing_needle(length: float, radius: float, color: Color) -> MeshInstance3D:
	var needle := CylinderMesh.new()
	needle.top_radius = radius * 0.12
	needle.bottom_radius = radius
	needle.height = length
	needle.radial_segments = 8
	var instance := MeshInstance3D.new()
	instance.name = "FacingNeedle"
	instance.mesh = needle
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func tint_preview(node: Node, color: Color) -> void:
	if node == null:
		return
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		var material := geometry.material_override as StandardMaterial3D
		if material == null:
			material = StandardMaterial3D.new()
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			geometry.material_override = material
		material.albedo_color = color
	for child in node.get_children():
		tint_preview(child, color)


static func disable_collisions(node: Node) -> void:
	if node == null:
		return
	if node is CollisionObject3D:
		var collision_object := node as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
		collision_object.input_ray_pickable = false
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	if node is CollisionPolygon3D:
		(node as CollisionPolygon3D).disabled = true
	for child in node.get_children():
		disable_collisions(child)


## Convert local Structure edge contributions into editor-only protected-side
## arrows. The input is plain dictionaries so this helper stays independent of
## Baker and is directly testable in headless mode.
static func build_local_cover_preview_records(contributions: Array, rotation_quarters: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for contribution_value in contributions:
		if not contribution_value is Dictionary:
			continue
		var contribution: Dictionary = contribution_value
		if not bool(contribution.get(&"enabled", true)):
			continue
		var world_direction := rotate_cardinal_direction(int(contribution.get(&"local_direction", 0)), rotation_quarters)
		for side in [&"A", &"B"]:
			var profile: Dictionary = contribution.get(&"profile_%s" % String(side).to_lower(), {})
			if not profile is Dictionary or int(profile.get(&"level", 0)) <= 0:
				continue
			var protected_direction := world_direction if side == &"B" else -world_direction
			var level := int(profile.get(&"level", 0))
			result.append({
				&"side": side,
				&"direction": protected_direction,
				&"profile_id": profile.get(&"id", &""),
				&"level": level,
				&"reduction": float(profile.get(&"reduction", profile.get(&"damage_reduction_ratio", 0.0))),
				&"color": profile.get(&"debug_color", Color(0.95, 0.72, 0.18, 0.9)),
				&"length_factor": 0.46 if level >= 2 else 0.32,
				&"width": 0.11 if level >= 2 else 0.065,
			})
	return result


## Build pure line/arrow records for baked cover edges. The caller supplies
## center_a/center_b in author-local space; no scene nodes or resources are
## created here.
static func build_cover_edge_visual_records(edges: Array, dimensions: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if dimensions.x <= 0.0 or dimensions.z <= 0.0:
		return result
	for edge_value in edges:
		if not edge_value is Dictionary:
			continue
		var edge: Dictionary = edge_value
		var diagnostic_only := bool(edge.get(&"diagnostic_only", false))
		if diagnostic_only:
			var diagnostic_position = edge.get(&"center_a", edge.get(&"position", Vector3.ZERO))
			if diagnostic_position is Vector3:
				result.append({
					&"edge_key": edge.get(&"edge_key", ""),
					&"diagnostic_only": true,
					&"invalid": true,
					&"position": diagnostic_position,
					&"color": Color(0.95, 0.05, 0.15, 0.92),
				})
			continue
		var center_a_value = edge.get(&"center_a", null)
		var center_b_value = edge.get(&"center_b", null)
		if not center_a_value is Vector3 or not center_b_value is Vector3:
			continue
		var center_a: Vector3 = center_a_value
		var center_b: Vector3 = center_b_value
		var delta: Vector3 = center_b - center_a
		delta.y = 0.0
		if delta.length_squared() <= 0.0001:
			continue
		var normal := delta.normalized()
		var is_cardinal := absf(normal.x) > 0.99 or absf(normal.z) > 0.99
		if not is_cardinal:
			continue
		var edge_center := (center_a + center_b) * 0.5
		var tangent := Vector3(-normal.z, 0.0, normal.x)
		var span := dimensions.x * 0.88 if absf(normal.z) > absf(normal.x) else dimensions.z * 0.88
		var line_from := edge_center - tangent * (span * 0.5)
		var line_to := edge_center + tangent * (span * 0.5)
		line_from.y += dimensions.y * 0.48
		line_to.y += dimensions.y * 0.48
		var profile_a: Dictionary = edge.get(&"profile_a", {})
		var profile_b: Dictionary = edge.get(&"profile_b", {})
		var level_a := int(profile_a.get(&"level", 0)) if profile_a is Dictionary else 0
		var level_b := int(profile_b.get(&"level", 0)) if profile_b is Dictionary else 0
		var invalid := bool(edge.get(&"invalid_or_conflict", false))
		if not invalid and level_a <= 0 and level_b <= 0:
			continue
		var strongest_level := maxi(level_a, level_b)
		var line_color := Color(0.95, 0.05, 0.15, 0.92) if invalid else _cover_profile_color(profile_b if level_b >= level_a else profile_a)
		var arrows: Array[Dictionary] = []
		if not invalid:
			if level_a > 0:
				arrows.append(_cover_arrow_record(edge_center, -normal, profile_a, dimensions))
			if level_b > 0:
				arrows.append(_cover_arrow_record(edge_center, normal, profile_b, dimensions))
		else:
			# Keep a red direction cue for profiles that survived a conflicting
			# source merge; invalid/no-profile diagnostics are represented by the
			# red boundary/marker instead.
			if level_a > 0:
				arrows.append(_cover_arrow_record(edge_center, -normal, profile_a, dimensions, true))
			if level_b > 0:
				arrows.append(_cover_arrow_record(edge_center, normal, profile_b, dimensions, true))
		result.append({
			&"edge_key": edge.get(&"edge_key", ""),
			&"diagnostic_only": false,
			&"invalid": invalid,
			&"line": {&"from": line_from, &"to": line_to, &"width": 0.10 if strongest_level >= 2 else 0.055, &"color": line_color},
			&"arrows": arrows,
			&"source": edge.get(&"source_type", &""),
		})
	return result


static func rotate_cardinal_direction(local_direction: int, rotation_quarters: int) -> Vector2i:
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	return directions[posmod(clampi(local_direction, 0, 3) - posmod(rotation_quarters, 4), 4)]


static func _cover_arrow_record(edge_center: Vector3, direction: Vector3, profile: Dictionary, dimensions: Vector3, invalid: bool = false) -> Dictionary:
	var normalized_direction := Vector3(direction.x, 0.0, direction.z).normalized()
	var level := int(profile.get(&"level", 0))
	var length := minf(dimensions.x, dimensions.z) * (0.46 if level >= 2 else 0.32)
	var from := edge_center + normalized_direction * 0.05
	from.y += dimensions.y * 0.52
	var to := from + normalized_direction * length
	return {
		&"from": from,
		&"to": to,
		&"direction": Vector2i(roundi(normalized_direction.x), roundi(normalized_direction.z)),
		&"width": 0.11 if level >= 2 else 0.065,
		&"color": Color(0.95, 0.05, 0.15, 0.92) if invalid else _cover_profile_color(profile),
		&"profile_id": profile.get(&"id", &""),
		&"level": level,
		&"reduction": float(profile.get(&"reduction", profile.get(&"damage_reduction_ratio", 0.0))),
	}


static func _cover_profile_color(profile: Dictionary) -> Color:
	var color = profile.get(&"debug_color", Color(0.95, 0.72, 0.18, 0.9)) if profile is Dictionary else Color(0.95, 0.72, 0.18, 0.9)
	return color if color is Color else Color(0.95, 0.72, 0.18, 0.9)
