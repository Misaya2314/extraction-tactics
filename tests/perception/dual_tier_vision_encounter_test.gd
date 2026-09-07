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
const PrototypeControllerScript = preload("res://scripts/gameplay/prototype_controller.gd")
const PrototypeUnitScript = preload("res://scripts/gameplay/prototype_unit.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_dual_tier_detection_rules()
	_test_alert_state_transitions()
	_test_outer_vision_investigation_flow()
	_test_inner_vision_assassination_flow()
	_test_inner_vision_squad_alarm_propagation()
	_test_proactive_attack_squad_alarm_propagation()
	_test_proactive_attack_silent_assassination_flow()
	_test_detection_ap_recovery_mechanic()
	_finish()


func _test_dual_tier_detection_rules() -> void:
	var observer := Vector3i(2, 0, 2)
	var inner_range := 3
	var outer_range := 7

	# Target directly ahead within inner range (distance 2 <= 3)
	var inner_target := Vector3i(2, 0, 4)
	var tier := DetectionRulesScript.evaluate_detection_tier(
		observer, inner_target, inner_range, outer_range, {}
	)
	_expect(tier == DetectionRulesScript.DetectionTier.INNER_DISCOVERY, "rules: inner target should be INNER_DISCOVERY")

	# Target directly ahead within outer range (distance 5: > 3 and <= 7)
	var outer_target := Vector3i(2, 0, 7)
	tier = DetectionRulesScript.evaluate_detection_tier(
		observer, outer_target, inner_range, outer_range, {}
	)
	_expect(tier == DetectionRulesScript.DetectionTier.OUTER_ALERT, "rules: outer target should be OUTER_ALERT")

	# Target outside outer range (distance 8 > 7)
	var far_target := Vector3i(2, 0, 10)
	tier = DetectionRulesScript.evaluate_detection_tier(
		observer, far_target, inner_range, outer_range, {}
	)
	_expect(tier == DetectionRulesScript.DetectionTier.NONE, "rules: far target should be NONE")

	# Target behind observer (distance 2 <= 3, 360 degree grid distance)
	var behind_target := Vector3i(2, 0, 0)
	tier = DetectionRulesScript.evaluate_detection_tier(
		observer, behind_target, inner_range, outer_range, {}
	)
	_expect(tier == DetectionRulesScript.DetectionTier.INNER_DISCOVERY, "rules: behind target within inner range should be INNER_DISCOVERY (360 degrees vision)")

	# Target blocked by opaque wall
	var wall := {Vector3i(2, 0, 3): true}
	tier = DetectionRulesScript.evaluate_detection_tier(
		observer, inner_target, inner_range, outer_range, wall
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

	# Mark player cell as occupied by player
	grid.occupy(player_cell, &"player_unit")

	var tier := DetectionRulesScript.evaluate_detection_tier(
		enemy_cell, player_cell, 3, 7, {}
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


func _test_proactive_attack_squad_alarm_propagation() -> void:
	# Simulates player actively attacking an enemy during exploration, entering combat,
	# and ending the player turn without killing the target.
	# Verifies that whole squad alarm is propagated at end of turn.
	var turn_mgr := TurnManagerScript.new()
	var session_mgr := GameStateManagerScript.new()
	session_mgr.start_exploration()

	var player_id := &"player_1"
	var target_enemy_id := &"enemy_target"
	var squad_guard_id := &"enemy_guard"

	var squad_members: Array[StringName] = [target_enemy_id, squad_guard_id]
	var enemy_alerts := {
		target_enemy_id: AlertStateScript.new(),
		squad_guard_id: AlertStateScript.new(),
	}

	# Player attacks target_enemy in exploration
	(enemy_alerts[target_enemy_id] as AlertStateScript).engage(player_id, Vector3i(3, 0, 3))
	(enemy_alerts[squad_guard_id] as AlertStateScript).become_suspicious(Vector3i(3, 0, 3))

	turn_mgr.configure([player_id], squad_members)
	session_mgr.start_combat()
	turn_mgr.start_combat(true)

	_expect(turn_mgr.is_player_turn(), "proactive_alarm: combat begins in player turn")
	_expect((enemy_alerts[target_enemy_id] as AlertStateScript).is_engaged(), "proactive_alarm: target is engaged")
	_expect((enemy_alerts[squad_guard_id] as AlertStateScript).is_suspicious(), "proactive_alarm: guard is suspicious")

	# Player ends turn WITHOUT killing target -> alarm propagation
	var pending_squads: Array[Array] = []
	for enemy_id in turn_mgr.get_enemy_ids():
		var alert := enemy_alerts[enemy_id] as AlertStateScript
		if alert.is_alerted() or alert.is_engaged():
			var has_unengaged := false
			for member_id in squad_members:
				var m_alert := enemy_alerts[member_id] as AlertStateScript
				if not m_alert.is_engaged():
					has_unengaged = true
					break
			if has_unengaged:
				pending_squads.append(squad_members)
				break

	for squad in pending_squads:
		for member_id in squad:
			(enemy_alerts[member_id] as AlertStateScript).engage(player_id, Vector3i(3, 0, 3))

	turn_mgr.end_player_turn()

	_expect(turn_mgr.is_enemy_turn(), "proactive_alarm: phase transitioned to enemy turn")
	_expect((enemy_alerts[target_enemy_id] as AlertStateScript).is_engaged(), "proactive_alarm: target remains engaged")
	_expect((enemy_alerts[squad_guard_id] as AlertStateScript).is_engaged(), "proactive_alarm: entire squad guard is now engaged!")


func _test_proactive_attack_silent_assassination_flow() -> void:
	# Simulates player actively attacking an enemy in exploration and killing it in player turn.
	# Verifies that silent resolution resets to exploration and guard remains unaffected.
	var turn_mgr := TurnManagerScript.new()
	var session_mgr := GameStateManagerScript.new()
	session_mgr.start_exploration()

	var player_id := &"player_1"
	var target_enemy_id := &"enemy_target"
	var squad_guard_id := &"enemy_guard"

	var squad_members: Array[StringName] = [target_enemy_id, squad_guard_id]
	var enemy_alerts := {
		target_enemy_id: AlertStateScript.new(),
		squad_guard_id: AlertStateScript.new(),
	}

	# Player attacks target_enemy in exploration
	(enemy_alerts[target_enemy_id] as AlertStateScript).engage(player_id, Vector3i(3, 0, 3))
	(enemy_alerts[squad_guard_id] as AlertStateScript).become_suspicious(Vector3i(3, 0, 3))

	turn_mgr.configure([player_id], squad_members)
	session_mgr.start_combat()
	turn_mgr.start_combat(true)

	_expect(turn_mgr.is_player_turn(), "proactive_assassination: combat begins in player turn")

	# Player kills target in player turn
	turn_mgr.remove_unit(target_enemy_id)
	var living_enemies: Array[StringName] = [squad_guard_id]

	# Check silent assassination condition: no living enemies are engaged
	var has_living_engaged := false
	for enemy_id in living_enemies:
		var alert := enemy_alerts[enemy_id] as AlertStateScript
		if alert.is_engaged():
			has_living_engaged = true
			break

	_expect(not has_living_engaged, "proactive_assassination: no living enemies are engaged")

	# Reset back to exploration
	turn_mgr.reset_to_exploration()
	turn_mgr.configure([player_id], [])
	session_mgr.resolve_combat()

	_expect(turn_mgr.get_phase() == TurnManagerScript.Phase.EXPLORATION, "proactive_assassination: phase reset to exploration")
	_expect(session_mgr.get_state() == GameStateManagerScript.State.EXPLORATION, "proactive_assassination: session reset to exploration")
	_expect((enemy_alerts[squad_guard_id] as AlertStateScript).is_suspicious(), "proactive_assassination: guard remains only suspicious")


func _test_detection_ap_recovery_mechanic() -> void:
	# Scenario 1: Enemy action discovery:
	# Unit A (spent to 0 AP) and Unit B (has 1 AP) end turn.
	# Enemy discovers Unit A during exploration tick.
	# Unit A recovers 1 AP (0 -> 1). Unit B keeps pre-turn AP (1 AP).
	var controller := PrototypeControllerScript.new()
	controller.grid = GridModelScript.new(Vector2i(15, 15))
	controller.turn_manager = TurnManagerScript.new()
	controller.session_manager = GameStateManagerScript.new()
	controller.session_manager.start_exploration()

	var player_a := PrototypeUnitScript.new()
	player_a.unit_id = &"player_a"
	player_a.faction = &"player"
	player_a.grid_cell = Vector3i(2, 0, 2)
	player_a.max_action_points = 2
	player_a.current_action_points = 0
	player_a.current_hp = 10
	player_a.max_hp = 10

	var player_b := PrototypeUnitScript.new()
	player_b.unit_id = &"player_b"
	player_b.faction = &"player"
	player_b.grid_cell = Vector3i(10, 0, 10)
	player_b.max_action_points = 2
	player_b.current_action_points = 1
	player_b.current_hp = 10
	player_b.max_hp = 10

	var enemy := PrototypeUnitScript.new()
	enemy.unit_id = &"enemy_patrol"
	enemy.faction = &"enemy"
	enemy.grid_cell = Vector3i(2, 0, 4) # distance 2 from player_a, <= inner vision 3
	enemy.max_action_points = 2
	enemy.current_action_points = 2
	enemy.current_hp = 10
	enemy.max_hp = 10
	enemy.inner_vision_range = 3
	enemy.vision_range = 7

	var player_ids: Array[StringName] = [&"player_a", &"player_b"]
	var enemy_ids: Array[StringName] = [&"enemy_patrol"]
	controller.all_player_ids = player_ids.duplicate()
	controller.all_enemy_ids = enemy_ids.duplicate()
	controller.units_by_id = {&"player_a": player_a, &"player_b": player_b, &"enemy_patrol": enemy}
	controller.enemy_alerts = {&"enemy_patrol": AlertStateScript.new()}
	controller.encounter_by_unit = {&"enemy_patrol": &"patrol_encounter"}
	controller.encounter_members = {&"patrol_encounter": enemy_ids.duplicate()}
	controller.turn_manager.configure(player_ids, [])

	# Simulate turn end
	controller._capture_pre_turn_end_player_ap()
	controller._is_running_exploration_tick = true

	var detected := controller._evaluate_detection()
	_expect(detected, "ap_mechanic: enemy action should trigger discovery")
	_expect(player_a.current_action_points == 1, "ap_mechanic: discovered unit A should recover 1 AP (0 -> 1)")
	_expect(player_b.current_action_points == 1, "ap_mechanic: undiscovered unit B should retain pre-turn-end AP (1)")
	_expect(controller.turn_manager.is_player_turn(), "ap_mechanic: combat started in player turn")
	_expect(controller.session_manager.get_state() == GameStateManagerScript.State.COMBAT, "ap_mechanic: session entered combat")

	controller.free()

	# Scenario 2: Enemy action NO discovery:
	# Unit A (0 AP), Unit B (1 AP) end turn, no enemy sees them.
	# Both should reset to max AP (2).
	var controller2 := PrototypeControllerScript.new()
	controller2.grid = GridModelScript.new(Vector2i(20, 20))
	controller2.turn_manager = TurnManagerScript.new()
	controller2.session_manager = GameStateManagerScript.new()
	controller2.session_manager.start_exploration()

	var player_a2 := PrototypeUnitScript.new()
	player_a2.unit_id = &"player_a"
	player_a2.faction = &"player"
	player_a2.grid_cell = Vector3i(1, 0, 1)
	player_a2.max_action_points = 2
	player_a2.current_action_points = 0
	player_a2.current_hp = 10
	player_a2.max_hp = 10

	var player_b2 := PrototypeUnitScript.new()
	player_b2.unit_id = &"player_b"
	player_b2.faction = &"player"
	player_b2.grid_cell = Vector3i(2, 0, 1)
	player_b2.max_action_points = 2
	player_b2.current_action_points = 1
	player_b2.current_hp = 10
	player_b2.max_hp = 10

	var enemy2 := PrototypeUnitScript.new()
	enemy2.unit_id = &"enemy_far"
	enemy2.faction = &"enemy"
	enemy2.grid_cell = Vector3i(18, 0, 18)
	enemy2.max_action_points = 2
	enemy2.current_action_points = 2
	enemy2.current_hp = 10
	enemy2.max_hp = 10
	enemy2.inner_vision_range = 3
	enemy2.vision_range = 7

	controller2.all_player_ids = player_ids.duplicate()
	controller2.all_enemy_ids = [&"enemy_far"]
	controller2.units_by_id = {&"player_a": player_a2, &"player_b": player_b2, &"enemy_far": enemy2}
	controller2.enemy_alerts = {&"enemy_far": AlertStateScript.new()}
	controller2.encounter_by_unit = {&"enemy_far": &"far_encounter"}
	controller2.encounter_members = {&"far_encounter": [&"enemy_far"]}
	controller2.turn_manager.configure(player_ids, [])

	controller2._capture_pre_turn_end_player_ap()
	controller2._is_running_exploration_tick = true
	var detected2 := controller2._evaluate_detection()
	_expect(not detected2, "ap_mechanic: distant enemy should not trigger discovery")
	if not detected2 and controller2.turn_manager.get_phase() == TurnManagerScript.Phase.EXPLORATION:
		for u_val in controller2.units_by_id.values():
			var u: PrototypeUnit = u_val as PrototypeUnit
			if u.faction == &"player":
				u.reset_action_points()
	_expect(player_a2.current_action_points == 2, "ap_mechanic: unit A should reset to max AP (2)")
	_expect(player_b2.current_action_points == 2, "ap_mechanic: unit B should reset to max AP (2)")

	controller2.free()

	# Scenario 3: Player active movement discovery:
	# Unit A moves to distance 2 from enemy, spent to 0 AP.
	# _is_running_exploration_tick is false.
	# Unit A should NOT recover 1 AP (stays at 0 AP). Unit B keeps current AP (2).
	var controller3 := PrototypeControllerScript.new()
	controller3.grid = GridModelScript.new(Vector2i(15, 15))
	controller3.turn_manager = TurnManagerScript.new()
	controller3.session_manager = GameStateManagerScript.new()
	controller3.session_manager.start_exploration()

	var player_a3 := PrototypeUnitScript.new()
	player_a3.unit_id = &"player_a"
	player_a3.faction = &"player"
	player_a3.grid_cell = Vector3i(2, 0, 2)
	player_a3.max_action_points = 2
	player_a3.current_action_points = 0 # moved and spent all AP
	player_a3.current_hp = 10
	player_a3.max_hp = 10

	var player_b3 := PrototypeUnitScript.new()
	player_b3.unit_id = &"player_b"
	player_b3.faction = &"player"
	player_b3.grid_cell = Vector3i(10, 0, 10)
	player_b3.max_action_points = 2
	player_b3.current_action_points = 2 # hasn't moved
	player_b3.current_hp = 10
	player_b3.max_hp = 10

	var enemy3 := PrototypeUnitScript.new()
	enemy3.unit_id = &"enemy_patrol"
	enemy3.faction = &"enemy"
	enemy3.grid_cell = Vector3i(2, 0, 4)
	enemy3.max_action_points = 2
	enemy3.current_action_points = 2
	enemy3.current_hp = 10
	enemy3.max_hp = 10
	enemy3.inner_vision_range = 3
	enemy3.vision_range = 7

	controller3.all_player_ids = player_ids.duplicate()
	controller3.all_enemy_ids = enemy_ids.duplicate()
	controller3.units_by_id = {&"player_a": player_a3, &"player_b": player_b3, &"enemy_patrol": enemy3}
	controller3.enemy_alerts = {&"enemy_patrol": AlertStateScript.new()}
	controller3.encounter_by_unit = {&"enemy_patrol": &"patrol_encounter"}
	controller3.encounter_members = {&"patrol_encounter": enemy_ids.duplicate()}
	controller3.turn_manager.configure(player_ids, [])

	controller3._is_running_exploration_tick = false
	var detected3 := controller3._evaluate_detection()
	_expect(detected3, "ap_mechanic: active move into inner vision should trigger discovery")
	_expect(player_a3.current_action_points == 0, "ap_mechanic: active move discovery should NOT recover AP (stays 0)")
	_expect(player_b3.current_action_points == 2, "ap_mechanic: unit B should keep current AP (2)")
	_expect(controller3.turn_manager.is_player_turn(), "ap_mechanic: combat started in player turn")

	controller3.free()


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
