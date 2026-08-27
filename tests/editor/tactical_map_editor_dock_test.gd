extends SceneTree

## Pure Dock wiring coverage. It exercises the code-built control only and
## never loads a map scene or invokes authoring/bake data.

const DockScript = preload("res://addons/tactical_map_editor/ui/tactical_map_dock.gd")
const SessionScript = preload("res://addons/tactical_map_editor/editing/map_edit_session.gd")
const FormalSpecialStateSessionScript = preload("res://tests/editor/formal_special_state_session_stub.gd")

var _failures: Array[String] = []
var _play_signal_count: int = 0
var _add_signal_count: int = 0
var _location_signal_count: int = 0
var _special_finish_signal_count: int = 0


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
	var add_button := dock.find_child("AddPlaceableButton", true, false) as Button
	_expect(add_button != null and add_button.text == "添加素材", "dock: Add Placeable button should be visible")
	if add_button != null:
		dock.add_placeable_requested.connect(_on_add_placeable_requested)
		add_button.pressed.emit()
		_expect(_add_signal_count == 1, "dock: Add Placeable button should emit once")
	var edit_toggle := dock.find_child("EditModeToggle", true, false) as CheckButton
	_expect(edit_toggle != null and edit_toggle.text.contains("M"), "dock: edit toggle should expose the M shortcut")
	_expect(edit_toggle != null and edit_toggle.tooltip_text.contains("M") and edit_toggle.tooltip_text.contains("3D"), "dock: edit toggle tooltip should scope M to the 3D viewport")
	var navigation_hint := dock.find_child("NavigationHint", true, false) as Label
	_expect(navigation_hint != null, "dock: narrow-width navigation hint should be present")
	if navigation_hint != null:
		_expect(navigation_hint.autowrap_mode != TextServer.AUTOWRAP_OFF, "dock: navigation hint should wrap in a narrow Dock")
		_expect(navigation_hint.text.contains("RMB") and navigation_hint.text.contains("WASD") and navigation_hint.text.contains("MMB"), "dock: navigation hint should describe Godot viewport controls")
		_expect(navigation_hint.text.contains("擦除工具") and navigation_hint.text.contains("Ctrl"), "dock: navigation hint should describe both erase gestures")
	_expect(dock.custom_minimum_size.x <= 0.0, "dock: layout should not impose a hard minimum width")

	_expect(play_button == null or play_button.disabled, "dock: no Author should disable Bake & Play")
	_expect(edit_toggle == null or edit_toggle.disabled, "dock: no selected root should disable edit mode")
	var selection_label := dock.find_child("SelectionLabel", true, false) as Label
	_expect(selection_label != null and selection_label.text.contains("地图根节点"), "dock: no selected root should show the scene-tree requirement")
	var target_option := dock.find_child("TargetLayerOption", true, false) as OptionButton
	var expected_layers := ["Floor", "Structure", "Decoration", "Traversal", "Spawner", "Object", "AI"]
	_expect(target_option != null and target_option.item_count == expected_layers.size(), "dock: target layer selector should expose all seven ordered layers")
	if target_option != null:
		for layer_index in range(expected_layers.size()):
			_expect(target_option.get_item_id(layer_index) == layer_index and target_option.get_item_text(layer_index) == expected_layers[layer_index], "dock: target layer %d should keep stable ID and label" % layer_index)

	# Exercise palette filtering without a map scene. This mirrors both the
	# legacy one-argument Session API and the future layer-filtered API through
	# the same Dock path.
	var palette_fixture := [
		{&"id": "fixture.floor", &"label": "Fixture Floor", &"category": "Floor", &"kind": "cell", &"layer": 0},
		{&"id": "fixture.structure", &"label": "Fixture Structure", &"category": "Structure", &"kind": "cell", &"layer": 1},
		{&"id": "fixture.traversal", &"label": "Fixture Traversal", &"category": "Traversal", &"kind": "traversal", &"layer": 3},
		{&"id": "fixture.spawner", &"label": "Fixture Spawner", &"category": "Spawner", &"kind": "spawn", &"layer": 4},
		{&"id": "fixture.object", &"label": "Fixture Object", &"category": "Object", &"kind": "object", &"layer": 5},
		{&"id": "fixture.ai", &"label": "Fixture AI", &"category": "AI", &"kind": "ai", &"layer": 6},
	]
	session.placeables = palette_fixture
	session.selected_placeable = {&"id": "fixture.structure", &"layer": 1}
	session.target_layer = 0
	dock.set_session(session)
	var palette := dock.find_child("Palette", true, false) as ItemList
	_expect(palette != null and palette.item_count == 1 and palette.get_item_text(0) == "Fixture Floor", "dock: Floor palette should hide non-Floor entities")
	_expect(palette == null or palette.get_selected_items().is_empty(), "dock: selection from another layer must not be highlighted")
	session.target_layer = 4
	dock.call("_refresh")
	_expect(palette != null and palette.item_count == 1 and palette.get_item_text(0) == "Fixture Spawner", "dock: Spawner palette should show only spawner entries")
	if palette != null:
		var search := dock.find_child("PlaceableSearch", true, false) as LineEdit
		if search != null:
			search.text = "fixture"
			_expect(palette.item_count == 1 and palette.get_item_text(0) == "Fixture Spawner", "dock: palette search must remain scoped to the active layer")
			search.text = ""
	session.placeables = []
	session.selected_placeable.clear()
	session.target_layer = 0
	dock.set_session(session)
	var scroll := dock.find_child("TacticalMapDockScroll", true, false) as ScrollContainer
	var content := dock.find_child("TacticalMapDockContent", true, false) as VBoxContainer
	_expect(scroll != null, "dock: main content should be hosted in a ScrollContainer")
	_expect(scroll == null or scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "dock: main content must not require horizontal scrolling")
	_expect(content != null and content.get_parent() == scroll, "dock: scroll container should own the complete content stack")
	_expect(dock.find_child("ToolOption", true, false) != null and dock.find_child("DebugViewOption", true, false) != null and dock.find_child("ValidationList", true, false) != null, "dock: key controls should remain reachable inside the scroll content")
	var special_panel := dock.find_child("SpecialEditPanel", true, false) as VBoxContainer
	var finish_special := dock.find_child("FinishSpecialEditButton", true, false) as Button
	_expect(special_panel != null and finish_special != null and finish_special.disabled, "dock: special-edit state area should be visible and safely disabled without the new Session API")
	# The production Session uses the formal kind/pending/active/... contract.
	# Drive it through a map-free subclass so stale legacy-key handling cannot
	# hide a real pending traversal or patrol route in the Dock.
	var formal_special_session = FormalSpecialStateSessionScript.new()
	formal_special_session.formal_state = {
		&"kind": &"traversal",
		&"pending": true,
		&"active": false,
		&"active_route_id": &"",
		&"pending_from": Vector3i(2, 0, 3),
		&"can_finish": true,
		&"label": "正式连接等待",
	}
	dock.special_edit_finish_requested.connect(_on_special_finish_requested)
	dock.set_session(formal_special_session)
	await process_frame
	var formal_state_label := dock.find_child("SpecialEditStateLabel", true, false) as Label
	_expect(formal_state_label != null and formal_state_label.text == "正式连接等待", "dock: formal pending traversal label should be shown")
	_expect(finish_special != null and not finish_special.disabled and finish_special.text == "取消连接等待", "dock: formal pending traversal should enable the cancel action")
	if finish_special != null:
		finish_special.pressed.emit()
		_expect(_special_finish_signal_count == 1, "dock: formal traversal action should emit the finish signal once")
	formal_special_session.formal_state = {
		&"kind": &"patrol",
		&"pending": false,
		&"active": true,
		&"active_route_id": &"route.formal",
		&"pending_from": Vector3i(-1, -1, -1),
		&"can_finish": true,
		&"label": "正式巡逻路线",
	}
	formal_special_session.changed.emit()
	await process_frame
	_expect(formal_state_label != null and formal_state_label.text == "正式巡逻路线", "dock: formal active patrol label should be shown")
	_expect(finish_special != null and not finish_special.disabled and finish_special.text == "结束当前巡逻路线", "dock: formal active patrol should enable the finish action")
	if finish_special != null:
		finish_special.pressed.emit()
		_expect(_special_finish_signal_count == 2, "dock: formal patrol action should emit the finish signal once")
	dock.set_session(session)
	_expect(dock.find_child("SpawnConfigurationPanel", true, false) != null and dock.find_child("ApplySpawnConfigurationButton", true, false) != null, "dock: spawn configuration controls should remain reachable")
	session.placeables = [{&"id": "spawn.synthetic", &"label": "Synthetic Spawn", &"kind": "spawn", &"faction": "enemy", &"archetype": null, &"weapon": null, &"encounter_id": &"", &"patrol_route_id": &""}]
	session.select_placeable(0)
	dock.set_session(session)
	await process_frame
	var spawn_panel := dock.find_child("SpawnConfigurationPanel", true, false) as VBoxContainer
	var encounter_edit := dock.find_child("SpawnEncounterIdEdit", true, false) as LineEdit
	var apply_spawn := dock.find_child("ApplySpawnConfigurationButton", true, false) as Button
	_expect(spawn_panel != null and spawn_panel.visible and encounter_edit != null and apply_spawn != null, "dock: selecting a spawn should reveal template configuration controls")
	if encounter_edit != null and apply_spawn != null:
		encounter_edit.text = "encounter.synthetic"
		apply_spawn.pressed.emit()
		_expect(String(session.get_selected_placeable().get("encounter_id", "")) == "encounter.synthetic", "dock: spawn template Apply should call Session configuration API")
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
		for view in range(SessionScript.DebugView.NORMAL, SessionScript.DebugView.COVER + 1):
			var view_count := 0
			for index in range(debug_option.item_count):
				if debug_option.get_item_id(index) == view:
					view_count += 1
			_expect(view_count == 1, "dock: each stable debug view should appear exactly once")
	var debug_legend := dock.find_child("DebugLegend", true, false) as Label
	_expect(debug_legend != null and not debug_legend.text.is_empty(), "dock: debug view should expose a legend")
	if debug_option != null:
		var cover_index := -1
		for index in range(debug_option.item_count):
			if debug_option.get_item_id(index) == SessionScript.DebugView.COVER:
				cover_index = index
		_expect(cover_index >= 0 and debug_option.get_item_text(cover_index).contains("掩体"), "dock: Cover debug view should be visible with a Chinese label")
	session.set_debug_view(SessionScript.DebugView.COVER)
	dock.call("_refresh")
	_expect(debug_legend != null and debug_legend.text.contains("掩体"), "dock: Cover view should expose a Chinese legend")
	var cover_inspection_panel := dock.find_child("CoverInspectionPanel", true, false) as VBoxContainer
	var cover_inspection_summary := dock.find_child("CoverInspectionSummary", true, false) as Label
	var cover_inspection_details := dock.find_child("CoverInspectionDetails", true, false) as Label
	var clear_cover_edge_button := dock.find_child("ClearCoverEdgeButton", true, false) as Button
	_expect(cover_inspection_panel != null and cover_inspection_panel.visible, "dock: Cover view should reveal the cover edge inspector")
	_expect(cover_inspection_summary != null and cover_inspection_summary.text == "未选中掩体边", "dock: cover inspector should explain that no edge is selected")
	_expect(cover_inspection_details != null and cover_inspection_details.text.contains("左键点击掩体边"), "dock: empty cover inspector should describe the selection gesture")
	_expect(clear_cover_edge_button != null and clear_cover_edge_button.disabled, "dock: clear cover edge should be disabled without a selection")
	var inspection_text := String(dock.call("_format_cover_edge_inspection", {
		&"cell_a": Vector3i(1, 0, 2),
		&"cell_b": Vector3i(2, 0, 2),
		&"source_cell": Vector3i(1, 0, 2),
		&"source_type": &"structure_derived",
		&"source_layer": &"structure",
		&"source_placeable_id": &"tile.cover.synthetic",
		&"source_mesh_item_id": 4,
		&"profile_a": {&"id": &"cover.none", &"level_name": "NONE", &"reduction": 0.0},
		&"profile_b": {&"id": &"cover.half", &"level_name": "HALF", &"reduction": 0.5},
		&"blocks_movement": true,
		&"sight_block": 1.0,
		&"projectile_block": 0.75,
		&"height": 1.0,
		&"destructible": false,
	}))
	_expect(inspection_text.contains("来源地块：(1, 0, 2)") and inspection_text.contains("Structure 地块自动派生"), "dock: cover inspector should show source provenance")
	_expect(inspection_text.contains("A 侧 Profile") and inspection_text.contains("减伤 50%"), "dock: cover inspector should show both Profile and reduction")
	_expect(inspection_text.contains("移动阻挡：是") and inspection_text.contains("投射物阻挡：0.75"), "dock: cover inspector should show blocking properties")
	session.set_debug_view(SessionScript.DebugView.NORMAL)
	_expect(cover_inspection_panel != null and not cover_inspection_panel.visible, "dock: cover inspector should hide outside Cover view")
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
	# Simulate a hot-reloaded Dock whose new Phase-C fields were not restored on
	# the existing instance. _refresh must recover controls without duplicating
	# legacy controls or the Select item.
	dock.set("_play_button", null)
	if tool_option != null:
		for index in range(tool_option.item_count - 1, -1, -1):
			if tool_option.get_item_id(index) == SessionScript.Tool.SELECT:
				tool_option.remove_item(index)
	dock.set("_tool_option", null)
	dock.set("_debug_option", null)
	dock.set("_scroll", null)
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
	dock.call("_refresh")
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


func _on_add_placeable_requested() -> void:
	_add_signal_count += 1


func _on_validation_location_requested(_diagnostic: Dictionary) -> void:
	_location_signal_count += 1


func _on_special_finish_requested() -> void:
	_special_finish_signal_count += 1


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
