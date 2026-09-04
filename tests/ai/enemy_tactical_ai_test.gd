extends SceneTree

const EnemyTacticalAIScript = preload("res://scripts/core/ai/enemy_tactical_ai.gd")
const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")
const AlertStateScript = preload("res://scripts/core/encounter/alert_state.gd")
const PatrolRouteScript = preload("res://scripts/core/encounter/patrol_route.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_find_path_towards()
	_test_exploration_patrol_decision()
	_test_sparse_waypoint_multi_step()
	_test_patrol_dwell_wait()
	_test_patrol_unreachable_waypoint_skip()
	_test_return_to_patrol_after_calm_down()
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


func _test_sparse_waypoint_multi_step() -> void:
	var grid := GridModelScript.new(Vector2i(10, 10))
	# Sparse route: only two key waypoints; pathfinding fills the middle.
	var route := PatrolRouteScript.new()
	route.configure([Vector3i(0, 0, 0), Vector3i(0, 0, 5)], true)
	var alert := AlertStateScript.new()

	# Enemy anchored at the first waypoint: advance targets (0,0,5), then walk
	# up to move_range cells per tick.
	var plan := EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(0, 0, 0), alert, route, {}, grid, 2
	)
	_expect(plan[&"intent"] == EnemyTacticalAIScript.IntentType.PATROL_STEP, "ai sparse: should walk toward the far waypoint")
	_expect(plan[&"destination"] == Vector3i(0, 0, 2), "ai sparse: move_range 2 should advance to (0,0,2)")
	_expect(plan[&"waypoint"] == Vector3i(0, 0, 5), "ai sparse: plan should carry the target waypoint")

	# Mid-path: no arrival yet, keep walking.
	var plan_mid := EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(0, 0, 2), alert, route, {}, grid, 1
	)
	_expect(plan_mid[&"intent"] == EnemyTacticalAIScript.IntentType.PATROL_STEP, "ai sparse: mid-path should keep patrolling")
	_expect(plan_mid[&"destination"] == Vector3i(0, 0, 3), "ai sparse: mid-path should step to (0,0,3)")

	# Arrival at (0,0,5): route advances to the loop-wrapped next waypoint.
	var plan_arrival := EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(0, 0, 5), alert, route, {}, grid, 1
	)
	_expect(plan_arrival[&"intent"] == EnemyTacticalAIScript.IntentType.PATROL_STEP, "ai sparse: arrival should continue the loop")
	_expect(plan_arrival[&"destination"] == Vector3i(0, 0, 4), "ai sparse: loop should head back toward (0,0,0)")

	# Single-waypoint route: nothing to walk to.
	var single := PatrolRouteScript.new()
	single.configure([Vector3i(3, 0, 3)], true)
	var plan_single := EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(3, 0, 3), alert, single, {}, grid
	)
	_expect(plan_single[&"intent"] == EnemyTacticalAIScript.IntentType.PASS, "ai sparse: single waypoint should pass")


