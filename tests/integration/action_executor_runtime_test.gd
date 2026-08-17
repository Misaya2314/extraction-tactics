extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main/prototype_main.tscn")
const GameStateManagerScript = preload("res://scripts/core/session/game_state_manager.gd")
const SquadInventoryScript = preload("res://scripts/core/inventory/squad_inventory.gd")

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_move_pipeline()
	await _test_enemy_attack_no_ap_termination()
	await _test_attack_pipeline()
	await _test_interact_pipeline()
	await _test_loot_pipeline()
	_finish()


func _test_move_pipeline() -> void:
	var prototype := await _spawn_prototype()
	var player := prototype._unit_by_name(&"PlayerAlpha")
	var patrol_enemy := prototype._unit_by_name(&"EnemyScout")
	_expect(prototype.action_executor != null, "actions: controller should own an executor")
	for action_type in [&"move", &"attack", &"interact", &"loot"]:
		_expect(prototype.action_executor.get_handler(action_type).is_valid(), "actions: executor should register %s handler" % action_type)

	var start_cell := player.grid_cell
	var destination := Vector3i(1, 0, 2)
	var player_ap_before := player.current_action_points
	await prototype._move_selected_unit(destination)
	_expect(prototype.last_action_result != null and prototype.last_action_result.success, "move: selected player should use a successful executor action")
	_expect(prototype.last_action_result.action_type == &"move" and prototype.last_action_result.ap_cost == 1, "move: result should identify one-AP Move")
	_expect(player.current_action_points == player_ap_before - 1, "move: player AP should be committed exactly once")
	_expect(player.grid_cell == destination and prototype.grid.get_occupant(destination) == player.unit_id, "move: logical occupancy should reach destination")
	_expect(prototype.grid.get_occupant(start_cell) == &"" and player.global_position.distance_to(prototype.grid.cell_to_world(destination)) < 0.01, "move: visual endpoint and vacated cell should agree")

	prototype._refresh_highlights()
	var unlocked_move_count := prototype.highlights_root.get_child_count()
	_expect(unlocked_move_count > 0 and prototype.highlights_root.visible, "highlights: unlocked player should show move cells")
	prototype.input_locked = true
	prototype._refresh_highlights()
	_expect(not prototype._can_show_move_highlights(), "highlights: input lock should disable tactical highlight eligibility")
	await process_frame
	_expect(prototype.highlights_root.get_child_count() == 0, "highlights: input lock should clear move cells")
	_expect(prototype.attack_highlights_root.get_child_count() == 0, "highlights: input lock should clear attack cells")
	_expect(prototype.object_highlights_root.get_child_count() == 0, "highlights: input lock should clear object cells")
	_expect(not prototype.highlights_root.visible and not prototype.attack_highlights_root.visible and not prototype.object_highlights_root.visible, "highlights: input lock should hide tactical highlight roots")
	prototype.input_locked = false
	prototype._refresh_highlights()
	_expect(prototype.highlights_root.visible and prototype.highlights_root.get_child_count() > 0, "highlights: unlocking should restore move cells")

	var patrol_ap_before := patrol_enemy.current_action_points
	await prototype._run_exploration_tick()
	_expect(patrol_enemy.current_action_points == patrol_ap_before, "patrol: zero-AP exploration Move should not spend enemy AP")
	_expect(prototype.last_action_result != null and prototype.last_action_result.action_type == &"move" and prototype.last_action_result.ap_cost == 0, "patrol: exploration movement should use the executor with zero cost")

	var guard := prototype._unit_by_name(&"EnemyGuard")
	_expect(prototype._start_combat(true, guard, player.grid_cell, player.unit_id), "AI move: setup should enter the guard encounter")
	_expect(prototype.turn_manager.end_player_turn(), "AI move: setup should enter the enemy turn")
	guard.reset_action_points()
	var ai_destination := prototype._best_enemy_move(guard, player)
	if ai_destination == guard.grid_cell:
		_expect(false, "AI move: guard should have a reachable tactical destination")
	else:
		var ai_start := guard.grid_cell
		var ai_path := prototype.grid.find_path(ai_start, ai_destination)
		var ai_ap_before := guard.current_action_points
		var ai_moved := await prototype._move_unit(guard, ai_destination, ai_path, 1)
		_expect(ai_moved and prototype.last_action_result.action_type == &"move", "AI move: enemy movement should use the same Move executor")
		_expect(guard.current_action_points == ai_ap_before - 1, "AI move: enemy AP should be committed once")
		_expect(guard.grid_cell == ai_destination and prototype.grid.get_occupant(ai_destination) == guard.unit_id, "AI move: enemy occupancy should reach its destination")
	await _free_prototype(prototype)


