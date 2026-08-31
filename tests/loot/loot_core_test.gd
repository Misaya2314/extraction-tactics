extends SceneTree

const ItemDefinitionScript = preload("res://scripts/core/items/item_definition.gd")
const ItemInstanceFactoryScript = preload("res://scripts/core/items/item_instance_factory.gd")
const SquadInventoryScript = preload("res://scripts/core/inventory/squad_inventory.gd")
const InventoryItemInstanceScript = preload("res://scripts/core/inventory/inventory_item_instance.gd")
const LootTableScript = preload("res://scripts/core/loot/loot_table_definition.gd")
const LootContainerScript = preload("res://scripts/core/loot/loot_container_model.gd")
const LootSettlementScript = preload("res://scripts/core/loot/loot_settlement.gd")
const LootContainerSnapshotScript = preload("res://scripts/core/runtime/snapshots/loot_container_snapshot.gd")
const InstanceIdGeneratorScript = preload("res://scripts/core/runtime/instance_id_generator.gd")
const RuntimeInstanceRegistryScript = preload("res://scripts/core/runtime/runtime_instance_registry.gd")
const GameContentManifestScript = preload("res://scripts/core/content/game_content_manifest.gd")
const GameDefinitionRegistryScript = preload("res://scripts/core/content/game_definition_registry.gd")
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
	_test_duplicate_ownership_rejection()
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
	var registry = _make_registry()
	var factory = _make_factory(&"loot_specified", registry)
	var container = LootContainerScript.new(factory)
	_expect(container.initialize(&"crate_1", fixed, 11), "loot: container should initialize from table")
	_expect(container.get_item_count() == 1 and not container.opened and not container.depleted, "loot: initial container state")
	var inventory = SquadInventoryScript.new(4, 4, &"loot_inventory", factory)
	var before: InventoryItemInstance = container.get_item(0)
	var before_id: StringName = before.instance_id
	_expect(container.open(), "loot: initialized container should open")
	var container_snapshot_data := container.to_snapshot()
	var parsed_container_snapshot = LootContainerSnapshotScript.from_dictionary(container_snapshot_data)
	_expect(parsed_container_snapshot != null and parsed_container_snapshot.is_valid(), "loot: container snapshot should round-trip structurally")
	var restored_container = LootContainerScript.from_snapshot(container_snapshot_data, registry, _make_factory(&"loot_restore", registry))
	_expect(restored_container != null and restored_container.opened and not restored_container.depleted, "loot: container snapshot should preserve open state")
	_expect(restored_container != null and restored_container.get_item(0).instance_id == before_id, "loot: container snapshot should preserve item identity")
	_expect(not container.transfer_to_inventory_at(0, inventory, Vector2i(3, 3)), "loot: overflowing specified position should fail")
	_expect(container.get_item(0) == before and inventory.get_items().is_empty(), "loot: failed specified transfer is atomic")
	_expect(container.transfer_to_inventory_at(0, inventory, Vector2i(2, 1)), "loot: valid specified position should transfer")
	_expect(container.depleted and inventory.get_occupied_cells(before) == [Vector2i(2, 1), Vector2i(2, 2)], "loot: specified transfer preserves placement")
	_expect(inventory.get_items()[0].instance_id == before_id, "loot: container transfer preserves the same instance identity")
	_expect(container.get_contents().is_empty() and container.get_instances().is_empty(), "loot: compatibility contents are empty after transfer")
	_expect(not container.transfer_to_inventory_at(0, inventory, Vector2i.ZERO), "loot: depleted container cannot transfer")
	var malformed_snapshot := container_snapshot_data.duplicate(true)
	malformed_snapshot[&"items"][0][&"instance_id"] = "wrong_type"
	_expect(LootContainerSnapshotScript.from_dictionary(malformed_snapshot) == null, "loot: snapshot must reject String where StringName is required")


func _test_inventory_to_container() -> void:
	var empty_inventory = SquadInventoryScript.new(4, 4, &"empty_container_source")
	var empty_item := InventoryItemInstance.new(&"empty_container_item", SecureChip, 90)
	_expect(empty_inventory.place(empty_item, Vector2i(1, 1)), "loot: setup item for empty-container rejection")
	var empty_container = LootContainerScript.new()
	var empty_before_placement = empty_inventory.get_placement(empty_item)
	_expect(not empty_container.transfer_from_inventory(empty_item, empty_inventory), "loot: empty container ID must reject back-transfer")
	_expect(empty_container.last_reason_code == &"container_uninitialized", "loot: empty container rejection should expose a stable reason")
	_expect(empty_container.get_item_count() == 0 and empty_inventory.get_placement(empty_item) == empty_before_placement and empty_item.get_owner_id() == &"inventory:empty_container_source", "loot: empty-container rejection must not mutate either side")

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

	var conflict_inventory = SquadInventoryScript.new(4, 4, &"conflict_source")
	var conflict_item := InventoryItemInstance.new(&"conflict_item", SecureChip, 90)
	_expect(conflict_inventory.place(conflict_item, Vector2i(0, 0)), "loot: setup ownership-conflict source")
	conflict_item.release_owner(&"inventory:conflict_source")
	conflict_item.claim_owner(&"loot:another_container")
	var conflict_placement = conflict_inventory.get_placement(conflict_item)
	var conflict_container_count := container.get_item_count()
	_expect(not container.transfer_from_inventory(conflict_item, conflict_inventory), "loot: corrupted source ownership should reject")
	_expect(container.last_reason_code == &"source_ownership_conflict", "loot: source ownership failure should expose a stable reason")
	_expect(container.get_item_count() == conflict_container_count and conflict_inventory.get_placement(conflict_item) == conflict_placement and conflict_item.get_owner_id() == &"loot:another_container", "loot: source ownership rejection must preserve both sides")


