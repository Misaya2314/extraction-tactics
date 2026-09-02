class_name UnitInstanceFactory
extends RefCounted

## Creates the runtime pair for one map spawn.
##
## MapSpawnData and the content Resources are inputs only.  The factory owns
## the transaction that creates and registers one WeaponInstance followed by
## one UnitRuntimeState; neither the View nor UnitRuntimeState invents an ID.

const RuntimeOperationResultScript = preload("res://scripts/core/runtime/runtime_operation_result.gd")
const UnitRuntimeStateScript = preload("res://scripts/core/units/unit_runtime_state.gd")
const WeaponInstanceScript = preload("res://scripts/core/combat/weapon_instance.gd")
const MapSpawnDataScript = preload("res://scripts/core/map/map_spawn_data.gd")

var definition_registry: Variant
var runtime_instance_registry: RuntimeInstanceRegistry
var instance_id_generator: InstanceIdGenerator
var require_explicit_spawn_id: bool = false
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


func create_from_spawn(
		spawn: MapSpawnData,
		map_id: StringName,
		legacy_index: int = -1
) -> UnitRuntimeState:
	var result := create_from_spawn_result(spawn, map_id, legacy_index)
	return result.value as UnitRuntimeState if _result_is_success(result) else null


func create_unit(
		spawn: MapSpawnData,
		map_id: StringName,
		legacy_index: int = -1
) -> UnitRuntimeState:
	return create_from_spawn(spawn, map_id, legacy_index)


func create(
		spawn: MapSpawnData,
		map_id: StringName,
		legacy_index: int = -1
) -> UnitRuntimeState:
	return create_from_spawn(spawn, map_id, legacy_index)


func create_from_spawn_result(
		spawn: MapSpawnData,
		map_id: StringName,
		legacy_index: int = -1
) -> RuntimeOperationResult:
	last_result = _create_from_spawn_result(spawn, map_id, legacy_index)
	return last_result


func create_unit_result(
		spawn: MapSpawnData,
		map_id: StringName,
		legacy_index: int = -1
) -> RuntimeOperationResult:
	return create_from_spawn_result(spawn, map_id, legacy_index)


func create_result(
		spawn: MapSpawnData,
		map_id: StringName,
		legacy_index: int = -1
) -> RuntimeOperationResult:
	return create_from_spawn_result(spawn, map_id, legacy_index)


func get_last_result() -> RuntimeOperationResult:
	return last_result


