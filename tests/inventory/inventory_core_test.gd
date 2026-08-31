extends SceneTree

const ItemDefinitionScript = preload("res://scripts/core/items/item_definition.gd")
const ItemInstanceFactoryScript = preload("res://scripts/core/items/item_instance_factory.gd")
const InventoryItemInstanceScript = preload("res://scripts/core/inventory/inventory_item_instance.gd")
const SquadInventoryScript = preload("res://scripts/core/inventory/squad_inventory.gd")
const InstanceIdGeneratorScript = preload("res://scripts/core/runtime/instance_id_generator.gd")
const GameContentManifestScript = preload("res://scripts/core/content/game_content_manifest.gd")
const GameDefinitionRegistryScript = preload("res://scripts/core/content/game_definition_registry.gd")
const RuntimeInstanceRegistryScript = preload("res://scripts/core/runtime/runtime_instance_registry.gd")
const InventorySnapshotScript = preload("res://scripts/core/runtime/snapshots/inventory_snapshot.gd")
const ScrapMetal = preload("res://resources/items/scrap_metal.tres")
const Medkit = preload("res://resources/items/medkit.tres")
const RareWatch = preload("res://resources/items/rare_watch.tres")
const SecureChip = preload("res://resources/items/secure_chip.tres")

var _failures: Array[String] = []


func _init() -> void:
	_test_boundaries_and_rotation()
	_test_overlap_and_l_shape()
	_test_fragmented_space()
	_test_failed_move_and_rotate_rollback()
	_test_first_fit_and_legacy_instances()
	_test_factory_snapshot_and_rotation_ownership()
	_test_factory_runtime_registry_guard()
	_test_remove_and_value()
	_finish()


func _test_boundaries_and_rotation() -> void:
	var inventory = SquadInventoryScript.new(4, 4)
	var medkit := _instance(&"medkit_1", Medkit)
	_expect(inventory.can_place(medkit, Vector2i(0, 2)), "inventory: 1x2 item should fit at boundary")
	_expect(inventory.place(medkit, Vector2i(0, 2)), "inventory: 1x2 item should place")
	_expect(not inventory.can_place(medkit, Vector2i(0, 3)), "inventory: 1x2 item should reject bottom overflow")
	_expect(inventory.rotate(medkit, 90), "inventory: item should rotate in place")
	_expect(inventory.get_occupied_cells(medkit) == [Vector2i(0, 2), Vector2i(1, 2)], "inventory: 90-degree rotation should update occupied cells")
	_expect(inventory.get_cell_occupant(Vector2i(1, 2)) == medkit, "inventory: cell should reference its instance")


func _test_overlap_and_l_shape() -> void:
	var inventory = SquadInventoryScript.new(4, 4)
	var watch := _instance(&"watch_1", RareWatch)
	var chip := _instance(&"chip_1", SecureChip)
	_expect(inventory.find_first_fit(watch) == Vector2i.ZERO, "inventory: first-fit should scan from top-left")
	_expect(inventory.place(watch, Vector2i(1, 1)), "inventory: 2x2 item should place")
	_expect(not inventory.can_place(chip, Vector2i(1, 1)), "inventory: overlapping L shape should reject")
	_expect(inventory.can_place(chip, Vector2i(0, 2)), "inventory: L shape should fit in an open corner")
	_expect(inventory.place(chip, Vector2i(0, 2)), "inventory: L shape should place")
	_expect(inventory.get_occupied_cells(chip).size() == 3, "inventory: L shape should occupy three cells")


func _test_fragmented_space() -> void:
	var inventory = SquadInventoryScript.new(3, 2)
	var first := _instance(&"first", ScrapMetal)
	var second := _instance(&"second", ScrapMetal)
	var third := _instance(&"third", ScrapMetal)
	_expect(inventory.place(first, Vector2i(0, 1)), "inventory: fragment setup first")
	_expect(inventory.place(second, Vector2i(1, 0)), "inventory: fragment setup second")
	_expect(inventory.place(third, Vector2i(2, 1)), "inventory: fragment setup third")
	_expect(inventory.free == 3, "inventory: fragmented setup should leave three free cells")
	var medkit := _instance(&"fragment_medkit", Medkit)
	_expect(inventory.find_first_fit(medkit) == SquadInventoryScript.NO_FIT, "inventory: enough free cells without a continuous 1x2 fit should fail")
	_expect(not inventory.can_place(medkit, Vector2i(0, 0)), "inventory: fragmented target should reject overlap")


