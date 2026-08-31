class_name InventorySnapshot
extends RefCounted

## Complete pure-data inventory snapshot. Item definitions are represented by
## ItemInstanceSnapshot keys; positions and rotations are separate DTOs.

const CURRENT_SCHEMA_VERSION: int = 1
const ItemInstanceSnapshotScript = preload("res://scripts/core/runtime/snapshots/item_instance_snapshot.gd")
const ItemPlacementSnapshotScript = preload("res://scripts/core/runtime/snapshots/item_placement_snapshot.gd")

var schema_version: int = CURRENT_SCHEMA_VERSION
var inventory_id: StringName = &""
var width: int = 0
var height: int = 0
var items: Array[ItemInstanceSnapshot] = []
var placements: Array[ItemPlacementSnapshot] = []


func is_valid() -> bool:
	if schema_version != CURRENT_SCHEMA_VERSION or inventory_id == &"" or width <= 0 or height <= 0:
		return false
	var item_ids: Dictionary = {}
	for item in items:
		if item == null or not item.is_valid() or item_ids.has(item.instance_id):
			return false
		item_ids[item.instance_id] = true
	var placement_ids: Dictionary = {}
	for placement in placements:
		if placement == null or not placement.is_valid() or placement.container_id != inventory_id:
			return false
		if placement_ids.has(placement.instance_id) or not item_ids.has(placement.instance_id):
			return false
		placement_ids[placement.instance_id] = true
	return placement_ids.size() == item_ids.size()


func validate() -> bool:
	return is_valid()


func to_dictionary() -> Dictionary:
	var item_data: Array[Dictionary] = []
	for item in items:
		item_data.append(item.to_dictionary())
	var placement_data: Array[Dictionary] = []
	for placement in placements:
		placement_data.append(placement.to_dictionary())
	return {
		&"schema_version": schema_version,
		&"inventory_id": inventory_id,
		&"width": width,
		&"height": height,
		&"items": item_data,
		&"placements": placement_data,
	}


func to_dict() -> Dictionary:
	return to_dictionary()


static func from_dictionary(value: Variant):
	if typeof(value) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = value
	var required: Array[StringName] = [&"schema_version", &"inventory_id", &"width", &"height", &"items", &"placements"]
	for key in required:
		if not data.has(key):
			return null
	var raw_schema = data[&"schema_version"]
	var raw_inventory = data[&"inventory_id"]
	var raw_width = data[&"width"]
	var raw_height = data[&"height"]
	var raw_items = data[&"items"]
	var raw_placements = data[&"placements"]
	if typeof(raw_schema) != TYPE_INT or raw_schema != CURRENT_SCHEMA_VERSION:
		return null
	if typeof(raw_inventory) != TYPE_STRING_NAME or typeof(raw_width) != TYPE_INT or typeof(raw_height) != TYPE_INT:
		return null
	if not raw_items is Array or not raw_placements is Array:
		return null
	var result := InventorySnapshot.new()
	result.schema_version = raw_schema
	result.inventory_id = raw_inventory
	result.width = raw_width
	result.height = raw_height
	for raw_item in raw_items:
		var item = ItemInstanceSnapshotScript.from_dictionary(raw_item)
		if item == null:
			return null
		result.items.append(item)
	for raw_placement in raw_placements:
		var placement = ItemPlacementSnapshotScript.from_dictionary(raw_placement)
		if placement == null:
			return null
		result.placements.append(placement)
	return result if result.is_valid() else null


static func from_dict(value: Variant):
	return from_dictionary(value)


func duplicate_snapshot() -> InventorySnapshot:
	var result := InventorySnapshot.new()
	result.schema_version = schema_version
	result.inventory_id = inventory_id
	result.width = width
	result.height = height
	for item in items:
		result.items.append(item.duplicate_snapshot())
	for placement in placements:
		result.placements.append(placement.duplicate_snapshot())
	return result
