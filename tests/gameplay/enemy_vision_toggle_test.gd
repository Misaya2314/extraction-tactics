extends SceneTree

const PrototypeControllerScript = preload("res://scripts/gameplay/prototype_controller.gd")
const PrototypeUnitScript = preload("res://scripts/gameplay/prototype_unit.gd")
const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")
const TurnManagerScript = preload("res://scripts/core/turn/turn_manager.gd")
const DetectionRulesScript = preload("res://scripts/core/perception/detection_rules.gd")

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_main_scene_hint_text()
	_test_default_state_and_key_handling()
	_test_vision_overlay_rendering_visibility()
	_test_overlapping_vision_cones_deduplication()
	_finish()


func _test_main_scene_hint_text() -> void:
	var scene_text := FileAccess.get_file_as_string("res://scenes/main/prototype_main.tscn")
	_expect(not scene_text.is_empty(), "main_scene: prototype_main.tscn should be readable")
	_expect(scene_text.contains("Z切换敌人视野"), "main_scene: HintLabel should mention 'Z切换敌人视野'")


func _test_default_state_and_key_handling() -> void:
	var controller = PrototypeControllerScript.new()
	controller.grid = GridModelScript.new(Vector2i(8, 8))

	_expect(controller.show_enemy_vision == false, "toggle: show_enemy_vision should default to false")

	# Simulate pressing Z
	var z_press := InputEventKey.new()
	z_press.pressed = true
	z_press.echo = false
	z_press.keycode = KEY_Z
	controller._unhandled_input(z_press)
	_expect(controller.show_enemy_vision == true, "toggle: pressing Z should toggle show_enemy_vision to true")

	# Echo event should be ignored
	var z_echo := InputEventKey.new()
	z_echo.pressed = true
	z_echo.echo = true
	z_echo.keycode = KEY_Z
	controller._unhandled_input(z_echo)
	_expect(controller.show_enemy_vision == true, "toggle: echo Z should not toggle")

	# Release event should be ignored
	var z_release := InputEventKey.new()
	z_release.pressed = false
	z_release.echo = false
	z_release.keycode = KEY_Z
	controller._unhandled_input(z_release)
	_expect(controller.show_enemy_vision == true, "toggle: releasing Z should not toggle")

	# Pressing Z again should toggle back to false
	controller._unhandled_input(z_press)
	_expect(controller.show_enemy_vision == false, "toggle: pressing Z again should toggle show_enemy_vision to false")

	controller.free()


func _test_vision_overlay_rendering_visibility() -> void:
	var controller = PrototypeControllerScript.new()
	var grid = GridModelScript.new(Vector2i(10, 10))
	controller.grid = grid

	var vision_root = Node3D.new()
	var highlights_root = Node3D.new()
	var attack_root = Node3D.new()
	var object_root = Node3D.new()
	controller.vision_highlights_root = vision_root
	controller.highlights_root = highlights_root
	controller.attack_highlights_root = attack_root
	controller.object_highlights_root = object_root

	var turn_manager = TurnManagerScript.new()
	turn_manager.configure([&"player_1"], [&"enemy_1", &"enemy_2"])
	controller.turn_manager = turn_manager

	# Player unit at (0, 0, 0) with vision_range = 5
	var player = PrototypeUnitScript.new()
	player.faction = &"player"
	player.grid_cell = Vector3i(0, 0, 0)
	player.vision_range = 5
	player.inner_vision_range = 3
	controller.units_by_id[&"player_1"] = player

	# Visible Enemy 1 at (2, 0, 0), facing RIGHT (1, 0), vision_range = 3, inner_vision_range = 1
	var enemy1 = PrototypeUnitScript.new()
	enemy1.faction = &"enemy"
	enemy1.grid_cell = Vector3i(2, 0, 0)
	enemy1.facing = Vector2i(1, 0)
	enemy1.vision_range = 3
	enemy1.inner_vision_range = 1
	enemy1.visible = true
	controller.units_by_id[&"enemy_1"] = enemy1

	# Hidden Enemy 2 at (9, 0, 9), facing LEFT (-1, 0), vision_range = 3, inner_vision_range = 1
	var enemy2 = PrototypeUnitScript.new()
	enemy2.faction = &"enemy"
	enemy2.grid_cell = Vector3i(9, 0, 9)
	enemy2.facing = Vector2i(-1, 0)
	enemy2.vision_range = 3
	enemy2.inner_vision_range = 1
	enemy2.visible = false
	controller.units_by_id[&"enemy_2"] = enemy2

	var player_ids: Array[StringName] = [&"player_1"]
	var enemy_ids: Array[StringName] = [&"enemy_1", &"enemy_2"]
	controller.all_player_ids = player_ids
	controller.all_enemy_ids = enemy_ids

	# 1. show_enemy_vision is false and no enemy selected -> no enemy highlights in vision_root
	controller.show_enemy_vision = false
	controller.selected_unit = null
	controller._refresh_highlights()

	var enemy_highlights := _get_enemy_vision_highlights(vision_root)
	_expect(enemy_highlights.is_empty(), "render: when toggle is off and no selection, no enemy vision highlights should appear")

	# 2. Toggle show_enemy_vision to true -> enemy1's vision should be rendered, enemy2 should not
	controller._set_show_enemy_vision(true)
	enemy_highlights = _get_enemy_vision_highlights(vision_root)
	_expect(not enemy_highlights.is_empty(), "render: when toggle is on, visible enemy highlights should appear")

	# Check that enemy 1's cells (e.g. (3, 0, 0)) are highlighted
	var highlighted_cells: Array[Vector3i] = []
	for h in enemy_highlights:
		highlighted_cells.append(h.get_meta(&"grid_cell"))
	_expect(highlighted_cells.has(Vector3i(3, 0, 0)), "render: enemy1's forward cell (3,0,0) should be highlighted")
	# Check that enemy 2's cells (e.g. (8, 0, 9)) are NOT highlighted
	_expect(not highlighted_cells.has(Vector3i(8, 0, 9)), "render: hidden enemy2's cell (8,0,9) should NOT be highlighted")

	# 3. When enemy2 is selected, its vision should now be rendered too
	controller.selected_unit = enemy2
	controller._refresh_highlights()
	enemy_highlights = _get_enemy_vision_highlights(vision_root)
	highlighted_cells.clear()
	for h in enemy_highlights:
		highlighted_cells.append(h.get_meta(&"grid_cell"))
	_expect(highlighted_cells.has(Vector3i(8, 0, 9)), "render: selected enemy2 should display vision highlights even if hidden")
	_expect(highlighted_cells.has(Vector3i(3, 0, 0)), "render: visible enemy1 should still display vision highlights")

	# Cleanup
	player.free()
	enemy1.free()
	enemy2.free()
	vision_root.free()
	highlights_root.free()
	attack_root.free()
	object_root.free()
	controller.free()


