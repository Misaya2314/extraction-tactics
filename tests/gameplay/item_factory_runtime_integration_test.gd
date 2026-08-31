extends SceneTree

## Pure gameplay contract test for the shared item-instance wiring.  This test
## intentionally does not load a map or a scene: it validates the dependency
## graph and the two runtime containers with synthetic content only.

const ItemInstanceFactoryScript = preload("res://scripts/core/items/item_instance_factory.gd")
const InstanceIdGeneratorScript = preload("res://scripts/core/runtime/instance_id_generator.gd")
const RuntimeInstanceRegistryScript = preload("res://scripts/core/runtime/runtime_instance_registry.gd")
const GameContentManifestScript = preload("res://scripts/core/content/game_content_manifest.gd")
const GameDefinitionRegistryScript = preload("res://scripts/core/content/game_definition_registry.gd")
const SquadInventoryScript = preload("res://scripts/core/inventory/squad_inventory.gd")
const LootContainerScript = preload("res://scripts/core/loot/loot_container_model.gd")
const LootTableScript = preload("res://scripts/core/loot/loot_table_definition.gd")
const MapObjectPlacementScript = preload("res://scripts/core/map/map_object_placement.gd")
const GameStateManagerScript = preload("res://scripts/core/session/game_state_manager.gd")
const TurnManagerScript = preload("res://scripts/core/turn/turn_manager.gd")
const PrototypeControllerScript = preload("res://scripts/gameplay/prototype_controller.gd")
const PrototypeUnitScript = preload("res://scripts/gameplay/prototype_unit.gd")
const ScrapMetal = preload("res://resources/items/scrap_metal.tres")

var _failures: Array[String] = []


func _init() -> void:
	_test_controller_dependency_contract()
	_test_shared_factory_is_injected_into_containers()
	_test_controller_loot_owned_preflight_and_transfer()
	_finish()


func _test_controller_dependency_contract() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/gameplay/prototype_controller.gd")
	_expect(not source.is_empty(), "gameplay: controller source should be readable")
	_expect(source.contains("ItemInstanceFactoryScript = preload(\"res://scripts/core/items/item_instance_factory.gd\")"), "gameplay: controller should preload ItemInstanceFactory")
	_expect(source.contains("var item_instance_factory: ItemInstanceFactory"), "gameplay: controller should hold the shared ItemInstanceFactory")
	_expect(source.contains("item_instance_factory = ItemInstanceFactoryScript.new("), "gameplay: controller should construct ItemInstanceFactory")
	_expect(source.contains("definition_registry,\n\t\truntime_instance_registry"), "gameplay: factory construction should pass Definition and Runtime registries")
	_expect(source.contains("SquadInventoryScript.DEFAULT_WIDTH"), "gameplay: controller should explicitly construct the default grid dimensions")
	_expect(source.contains("\n\t\titem_instance_factory\n\t)"), "gameplay: SquadInventory should receive the shared factory")
	_expect(source.contains("LootContainerScript.new(item_instance_factory)"), "gameplay: each LootContainer should receive the shared factory")
	_expect(source.contains("_runtime_content_ready"), "gameplay: invalid content should be tracked before Loot indexing")
	_expect(source.contains("Game content manifest is invalid or unavailable"), "gameplay: invalid content should explicitly skip Loot")
	_expect(not source.contains("item.rotation"), "gameplay: controller should not use compatibility item.rotation for Loot or settlement UI")
	_expect(source.contains("squad_inventory.can_place(item, anchor, rotation, allow_owned)"), "gameplay: Loot placement preflight should pass ownership context explicitly")
	_expect(source.contains("squad_inventory.find_first_fit(item, -1, allow_owned)"), "gameplay: single-item Loot first-fit should pass ownership context explicitly")
	_expect(source.contains("squad_inventory.find_first_fit(item, rotation, allow_owned)"), "gameplay: drag/button first-fit should pass ownership context explicitly")
	_expect(source.contains("squad_inventory.can_add_items(contents, allow_owned)"), "gameplay: Loot All preflight should pass ownership context explicitly")
	_expect(source.contains("squad_inventory.can_move(instance_id, anchor, rotation)"), "gameplay: inventory-only movement should retain strict ownership path")


