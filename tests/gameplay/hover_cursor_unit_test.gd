extends SceneTree

const PrototypeControllerScript = preload("res://scripts/gameplay/prototype_controller.gd")
const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")
const MapEdgeDataScript = preload("res://scripts/core/map/map_edge_data.gd")
const TacticalEdgeRulesScript = preload("res://scripts/core/map/tactical_edge_rules.gd")
const TacticalCoverProfileScript = preload("res://scripts/core/cover/tactical_cover_profile.gd")

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_hover_cursor_lifecycle()
	_test_hover_cursor_bounds_and_visibility()
	_test_cover_preview_indicators()
	_finish()


func _test_hover_cursor_lifecycle() -> void:
	var controller = PrototypeControllerScript.new()
	controller.grid = GridModelScript.new(Vector2i(4, 4))
	controller._init_hover_cursor()

	_expect(controller._hover_cursor != null, "cursor: _hover_cursor should be instantiated")
	_expect(controller._cover_indicators_root != null, "cursor: _cover_indicators_root should be instantiated")
	if controller._hover_cursor != null:
		_expect(controller._hover_cursor.name == "HoverCursor", "cursor: name should be HoverCursor")
		_expect(not controller._hover_cursor.visible, "cursor: initial visibility should be false")
		_expect(controller._hover_cursor.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "cursor: shadows should be disabled")
		_expect(controller.get_hovered_cell() == Vector3i(-1, -1, -1), "cursor: initial hovered cell should be invalid")
		
		# Test hide
		controller._hover_cursor.visible = true
		controller._hovered_cell = Vector3i(1, 0, 1)
		controller._hide_hover_cursor()
		_expect(not controller._hover_cursor.visible, "cursor: _hide_hover_cursor should set visible to false")
		_expect(controller.get_hovered_cell() == controller.grid.invalid_cell(), "cursor: _hide_hover_cursor should reset hovered cell")

	controller.free()


func _test_hover_cursor_bounds_and_visibility() -> void:
	var controller = PrototypeControllerScript.new()
	controller.grid = GridModelScript.new(Vector2i(4, 4))
	controller._init_hover_cursor()

	# When player cannot act, cursor hides
	controller._update_hover_cursor(Vector2(100, 100))
	_expect(not controller._hover_cursor.visible, "cursor: should remain hidden when player cannot act")

	controller.free()


func _test_cover_preview_indicators() -> void:
	var controller = PrototypeControllerScript.new()
	var grid = GridModelScript.new(Vector2i(6, 6))
	controller.grid = grid
	controller._init_hover_cursor()

	# Setup an edge with HALF cover on side A (cell (2,0,2)) and FULL cover on side B (cell (2,0,3))
	var edge := MapEdgeDataScript.new()
	edge.cell_a = Vector3i(2, 0, 2)
	edge.cell_b = Vector3i(2, 0, 3)
	edge.cover_a = TacticalEdgeRulesScript.CoverLevel.HALF
	edge.cover_b = TacticalEdgeRulesScript.CoverLevel.FULL
	grid.edge_index.configure([edge])

	# Update preview with cursor at (2, 0, 2)
	controller._update_cover_preview(Vector3i(2, 0, 2))

	var visible_sprites: Array[Sprite3D] = []
	for sprite in controller._cover_icon_pool:
		if sprite.visible:
			visible_sprites.append(sprite)

	_expect(visible_sprites.size() == 2, "cover_preview: should show 2 cover icons (one for (2,0,2), one for (2,0,3))")
	if visible_sprites.size() >= 2:
		var textures := [visible_sprites[0].texture, visible_sprites[1].texture]
		_expect(textures.has(controller.HALF_COVER_TEXTURE), "cover_preview: should have half cover texture")
		_expect(textures.has(controller.FULL_COVER_TEXTURE), "cover_preview: should have full cover texture")

	# Moving cursor far away (> 2 distance, e.g. (5, 0, 5)) should show no icons
	controller._update_cover_preview(Vector3i(5, 0, 5))
	var visible_count_far := 0
	for sprite in controller._cover_icon_pool:
		if sprite.visible:
			visible_count_far += 1
	_expect(visible_count_far == 0, "cover_preview: should show 0 cover icons when beyond distance 2")

	# Hide cover preview
	controller._hide_cover_preview()
	for sprite in controller._cover_icon_pool:
		_expect(not sprite.visible, "cover_preview: _hide_cover_preview should make all sprites invisible")

	controller.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("HOVER_CURSOR_UNIT_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("HOVER_CURSOR_UNIT_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
