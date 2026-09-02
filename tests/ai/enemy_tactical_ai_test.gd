extends SceneTree

const EnemyTacticalAIScript = preload("res://scripts/core/ai/enemy_tactical_ai.gd")
const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")
const AlertStateScript = preload("res://scripts/core/encounter/alert_state.gd")
const PatrolRouteScript = preload("res://scripts/core/encounter/patrol_route.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_find_path_towards()
	_test_exploration_patrol_decision()
	_test_exploration_investigation_and_calm_down()
	_test_combat_attack_priority()
	_test_combat_move_towards_target()
	_test_combat_pass_on_no_ap()
	_finish()


func _test_find_path_towards() -> void:
	var grid := GridModelScript.new(Vector2i(10, 10))
	var start := Vector3i(1, 0, 1)
	var free_target := Vector3i(4, 0, 1)
	var direct_path := EnemyTacticalAIScript.find_path_towards(start, free_target, grid)
	_expect(direct_path.size() == 4, "ai: direct path should have 4 points")
	_expect(direct_path.back() == free_target, "ai: direct path should reach target")

	# Target occupied by player unit
	var occupied_target := Vector3i(5, 0, 1)
	grid.occupy(occupied_target, &"player_target")
	var path_to_occupied := EnemyTacticalAIScript.find_path_towards(start, occupied_target, grid)
	_expect(path_to_occupied.size() >= 2, "ai: path to occupied target should find neighbor")
	_expect(path_to_occupied.back() == Vector3i(4, 0, 1), "ai: path should end at neighbor (4, 0, 1)")


func _test_exploration_patrol_decision() -> void:
	var grid := GridModelScript.new(Vector2i(10, 10))
	var route := PatrolRouteScript.new()
	route.configure([Vector3i(2, 0, 2), Vector3i(2, 0, 3), Vector3i(2, 0, 4)], true)
	var alert := AlertStateScript.new()
	var enemy_cell := Vector3i(2, 0, 2)

	# Enemy at (2,0,2), route next is (2,0,3)
	var plan := EnemyTacticalAIScript.plan_exploration_step(
		enemy_cell, alert, route, {}, grid
	)
	_expect(plan[&"intent"] == EnemyTacticalAIScript.IntentType.PATROL_STEP, "ai: unaware enemy should follow patrol")
	_expect(plan[&"destination"] == Vector3i(2, 0, 3), "ai: patrol step destination should be (2, 0, 3)")


func _test_exploration_investigation_and_calm_down() -> void:
	var grid := GridModelScript.new(Vector2i(10, 10))
	var enemy_cell := Vector3i(2, 0, 2)
	var target_cell := Vector3i(2, 0, 5)
	grid.occupy(target_cell, &"player")

	var alert := AlertStateScript.new()
	alert.become_suspicious(target_cell)

	# Step towards target with move_range 4 (target neighbor is (2, 0, 4))
	var plan1 := EnemyTacticalAIScript.plan_exploration_step(
		enemy_cell, alert, null, {}, grid, 4
	)
	_expect(plan1[&"intent"] == EnemyTacticalAIScript.IntentType.INVESTIGATE_STEP, "ai: suspicious enemy should investigate")
	_expect(plan1[&"destination"] == Vector3i(2, 0, 4), "ai: full move_range should reach (2, 0, 4)")
	_expect(plan1[&"path"].size() == 3, "ai: path should have 3 nodes [start, step1, destination]")

	# Enemy reaches adjacent cell (2, 0, 4) where path cannot advance further
	var at_target_cell := Vector3i(2, 0, 4)
	var plan_at_target := EnemyTacticalAIScript.plan_exploration_step(
		at_target_cell, alert, null, {&"idle_ticks": 0}, grid
	)
	_expect(plan_at_target[&"intent"] == EnemyTacticalAIScript.IntentType.PASS, "ai: first idle tick should pass")
	_expect(plan_at_target[&"updated_investigation"][&"idle_ticks"] == 1, "ai: idle ticks should increment to 1")

	# Second idle tick -> calm down
	var plan_calm := EnemyTacticalAIScript.plan_exploration_step(
		at_target_cell, alert, null, {&"idle_ticks": 1}, grid
	)
	_expect(plan_calm[&"intent"] == EnemyTacticalAIScript.IntentType.CALM_DOWN, "ai: second idle tick should trigger CALM_DOWN")
	_expect(plan_calm[&"should_calm_down"] == true, "ai: should_calm_down should be true")


func _test_combat_attack_priority() -> void:
	var grid := GridModelScript.new(Vector2i(10, 10))
	var enemy_cell := Vector3i(3, 0, 3)
	var player_target := {
		&"id": &"player_alpha",
		&"cell": Vector3i(3, 0, 5),
		&"alive": true,
	}
	var can_attack_checker := func(from_c: Vector3i, to_c: Vector3i, range_val: int) -> bool:
		return absi(from_c.x - to_c.x) + absi(from_c.z - to_c.z) <= range_val

	# Enemy has AP and range to attack
	var plan := EnemyTacticalAIScript.plan_combat_action(
		enemy_cell, 2, 4, 5, 1, 4, 1, [player_target], grid, can_attack_checker
	)
	_expect(plan[&"intent"] == EnemyTacticalAIScript.IntentType.ATTACK, "ai combat: in range should prioritize attack")
	_expect(plan[&"target_id"] == &"player_alpha", "ai combat: target should be player_alpha")
	_expect(plan[&"ap_cost"] == 1, "ai combat: ap cost should match attack ap cost")


func _test_combat_move_towards_target() -> void:
	var grid := GridModelScript.new(Vector2i(20, 20))
	var enemy_cell := Vector3i(1, 0, 1)
	var player_target := {
		&"id": &"player_alpha",
		&"cell": Vector3i(10, 0, 1),
		&"alive": true,
	}
	grid.occupy(player_target[&"cell"], &"player_alpha")

	var can_attack_checker := func(from_c: Vector3i, to_c: Vector3i, range_val: int) -> bool:
		return absi(from_c.x - to_c.x) + absi(from_c.z - to_c.z) <= range_val

	# Enemy attack range is 2 (distance is 9), move range is 4
	var plan := EnemyTacticalAIScript.plan_combat_action(
		enemy_cell, 2, 4, 2, 1, 4, 1, [player_target], grid, can_attack_checker
	)
	_expect(plan[&"intent"] == EnemyTacticalAIScript.IntentType.MOVE, "ai combat: out of range should move closer")
	_expect(plan[&"destination"] == Vector3i(5, 0, 1), "ai combat: should advance 4 tiles towards target")
	_expect(plan[&"path"].size() == 5, "ai combat: path should have 5 nodes")


func _test_combat_pass_on_no_ap() -> void:
	var grid := GridModelScript.new(Vector2i(10, 10))
	var enemy_cell := Vector3i(1, 0, 1)
	var player_target := {
		&"id": &"player_alpha",
		&"cell": Vector3i(1, 0, 2),
		&"alive": true,
	}
	var can_attack_checker := func(_a, _b, _c) -> bool: return true

	# 0 AP
	var plan := EnemyTacticalAIScript.plan_combat_action(
		enemy_cell, 0, 4, 5, 1, 4, 1, [player_target], grid, can_attack_checker
	)
	_expect(plan[&"intent"] == EnemyTacticalAIScript.IntentType.PASS, "ai combat: 0 AP should pass")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("ENEMY_TACTICAL_AI_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ENEMY_TACTICAL_AI_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
