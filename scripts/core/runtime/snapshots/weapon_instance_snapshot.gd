class_name WeaponInstanceSnapshot
extends RefCounted

## Serializable DTO for one weapon instance.
##
## This type deliberately stores only identity and a state version.  The
## WeaponDefinition is resolved by the caller during hydration and never
## becomes part of the snapshot payload.

const CURRENT_STATE_VERSION: int = 1

var instance_id: StringName = &""
var definition_id: StringName = &""
var state_version: int = CURRENT_STATE_VERSION


func _init(
	new_instance_id: Variant = &"",
	new_definition_id: Variant = &"",
	new_state_version: int = CURRENT_STATE_VERSION,
) -> void:
	instance_id = _coerce_string_name(new_instance_id)
	definition_id = _coerce_string_name(new_definition_id)
	state_version = new_state_version


func is_valid() -> bool:
	return instance_id != &"" and definition_id != &"" and state_version == CURRENT_STATE_VERSION


func get_definition_id() -> StringName:
	return definition_id


func to_dictionary() -> Dictionary:
	return {
		&"instance_id": String(instance_id),
		&"definition_id": String(definition_id),
		&"state_version": state_version,
	}


func to_dict() -> Dictionary:
	return to_dictionary()


static func from_dictionary(data: Dictionary) -> WeaponInstanceSnapshot:
	if data == null:
		return null
	if not _has_field(data, &"instance_id") or not _has_field(data, &"definition_id") or not _has_field(data, &"state_version"):
		return null
	var raw_instance_id: Variant = _field(data, &"instance_id")
	var raw_definition_id: Variant = _field(data, &"definition_id")
	var raw_state_version: Variant = _field(data, &"state_version")
	if not _is_string_value(raw_instance_id) or not _is_string_value(raw_definition_id):
		return null
	if typeof(raw_state_version) != TYPE_INT:
		return null
	var snapshot := WeaponInstanceSnapshot.new(raw_instance_id, raw_definition_id, int(raw_state_version))
	return snapshot if snapshot.is_valid() else null


static func from_dict(data: Dictionary) -> WeaponInstanceSnapshot:
	return from_dictionary(data)


func duplicate_snapshot() -> WeaponInstanceSnapshot:
	return WeaponInstanceSnapshot.new(instance_id, definition_id, state_version)


static func _has_field(data: Dictionary, key: StringName) -> bool:
	return data.has(key) or data.has(String(key))


static func _field(data: Dictionary, key: StringName) -> Variant:
	return data[key] if data.has(key) else data[String(key)]


static func _is_string_value(value: Variant) -> bool:
	return value is StringName or value is String


func _coerce_string_name(value: Variant) -> StringName:
	if value is StringName or value is String:
		return StringName(value)
	return &""
