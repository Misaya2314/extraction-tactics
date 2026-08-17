extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main/prototype_main.tscn")
const GameStateManagerScript = preload("res://scripts/core/session/game_state_manager.gd")
const SURFACE_OFFSET := 0.025

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var prototype := MAIN_SCENE.instantiate() as PrototypeController
	get_root().add_child(prototype)
	await process_frame

	var unit := prototype.selected_unit
	_expect(is_instance_valid(unit), "initial: a player unit should be selected")
	if not is_instance_valid(unit):
		_finish(prototype)
		return

	var initial_reachable := _movement_cells(prototype)
	_expect(not initial_reachable.is_empty(), "initial: selected unit should have reachable cells")
	_expect(prototype.action_mode == PrototypeController.ACTION_MODE_MOVE, "initial: selected player should start in move mode")
	_expect(is_instance_valid(prototype.move_action_button), "initial: move action button should exist")
	_expect(is_instance_valid(prototype.attack_action_button), "initial: attack action button should exist")
	_expect(prototype.move_action_button.button_pressed, "initial: move action button should be selected")
	_expect(not prototype.attack_action_button.button_pressed, "initial: attack action button should not be selected")
	_expect(prototype.action_bar.visible, "initial: action bar should be visible for a selected player")
	_expect(prototype.highlights_root.visible, "initial: move highlight layer should be visible")
	_expect(not prototype.attack_highlights_root.visible, "initial: attack highlight layer should be hidden in move mode")
	_expect(_highlight_cells(prototype) == initial_reachable, "initial: highlights should match weighted reachable cells")
	_assert_highlight_nodes(prototype, "initial")
	prototype._select_unit(null)
	await process_frame
	_expect(not prototype.action_bar.visible, "selection: action bar should hide without a selected player")
	prototype._select_unit(unit)
	await process_frame
	_expect(prototype.action_bar.visible, "selection: action bar should return when a player is selected")

	var mode_blocked_destination := initial_reachable[0]
	var start_cell := unit.grid_cell
	prototype.attack_action_button.emit_signal("pressed")
	await process_frame
	_expect(prototype.action_mode == PrototypeController.ACTION_MODE_ATTACK, "mode: attack button should switch to attack mode")
	_expect(not prototype.highlights_root.visible, "mode: move highlights should hide in attack mode")
	_expect(prototype.attack_highlights_root.visible, "mode: attack highlights should show in attack mode")
	await prototype._handle_cell_click(mode_blocked_destination)
	_expect(unit.grid_cell == start_cell, "mode: attack mode should not move on a movement cell click")
	_expect(prototype.selected_unit == null, "mode: clicking an empty non-target cell should cancel selection")
	prototype._select_unit(unit)
	prototype.attack_action_button.emit_signal("pressed")
	await process_frame
	var other_player := prototype._unit_by_name(&"PlayerBravo")
	await prototype._handle_cell_click(other_player.grid_cell)
	_expect(prototype.selected_unit == other_player, "mode: clicking another player should select that unit")
	_expect(prototype.action_mode == PrototypeController.ACTION_MODE_MOVE, "mode: selecting another player should return to move mode")
	prototype._select_unit(unit)
	prototype.move_action_button.emit_signal("pressed")
	await process_frame
	_expect(prototype.action_mode == PrototypeController.ACTION_MODE_MOVE, "mode: move button should restore move mode")

	var attack_enemy := prototype._unit_by_name(&"EnemyScout")
	var original_enemy_cell := attack_enemy.grid_cell
	var attack_target_cell := mode_blocked_destination
	_expect(prototype.grid.vacate(original_enemy_cell, attack_enemy.unit_id), "attack: setup should release the enemy cell")
	_expect(prototype.grid.occupy(attack_target_cell, attack_enemy.unit_id), "attack: setup should occupy a visible target cell")
	attack_enemy.grid_cell = attack_target_cell
	attack_enemy.global_position = prototype.grid.cell_to_world(attack_target_cell)
	prototype._set_debug_reveal_all(true)
	prototype._select_unit(unit)
	prototype.attack_action_button.emit_signal("pressed")
	await process_frame
	_expect(_attack_highlight_cells(prototype).has(attack_target_cell), "attack: attack mode should highlight a visible in-range enemy cell in red")
	var attack_ap_before := unit.current_action_points
	var attack_hp_before := attack_enemy.current_hp
	await prototype._handle_cell_click(attack_target_cell)
	_expect(attack_enemy.current_hp == attack_hp_before - unit.attack_damage, "attack: clicking a red enemy cell should apply the attack")
	_expect(unit.current_action_points == attack_ap_before - unit.attack_ap_cost, "attack: clicking a red enemy cell should spend attack AP")
	_expect(prototype.action_mode == PrototypeController.ACTION_MODE_ATTACK, "attack: successful attack should preserve attack mode")
	prototype.turn_manager.reset_to_exploration()
	prototype.session_manager.resolve_combat()
	await process_frame
	prototype.grid.vacate(attack_target_cell, attack_enemy.unit_id)
	prototype.grid.occupy(original_enemy_cell, attack_enemy.unit_id)
	attack_enemy.grid_cell = original_enemy_cell
	attack_enemy.global_position = prototype.grid.cell_to_world(original_enemy_cell)
	prototype._set_debug_reveal_all(false)
	prototype._select_unit(unit)

	var extraction_cell: Vector3i = prototype.extraction_cells[0]
	var extraction_id: StringName = prototype._extraction_at_cell(extraction_cell)
	var approach_cell := Vector3i(extraction_cell.x, extraction_cell.y, extraction_cell.z - 1)
	var original_player_cell := unit.grid_cell
	_expect(extraction_id != &"", "extraction: setup should find an extraction object")
	_expect(prototype.grid.vacate(original_player_cell, unit.unit_id), "extraction: setup should release the player cell")
	_expect(prototype.grid.occupy(approach_cell, unit.unit_id), "extraction: setup should occupy the approach cell")
	unit.grid_cell = approach_cell
	unit.global_position = prototype.grid.cell_to_world(approach_cell)
	unit.reset_action_points()
	prototype._select_unit(unit)
	prototype.attack_action_button.emit_signal("pressed")
	await process_frame
	await prototype._handle_cell_click(extraction_cell)
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.EXTRACTION, "extraction: attack mode should still open extraction confirmation")
	_expect(prototype.extraction_panel.visible, "extraction: attack mode should show extraction confirmation")
	if prototype.session_manager.get_state() == GameStateManagerScript.State.EXTRACTION:
		prototype.cancel_extraction()
	prototype.grid.vacate(extraction_cell, unit.unit_id)
	prototype.grid.occupy(original_player_cell, unit.unit_id)
	unit.grid_cell = original_player_cell
	unit.global_position = prototype.grid.cell_to_world(original_player_cell)
	unit.reset_action_points()
	prototype._select_unit(unit)

	var destination := Vector3i(1, 0, 2)
	await prototype._move_selected_unit(destination)
	await process_frame
	_expect(unit.grid_cell == destination, "move: selected unit should reach the destination")
	_expect(not _highlight_cells(prototype).is_empty(), "move: highlights should refresh after movement")
	_expect(_highlight_cells(prototype) == _movement_cells(prototype), "move: highlights should match the new reachable cells")

	unit.spend_action_points(unit.current_action_points)
	await process_frame
	_expect(_highlight_cells(prototype).is_empty(), "AP: spending the last AP should clear move highlights")

	await prototype._on_end_turn_pressed()
	await process_frame
	_expect(unit.current_action_points == unit.max_action_points, "turn: exploration tick should reset player AP")
	_expect(not _highlight_cells(prototype).is_empty(), "turn: AP reset should restore move highlights")
	_expect(_highlight_cells(prototype) == _movement_cells(prototype), "turn: refreshed highlights should use current reachable cells")

	var encounter_enemy := prototype._unit_by_name(&"EnemyScout")
	_expect(prototype._start_combat(true, encounter_enemy, unit.grid_cell, unit.unit_id), "phase: an authored encounter should start combat")
	await process_frame
	_expect(prototype.turn_manager.is_player_turn(), "phase: combat should enter the player turn")
	_expect(not _highlight_cells(prototype).is_empty(), "phase: player turn should show move highlights")
	_expect(prototype.turn_manager.end_player_turn(), "phase: player turn should end")
	await process_frame
	_expect(prototype.turn_manager.is_enemy_turn(), "phase: enemy turn should follow player turn")
	_expect(_highlight_cells(prototype).is_empty(), "phase: enemy turn should clear player move highlights")
	_expect(prototype.turn_manager.end_enemy_turn(), "phase: enemy turn should end")
	await process_frame
	_expect(prototype.turn_manager.is_player_turn(), "phase: next player turn should start")
	_expect(_highlight_cells(prototype) == _movement_cells(prototype), "phase: next player turn should restore current highlights")
	_expect(prototype.turn_manager.reset_to_exploration(), "phase: live combat should reset to exploration")
	await process_frame

	var weighted_cell := Vector3i(0, 0, 1)
	_expect(prototype.grid.get_reachable_cells(unit.grid_cell, unit.move_range).has(weighted_cell), "weighted: test cell should initially be reachable")
	_expect(prototype.grid.set_move_cost(weighted_cell, unit.move_range + 1), "weighted: test cell cost should be configurable")
	prototype._refresh_move_highlights()
	await process_frame
	_expect(not _highlight_cells(prototype).has(weighted_cell), "weighted: cell over the movement budget should not be highlighted")

	var old_cell := unit.grid_cell
	var high_cell := Vector3i(8, 1, 1)
	_expect(prototype.grid.vacate(old_cell, unit.unit_id), "height: current cell should be released")
	_expect(prototype.grid.occupy(high_cell, unit.unit_id), "height: high-level test cell should be occupied")
	unit.grid_cell = high_cell
	unit.global_position = prototype.grid.cell_to_world(high_cell)
	unit.reset_action_points()
	prototype._select_unit(unit)
	await process_frame

	var high_highlights := _highlight_cells(prototype)
	_expect(not high_highlights.is_empty(), "height: high-level unit should have move highlights")
	var has_high_level_highlight := false
	for cell in high_highlights:
		if cell.y <= 0:
			continue
		has_high_level_highlight = true
		var node := _highlight_node(prototype, cell)
		_expect(is_instance_valid(node), "height: high-level highlight node should exist")
		if is_instance_valid(node):
			var expected_position := prototype.grid.cell_to_world(cell) + Vector3.UP * SURFACE_OFFSET
			_expect(node.global_position.is_equal_approx(expected_position), "height: highlight should use the cell world height")
	_expect(has_high_level_highlight, "height: reachable high-level cells should be highlighted")
	_assert_highlight_nodes(prototype, "height")

	_finish(prototype)


