class_name EnvironmentObjectFactory
extends RefCounted

## Creates and hydrates EnvironmentObjectRuntimeState instances from explicit
## content and authoring placement data.  Production creation always uses the
## shared definition registry, runtime registry and ID generator; there is no
## local fallback ID source.

const INSTANCE_TYPE: StringName = &"environment"
const DEFINITION_TYPE: StringName = &"placeable"
const RuntimeOperationResultScript = preload("res://scripts/core/runtime/runtime_operation_result.gd")
const EnvironmentObjectRuntimeStateScript = preload("res://scripts/core/environment/environment_object_runtime_state.gd")

var definition_registry: Variant
var runtime_instance_registry: RuntimeInstanceRegistry
var instance_id_generator: InstanceIdGenerator
var last_result: RuntimeOperationResult


func _init(
		new_definition_registry: Variant = null,
		new_runtime_instance_registry: Variant = null,
		new_instance_id_generator: Variant = null
) -> void:
	definition_registry = new_definition_registry
	runtime_instance_registry = new_runtime_instance_registry
	instance_id_generator = new_instance_id_generator


func configure(
		new_definition_registry: Variant,
		new_runtime_instance_registry: Variant,
		new_instance_id_generator: Variant
) -> bool:
	if new_runtime_instance_registry == null or new_instance_id_generator == null:
		return false
	definition_registry = new_definition_registry
	runtime_instance_registry = new_runtime_instance_registry
	instance_id_generator = new_instance_id_generator
	return true


func create_from_placement(
		placement: Variant,
		map_id: Variant
) -> EnvironmentObjectRuntimeState:
	var result := create_from_placement_result(placement, map_id)
	return result.value as EnvironmentObjectRuntimeState if _result_is_success(result) else null


func create_environment_object(
		placement: Variant,
		map_id: Variant
) -> EnvironmentObjectRuntimeState:
	return create_from_placement(placement, map_id)


func create(
		placement: Variant,
		map_id: Variant
) -> EnvironmentObjectRuntimeState:
	return create_from_placement(placement, map_id)


func create_from_placement_result(
		placement: Variant,
		map_id: Variant
) -> RuntimeOperationResult:
	last_result = _create_from_placement_result(placement, map_id)
	return last_result


func create_result(
		placement: Variant,
		map_id: Variant
) -> RuntimeOperationResult:
	return create_from_placement_result(placement, map_id)


func hydrate_from_snapshot(snapshot: Variant) -> EnvironmentObjectRuntimeState:
	var result := hydrate_from_snapshot_result(snapshot)
	return result.value as EnvironmentObjectRuntimeState if _result_is_success(result) else null


func hydrate_from_snapshot_result(snapshot: Variant) -> RuntimeOperationResult:
	last_result = _hydrate_from_snapshot_result(snapshot)
	return last_result


func get_last_result() -> RuntimeOperationResult:
	return last_result


func _create_from_placement_result(placement_value: Variant, map_id_value: Variant) -> RuntimeOperationResult:
	if not placement_value is MapObjectPlacement:
		return _failed(&"invalid_placement", "A MapObjectPlacement resource is required.")
	if typeof(map_id_value) != TYPE_STRING_NAME or not _is_valid_token(map_id_value):
		return _failed(&"invalid_map_id", "A stable map_id is required.")
	if runtime_instance_registry == null or not runtime_instance_registry.has_method("register"):
		return _failed(&"missing_runtime_registry", "A RuntimeInstanceRegistry is required.")
	if instance_id_generator == null or not instance_id_generator.has_method("id_for_placement"):
		return _failed(&"missing_id_generator", "An InstanceIdGenerator is required.")
	if definition_registry == null or not definition_registry.has_method("resolve"):
		return _failed(&"missing_definition_registry", "A GameDefinitionRegistry is required.")
	var placement := placement_value as MapObjectPlacement
	if not _is_valid_token(placement.object_id):
		return _failed(&"invalid_placement_id", "A stable object placement ID is required.")
	var definition_result := _resolve_placement_definition(placement)
	if not bool(definition_result.get(&"success", false)):
		return _failed(
			StringName(definition_result.get(&"reason_code", &"missing_definition")),
			String(definition_result.get(&"message", "Environment object Definition could not be resolved.")),
			placement.object_id
		)
	var resolved_definition := definition_result.get(&"definition", null) as TacticalObjectDefinition
	if resolved_definition == null:
		return _failed(&"invalid_definition", "The resolved Definition is not a TacticalObjectDefinition.", placement.object_id)
	var generator_state := _capture_generator_state()
	var instance_id: StringName = instance_id_generator.id_for_placement(INSTANCE_TYPE, map_id_value, placement.object_id)
	if instance_id.is_empty():
		_restore_generator_state(generator_state)
		return _failed(&"invalid_generated_id", "The environment object ID could not be generated.", placement.object_id)
	var state: EnvironmentObjectRuntimeState = EnvironmentObjectRuntimeStateScript.new(instance_id, resolved_definition, placement)
	if not state.is_valid(definition_registry):
		_restore_generator_state(generator_state)
		return _failed(&"invalid_runtime_state", "The generated EnvironmentObjectRuntimeState is invalid.", instance_id)
	var registration = runtime_instance_registry.register(state)
	if not _result_is_success(registration):
		_restore_generator_state(generator_state)
		var reason := StringName(registration.reason_code) if registration is RuntimeOperationResult else &"register_failed"
		return _failed(reason, "Environment object registration failed; creation was rolled back.", instance_id)
	return RuntimeOperationResultScript.succeeded(state, "Environment object runtime state created.", instance_id)


