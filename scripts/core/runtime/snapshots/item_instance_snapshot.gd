class_name ItemInstanceSnapshot
extends RefCounted

## Serializable identity DTO for one item instance. It intentionally contains
## no ItemDefinition, Resource, Node or placement rotation.

const CURRENT_SCHEMA_VERSION: int = 1
const ITEM_DEFINITION_TYPE: StringName = &"item"
const DefinitionKeyScript = preload("res://scripts/core/content/definition_key.gd")

var schema_version: int = CURRENT_SCHEMA_VERSION
var instance_id: StringName = &""
var definition_type: StringName = ITEM_DEFINITION_TYPE
var definition_id: StringName = &""
var state_version: int = 1


func _init(
		new_instance_id: Variant = &"",
		new_definition_id: Variant = &"",
		new_state_version: Variant = 1
	) -> void:
	if new_instance_id is StringName:
		instance_id = new_instance_id
	if new_definition_id is StringName:
		definition_id = new_definition_id
	if typeof(new_state_version) == TYPE_INT:
		state_version = new_state_version


func is_valid() -> bool:
	return schema_version == CURRENT_SCHEMA_VERSION \
		and instance_id != &"" \
		and definition_type == ITEM_DEFINITION_TYPE \
		and definition_id != &"" \
		and state_version == 1


func validate() -> bool:
	return is_valid()


func get_definition_key():
	return DefinitionKeyScript.new(definition_type, definition_id)


func to_dictionary() -> Dictionary:
	return {
		&"schema_version": schema_version,
		&"instance_id": instance_id,
		&"definition_type": definition_type,
		&"definition_id": definition_id,
		&"state_version": state_version,
	}


func to_dict() -> Dictionary:
	return to_dictionary()


static func from_dictionary(value: Variant):
	if typeof(value) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = value
	var required: Array[StringName] = [
		&"schema_version",
		&"instance_id",
		&"definition_type",
		&"definition_id",
		&"state_version",
	]
	for key in required:
		if not data.has(key):
			return null
	var raw_schema = data[&"schema_version"]
	var raw_instance = data[&"instance_id"]
	var raw_type = data[&"definition_type"]
	var raw_definition = data[&"definition_id"]
	var raw_state = data[&"state_version"]
	if typeof(raw_schema) != TYPE_INT or raw_schema != CURRENT_SCHEMA_VERSION:
		return null
	if not _is_string_name(raw_instance) or not _is_string_name(raw_type) or not _is_string_name(raw_definition):
		return null
	if typeof(raw_state) != TYPE_INT:
		return null
	var result := ItemInstanceSnapshot.new()
	result.schema_version = raw_schema
	result.instance_id = raw_instance
	result.definition_type = raw_type
	result.definition_id = raw_definition
	result.state_version = raw_state
	return result if result.is_valid() else null


static func from_dict(value: Variant):
	return from_dictionary(value)


func duplicate_snapshot() -> ItemInstanceSnapshot:
	var result := ItemInstanceSnapshot.new()
	result.schema_version = schema_version
	result.instance_id = instance_id
	result.definition_type = definition_type
	result.definition_id = definition_id
	result.state_version = state_version
	return result


static func _is_string_name(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING_NAME