func _test_enemy_attack_no_ap_termination() -> void:
	var prototype := await _spawn_prototype()
	var player := prototype._unit_by_name(&"PlayerAlpha")
	var bravo := prototype._unit_by_name(&"PlayerBravo")
	var assault := prototype._unit_by_name(&"EnemyAssault_1")
	var scout := prototype._unit_by_name(&"EnemyScout")
	var rifleman := prototype._unit_by_name(&"EnemyRifleman_2")
	_place_unit(prototype, player, Vector3i(9, 0, 1))
	_relocate_unit(prototype, assault, Vector3i(5, 0, 1))
	bravo.take_damage(bravo.current_hp)
	scout.take_damage(scout.current_hp)
	rifleman.take_damage(rifleman.current_hp)
	var start_cell := assault.grid_cell
	var player_hp_before := player.current_hp
	_expect(assault.attack_ap_cost == 1, "enemy AP guard: authored shotgun should use one AP")
	# Keep this regression independent of authored weapon data: a future
	# two-AP weapon must still terminate safely after moving into range.
	assault.attack_ap_cost = 2
	_expect(prototype._start_combat(true, assault, player.grid_cell, player.unit_id), "enemy AP guard: should activate the isolated assault encounter")
	_expect(prototype.turn_manager.get_enemy_ids().size() == 1, "enemy AP guard: test encounter should contain only the assault enemy")
	_expect(prototype.turn_manager.end_player_turn(), "enemy AP guard: should enter enemy turn")

	# _run_enemy_turn contains the observable termination under test. The
	# controller-side attempt guard also prevents a future failed-action loop
	# from blocking the headless test process.
	await prototype._run_enemy_turn()
	_expect(prototype.turn_manager.is_player_turn(), "enemy AP guard: enemy turn should terminate and return to player turn")
	_expect(not prototype.input_locked, "enemy AP guard: enemy turn should release input lock")
	_expect(prototype.last_action_result.action_type == &"attack" and prototype.last_action_result.reason == &"no_ap", "enemy AP guard: the unaffordable attack should expose no_ap")
	_expect(player.current_hp == player_hp_before, "enemy AP guard: no-AP shotgun attack must not damage the target")
	_expect(assault.current_action_points == assault.max_action_points - 1, "enemy AP guard: only the preceding move should spend AP")
	_expect(assault.grid_cell != start_cell and prototype._manhattan(assault.grid_cell, player.grid_cell) <= assault.attack_range, "enemy AP guard: enemy should have moved into attack range before rejection")
	await _free_prototype(prototype)


func _test_attack_pipeline() -> void:
	var prototype := await _spawn_prototype()
	var bravo := prototype._unit_by_name(&"PlayerBravo")
	var scout := prototype._unit_by_name(&"EnemyScout")
	_place_unit(prototype, bravo, Vector3i(5, 0, 1))
	bravo.reset_action_points()
	_expect(bravo.weapon.weapon_id == &"shotgun" and bravo.attack_damage == 5 and bravo.attack_range == 3 and bravo.attack_ap_cost == 1, "attack: PlayerBravo should use the authored one-AP shotgun")
	_expect(scout.weapon.weapon_id == &"carbine" and scout.attack_ap_cost == 1 and scout.attack_range == 7, "attack: enemy carbine stats should remain data-driven")

	var hp_before := scout.current_hp
	var ap_before := bravo.current_action_points
	var attack_result := await prototype._attack_with_unit(bravo, scout)
	_expect(attack_result.success and attack_result.action_type == &"attack", "attack: player attack should be an executor Attack")
	_expect(attack_result.damage == bravo.attack_damage and scout.current_hp == hp_before - bravo.attack_damage, "attack: weapon damage should be applied exactly once")
	_expect(bravo.current_action_points == ap_before - bravo.attack_ap_cost, "attack: shotgun AP should be committed exactly once")
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.COMBAT, "attack: proactive attack should enter combat")

	bravo.spend_action_points(bravo.current_action_points)
	var hp_before_rejected := scout.current_hp
	var rejected := await prototype._attack_with_unit(bravo, scout)
	_expect(not rejected.success and rejected.action_type == &"attack" and rejected.reason == &"no_ap", "attack: insufficient AP should reject through executor")
	_expect(scout.current_hp == hp_before_rejected and prototype.session_manager.get_state() == GameStateManagerScript.State.COMBAT, "attack: rejected attack should not damage or alter combat state")
	await _free_prototype(prototype)


