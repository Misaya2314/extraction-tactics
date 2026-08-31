class_name ItemInstanceFactory
extends RefCounted

## The only production entry point for creating or hydrating item instances.
## Definitions are resolved by stable key during hydration; no fallback
## resource and no local counter is allowed here.

const ItemDefinitionScript = preload("res://scripts/core/items/item_definition.gd")
const InventoryItemInstanceScript = preload("res://scripts/core/inventory/inventory_item_instance.gd")
const ItemInstanceSnapshotScript = preload("res://scripts/core/runtime/snapshots/item_instance_snapshot.gd")
const DefinitionKeyScript = preload("res://scripts/core/content/definition_key.gd")
const RuntimeOperationResultScript = preload("res://scripts/core/runtime/runtime_operation_result.gd")

var id_generator
var registry
var runtime_registry
var last_reason_code: StringName = &""
var _registered_instances: Dictionary = {}


func _init(new_id_generator = null, new_registry = null, new_runtime_registry = null) -> void:
	if new_id_generator != null:
		configure(new_id_generator, new_registry, new_runtime_registry)
	else:
		registry = new_registry
		set_runtime_registry(new_runtime_registry)


func configure(new_id_generator, new_registry = null, new_runtime_registry = null) -> bool:
	if new_id_generator == null or typeof(new_id_generator) != TYPE_OBJECT or not new_id_generator.has_method("next_id"):
		last_reason_code = &"missing_id_generator"
		return false
	if new_runtime_registry != null and not _is_runtime_registry(new_runtime_registry):
		last_reason_code = &"invalid_runtime_registry"
		return false
	id_generator = new_id_generator
	registry = new_registry
	runtime_registry = new_runtime_registry
	last_reason_code = &"configured"
	return true


func set_runtime_registry(new_runtime_registry) -> bool:
	if new_runtime_registry != null and not _is_runtime_registry(new_runtime_registry):
		last_reason_code = &"invalid_runtime_registry"
		return false
	runtime_registry = new_runtime_registry
	last_reason_code = &"runtime_registry_configured" if new_runtime_registry != null else &"runtime_registry_cleared"
	return true


func get_runtime_registry():
	return runtime_registry


func create(definition: Variant):
	if not definition is ItemDefinition:
		last_reason_code = &"invalid_definition"
		return null
	var typed_definition: ItemDefinition = definition as ItemDefinition
	if not typed_definition.is_valid():
		last_reason_code = &"invalid_definition"
		return null
	if id_generator == null or typeof(id_generator) != TYPE_OBJECT or not id_generator.has_method("next_id"):
		last_reason_code = &"missing_id_generator"
		return null
	var generator_state = capture_generator_state()
	var generated_id = id_generator.call("next_id", &"item")
	if not generated_id is StringName or generated_id == &"":
		_restore_generator_state_after_failure(generator_state)
		last_reason_code = &"id_generation_failed"
		return null
	var result := InventoryItemInstanceScript.new(generated_id, typed_definition)
	if not result.is_valid():
		_restore_generator_state_after_failure(generator_state)
		last_reason_code = &"instance_creation_failed"
		return null
	if not _register_runtime_instance(result):
		_restore_generator_state_after_failure(generator_state)
		return null
	last_reason_code = &"ok"
	return result


func create_result(definition: Variant):
	var instance = create(definition)
	if instance == null:
		return RuntimeOperationResultScript.failed(last_reason_code, "Unable to create ItemInstance.")
	return RuntimeOperationResultScript.succeeded(instance, "ItemInstance created.", instance.instance_id)


func hydrate(snapshot: Variant, registry_override = null):
	var active_registry = registry_override if registry_override != null else registry
	if active_registry == null or typeof(active_registry) != TYPE_OBJECT or (not active_registry.has_method("resolve_key") and not active_registry.has_method("resolve")):
		last_reason_code = &"missing_registry"
		return null
	var typed_snapshot = _coerce_snapshot(snapshot)
	if typed_snapshot == null or not typed_snapshot.is_valid():
		last_reason_code = &"invalid_snapshot"
		return null
	if typed_snapshot.definition_type != &"item":
		last_reason_code = &"definition_type_mismatch"
		return null
	var definition_key := DefinitionKeyScript.new(typed_snapshot.definition_type, typed_snapshot.definition_id)
	if not definition_key.is_valid():
		last_reason_code = &"invalid_definition_key"
		return null
	var resolved = active_registry.call("resolve_key", definition_key) if active_registry.has_method("resolve_key") else active_registry.call("resolve", definition_key.definition_type, definition_key.definition_id)
	if not resolved is ItemDefinition or not (resolved as ItemDefinition).is_valid():
		last_reason_code = &"missing_definition"
		return null
	var result := InventoryItemInstanceScript.new()
	if not result.hydrate_from_snapshot(typed_snapshot, active_registry):
		last_reason_code = &"hydrate_failed"
		return null
	var generator_state = capture_generator_state()
	if not _reserve_hydrated_id(typed_snapshot.instance_id):
		_restore_generator_state_after_failure(generator_state)
		return null
	if not _register_runtime_instance(result):
		_restore_generator_state_after_failure(generator_state)
		return null
	last_reason_code = &"ok"
	return result


