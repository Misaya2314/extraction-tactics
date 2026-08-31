@tool
class_name DefinitionKey
extends RefCounted

## Stable content identity. A bare ID is only meaningful inside its type
## namespace, so both fields are intentionally part of the public contract.

const KEY_SEPARATOR := "/"

var definition_type: StringName = &""
var definition_id: StringName = &""


func _init(type: Variant = &"", id: Variant = &"") -> void:
	definition_type = _coerce_component(type)
	definition_id = _coerce_component(id)


static func from_values(type: Variant, id: Variant) -> DefinitionKey:
	return DefinitionKey.new(type, id)


static func from_dictionary(value: Variant) -> DefinitionKey:
	if typeof(value) != TYPE_DICTIONARY:
		return DefinitionKey.new()
	var dictionary: Dictionary = value
	var raw_type = dictionary.get(&"definition_type", null)
	var raw_id = dictionary.get(&"definition_id", null)
	if not _is_string_like(raw_type) or not _is_string_like(raw_id):
		return DefinitionKey.new()
	return DefinitionKey.new(_coerce_component(raw_type), _coerce_component(raw_id))


func is_valid() -> bool:
	return _is_valid_component(definition_type) and _is_valid_component(definition_id)


func key_string() -> String:
	return "%s%s%s" % [String(definition_type), KEY_SEPARATOR, String(definition_id)]


func equals(other: DefinitionKey) -> bool:
	return other != null \
		and definition_type == other.definition_type \
		and definition_id == other.definition_id


func is_equal(other: DefinitionKey) -> bool:
	return equals(other)


func duplicate_key() -> DefinitionKey:
	return DefinitionKey.new(definition_type, definition_id)


func to_dictionary() -> Dictionary:
	return {
		&"definition_type": definition_type,
		&"definition_id": definition_id,
	}


func _to_string() -> String:
	return key_string()


static func _is_valid_component(value: StringName) -> bool:
	var text := String(value).strip_edges()
	if text.is_empty():
		return false
	for character in [" ", "\t", "\r", "\n", "/", "\\", ":"]:
		if text.contains(character):
			return false
	return true


static func _is_string_like(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING_NAME or typeof(value) == TYPE_STRING


static func _coerce_component(value: Variant) -> StringName:
	if not _is_string_like(value):
		return &""
	return StringName(value)