func _test_interact_pipeline() -> void:
	var prototype := await _spawn_prototype()
	var player := prototype._unit_by_name(&"PlayerAlpha")
	_place_unit(prototype, player, Vector3i(1, 0, 2))
	player.spend_action_points(player.current_action_points)
	var container = prototype.loot_containers[&"loot_1"]
	var unopened_count: int = container.get_item_count()
	var rejected_open := prototype.interact_with_loot(&"loot_1")
	_expect(not rejected_open.success and rejected_open.action_type == &"interact" and rejected_open.reason == &"no_ap" and rejected_open.ap_cost == 1, "interact: zero-AP Loot opening should reject before the handler")
	_expect(player.current_action_points == 0 and not container.is_opened() and container.get_item_count() == unopened_count and not prototype.loot_panel.visible, "interact: rejected zero-AP opening should preserve container, AP and panel")
	player.reset_action_points()
	var ap_before_open := player.current_action_points
	var open_result := prototype.interact_with_loot(&"loot_1")
	_expect(open_result.success and open_result.action_type == &"interact" and open_result.ap_cost == 1, "interact: opening Loot should use one executor Interact AP")
	_expect(player.current_action_points == ap_before_open - 1 and container.is_opened() and prototype.loot_panel.visible, "interact: successful opening should spend one AP and show the panel")

	_place_unit(prototype, player, Vector3i(11, 0, 8))
	player.reset_action_points()
	var ap_before_prompt := player.current_action_points
	var prompt_result := prototype.begin_extraction_prompt(&"extraction")
	_expect(prompt_result.success and prompt_result.action_type == &"interact" and prompt_result.ap_cost == 0, "interact: extraction prompt should be a zero-cost Interact")
	_expect(player.current_action_points == ap_before_prompt and prototype.session_manager.get_state() == GameStateManagerScript.State.EXTRACTION, "interact: prompt should not spend AP or skip confirmation")
	player.spend_action_points(player.current_action_points)
	var confirm_rejected := prototype.confirm_extraction()
	_expect(not confirm_rejected.success and confirm_rejected.reason == &"no_ap", "interact: confirmation should reject without one AP")
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.EXTRACTION, "interact: rejected confirmation should keep the prompt open")
	_expect(prototype.cancel_extraction(), "interact: extraction cancel should return to exploration")

	player.reset_action_points()
	var prompt_again := prototype.begin_extraction_prompt(&"extraction")
	var confirm_result := prototype.confirm_extraction()
	_expect(prompt_again.success and confirm_result.success and confirm_result.action_type == &"interact" and confirm_result.ap_cost == 1, "interact: confirmed extraction should use one executor Interact")
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.RESULT, "interact: confirmed extraction should produce the session result")
	await _free_prototype(prototype)