func _movement_cells(prototype: PrototypeController) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if not is_instance_valid(prototype.selected_unit):
		return result
	for cell in prototype.grid.get_reachable_cells(prototype.selected_unit.grid_cell, prototype.selected_unit.move_range):
		if cell != prototype.selected_unit.grid_cell:
			result.append(cell)
	return result


func _highlight_cells(prototype: PrototypeController) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for child in prototype.highlights_root.get_children():
		if child.has_meta(&"grid_cell"):
			result.append(child.get_meta(&"grid_cell"))
	return result


func _attack_highlight_cells(prototype: PrototypeController) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for child in prototype.attack_highlights_root.get_children():
		if child.has_meta(&"grid_cell"):
			result.append(child.get_meta(&"grid_cell"))
	return result


func _highlight_node(prototype: PrototypeController, cell: Vector3i) -> MeshInstance3D:
	for child in prototype.highlights_root.get_children():
		if child.has_meta(&"grid_cell") and child.get_meta(&"grid_cell") == cell:
			return child as MeshInstance3D
	return null


func _assert_highlight_nodes(prototype: PrototypeController, context: String) -> void:
	for child in prototype.highlights_root.get_children():
		_expect(child.visible, "%s: highlight node should be visible" % context)
		_expect(child.is_visible_in_tree(), "%s: highlight node should be visible in the scene tree" % context)
		_expect(child.get_parent() == prototype.highlights_root, "%s: highlight should remain under MoveHighlights" % context)


func _finish(prototype: PrototypeController) -> void:
	prototype.queue_free()
	await process_frame
	if _failures.is_empty():
		print("MOVE_HIGHLIGHTS_TEST: PASS")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	print("MOVE_HIGHLIGHTS_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
