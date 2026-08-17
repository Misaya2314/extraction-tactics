extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main/prototype_main.tscn")
const InventoryItemInstanceScript = preload("res://scripts/core/inventory/inventory_item_instance.gd")
const LootSettlementScript = preload("res://scripts/core/loot/loot_settlement.gd")
const SquadInventoryScript = preload("res://scripts/core/inventory/squad_inventory.gd")
const ScrapMetal = preload("res://resources/items/scrap_metal.tres")
const Medkit = preload("res://resources/items/medkit.tres")
const RareWatch = preload("res://resources/items/rare_watch.tres")
const SecureChip = preload("res://resources/items/secure_chip.tres")

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_grid_mapping_and_shapes()
	await _test_precise_shape_hit_testing()
	await _test_loot_targeted_place_and_return()
	await _test_inventory_rearrange_rotate_and_rollback()
	await _test_fragmented_space_is_not_free_capacity()
	await _test_native_drag_and_key_input_path()
	await _test_drag_cleanup_and_live_rotation_preview()
	await _test_preview_rejects_closed_or_wrong_phase_loot()
	await _test_pending_loot_rotation_does_not_override_returned_instance()
	await _test_settlement_reads_final_instances_once()
	_finish()


func _test_grid_mapping_and_shapes() -> void:
	var prototype := await _spawn_prototype()
	var grid := prototype.inventory_grid
	_expect(is_instance_valid(grid), "grid: InventoryGridControl should exist")
	_expect(grid.get_dimensions() == Vector2i(6, 8), "grid: inventory should be 6x8")
	_expect(grid.get_cell_count() == 48, "grid: inventory should draw 48 cells")

	var scrap := _instance(&"ui_scrap", ScrapMetal)
	var medkit := _instance(&"ui_medkit", Medkit)
	var watch := _instance(&"ui_watch", RareWatch)
	var chip := _instance(&"ui_chip", SecureChip)
	_expect(prototype.squad_inventory.place(scrap, Vector2i(0, 0)), "grid: 1x1 placement")
	_expect(prototype.squad_inventory.place(medkit, Vector2i(1, 0)), "grid: 1x2 placement")
	_expect(prototype.squad_inventory.place(watch, Vector2i(2, 0)), "grid: 2x2 placement")
	_expect(prototype.squad_inventory.place(chip, Vector2i(4, 0)), "grid: L placement")
	prototype._refresh_inventory_ui()
	await process_frame
	_expect(grid.get_item_control_count() == 4, "grid: each placed instance should have one visual control")
	_expect(is_instance_valid(grid.get_item_control(&"ui_scrap")), "grid: 1x1 control mapping")
	_expect(is_instance_valid(grid.get_item_control(&"ui_medkit")), "grid: 1x2 control mapping")
	_expect(is_instance_valid(grid.get_item_control(&"ui_watch")), "grid: 2x2 control mapping")
	_expect(is_instance_valid(grid.get_item_control(&"ui_chip")), "grid: L control mapping")
	_expect(prototype.squad_inventory.get_cell_occupant(Vector2i(5, 1)).instance_id == &"ui_chip", "grid: L shape should occupy each mask cell")
	_expect(prototype.squad_inventory.get_cell_occupant(Vector2i(3, 1)).instance_id == &"ui_watch", "grid: 2x2 should occupy all four cells")
	await _free_prototype(prototype)


