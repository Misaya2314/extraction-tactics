class_name EnvironmentObjectView
extends Node3D

## Presentation adapter for a runtime environment object.
##
## This node deliberately owns no HP, destruction or collision rules.  The
## Controller/EnvironmentObjectRuntimeState decides whether the object is
## active; this view only mirrors that decision and applies local feedback.

var _runtime_active: bool = true
var _visibility_allowed: bool = true
var _collision_shapes: Array[CollisionShape3D] = []
var _collision_objects: Array[CollisionObject3D] = []
var _collision_layers: Dictionary = {}
var _collision_masks: Dictionary = {}
var _rest_scales: Dictionary = {}
var _feedback_tween: Tween


func _ready() -> void:
	_collect_presentation_nodes(self)
	_apply_active_state()


func sync_from_runtime_state(state: Variant) -> void:
	if state == null:
		return
	if not (state is EnvironmentObjectRuntimeState):
		return
	var runtime_state := state as EnvironmentObjectRuntimeState
	set_runtime_active(runtime_state.active and not runtime_state.destroyed)


func apply_runtime_state(state: Variant) -> void:
	sync_from_runtime_state(state)


func set_runtime_active(active: bool) -> void:
	_runtime_active = active
	_apply_active_state()


func set_visibility_allowed(allowed: bool) -> void:
	_visibility_allowed = allowed
	visible = _runtime_active and _visibility_allowed


func play_damage_feedback() -> void:
	if not _runtime_active:
		return
	_stop_feedback()
	var targets: Array[Node3D] = []
	for child in get_children():
		if child is MeshInstance3D:
			targets.append(child as Node3D)
	if targets.is_empty():
		return
	_feedback_tween = create_tween()
	_feedback_tween.set_trans(Tween.TRANS_QUAD)
	_feedback_tween.set_ease(Tween.EASE_OUT)
	for target in targets:
		var rest: Vector3 = _rest_scales.get(target, target.scale)
		_feedback_tween.parallel().tween_property(target, NodePath("scale"), rest * 1.08, 0.06)
	var restore_tween := _feedback_tween.chain()
	for target in targets:
		var rest: Vector3 = _rest_scales.get(target, target.scale)
		restore_tween.parallel().tween_property(target, NodePath("scale"), rest, 0.10)


func play_destroy_feedback() -> void:
	_stop_feedback()
	set_runtime_active(false)


func _collect_presentation_nodes(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionShape3D:
			var shape := child as CollisionShape3D
			_collision_shapes.append(shape)
		if child is CollisionObject3D:
			var collision_object := child as CollisionObject3D
			_collision_objects.append(collision_object)
			_collision_layers[collision_object] = collision_object.collision_layer
			_collision_masks[collision_object] = collision_object.collision_mask
		if child is MeshInstance3D:
			_rest_scales[child] = (child as MeshInstance3D).scale
		_collect_presentation_nodes(child)


func _apply_active_state() -> void:
	visible = _runtime_active and _visibility_allowed
	for shape in _collision_shapes:
		if is_instance_valid(shape):
			shape.disabled = not _runtime_active
	for collision_object in _collision_objects:
		if not is_instance_valid(collision_object):
			continue
		collision_object.collision_layer = int(_collision_layers.get(collision_object, 0)) if _runtime_active else 0
		collision_object.collision_mask = int(_collision_masks.get(collision_object, 0)) if _runtime_active else 0
	if not _runtime_active:
		_stop_feedback()


func _stop_feedback() -> void:
	if is_instance_valid(_feedback_tween):
		_feedback_tween.kill()
	_feedback_tween = null
	for value in _rest_scales.keys():
		var mesh := value as MeshInstance3D
		if is_instance_valid(mesh):
			mesh.scale = _rest_scales[value]


func _exit_tree() -> void:
	_stop_feedback()
