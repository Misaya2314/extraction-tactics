extends SceneTree

const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")
const AlertStateScript = preload("res://scripts/core/encounter/alert_state.gd")
const TurnManagerScript = preload("res://scripts/core/turn/turn_manager.gd")
const GameStateManagerScript = preload("res://scripts/core/session/game_state_manager.gd")
const PrototypeControllerScript = preload("res://scripts/gameplay/prototype_controller.gd")
const PrototypeUnitScript = preload("res://scripts/gameplay/prototype_unit.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_investigation_highlight_displays_target_cell()
	_test_investigation_highlight_multiple_enemies_merge()
	_test_investigation_highlight_clears_on_calm_down()
	_finish()


func _test_investigation_highlight_displays_target_cell() -> void:
	var controller := PrototypeControllerScript.new()
	controller.grid = GridModelScript.new(Vector2i(20, 20))
	controller.turn_manager = TurnManagerScript.new()
	controller.session_manager = GameStateManagerScript.new()
	controller.session_manager.start_exploration()

	var player := PrototypeUnitScript.new()
	player.unit_id = &"p1"
	player.name = "玩家A"
	player.faction = &"player"
	player.grid_cell = Vector3i(1, 0, 1)

	var enemy := PrototypeUnitScript.new()
	enemy.unit_id = &"e1"
	enemy.name = "守卫A"
	enemy.faction = &"enemy"
	enemy.grid_cell = Vector3i(10, 0, 10)
	enemy.max_hp = 10
	enemy.current_hp = 10

	var alert := AlertStateScript.new()
	alert.become_suspicious(Vector3i(5, 0, 5))

	controller.all_player_ids = [&"p1"]
	controller.all_enemy_ids = [&"e1"]
	controller.units_by_id = {&"p1": player, &"e1": enemy}
	controller.enemy_alerts = {&"e1": alert}
	controller.suspicious_investigations = {
		&"e1": {&"target_cell": Vector3i(5, 0, 5), &"idle_ticks": 0}
	}
	controller.turn_manager.configure([&"p1"], [])

	# Manually supply root container since we're in headless test without full scene
	controller.investigation_highlights_root = Node3D.new()

	controller._refresh_highlights()

	# Verify highlight and marker exist in investigation_highlights_root
	var root: Node3D = controller.investigation_highlights_root
	_expect(root.get_child_count() == 2, "highlight: should have 2 children (1 mesh highlight + 1 marker node)")

	var marker: Node3D = root.get_node_or_null("InvestigationMarker_5_0_5") as Node3D
	_expect(marker != null, "highlight: InvestigationMarker_5_0_5 should exist")
	if marker != null:
		var label: Label3D = marker.get_node_or_null("Label") as Label3D
		_expect(label != null, "highlight: marker should have Label3D")
		if label != null:
			_expect(label.text.contains("守卫A"), "highlight: label should mention 守卫A")
			_expect(label.text.contains("探查目标"), "highlight: label should contain '探查目标'")

	controller.free()


func _test_investigation_highlight_multiple_enemies_merge() -> void:
	var controller := PrototypeControllerScript.new()
	controller.grid = GridModelScript.new(Vector2i(20, 20))
	controller.turn_manager = TurnManagerScript.new()
	controller.session_manager = GameStateManagerScript.new()
	controller.session_manager.start_exploration()

	var enemy1 := PrototypeUnitScript.new()
	enemy1.unit_id = &"e1"
	enemy1.name = "守卫A"
	enemy1.faction = &"enemy"
	enemy1.grid_cell = Vector3i(8, 0, 8)
	enemy1.max_hp = 10
	enemy1.current_hp = 10

	var enemy2 := PrototypeUnitScript.new()
	enemy2.unit_id = &"e2"
	enemy2.name = "守卫B"
	enemy2.faction = &"enemy"
	enemy2.grid_cell = Vector3i(12, 0, 12)
	enemy2.max_hp = 10
	enemy2.current_hp = 10

	var alert1 := AlertStateScript.new()
	alert1.become_suspicious(Vector3i(6, 0, 6))

	var alert2 := AlertStateScript.new()
	alert2.become_suspicious(Vector3i(6, 0, 6))

	controller.all_player_ids = []
	controller.all_enemy_ids = [&"e1", &"e2"]
	controller.units_by_id = {&"e1": enemy1, &"e2": enemy2}
	controller.enemy_alerts = {&"e1": alert1, &"e2": alert2}
	controller.turn_manager.configure([], [])
	controller.investigation_highlights_root = Node3D.new()

	controller._refresh_highlights()

	var root: Node3D = controller.investigation_highlights_root
	_expect(root.get_child_count() == 2, "merge: should have 2 children (1 mesh + 1 marker for the shared cell)")
	var marker: Node3D = root.get_node_or_null("InvestigationMarker_6_0_6") as Node3D
	_expect(marker != null, "merge: shared InvestigationMarker_6_0_6 should exist")
	if marker != null:
		var label: Label3D = marker.get_node_or_null("Label") as Label3D
		_expect(label != null, "merge: label should exist")
		if label != null:
			_expect(label.text.contains("2人"), "merge: label should indicate 2 enemies")
			_expect(label.text.contains("守卫A") and label.text.contains("守卫B"), "merge: label should contain both names")

	controller.free()


func _test_investigation_highlight_clears_on_calm_down() -> void:
	var controller := PrototypeControllerScript.new()
	controller.grid = GridModelScript.new(Vector2i(20, 20))
	controller.turn_manager = TurnManagerScript.new()
	controller.session_manager = GameStateManagerScript.new()
	controller.session_manager.start_exploration()

	var enemy := PrototypeUnitScript.new()
	enemy.unit_id = &"e1"
	enemy.name = "守卫A"
	enemy.faction = &"enemy"
	enemy.grid_cell = Vector3i(10, 0, 10)
	enemy.max_hp = 10
	enemy.current_hp = 10

	var alert := AlertStateScript.new()
	alert.become_suspicious(Vector3i(5, 0, 5))

	controller.all_player_ids = []
	controller.all_enemy_ids = [&"e1"]
	controller.units_by_id = {&"e1": enemy}
	controller.enemy_alerts = {&"e1": alert}
	controller.turn_manager.configure([], [])
	controller.investigation_highlights_root = Node3D.new()

	controller._refresh_highlights()
	_expect(controller.investigation_highlights_root.get_child_count() == 2, "clear: initially 2 children")

	# Enemy calms down
	alert.calm_down()
	controller._refresh_highlights()
	_expect(controller.investigation_highlights_root.get_child_count() == 0, "clear: 0 children after calm down")

	controller.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("INVESTIGATION_HIGHLIGHT_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("INVESTIGATION_HIGHLIGHT_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
