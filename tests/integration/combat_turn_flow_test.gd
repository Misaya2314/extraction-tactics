extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main/prototype_main.tscn")
const GameStateManagerScript = preload("res://scripts/core/session/game_state_manager.gd")

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var prototype := MAIN_SCENE.instantiate() as PrototypeController
	get_root().add_child(prototype)
	await process_frame

	var player := prototype._unit_by_name(&"PlayerAlpha")
	var scout := prototype._unit_by_name(&"EnemyScout")
	_expect(is_instance_valid(player) and is_instance_valid(scout), "setup: expected combatants should spawn")
	if not is_instance_valid(player) or not is_instance_valid(scout):
		_finish()
		return

	_move_immediately(prototype, player, Vector3i(5, 0, 1))
	player.reset_action_points()
	await prototype._attack_with_unit(player, scout)
	_expect(prototype.turn_manager.is_player_turn(), "combat: proactive attack should enter player turn")
	var player_hp_before := player.current_hp
	await prototype._on_end_turn_pressed()
	_expect(prototype.turn_manager.is_player_turn(), "turn: enemy phase should complete and return control")
	_expect(player.current_hp < player_hp_before, "enemy AI: enemy should damage a reachable player")
	_expect(player.current_action_points == player.max_action_points, "turn: player AP should reset after enemy phase")

	for enemy_id in prototype.turn_manager.get_enemy_ids().duplicate():
		var enemy := prototype._unit_by_id(enemy_id)
		if is_instance_valid(enemy):
			enemy.take_damage(enemy.current_hp)
	_expect(prototype.turn_manager.get_phase() == TurnManager.Phase.EXPLORATION, "victory: resolved encounter should return to exploration")
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.EXPLORATION, "victory: session should remain active after encounter")
	_expect(not prototype.session_manager.is_terminal(), "victory: encounter resolution is not a session result")
	_expect(not prototype.end_turn_button.disabled, "victory: exploration input should remain available")
	_expect(prototype.active_encounter_id == &"", "victory: resolved encounter should clear the active group")
	_expect(prototype._unit_by_name(&"EnemyGuard") != null and not prototype.turn_manager.get_enemy_ids().has(prototype._unit_by_name(&"EnemyGuard").unit_id), "encounter: a different group should remain inactive")
	var guard := prototype._unit_by_name(&"EnemyGuard")
	_expect(prototype._start_combat(true, guard, player.grid_cell, player.unit_id), "encounter: second authored group should start independently")
	_expect(prototype.active_encounter_id == &"outpost", "encounter: second group should carry its own encounter ID")
	_expect(prototype.turn_manager.get_enemy_ids().size() == 3, "encounter: second group should load exactly three enemies")
	for enemy_id in prototype.turn_manager.get_enemy_ids().duplicate():
		var target := prototype._unit_by_id(enemy_id)
		if is_instance_valid(target):
			target.take_damage(target.current_hp)
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.EXPLORATION, "encounter: second group should also return to exploration")
	_expect(prototype.turn_manager.reset_to_exploration() == false, "victory: duplicate exploration reset should be stable")

	prototype.queue_free()
	await process_frame
	_finish()


func _move_immediately(prototype: PrototypeController, unit: PrototypeUnit, cell: Vector3i) -> void:
	prototype.grid.vacate(unit.grid_cell, unit.unit_id)
	prototype.grid.occupy(cell, unit.unit_id)
	unit.grid_cell = cell
	unit.global_position = prototype.grid.cell_to_world(cell)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("COMBAT_TURN_FLOW_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("COMBAT_TURN_FLOW_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
