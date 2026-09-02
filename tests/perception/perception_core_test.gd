extends SceneTree

const GridVisibilityScript = preload("res://scripts/core/perception/grid_visibility.gd")
const DetectionRulesScript = preload("res://scripts/core/perception/detection_rules.gd")
const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")
const AlertStateScript = preload("res://scripts/core/encounter/alert_state.gd")
const PatrolRouteScript = preload("res://scripts/core/encounter/patrol_route.gd")

var _failures: Array[String] = []
var _level_events: Array[Vector2i] = []


func _init() -> void:
	_test_line_of_sight_and_levels()
	_test_visible_cells()
	_test_detection_rules()
	_test_alert_state()
	_test_patrol_route()
	_finish()


func _test_line_of_sight_and_levels() -> void:
	var horizontal := GridVisibilityScript.line_cells(_c(0, 2), _c(3, 2))
	_expect(horizontal == [_c(0, 2), _c(1, 2), _c(2, 2), _c(3, 2)], "line: horizontal traversal should include every cell")
	var diagonal := GridVisibilityScript.line_cells(_c(0, 0), _c(2, 2))
	_expect(diagonal == [_c(0, 0), _c(1, 0), _c(0, 1), _c(1, 1), _c(2, 1), _c(1, 2), _c(2, 2)], "line: diagonal supercover should prevent corner peeking")
	var wall: Dictionary = {_c(2, 0): true}
	_expect(not GridVisibilityScript.has_line_of_sight(_c(0, 0), _c(4, 0), wall), "los: same-level intermediate wall should block")
	_expect(GridVisibilityScript.has_line_of_sight(_c(0, 0, 1), _c(4, 0, 1), wall), "los: lower-level wall key must not block upper-level sight")
	_expect(GridVisibilityScript.has_line_of_sight(_c(0, 0), _c(2, 0), wall), "los: opaque target itself remains visible")
	_expect(not GridVisibilityScript.has_line_of_sight(_c(0, 0), _c(4, 0), {}, 3), "los: range should include vertical and horizontal distance")
	_expect(GridVisibilityScript.tactical_distance(_c(0, 0), _c(2, 0, 1)) == 3, "distance: one level should cost one range unit")


func _test_visible_cells() -> void:
	var visible := GridVisibilityScript.visible_cells(_c(1, 1), Vector2i(4, 4), 1, 1, {})
	var expected: Array[Vector3i] = [_c(1, 0), _c(0, 1), _c(1, 1), _c(2, 1), _c(1, 2)]
	_expect(visible == expected, "visible: level-zero range and ordering should remain stable")
	var stacked := GridVisibilityScript.visible_cells(_c(1, 1), Vector2i(3, 3), 2, 1, {})
	_expect(stacked.has(_c(1, 1, 1)), "visible: adjacent logical level should be considered")
	_expect(GridVisibilityScript.visible_cells(_c(1, 1), Vector2i(3, 3), 2, -1, {}).is_empty(), "visible: negative range should return no cells")


