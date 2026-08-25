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
