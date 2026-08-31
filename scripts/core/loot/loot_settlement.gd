class_name LootSettlement
extends RefCounted

const ItemInstanceSnapshotScript = preload("res://scripts/core/runtime/snapshots/item_instance_snapshot.gd")

## Settlement is a read-only result view over the instances that were already
## extracted. It deliberately keeps the same InventoryItemInstance references
## instead of creating a second live object with the same stable ID. Callers
## that need persistence should consume get_item_snapshots()/to_snapshot().

var successful: bool = false
var items: Array[InventoryItemInstance] = []
var total_value: int = 0
var last_reason_code: StringName = &""


static func success_snapshot(extracted_items: Array, instance_factory = null) -> LootSettlement:
	var result := LootSettlement.new()
	result.successful = true
	var seen_instance_ids: Dictionary = {}
	var created_instances: Array[InventoryItemInstance] = []
	for extracted_item in extracted_items:
		var instance: InventoryItemInstance = null
		if extracted_item is InventoryItemInstance:
			instance = extracted_item as InventoryItemInstance
		elif extracted_item is ItemDefinition:
			# Legacy callers may still pass definitions, but materializing one is
			# a creation operation and therefore requires the injected factory.
			if instance_factory == null or typeof(instance_factory) != TYPE_OBJECT or not instance_factory.has_method("create"):
				result.successful = false
				result.last_reason_code = &"missing_instance_factory"
				result.items.clear()
				result.total_value = 0
				return result
			instance = instance_factory.call("create", extracted_item)
			if instance is InventoryItemInstance:
				created_instances.append(instance)
		if not instance is InventoryItemInstance or not instance.is_valid():
			_discard_instances(instance_factory, created_instances)
			result.successful = false
			result.last_reason_code = &"invalid_instance"
			result.items.clear()
			result.total_value = 0
			return result
		if seen_instance_ids.has(instance.instance_id):
			if seen_instance_ids[instance.instance_id] != instance:
				_discard_instances(instance_factory, created_instances)
				result.successful = false
				result.last_reason_code = &"duplicate_instance_id"
				result.items.clear()
				result.total_value = 0
				return result
			continue
		seen_instance_ids[instance.instance_id] = instance
		result.items.append(instance)
		result.total_value += instance.value
	result.last_reason_code = &"ok"
	return result


static func failure_snapshot() -> LootSettlement:
	var result := LootSettlement.new()
	result.last_reason_code = &"operation_failed"
	return result


static func from_inventory(operation_succeeded: bool, inventory: SquadInventory) -> LootSettlement:
	if not operation_succeeded or inventory == null:
		return failure_snapshot()
	return success_snapshot(inventory.get_items())


static func from_placements(operation_succeeded: bool, final_placements: Array, instance_factory = null) -> LootSettlement:
	if not operation_succeeded:
		return failure_snapshot()
	var extracted: Array = []
	for placement in final_placements:
		if placement is InventoryItemPlacement and placement.instance != null:
			extracted.append(placement.instance)
		elif placement is InventoryItemInstance:
			extracted.append(placement)
	return success_snapshot(extracted, instance_factory)


static func from_items(operation_succeeded: bool, extracted_items: Array, instance_factory = null) -> LootSettlement:
	if not operation_succeeded:
		return failure_snapshot()
	return success_snapshot(extracted_items, instance_factory)


func is_successful() -> bool:
	return successful


func get_items() -> Array[InventoryItemInstance]:
	var result: Array[InventoryItemInstance] = []
	for item in items:
		result.append(item)
	return result


func get_item_snapshots() -> Array[ItemInstanceSnapshot]:
	var result: Array[ItemInstanceSnapshot] = []
	for item in items:
		if item != null:
			result.append(item.to_snapshot_resource())
	return result


func to_snapshot() -> Dictionary:
	var snapshot_items: Array[Dictionary] = []
	for item_snapshot in get_item_snapshots():
		snapshot_items.append(item_snapshot.to_dictionary())
	return {
		&"schema_version": 1,
		&"successful": successful,
		&"total_value": total_value,
		&"items": snapshot_items,
	}


func get_total_value() -> int:
	return total_value


static func _discard_instances(factory: Variant, instances: Array) -> void:
	if factory == null or typeof(factory) != TYPE_OBJECT or not factory.has_method("discard_instance"):
		return
	for instance in instances:
		factory.call("discard_instance", instance)