func _test_overlapping_vision_cones_deduplication() -> void:
	var controller = PrototypeControllerScript.new()
	var grid = GridModelScript.new(Vector2i(10, 10))
	controller.grid = grid

	var vision_root = Node3D.new()
	var highlights_root = Node3D.new()
	var attack_root = Node3D.new()
	var object_root = Node3D.new()
	controller.vision_highlights_root = vision_root
	controller.highlights_root = highlights_root
	controller.attack_highlights_root = attack_root
	controller.object_highlights_root = object_root

	var turn_manager = TurnManagerScript.new()
	turn_manager.configure([&"player_1"], [&"enemy_1", &"enemy_2"])
	controller.turn_manager = turn_manager

	var player = PrototypeUnitScript.new()
	player.faction = &"player"
	player.grid_cell = Vector3i(0, 0, 0)
	player.vision_range = 10
	controller.units_by_id[&"player_1"] = player

	# Enemy 1 at (2, 0, 2) facing RIGHT (1, 0)
	var enemy1 = PrototypeUnitScript.new()
	enemy1.faction = &"enemy"
	enemy1.grid_cell = Vector3i(2, 0, 2)
	enemy1.facing = Vector2i(1, 0)
	enemy1.vision_range = 4
	enemy1.inner_vision_range = 2
	enemy1.visible = true
	controller.units_by_id[&"enemy_1"] = enemy1

	# Enemy 2 at (2, 0, 3) facing RIGHT (1, 0)
	var enemy2 = PrototypeUnitScript.new()
	enemy2.faction = &"enemy"
	enemy2.grid_cell = Vector3i(2, 0, 3)
	enemy2.facing = Vector2i(1, 0)
	enemy2.vision_range = 4
	enemy2.inner_vision_range = 2
	enemy2.visible = true
	controller.units_by_id[&"enemy_2"] = enemy2

	var player_ids: Array[StringName] = [&"player_1"]
	var enemy_ids: Array[StringName] = [&"enemy_1", &"enemy_2"]
	controller.all_player_ids = player_ids
	controller.all_enemy_ids = enemy_ids

	controller._set_show_enemy_vision(true)
	var enemy_highlights := _get_enemy_vision_highlights(vision_root)

	# Verify no duplicate cells in highlights
	var seen_cells: Dictionary = {}
	var has_duplicate := false
	for h in enemy_highlights:
		var cell: Vector3i = h.get_meta(&"grid_cell")
		if seen_cells.has(cell):
			has_duplicate = true
			break
		seen_cells[cell] = true
	_expect(not has_duplicate, "render: overlapping vision cones should not create duplicate meshes on the same cell")

	player.free()
	enemy1.free()
	enemy2.free()
	vision_root.free()
	highlights_root.free()
	attack_root.free()
	object_root.free()
	controller.free()


func _get_enemy_vision_highlights(parent: Node3D) -> Array[MeshInstance3D]:
	var results: Array[MeshInstance3D] = []
	for child in parent.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance != null:
			var mat := mesh_instance.material_override as StandardMaterial3D
			if mat != null and (mat.albedo_color == PrototypeControllerScript.ENEMY_INNER_VISION_COLOR or mat.albedo_color == PrototypeControllerScript.ENEMY_OUTER_VISION_COLOR):
				results.append(mesh_instance)
	return results


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("ENEMY_VISION_TOGGLE_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ENEMY_VISION_TOGGLE_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
