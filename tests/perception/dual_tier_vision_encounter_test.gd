extends SceneTree

const DetectionRulesScript = preload("res://scripts/core/perception/detection_rules.gd")
const AlertStateScript = preload("res://scripts/core/encounter/alert_state.gd")
const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")
const UnitArchetypeScript = preload("res://scripts/core/units/unit_archetype.gd")
const UnitRuntimeStateScript = preload("res://scripts/core/units/unit_runtime_state.gd")
const WeaponDefinitionScript = preload("res://scripts/core/combat/weapon_definition.gd")
const WeaponInstanceScript = preload("res://scripts/core/combat/weapon_instance.gd")
const TurnManagerScript = preload("res://scripts/core/turn/turn_manager.gd")
const GameStateManagerScript = preload("res://scripts/core/session/game_state_manager.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_dual_tier_detection_rules()
	_test_alert_state_transitions()
	_test_outer_vision_investigation_flow()
	_test_inner_vision_assassination_flow()
	_test_inner_vision_squad_alarm_propagation()
	_finish()


func _test_dual_tier_detection_rules() -> void:
	var observer := Vector3i(2, 0, 2)
	var facing := Vector2i(0, 1) # Facing DOWN (increasing Z)
	var inner_range := 3
	var outer_range := 7

	# Target directly ahead within inner cone (distance 2 <= 3)
	var inner_target := Vector3i(2, 0, 4)
	var tier := DetectionRulesScript.evaluate_detection_tier(
		observer, inner_target, facing, inner_range, outer_range, {}
	)
	_expect(tier == DetectionRulesScript.DetectionTier.INNER_DISCOVERY, "rules: inner target should be INNER_DISCOVERY")

	# Target directly ahead within outer cone (distance 5: > 3 and <= 7)
	var outer_target := Vector3i(2, 0, 7)
	tier = DetectionRulesScript.evaluate_detection_tier(
		observer, outer_target, facing, inner_range, outer_range, {}
	)
	_expect(tier == DetectionRulesScript.DetectionTier.OUTER_ALERT, "rules: outer target should be OUTER_ALERT")

	# Target outside outer range (distance 8 > 7)
	var far_target := Vector3i(2, 0, 10)
	tier = DetectionRulesScript.evaluate_detection_tier(
		observer, far_target, facing, inner_range, outer_range, {}
	)
	_expect(tier == DetectionRulesScript.DetectionTier.NONE, "rules: far target should be NONE")

	# Target behind observer (facing DOWN, target at Z=0)
	var behind_target := Vector3i(2, 0, 0)
	tier = DetectionRulesScript.evaluate_detection_tier(
		observer, behind_target, facing, inner_range, outer_range, {}
	)
	_expect(tier == DetectionRulesScript.DetectionTier.NONE, "rules: behind target should be NONE")

	# Target blocked by opaque wall
	var wall := {Vector3i(2, 0, 3): true}
	tier = DetectionRulesScript.evaluate_detection_tier(
		observer, inner_target, facing, inner_range, outer_range, wall
	)
	_expect(tier == DetectionRulesScript.DetectionTier.NONE, "rules: blocked inner target should be NONE")


func _test_alert_state_transitions() -> void:
	var state = AlertStateScript.new()
	_expect(state.is_unaware(), "state: initial should be UNAWARE")

	# Unaware -> Suspicious
	_expect(state.become_suspicious(Vector3i(5, 0, 5)), "state: unaware becomes suspicious")
	_expect(state.is_suspicious(), "state: should be suspicious")
	_expect(state.get_last_known_cell() == Vector3i(5, 0, 5), "state: last known cell should match")

	# Suspicious -> Alerted (inner discovery)
	_expect(state.become_alerted(&"player_1", Vector3i(4, 0, 4)), "state: suspicious becomes alerted")
	_expect(state.is_alerted(), "state: should be alerted")
	_expect(state.get_target_id() == &"player_1", "state: target id should be recorded")

	# Alerted cannot be downgraded to suspicious by become_suspicious
	_expect(not state.become_suspicious(Vector3i(6, 0, 6)), "state: alerted ignores become_suspicious")
	_expect(state.is_alerted(), "state: should still be alerted")

	# Alerted -> Engaged (squad alarm)
	_expect(state.engage(&"player_1", Vector3i(4, 0, 4)), "state: alerted becomes engaged")
	_expect(state.is_engaged(), "state: should be engaged")

	# Engaged -> Suspicious -> Unaware (calm down)
	_expect(state.calm_down(), "state: engaged calms down to suspicious")
	_expect(state.is_suspicious(), "state: should be suspicious after first calm down")
	_expect(state.calm_down(), "state: suspicious calms down to unaware")
	_expect(state.is_unaware(), "state: should be unaware after second calm down")
	_expect(not state.calm_down(), "state: unaware cannot calm down further")


func _test_outer_vision_investigation_flow() -> void:
	# Simulates controller exploration tick investigation with occupied target cell
	var grid := GridModelScript.new(Vector2i(10, 10))
	var enemy_cell := Vector3i(2, 0, 2)
	var player_cell := Vector3i(2, 0, 7) # Outer vision range (distance 5)
	var facing := Vector2i(0, 1)

	# Mark player cell as occupied by player
	grid.occupy(player_cell, &"player_unit")

	var tier := DetectionRulesScript.evaluate_detection_tier(
		enemy_cell, player_cell, facing, 3, 7, {}
	)
	_expect(tier == DetectionRulesScript.DetectionTier.OUTER_ALERT, "investigation: outer alert triggered")

	var alert := AlertStateScript.new()
	alert.become_suspicious(player_cell)
	_expect(alert.is_suspicious(), "investigation: enemy is suspicious")
	_expect(alert.get_last_known_cell() == player_cell, "investigation: target is player cell")

	# Testing pathfinding towards occupied player cell using neighbor search
	var path := _find_path_towards_helper(grid, enemy_cell, alert.get_last_known_cell())
	_expect(path.size() >= 2, "investigation: path towards occupied target should exist via neighbor")
	var next_step := path[1]
	_expect(next_step == Vector3i(2, 0, 3), "investigation: step towards target should advance towards (2, 0, 3)")

	# Simulated calm down when reaching target and nothing found
	alert.calm_down()
	_expect(alert.is_unaware(), "investigation: should calm down to unaware when clear")


func _find_path_towards_helper(grid: GridModel, start_cell: Vector3i, target_cell: Vector3i) -> Array[Vector3i]:
	if start_cell == target_cell:
		return [start_cell]
	if grid.is_walkable(target_cell) and not grid.is_occupied(target_cell):
		var direct := grid.find_path(start_cell, target_cell)
		if not direct.is_empty():
			return direct
	var best_neighbor := grid.invalid_cell()
	var best_dist := INF
	for neighbor in grid.get_neighbors(target_cell):
		if grid.is_walkable(neighbor) and not grid.is_occupied(neighbor):
			var dist := _manhattan_dist(start_cell, neighbor)
			if dist < best_dist:
				best_dist = dist
				best_neighbor = neighbor
	if best_neighbor != grid.invalid_cell():
		var neighbor_path := grid.find_path(start_cell, best_neighbor)
		if not neighbor_path.is_empty():
			return neighbor_path
	return []


func _manhattan_dist(a: Vector3i, b: Vector3i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z)


func _test_inner_vision_assassination_flow() -> void:
	# Simulates discovery & silent assassination during player turn
	var turn_mgr := TurnManagerScript.new()
	var session_mgr := GameStateManagerScript.new()
	session_mgr.start_exploration()

	var player_id := &"player_1"
	var scout_enemy_id := &"enemy_scout"
	var guard_enemy_id := &"enemy_guard"

	var scout_alert := AlertStateScript.new()
	var guard_alert := AlertStateScript.new()

	# Inner discovery triggers on scout
	scout_alert.become_alerted(player_id, Vector3i(3, 0, 3))
	var discovering_ids: Array[StringName] = [scout_enemy_id]

	# Combat enters player turn
	turn_mgr.configure([player_id], [scout_enemy_id, guard_enemy_id])
	session_mgr.start_combat()
	turn_mgr.start_combat(true)

	_expect(turn_mgr.is_player_turn(), "assassination: combat should be in player turn")
	_expect(scout_alert.is_alerted(), "assassination: scout should be alerted")
	_expect(guard_alert.is_unaware(), "assassination: guard should still be unaware")

	# Player kills the scout during player turn
	discovering_ids.erase(scout_enemy_id)
	turn_mgr.remove_unit(scout_enemy_id)

	# Check silent resolution: discovering_ids is empty and no engaged enemies
	var has_engaged := scout_alert.is_engaged() or guard_alert.is_engaged()
	_expect(not has_engaged, "assassination: no enemies are engaged")
	_expect(discovering_ids.is_empty(), "assassination: all discoverers eliminated")

	# Reset back to exploration without triggering guard
	turn_mgr.reset_to_exploration()
	turn_mgr.configure([player_id], [])
	session_mgr.resolve_combat()

	_expect(turn_mgr.get_phase() == TurnManagerScript.Phase.EXPLORATION, "assassination: phase reset to exploration")
	_expect(session_mgr.get_state() == GameStateManagerScript.State.EXPLORATION, "assassination: session reset to exploration")
	_expect(guard_alert.is_unaware(), "assassination: squad guard remained completely unalerted")


func _test_inner_vision_squad_alarm_propagation() -> void:
	# Simulates failing to kill discoverer during player turn -> whole squad alarm
	var turn_mgr := TurnManagerScript.new()
	var session_mgr := GameStateManagerScript.new()
	session_mgr.start_exploration()

	var player_id := &"player_1"
	var scout_enemy_id := &"enemy_scout"
	var guard_enemy_id := &"enemy_guard"

	var squad_members: Array[StringName] = [scout_enemy_id, guard_enemy_id]
	var enemy_alerts := {
		scout_enemy_id: AlertStateScript.new(),
		guard_enemy_id: AlertStateScript.new(),
	}

	# Inner discovery triggers on scout
	(enemy_alerts[scout_enemy_id] as AlertStateScript).become_alerted(player_id, Vector3i(3, 0, 3))
	var discovering_ids: Array[StringName] = [scout_enemy_id]

	# Combat enters player turn
	turn_mgr.configure([player_id], squad_members)
	session_mgr.start_combat()
	turn_mgr.start_combat(true)

	_expect(turn_mgr.is_player_turn(), "squad_alarm: combat begins in player turn")
	_expect((enemy_alerts[scout_enemy_id] as AlertStateScript).is_alerted(), "squad_alarm: scout is alerted")
	_expect((enemy_alerts[guard_enemy_id] as AlertStateScript).is_unaware(), "squad_alarm: guard is initially unaware")

	# Player ends turn WITHOUT killing scout
	# Alarm propagation logic:
	for enemy_id in discovering_ids:
		var alert := enemy_alerts[enemy_id] as AlertStateScript
		if alert.is_alerted():
			alert.engage(player_id, alert.get_last_known_cell())
			for member_id in squad_members:
				(enemy_alerts[member_id] as AlertStateScript).engage(player_id, alert.get_last_known_cell())
	discovering_ids.clear()

	turn_mgr.end_player_turn()

	_expect(turn_mgr.is_enemy_turn(), "squad_alarm: phase transitioned to enemy turn")
	_expect((enemy_alerts[scout_enemy_id] as AlertStateScript).is_engaged(), "squad_alarm: scout is now engaged")
	_expect((enemy_alerts[guard_enemy_id] as AlertStateScript).is_engaged(), "squad_alarm: entire squad guard is now engaged!")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("DUAL_TIER_VISION_ENCOUNTER_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("DUAL_TIER_VISION_ENCOUNTER_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
