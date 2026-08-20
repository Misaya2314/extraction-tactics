extends SceneTree

## Pure Dock wiring coverage. It exercises the code-built control only and
## never loads a map scene or invokes authoring/bake data.

const DockScript = preload("res://addons/tactical_map_editor/ui/tactical_map_dock.gd")
const SessionScript = preload("res://addons/tactical_map_editor/editing/map_edit_session.gd")

var _failures: Array[String] = []
var _play_signal_count: int = 0
var _location_signal_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dock = DockScript.new()
	var session = SessionScript.new()
	# Match the EditorPlugin lifecycle: set_session can happen before the Dock
	# enters the tree and before _ready() builds the controls.
	dock.set_status_message("before-ready", false)
	dock.set_session(session)
	get_root().add_child(dock)
	await process_frame
	var play_button := dock.find_child("BakeAndPlayButton", true, false) as Button
	_expect(play_button != null, "dock: Bake & Play button should be created")
	if play_button != null:
		_expect(play_button.text == "Bake & Play", "dock: button label should be stable")
		dock.play_requested.connect(_on_play_requested)
		play_button.pressed.emit()
		_expect(_play_signal_count == 1, "dock: button should emit play_requested once")

	_expect(play_button == null or play_button.disabled, "dock: no Author should disable Bake & Play")
	var scroll := dock.find_child("TacticalMapDockScroll", true, false) as ScrollContainer
	var content := dock.find_child("TacticalMapDockContent", true, false) as VBoxContainer
	_expect(scroll != null, "dock: main content should be hosted in a ScrollContainer")
	_expect(content != null and content.get_parent() == scroll, "dock: scroll container should own the complete content stack")
	_expect(dock.find_child("ToolOption", true, false) != null and dock.find_child("DebugViewOption", true, false) != null and dock.find_child("ValidationList", true, false) != null, "dock: key controls should remain reachable inside the scroll content")
	var tool_option := dock.find_child("ToolOption", true, false) as OptionButton
	var has_select_tool := false
	var select_index := -1
	if tool_option != null:
		for index in range(tool_option.item_count):
			if tool_option.get_item_id(index) == SessionScript.Tool.SELECT:
				has_select_tool = true
				select_index = index
		_expect(has_select_tool, "dock: Select tool should be appended without changing legacy tool IDs")
		_expect(select_index >= 0 and tool_option.get_item_id(select_index) == SessionScript.Tool.SELECT, "dock: Select option should carry the stable Session enum value")
	var debug_option := dock.find_child("DebugViewOption", true, false) as OptionButton
	_expect(debug_option != null, "dock: debug view selector should be present")
	if debug_option != null:
		for view in range(SessionScript.DebugView.NORMAL, SessionScript.DebugView.VALIDATION + 1):
			var view_count := 0
			for index in range(debug_option.item_count):
				if debug_option.get_item_id(index) == view:
					view_count += 1
			_expect(view_count == 1, "dock: each stable debug view should appear exactly once")
	var debug_legend := dock.find_child("DebugLegend", true, false) as Label
	_expect(debug_legend != null and not debug_legend.text.is_empty(), "dock: debug view should expose a legend")
	var default_scope := dock.find_child("DefaultPropertyScope", true, false) as Label
	_expect(default_scope != null and default_scope.text.contains("影响所有未覆盖实例"), "dock: default property panel should explain its global scope")
	_expect(dock.find_child("DefaultWrite_MOVE_COST", true, false) != null, "dock: default property panel should expose a write action")
	var validation_list := dock.find_child("ValidationList", true, false) as ItemList
	_expect(validation_list != null, "dock: structured validation list should be present")
	if validation_list != null:
		dock.validation_location_requested.connect(_on_validation_location_requested)
		dock.set_validation_diagnostics([
			{&"severity": &"error", &"code": &"T-1", &"message": "带坐标错误", &"has_coordinate": true, &"coordinate": Vector3i(0, 0, 0)},
			{&"severity": &"warning", &"code": &"T-2", &"message": "全局警告", &"has_coordinate": false, &"coordinate": null},
		])
		_expect(validation_list.item_count == 2, "dock: all structured diagnostics should be listed")
		_expect(not validation_list.is_item_disabled(0) and validation_list.is_item_disabled(1), "dock: only coordinate diagnostics should be locatable")
		dock.call("_on_validation_item_selected", 0)
		_expect(_location_signal_count == 1, "dock: coordinate diagnostic selection should emit a location request")
		dock.call("_on_validation_item_selected", 1)
		_expect(_location_signal_count == 1, "dock: coordinate-less diagnostic must not emit a location request")
	var property_panel := dock.find_child("CellPropertyPanel", true, false)
	_expect(property_panel != null, "dock: cell property panel should be present")
	var property_selection_label := dock.find_child("PropertySelectionLabel", true, false) as Label
	_expect(property_selection_label != null and property_selection_label.text == "未选择地格", "dock: property panel should explain that no cell is selected")
	var property_write_button := dock.find_child("PropertyWrite_WALKABLE", true, false) as Button
	_expect(property_write_button != null and property_write_button.disabled, "dock: property edits should be disabled without a selected cell")
	var sight_field := dock.find_child("PropertyField_SIGHT_BLOCK", true, false) as Label
	var projectile_field := dock.find_child("PropertyField_PROJECTILE_BLOCK", true, false) as Label
	var sight_editor := dock.find_child("PropertyEditor_SIGHT_BLOCK", true, false) as SpinBox
	var projectile_editor := dock.find_child("PropertyEditor_PROJECTILE_BLOCK", true, false) as SpinBox
	_expect(sight_field != null and sight_field.text == "视线阻挡", "dock: property field should use the formal descriptor label")
	_expect(projectile_field != null and projectile_field.text == "弹道阻挡", "dock: projectile field should use the formal descriptor label")
	_expect(sight_editor != null and is_equal_approx(sight_editor.step, 0.01), "dock: sight-block editor should use the formal descriptor step")
	_expect(projectile_editor != null and is_equal_approx(projectile_editor.step, 0.01), "dock: projectile-block editor should use the formal descriptor step")
	var descriptor_probe := SpinBox.new()
	dock.call("_apply_default_editor_descriptor", descriptor_probe, {&"min": 0.0, &"max": 1.0, &"step": 1.0, &"allowed_values": [0.0, 1.0]})
	_expect(descriptor_probe.tooltip_text.contains("允许值"), "dock: legacy descriptor should expose its binary constraint")
	dock.call("_apply_default_editor_descriptor", descriptor_probe, {&"min": 0.0, &"max": 1.0, &"step": 0.01})
	_expect(is_equal_approx(descriptor_probe.step, 0.01) and descriptor_probe.tooltip_text.is_empty(), "dock: formal descriptor should clear legacy binary tooltip and restore its step")
	descriptor_probe.free()
	_expect(dock.find_child("PropertyBase_MOVE_COST", true, false) != null, "dock: property panel should expose the default value column")
	_expect(dock.find_child("PropertyOverride_MOVE_COST", true, false) != null, "dock: property panel should expose the override value column")
	_expect(dock.find_child("PropertyValue_MOVE_COST", true, false) != null, "dock: property panel should expose the final value column")
	# Simulate a hot-reloaded Dock whose new Phase-C fields were not restored on
	# the existing instance. _refresh must recover controls without duplicating
	# legacy controls or the Select item.
	dock.set("_play_button", null)
	if tool_option != null:
		for index in range(tool_option.item_count - 1, -1, -1):
			if tool_option.get_item_id(index) == SessionScript.Tool.SELECT:
				tool_option.remove_item(index)
	dock.set("_tool_option", null)
	dock.set("_property_panel", null)
	dock.set("_property_selection_label", null)
	dock.set("_debug_option", null)
	dock.set("_scroll", null)
	var old_property_panel := dock.find_child("CellPropertyPanel", true, false)
	if old_property_panel != null:
		old_property_panel.free()
	dock.call("_refresh")
	var recovered_button := dock.find_child("BakeAndPlayButton", true, false) as Button
	_expect(recovered_button != null and recovered_button.disabled, "dock: refresh should recover a stale play-button field")
	var recovered_tool_option := dock.find_child("ToolOption", true, false) as OptionButton
	var select_count := 0
	if recovered_tool_option != null:
		for index in range(recovered_tool_option.item_count):
			if recovered_tool_option.get_item_id(index) == SessionScript.Tool.SELECT:
				select_count += 1
	_expect(select_count == 1, "dock: hot reload should add exactly one Select item")
	_expect(dock.find_child("CellPropertyPanel", true, false) != null and dock.find_child("PropertyWrite_MOVE_COST", true, false) != null, "dock: refresh should rebuild missing Phase-C property controls")
	var recovered_scroll := dock.find_child("TacticalMapDockScroll", true, false) as ScrollContainer
	var recovered_content := dock.find_child("TacticalMapDockContent", true, false) as VBoxContainer
	_expect(recovered_scroll != null and recovered_content != null and recovered_content.get_parent() == recovered_scroll, "dock: hot reload should restore the scroll wrapper without losing content")
	var recovered_debug_option := dock.find_child("DebugViewOption", true, false) as OptionButton
	var recovered_debug_count := 0
	if recovered_debug_option != null:
		for index in range(recovered_debug_option.item_count):
			if recovered_debug_option.get_item_id(index) == SessionScript.DebugView.VALIDATION:
				recovered_debug_count += 1
	_expect(recovered_debug_option != null and recovered_debug_count == 1, "dock: refresh should recover the debug selector without duplicate items")
	var removed_property_button := dock.find_child("PropertyWrite_MOVE_COST", true, false)
	if removed_property_button != null:
		removed_property_button.free()
	dock.call("_refresh")
	_expect(dock.find_child("PropertyWrite_MOVE_COST", true, false) != null, "dock: refresh should restore a missing individual property control")
	var second_select_count := 0
	if recovered_tool_option != null:
		for index in range(recovered_tool_option.item_count):
			if recovered_tool_option.get_item_id(index) == SessionScript.Tool.SELECT:
				second_select_count += 1
	_expect(second_select_count == 1, "dock: repeated Phase-C refresh must not duplicate Select")
	var status_label := dock.find_child("StatusLabel", true, false) as Label
	_expect(status_label != null, "dock: status label should be available after ready")
	if status_label != null:
		dock.set_status_message("ready-error", false)
		_expect(status_label.text == "ready-error", "dock: public status API should update text")
		_expect(status_label.modulate == Color("ff8c8c"), "dock: invalid status should use error color")
		dock.set_status_message("ready-ok", true)
		_expect(status_label.text == "ready-ok", "dock: public status API should update valid text")
		_expect(status_label.modulate == Color("8fe388"), "dock: valid status should use success color")
	dock.free()
	_finish()


func _on_play_requested() -> void:
	_play_signal_count += 1


func _on_validation_location_requested(_diagnostic: Dictionary) -> void:
	_location_signal_count += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_MAP_EDITOR_DOCK_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_MAP_EDITOR_DOCK_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