func _test_shared_factory_is_injected_into_containers() -> void:
	var manifest := GameContentManifestScript.new()
	manifest.item_definitions.append(ScrapMetal)
	var definition_registry := GameDefinitionRegistryScript.new()
	var validation: Dictionary = definition_registry.configure(manifest)
	_expect(bool(validation.get(&"valid", false)), "gameplay: synthetic item manifest should be valid")

	var runtime_registry := RuntimeInstanceRegistryScript.new()
	var id_generator := InstanceIdGeneratorScript.new(&"gameplay_item_factory")
	var factory := ItemInstanceFactoryScript.new(id_generator, definition_registry, runtime_registry)
	_expect(factory.get_runtime_registry() == runtime_registry, "gameplay: factory should retain the shared RuntimeInstanceRegistry")

	var inventory := SquadInventoryScript.new(6, 8, &"gameplay_inventory", factory)
	_expect(inventory.get_instance_factory() == factory, "gameplay: SquadInventory should retain the shared factory")

	var table := LootTableScript.new()
	table.table_id = &"gameplay_factory_table"
	table.fixed_items.append(ScrapMetal)
	var container := LootContainerScript.new(factory)
	_expect(container.get_instance_factory() == factory, "gameplay: LootContainer should retain the shared factory")
	_expect(container.initialize(&"gameplay_crate", table, 7, null, factory), "gameplay: LootContainer should create content through the injected factory")
	var item: InventoryItemInstance = container.get_item(0)
	_expect(item != null and runtime_registry.contains(item.instance_id), "gameplay: factory-created Loot item should be in the shared runtime registry")
	_expect(inventory.get_instance_factory() == container.get_instance_factory(), "gameplay: inventory and Loot should share one factory instance")