func _test_detection_rules() -> void:
	var observer := _c(2, 2)
	_expect(DetectionRulesScript.is_in_range(observer, _c(2, 0), 4), "range: target in range should be true")
	_expect(DetectionRulesScript.is_in_range(observer, _c(2, 4), 4), "range: target at distance 2 should be in range 4")
	_expect(DetectionRulesScript.is_in_range(observer, _c(4, 2, 1), 4), "range: elevated target in range should be true")
	_expect(not DetectionRulesScript.is_in_range(observer, _c(2, 8), 4), "range: target beyond distance 4 should be false")
	_expect(not DetectionRulesScript.can_detect(observer, _c(2, 0), 4, {_c(2, 1): true}), "detect: LOS blocker should prevent detection")
	_expect(DetectionRulesScript.can_player_see(observer, _c(2, 4), 4, {}), "player: vision should remain 360 degrees")

	var edge_grid := GridModelScript.new(Vector2i(5, 1))
	var sight_edge := _edge(_c(1, 0), _c(2, 0), 1.0, 0.0)
	_expect(edge_grid.edge_index.configure([sight_edge]), "detect: explicit sight edge should index")
	var edge_observer := _c(0, 0)
	var edge_target := _c(4, 0)
	_expect(not DetectionRulesScript.can_detect(
		edge_observer, edge_target, 4, {},
		edge_grid, edge_grid.get_edge_index()
	), "detect: explicit sight edge should block enemy detection")
	_expect(DetectionRulesScript.can_player_see(
		edge_observer, edge_target, 4, {}, edge_grid, edge_grid.get_edge_index()
	), "player: explicit sight edge should not block player visibility")

	var projectile_edge := _edge(_c(1, 0), _c(2, 0), 0.0, 1.0)
	_expect(edge_grid.edge_index.configure([projectile_edge]), "detect: explicit projectile edge should index")
	_expect(DetectionRulesScript.can_detect(
		edge_observer, edge_target, 4, {},
		edge_grid, edge_grid.get_edge_index()
	), "detect: projectile-only edge must not block enemy detection")
	_expect(DetectionRulesScript.can_player_see(
		edge_observer, edge_target, 4, {}, edge_grid, edge_grid.get_edge_index()
	), "player: projectile-only edge must not block player visibility")

	# Intermediate opaque cells must not block player vision
	var opaque_wall := {_c(2, 0): true}
	_expect(DetectionRulesScript.can_player_see(
		edge_observer, edge_target, 4, opaque_wall
	), "player: opaque cell must not block player visibility")

	var empty_grid := GridModelScript.new(Vector2i(5, 1))
	var legacy_result := DetectionRulesScript.can_player_see(edge_observer, edge_target, 4, {})
	var compatible_result := DetectionRulesScript.can_player_see(edge_observer, edge_target, 4, {}, empty_grid, empty_grid.get_edge_index())
	_expect(legacy_result == compatible_result, "detect: legacy call without GridModel must retain its result")
	var legacy_negative := DetectionRulesScript.can_player_see(edge_observer, edge_target, -1, {})
	var compatible_negative := DetectionRulesScript.can_player_see(edge_observer, edge_target, -1, {}, empty_grid, empty_grid.get_edge_index())
	_expect(not legacy_negative and not compatible_negative, "player: negative vision range must remain rejected on old and GridModel paths")

	# Dual-tier vision tests
	var origin := _c(2, 2)
	var close_target := _c(2, 4)
	var far_target := _c(2, 6)
	var out_target := _c(2, 9)
	_expect(DetectionRulesScript.evaluate_detection_tier(
		origin, close_target, 3, 6, {}
	) == DetectionRulesScript.DetectionTier.INNER_DISCOVERY, "dual-tier: close target should trigger INNER_DISCOVERY")
	_expect(DetectionRulesScript.evaluate_detection_tier(
		origin, far_target, 3, 6, {}
	) == DetectionRulesScript.DetectionTier.OUTER_ALERT, "dual-tier: intermediate target should trigger OUTER_ALERT")
	_expect(DetectionRulesScript.evaluate_detection_tier(
		origin, out_target, 3, 6, {}
	) == DetectionRulesScript.DetectionTier.NONE, "dual-tier: target beyond outer range should be NONE")


func _test_alert_state() -> void:
	var state = AlertStateScript.new()
	state.level_changed.connect(_record_level_change)
	_expect(state.become_suspicious(_c(3, 3, 1)), "alert: unaware should become suspicious")
	_expect(state.get_last_known_cell() == _c(3, 3, 1), "alert: last-known cell should preserve level")
	_expect(state.become_alerted(&"enemy_alpha", _c(4, 4, 1)), "alert: suspicious should become alerted")
	_expect(state.get_target_id() == &"enemy_alpha", "alert: target id should persist in alerted")
	_expect(state.is_alerted(), "alert: should report is_alerted")
	_expect(state.engage(&"enemy_alpha", _c(5, 5, 1)), "alert: valid target should engage")
	_expect(state.is_engaged(), "alert: should report is_engaged")
	_expect(state.calm_down(), "alert: engage calm_down to suspicious")
	_expect(state.is_suspicious(), "alert: should now be suspicious")
	_expect(state.calm_down(), "alert: suspicious calm_down to unaware")
	_expect(state.is_unaware(), "alert: should now be unaware")
	_expect(_level_events.size() == 5, "alert: real state changes should emit events")
	state.reset()
	_expect(state.get_last_known_cell() == AlertStateScript.INVALID_CELL, "alert: reset should clear last-known cell")


func _test_patrol_route() -> void:
	var route = PatrolRouteScript.new()
	var points: Array[Vector3i] = [_c(0, 0), _c(1, 0), _c(1, 0), _c(1, 0, 1)]
	route.configure(points, true)
	_expect(route.current() == _c(0, 0), "patrol: should start at first point")
	_expect(route.advance() == _c(1, 0), "patrol: should advance horizontally")
	_expect(route.advance() == _c(1, 0, 1), "patrol: route should preserve cross-level point")
	_expect(route.advance() == _c(0, 0), "patrol: looping route should wrap")
	var empty = PatrolRouteScript.new()
	empty.configure([], false)
	_expect(empty.current() == PatrolRouteScript.INVALID_CELL, "patrol: empty route should return invalid cell")


func _c(x: int, z: int, level: int = 0) -> Vector3i:
	return Vector3i(x, level, z)


func _edge(cell_a: Vector3i, cell_b: Vector3i, sight_block: float, projectile_block: float) -> MapEdgeData:
	var edge := MapEdgeData.new()
	var key := TacticalEdgeKey.from_cells(cell_a, cell_b)
	edge.cell_a = key.cell_a
	edge.cell_b = key.cell_b
	edge.sight_block = sight_block
	edge.projectile_block = projectile_block
	return edge


func _record_level_change(previous: int, current: int) -> void:
	_level_events.append(Vector2i(previous, current))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PERCEPTION_CORE_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("PERCEPTION_CORE_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
