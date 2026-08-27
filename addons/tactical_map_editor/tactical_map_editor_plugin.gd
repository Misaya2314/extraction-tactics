@tool
extends EditorPlugin

const SESSION_SCRIPT := preload("res://addons/tactical_map_editor/editing/map_edit_session.gd")
const TARGET_SCRIPT := preload("res://addons/tactical_map_editor/editing/placement_target.gd")
const INPUT_STRATEGY := preload("res://addons/tactical_map_editor/editing/tactical_map_input_strategy.gd")
const DOCK_SCRIPT := preload("res://addons/tactical_map_editor/ui/tactical_map_dock.gd")
const WIZARD_SCRIPT := preload("res://addons/tactical_map_editor/ui/tactical_placeable_wizard.gd")
const PLACEABLE_SERVICE := preload("res://addons/tactical_map_editor/content/tactical_placeable_wizard_service.gd")
const NEW_MAP_DIALOG_SCRIPT := preload("res://addons/tactical_map_editor/ui/tactical_new_map_dialog.gd")
const PREVIEW_BUILDER := preload("res://addons/tactical_map_editor/preview/tactical_preview_builder.gd")
const AUTHOR_SCRIPT_PATH := "res://scripts/map_authoring/tactical_map_author.gd"

var _dock: TacticalMapDock
var _session: TacticalMapEditSession
var _selection: EditorSelection
var _resource_filesystem: EditorFileSystem
var _active_author: Node
var _preview_root: Node3D
var _preview_mesh: MeshInstance3D
var _selection_overlay_root: Node3D
var _selection_overlay: MultiMeshInstance3D
var _box_overlay_root: Node3D
var _box_overlay: MeshInstance3D
var _debug_overlay_root: Node3D
var _debug_overlay: MultiMeshInstance3D
var _cover_overlay_root: Node3D
var _special_overlay_root: Node3D
var _wizard: TacticalPlaceableWizard
var _placeable_file_dialog: FileDialog
var _new_map_dialog: TacticalNewMapDialog
var _last_preview_target: TacticalPlacementTarget
var _drag_button: int = 0
var _box_drag_active: bool = false
var _box_erase_mode: bool = false
var _box_anchor_cell: Vector3i = Vector3i.ZERO
var _box_current_cell: Vector3i = Vector3i.ZERO
var _temporary_erase_restore_tool: int = -1
var _temporary_erase_active: bool = false
enum SelectionDragMode {
	NONE,
	RECTANGLE,
	MOVE,
}
var _selection_drag_active: bool = false
var _selection_drag_mode: int = SelectionDragMode.NONE
var _selection_drag_start_cell: Vector3i = Vector3i.ZERO
var _selection_drag_current_cell: Vector3i = Vector3i.ZERO
var _selection_drag_additive: bool = false
var _selection_drag_toggle: bool = false
var _selection_drag_preview_delta: Vector3i = Vector3i.ZERO
var _selection_rect_drag_active: bool = false
var _bake_and_play_in_progress: bool = false
var _selection_clear_in_progress: bool = false
var _library_repair_in_progress: bool = false

func _enter_tree() -> void:
	_session = SESSION_SCRIPT.new()
	_dock = DOCK_SCRIPT.new()
	_dock.name = "TacticalMapBuilder"
	_dock.set_session(_session)
	_session.changed.connect(_on_session_changed)
	_dock.edit_mode_changed.connect(_on_edit_mode_changed)
	_dock.floor_changed.connect(_on_floor_changed)
	_dock.target_layer_changed.connect(_on_target_layer_changed)
	_dock.tool_changed.connect(_on_tool_changed)
	_dock.rotate_requested.connect(_on_rotate_requested)
	_dock.selection_replace_requested.connect(_on_selection_replace_requested)
	_dock.selection_rotate_requested.connect(_on_selection_rotate_requested)
	_dock.selection_delete_requested.connect(_on_selection_delete_requested)
	_dock.selection_copy_requested.connect(_on_selection_copy_requested)
	_dock.selection_paste_requested.connect(_on_selection_paste_requested)
	_dock.placeable_selected.connect(_on_placeable_selected)
	_dock.validate_requested.connect(_validate_author)
	_dock.bake_requested.connect(_bake_author)
	_dock.save_requested.connect(_save_scene)
	_dock.play_requested.connect(_bake_and_play)
	_dock.add_placeable_requested.connect(_open_placeable_wizard)
	_dock.new_map_requested.connect(_open_new_map_dialog)
	_dock.special_edit_finish_requested.connect(_finish_special_edit)
	_dock.debug_view_changed.connect(_on_debug_view_changed)
	_dock.validation_location_requested.connect(_on_validation_location_requested)
	set_input_event_forwarding_always_enabled()
	set_process(true)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_selection = get_editor_interface().get_selection()
	if _selection != null:
		_selection.selection_changed.connect(_on_selection_changed)
	_resource_filesystem = get_editor_interface().get_resource_filesystem()
	if _resource_filesystem != null and not _resource_filesystem.filesystem_changed.is_connected(_on_resource_filesystem_changed):
		_resource_filesystem.filesystem_changed.connect(_on_resource_filesystem_changed)
	_on_selection_changed()

func _exit_tree() -> void:
	set_process(false)
	_cancel_active_edit_input()
	_clear_preview()
	_clear_selection_overlay()
	_clear_box_overlay()
	_clear_debug_overlay()
	_clear_cover_overlay()
	_clear_special_overlay()
	if _wizard != null and is_instance_valid(_wizard):
		_wizard.queue_free()
		_wizard = null
	if _placeable_file_dialog != null and is_instance_valid(_placeable_file_dialog):
		_placeable_file_dialog.queue_free()
		_placeable_file_dialog = null
	if _new_map_dialog != null and is_instance_valid(_new_map_dialog):
		_new_map_dialog.queue_free()
	_new_map_dialog = null
	if _selection != null and _selection.selection_changed.is_connected(_on_selection_changed):
		_selection.selection_changed.disconnect(_on_selection_changed)
	if _resource_filesystem != null and _resource_filesystem.filesystem_changed.is_connected(_on_resource_filesystem_changed):
		_resource_filesystem.filesystem_changed.disconnect(_on_resource_filesystem_changed)
	_resource_filesystem = null
	if _session != null:
		if _session.changed.is_connected(_on_session_changed):
			_session.changed.disconnect(_on_session_changed)
		_session.cancel_stroke()
	_bake_and_play_in_progress = false
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
	_dock = null
	_session = null
	_active_author = null

func _process(_delta: float) -> void:
	if _session == null or not _session.edit_mode:
		return
	if not _is_locked_edit_valid():
		_exit_edit_mode("地图作者或编辑场景已改变，编辑模式已关闭。")


func _on_resource_filesystem_changed() -> void:
	if _library_repair_in_progress or _session == null or not _session.has_author():
		return
	var author := _session.author
	var library := author.get("placeable_library") as TacticalPlaceableLibrary if author != null else null
	if library == null:
		return
	_library_repair_in_progress = true
	var repair: Dictionary = PLACEABLE_SERVICE.repair_library(library)
	_library_repair_in_progress = false
	if not bool(repair.get(&"changed", false)):
		return
	if _session.has_method("reload_placeables"):
		_session.call("reload_placeables", true)
	var removed_definitions := int(repair.get(&"removed_definition_count", 0))
	var removed_bindings := int(repair.get(&"removed_binding_count", 0))
	var summary := "已删除素材 %d 个、失效绑定 %d 个" % [removed_definitions, removed_bindings]
	var errors: Array = repair.get(&"errors", [])
	if not bool(repair.get(&"valid", false)):
		_dock.set_status_message("检测到素材库悬空引用，已从当前编辑器清理%s，但保存失败：%s" % [summary, "；".join(errors)], false)
		return
	_dock.set_status_message("检测到素材文件被删除，已自动从素材库移除%s。" % summary, true)

func _handles(object: Object) -> bool:
	return _find_author(object) != null

func _edit(object: Object) -> void:
	var selected_author := _find_author(object)
	if selected_author != null:
		_activate_author(selected_author)

