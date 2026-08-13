extends SceneTree

const ItemDefinitionScript = preload("res://scripts/core/items/item_definition.gd")
const SquadInventoryScript = preload("res://scripts/core/inventory/squad_inventory.gd")
const LootTableScript = preload("res://scripts/core/loot/loot_table_definition.gd")
const LootContainerScript = preload("res://scripts/core/loot/loot_container_model.gd")
const LootSettlementScript = preload("res://scripts/core/loot/loot_settlement.gd")
const ScrapMetal = preload("res://resources/items/scrap_metal.tres")
const Medkit = preload("res://resources/items/medkit.tres")
const RareWatch = preload("res://resources/items/rare_watch.tres")
const SecureChip = preload("res://resources/items/secure_chip.tres")
const SupplyTable = preload("res://resources/loot/loot_table_supply.tres")
const WarehouseTable = preload("res://resources/loot/loot_table_warehouse.tres")
const HighValueTable = preload("res://resources/loot/loot_table_high_value.tres")
const OutpostTable = preload("res://resources/loot/loot_table_outpost.tres")

var _failures: Array[String] = []


func _init() -> void:
	_test_fixed_and_random_tables()
	_test_demo_tables()
	_test_specified_transfer_and_failure_atomicity()
	_test_inventory_to_container()
	_test_batch_transfer_and_settlement()
	_finish()


func _test_fixed_and_random_tables() -> void:
	var fixed = LootTableScript.new()
	fixed.table_id = &"fixed_test"
	fixed.fixed_items.append(ScrapMetal)
	fixed.fixed_items.append(Medkit)
	_expect(fixed.is_valid(), "loot: fixed table should be valid")
	var fixed_contents: Array[ItemDefinition] = fixed.generate_contents(99)
	_expect(_definition_ids(fixed_contents) == [&"scrap_metal", &"medkit"], "loot: fixed contents preserve order")

	var random = LootTableScript.new()
	random.table_id = &"random_test"
	random.random_pool.append(ScrapMetal)
	random.random_pool.append(Medkit)
	random.random_pool.append(RareWatch)
	random.random_pool.append(SecureChip)
	random.random_draw_count = 3
	random.allow_duplicates = false
	_expect(random.is_valid(), "loot: random table should be valid")
	var first: Array[ItemDefinition] = random.generate_contents(123456)
	var second: Array[ItemDefinition] = random.generate_contents(123456)
	_expect(_definition_ids(first) == _definition_ids(second), "loot: equal seeds should produce equal results")
	_expect(first.size() == 3 and _unique_definition_ids(first).size() == 3, "loot: no-duplicate pool draws")


func _test_demo_tables() -> void:
	var tables := [SupplyTable, WarehouseTable, HighValueTable, OutpostTable]
	for index in range(tables.size()):
		var table = tables[index]
		_expect(table != null and table.is_valid(), "loot: demo table %d should be valid" % index)
		_expect(not table.generate_contents(7).is_empty(), "loot: demo table %d should generate contents" % index)
	_expect(HighValueTable.fixed_items[0].item_id == &"rare_watch", "loot: high-value table should include a valuable item")
	_expect(HighValueTable.random_pool.has(SecureChip), "loot: high-value table should include the chip pool")


func _test_specified_transfer_and_failure_atomicity() -> void:
	var fixed = LootTableScript.new()
	fixed.table_id = &"container_test"
	fixed.fixed_items.append(Medkit)
	var container = LootContainerScript.new()
	_expect(container.initialize(&"crate_1", fixed, 11), "loot: container should initialize from table")
	_expect(container.get_item_count() == 1 and not container.opened and not container.depleted, "loot: initial container state")
	var inventory = SquadInventoryScript.new(4, 4)
	var before := container.get_item(0)
	_expect(not container.transfer_to_inventory_at(0, inventory, Vector2i(3, 3)), "loot: overflowing specified position should fail")
	_expect(container.get_item(0) == before and inventory.get_items().is_empty(), "loot: failed specified transfer is atomic")
	_expect(container.transfer_to_inventory_at(0, inventory, Vector2i(2, 1)), "loot: valid specified position should transfer")
	_expect(container.depleted and inventory.get_occupied_cells(before) == [Vector2i(2, 1), Vector2i(2, 2)], "loot: specified transfer preserves placement")
	_expect(container.get_contents().is_empty() and container.get_instances().is_empty(), "loot: compatibility contents are empty after transfer")
	_expect(not container.transfer_to_inventory_at(0, inventory, Vector2i.ZERO), "loot: depleted container cannot transfer")


func _test_inventory_to_container() -> void:
	var inventory = SquadInventoryScript.new(4, 4)
	var item := InventoryItemInstance.new(&"drop_chip", SecureChip, 90)
	_expect(inventory.place(item, Vector2i(1, 1)), "loot: setup item for drop")
	var container = LootContainerScript.new()
	container.container_id = &"drop_crate"
	container.depleted = false
	_expect(container.transfer_from_inventory(item, inventory), "loot: item should transfer back to container")
	_expect(inventory.get_items().is_empty() and container.get_item_count() == 1, "loot: back-transfer updates both sides")
	_expect(container.get_item(0).instance_id == &"drop_chip", "loot: back-transfer preserves instance identity")
	var before_count := container.get_item_count()
	_expect(not container.transfer_from_inventory(&"missing", inventory), "loot: missing back-transfer should fail")
	_expect(container.get_item_count() == before_count and inventory.get_items().is_empty(), "loot: failed back-transfer is atomic")


func _test_batch_transfer_and_settlement() -> void:
	var batch_table = LootTableScript.new()
	batch_table.table_id = &"batch_test"
	batch_table.fixed_items.append(RareWatch)
	batch_table.fixed_items.append(SecureChip)
	var container = LootContainerScript.new()
	_expect(container.initialize(&"crate_2", batch_table), "loot: batch container should initialize")
	var too_small = SquadInventoryScript.new(3, 2)
	_expect(not container.transfer_all_to_inventory(too_small), "loot: insufficient batch capacity should fail")
	_expect(container.get_item_count() == 2 and too_small.get_items().is_empty(), "loot: failed batch transfer is atomic")
	var inventory = SquadInventoryScript.new(6, 2)
	_expect(container.transfer_all_to_inventory(inventory), "loot: exact batch layout should succeed")
	_expect(container.depleted and inventory.get_items().size() == 2, "loot: successful batch empties container")

	var success = LootSettlementScript.from_inventory(true, inventory)
	_expect(success.successful and success.items.size() == 2 and success.total_value == 750, "loot: success settlement copies instances and value")
	var success_items = success.get_items()
	success_items.clear()
	_expect(success.items.size() == 2, "loot: settlement item list is copied on read")
	_expect(success.items[0] != inventory.get_items()[0], "loot: settlement owns copied instances")
	var failure = LootSettlementScript.from_inventory(false, inventory)
	_expect(not failure.successful and failure.items.is_empty() and failure.total_value == 0, "loot: failed settlement is empty and zero-valued")


func _definition_ids(items: Array[ItemDefinition]) -> Array[StringName]:
	var result: Array[StringName] = []
	for item in items:
		result.append(item.item_id)
	return result


func _unique_definition_ids(items: Array[ItemDefinition]) -> Array[StringName]:
	var result: Array[StringName] = []
	for item in items:
		if not result.has(item.item_id):
			result.append(item.item_id)
	return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("LOOT_CORE_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("LOOT_CORE_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