func _test_precise_shape_hit_testing() -> void:
	var prototype := await _spawn_prototype()
	var l_item := _instance(&"hit_l", SecureChip)
	var gap_item := _instance(&"hit_gap", ScrapMetal)
	_expect(prototype.squad_inventory.place(l_item, Vector2i(0, 0)), "hit test: L shape setup")
	_expect(prototype.squad_inventory.place(gap_item, Vector2i(1, 0)), "hit test: 1x1 fits the L gap")
	prototype._refresh_inventory_ui()
	await process_frame
	var l_control := prototype.inventory_grid.get_item_control(&"hit_l")
	var gap_control := prototype.inventory_grid.get_item_control(&"hit_gap")
	_expect(is_instance_valid(l_control) and is_instance_valid(gap_control), "hit test: L and gap controls exist after refresh")
	if is_instance_valid(l_control) and is_instance_valid(gap_control):
		_expect(l_control._has_point(Vector2(15, 15)), "hit test: L occupied top-left cell is clickable")
		_expect(l_control._has_point(Vector2(15, 45)), "hit test: L occupied bottom-left cell is clickable")
		_expect(l_control._has_point(Vector2(45, 45)), "hit test: L occupied bottom-right cell is clickable")
		_expect(not l_control._has_point(Vector2(45, 15)), "hit test: L missing cell is not clickable")
		_expect(not l_control._has_point(Vector2(-0.1, 15)), "hit test: point left of bounds is not clickable")
		_expect(not l_control._has_point(Vector2(60, 15)), "hit test: point on right boundary is not clickable")
		_expect(gap_control._has_point(Vector2(15, 15)), "hit test: 1x1 gap item is clickable")
		l_control.set_rotation_preview(90)
		_expect(l_control._has_point(Vector2(15, 15)), "hit test: rotated L occupied top-left cell is clickable")
		_expect(l_control._has_point(Vector2(45, 15)), "hit test: rotated L occupied top-right cell is clickable")
		_expect(l_control._has_point(Vector2(15, 45)), "hit test: rotated L occupied bottom-left cell is clickable")
		_expect(not l_control._has_point(Vector2(45, 45)), "hit test: rotated L missing cell is not clickable")
	await _free_prototype(prototype)


func _test_loot_targeted_place_and_return() -> void:
	var prototype := await _spawn_prototype()
	var player := prototype._unit_by_name(&"PlayerAlpha")
	_place_unit(prototype, player, Vector3i(1, 0, 2))
	player.reset_action_points()
	var container = prototype.loot_containers[&"loot_1"]
	var open_result := prototype.interact_with_loot(&"loot_1")
	_expect(open_result.success and open_result.action_type == &"interact" and open_result.ap_cost == 1, "loot: opening remains a one-AP Interact")
	_expect(player.current_action_points == 1, "loot: opening consumes one AP")
	_expect(prototype.loot_grid.get_item_control_count() > 0, "loot: instance controls should be visible")
	var item: InventoryItemInstance = container.get_item(0)
	var before_count: int = container.get_item_count()
	player.reset_action_points()
	var ap_before_place: int = player.current_action_points
	var place_result := prototype.place_loot_instance(&"loot_1", 0, Vector2i(0, 0), item.rotation)
	_expect(place_result.success and place_result.action_type == &"loot" and place_result.ap_cost == 0, "loot: targeted placement should be a free Loot action")
	_expect(player.current_action_points == ap_before_place, "loot: successful placement does not consume AP")
	_expect(container.get_item_count() == before_count - 1, "loot: successful placement removes one instance")
	var placed_id: StringName = item.instance_id
	var before_used: int = prototype.squad_inventory.used
	var before_ap: int = player.current_action_points
	var invalid := prototype.place_loot_instance(&"loot_1", 0, Vector2i(-1, 0), 0)
	_expect(not invalid.success and invalid.action_type == &"loot", "loot: invalid anchor should reject")
	_expect(container.get_item_count() == before_count - 1 and prototype.squad_inventory.used == before_used, "loot: invalid placement is atomic")
	_expect(player.current_action_points == before_ap, "loot: invalid placement does not consume AP")
	var return_result := prototype.return_inventory_instance_to_loot(placed_id, &"loot_1")
	_expect(return_result.success, "loot: item can return to current container")
	_expect(prototype.squad_inventory.get_placement(placed_id) == null, "loot: returned instance leaves inventory")
	var found_returned := false
	for returned_item in container.get_contents_instances():
		if returned_item.instance_id == placed_id:
			found_returned = true
	_expect(found_returned, "loot: return preserves instance identity")
	_expect(player.current_action_points == before_ap, "loot: return is inventory management and costs no AP")
	await _free_prototype(prototype)