func _test_failed_move_and_rotate_rollback() -> void:
	var inventory = SquadInventoryScript.new(4, 4)
	var watch := _instance(&"rollback_watch", RareWatch)
	var medkit := _instance(&"rollback_medkit", Medkit)
	var blocker := _instance(&"rollback_blocker", ScrapMetal)
	_expect(inventory.place(watch, Vector2i(0, 0)), "inventory: rollback watch setup")
	_expect(inventory.place(medkit, Vector2i(0, 2)), "inventory: rollback medkit setup")
	_expect(inventory.place(blocker, Vector2i(1, 2)), "inventory: rollback blocker setup")
	var old_anchor: Vector2i = inventory.get_placement(watch).anchor
	var old_rotation: int = inventory.get_placement(medkit).rotation
	_expect(not inventory.move(watch, Vector2i(3, 3)), "inventory: colliding move should fail")
	_expect(inventory.get_placement(watch).anchor == old_anchor, "inventory: failed move keeps old anchor")
	_expect(not inventory.rotate(medkit, 90), "inventory: impossible rotation should fail")
	_expect(inventory.get_placement(medkit).rotation == old_rotation, "inventory: failed rotation keeps old rotation")


func _test_first_fit_and_legacy_instances() -> void:
	var factory = _make_factory(&"inventory_legacy")
	var inventory = SquadInventoryScript.new(4, 4, &"legacy_inventory", factory)
	_expect(inventory.add(ScrapMetal), "inventory: legacy definition add should create instance")
	_expect(inventory.add(ScrapMetal), "inventory: legacy add should use first fit")
	_expect(inventory.get_items().size() == 2, "inventory: two same-definition API entries should be instances")
	var items := inventory.get_items()
	_expect(items[0].instance_id != items[1].instance_id, "inventory: instances should have unique IDs")
	_expect(inventory.placements.size() == 2, "inventory: placements should track each instance")
	_expect(items[0].instance_id == &"inventory_legacy:item:0000", "inventory: factory should own the first generated ID")
	_expect(items[1].instance_id == &"inventory_legacy:item:0001", "inventory: factory should own the second generated ID")
	var duplicate = InventoryItemInstanceScript.new(items[0].instance_id, ScrapMetal)
	_expect(not inventory.can_place(duplicate, Vector2i(3, 3)), "inventory: a different object with an existing ID must be rejected")


func _test_factory_snapshot_and_rotation_ownership() -> void:
	var registry = _make_registry()
	var factory = _make_factory(&"inventory_snapshot", registry)
	var inventory = SquadInventoryScript.new(4, 4, &"snapshot_inventory", factory)
	var item = factory.create(Medkit)
	var definition_shape := Medkit.get_shape_cells()
	_expect(item != null and item.is_valid(registry), "inventory: factory-created item should resolve through registry")
	_expect(inventory.place(item, Vector2i(1, 1), 90), "inventory: rotated placement should succeed")
	var placement = inventory.get_placement(item)
	_expect(placement != null and placement.rotation == 90, "inventory: placement owns the requested rotation")
	_expect(item.rotation == 0, "inventory: placing an item must not synchronize legacy instance rotation")
	_expect(Medkit.get_shape_cells() == definition_shape, "inventory: placement operations must not mutate the shared definition")
	var snapshot_data := inventory.to_snapshot()
	_expect(not snapshot_data[&"items"][0].has(&"rotation"), "inventory: item snapshot must not contain placement rotation")
	_expect(snapshot_data[&"placements"][0][&"rotation"] == 90, "inventory: placement snapshot must contain rotation")
	var parsed_snapshot = InventorySnapshotScript.from_dictionary(snapshot_data)
	_expect(parsed_snapshot != null and parsed_snapshot.is_valid(), "inventory: strict snapshot should round-trip")
	var restore_factory = _make_factory(&"inventory_snapshot", registry)
	var restored = SquadInventoryScript.from_snapshot(snapshot_data, registry, restore_factory)
	_expect(restored != null and restored.get_items().size() == 1, "inventory: snapshot should hydrate one item")
	if restored != null and not restored.get_items().is_empty():
		var restored_item = restored.get_items()[0]
		_expect(restored_item.instance_id == item.instance_id, "inventory: hydration preserves instance identity")
		_expect(restored_item.definition == Medkit, "inventory: hydration resolves the declared definition")
		_expect(restored.get_placement(restored_item).rotation == 90, "inventory: hydration preserves placement rotation")
		_expect(restored.total_value() == inventory.total_value(), "inventory: hydration preserves definition-derived value")
	var next_id: StringName = restore_factory.id_generator.next_id(&"item")
	_expect(next_id != item.instance_id, "inventory: hydrated identity must be reserved before next creation")
	var wrong_type := snapshot_data.duplicate(true)
	wrong_type[&"items"][0][&"definition_id"] = "medkit"
	_expect(InventorySnapshotScript.from_dictionary(wrong_type) == null, "inventory: snapshot must reject String where StringName is required")
	var missing_definition := snapshot_data.duplicate(true)
	missing_definition[&"items"][0][&"definition_id"] = &"missing_item"
	var missing_snapshot = InventorySnapshotScript.from_dictionary(missing_definition)
	_expect(missing_snapshot != null, "inventory: missing definition remains a structurally valid snapshot")
	_expect(SquadInventoryScript.from_snapshot(missing_definition, registry, _make_factory(&"inventory_missing", registry)) == null, "inventory: missing definition hydration must fail")