func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if _session == null:
		return AFTER_GUI_INPUT_PASS
	if _session.edit_mode:
		if not _is_locked_edit_valid():
			_exit_edit_mode("地图作者或编辑场景已改变，编辑模式已关闭。")
			return AFTER_GUI_INPUT_PASS
	else:
		# Before editing, only a selected scene root can start the mode.  This
		# gate also lets M bind a root whose selection signal is still settling.
		# An already-bound author (edit mode off) is allowed through so M can
		# re-enter the mode without re-selecting the root.
		if _selected_scene_root_author() == null and not _session.has_author():
			return AFTER_GUI_INPUT_PASS

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		var key_action := INPUT_STRATEGY.classify_key(key_event, true, _session.edit_mode)
		if key_action == INPUT_STRATEGY.Action.TOGGLE_EDIT_MODE:
			_request_edit_mode(not _session.edit_mode)
			return AFTER_GUI_INPUT_STOP
		if not _session.edit_mode:
			return AFTER_GUI_INPUT_PASS
		if key_action == INPUT_STRATEGY.Action.ROTATE:
			if _session.tool == TacticalMapEditSession.Tool.SELECT:
				_session.selection_rotate(get_undo_redo())
			else:
				_session.rotate_selection()
			return AFTER_GUI_INPUT_STOP
		if key_action == INPUT_STRATEGY.Action.CANCEL:
			_cancel_active_edit_input()
			_session.cancel_stroke()
			_session.clear_selection()
			_clear_preview()
			_update_selection_overlay()
			return AFTER_GUI_INPUT_STOP
		return AFTER_GUI_INPUT_PASS

	if not _session.edit_mode:
		return AFTER_GUI_INPUT_PASS
	if viewport_camera == null:
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if INPUT_STRATEGY.is_native_navigation_event(motion):
			# Let Godot's 3D editor consume RMB/MMB navigation and all native
			# modifiers.  A ghost under the moving camera is misleading, so pause
			# it until the next ordinary cursor motion.
			_clear_preview()
			return AFTER_GUI_INPUT_PASS
		var box_target_tool := TacticalMapEditSession.Tool.ERASE if _box_drag_active and _box_erase_mode else -1
		var target := _target_from_screen(viewport_camera, motion.position, box_target_tool)
		if _session.tool == TacticalMapEditSession.Tool.SELECT:
			_clear_preview()
		else:
			_update_preview(target)
		if _box_drag_active:
			if target.valid:
				_box_current_cell = target.cell
			_update_box_overlay(_box_anchor_cell, _box_current_cell, target.valid)
			return AFTER_GUI_INPUT_STOP
		if _selection_drag_active:
			return _update_selection_drag(target)
		if _drag_button != 0:
			if target.valid:
				_session.apply_at(target.cell)
			return AFTER_GUI_INPUT_STOP
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		var mouse_action := INPUT_STRATEGY.classify_mouse_button(mouse, true, _session.tool, TacticalMapEditSession.Tool.SELECT, TacticalMapEditSession.Tool.PICK)
		if mouse_action == INPUT_STRATEGY.Action.NATIVE_NAVIGATION:
			_clear_preview()
			return AFTER_GUI_INPUT_PASS
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if not mouse.pressed and _box_drag_active:
				return _finish_box_paint(viewport_camera, mouse)
			if not mouse.pressed and _selection_drag_active:
				return _finish_selection_drag(viewport_camera, mouse)
			if mouse.pressed:
				if _session.tool == TacticalMapEditSession.Tool.BOX_PAINT:
					var is_box_erase := mouse.ctrl_pressed
					var requested_tool := TacticalMapEditSession.Tool.ERASE if is_box_erase else TacticalMapEditSession.Tool.BOX_PAINT
					var box_left_target := _target_from_screen(viewport_camera, mouse.position, requested_tool)
					_update_preview(box_left_target)
					if not box_left_target.valid:
						_session.set_status_message(box_left_target.reason, false)
						return AFTER_GUI_INPUT_STOP
					return _begin_box_paint(box_left_target, is_box_erase)
				if mouse_action == INPUT_STRATEGY.Action.LEFT_TEMP_ERASE:
					return _begin_temporary_erase(viewport_camera, mouse)
				var left_target := _target_from_screen(viewport_camera, mouse.position)
				if mouse_action == INPUT_STRATEGY.Action.LEFT_SELECT:
					if not _selection_target_has_cell_position(left_target):
						_session.set_status_message(left_target.reason, false)
						return AFTER_GUI_INPUT_STOP
					_clear_preview()
					return _begin_selection_drag(left_target, mouse)
				_update_preview(left_target)
				if not left_target.valid:
					_session.set_status_message(left_target.reason, false)
					return AFTER_GUI_INPUT_STOP
				if mouse_action == INPUT_STRATEGY.Action.LEFT_PICK:
					_session.pick_at(left_target.cell)
					return AFTER_GUI_INPUT_STOP
				_drag_button = MOUSE_BUTTON_LEFT
				_session.begin_stroke(_session.tool_name())
				_session.apply_at(left_target.cell)
				return AFTER_GUI_INPUT_STOP
			if _drag_button == MOUSE_BUTTON_LEFT:
				_drag_button = 0
				_session.finish_stroke(get_undo_redo())
				_restore_temporary_erase_tool()
				return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS

func _begin_temporary_erase(viewport_camera: Camera3D, mouse: InputEventMouseButton) -> int:
	var erase_target := _target_from_screen(viewport_camera, mouse.position, TacticalMapEditSession.Tool.ERASE)
	_update_preview(erase_target)
	if not erase_target.valid:
		_session.set_status_message(erase_target.reason, false)
		return AFTER_GUI_INPUT_STOP
	_temporary_erase_restore_tool = _session.tool
	_temporary_erase_active = true
	_session.set_tool(TacticalMapEditSession.Tool.ERASE)
	_drag_button = MOUSE_BUTTON_LEFT
	_session.begin_stroke("擦除")
	_session.apply_at(erase_target.cell)
	return AFTER_GUI_INPUT_STOP

func _begin_box_paint(target: TacticalPlacementTarget, is_erase: bool = false) -> int:
	_box_drag_active = true
	_box_erase_mode = is_erase
	_box_anchor_cell = target.cell
	_box_current_cell = target.cell
	_session.begin_stroke("框选擦除" if is_erase else "框选绘制")
	_update_box_overlay(_box_anchor_cell, _box_current_cell, true)
	return AFTER_GUI_INPUT_STOP

func _finish_box_paint(viewport_camera: Camera3D, mouse: InputEventMouseButton) -> int:
	var is_erase := _box_erase_mode or mouse.ctrl_pressed
	var requested_tool := TacticalMapEditSession.Tool.ERASE if is_erase else TacticalMapEditSession.Tool.BOX_PAINT
	var target := _target_from_screen(viewport_camera, mouse.position, requested_tool)
	if target.valid:
		_box_current_cell = target.cell
	_update_box_overlay(_box_anchor_cell, _box_current_cell, target.valid)
	_box_drag_active = false
	# Allow mid-drag Ctrl toggle: keep stroke label in sync with final mode.
	var expected_label := "框选擦除" if is_erase else "框选绘制"
	if _session.stroke_active and _session.stroke_label != expected_label:
		_session.stroke_label = expected_label
	_box_erase_mode = false
	_session.apply_rectangle(_box_anchor_cell, _box_current_cell, is_erase)
	_session.finish_stroke(get_undo_redo())
	_clear_box_overlay()
	_clear_preview()
	return AFTER_GUI_INPUT_STOP

func _selection_target_has_cell_position(target: TacticalPlacementTarget) -> bool:
	if target == null or _session == null or not _session.has_author():
		return false
	# A target with a canonical world position came from a successful ray/plane
	# intersection. It may still be invalid for Select because the cell has no
	# Floor; rectangle selection deliberately accepts those coordinates and
	# filters them in Session.
	return target.world_position != Vector3.ZERO and _session._inside_volume(target.cell)


func _begin_selection_drag(target: TacticalPlacementTarget, mouse: InputEventMouseButton) -> int:
	_selection_drag_active = true
	_selection_drag_start_cell = target.cell
	_selection_drag_current_cell = target.cell
	_selection_drag_additive = mouse.shift_pressed
	_selection_drag_toggle = mouse.shift_pressed
	_selection_drag_preview_delta = Vector3i.ZERO
	if _session.is_cell_selected(target.cell) and not mouse.shift_pressed:
		_selection_drag_mode = SelectionDragMode.MOVE
		_update_selection_overlay()
	else:
		_selection_drag_mode = SelectionDragMode.RECTANGLE
		_selection_rect_drag_active = true
		_update_box_overlay(target.cell, target.cell, true)
	return AFTER_GUI_INPUT_STOP


func _update_selection_drag(target: TacticalPlacementTarget) -> int:
	if not _selection_drag_active:
		return AFTER_GUI_INPUT_PASS
	if _selection_target_has_cell_position(target):
		_selection_drag_current_cell = target.cell
		if _selection_drag_mode == SelectionDragMode.MOVE:
			_selection_drag_preview_delta = target.cell - _selection_drag_start_cell
			_update_selection_overlay(_selection_drag_preview_delta)
		else:
			_update_box_overlay(_selection_drag_start_cell, _selection_drag_current_cell, _session._inside_volume(target.cell))
	return AFTER_GUI_INPUT_STOP


func _finish_selection_drag(viewport_camera: Camera3D, mouse: InputEventMouseButton) -> int:
	if not _selection_drag_active:
		return AFTER_GUI_INPUT_PASS
	var target := _target_from_screen(viewport_camera, mouse.position)
	if _selection_target_has_cell_position(target):
		_selection_drag_current_cell = target.cell
	var start_cell := _selection_drag_start_cell
	var end_cell := _selection_drag_current_cell
	var drag_mode := _selection_drag_mode
	var additive := _selection_drag_additive
	var toggle := _selection_drag_toggle
	_reset_selection_drag()
	if drag_mode == SelectionDragMode.MOVE:
		var delta := end_cell - start_cell
		if delta != Vector3i.ZERO:
			_session.selection_move(delta, get_undo_redo())
		_update_selection_overlay()
		_clear_preview()
		return AFTER_GUI_INPUT_STOP
	_clear_box_overlay()
	if start_cell == end_cell:
		_session.select_cell(start_cell, additive, toggle)
	else:
		_session.select_cells_in_rect(start_cell, end_cell, additive, toggle)
	_update_selection_overlay()
	_clear_preview()
	return AFTER_GUI_INPUT_STOP


func _reset_selection_drag() -> void:
	_selection_drag_active = false
	_selection_drag_mode = SelectionDragMode.NONE
	_selection_drag_start_cell = Vector3i.ZERO
	_selection_drag_current_cell = Vector3i.ZERO
	_selection_drag_additive = false
	_selection_drag_toggle = false
	_selection_drag_preview_delta = Vector3i.ZERO
	_selection_rect_drag_active = false