func _hydrate_from_snapshot_result(snapshot: Variant) -> RuntimeOperationResult:
	if runtime_instance_registry == null or not runtime_instance_registry.has_method("register"):
		return _failed(&"missing_runtime_registry", "A RuntimeInstanceRegistry is required to hydrate an environment object.")
	if instance_id_generator == null or not instance_id_generator.has_method("reserve"):
		return _failed(&"missing_id_generator", "An InstanceIdGenerator is required to hydrate an environment object.")
	if definition_registry == null or not definition_registry.has_method("resolve"):
		return _failed(&"missing_definition_registry", "A GameDefinitionRegistry is required to hydrate an environment object.")
	if typeof(snapshot) != TYPE_DICTIONARY:
		return _failed(&"invalid_snapshot", "EnvironmentObjectSnapshot must be a Dictionary.")
	var data: Dictionary = snapshot
	if typeof(data.get(&"instance_id", null)) != TYPE_STRING_NAME:
		return _failed(&"invalid_snapshot", "EnvironmentObjectSnapshot instance_id must be a StringName.")
	if typeof(data.get(&"definition_type", null)) != TYPE_STRING_NAME or data[&"definition_type"] != DEFINITION_TYPE:
		return _failed(&"invalid_snapshot", "EnvironmentObjectSnapshot definition_type is invalid.")
	if typeof(data.get(&"definition_id", null)) != TYPE_STRING_NAME:
		return _failed(&"invalid_snapshot", "EnvironmentObjectSnapshot definition_id must be a StringName.")
	var snapshot_id: StringName = data[&"instance_id"]
	var definition_id: StringName = data[&"definition_id"]
	if not _is_valid_token(snapshot_id) or not _is_valid_token(definition_id):
		return _failed(&"invalid_snapshot", "EnvironmentObjectSnapshot identity is invalid.", snapshot_id)
	var resolved = definition_registry.resolve(DEFINITION_TYPE, definition_id)
	if not resolved is TacticalObjectDefinition:
		return _failed(&"missing_definition", "Environment object Definition could not be resolved from the snapshot.", snapshot_id)
	var resolved_definition := resolved as TacticalObjectDefinition
	if not resolved_definition.is_valid():
		return _failed(&"invalid_definition", "The snapshot Definition is invalid.", snapshot_id)
	if runtime_instance_registry.contains(snapshot_id):
		return _failed(&"duplicate_instance_id", "Runtime instance ID is already registered.", snapshot_id)
	var generator_state := _capture_generator_state()
	if not instance_id_generator.is_reserved(snapshot_id):
		if not instance_id_generator.reserve(snapshot_id):
			_restore_generator_state(generator_state)
			return _failed(&"id_reservation_failed", "The snapshot instance ID could not be reserved.", snapshot_id)
	var state: EnvironmentObjectRuntimeState = EnvironmentObjectRuntimeStateScript.new()
	if not state.hydrate_from_snapshot(snapshot, resolved_definition, definition_registry):
		_restore_generator_state(generator_state)
		return _failed(&"invalid_snapshot", "EnvironmentObjectSnapshot values failed validation.", snapshot_id)
	var registration = runtime_instance_registry.register(state)
	if not _result_is_success(registration):
		_restore_generator_state(generator_state)
		var reason := StringName(registration.reason_code) if registration is RuntimeOperationResult else &"register_failed"
		return _failed(reason, "Environment object hydration was rolled back.", snapshot_id)
	return RuntimeOperationResultScript.succeeded(state, "Environment object runtime state hydrated.", snapshot_id)