func _test_inventory_rearrange_rotate_and_rollback() -> void:
	var prototype := await _spawn_prototype()
	var medkit := _instance(&"move_medkit", Medkit)
	var scrap := _instance(&"move_scrap", ScrapMetal)
	var watch := _instance(&"move_watch", RareWatch)
	_expect(prototype.squad_inventory.place(medkit, Vector2i(0, 0)), "rearrange: setup medkit")
	_expect(prototype.squad_inventory.place(watch, Vector2i(3, 0)), "rearrange: setup watch")
	_expect(prototype.squad_inventory.place(scrap, Vector2i(1, 6)), "rearrange: setup rotation blocker")
	prototype._refresh_inventory_ui()
	var move_result := prototype.move_inventory_instance(&"move_medkit", Vector2i(0, 6), 0)
	_expect(move_result.success, "rearrange: move to free cells")
	_expect(prototype.squad_inventory.get_placement(&"move_medkit").anchor == Vector2i(0, 6), "rearrange: anchor should update")
	var invalid_move := prototype.move_inventory_instance(&"move_medkit", Vector2i(3, 0), 0)
	_expect(not invalid_move.success, "rearrange: overlap should reject")
	_expect(prototype.squad_inventory.get_placement(&"move_medkit").anchor == Vector2i(0, 6), "rearrange: rejected overlap keeps anchor")
	var invalid_rotation := prototype.rotate_inventory_instance(&"move_medkit")
	_expect(not invalid_rotation.success, "rearrange: blocked rotation should reject")
	_expect(prototype.squad_inventory.get_placement(&"move_medkit").rotation == 0, "rearrange: rejected rotation keeps orientation")
	_expect(prototype.squad_inventory.remove(&"move_scrap"), "rearrange: remove temporary blocker")
	var rotate_result := prototype.rotate_inventory_instance(&"move_medkit")
	_expect(rotate_result.success, "rearrange: valid 90 degree rotation")
	_expect(prototype.squad_inventory.get_placement(&"move_medkit").rotation == 90, "rearrange: rotation should be stored")
	_expect(prototype.squad_inventory.get_cell_occupant(Vector2i(1, 6)).instance_id == &"move_medkit", "rearrange: rotated shape should occupy horizontal cell")
	var invalid_edge := prototype.move_inventory_instance(&"move_medkit", Vector2i(5, 7), 90)
	_expect(not invalid_edge.success, "rearrange: rotated out-of-bounds placement should reject")
	await _free_prototype(prototype)


func _test_fragmented_space_is_not_free_capacity() -> void:
	var prototype := await _spawn_prototype()
	var player := prototype._unit_by_name(&"PlayerAlpha")
	prototype.squad_inventory.configure(3, 2)
	_expect(prototype.squad_inventory.place(_instance(&"fragment_a", ScrapMetal), Vector2i(0, 0)), "fragment: top-left setup")
	_expect(prototype.squad_inventory.place(_instance(&"fragment_b", ScrapMetal), Vector2i(1, 0)), "fragment: top-middle setup")
	_expect(prototype.squad_inventory.place(_instance(&"fragment_c", ScrapMetal), Vector2i(2, 0)), "fragment: top-right setup")
	prototype._refresh_inventory_ui()
	_expect(prototype.squad_inventory.free == 3, "fragment: free cell count is three")
	_place_unit(prototype, player, Vector3i(10, 1, 1))
	player.reset_action_points()
	var open_result := prototype.interact_with_loot(&"loot_high")
	_expect(open_result.success, "fragment: high-value Loot should open")
	var container = prototype.loot_containers[&"loot_high"]
	var item: InventoryItemInstance = container.get_item(0)
	var before_count: int = container.get_item_count()
	player.reset_action_points()
	var preview := prototype.preview_inventory_command(&"loot_high", 0, item.instance_id, Vector2i(0, 0), 0, &"loot")
	_expect(not preview.valid, "fragment: shape preview should reject despite enough free cells")
	var before_ap := player.current_action_points
	var result := prototype.place_loot_instance(&"loot_high", 0, Vector2i(0, 0), 0)
	_expect(not result.success and result.reason == &"inventory_full", "fragment: placement should report inventory_full")
	_expect(container.get_item_count() == before_count and prototype.squad_inventory.used == 3, "fragment: rejected placement preserves both models")
	_expect(player.current_action_points == before_ap, "fragment: rejected placement costs no AP")
	await _free_prototype(prototype)


