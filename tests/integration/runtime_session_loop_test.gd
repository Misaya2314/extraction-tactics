extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main/prototype_main.tscn")
const GameStateManagerScript = preload("res://scripts/core/session/game_state_manager.gd")

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_session_cancel_api()
	await _test_loot_and_extraction()
	await _test_capacity_is_atomic()
	await _test_team_defeat_result()
	await _test_encounter_returns_to_exploration()
	_finish()


func _test_session_cancel_api() -> void:
	var manager := GameStateManagerScript.new()
	_expect(manager.start_exploration(), "session: cancel setup should enter exploration")
	_expect(manager.start_extraction(), "session: cancel setup should enter extraction")
	_expect(manager.cancel_extraction(), "session: cancel API should return to exploration")
	_expect(manager.get_state() == GameStateManagerScript.State.EXPLORATION and not manager.has_result(), "session: cancel should not create a result")
	_expect(not manager.cancel_extraction(), "session: duplicate cancel should be rejected")


func _test_loot_and_extraction() -> void:
	var prototype := await _spawn_prototype()
	var player := prototype._unit_by_name(&"PlayerAlpha")
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.EXPLORATION, "loop: controller should start exploration")
	var configured_loot_ids := _configured_loot_ids(prototype)
	_expect(not configured_loot_ids.is_empty(), "loot: map LOOT placements should expose valid configuration")
	for loot_id in configured_loot_ids:
		_expect(prototype.loot_containers.has(loot_id), "loot: every valid map LOOT placement should have a runtime container (%s)" % loot_id)
		_expect(prototype.loot_nodes_by_id.has(loot_id), "loot: every valid map LOOT placement should have a visual index entry (%s)" % loot_id)
	_expect(is_instance_valid(prototype.loot_panel) and is_instance_valid(prototype.extraction_panel) and is_instance_valid(prototype.result_panel), "ui: runtime panels should exist")
	_expect(not prototype.hint_label.text.is_empty(), "ui: first-operation hint should be visible")
	if not is_instance_valid(player):
		await _free_prototype(prototype)
		return

	_place_unit(prototype, player, Vector3i(1, 0, 2))
	player.spend_action_points(player.current_action_points)
	var container = prototype.loot_containers[&"loot_1"]
	var unopened_count: int = container.get_item_count()
	var rejected_open := prototype.interact_with_loot(&"loot_1")
	_expect(not rejected_open.success and rejected_open.action_type == &"interact" and rejected_open.reason == &"no_ap", "loot: zero-AP opening should reject before the handler")
	_expect(player.current_action_points == 0 and not container.is_opened() and container.get_item_count() == unopened_count and not prototype.loot_panel.visible, "loot: rejected opening should preserve the unopened container, AP and panel")

	player.reset_action_points()
	var open_ap_before: int = player.current_action_points
	var open_result := prototype.interact_with_loot(&"loot_1")
	_expect(open_result.success and open_result.action_type == &"interact" and open_result.ap_cost == 1, "loot: opening nearby container should be a one-AP Interact action")
	_expect(player.current_action_points == open_ap_before - 1 and container.is_opened(), "loot: successful opening should spend one AP and expose contents")
	_expect(prototype.loot_panel.visible, "loot: opening should show the loot panel")

	player.reset_action_points()
	player.spend_action_points(player.current_action_points)
	var before_count: int = container.get_item_count()
	var loot_result := prototype.loot_item(0)
	_expect(loot_result.success and loot_result.action_type == &"loot" and loot_result.ap_cost == 0, "loot: valid opened-container pickup should be a free Loot action")
	_expect(player.current_action_points == 0, "loot: item pickup should remain free at zero AP")
	_expect(container.get_item_count() == before_count - 1 and prototype.squad_inventory.used > 0, "loot: item should move into squad inventory")
	prototype._refresh_highlights()
	_expect(prototype.object_highlights_root.get_child_count() > 0, "highlight: nearby loot should have an interaction highlight")

	_place_unit(prototype, player, Vector3i(11, 0, 7))
	player.reset_action_points()
	prototype._refresh_highlights()
	_expect(prototype.object_highlights_root.get_child_count() > 0, "highlight: nearby extraction should have an interaction highlight")
	await prototype._handle_cell_click(Vector3i(11, 0, 8))
	_expect(player.grid_cell == Vector3i(11, 0, 8), "extraction click: empty extraction cell should move the selected unit")
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.EXTRACTION and prototype.extraction_panel.visible, "extraction click: moving onto extraction should open confirmation")
	var ap_before_cancel: int = player.current_action_points
	_expect(prototype.cancel_extraction(), "extraction: cancel should return to exploration")
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.EXPLORATION and player.current_action_points == ap_before_cancel, "extraction: cancel should not consume AP")

	player.spend_action_points(player.current_action_points)
	await prototype._handle_cell_click(Vector3i(11, 0, 8))
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.EXPLORATION, "extraction click: zero AP must not enter confirmation")

	player.reset_action_points()
	await prototype._handle_cell_click(Vector3i(11, 0, 8))
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.EXTRACTION and prototype.extraction_panel.visible, "extraction click: occupied extraction cell should open confirmation")
	var confirm_result := prototype.confirm_extraction()
	_expect(confirm_result.success and confirm_result.action_type == &"interact", "extraction: confirm should be an Interact action")
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.RESULT, "extraction: confirmation should enter session result")
	_expect(prototype.session_manager.get_result_success(), "extraction: confirmed extraction should succeed")
	_expect(prototype.loot_settlement != null and prototype.loot_settlement.get_total_value() > 0, "extraction: settlement should preserve carried value")
	_expect(prototype.result_panel.visible and prototype.end_turn_button.disabled, "extraction: result UI should be visible and actions locked")
	await _free_prototype(prototype)