func _test_batch_transfer_and_settlement() -> void:
	var batch_table = LootTableScript.new()
	batch_table.table_id = &"batch_test"
	batch_table.fixed_items.append(RareWatch)
	batch_table.fixed_items.append(SecureChip)
	var factory = _make_factory(&"loot_batch")
	var container = LootContainerScript.new(factory)
	_expect(container.initialize(&"crate_2", batch_table), "loot: batch container should initialize")
	var too_small = SquadInventoryScript.new(3, 2)
	_expect(not container.transfer_all_to_inventory(too_small), "loot: insufficient batch capacity should fail")
	_expect(container.get_item_count() == 2 and too_small.get_items().is_empty(), "loot: failed batch transfer is atomic")
	var inventory = SquadInventoryScript.new(6, 2)
	_expect(container.transfer_all_to_inventory(inventory), "loot: exact batch layout should succeed")
	_expect(container.depleted and inventory.get_items().size() == 2, "loot: successful batch empties container")

	var success = LootSettlementScript.from_inventory(true, inventory)
	_expect(success.successful and success.items.size() == 2 and success.total_value == 750, "loot: success settlement preserves instances and value")
	var success_items = success.get_items()
	success_items.clear()
	_expect(success.items.size() == 2, "loot: settlement item list is copied on read")
	_expect(success.items[0] == inventory.get_items()[0], "loot: settlement keeps the original instance identity")
	_expect(success.get_item_snapshots().size() == 2, "loot: settlement exposes pure item snapshots")
	_expect(success.to_snapshot()[&"total_value"] == 750, "loot: settlement snapshot preserves total value")
	var failure = LootSettlementScript.from_inventory(false, inventory)
	_expect(not failure.successful and failure.items.is_empty() and failure.total_value == 0, "loot: failed settlement is empty and zero-valued")
	var definition_without_factory = LootSettlementScript.success_snapshot([ScrapMetal])
	_expect(not definition_without_factory.successful and definition_without_factory.last_reason_code == &"missing_instance_factory", "loot: definition settlement requires an explicit factory")


func _test_duplicate_ownership_rejection() -> void:
	var table = LootTableScript.new()
	table.table_id = &"duplicate_ownership"
	table.fixed_items.append(ScrapMetal)
	var definition_registry = _make_registry()
	var runtime_registry = RuntimeInstanceRegistryScript.new()
	var factory = ItemInstanceFactoryScript.new(InstanceIdGeneratorScript.new(&"loot_duplicate"), definition_registry, runtime_registry)
	var container = LootContainerScript.new(factory)
	_expect(container.initialize(&"duplicate_crate", table), "loot: duplicate ownership container setup")
	var inventory = SquadInventoryScript.new(2, 2)
	var item = container.get_item(0)
	_expect(item.get_owner_id() == &"loot:duplicate_crate", "loot: container claims each created instance")
	_expect(runtime_registry.get_instance(item.instance_id) == item, "loot: container factory should register the live instance")
	_expect(not inventory.place(item, Vector2i.ZERO), "loot: direct placement of an owned item must be rejected")
	_expect(container.get_item(0) == item and inventory.get_items().is_empty(), "loot: rejected direct placement leaves both sides unchanged")
	var snapshot_data := container.to_snapshot()
	var restore_generator = InstanceIdGeneratorScript.new(&"loot_duplicate_restore")
	var restore_factory = ItemInstanceFactoryScript.new(restore_generator, definition_registry, runtime_registry)
	var generator_before_restore = restore_generator.capture_state()
	var duplicate_container = LootContainerScript.from_snapshot(snapshot_data, definition_registry, restore_factory)
	_expect(duplicate_container == null, "loot: shared runtime registry should reject duplicate hydrate across containers")
	_expect(restore_generator.capture_state() == generator_before_restore, "loot: rejected duplicate hydrate should restore generator state")
	_expect(runtime_registry.size() == 1 and container.get_item(0) == item, "loot: rejected duplicate hydrate must preserve the original live instance")

	var duplicate := InventoryItemInstance.new(item.instance_id, ScrapMetal)
	var second_inventory = SquadInventoryScript.new(2, 2)
	_expect(second_inventory.place(duplicate, Vector2i.ZERO), "loot: distinct duplicate-ID setup should remain possible for rejection testing")
	var before_count := container.get_item_count()
	_expect(not container.transfer_from_inventory(duplicate, second_inventory), "loot: transfer must reject an ID already owned by container")
	_expect(container.get_item_count() == before_count and container.get_item(0) == item and second_inventory.get_item(0) == duplicate, "loot: duplicate ID rejection leaves both sides unchanged")


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


func _make_registry():
	var manifest = GameContentManifestScript.new()
	manifest.item_definitions.append(ScrapMetal)
	manifest.item_definitions.append(Medkit)
	manifest.item_definitions.append(RareWatch)
	manifest.item_definitions.append(SecureChip)
	var registry = GameDefinitionRegistryScript.new()
	var validation: Dictionary = registry.configure(manifest)
	_expect(bool(validation.get(&"valid", false)), "loot: synthetic item manifest should be valid")
	return registry


func _make_factory(session_id: StringName, registry = null, runtime_registry = null):
	return ItemInstanceFactoryScript.new(InstanceIdGeneratorScript.new(session_id), registry, runtime_registry)


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
