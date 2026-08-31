class_name WeaponInstance
extends RuntimeInstance

## Runtime identity for one concrete weapon.
##
## WeaponDefinition remains shared, immutable content. This instance owns only
## the stable runtime identity and definition reference needed to resolve that
## content. Ammunition, durability and attachments are intentionally absent in
## this first implementation.

const DEFINITION_TYPE: StringName = &"weapon"
const DEFAULT_STATE_VERSION: int = 1
const WeaponInstanceSnapshotScript = preload("res://scripts/core/runtime/snapshots/weapon_instance_snapshot.gd")

var definition: WeaponDefinition
var state_version: int = DEFAULT_STATE_VERSION
var last_operation_reason: StringName = &""


func _init(new_instance_id: Variant = &"", new_definition: Variant = null) -> void:
	var resolved_instance_id: StringName = &""
	var resolved_definition: WeaponDefinition = null
	if new_instance_id is WeaponDefinition:
		resolved_definition = new_instance_id as WeaponDefinition
		resolved_instance_id = _coerce_string_name(new_definition)
	else:
		resolved_instance_id = _coerce_string_name(new_instance_id)
		if new_definition is WeaponDefinition:
			resolved_definition = new_definition as WeaponDefinition

	var resolved_definition_id: StringName = resolved_definition.weapon_id if resolved_definition != null else &""
	super(resolved_instance_id, DEFINITION_TYPE, resolved_definition_id)
	definition = resolved_definition


static func create(new_instance_id: StringName, new_definition: WeaponDefinition) -> WeaponInstance:
	return WeaponInstance.new(new_instance_id, new_definition)


static func from_definition(first: Variant, second: Variant = &"") -> WeaponInstance:
	## Accept both `(instance_id, definition)` and `(definition, instance_id)`
	## during migration so factories can converge without changing IDs.
	var resolved_id: StringName = &""
	var resolved_definition: WeaponDefinition = null
	if first is WeaponDefinition:
		resolved_definition = first as WeaponDefinition
		resolved_id = _coerce_string_name(second)
	else:
		resolved_id = _coerce_string_name(first)
		if second is WeaponDefinition:
			resolved_definition = second as WeaponDefinition
	return WeaponInstance.new(resolved_id, resolved_definition)


func is_valid(registry: Variant = null) -> bool:
	return (
		is_valid_identity()
		and definition_type == DEFINITION_TYPE
		and definition != null
		and definition.is_valid()
		and definition_id == definition.weapon_id
		and state_version == DEFAULT_STATE_VERSION
		and _definition_is_resolved(registry)
	)


func validate() -> bool:
	return is_valid()


func get_definition_id() -> StringName:
	return definition_id


func get_definition_type() -> StringName:
	return definition_type


func get_definition_key() -> DefinitionKey:
	return definition_key()


func bind_definition(resolved_definition: WeaponDefinition) -> bool:
	## Resolve a definition during hydration without changing the identity key.
	if resolved_definition == null or not resolved_definition.is_valid():
		last_operation_reason = &"invalid_definition"
		return false
	if definition_id != &"" and definition_id != resolved_definition.weapon_id:
		last_operation_reason = &"definition_mismatch"
		return false
	definition = resolved_definition
	definition_id = resolved_definition.weapon_id
	last_operation_reason = &"definition_bound"
	return true


func to_snapshot() -> Dictionary:
	## RuntimeInstance exposes a dictionary snapshot contract. Keep the
	## concrete DTO available through to_snapshot_resource() for callers that
	## need typed validation without putting a Resource/Node in generic state.
	var payload := to_snapshot_resource().to_dictionary()
	payload[&"definition_type"] = definition_type
	return payload


func to_snapshot_resource() -> WeaponInstanceSnapshot:
	var snapshot: WeaponInstanceSnapshot = WeaponInstanceSnapshotScript.new()
	snapshot.instance_id = instance_id
	snapshot.definition_id = definition_id
	snapshot.state_version = state_version
	return snapshot


static func from_snapshot(
	snapshot: Variant,
	resolved_definition: WeaponDefinition = null,
) -> WeaponInstance:
	var result := WeaponInstance.new()
	if not result.hydrate_from_snapshot(snapshot, resolved_definition):
		return null
	return result


func hydrate_from_snapshot(
	snapshot: Variant,
	resolved_definition: WeaponDefinition = null,
) -> bool:
	## Direct assignment is intentional: hydration must not emit gameplay
	## events, spend AP, or invoke any presentation path.
	if resolved_definition == null:
		last_operation_reason = &"missing_definition"
		return false
	var typed_snapshot: WeaponInstanceSnapshot = _coerce_snapshot(snapshot)
	if typed_snapshot == null:
		last_operation_reason = &"invalid_snapshot"
		return false
	if not typed_snapshot.is_valid():
		last_operation_reason = &"invalid_snapshot"
		return false
	if not resolved_definition.is_valid() or resolved_definition.weapon_id != typed_snapshot.definition_id:
		last_operation_reason = &"definition_mismatch"
		return false

	instance_id = typed_snapshot.instance_id
	definition_id = typed_snapshot.definition_id
	state_version = typed_snapshot.state_version
	definition = resolved_definition
	last_operation_reason = &"hydrated"
	return true


func copy() -> WeaponInstance:
	## A runtime copy cannot preserve the stable identity.  Keep this legacy
	## entry point explicit and inert until a factory-backed clone API exists.
	last_operation_reason = &"copy_not_supported"
	return null


static func _coerce_snapshot(value: Variant) -> WeaponInstanceSnapshot:
	if value is WeaponInstanceSnapshot:
		return value as WeaponInstanceSnapshot
	if value is Dictionary:
		return WeaponInstanceSnapshotScript.from_dictionary(value)
	return null


func _definition_is_resolved(registry: Variant) -> bool:
	if registry == null:
		return true
	if typeof(registry) != TYPE_OBJECT:
		return false
	if registry is RuntimeInstanceRegistry:
		return false
	if registry.has_method("resolve"):
		var resolved = registry.call("resolve", DEFINITION_TYPE, definition_id)
		return resolved is WeaponDefinition and (resolved as WeaponDefinition).weapon_id == definition_id
	if registry.has_method("contains"):
		return bool(registry.call("contains", DEFINITION_TYPE, definition_id))
	return false


static func _coerce_string_name(value: Variant) -> StringName:
	if value is StringName or value is String:
		return StringName(value)
	return &""