func _test_capacity_is_atomic() -> void:
	var prototype := await _spawn_prototype()
	var player := prototype._unit_by_name(&"PlayerAlpha")
	_place_unit(prototype, player, Vector3i(7, 0, 3))
	prototype.squad_inventory.configure(0)
	player.spend_action_points(player.current_action_points)
	var container = prototype.loot_containers[&"loot_2"]
	var unopened_count: int = container.get_item_count()
	var rejected_open := prototype.interact_with_loot(&"loot_2")
	_expect(not rejected_open.success and rejected_open.reason == &"no_ap", "capacity: zero-AP opening should reject before inventory validation")
	_expect(player.current_action_points == 0 and not container.is_opened() and container.get_item_count() == unopened_count and not prototype.loot_panel.visible, "capacity: zero-AP opening rejection must preserve the container and panel")
	player.reset_action_points()
	var open_ap_before: int = player.current_action_points
	var open_result := prototype.interact_with_loot(&"loot_2")
	_expect(open_result.success and open_result.ap_cost == 1 and player.current_action_points == open_ap_before - 1, "capacity: opening should spend one AP")
	player.spend_action_points(player.current_action_points)
	var before_count: int = container.get_item_count()
	var before_ap: int = player.current_action_points
	var rejected := prototype.loot_item(0)
	_expect(not rejected.success and rejected.action_type == &"loot" and rejected.reason == &"inventory_full", "capacity: full inventory should reject through Loot action")
	_expect(container.get_item_count() == before_count and player.current_action_points == before_ap, "capacity: rejected pickup must be atomic")
	await _free_prototype(prototype)


func _test_team_defeat_result() -> void:
	var prototype := await _spawn_prototype()
	for player_id in prototype.turn_manager.get_player_ids().duplicate():
		var player := prototype._unit_by_id(player_id)
		if is_instance_valid(player):
			player.take_damage(player.current_hp)
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.RESULT, "failure: last living player should enter result")
	_expect(not prototype.session_manager.get_result_success(), "failure: all players down should be failure")
	_expect(prototype.loot_settlement != null and prototype.loot_settlement.get_total_value() == 0 and prototype.loot_settlement.get_items().is_empty(), "failure: failed settlement should contain no loot")
	_expect(prototype.result_panel.visible and prototype.end_turn_button.disabled, "failure: failed result should lock UI")
	await _free_prototype(prototype)


func _test_encounter_returns_to_exploration() -> void:
	var prototype := await _spawn_prototype()
	var player := prototype._unit_by_name(&"PlayerAlpha")
	var enemy := prototype._unit_by_name(&"EnemyGuard")
	_expect(prototype._start_combat(true, enemy, player.grid_cell, player.unit_id), "encounter: explicit combat start should enter combat")
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.COMBAT, "encounter: active fight should update session state")
	_expect(prototype.active_encounter_id == &"outpost" and prototype.turn_manager.get_enemy_ids().size() == 3, "encounter: only the selected outpost group should be active")
	_expect(not prototype.turn_manager.get_enemy_ids().has(prototype._unit_by_name(&"EnemyScout").unit_id), "encounter: warehouse enemies should not join the outpost fight")
	for enemy_id in prototype.turn_manager.get_enemy_ids().duplicate():
		var target := prototype._unit_by_id(enemy_id)
		if is_instance_valid(target):
			target.take_damage(target.current_hp)
	_expect(prototype.turn_manager.get_phase() == TurnManager.Phase.EXPLORATION, "encounter: clearing enemies should return turn flow to exploration")
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.EXPLORATION and not prototype.session_manager.is_terminal(), "encounter: clearing enemies must not end the session")
	player.reset_action_points()
	await prototype._move_selected_unit(Vector3i(1, 0, 2))
	_expect(player.grid_cell == Vector3i(1, 0, 2), "encounter: player should still be able to move after encounter")
	await _free_prototype(prototype)


func _spawn_prototype() -> PrototypeController:
	var prototype := MAIN_SCENE.instantiate() as PrototypeController
	get_root().add_child(prototype)
	await process_frame
	return prototype


func _free_prototype(prototype: PrototypeController) -> void:
	prototype.queue_free()
	await process_frame


func _place_unit(prototype: PrototypeController, unit: PrototypeUnit, cell: Vector3i) -> void:
	prototype.grid.vacate(unit.grid_cell, unit.unit_id)
	prototype.grid.occupy(cell, unit.unit_id)
	unit.grid_cell = cell
	unit.global_position = prototype.grid.cell_to_world(cell)
	prototype._select_unit(unit)


func _configured_loot_ids(prototype: PrototypeController) -> Array[StringName]:
	var ids: Array[StringName] = []
	if prototype == null or prototype.map_definition == null:
		return ids
	for placement_value in prototype.map_definition.objects:
		var placement := placement_value as MapObjectPlacement
		if placement == null or placement.object_id == &"":
			continue
		if placement.kind != MapObjectPlacement.Kind.LOOT or not placement.is_loot_configuration_valid():
			continue
		ids.append(placement.object_id)
	ids.sort()
	return ids


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("RUNTIME_SESSION_LOOP_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("RUNTIME_SESSION_LOOP_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
