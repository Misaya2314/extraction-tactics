extends SceneTree

const GridVisibilityScript = preload("res://scripts/core/perception/grid_visibility.gd")
const DetectionRulesScript = preload("res://scripts/core/perception/detection_rules.gd")
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
	_expect(DetectionRulesScript.is_in_vision_cone(observer, _c(2, 0), Vector2i.UP, 4), "cone: target in front should be visible")
	_expect(not DetectionRulesScript.is_in_vision_cone(observer, _c(2, 4), Vector2i.UP, 4), "cone: target behind should be hidden")
	_expect(DetectionRulesScript.is_in_vision_cone(observer, _c(4, 2, 1), Vector2i.RIGHT, 4), "cone: elevated target in facing direction should be visible")
	_expect(not DetectionRulesScript.can_detect(observer, _c(2, 0), Vector2i.UP, 4, {_c(2, 1): true}), "detect: LOS blocker should prevent detection")
	_expect(DetectionRulesScript.can_player_see(observer, _c(2, 4), 4, {}), "player: vision should remain 360 degrees")


func _test_alert_state() -> void:
	var state = AlertStateScript.new()
	state.level_changed.connect(_record_level_change)
	_expect(state.become_suspicious(_c(3, 3, 1)), "alert: unaware should become suspicious")
	_expect(state.get_last_known_cell() == _c(3, 3, 1), "alert: last-known cell should preserve level")
	_expect(state.engage(&"enemy_alpha", _c(5, 5, 1)), "alert: valid target should engage")
	_expect(state.get_target_id() == &"enemy_alpha", "alert: target id should persist")
	_expect(state.calm_down() and state.calm_down(), "alert: two calm-downs should return to unaware")
	_expect(_level_events.size() == 4, "alert: real state changes should emit events")
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