func _test_native_drag_and_key_input_path() -> void:
	var prototype := await _spawn_prototype()
	var player := prototype._unit_by_name(&"PlayerAlpha")
	_place_unit(prototype, player, Vector3i(1, 0, 2))
	player.reset_action_points()
	_expect(prototype.interact_with_loot(&"loot_1").success, "input: setup Loot should open")
	player.reset_action_points()
	var source_control := prototype.loot_grid.get_item_control(0)
	_expect(is_instance_valid(source_control), "input: Loot item Control should exist")
	if is_instance_valid(source_control):
		var payload: Dictionary = source_control._get_drag_data(Vector2.ZERO)
		_expect(source_control.get_active_drag_preview() != null, "input: drag visual should be retained for headless rotation updates")
		var key_event := InputEventKey.new()
		key_event.keycode = KEY_R
		key_event.pressed = true
		prototype.loot_grid._input(key_event)
		_expect(source_control.get_item_rotation() == 90, "input: native R input rotates the dragged preview")
		var can_drop := prototype.inventory_grid._can_drop_data(Vector2(5, 5), payload)
		_expect(can_drop, "input: native drag payload gets a valid grid preview")
		prototype.inventory_grid._drop_data(Vector2(5, 5), payload)
		_expect(prototype.squad_inventory.used > 0, "input: native drop transfers the instance")
		_expect(player.current_action_points == 2, "input: native drop uses the same free Loot command")
		_expect(not prototype.loot_grid.has_active_drag(), "input: successful drop clears Loot source drag")
		_expect(not prototype.inventory_grid.has_active_drag(), "input: successful drop clears inventory target drag")
		_expect(source_control.get_active_drag_preview() == null, "input: successful drop clears source drag visual")
	await _free_prototype(prototype)


func _test_drag_cleanup_and_live_rotation_preview() -> void:
	var prototype := await _spawn_prototype()
	var player := prototype._unit_by_name(&"PlayerAlpha")
	_place_unit(prototype, player, Vector3i(10, 1, 1))
	player.reset_action_points()
	_expect(prototype.interact_with_loot(&"loot_high").success, "drag lifecycle: Loot opens")
	var loot_control := prototype.loot_grid.get_item_control(1)
	var payload: Dictionary = loot_control._get_drag_data(Vector2.ZERO)
	_expect(prototype.inventory_grid._can_drop_data(Vector2.ZERO, payload), "drag lifecycle: establish legal hover preview")
	var before_cells := prototype.inventory_grid.get_preview_cells()
	var before_preview := loot_control.get_active_drag_preview()
	prototype.inventory_grid.rotate_active_drag()
	_expect(prototype.inventory_grid.get_preview_cells() != before_cells, "drag lifecycle: R recomputes preview cells without mouse movement")
	_expect(prototype.inventory_grid.get_active_drag_payload().get("rotation", 0) == 90, "drag lifecycle: target payload rotation updates")
	_expect(is_instance_valid(before_preview) and before_preview.get_item_rotation() == 90, "drag lifecycle: drag visual rotates with target preview")
	prototype.inventory_grid._notification(Control.NOTIFICATION_DRAG_END)
	prototype.loot_grid._notification(Control.NOTIFICATION_DRAG_END)
	_expect(not prototype.inventory_grid.has_active_drag() and not prototype.loot_grid.has_active_drag(), "drag lifecycle: cancel clears both grid payloads")
	var model_rotation: int = prototype.squad_inventory.get_placements().size()
	var after_cancel_payload := loot_control.get_drag_payload()
	prototype.loot_grid._input(_r_key_event())
	_expect(loot_control.get_drag_payload().get("rotation", 0) == after_cancel_payload.get("rotation", 0), "drag lifecycle: R after cancel does not rotate stale payload")
	_expect(prototype.squad_inventory.get_placements().size() == model_rotation, "drag lifecycle: cancel does not mutate inventory model")
	var failed_payload: Dictionary = loot_control._get_drag_data(Vector2.ZERO)
	_expect(not prototype.inventory_grid._can_drop_data(Vector2(-30, -30), failed_payload), "drag lifecycle: illegal hover is rejected")
	prototype.inventory_grid._notification(Control.NOTIFICATION_DRAG_END)
	prototype.loot_grid._notification(Control.NOTIFICATION_DRAG_END)
	_expect(not prototype.inventory_grid.has_active_drag() and not prototype.loot_grid.has_active_drag(), "drag lifecycle: failed/cancelled drop clears both grid payloads")
	await _free_prototype(prototype)