func _restore_temporary_erase_tool() -> void:
	if not _temporary_erase_active:
		_temporary_erase_restore_tool = -1
		return
	var previous_tool := _temporary_erase_restore_tool
	_temporary_erase_active = false
	_temporary_erase_restore_tool = -1
	if _session != null and _session.has_author() and previous_tool >= 0:
		_session.set_tool(previous_tool)

func _cancel_active_edit_input() -> void:
	if _session == null:
		_drag_button = 0
		_reset_selection_drag()
		_clear_box_overlay()
		_box_erase_mode = false
		_temporary_erase_active = false
		_temporary_erase_restore_tool = -1
		return
	if _drag_button == MOUSE_BUTTON_LEFT or _temporary_erase_active:
		_session.cancel_stroke()
	if _box_drag_active:
		_session.cancel_stroke()
		_box_drag_active = false
		_box_erase_mode = false
		_clear_box_overlay()
	if _selection_drag_active:
		_reset_selection_drag()
		_clear_box_overlay()
	_drag_button = 0
	_restore_temporary_erase_tool()

func _on_selection_changed() -> void:
	if _selection == null or _session == null:
		return
	var nodes := _selection.get_selected_nodes()
	if _session.edit_mode:
		if not _is_locked_edit_valid():
			_exit_edit_mode("地图作者或编辑场景已改变，编辑模式已关闭。")
			return
		if not selection_belongs_to_author(nodes, _active_author):
			_exit_edit_mode("已离开当前地图，编辑模式已关闭；请重新选择地图根节点。")
			return
		if _selection_includes_author(nodes, _active_author):
			_clear_editor_selection_for_lock()
		return

	var next_author := _selected_scene_root_author()
	if next_author == null:
		# Keep an already-bound author alive while edit mode is off so
		# Validate / Bake / Save Scene / Bake & Play remain usable with native
		# selection and camera unrestrained. A real scene switch still unbinds,
		# because the stale author reference becomes invalid and has_author()
		# returns false.
		if _session.has_author():
			return
		_clear_author_binding("请在场景树中选择地图根节点后开启编辑。", false)
		return
	if not _bind_author(next_author):
		_clear_author_binding("地图根节点绑定失败，请重新选择作者场景根节点。", false)

func _activate_author(next_author: Node) -> void:
	if next_author == null:
		return
	if not is_map_author_root_node(next_author) or next_author != get_editor_interface().get_edited_scene_root():
		_clear_author_binding("请直接选择当前编辑场景的地图根节点。", false)
		return
	if _session.author == next_author:
		return
	if not _bind_author(next_author):
		_clear_author_binding("地图根节点绑定失败，请重新选择作者场景根节点。", false)

func _on_edit_mode_changed(enabled: bool) -> void:
	_request_edit_mode(enabled)

func _request_edit_mode(enabled: bool) -> void:
	if _session == null:
		return
	if not enabled:
		_leave_edit_mode_keep_author()
		return
	var selected_author := _selected_scene_root_author()
	# Re-entering the mode right after leaving it: reuse the bound author even
	# when the user has since clicked a non-root node for native selection.
	if selected_author == null and _session.has_author() and _session.author == get_editor_interface().get_edited_scene_root():
		selected_author = _session.author
	if selected_author == null:
		_session.set_edit_mode(false)
		if _dock != null:
			_dock.set_map_locked(false)
			_dock.set_status_message("请在场景树中选择地图根节点后开启编辑。", false)
		return
	if not _bind_author(selected_author):
		_clear_author_binding("地图根节点绑定失败，请重新选择作者场景根节点。", false)
		return
	_session.set_edit_mode(true)
	if not _session.edit_mode or _session.author != selected_author:
		_clear_author_binding("地图编辑模式未能成功开启。", false)
		return
	_active_author = selected_author
	if _dock != null:
		_dock.set_map_locked(true)
		_dock.set_status_message("地图已锁定，已隐藏根节点选择框。", true)
	_clear_editor_selection_for_lock()

func _bind_author(next_author: Node) -> bool:
	if _session == null or not is_map_author_root_node(next_author):
		return false
	var scene_root := get_editor_interface().get_edited_scene_root()
	if next_author != scene_root:
		return false
	if _session.author == next_author:
		return true
	_cancel_active_edit_input()
	_clear_preview()
	_clear_selection_overlay()
	_clear_box_overlay()
	_clear_debug_overlay()
	_clear_cover_overlay()
	_clear_special_overlay()
	# Repair a Library before the Session builds its palette. This covers a
	# Definition deleted while the editor was closed, before any filesystem
	# change signal can refresh the active scene.
	if next_author != null:
		var library := next_author.get("placeable_library") as TacticalPlaceableLibrary
		if library != null:
			_library_repair_in_progress = true
			PLACEABLE_SERVICE.repair_library(library)
			_library_repair_in_progress = false
	if not _session.has_method("begin_for_author"):
		return false
	# Consume the formal bool result. Dynamic call() keeps this compatible with
	# older hot-reloaded Session scripts; false is always a failure, and the
	# bound-author check below is a second guard.
	var bind_result: Variant = _session.call("begin_for_author", next_author, scene_root)
	if bind_result is bool and not bool(bind_result):
		return false
	return _session.author == next_author

func _clear_author_binding(reason: String, valid: bool = false) -> void:
	_cancel_active_edit_input()
	_clear_preview()
	_clear_selection_overlay()
	_clear_box_overlay()
	_clear_debug_overlay()
	_clear_cover_overlay()
	_clear_special_overlay()
	if _session != null:
		if _session.edit_mode:
			_session.set_edit_mode(false)
		_session.clear_author()
	_active_author = null
	if _dock != null:
		_dock.set_map_locked(false)
		_dock.set_session(_session)
		_dock.set_status_message(reason, valid)

func _exit_edit_mode(reason: String) -> void:
	_clear_author_binding(reason, false)


## Turn edit mode off without unbinding the author, so the Validate / Bake /
## Save Scene / Bake & Play actions stay available while Godot's native
## selection and camera are freely usable.
func _leave_edit_mode_keep_author() -> void:
	if _session == null:
		return
	_cancel_active_edit_input()
	_clear_preview()
	_clear_selection_overlay()
	_clear_box_overlay()
	_clear_cover_overlay()
	_clear_special_overlay()
	_active_author = null
	if _session.edit_mode:
		_session.set_edit_mode(false)
	if _dock != null:
		_dock.set_map_locked(false)
		_dock.set_status_message("地图编辑模式已关闭；Validate / Bake / Save Scene / Bake & Play 仍可用。", true)

func _is_locked_edit_valid() -> bool:
	if _session == null or not _session.edit_mode:
		return true
	if _active_author == null or not is_instance_valid(_active_author):
		return false
	if _session.author != _active_author:
		return false
	return _active_author == get_editor_interface().get_edited_scene_root()

func _selected_scene_root_author() -> Node:
	if _selection == null:
		return null
	return selected_scene_root_author(_selection.get_selected_nodes(), get_editor_interface().get_edited_scene_root())

func _selection_includes_author(nodes: Array, author: Node) -> bool:
	if author == null:
		return false
	for node in nodes:
		if node == author:
			return true
	return false

func _clear_editor_selection_for_lock() -> void:
	if _selection == null or _selection_clear_in_progress:
		return
	if _selection.get_selected_nodes().is_empty():
		return
	_selection_clear_in_progress = true
	_selection.clear()
	_selection_clear_in_progress = false

func _on_floor_changed(level: int) -> void:
	_session.set_floor_level(level)
	_clear_preview()
	_clear_box_overlay()
	_update_selection_overlay()
	_update_debug_overlay()
	_update_special_overlay()

func _on_target_layer_changed(layer: int) -> void:
	_session.set_target_layer(layer)

func _on_tool_changed(tool: int) -> void:
	_cancel_active_edit_input()
	_session.set_tool(tool)
	_clear_box_overlay()

func _on_rotate_requested() -> void:
	if _session.tool == TacticalMapEditSession.Tool.SELECT:
		_session.selection_rotate(get_undo_redo())
	else:
		_session.rotate_selection()


func _on_selection_replace_requested() -> void:
	_session.selection_replace(get_undo_redo())


func _on_selection_rotate_requested() -> void:
	_session.selection_rotate(get_undo_redo())


func _on_selection_delete_requested() -> void:
	_session.selection_delete(get_undo_redo())


func _on_selection_copy_requested() -> void:
	_session.selection_copy()


func _on_selection_paste_requested() -> void:
	_session.selection_paste(get_undo_redo())

func _on_placeable_selected(index: int) -> void:
	_session.select_placeable(index)

func _on_session_changed() -> void:
	_refresh_debug_validation_diagnostics()
	_update_selection_overlay()
	_update_debug_overlay()
	_update_special_overlay()
	if _last_preview_target != null:
		_update_preview(_last_preview_target)

func _open_placeable_wizard() -> void:
	if _session == null or not _session.has_author():
		if _dock != null:
			_dock.set_status_message("没有活动的 TacticalMapAuthor，无法添加素材。", false)
		return
	var base_control := get_editor_interface().get_base_control()
	if base_control == null:
		_dock.set_status_message("无法打开素材选择器：编辑器基座不可用。", false)
		return
	if _placeable_file_dialog == null or not is_instance_valid(_placeable_file_dialog):
		_placeable_file_dialog = FileDialog.new()
		_placeable_file_dialog.name = "TacticalPlaceableDefinitionPicker"
		_placeable_file_dialog.title = "选择要加入素材库的 Definition"
		_placeable_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_placeable_file_dialog.access = FileDialog.ACCESS_RESOURCES
		_placeable_file_dialog.filters = PackedStringArray(["*.tres ; Placeable Definition"])
		_placeable_file_dialog.file_selected.connect(_on_placeable_definition_selected)
		base_control.add_child(_placeable_file_dialog)
	_placeable_file_dialog.current_dir = "res://resources/map_tiles/definitions"
	_placeable_file_dialog.popup_centered_ratio(0.7)
	_dock.set_status_message("请选择一个 TacticalCellTileDefinition 或 TacticalObjectDefinition。", true)