func _test_controller_loot_owned_preflight_and_transfer() -> void:
	var manifest := GameContentManifestScript.new()
	manifest.item_definitions.append(ScrapMetal)
	var definition_registry := GameDefinitionRegistryScript.new()
	var validation: Dictionary = definition_registry.configure(manifest)
	_expect(bool(validation.get(&"valid", false)), "gameplay: Loot preflight manifest should be valid")

	var runtime_registry := RuntimeInstanceRegistryScript.new()
	var id_generator := InstanceIdGeneratorScript.new(&"gameplay_loot_preflight")
	var factory := ItemInstanceFactoryScript.new(id_generator, definition_registry, runtime_registry)
	var table := LootTableScript.new()
	table.table_id = &"gameplay_loot_preflight_table"
	table.fixed_items.append(ScrapMetal)
	var container := LootContainerScript.new(factory)
	var container_id: StringName = &"gameplay_preflight_crate"
	_expect(container.initialize(container_id, table, 13, null, factory), "gameplay: synthetic preflight container should initialize")
	_expect(container.open(), "gameplay: synthetic preflight container should open")
	var item: InventoryItemInstance = container.get_item(0)
	var inventory := SquadInventoryScript.new(2, 1, &"gameplay_preflight_inventory", factory)
	var controller := PrototypeControllerScript.new()
	var session_manager := GameStateManagerScript.new()
	var turn_manager := TurnManagerScript.new()
	var actor := PrototypeUnitScript.new()
	actor.unit_id = &"gameplay_preflight_actor"
	actor.grid_cell = Vector3i.ZERO
	_expect(session_manager.start_exploration(), "gameplay: synthetic controller session should be active")
	controller.session_manager = session_manager
	controller.turn_manager = turn_manager
	controller.selected_unit = actor
	controller.squad_inventory = inventory
	controller.open_loot_container_id = container_id
	controller.loot_containers[container_id] = container
	controller.object_placements[container_id] = _loot_placement(container_id)
	controller._configure_action_executor()
	controller.input_locked = true
	controller.phase_label = Label.new()
	controller.alert_label = Label.new()
	controller.selection_label = Label.new()
	controller.end_turn_button = Button.new()
	controller.hint_label = Label.new()
	_expect(item != null and item.get_owner_id() == StringName("loot:" + String(container_id)), "gameplay: Loot item should remain owned by its container before preflight")
	_expect(inventory.find_first_fit(item) == SquadInventoryScript.NO_FIT, "gameplay: default inventory preflight must reject a Loot-owned item")
	var preview := controller.preview_inventory_command(
		container_id,
		0,
		item.instance_id if item != null else &"",
		Vector2i.ZERO,
		0,
		&"loot"
	)
	_expect(bool(preview.get(&"valid", false)), "gameplay: current Loot source should pass drag preflight while still container-owned")
	var ap_before_transfer := actor.current_action_points
	var transfer_result: ActionResult = controller.place_loot_instance(container_id, 0, Vector2i.ZERO, 0)
	_expect(transfer_result != null and transfer_result.success, "gameplay: public place_loot_instance should pass Validator and execute the transfer")
	_expect(actor.current_action_points == ap_before_transfer, "gameplay: free Loot transfer should not spend AP")
	_expect(item != null and item.get_owner_id() == StringName("inventory:" + String(inventory.inventory_id)), "gameplay: successful Loot transfer should move ownership to inventory")
	_expect(container.get_item_count() == 0 and inventory.get_placement(item) != null, "gameplay: successful Loot transfer should move the same instance exactly once")

	var all_container := LootContainerScript.new(factory)
	var all_container_id: StringName = &"gameplay_all_crate"
	_expect(all_container.initialize(all_container_id, table, 19, null, factory), "gameplay: Loot All container should initialize")
	_expect(all_container.open(), "gameplay: Loot All container should open")
	var all_item: InventoryItemInstance = all_container.get_item(0)
	controller.open_loot_container_id = all_container_id
	controller.loot_containers[all_container_id] = all_container
	controller.object_placements[all_container_id] = _loot_placement(all_container_id)
	var all_result: ActionResult = controller.loot_all()
	_expect(all_result != null and all_result.success, "gameplay: public loot_all should pass the ownership-aware capacity preflight")
	_expect(all_item != null and all_item.get_owner_id() == StringName("inventory:" + String(inventory.inventory_id)), "gameplay: Loot All should transfer ownership to inventory")

	var blocked_inventory := SquadInventoryScript.new(1, 1, &"gameplay_blocked_inventory", factory)
	var filler: InventoryItemInstance = factory.create(ScrapMetal)
	_expect(filler != null and blocked_inventory.place(filler, Vector2i.ZERO), "gameplay: blocked inventory should be filled with a separate item")
	var blocked_container := LootContainerScript.new(factory)
	var blocked_id: StringName = &"gameplay_blocked_crate"
	_expect(blocked_container.initialize(blocked_id, table, 17, null, factory), "gameplay: blocked Loot container should initialize")
	_expect(blocked_container.open(), "gameplay: blocked Loot container should open")
	var blocked_item: InventoryItemInstance = blocked_container.get_item(0)
	controller.squad_inventory = blocked_inventory
	controller.open_loot_container_id = blocked_id
	controller.loot_containers[blocked_id] = blocked_container
	controller.object_placements[blocked_id] = _loot_placement(blocked_id)
	var blocked_preview := controller.preview_inventory_command(
		blocked_id,
		0,
		blocked_item.instance_id if blocked_item != null else &"",
		Vector2i.ZERO,
		0,
		&"loot"
	)
	_expect(not bool(blocked_preview.get(&"valid", false)), "gameplay: a truly full inventory must reject the Loot preview")
	var blocked_ap_before := actor.current_action_points
	var blocked_result: ActionResult = controller.place_loot_instance(blocked_id, 0, Vector2i.ZERO, 0)
	_expect(blocked_result != null and not blocked_result.success and blocked_result.reason == &"inventory_full", "gameplay: a truly full inventory must reject the public Loot entry as inventory_full")
	_expect(actor.current_action_points == blocked_ap_before, "gameplay: rejected full transfer must not spend AP")
	_expect(blocked_item != null and blocked_item.get_owner_id() == StringName("loot:" + String(blocked_id)), "gameplay: rejected full transfer must preserve Loot ownership")
	_expect(blocked_container.get_item_count() == 1 and blocked_inventory.get_placement(blocked_item) == null, "gameplay: rejected full transfer must preserve both containers atomically")


func _loot_placement(object_id: StringName):
	var placement := MapObjectPlacementScript.new()
	placement.object_id = object_id
	placement.kind = MapObjectPlacementScript.Kind.LOOT
	placement.cell = Vector3i.ZERO
	return placement


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("ITEM_FACTORY_RUNTIME_INTEGRATION_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ITEM_FACTORY_RUNTIME_INTEGRATION_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
