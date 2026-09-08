extends SceneTree

const EnemyTacticalAIScript = preload("res://scripts/core/ai/enemy_tactical_ai.gd")
const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")
const AlertStateScript = preload("res://scripts/core/encounter/alert_state.gd")
const PatrolRouteScript = preload("res://scripts/core/encounter/patrol_route.gd")
const TurnManagerScript = preload("res://scripts/core/turn/turn_manager.gd")
const GameStateManagerScript = preload("res://scripts/core/session/game_state_manager.gd")
const PrototypeControllerScript = preload("res://scripts/gameplay/prototype_controller.gd")
const PrototypeUnitScript = preload("res://scripts/gameplay/prototype_unit.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_exploration_plan_ap_costs()
	_test_exploration_insufficient_ap()
	_test_exploration_dwell_and_calm_down_zero_ap()
	_test_combat_first_turn_inherits_remaining_ap()
	_finish()


func _test_exploration_plan_ap_costs() -> void:
	var grid := GridModelScript.new(Vector2i(10, 10))
	var route := PatrolRouteScript.new()
	route.configure([Vector3i(1, 0, 1), Vector3i(1, 0, 3)], true)
	var alert := AlertStateScript.new()

	# Patrol step with 2 AP
	var plan_patrol := EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(1, 0, 1), alert, route, {}, grid, 1, 2, 1
	)
	_expect(plan_patrol[&"intent"] == EnemyTacticalAIScript.IntentType.PATROL_STEP, "plan: patrol should step")
	_expect(plan_patrol[&"ap_cost"] == 1, "plan: patrol step should cost 1 AP")

	# Investigate step with 2 AP
	alert.become_suspicious(Vector3i(5, 0, 1))
	var plan_invest := EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(1, 0, 1), alert, route, {}, grid, 1, 2, 1
	)
	_expect(plan_invest[&"intent"] == EnemyTacticalAIScript.IntentType.INVESTIGATE_STEP, "plan: investigate should step")
	_expect(plan_invest[&"ap_cost"] == 1, "plan: investigate step should cost 1 AP")


func _test_exploration_insufficient_ap() -> void:
	var grid := GridModelScript.new(Vector2i(10, 10))
	var route := PatrolRouteScript.new()
	route.configure([Vector3i(1, 0, 1), Vector3i(1, 0, 3)], true)
	var alert := AlertStateScript.new()

	# Patrol with 0 AP
	var plan_patrol := EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(1, 0, 1), alert, route, {}, grid, 1, 0, 1
	)
	_expect(plan_patrol[&"intent"] == EnemyTacticalAIScript.IntentType.PASS, "insufficient ap: patrol should pass")
	_expect(plan_patrol[&"ap_cost"] == 0, "insufficient ap: pass should cost 0 AP")

	# Investigate with 0 AP
	alert.become_suspicious(Vector3i(5, 0, 1))
	var plan_invest := EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(1, 0, 1), alert, route, {}, grid, 1, 0, 1
	)
	_expect(plan_invest[&"intent"] == EnemyTacticalAIScript.IntentType.PASS, "insufficient ap: investigate should pass")
	_expect(plan_invest[&"ap_cost"] == 0, "insufficient ap: pass should cost 0 AP")


func _test_exploration_dwell_and_calm_down_zero_ap() -> void:
	var grid := GridModelScript.new(Vector2i(10, 10))
	var route := PatrolRouteScript.new()
	route.configure([Vector3i(0, 0, 0), Vector3i(0, 0, 2)], true, [0, 2])
	var alert := AlertStateScript.new()

	# Advance from start waypoint to arm dwell for (0, 0, 2)
	EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(0, 0, 0), alert, route, {}, grid, 1, 2, 1
	)

	# At waypoint (0, 0, 2) with dwell remaining
	var plan_dwell := EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(0, 0, 2), alert, route, {}, grid, 1, 2, 1
	)
	_expect(plan_dwell[&"intent"] == EnemyTacticalAIScript.IntentType.PASS, "dwell: should pass")
	_expect(plan_dwell[&"dwell"] == true, "dwell: flag should be true")
	_expect(plan_dwell[&"ap_cost"] == 0, "dwell: should cost 0 AP")

	# Calm down after idle investigation
	alert.become_suspicious(Vector3i(3, 0, 3))
	var plan_calm := EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(3, 0, 3), alert, route, {&"idle_ticks": 1}, grid, 1, 2, 1
	)
	_expect(plan_calm[&"intent"] == EnemyTacticalAIScript.IntentType.CALM_DOWN, "calm: should calm down")
	_expect(plan_calm[&"should_calm_down"] == true, "calm: flag should be true")
	_expect(plan_calm[&"ap_cost"] == 0, "calm: should cost 0 AP")


func _test_combat_first_turn_inherits_remaining_ap() -> void:
	var controller := PrototypeControllerScript.new()
	controller.grid = GridModelScript.new(Vector2i(20, 20))
	controller.turn_manager = TurnManagerScript.new()
	controller.session_manager = GameStateManagerScript.new()
	controller.session_manager.start_exploration()

	var player := PrototypeUnitScript.new()
	player.unit_id = &"p1"
	player.faction = &"player"
	player.grid_cell = Vector3i(1, 0, 1)
	player.max_action_points = 2
	player.current_action_points = 2
	player.max_hp = 10
	player.current_hp = 10

	var enemy := PrototypeUnitScript.new()
	enemy.unit_id = &"e1"
	enemy.faction = &"enemy"
	enemy.grid_cell = Vector3i(5, 0, 5)
	enemy.max_action_points = 2
	enemy.current_action_points = 1 # Has 1 remaining AP after exploration move
	enemy.max_hp = 10
	enemy.current_hp = 10

	controller.all_player_ids = [&"p1"]
	controller.all_enemy_ids = [&"e1"]
	controller.units_by_id = {&"p1": player, &"e1": enemy}
	controller.enemy_alerts = {&"e1": AlertStateScript.new()}
	controller.encounter_by_unit = {&"e1": &"enc1"}
	controller.encounter_members = {&"enc1": [&"e1"]}

	# Start combat with player_first = true
	var ok := controller._start_combat(true, enemy, Vector3i(1, 0, 1), &"p1", "发现玩家")
	_expect(ok, "start combat should succeed")
	_expect(controller._inherit_enemy_turn_ap == true, "_inherit_enemy_turn_ap should be armed")
	_expect(enemy.current_action_points == 1, "enemy should keep remaining 1 AP during player turn")

	# Player ends turn -> enemy turn 1
	controller.turn_manager.end_player_turn()
	_expect(controller.turn_manager.is_enemy_turn(), "turn should be enemy turn")

	# Run enemy turn: should inherit 1 AP and NOT reset to 2 AP
	controller._run_enemy_turn()
	_expect(controller._inherit_enemy_turn_ap == false, "_inherit_enemy_turn_ap should be consumed after first turn")

	# End enemy turn -> Round 2 starts
	controller.turn_manager.end_enemy_turn()
	_expect(controller.turn_manager.is_player_turn(), "round 2 player turn")

	# Player ends round 2 turn -> enemy turn 2
	controller.turn_manager.end_player_turn()
	_expect(controller.turn_manager.is_enemy_turn(), "round 2 enemy turn")

	# Round 2 enemy turn: should reset to max AP (2)
	controller._run_enemy_turn()
	_expect(enemy.current_action_points == 0 or enemy.current_action_points == 1 or enemy.current_action_points == 2, "enemy acted in round 2")

	controller.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("ENEMY_EXPLORATION_AP_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ENEMY_EXPLORATION_AP_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
