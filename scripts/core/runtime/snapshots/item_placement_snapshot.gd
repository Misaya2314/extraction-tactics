class_name ItemPlacementSnapshot
extends RefCounted

## Serializable position DTO. The item snapshot owns identity/definition;
## this DTO alone owns the container placement and rotation.

const CURRENT_SCHEMA_VERSION: int = 1

var schema_version: int = CURRENT_SCHEMA_VERSION
var instance_id: StringName = &""
var container_id: StringName = &""
var anchor: Vector2i = Vector2i.ZERO
var rotation: int = 0


func _init(
		new_instance_id: Variant = &"",
		new_container_id: Variant = &"",
		new_anchor: Variant = Vector2i.ZERO,
		new_rotation: Variant = 0
	) -> void:
	if new_instance_id is StringName:
		instance_id = new_instance_id
	if new_container_id is StringName:
		container_id = new_container_id
	if new_anchor is Vector2i:
		anchor = new_anchor
	if typeof(new_rotation) == TYPE_INT:
		rotation = new_rotation


func is_valid() -> bool:
	return schema_version == CURRENT_SCHEMA_VERSION \
		and instance_id != &"" \
		and container_id != &"" \
		and typeof(anchor) == TYPE_VECTOR2I \
		and rotation in [0, 90, 180, 270]


func validate() -> bool:
	return is_valid()


func to_dictionary() -> Dictionary:
	return {
		&"schema_version": schema_version,
		&"instance_id": instance_id,
		&"container_id": container_id,
		&"anchor": anchor,
		&"rotation": rotation,
	}


func to_dict() -> Dictionary:
	return to_dictionary()


static func from_dictionary(value: Variant):
	if typeof(value) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = value
	var required: Array[StringName] = [&"schema_version", &"instance_id", &"container_id", &"anchor", &"rotation"]
	for key in required:
		if not data.has(key):
			return null
	var raw_schema = data[&"schema_version"]
	var raw_instance = data[&"instance_id"]
	var raw_container = data[&"container_id"]
	var raw_anchor = data[&"anchor"]
	var raw_rotation = data[&"rotation"]
	if typeof(raw_schema) != TYPE_INT or raw_schema != CURRENT_SCHEMA_VERSION:
		return null
	if typeof(raw_instance) != TYPE_STRING_NAME or typeof(raw_container) != TYPE_STRING_NAME:
		return null
	if typeof(raw_anchor) != TYPE_VECTOR2I or typeof(raw_rotation) != TYPE_INT:
		return null
	var result := ItemPlacementSnapshot.new()
	result.schema_version = raw_schema
	result.instance_id = raw_instance
	result.container_id = raw_container
	result.anchor = raw_anchor
	result.rotation = raw_rotation
	return result if result.is_valid() else null


static func from_dict(value: Variant):
	return from_dictionary(value)


func duplicate_snapshot() -> ItemPlacementSnapshot:
	var result := ItemPlacementSnapshot.new()
	result.schema_version = schema_version
	result.instance_id = instance_id
	result.container_id = container_id
	result.anchor = anchor
	result.rotation = rotation
	return result