func _on_placeable_definition_selected(path: String) -> void:
	if _session == null or not _session.has_author():
		if _dock != null:
			_dock.set_status_message("地图作者已失效，请重新开启地图编辑模式。", false)
		return
	var paths := _default_placeable_paths()
	var result: Dictionary = PLACEABLE_SERVICE.import_definition(
		_session.author,
		path,
		String(paths.get(&"library", "")),
	)
	if not bool(result.get(&"valid", false)):
		var errors := Array(result.get(&"errors", []))
		var message_parts: Array[String] = []
		for error_value in errors:
			message_parts.append(String(error_value))
		var message := "；".join(message_parts)
		_dock.set_status_message("素材导入失败：%s" % message, false)
		return
	_on_placeable_wizard_saved(result)

func _open_new_map_dialog() -> void:
	if _new_map_dialog == null or not is_instance_valid(_new_map_dialog):
		_new_map_dialog = NEW_MAP_DIALOG_SCRIPT.new()
		_new_map_dialog.name = "TacticalNewMapDialog"
		_new_map_dialog.map_created.connect(_on_new_map_created)
		_new_map_dialog.canceled.connect(_on_new_map_dialog_canceled)
		var base_control := get_editor_interface().get_base_control()
		if base_control == null:
			_new_map_dialog.free()
			_new_map_dialog = null
			if _dock != null:
				_dock.set_status_message("无法打开新建地图对话框：编辑器基座不可用。", false)
			return
		base_control.add_child(_new_map_dialog)
	_new_map_dialog.open_for_default()
	if _dock != null:
		_dock.set_status_message("请配置新地图请求；创建服务校验通过后才可创建。", true)

func _on_new_map_dialog_canceled() -> void:
	if _dock != null:
		_dock.set_status_message("已取消新建地图。", true)

func _on_new_map_created(result: Dictionary) -> void:
	var scene_path := String(result.get(&"scene_path", "")).strip_edges()
	if scene_path.is_empty() or not FileAccess.file_exists(scene_path):
		if _new_map_dialog != null and is_instance_valid(_new_map_dialog):
			_new_map_dialog.call("_show_validation", ["创建服务未返回有效的作者场景路径。"], [])
		if _dock != null:
			_dock.set_status_message("新建地图失败：作者场景路径无效。", false)
		return
	if _new_map_dialog != null and is_instance_valid(_new_map_dialog):
		_new_map_dialog.hide()
	get_editor_interface().open_scene_from_path(scene_path)
	if _dock != null:
		_dock.set_status_message("地图已创建，正在打开作者场景…", true)
	call_deferred("_activate_new_map_scene", scene_path)

func _activate_new_map_scene(scene_path: String) -> void:
	var root := get_editor_interface().get_edited_scene_root()
	var author: Node = root if is_map_author_root_node(root) else null
	if author != null:
		# Opening a scene may leave the previous scene-tree selection in place.
		# Select only the actual root to bind the idle Session; do not enter edit
		# mode automatically.
		if _selection != null:
			_selection.clear()
			_selection.add_node(author)
			_on_selection_changed()
		if _dock != null:
			_dock.set_status_message("已打开新地图：%s。请选中地图根节点后手动开启编辑。" % scene_path, true)
		return
	if _dock != null:
		_dock.set_status_message("地图场景已打开，但未找到 TacticalMapAuthor；请检查创建服务输出。", false)

func _default_placeable_paths() -> Dictionary:
	var map_token := "map"
	if _session != null and _session.has_author():
		var author_id := String(_session.author.get("map_id"))
		if not author_id.is_empty():
			map_token = _safe_path_token(author_id)
	var library_path := ""
	if _session != null and _session.has_author():
		var current_library = _session.author.get("placeable_library")
		if current_library is TacticalPlaceableLibrary and not String(current_library.resource_path).is_empty():
			library_path = String(current_library.resource_path)
	if library_path.is_empty():
		library_path = "res://resources/map_tiles/libraries/%s_placeable_library.tres" % map_token
	var definition_path := "res://resources/map_tiles/definitions/generated/%s_terrain_new_cell.tres" % map_token
	return {&"definition": definition_path, &"library": library_path}

func _safe_path_token(value: String) -> String:
	var result := value.strip_edges()
	for character in ["/", "\\", " ", ":"]:
		result = result.replace(character, "_")
	return result if not result.is_empty() else "map"

func _on_placeable_wizard_saved(result: Dictionary) -> void:
	if _session == null:
		return
	var new_id := StringName(String(result.get(&"placeable_id", "")))
	var reloaded := false
	if _session.has_method("reload_placeables"):
		_session.call("reload_placeables", true)
		reloaded = true
	elif _session.has_method("_load_placeables"):
		# Current Session exposes the loader privately; use it only as a
		# compatibility fallback until the public reload API is available.
		_session.call("_load_placeables")
		reloaded = true
	if reloaded:
		var entries: Array = _session.get_placeables()
		for index in range(entries.size()):
			if String(entries[index].get("id", "")) == String(new_id):
				_session.select_placeable(index)
				break
	if _dock != null:
		_dock.set_session(_session)
		var warning_count := Array(result.get(&"warnings", [])).size()
		_dock.set_status_message("素材已加入%s，请保存作者场景。" % ("（警告 %d 条）" % warning_count if warning_count > 0 else ""), true)

func _finish_special_edit() -> void:
	if _session == null or not _session.has_method("finish_special_edit"):
		if _session != null:
			_session.set_status_message("当前 Session 未提供 finish_special_edit 接口。", false)
		return
	var finished := bool(_session.call("finish_special_edit", get_undo_redo()))
	if not finished:
		_session.set_status_message("当前没有可结束的特殊编辑。", false)

func _on_debug_view_changed(view: int) -> void:
	if _session == null:
		return
	_session.set_debug_view(view)
	_refresh_debug_validation_diagnostics()
	_update_debug_overlay()


func _refresh_debug_validation_diagnostics() -> void:
	if _dock == null or _session == null:
		return
	if _session.get_debug_view() == TacticalMapEditSession.DebugView.COVER and _session.has_method("get_cover_debug_snapshot"):
		var snapshot: Dictionary = _session.call("get_cover_debug_snapshot")
		_dock.set_validation_diagnostics(snapshot.get(&"diagnostics", []))
		return
	_dock.set_validation_diagnostics(_session.get_validation_diagnostics())

func _on_validation_location_requested(diagnostic: Dictionary) -> void:
	if _session == null:
		return
	var coordinate = diagnostic.get(&"coordinate", null)
	if not coordinate is Vector3i:
		_session.set_status_message("该诊断没有结构化坐标，无法定位。", false)
		return
	_session.set_debug_view(TacticalMapEditSession.DebugView.VALIDATION)
	if not _session.focus_validation_cell(coordinate as Vector3i):
		return
	_update_selection_overlay()
	_update_debug_overlay()
	_best_effort_focus_validation_cell(coordinate as Vector3i)

func _validate_author() -> void:
	if not _session.has_author():
		return
	var result = _session.author.call("validate_map")
	if result is Dictionary:
		_dock.show_result("Validate", result)
	_refresh_validation_outputs(result)

func _bake_author() -> void:
	if not _session.has_author():
		return
	var result = _session.author.call("bake_map")
	if result is Dictionary:
		_dock.show_result("Bake", result)
	_refresh_validation_outputs(result)

func _refresh_validation_outputs(result: Variant = null) -> void:
	if _session == null:
		return
	var diagnostics: Array[Dictionary] = []
	var has_result_diagnostics := false
	if result is Dictionary:
		var result_dictionary: Dictionary = result
		if result_dictionary.has(&"diagnostics"):
			has_result_diagnostics = true
			var raw_diagnostics = result_dictionary.get(&"diagnostics", [])
			if raw_diagnostics is Array:
				for diagnostic in raw_diagnostics:
					if diagnostic is Dictionary:
						diagnostics.append((diagnostic as Dictionary).duplicate(true))
	if not has_result_diagnostics:
		diagnostics = _session.get_validation_diagnostics()
	if _dock != null:
		_dock.set_validation_diagnostics(diagnostics)
	_update_debug_overlay()

func _save_scene() -> void:
	var error := get_editor_interface().save_scene()
	if error == OK:
		_session.set_status_message("场景已保存。", true)
	else:
		_session.set_status_message("场景保存失败：%s" % error_string(error), false)