func hydrate_result(snapshot: Variant, registry_override = null):
	var instance = hydrate(snapshot, registry_override)
	if instance == null:
		return RuntimeOperationResultScript.failed(last_reason_code, "Unable to hydrate ItemInstance.")
	return RuntimeOperationResultScript.succeeded(instance, "ItemInstance hydrated.", instance.instance_id)


func restore_from_snapshot(snapshot: Variant, registry_override = null):
	return hydrate(snapshot, registry_override)


func capture_generator_state():
	if id_generator != null and typeof(id_generator) == TYPE_OBJECT and id_generator.has_method("capture_state"):
		return id_generator.call("capture_state")
	return null


func restore_generator_state(state: Variant) -> bool:
	if state == null or id_generator == null or typeof(id_generator) != TYPE_OBJECT or not id_generator.has_method("restore_state"):
		return false
	return bool(id_generator.call("restore_state", state))


func discard_instance(instance: Variant) -> bool:
	if not instance is InventoryItemInstance:
		last_reason_code = &"invalid_instance"
		return false
	var typed_instance: InventoryItemInstance = instance as InventoryItemInstance
	var tracked = _registered_instances.get(typed_instance.instance_id)
	if tracked != typed_instance:
		last_reason_code = &"instance_not_owned_by_factory"
		return false
	if runtime_registry != null and not _unregister_runtime_instance(typed_instance.instance_id):
		return false
	_registered_instances.erase(typed_instance.instance_id)
	last_reason_code = &"ok"
	return true


func _reserve_hydrated_id(instance_id: StringName) -> bool:
	if id_generator == null or typeof(id_generator) != TYPE_OBJECT:
		return true
	if id_generator.has_method("is_reserved") and bool(id_generator.call("is_reserved", instance_id)):
		return true
	if not id_generator.has_method("reserve"):
		return true
	if bool(id_generator.call("reserve", instance_id)):
		return true
	last_reason_code = &"instance_id_already_reserved"
	return false


func _register_runtime_instance(instance: InventoryItemInstance) -> bool:
	if runtime_registry == null:
		return true
	var registration = runtime_registry.call("register", instance)
	if not _operation_succeeded(registration):
		last_reason_code = _operation_reason(registration, &"runtime_registration_failed")
		return false
	_registered_instances[instance.instance_id] = instance
	return true


func _unregister_runtime_instance(instance_id: StringName) -> bool:
	if runtime_registry == null:
		return true
	var unregistration = runtime_registry.call("unregister", instance_id)
	if not _operation_succeeded(unregistration):
		last_reason_code = _operation_reason(unregistration, &"runtime_unregistration_failed")
		return false
	return true


func _restore_generator_state_after_failure(state) -> void:
	if state != null:
		restore_generator_state(state)


func _is_runtime_registry(value: Variant) -> bool:
	return typeof(value) == TYPE_OBJECT and value.has_method("register") and value.has_method("unregister")


func _operation_succeeded(value: Variant) -> bool:
	if value is bool:
		return value
	if value == null or typeof(value) != TYPE_OBJECT:
		return false
	return bool(value.get("success"))


func _operation_reason(value: Variant, fallback: StringName) -> StringName:
	if value != null and typeof(value) == TYPE_OBJECT:
		var raw_reason = value.get("reason_code")
		if raw_reason is StringName and raw_reason != &"":
			return raw_reason
	return fallback


func _coerce_snapshot(value: Variant):
	if value is ItemInstanceSnapshot:
		return value
	if value is Dictionary:
		return ItemInstanceSnapshotScript.from_dictionary(value)
	return null