func _test_factory_runtime_registry_guard() -> void:
	var definition_registry = _make_registry()
	var runtime_registry = RuntimeInstanceRegistryScript.new()
	var first_generator = InstanceIdGeneratorScript.new(&"inventory_runtime_guard")
	var first_factory = ItemInstanceFactoryScript.new(first_generator, definition_registry, runtime_registry)
	var first = first_factory.create(ScrapMetal)
	_expect(first != null and runtime_registry.get_instance(first.instance_id) == first, "inventory: factory should register created instances")
	var source_inventory = SquadInventoryScript.new(2, 2, &"runtime_source", first_factory)
	_expect(source_inventory.place(first, Vector2i.ZERO), "inventory: registered instance should be placeable in its first container")

	var duplicate_generator = InstanceIdGeneratorScript.new(&"inventory_runtime_guard")
	var duplicate_factory = ItemInstanceFactoryScript.new(duplicate_generator, definition_registry, runtime_registry)
	var before_create = duplicate_generator.capture_state()
	var duplicate_create = duplicate_factory.create(ScrapMetal)
	_expect(duplicate_create == null and duplicate_factory.last_reason_code == &"duplicate_instance_id", "inventory: shared runtime registry should reject a different created object with a duplicate ID")
	_expect(duplicate_generator.capture_state() == before_create, "inventory: rejected create should restore generator state")
	_expect(runtime_registry.get_instance(first.instance_id) == first, "inventory: rejected create must not replace the registered instance")

	var snapshot_data := source_inventory.to_snapshot()
	var hydrate_generator = InstanceIdGeneratorScript.new(&"inventory_hydrate_guard")
	var hydrate_factory = ItemInstanceFactoryScript.new(hydrate_generator, definition_registry, runtime_registry)
	var before_hydrate = hydrate_generator.capture_state()
	var duplicate_inventory = SquadInventoryScript.from_snapshot(snapshot_data, definition_registry, hydrate_factory)
	_expect(duplicate_inventory == null, "inventory: restoring the same snapshot into another container should be rejected")
	_expect(hydrate_generator.capture_state() == before_hydrate, "inventory: rejected hydrate should restore generator state")
	_expect(source_inventory.get_item(0) == first and runtime_registry.size() == 1, "inventory: rejected hydrate must leave original ownership and registry intact")


func _make_registry():
	var manifest = GameContentManifestScript.new()
	manifest.item_definitions.append(ScrapMetal)
	manifest.item_definitions.append(Medkit)
	manifest.item_definitions.append(RareWatch)
	manifest.item_definitions.append(SecureChip)
	var registry = GameDefinitionRegistryScript.new()
	var validation: Dictionary = registry.configure(manifest)
	_expect(bool(validation.get(&"valid", false)), "inventory: synthetic item manifest should be valid")
	return registry


func _make_factory(session_id: StringName, registry = null):
	return ItemInstanceFactoryScript.new(InstanceIdGeneratorScript.new(session_id), registry)


func _test_remove_and_value() -> void:
	var inventory = SquadInventoryScript.new(6, 8)
	var first := _instance(&"value_1", ScrapMetal)
	var second := _instance(&"value_2", ScrapMetal)
	var watch := _instance(&"value_watch", RareWatch)
	_expect(inventory.place(first, Vector2i(0, 0)), "inventory: value first")
	_expect(inventory.place(second, Vector2i(1, 0)), "inventory: value second")
	_expect(inventory.place(watch, Vector2i(2, 0)), "inventory: value watch")
	_expect(inventory.total_value() == 290, "inventory: total value counts each instance once")
	var used_before: int = inventory.used
	_expect(not inventory.remove(&"scrap_metal", 3), "inventory: removing too many instances should fail")
	_expect(inventory.used == used_before and inventory.get_item_count(&"scrap_metal") == 2, "inventory: failed remove is atomic")
	_expect(inventory.remove(first), "inventory: removing one instance should succeed")
	_expect(inventory.get_item_count(&"scrap_metal") == 1, "inventory: instance removal should preserve other same-type item")


func _instance(instance_id: StringName, definition: ItemDefinition) -> InventoryItemInstance:
	return InventoryItemInstanceScript.new(instance_id, definition, 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("INVENTORY_CORE_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("INVENTORY_CORE_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