func _bake_and_play() -> void:
	if _bake_and_play_in_progress:
		if _dock != null:
			_dock.set_status_message("Bake & Play 已在执行中。", false)
		return
	if _session == null or not _session.has_author():
		if _dock != null:
			_dock.set_status_message("没有活动的 TacticalMapAuthor。", false)
		return
	if EditorInterface.is_playing_scene():
		_dock.set_status_message("主场景已经在运行中。", false)
		return

	_bake_and_play_in_progress = true
	_dock.set_status_message("正在保存作者场景…", true)
	var save_error := get_editor_interface().save_scene()
	if save_error != OK:
		_dock.set_status_message("Bake & Play 停止：场景保存失败：%s" % error_string(save_error), false)
		_bake_and_play_in_progress = false
		return

	_dock.set_status_message("正在 Bake 地图…", true)
	var bake_value = _session.author.call("bake_map")
	if not bake_value is Dictionary:
		_dock.set_status_message("Bake & Play 停止：Bake 未返回有效结果。", false)
		_refresh_validation_outputs()
		_bake_and_play_in_progress = false
		return
	var bake_result: Dictionary = bake_value
	var errors: Array = bake_result.get(&"errors", [])
	if not errors.is_empty():
		_dock.show_result("Bake & Play", bake_result)
		_refresh_validation_outputs(bake_result)
		_bake_and_play_in_progress = false
		return

	_dock.show_result("Bake", bake_result)
	_refresh_validation_outputs(bake_result)
	EditorInterface.play_main_scene()
	_dock.set_status_message("Bake & Play 已启动主场景。", true)
	_bake_and_play_in_progress = false

func _target_from_screen(camera: Camera3D, screen_position: Vector2, requested_tool: int = -1) -> TacticalPlacementTarget:
	if not _session.has_author():
		return TARGET_SCRIPT.invalid("没有活动的地图作者。")
	var author: Node3D = _session.author as Node3D
	if author == null:
		return TARGET_SCRIPT.invalid("活动作者不是 Node3D。")
	var dimensions: Vector3 = author.get("cell_dimensions")
	if dimensions.x <= 0.0 or dimensions.y <= 0.0 or dimensions.z <= 0.0:
		return TARGET_SCRIPT.invalid("作者 cell_dimensions 无效。")
	var origin: Vector3 = author.get("grid_origin")
	var local_plane_point := origin + Vector3(0.0, (float(_session.floor_level) + 0.5) * dimensions.y, 0.0)
	var plane_point := author.to_global(local_plane_point)
	var plane_normal := author.global_transform.basis * Vector3.UP
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var denominator := ray_direction.dot(plane_normal)
	if absf(denominator) < 0.00001:
		return TARGET_SCRIPT.invalid("视线与当前楼层平面平行。")
	var distance := (plane_point - ray_origin).dot(plane_normal) / denominator
	if distance < 0.0:
		return TARGET_SCRIPT.invalid("当前楼层位于视线背后。")
	var world_position := ray_origin + ray_direction * distance
	var local_position := author.to_local(world_position)
	var cell := Vector3i(
		floori((local_position.x - origin.x) / dimensions.x),
		_session.floor_level,
		floori((local_position.z - origin.z) / dimensions.z)
	)
	var target := TARGET_SCRIPT.new()
	target.cell = cell
	target.world_position = author.to_global(author.call("cell_to_local", cell))
	target.current_level = _session.floor_level
	target.surface_normal = plane_normal.normalized()
	var effective_tool := _session.tool if requested_tool < 0 else requested_tool
	var check := _session.can_edit_cell(cell, effective_tool)
	target.valid = bool(check.get("valid", false))
	target.reason = String(check.get("reason", ""))
	if effective_tool == TacticalMapEditSession.Tool.PICK:
		target.valid = _session._inside_volume(cell)
		target.reason = "可吸取。" if target.valid else "坐标超出地图体积。"
	return target

func _update_preview(target: TacticalPlacementTarget) -> void:
	if _session == null or not _session.edit_mode or not _session.has_author() or target == null:
		_clear_preview()
		return
	# Invalid targets returned from the ray cast may still have a canonical cell
	# centre. Keep them visible in red so a user can understand why painting is
	# rejected; targets without a position (parallel ray/out-of-view) are simply
	# cleared.
	if not target.valid and target.world_position == Vector3.ZERO:
		_clear_preview()
		return
	_last_preview_target = target
	_ensure_preview()
	if _preview_root == null:
		return
	var author: Node3D = _session.author as Node3D
	_preview_root.global_position = target.world_position
	_rebuild_preview_content(author)
	_apply_preview_tint(Color(0.25, 0.95, 0.4, 0.28) if target.valid else Color(0.95, 0.2, 0.2, 0.28))
	_preview_root.visible = true

func _update_selection_overlay(offset: Vector3i = Vector3i.ZERO) -> void:
	if _session == null or not _session.has_author():
		_clear_selection_overlay()
		return
	var cells := _session.get_selected_cells()
	if cells.is_empty():
		_clear_selection_overlay()
		return
	var author := _session.author as Node3D
	if author == null or not author.has_method("cell_to_local"):
		_clear_selection_overlay()
		return
	_ensure_selection_overlay()
	if _selection_overlay == null:
		return
	var dimensions: Vector3 = author.get("cell_dimensions")
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(dimensions.x * 0.9, maxf(dimensions.y * 0.06, 0.05), dimensions.z * 0.9)
	multi_mesh.mesh = box
	multi_mesh.instance_count = cells.size()
	for index in range(cells.size()):
		var local_center: Vector3 = author.call("cell_to_local", cells[index] + offset)
		# cell_to_local is the canonical centre; lift the thin overlay just above
		# the tile so it remains visible without changing any map geometry.
		local_center.y += dimensions.y * 0.47
		multi_mesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, local_center))
	_selection_overlay.multimesh = multi_mesh
	_selection_overlay.visible = true

func _ensure_selection_overlay() -> void:
	if _selection_overlay != null and is_instance_valid(_selection_overlay):
		return
	if _session == null or not _session.has_author():
		return
	var author := _session.author as Node3D
	if author == null:
		return
	_selection_overlay_root = Node3D.new()
	_selection_overlay_root.name = "__TacticalMapEditorSelectionOverlay"
	_selection_overlay_root.set_meta("tactical_map_editor_preview", true)
	author.add_child(_selection_overlay_root)
	_selection_overlay = MultiMeshInstance3D.new()
	_selection_overlay.name = "SelectedCells"
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 0.7, 1.0, 0.34)
	_selection_overlay.material_override = material
	_selection_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_overlay_root.add_child(_selection_overlay)
	_selection_overlay_root.owner = null
	_selection_overlay.owner = null

func _clear_selection_overlay() -> void:
	if _selection_overlay_root != null and is_instance_valid(_selection_overlay_root):
		if _selection_overlay_root.get_parent() != null:
			_selection_overlay_root.get_parent().remove_child(_selection_overlay_root)
		_selection_overlay_root.free()
	_selection_overlay_root = null
	_selection_overlay = null

func _update_box_overlay(from_cell: Vector3i, to_cell: Vector3i, valid: bool) -> void:
	if (not _box_drag_active and not _selection_rect_drag_active) or _session == null or not _session.has_author():
		_clear_box_overlay()
		return
	var author := _session.author as Node3D
	if author == null or not author.has_method("cell_to_local"):
		_clear_box_overlay()
		return
	var dimensions: Vector3 = author.get("cell_dimensions")
	if dimensions.x <= 0.0 or dimensions.y <= 0.0 or dimensions.z <= 0.0:
		_clear_box_overlay()
		return
	var min_x := mini(from_cell.x, to_cell.x)
	var max_x := maxi(from_cell.x, to_cell.x)
	var min_z := mini(from_cell.z, to_cell.z)
	var max_z := maxi(from_cell.z, to_cell.z)
	var first_center: Vector3 = author.call("cell_to_local", Vector3i(min_x, from_cell.y, min_z))
	var last_center: Vector3 = author.call("cell_to_local", Vector3i(max_x, from_cell.y, max_z))
	var local_center := (first_center + last_center) * 0.5
	local_center.y += dimensions.y * 0.48
	_ensure_box_overlay()
	if _box_overlay == null:
		return
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(
		float(max_x - min_x + 1) * dimensions.x * 0.96,
		maxf(dimensions.y * 0.06, 0.05),
		float(max_z - min_z + 1) * dimensions.z * 0.96
	)
	_box_overlay.position = local_center
	_box_overlay.mesh = box_mesh
	var overlay_material := _box_overlay.material_override as StandardMaterial3D
	if overlay_material != null:
		if not valid:
			overlay_material.albedo_color = Color(0.95, 0.2, 0.2, 0.24)
		elif _box_erase_mode:
			overlay_material.albedo_color = Color(0.96, 0.42, 0.18, 0.32)
		else:
			overlay_material.albedo_color = Color(0.25, 0.95, 0.4, 0.24)
	_box_overlay.visible = true

func _ensure_box_overlay() -> void:
	if _box_overlay != null and is_instance_valid(_box_overlay):
		return
	if _session == null or not _session.has_author():
		return
	var author := _session.author as Node3D
	if author == null:
		return
	_box_overlay_root = Node3D.new()
	_box_overlay_root.name = "__TacticalMapEditorBoxOverlay"
	_box_overlay_root.set_meta("tactical_map_editor_preview", true)
	author.add_child(_box_overlay_root)
	_box_overlay = MeshInstance3D.new()
	_box_overlay.name = "BoxPaintArea"
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	_box_overlay.material_override = material
	_box_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box_overlay_root.add_child(_box_overlay)
	_box_overlay_root.owner = null
	_box_overlay.owner = null

func _clear_box_overlay() -> void:
	if _box_overlay_root != null and is_instance_valid(_box_overlay_root):
		if _box_overlay_root.get_parent() != null:
			_box_overlay_root.get_parent().remove_child(_box_overlay_root)
		_box_overlay_root.free()
	_box_overlay_root = null
	_box_overlay = null

