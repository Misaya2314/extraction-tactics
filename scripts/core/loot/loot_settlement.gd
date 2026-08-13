class_name LootSettlement
extends RefCounted

var successful: bool = false
var items: Array[InventoryItemInstance] = []
var total_value: int = 0


static func success_snapshot(extracted_items: Array) -> LootSettlement:
	var result := LootSettlement.new()
	result.successful = true
	var generated_id := 0
	var seen_instance_ids: Dictionary = {}
	for extracted_item in extracted_items:
		var instance: InventoryItemInstance = null
		if extracted_item is InventoryItemInstance:
			instance = extracted_item.copy()
		elif extracted_item is ItemDefinition and extracted_item.is_valid():
			instance = InventoryItemInstance.new(StringName("settlement_item_%d" % generated_id), extracted_item, 0)
		if instance == null or not instance.is_valid():
			continue
		if seen_instance_ids.has(instance.instance_id):
			continue
		seen_instance_ids[instance.instance_id] = true
		result.items.append(instance)
		result.total_value += instance.value
		generated_id += 1
	return result


static func failure_snapshot() -> LootSettlement:
	return LootSettlement.new()


static func from_inventory(operation_succeeded: bool, inventory: SquadInventory) -> LootSettlement:
	if not operation_succeeded or inventory == null:
		return failure_snapshot()
	return from_placements(true, inventory.placements)


static func from_placements(operation_succeeded: bool, final_placements: Array) -> LootSettlement:
	if not operation_succeeded:
		return failure_snapshot()
	var extracted: Array = []
	for placement in final_placements:
		if placement is InventoryItemPlacement and placement.instance != null:
			extracted.append(placement.instance)
		elif placement is InventoryItemInstance:
			extracted.append(placement)
	return success_snapshot(extracted)


static func from_items(operation_succeeded: bool, extracted_items: Array) -> LootSettlement:
	if not operation_succeeded:
		return failure_snapshot()
	return success_snapshot(extracted_items)


func is_successful() -> bool:
	return successful


func get_items() -> Array[InventoryItemInstance]:
	var result: Array[InventoryItemInstance] = []
	for item in items:
		result.append(item)
	return result


func get_total_value() -> int:
	return total_value
