class_name RuntimeInstanceRegistry
extends RefCounted

## Identity index only. It does not own domain state or create Node instances.

const RuntimeOperationResultScript = preload("res://scripts/core/runtime/runtime_operation_result.gd")

var _instances: Dictionary = {}
var _order: Array[StringName] = []


func register(instance):
	if instance == null:
		return RuntimeOperationResultScript.failed(&"invalid_instance", "RuntimeInstance is required.")
	if typeof(instance) != TYPE_OBJECT or not instance.has_method("is_valid_identity"):
		return RuntimeOperationResultScript.failed(&"invalid_instance", "A RuntimeInstance identity object is required.")
	if not instance.is_valid_identity():
		return RuntimeOperationResultScript.failed(&"invalid_instance_identity", "RuntimeInstance identity is empty or invalid.", null, instance.instance_id)
	if _instances.has(instance.instance_id):
		return RuntimeOperationResultScript.failed(&"duplicate_instance_id", "Runtime instance ID '%s' is already registered." % instance.instance_id, null, instance.instance_id)
	_instances[instance.instance_id] = instance
	_order.append(instance.instance_id)
	return RuntimeOperationResultScript.succeeded(instance, "RuntimeInstance registered.", instance.instance_id)


func get_instance(instance_id: StringName):
	return _instances.get(instance_id)


func find(instance_id: StringName):
	return get_instance(instance_id)


func contains(instance_id: StringName) -> bool:
	return _instances.has(instance_id)


func unregister(instance_id: StringName):
	if not _instances.has(instance_id):
		return RuntimeOperationResultScript.failed(&"instance_not_found", "Runtime instance ID '%s' is not registered." % instance_id, null, instance_id)
	var removed = _instances[instance_id]
	_instances.erase(instance_id)
	_order.erase(instance_id)
	return RuntimeOperationResultScript.succeeded(removed, "RuntimeInstance unregistered.", instance_id)


func get_all() -> Array[RefCounted]:
	var result: Array[RefCounted] = []
	for instance_id in _order:
		var instance := _instances.get(instance_id) as RefCounted
		if instance != null:
			result.append(instance)
	return result


func clear() -> void:
	_instances.clear()
	_order.clear()


func size() -> int:
	return _order.size()
