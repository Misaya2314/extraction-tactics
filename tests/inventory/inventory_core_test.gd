extends SceneTree

const ItemDefinitionScript = preload("res://scripts/core/items/item_definition.gd")
const InventoryItemInstanceScript = preload("res://scripts/core/inventory/inventory_item_instance.gd")
const SquadInventoryScript = preload("res://scripts/core/inventory/squad_inventory.gd")
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
	var old_anchor := inventory.get_placement(watch).anchor
	var old_rotation := inventory.get_placement(medkit).rotation
	_expect(not inventory.move(watch, Vector2i(3, 3)), "inventory: colliding move should fail")
	_expect(inventory.get_placement(watch).anchor == old_anchor, "inventory: failed move keeps old anchor")
	_expect(not inventory.rotate(medkit, 90), "inventory: impossible rotation should fail")
	_expect(inventory.get_placement(medkit).rotation == old_rotation, "inventory: failed rotation keeps old rotation")


func _test_first_fit_and_legacy_instances() -> void:
	var inventory = SquadInventoryScript.new(4, 4)
	_expect(inventory.add(ScrapMetal), "inventory: legacy definition add should create instance")
	_expect(inventory.add(Medkit), "inventory: legacy add should use first fit")
	_expect(inventory.get_items().size() == 2, "inventory: two same-definition API entries should be instances")
	var items := inventory.get_items()
	_expect(items[0].instance_id != items[1].instance_id, "inventory: instances should have unique IDs")
	_expect(inventory.placements.size() == 2, "inventory: placements should track each instance")


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