func _update_debug_overlay() -> void:
	if _session == null or not _session.has_author():
		_clear_debug_overlay()
		_clear_cover_overlay()
		return
	var current_view := _session.get_debug_view()
	if current_view == TacticalMapEditSession.DebugView.COVER:
		_clear_debug_overlay()
		_update_cover_overlay()
		return
	_clear_cover_overlay()
	if current_view == TacticalMapEditSession.DebugView.NORMAL:
		_clear_debug_overlay()
		return
	var author := _session.author as Node3D
	if author == null or not author.has_method("cell_to_local"):
		_clear_debug_overlay()
		return
	var cells: Array = _session.get_debug_cells_for_view(_session.get_debug_view())
	if cells.is_empty():
		_clear_debug_overlay()
		return
	_ensure_debug_overlay()
	if _debug_overlay == null:
		return
	var dimensions: Vector3 = author.get("cell_dimensions")
	if dimensions.x <= 0.0 or dimensions.y <= 0.0 or dimensions.z <= 0.0:
		_clear_debug_overlay()
		return
	var display_cells: Array[Dictionary] = []
	for cell_value in cells:
		if not cell_value is Dictionary:
			continue
		var cell_record: Dictionary = cell_value
		var validation_only := bool(cell_record.get(&"validation_only", false))
		if validation_only and _session.get_debug_view() != TacticalMapEditSession.DebugView.VALIDATION:
			continue
		if not validation_only and cell_record.has(&"has_floor") and not bool(cell_record.get(&"has_floor", false)):
			continue
		if not cell_record.get(&"coordinate", null) is Vector3i:
			continue
		display_cells.append(cell_record)
	if display_cells.is_empty():
		_clear_debug_overlay()
		return
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(dimensions.x * 0.9, maxf(dimensions.y * 0.08, 0.06), dimensions.z * 0.9)
	multi_mesh.mesh = box
	multi_mesh.instance_count = display_cells.size()
	for index in range(display_cells.size()):
		var record := display_cells[index]
		var cell: Vector3i = record.get(&"coordinate", Vector3i.ZERO)
		var local_center: Vector3 = author.call("cell_to_local", cell)
		local_center.y += dimensions.y * 0.46
		var instance_basis := Basis.IDENTITY
		if cell == _session.get_debug_focus_cell():
			instance_basis = instance_basis.scaled(Vector3(1.08, 1.6, 1.08))
		multi_mesh.set_instance_transform(index, Transform3D(instance_basis, local_center))
		multi_mesh.set_instance_color(index, _debug_color(record))
	_debug_overlay.multimesh = multi_mesh
	_debug_overlay.visible = true

func _debug_color(record: Dictionary) -> Color:
	if record.get(&"coordinate", null) == _session.get_debug_focus_cell():
		return Color(0.98, 0.12, 0.92, 0.9)
	var view := _session.get_debug_view()
	if view == TacticalMapEditSession.DebugView.VALIDATION:
		var severity := String(record.get(&"validation_severity", "")).to_lower()
		if severity == "error":
			return Color(0.95, 0.08, 0.05, 0.62)
		if severity == "warning":
			return Color(0.98, 0.72, 0.08, 0.56)
		return Color(0.28, 0.62, 0.95, 0.16)
	if view == TacticalMapEditSession.DebugView.WALKABILITY:
		var walkable = _session.get_debug_value(record, &"walkable")
		if walkable == null:
			return Color(0.55, 0.55, 0.6, 0.18)
		return Color(0.12, 0.82, 0.26, 0.5) if bool(walkable) else Color(0.9, 0.1, 0.08, 0.58)
	var field := &"move_cost"
	if view == TacticalMapEditSession.DebugView.SIGHT_BLOCK:
		field = &"sight_block"
	elif view == TacticalMapEditSession.DebugView.PROJECTILE_BLOCK:
		field = &"projectile_block"
	elif view == TacticalMapEditSession.DebugView.OCCLUDER_HEIGHT:
		field = &"occluder_height"
	var value = _session.get_debug_value(record, field)
	if value == null:
		return Color(0.55, 0.55, 0.6, 0.18)
	var normalized := 0.0
	match view:
		TacticalMapEditSession.DebugView.MOVE_COST:
			normalized = clampf((float(value) - 1.0) / 8.0, 0.0, 1.0)
		TacticalMapEditSession.DebugView.SIGHT_BLOCK, TacticalMapEditSession.DebugView.PROJECTILE_BLOCK:
			normalized = clampf(float(value), 0.0, 1.0)
		TacticalMapEditSession.DebugView.OCCLUDER_HEIGHT:
			normalized = clampf(float(value) / 4.0, 0.0, 1.0)
	return _heat_color(normalized)

func _heat_color(value: float) -> Color:
	var low := Color(0.12, 0.85, 0.82, 0.42)
	var high := Color(0.94, 0.12, 0.08, 0.58)
	return low.lerp(high, clampf(value, 0.0, 1.0))

func _ensure_debug_overlay() -> void:
	if _debug_overlay != null and is_instance_valid(_debug_overlay):
		return
	if _session == null or not _session.has_author():
		return
	var author := _session.author as Node3D
	if author == null:
		return
	_debug_overlay_root = Node3D.new()
	_debug_overlay_root.name = "__TacticalMapEditorDebugOverlay"
	_debug_overlay_root.set_meta("tactical_map_editor_preview", true)
	author.add_child(_debug_overlay_root)
	_debug_overlay = MultiMeshInstance3D.new()
	_debug_overlay.name = "RuleDebugCells"
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	_debug_overlay.material_override = material
	_debug_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debug_overlay_root.add_child(_debug_overlay)
	_debug_overlay_root.owner = null
	_debug_overlay.owner = null

func _clear_debug_overlay() -> void:
	if _debug_overlay_root != null and is_instance_valid(_debug_overlay_root):
		if _debug_overlay_root.get_parent() != null:
			_debug_overlay_root.get_parent().remove_child(_debug_overlay_root)
		_debug_overlay_root.free()
	_debug_overlay_root = null
	_debug_overlay = null


func _update_cover_overlay() -> void:
	if _session == null or not _session.has_method("get_cover_debug_snapshot"):
		_clear_cover_overlay()
		return
	var author := _session.author as Node3D
	if author == null or not author.has_method("cell_to_local"):
		_clear_cover_overlay()
		return
	var dimensions: Vector3 = author.get("cell_dimensions")
	if dimensions.x <= 0.0 or dimensions.z <= 0.0:
		_clear_cover_overlay()
		return
	var snapshot: Dictionary = _session.call("get_cover_debug_snapshot")
	var snapshot_edges: Array = snapshot.get(&"edges", [])
	if snapshot_edges.is_empty():
		_clear_cover_overlay()
		return
	var edge_inputs: Array[Dictionary] = []
	for edge_value in snapshot_edges:
		if not edge_value is Dictionary:
			continue
		edge_inputs.append(_cover_edge_visual_input(edge_value as Dictionary, author))
	var visual_records := PREVIEW_BUILDER.build_cover_edge_visual_records(edge_inputs, dimensions)
	if visual_records.is_empty():
		_clear_cover_overlay()
		return
	_ensure_cover_overlay(author)
	if _cover_overlay_root == null:
		return
	for child in _cover_overlay_root.get_children():
		child.free()
	_add_cover_boundary_lines(visual_records)
	_add_cover_arrows(visual_records)
	_add_cover_diagnostic_markers(visual_records, dimensions)


static func _cover_edge_visual_input(edge: Dictionary, author: Node3D) -> Dictionary:
	var result: Dictionary = edge.duplicate(true)
	if author == null or not author.has_method("cell_to_local"):
		return result
	var cell_a := result.get(&"cell_a", null)
	var cell_b := result.get(&"cell_b", null)
	if cell_a is Vector3i:
		result[&"center_a"] = author.call("cell_to_local", cell_a)
	if not bool(result.get(&"diagnostic_only", false)) and cell_b is Vector3i:
		result[&"center_b"] = author.call("cell_to_local", cell_b)
	return result


func _ensure_cover_overlay(author: Node3D) -> void:
	if _cover_overlay_root != null and is_instance_valid(_cover_overlay_root):
		return
	if author == null:
		return
	_cover_overlay_root = Node3D.new()
	_cover_overlay_root.name = "__TacticalMapEditorCoverOverlay"
	_cover_overlay_root.set_meta("tactical_map_editor_preview", true)
	author.add_child(_cover_overlay_root)
	_cover_overlay_root.owner = null


func _add_cover_boundary_lines(records: Array[Dictionary]) -> void:
	var lines: Array[Dictionary] = []
	for record in records:
		if record.get(&"diagnostic_only", false):
			continue
		var line = record.get(&"line", null)
		if line is Dictionary:
			lines.append(line)
	if _cover_overlay_root == null or lines.is_empty():
		return
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	multi_mesh.mesh = box
	multi_mesh.instance_count = lines.size()
	for index in range(lines.size()):
		var line: Dictionary = lines[index]
		var from: Vector3 = line.get(&"from", Vector3.ZERO)
		var to: Vector3 = line.get(&"to", Vector3.ZERO)
		var delta := to - from
		var length := maxf(delta.length(), 0.01)
		var x_axis := delta.normalized()
		var z_axis := x_axis.cross(Vector3.UP).normalized()
		var basis := Basis(x_axis, Vector3.UP, z_axis)
		var width := float(line.get(&"width", 0.055))
		multi_mesh.set_instance_transform(index, Transform3D(basis.scaled(Vector3(length, width, width)), (from + to) * 0.5))
		multi_mesh.set_instance_color(index, line.get(&"color", Color.WHITE))
	var instance := MultiMeshInstance3D.new()
	instance.name = "CoverBoundaries"
	instance.multimesh = multi_mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cover_overlay_root.add_child(instance)
	instance.owner = null


