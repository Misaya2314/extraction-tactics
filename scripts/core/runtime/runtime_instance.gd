class_name RuntimeInstance
extends RefCounted

## Intentionally thin identity base. Domain state belongs to later instances,
## not to this shared identity contract.

const DefinitionKeyScript = preload("res://scripts/core/content/definition_key.gd")

var instance_id: StringName = &""
var definition_type: StringName = &""
var definition_id: StringName = &""


func _init(
	new_instance_id: StringName = &"",
	new_definition_type: StringName = &"",
	new_definition_id: StringName = &""
) -> void:
	instance_id = new_instance_id
	definition_type = new_definition_type
	definition_id = new_definition_id


func configure_identity(new_instance_id: StringName, new_definition_type: StringName, new_definition_id: StringName) -> bool:
	if not _is_valid_instance_id(new_instance_id):
		return false
	if not DefinitionKeyScript.new(new_definition_type, new_definition_id).is_valid():
		return false
	instance_id = new_instance_id
	definition_type = new_definition_type
	definition_id = new_definition_id
	return true


func definition_key():
	return DefinitionKeyScript.new(definition_type, definition_id)


func get_stable_instance_id() -> StringName:
	return instance_id


func get_definition_key():
	return definition_key()


func is_valid_identity() -> bool:
	return _is_valid_instance_id(instance_id) and definition_key().is_valid()


func is_valid(registry = null) -> bool:
	if not is_valid_identity():
		return false
	if registry != null:
		if typeof(registry) != TYPE_OBJECT or not registry.has_method("contains"):
			return false
		return bool(registry.contains(definition_type, definition_id))
	return true


func to_snapshot() -> Dictionary:
	return {
		&"instance_id": instance_id,
		&"definition_type": definition_type,
		&"definition_id": definition_id,
	}


static func _is_valid_instance_id(value: StringName) -> bool:
	var text := String(value).strip_edges()
	if text.is_empty():
		return false
	for character in ["\t", "\r", "\n", "/", "\\"]:
		if text.contains(character):
			return false
	return true