func _test_loot_pipeline() -> void:
	var prototype := await _spawn_prototype()
	var player := prototype._unit_by_name(&"PlayerAlpha")
	_place_unit(prototype, player, Vector3i(1, 0, 2))
	player.reset_action_points()
	var open_result := prototype.interact_with_loot(&"loot_1")
	var container = prototype.loot_containers[&"loot_1"]
	var item = container.get_item(0)
	var anchor: Vector2i = prototype.squad_inventory.find_first_fit(item, item.rotation)
	var count_before: int = container.get_item_count()
	player.reset_action_points()
	player.spend_action_points(player.current_action_points)
	var ap_before_loot := player.current_action_points
	var loot_result := prototype.place_loot_instance(&"loot_1", 0, anchor, item.rotation)
	_expect(open_result.success and open_result.ap_cost == 1 and loot_result.success and loot_result.action_type == &"loot" and loot_result.ap_cost == 0, "loot: opening should cost one AP and targeted placement should be a free executor Loot action")
	_expect(player.current_action_points == ap_before_loot, "loot: valid placement should remain free at zero AP")
	_expect(container.get_item_count() == count_before - 1 and prototype.squad_inventory.get_placement(item.instance_id) != null, "loot: successful placement should transfer the same instance")

	var next_item = container.get_item(0)
	var count_before_invalid: int = container.get_item_count()
	var ap_before_invalid := player.current_action_points
	var invalid := prototype.place_loot_instance(&"loot_1", 0, Vector2i(-1, 0), next_item.rotation)
	_expect(not invalid.success and invalid.reason == &"inventory_full", "loot: invalid anchor should reject through Loot validation")
	_expect(container.get_item_count() == count_before_invalid and player.current_action_points == ap_before_invalid, "loot: invalid placement should be atomic")

	var valid_anchor: Vector2i = prototype.squad_inventory.find_first_fit(next_item, next_item.rotation)
	_expect(valid_anchor != SquadInventoryScript.NO_FIT, "loot: second item should have a valid first-fit anchor")
	var count_before_zero_ap: int = container.get_item_count()
	var zero_ap_pickup := prototype.place_loot_instance(&"loot_1", 0, valid_anchor, next_item.rotation)
	_expect(zero_ap_pickup.success and zero_ap_pickup.action_type == &"loot" and zero_ap_pickup.ap_cost == 0, "loot: opened-container pickup should succeed at zero AP")
	_expect(container.get_item_count() == count_before_zero_ap - 1 and player.current_action_points == 0, "loot: zero-AP pickup should change only the inventory/container state")
	await _free_prototype(prototype)

	var all_prototype := await _spawn_prototype()
	var all_player := all_prototype._unit_by_name(&"PlayerAlpha")
	_place_unit(all_prototype, all_player, Vector3i(7, 0, 3))
	all_player.reset_action_points()
	var all_open_ap_before := all_player.current_action_points
	var all_open := all_prototype.interact_with_loot(&"loot_2")
	_expect(all_open.success and all_open.ap_cost == 1 and all_player.current_action_points == all_open_ap_before - 1, "loot: Loot All setup opening should spend one AP")
	all_player.spend_action_points(all_player.current_action_points)
	var all_ap_before := all_player.current_action_points
	var all_result := all_prototype.loot_all()
	_expect(all_result.success and all_result.action_type == &"loot" and all_result.ap_cost == 0, "loot: Loot All should use a free executor Loot action")
	_expect(all_player.current_action_points == all_ap_before and all_player.current_action_points == 0, "loot: Loot All should remain free at zero AP")
	_expect(all_prototype.loot_containers[&"loot_2"].is_depleted(), "loot: successful Loot All should deplete the container")
	await _free_prototype(all_prototype)


func _spawn_prototype() -> PrototypeController:
	var prototype := MAIN_SCENE.instantiate() as PrototypeController
	get_root().add_child(prototype)
	await process_frame
	return prototype


func _free_prototype(prototype: PrototypeController) -> void:
	prototype.queue_free()
	await process_frame


func _place_unit(prototype: PrototypeController, unit: PrototypeUnit, cell: Vector3i) -> void:
	_relocate_unit(prototype, unit, cell)
	prototype._select_unit(unit)


func _relocate_unit(prototype: PrototypeController, unit: PrototypeUnit, cell: Vector3i) -> void:
	prototype.grid.vacate(unit.grid_cell, unit.unit_id)
	prototype.grid.occupy(cell, unit.unit_id)
	unit.grid_cell = cell
	unit.global_position = prototype.grid.cell_to_world(cell)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("ACTION_EXECUTOR_RUNTIME_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ACTION_EXECUTOR_RUNTIME_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