func _resolve_placement_definition(placement: MapObjectPlacement) -> Dictionary:
	if placement.definition_id != &"":
		var direct = definition_registry.resolve(DEFINITION_TYPE, placement.definition_id)
		if direct == null:
			return _definition_failure(&"missing_definition", "Environment object Definition '%s' could not be resolved." % placement.definition_id)
		if not direct is TacticalObjectDefinition:
			return _definition_failure(&"invalid_definition", "Definition '%s' is not a TacticalObjectDefinition." % placement.definition_id)
		if not (direct as TacticalObjectDefinition).is_valid():
			return _definition_failure(&"invalid_definition", "Environment object Definition '%s' is invalid." % placement.definition_id)
		return {&"success": true, &"definition": direct}

	var candidates: Array[TacticalObjectDefinition] = []
	var definitions = definition_registry.get_all(DEFINITION_TYPE) if definition_registry.has_method("get_all") else []
	for definition_value in definitions:
		if not definition_value is TacticalObjectDefinition:
			continue
		var definition := definition_value as TacticalObjectDefinition
		if not definition.is_valid() or not _legacy_kind_matches(definition.object_kind, placement.kind):
			continue
		if placement.scene != null:
			if not _same_scene(definition.scene, placement.scene):
				continue
		candidates.append(definition)
	if candidates.size() == 1:
		return {&"success": true, &"definition": candidates[0]}
	if candidates.is_empty():
		return _definition_failure(&"missing_definition", "Legacy environment placement '%s' has no unique matching Definition." % placement.object_id)
	return _definition_failure(&"ambiguous_definition", "Legacy environment placement '%s' matches multiple Definitions." % placement.object_id)


static func _legacy_kind_matches(object_kind: StringName, placement_kind: int) -> bool:
	var expected := ""
	match placement_kind:
		MapObjectPlacement.Kind.LOOT:
			expected = "loot"
		MapObjectPlacement.Kind.EXTRACTION:
			expected = "extraction"
		MapObjectPlacement.Kind.EXPLOSIVE:
			expected = "explosive"
		MapObjectPlacement.Kind.DOOR:
			expected = "door"
		MapObjectPlacement.Kind.GENERIC:
			expected = "generic"
		_:
			return false
	var actual := String(object_kind).to_lower()
	return actual == expected or (expected != "generic" and actual.contains(expected))


static func _same_scene(first: PackedScene, second: PackedScene) -> bool:
	if first == null or second == null:
		return false
	if first == second:
		return true
	var first_path := String(first.resource_path)
	var second_path := String(second.resource_path)
	return not first_path.is_empty() and first_path == second_path


static func _definition_failure(reason_code: StringName, message: String) -> Dictionary:
	return {&"success": false, &"reason_code": reason_code, &"message": message}


func _capture_generator_state() -> Dictionary:
	if instance_id_generator != null and instance_id_generator.has_method("capture_state"):
		return instance_id_generator.capture_state()
	return {}


func _restore_generator_state(state: Dictionary) -> void:
	if not state.is_empty() and instance_id_generator != null and instance_id_generator.has_method("restore_state"):
		instance_id_generator.restore_state(state)


func _failed(reason_code: StringName, message: String, related_id: StringName = &"") -> RuntimeOperationResult:
	return RuntimeOperationResultScript.failed(reason_code, message, null, related_id)


func _result_is_success(result: Variant) -> bool:
	if result is RuntimeOperationResult:
		return result.success
	if typeof(result) == TYPE_BOOL:
		return bool(result)
	return false


static func _is_valid_token(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING_NAME:
		return false
	var text := String(value).strip_edges()
	if text.is_empty():
		return false
	for character in ["\t", "\r", "\n", "/", "\\"]:
		if text.contains(character):
			return false
	return true