func _create_from_spawn_result(
		spawn: MapSpawnData,
		map_id: StringName,
		legacy_index: int
) -> RuntimeOperationResult:
	if spawn == null or not (spawn is MapSpawnDataScript):
		return _failed(&"invalid_spawn", "A MapSpawnData resource is required.")
	if not _is_valid_token(map_id):
		return _failed(&"invalid_map_id", "A stable map_id is required.")
	if runtime_instance_registry == null or not runtime_instance_registry.has_method("register"):
		return _failed(&"missing_runtime_registry", "A RuntimeInstanceRegistry is required.")
	if instance_id_generator == null or not instance_id_generator.has_method("id_for_placement"):
		return _failed(&"missing_id_generator", "An InstanceIdGenerator is required.")

	var spawn_identity := spawn.get_stable_spawn_id(legacy_index)
	if spawn_identity.is_empty():
		return _failed(&"missing_spawn_id", "A stable spawn_id is required.")
	if not spawn.has_explicit_spawn_id():
		if require_explicit_spawn_id:
			return _failed(&"missing_spawn_id", "New unit content must provide an explicit spawn_id.", spawn_identity)
		push_warning("MapSpawnData '%s' has no spawn_id; using compatibility ID '%s'." % [spawn.unit_name, spawn_identity])

	var resolved_archetype: UnitArchetype = spawn.archetype
	if resolved_archetype == null or not resolved_archetype.is_valid():
		return _failed(&"invalid_archetype", "Map spawn '%s' has no valid UnitArchetype." % spawn_identity, spawn_identity)
	if not _definition_is_resolved(&"unit_archetype", resolved_archetype.archetype_id, resolved_archetype):
		return _failed(&"unresolved_archetype", "UnitArchetype '%s' is not present in the definition registry." % resolved_archetype.archetype_id, spawn_identity)

	var resolved_weapon: WeaponDefinition = spawn.weapon if spawn.weapon != null else resolved_archetype.default_weapon
	if resolved_weapon == null or not resolved_weapon.is_valid():
		return _failed(&"invalid_weapon", "Map spawn '%s' has no valid WeaponDefinition." % spawn_identity, spawn_identity)
	if not _definition_is_resolved(&"weapon", resolved_weapon.weapon_id, resolved_weapon):
		return _failed(&"unresolved_weapon", "WeaponDefinition '%s' is not present in the definition registry." % resolved_weapon.weapon_id, spawn_identity)

	var generator_state: Dictionary = {}
	if instance_id_generator.has_method("capture_state"):
		generator_state = instance_id_generator.capture_state()
	var weapon_instance_id: StringName = instance_id_generator.id_for_placement(
			&"weapon", map_id, spawn_identity
	)
	var unit_instance_id: StringName = instance_id_generator.id_for_placement(
			&"unit", map_id, spawn_identity
	)
	if weapon_instance_id.is_empty() or unit_instance_id.is_empty():
		_restore_generator_state(generator_state)
		return _failed(&"invalid_generated_id", "The factory could not create stable instance IDs.", spawn_identity)

	var weapon_instance: WeaponInstance = WeaponInstanceScript.new(weapon_instance_id, resolved_weapon)
	if not weapon_instance.is_valid(definition_registry):
		_restore_generator_state(generator_state)
		return _failed(&"invalid_weapon_instance", "The generated WeaponInstance is invalid.", weapon_instance_id)
	var unit_state: UnitRuntimeState = UnitRuntimeStateScript.new(
			unit_instance_id,
			resolved_archetype,
			spawn.faction,
			spawn.cell,
			weapon_instance
	)
	if not unit_state.is_valid(definition_registry):
		_restore_generator_state(generator_state)
		return _failed(&"invalid_unit_state", "The generated UnitRuntimeState is invalid.", unit_instance_id)

	var weapon_registration = runtime_instance_registry.register(weapon_instance)
	if not _result_is_success(weapon_registration):
		_restore_generator_state(generator_state)
		return _failed(&"weapon_register_failed", "WeaponInstance registration failed.", weapon_instance_id)
	var unit_registration = runtime_instance_registry.register(unit_state)
	if not _result_is_success(unit_registration):
		# The weapon was registered by this transaction.  It must never remain
		# as an orphan when the unit registration fails.
		runtime_instance_registry.unregister(weapon_instance.instance_id)
		_restore_generator_state(generator_state)
		return _failed(&"unit_register_failed", "UnitRuntimeState registration failed; transaction rolled back.", unit_instance_id)

	return RuntimeOperationResultScript.succeeded(unit_state, "Unit runtime pair created.", unit_state.instance_id)


func _definition_is_resolved(
		definition_type: StringName,
		definition_id: StringName,
		expected_definition: Resource
) -> bool:
	if definition_registry == null:
		return true
	if typeof(definition_registry) != TYPE_OBJECT:
		return false
	if definition_registry.has_method("resolve"):
		var resolved = definition_registry.call("resolve", definition_type, definition_id)
		if resolved == expected_definition:
			return true
		if definition_type == &"weapon":
			return resolved is WeaponDefinition and (resolved as WeaponDefinition).weapon_id == definition_id
		if definition_type == &"unit_archetype":
			return resolved is UnitArchetype and (resolved as UnitArchetype).archetype_id == definition_id
		return false
	if definition_registry.has_method("contains"):
		return bool(definition_registry.call("contains", definition_type, definition_id))
	return false


func _restore_generator_state(state: Dictionary) -> void:
	if not state.is_empty() and instance_id_generator != null and instance_id_generator.has_method("restore_state"):
		instance_id_generator.restore_state(state)


func _failed(code: StringName, message: String, related_id: StringName = &"") -> RuntimeOperationResult:
	return RuntimeOperationResultScript.failed(code, message, null, related_id)


func _result_is_success(result: Variant) -> bool:
	if result == null:
		return false
	if result is RuntimeOperationResult:
		return result.success
	if typeof(result) == TYPE_BOOL:
		return bool(result)
	if typeof(result) == TYPE_OBJECT and result.get("success") != null:
		return bool(result.success)
	return false


static func _is_valid_token(value: StringName) -> bool:
	var text := String(value).strip_edges()
	if text.is_empty():
		return false
	for character in ["\t", "\r", "\n", "/", "\\"]:
		if text.contains(character):
			return false
	return true