func _add_cover_arrows(records: Array[Dictionary]) -> void:
	var arrows: Array[Dictionary] = []
	for record in records:
		for arrow_value in record.get(&"arrows", []):
			if arrow_value is Dictionary:
				arrows.append(arrow_value)
	if _cover_overlay_root == null or arrows.is_empty():
		return
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_colors = true
	var needle := CylinderMesh.new()
	needle.top_radius = 0.12
	needle.bottom_radius = 1.0
	needle.height = 1.0
	needle.radial_segments = 8
	multi_mesh.mesh = needle
	multi_mesh.instance_count = arrows.size()
	for index in range(arrows.size()):
		var arrow: Dictionary = arrows[index]
		var from: Vector3 = arrow.get(&"from", Vector3.ZERO)
		var to: Vector3 = arrow.get(&"to", Vector3.UP)
		var delta := to - from
		var length := maxf(delta.length(), 0.01)
		var direction := delta.normalized() if delta.length_squared() > 0.000001 else Vector3(0.0, 0.0, 1.0)
		var facing := Vector2i(roundi(direction.x), roundi(direction.z))
		if facing == Vector2i.ZERO:
			facing = Vector2i.DOWN
		var basis := PREVIEW_BUILDER.facing_basis(facing)
		var width := float(arrow.get(&"width", 0.065))
		multi_mesh.set_instance_transform(index, Transform3D(basis.scaled(Vector3(width, length, width)), (from + to) * 0.5))
		multi_mesh.set_instance_color(index, arrow.get(&"color", Color.WHITE))
	var instance := MultiMeshInstance3D.new()
	instance.name = "CoverProtectionArrows"
	instance.multimesh = multi_mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cover_overlay_root.add_child(instance)
	instance.owner = null


func _add_cover_diagnostic_markers(records: Array[Dictionary], dimensions: Vector3) -> void:
	var positions: Array[Vector3] = []
	for record in records:
		if not record.get(&"diagnostic_only", false):
			continue
		var position = record.get(&"position", null)
		if position is Vector3:
			positions.append(position)
	if _cover_overlay_root == null or positions.is_empty():
		return
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = SphereMesh.new()
	var sphere := multi_mesh.mesh as SphereMesh
	sphere.radius = maxf(minf(dimensions.x, dimensions.z) * 0.12, 0.08)
	sphere.height = sphere.radius * 2.0
	multi_mesh.instance_count = positions.size()
	for index in range(positions.size()):
		var position := positions[index]
		position.y += dimensions.y * 0.55
		multi_mesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, position))
	var instance := MultiMeshInstance3D.new()
	instance.name = "CoverDiagnosticMarkers"
	instance.multimesh = multi_mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.95, 0.05, 0.15, 0.92)
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cover_overlay_root.add_child(instance)
	instance.owner = null


func _clear_cover_overlay() -> void:
	if _cover_overlay_root != null and is_instance_valid(_cover_overlay_root):
		if _cover_overlay_root.get_parent() != null:
			_cover_overlay_root.get_parent().remove_child(_cover_overlay_root)
		_cover_overlay_root.free()
	_cover_overlay_root = null

func _best_effort_focus_validation_cell(cell: Vector3i) -> void:
	# Godot 4.7 editor viewport focus APIs differ between minor builds.  Use a
	# capability check and keep the canonical selection/debug overlay as the
	# reliable fallback; never make locating a diagnostic depend on a camera API.
	var editor_interface := get_editor_interface()
	if editor_interface == null or not editor_interface.has_method("get_3d_viewport"):
		_session.set_status_message("已高亮地格 %s；当前编辑器未提供视口聚焦 API。" % cell, true)
		return
	var viewport = editor_interface.call("get_3d_viewport")
	if viewport != null and viewport.has_method("focus_selection"):
		viewport.call("focus_selection")
	_session.set_status_message("已定位并高亮地格 %s。" % cell, true)

func _update_special_overlay() -> void:
	if _session == null or not _session.has_author():
		_clear_special_overlay()
		return
	var author := _session.author as Node3D
	if author == null or not author.has_method("cell_to_local"):
		_clear_special_overlay()
		return
	var dimensions: Vector3 = author.get("cell_dimensions")
	if dimensions.x <= 0.0 or dimensions.y <= 0.0 or dimensions.z <= 0.0:
		_clear_special_overlay()
		return
	var spawn_points: Array[Dictionary] = []
	var traversal_points: Array[Dictionary] = []
	var patrol_points: Array[Dictionary] = []
	var traversal_segments: Array[Dictionary] = []
	var patrol_segments: Array[Dictionary] = []
	for node in _editor_descendants(author):
		if node is UnitSpawnMarker3D:
			var marker := node as UnitSpawnMarker3D
			if marker.cell.y == _session.floor_level:
				spawn_points.append({
				&"position": author.call("cell_to_local", marker.cell),
				&"color": marker.visual_color,
				&"facing": marker.facing,
			})
		elif node is TraversalLink3D:
			var link := node as TraversalLink3D
			if link.from_cell.y == _session.floor_level:
				traversal_points.append({&"position": author.call("cell_to_local", link.from_cell), &"color": Color("d58cff")})
			if link.to_cell.y == _session.floor_level:
				traversal_points.append({&"position": author.call("cell_to_local", link.to_cell), &"color": Color("d58cff")})
			if link.from_cell.y == _session.floor_level and link.to_cell.y == _session.floor_level:
				traversal_segments.append({&"from": author.call("cell_to_local", link.from_cell), &"to": author.call("cell_to_local", link.to_cell)})
		elif node is PatrolRoute3D:
			var route := node as PatrolRoute3D
			var previous: Variant = null
			for point in route.points:
				if not point is Vector3i or point.y != _session.floor_level:
					previous = null
					continue
				var local_point: Vector3 = author.call("cell_to_local", point)
				patrol_points.append({&"position": local_point, &"color": Color("ffbf63")})
				if previous is Vector3:
					patrol_segments.append({&"from": previous, &"to": local_point})
				previous = local_point
	if spawn_points.is_empty() and traversal_points.is_empty() and patrol_points.is_empty() and traversal_segments.is_empty() and patrol_segments.is_empty():
		_clear_special_overlay()
		return
	_ensure_special_overlay(author)
	if _special_overlay_root == null:
		return
	for child in _special_overlay_root.get_children():
		child.free()
	_add_special_points(spawn_points, "SpawnMarkers", dimensions, 0.24)
	_add_special_needles(spawn_points, "SpawnFacing", dimensions)
	_add_special_points(traversal_points, "TraversalEndpoints", dimensions, 0.18)
	_add_special_points(patrol_points, "PatrolPoints", dimensions, 0.16)
	_add_special_lines(traversal_segments, "TraversalLines", Color("d58cff"))
	_add_special_lines(patrol_segments, "PatrolLines", Color("ffbf63"))

func _ensure_special_overlay(author: Node3D) -> void:
	if _special_overlay_root != null and is_instance_valid(_special_overlay_root):
		return
	_special_overlay_root = Node3D.new()
	_special_overlay_root.name = "__TacticalMapEditorSpecialOverlay"
	_special_overlay_root.set_meta("tactical_map_editor_preview", true)
	author.add_child(_special_overlay_root)
	_special_overlay_root.owner = null

func _add_special_points(points: Array[Dictionary], node_name: String, dimensions: Vector3, radius: float) -> void:
	if _special_overlay_root == null or points.is_empty():
		return
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_colors = true
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	multi_mesh.mesh = sphere
	multi_mesh.instance_count = points.size()
	for index in range(points.size()):
		var point: Dictionary = points[index]
		var local_position: Vector3 = point.get(&"position", Vector3.ZERO)
		local_position.y += dimensions.y * 0.55
		multi_mesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, local_position))
		multi_mesh.set_instance_color(index, point.get(&"color", Color.WHITE))
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi_mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_special_overlay_root.add_child(instance)
	instance.owner = null

func _add_special_needles(points: Array[Dictionary], node_name: String, dimensions: Vector3) -> void:
	if _special_overlay_root == null or points.is_empty():
		return
	var length := maxf(dimensions.x, dimensions.z) * 0.95
	var radius := maxf(dimensions.x * 0.07, 0.03)
	var raise := dimensions.y * 0.34
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_colors = true
	var needle := CylinderMesh.new()
	needle.top_radius = radius * 0.12
	needle.bottom_radius = radius
	needle.height = length
	needle.radial_segments = 8
	multi_mesh.mesh = needle
	multi_mesh.instance_count = points.size()
	for index in range(points.size()):
		var point: Dictionary = points[index]
		var facing: Vector2i = point.get(&"facing", Vector2i.DOWN)
		var local_position: Vector3 = point.get(&"position", Vector3.ZERO)
		var y := Vector3(float(facing.x), 0.0, float(facing.y)).normalized()
		local_position += y * (length * 0.5) + Vector3.UP * raise
		var transform := Transform3D(PREVIEW_BUILDER.facing_basis(facing), local_position)
		multi_mesh.set_instance_transform(index, transform)
		multi_mesh.set_instance_color(index, point.get(&"color", Color.WHITE))
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi_mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_special_overlay_root.add_child(instance)
	instance.owner = null

func _add_special_lines(segments: Array[Dictionary], node_name: String, color: Color) -> void:
	if _special_overlay_root == null or segments.is_empty():
		return
	var immediate := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for segment in segments:
		var from_position: Vector3 = segment.get(&"from", Vector3.ZERO)
		var to_position: Vector3 = segment.get(&"to", Vector3.ZERO)
		from_position.y += 0.18
		to_position.y += 0.18
		immediate.surface_add_vertex(from_position)
		immediate.surface_add_vertex(to_position)
	immediate.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = immediate
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_special_overlay_root.add_child(instance)
	instance.owner = null

