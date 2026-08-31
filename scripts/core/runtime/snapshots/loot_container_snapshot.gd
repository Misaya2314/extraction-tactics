class_name LootContainerSnapshot
extends RefCounted

## Pure-data Loot container state. Contained item snapshots preserve the same
## instance IDs while never embedding ItemDefinition resources.

const CURRENT_SCHEMA_VERSION: int = 1
const ItemInstanceSnapshotScript = preload("res://scripts/core/runtime/snapshots/item_instance_snapshot.gd")

var schema_version: int = CURRENT_SCHEMA_VERSION
var container_id: StringName = &""
var opened: bool = false
var depleted: bool = true
var items: Array[ItemInstanceSnapshot] = []


func is_valid() -> bool:
	if schema_version != CURRENT_SCHEMA_VERSION or container_id == &"":
		return false
	var seen: Dictionary = {}
	for item in items:
		if item == null or not item.is_valid() or seen.has(item.instance_id):
			return false
		seen[item.instance_id] = true
	return depleted == items.is_empty()


func validate() -> bool:
	return is_valid()


func to_dictionary() -> Dictionary:
	var item_data: Array[Dictionary] = []
	for item in items:
		item_data.append(item.to_dictionary())
	return {
		&"schema_version": schema_version,
		&"container_id": container_id,
		&"opened": opened,
		&"depleted": depleted,
		&"items": item_data,
	}


func to_dict() -> Dictionary:
	return to_dictionary()


static func from_dictionary(value: Variant):
	if typeof(value) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = value
	var required: Array[StringName] = [&"schema_version", &"container_id", &"opened", &"depleted", &"items"]
	for key in required:
		if not data.has(key):
			return null
	var raw_schema = data[&"schema_version"]
	var raw_container = data[&"container_id"]
	var raw_opened = data[&"opened"]
	var raw_depleted = data[&"depleted"]
	var raw_items = data[&"items"]
	if typeof(raw_schema) != TYPE_INT or raw_schema != CURRENT_SCHEMA_VERSION:
		return null
	if typeof(raw_container) != TYPE_STRING_NAME or typeof(raw_opened) != TYPE_BOOL or typeof(raw_depleted) != TYPE_BOOL:
		return null
	if not raw_items is Array:
		return null
	var result := LootContainerSnapshot.new()
	result.schema_version = raw_schema
	result.container_id = raw_container
	result.opened = raw_opened
	result.depleted = raw_depleted
	for raw_item in raw_items:
		var item = ItemInstanceSnapshotScript.from_dictionary(raw_item)
		if item == null:
			return null
		result.items.append(item)
	return result if result.is_valid() else null


static func from_dict(value: Variant):
	return from_dictionary(value)


func duplicate_snapshot() -> LootContainerSnapshot:
	var result := LootContainerSnapshot.new()
	result.schema_version = schema_version
	result.container_id = container_id
	result.opened = opened
	result.depleted = depleted
	for item in items:
		result.items.append(item.duplicate_snapshot())
	return result
