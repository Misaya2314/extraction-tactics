class_name LootContainerModel
extends RefCounted

const NO_FIT: Vector2i = Vector2i(-1, -1)

var container_id: StringName = &""
var opened: bool = false
var depleted: bool = true

var _items: Array[InventoryItemInstance] = []


func initialize(
		new_container_id: StringName,
		table: LootTableDefinition,
		random_seed: int = -1,
		rng: RandomNumberGenerator = null
) -> bool:
	if new_container_id == &"" or table == null or not table.is_valid():
		return false

	var generated: Array[ItemDefinition] = table.generate_contents(random_seed, rng)
	var copied: Array[InventoryItemInstance] = []
	var item_index := 0
	for definition in generated:
		if definition == null or not definition.is_valid():
			return false
		var instance_id := StringName("%s_item_%d" % [new_container_id, item_index])
		copied.append(InventoryItemInstance.new(instance_id, definition, 0))
		item_index += 1

	container_id = new_container_id
	_items = copied
	opened = false
	depleted = _items.is_empty()
	return true


func initialize_from_table(
		new_container_id: StringName,
		table: LootTableDefinition,
		random_seed: int = -1,
		rng: RandomNumberGenerator = null
) -> bool:
	return initialize(new_container_id, table, random_seed, rng)


func open() -> bool:
	if container_id == &"" or depleted:
		return false
	opened = true
	return true


func is_opened() -> bool:
	return opened


func is_depleted() -> bool:
	return depleted


func get_item_count() -> int:
	return _items.size()


func get_item(index: int) -> InventoryItemInstance:
	if index < 0 or index >= _items.size():
		return null
	return _items[index]


func get_instances() -> Array[InventoryItemInstance]:
	var result: Array[InventoryItemInstance] = []
	for item in _items:
		result.append(item)
	return result


func get_contents_instances() -> Array[InventoryItemInstance]:
	return get_instances()


func get_items() -> Array[InventoryItemInstance]:
	return get_instances()


func get_contents() -> Array[ItemDefinition]:
	return get_item_definitions()


func view_contents() -> Array[ItemDefinition]:
	if not depleted:
		opened = true
	return get_contents()


func transfer_to_inventory_at(index: int, inventory: SquadInventory, anchor: Vector2i, requested_rotation: int = -1) -> bool:
	if inventory == null or depleted or index < 0 or index >= _items.size():
		return false
	var item := _items[index]
	if item == null or not inventory.can_place(item, anchor, requested_rotation):
		return false
	if not inventory.place(item, anchor, requested_rotation):
		return false
	_items.remove_at(index)
	opened = true
	depleted = _items.is_empty()
	return true


func transfer_to_inventory(index: int, inventory: SquadInventory) -> bool:
	if inventory == null or depleted or index < 0 or index >= _items.size():
		return false
	var item := _items[index]
	var anchor := inventory.find_first_fit(item)
	if anchor == NO_FIT:
		return false
	return transfer_to_inventory_at(index, inventory, anchor)


func transfer_all_to_inventory(inventory: SquadInventory) -> bool:
	if inventory == null or depleted or _items.is_empty():
		return false
	if not inventory.can_add_items(_items):
		return false
	if not inventory.add_items(_items):
		return false
	_items.clear()
	opened = true
	depleted = true
	return true


func transfer_from_inventory(item_or_id: Variant, inventory: SquadInventory) -> bool:
	if inventory == null:
		return false
	var placement := inventory.get_placement(item_or_id)
	if placement == null or placement.instance == null:
		return false
	var item := placement.instance
	_items.append(item)
	if not inventory.remove(item):
		_items.pop_back()
		return false
	opened = true
	depleted = false
	return true


func get_item_definitions() -> Array[ItemDefinition]:
	var result: Array[ItemDefinition] = []
	for item in _items:
		if item != null:
			result.append(item.definition)
	return result