func _clear_special_overlay() -> void:
	if _special_overlay_root != null and is_instance_valid(_special_overlay_root):
		if _special_overlay_root.get_parent() != null:
			_special_overlay_root.get_parent().remove_child(_special_overlay_root)
		_special_overlay_root.free()
	_special_overlay_root = null

func _editor_descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	if root == null:
		return result
	var pending: Array[Node] = []
	for child in root.get_children():
		pending.append(child)
	while not pending.is_empty():
		var node: Node = pending.pop_front()
		result.append(node)
		for child in node.get_children():
			pending.append(child)
	return result

func _ensure_preview() -> void:
	if _preview_root != null and is_instance_valid(_preview_root):
		return
	if not _session.has_author():
		return
	var author: Node3D = _session.author as Node3D
	_preview_root = Node3D.new()
	_preview_root.name = "__TacticalMapEditorPreview"
	_preview_root.set_meta("tactical_map_editor_preview", true)
	author.add_child(_preview_root)
	_preview_root.owner = null

func _rebuild_preview_content(author: Node3D) -> void:
	if _preview_root == null or author == null or _session == null:
		return
	for child in _preview_root.get_children():
		child.free()
	_preview_mesh = null
	var selected := _session.get_selected_placeable()
	var selected_kind := String(selected.get("kind", "cell"))
	var tintable: Array[Node] = []
	if selected_kind == "cell":
		var mesh_instance := _build_cell_preview(selected, author)
		if mesh_instance != null:
			_preview_mesh = mesh_instance
			tintable.append(mesh_instance)
	else:
		var scene := selected.get("scene", null) as PackedScene
		if scene == null:
			var definition := selected.get("definition", null) as Resource
			if definition != null:
				scene = definition.get("scene") as PackedScene if definition.get("scene") is PackedScene else null
		if scene != null:
			var instance := PREVIEW_BUILDER.instantiate_scene_preview(_preview_root, scene, _session.rotation_quarters)
			if instance != null:
				_collect_preview_visuals(instance, tintable)
				if instance is MeshInstance3D:
					_preview_mesh = instance as MeshInstance3D
		if _preview_mesh == null and tintable.size() > 0:
			_preview_mesh = tintable[0] as MeshInstance3D
	if _preview_mesh == null:
		_preview_mesh = _build_fallback_preview(author)
		if _preview_mesh != null:
			tintable.append(_preview_mesh)
	if selected_kind == "cell":
		_build_preview_cover_directions(selected, author)
	if selected_kind == "spawn":
		_build_preview_facing_needle(selected, author)
	for visual_node in tintable:
		if visual_node != null and is_instance_valid(visual_node):
			_apply_preview_visual_defaults(visual_node)


func _build_preview_cover_directions(selected: Dictionary, author: Node3D) -> void:
	if _preview_root == null or author == null or _session == null:
		return
	var definition := selected.get(&"definition", null) as Resource
	if definition == null:
		return
	var raw_contributions = definition.get(&"edge_contributions") if definition.has_method("get") else []
	if not raw_contributions is Array or raw_contributions.is_empty():
		return
	var contributions: Array[Dictionary] = []
	for contribution_value in raw_contributions:
		var contribution := contribution_value as TacticalLocalEdgeContribution
		if contribution == null or not contribution.is_active():
			continue
		var rules := contribution.edge_rules
		if rules == null:
			continue
		contributions.append({
			&"local_direction": int(contribution.local_direction),
			&"enabled": contribution.enabled,
			&"profile_a": _preview_cover_profile(rules.resolve_profile(0)),
			&"profile_b": _preview_cover_profile(rules.resolve_profile(1)),
		})
	var arrows := PREVIEW_BUILDER.build_local_cover_preview_records(contributions, _session.rotation_quarters)
	if arrows.is_empty():
		return
	var dimensions: Vector3 = author.get("cell_dimensions")
	var base_length := minf(dimensions.x, dimensions.z)
	var raise := dimensions.y * 0.42
	for arrow in arrows:
		var direction: Vector2i = arrow.get(&"direction", Vector2i.DOWN)
		var length := base_length * float(arrow.get(&"length_factor", 0.32))
		var width := float(arrow.get(&"width", 0.065))
		var color: Color = arrow.get(&"color", Color(0.95, 0.72, 0.18, 0.9))
		var needle := PREVIEW_BUILDER.build_facing_needle(length, width, color)
		var facing := Vector3(float(direction.x), 0.0, float(direction.y)).normalized()
		needle.transform = Transform3D(
			PREVIEW_BUILDER.facing_basis(direction),
			facing * (length * 0.5) + Vector3.UP * raise
		)
		_preview_root.add_child(needle)
		needle.owner = null


func _preview_cover_profile(profile: TacticalCoverProfile) -> Dictionary:
	if profile == null:
		return {}
	return {
		&"id": profile.cover_id,
		&"level": profile.cover_level,
		&"reduction": profile.damage_reduction_ratio,
		&"debug_color": profile.debug_color,
	}

func _build_preview_facing_needle(selected: Dictionary, author: Node3D) -> void:
	if _preview_root == null or author == null or _session == null:
		return
	var facing_quarters: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	var facing := facing_quarters[posmod(_session.rotation_quarters, 4)]
	var dimensions: Vector3 = author.get("cell_dimensions")
	var length := maxf(dimensions.x, dimensions.z) * 0.95
	var radius := maxf(dimensions.x * 0.07, 0.03)
	var raise := dimensions.y * 0.34
	var color: Variant = selected.get("visual_color", null)
	var tint := color as Color if color is Color else Color(0.25, 0.95, 0.4, 0.55)
	var needle := PREVIEW_BUILDER.build_facing_needle(length, radius, tint)
	var y := Vector3(float(facing.x), 0.0, float(facing.y)).normalized()
	needle.transform = Transform3D(PREVIEW_BUILDER.facing_basis(facing), y * (length * 0.5) + Vector3.UP * raise)
	_preview_root.add_child(needle)
	needle.owner = null

func _build_cell_preview(selected: Dictionary, author: Node3D) -> MeshInstance3D:
	if String(selected.get("kind", "cell")) != "cell":
		return null
	var definition := selected.get("definition", null) as Resource
	var mesh_library := definition.get("mesh_library") as MeshLibrary if definition != null and definition.get("mesh_library") is MeshLibrary else null
	var layer := int(selected.get("layer", 0))
	var grid_name := _cell_preview_grid_name(layer)
	if grid_name.is_empty():
		return null
	if mesh_library == null:
		var grid := author.get_node_or_null(NodePath(grid_name)) as GridMap
		mesh_library = grid.mesh_library if grid != null else null
	var default_item_id := -1
	if definition != null:
		var definition_item_id = definition.get("mesh_item_id")
		if definition_item_id != null:
			default_item_id = int(definition_item_id)
	var item_id := int(selected.get("item_id", default_item_id))
	return PREVIEW_BUILDER.build_cell_mesh(_preview_root, mesh_library, item_id, _session.rotation_quarters)

static func _cell_preview_grid_name(layer: int) -> String:
	match layer:
		0:
			return "FloorGrid"
		1:
			return "StructureGrid"
		2:
			return "DecorationGrid"
	return ""

func _build_fallback_preview(author: Node3D) -> MeshInstance3D:
	var dimensions: Vector3 = author.get("cell_dimensions")
	return PREVIEW_BUILDER.build_fallback(_preview_root, dimensions)

func _collect_preview_visuals(node: Node, output: Array[Node]) -> void:
	if node is GeometryInstance3D:
		output.append(node)
	for child in node.get_children():
		_collect_preview_visuals(child, output)

func _apply_preview_visual_defaults(node: Node) -> void:
	PREVIEW_BUILDER.apply_preview_visual_defaults(node)

func _apply_preview_tint(color: Color) -> void:
	if _preview_root == null:
		return
	PREVIEW_BUILDER.tint_preview(_preview_root, color)

func _disable_preview_collisions(node: Node) -> void:
	PREVIEW_BUILDER.disable_collisions(node)

func _clear_preview() -> void:
	_clear_box_overlay()
	if _preview_root != null and is_instance_valid(_preview_root):
		if _preview_root.get_parent() != null:
			_preview_root.get_parent().remove_child(_preview_root)
		_preview_root.free()
	_preview_root = null
	_preview_mesh = null
	_last_preview_target = null

static func is_map_author_root_node(object: Object) -> bool:
	var node := object as Node
	if node == null or not is_instance_valid(node):
		return false
	if node is TacticalMapAuthor:
		return true
	var script := node.get_script()
	return script != null and script.resource_path == AUTHOR_SCRIPT_PATH

static func selected_scene_root_author(nodes: Array, edited_scene_root: Node) -> Node:
	if edited_scene_root == null or nodes.size() != 1:
		return null
	var candidate := nodes[0] as Node
	if candidate != edited_scene_root:
		return null
	return candidate if is_map_author_root_node(candidate) else null

static func selection_belongs_to_author(nodes: Array, author: Node) -> bool:
	if author == null or not is_instance_valid(author):
		return false
	for node in nodes:
		var selected := node as Node
		if selected == null or (selected != author and not author.is_ancestor_of(selected)):
			return false
	return true

func _find_author(object: Object) -> Node:
	var node := object as Node
	return node if is_map_author_root_node(node) else null
