@tool
class_name DefinitionAlias
extends Resource

## Explicit content-ID migration entry. Aliases are data, not directory scans.

const DefinitionKeyScript = preload("res://scripts/core/content/definition_key.gd")

@export var from_type: StringName = &""
@export var from_id: StringName = &""
@export var to_type: StringName = &""
@export var to_id: StringName = &""


func source_key():
	return DefinitionKeyScript.new(from_type, from_id)


func target_key():
	return DefinitionKeyScript.new(to_type, to_id)


func is_valid() -> bool:
	return source_key().is_valid() and target_key().is_valid()