func _test_preview_rejects_closed_or_wrong_phase_loot() -> void:
	var prototype := await _spawn_prototype()
	var container = prototype.loot_containers[&"loot_1"]
	var item: InventoryItemInstance = container.get_item(0)
	var closed_preview := prototype.preview_inventory_command(&"loot_1", 0, item.instance_id, Vector2i.ZERO, 0, &"loot")
	_expect(not closed_preview.valid and closed_preview.reason == &"invalid_container", "preview guard: closed non-active Loot is rejected")
	var player := prototype._unit_by_name(&"PlayerAlpha")
	_place_unit(prototype, player, Vector3i(1, 0, 2))
	player.reset_action_points()
	_expect(prototype.interact_with_loot(&"loot_1").success, "preview guard: open Loot")
	prototype.session_manager.start_combat()
	var combat_preview := prototype.preview_inventory_command(&"loot_1", 0, item.instance_id, Vector2i.ZERO, 0, &"loot")
	_expect(not combat_preview.valid and combat_preview.reason == &"wrong_phase", "preview guard: Combat preview is rejected")
	await _free_prototype(prototype)


func _test_pending_loot_rotation_does_not_override_returned_instance() -> void:
	var prototype := await _spawn_prototype()
	var player := prototype._unit_by_name(&"PlayerAlpha")
	_place_unit(prototype, player, Vector3i(1, 0, 2))
	player.reset_action_points()
	_expect(prototype.interact_with_loot(&"loot_1").success, "pending rotation: Loot opens")
	var container = prototype.loot_containers[&"loot_1"]
	var item: InventoryItemInstance = container.get_item(0)
	var loot_control := prototype.loot_grid.get_item_control(0)
	loot_control._gui_input(_right_click_event())
	await process_frame
	var placed := prototype.place_loot_instance(&"loot_1", 0, Vector2i(0, 0), 90)
	_expect(placed.success, "pending rotation: rotated Loot item can be placed")
	var placement = prototype.squad_inventory.get_placement(item.instance_id)
	_expect(placement != null and placement.rotation == 90, "pending rotation: placed instance stores actual rotation")
	var rotated := prototype.rotate_inventory_instance(item.instance_id)
	_expect(rotated.success, "pending rotation: inventory rotation succeeds")
	var returned := prototype.return_inventory_instance_to_loot(item.instance_id, &"loot_1")
	_expect(returned.success, "pending rotation: returned instance succeeds")
	var returned_item: InventoryItemInstance = container.get_item(container.get_item_count() - 1)
	_expect(returned_item != null and returned_item.rotation == 180, "pending rotation: returned model rotation is authoritative")
	var returned_control := prototype.loot_grid.get_item_control(container.get_item_count() - 1)
	_expect(is_instance_valid(returned_control) and returned_control.get_item_rotation() == 180, "pending rotation: visual uses returned instance rotation")
	await _free_prototype(prototype)


func _r_key_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_R
	event.pressed = true
	return event


func _right_click_event() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	return event


func _test_settlement_reads_final_instances_once() -> void:
	var prototype := await _spawn_prototype()
	_expect(prototype.squad_inventory.place(_instance(&"settle_scrap", ScrapMetal), Vector2i(0, 0)), "settlement: scrap setup")
	_expect(prototype.squad_inventory.place(_instance(&"settle_watch", RareWatch), Vector2i(1, 0)), "settlement: watch setup")
	var settlement = LootSettlementScript.from_inventory(true, prototype.squad_inventory)
	_expect(settlement.is_successful(), "settlement: successful snapshot")
	_expect(settlement.get_items().size() == 2, "settlement: final instances appear once")
	_expect(settlement.get_total_value() == ScrapMetal.value + RareWatch.value, "settlement: value reads final definitions")
	var ids: Array[StringName] = []
	for item in settlement.get_items():
		ids.append(item.instance_id)
	_expect(ids.has(&"settle_scrap") and ids.has(&"settle_watch"), "settlement: instance identities are preserved")
	await _free_prototype(prototype)


func _spawn_prototype() -> PrototypeController:
	var prototype := MAIN_SCENE.instantiate() as PrototypeController
	get_root().add_child(prototype)
	await process_frame
	return prototype


func _free_prototype(prototype: PrototypeController) -> void:
	prototype.queue_free()
	await process_frame


func _instance(instance_id: StringName, definition: ItemDefinition) -> InventoryItemInstance:
	return InventoryItemInstanceScript.new(instance_id, definition, 0)


func _place_unit(prototype: PrototypeController, unit: PrototypeUnit, cell: Vector3i) -> void:
	prototype.grid.vacate(unit.grid_cell, unit.unit_id)
	prototype.grid.occupy(cell, unit.unit_id)
	unit.grid_cell = cell
	unit.global_position = prototype.grid.cell_to_world(cell)
	prototype._select_unit(unit)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("INVENTORY_GRID_UI_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("INVENTORY_GRID_UI_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