func _test_patrol_dwell_wait() -> void:
	var grid := GridModelScript.new(Vector2i(10, 10))
	var route := PatrolRouteScript.new()
	route.configure([Vector3i(0, 0, 0), Vector3i(0, 0, 5)], true, [0, 2])
	var alert := AlertStateScript.new()

	# Enemy anchored at the start waypoint: advance arms dwell 2 at (0,0,5),
	# then it walks one cell per tick.
	var plan_walk := EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(0, 0, 0), alert, route, {}, grid, 1
	)
	_expect(plan_walk[&"intent"] == EnemyTacticalAIScript.IntentType.PATROL_STEP, "ai dwell: walking to waypoint should not dwell")
	_expect(plan_walk[&"destination"] == Vector3i(0, 0, 1), "ai dwell: should step one cell toward the waypoint")

	# Arrival at the waypoint: dwell_ticks 2 -> two PASS ticks.
	var plan_dwell1 := EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(0, 0, 5), alert, route, {}, grid
	)
	_expect(plan_dwell1[&"intent"] == EnemyTacticalAIScript.IntentType.PASS, "ai dwell: first dwell tick should pass")
	_expect(plan_dwell1[&"dwell"] == true, "ai dwell: plan should flag the dwell wait")
	_expect(route.dwell_remaining() == 1, "ai dwell: remaining should drop to 1")

	var plan_dwell2 := EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(0, 0, 5), alert, route, {}, grid
	)
	_expect(plan_dwell2[&"intent"] == EnemyTacticalAIScript.IntentType.PASS, "ai dwell: second dwell tick should pass")
	_expect(route.dwell_remaining() == 0, "ai dwell: remaining should drop to 0")

	# Dwell exhausted: advance and resume the loop.
	var plan_resume := EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(0, 0, 5), alert, route, {}, grid, 1
	)
	_expect(plan_resume[&"intent"] == EnemyTacticalAIScript.IntentType.PATROL_STEP, "ai dwell: after dwell should resume patrolling")
	_expect(plan_resume[&"destination"] == Vector3i(0, 0, 4), "ai dwell: should head back toward the first waypoint")


func _test_patrol_unreachable_waypoint_skip() -> void:
	var grid := GridModelScript.new(Vector2i(10, 10))
	# Isolate waypoint (0,0,5): every other cell except the two waypoints is
	# non-walkable, so no path to it exists and no neighbor fallback can help.
	for z in range(10):
		for x in range(10):
			var cell := Vector3i(x, 0, z)
			if cell != Vector3i(0, 0, 0) and cell != Vector3i(0, 0, 5):
				grid.set_walkable(cell, false)
	var route := PatrolRouteScript.new()
	route.configure([Vector3i(0, 0, 0), Vector3i(0, 0, 5)], true)
	var alert := AlertStateScript.new()

	var plan := EnemyTacticalAIScript.plan_exploration_step(
		Vector3i(0, 0, 0), alert, route, {}, grid
	)
	_expect(plan[&"intent"] == EnemyTacticalAIScript.IntentType.PASS, "ai skip: blocked waypoint should pass without moving")
	_expect(route.current() == Vector3i(0, 0, 0), "ai skip: skipped waypoint should wrap back to the start")


func _test_return_to_patrol_after_calm_down() -> void:
	var grid := GridModelScript.new(Vector2i(10, 10))
	var route := PatrolRouteScript.new()
	route.configure([Vector3i(0, 0, 0), Vector3i(0, 0, 4), Vector3i(4, 0, 4)], true)
	var alert := AlertStateScript.new()

	# Guard investigated cell (3,0,3) and found nothing: idle ticks exhausted.
	alert.become_suspicious(Vector3i(3, 0, 3))
	var enemy_cell := Vector3i(3, 0, 3)
	var plan := EnemyTacticalAIScript.plan_exploration_step(
		enemy_cell, alert, route, {&"idle_ticks": 1}, grid
	)
	_expect(plan[&"intent"] == EnemyTacticalAIScript.IntentType.CALM_DOWN, "ai return: fruitless search should calm down")
	_expect(plan[&"should_calm_down"] == true, "ai return: should flag calm down")
	_expect(route.current() == Vector3i(4, 0, 4), "ai return: route should re-anchor to nearest waypoint (4,0,4)")

	# Next tick: guard pathfinds back and resumes the loop seamlessly.
	alert.calm_down()
	var plan_back := EnemyTacticalAIScript.plan_exploration_step(
		enemy_cell, alert, route, {}, grid
	)
	_expect(plan_back[&"intent"] == EnemyTacticalAIScript.IntentType.PATROL_STEP, "ai return: should walk back to the nearest waypoint")
	_expect(plan_back[&"waypoint"] == Vector3i(4, 0, 4), "ai return: plan should target the re-anchored waypoint")


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
