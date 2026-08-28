extends SceneTree

const PrototypeControllerScript = preload("res://scripts/gameplay/prototype_controller.gd")
const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_hover_cursor_lifecycle()
	_test_hover_cursor_bounds_and_visibility()
	_finish()


func _test_hover_cursor_lifecycle() -> void:
	var controller = PrototypeControllerScript.new()
	controller.grid = GridModelScript.new(Vector2i(4, 4))
	controller._init_hover_cursor()

	_expect(controller._hover_cursor != null, "cursor: _hover_cursor should be instantiated")
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
