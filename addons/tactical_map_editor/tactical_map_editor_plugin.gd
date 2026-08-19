@tool
extends EditorPlugin

const SESSION_SCRIPT := preload("res://addons/tactical_map_editor/editing/map_edit_session.gd")
const TARGET_SCRIPT := preload("res://addons/tactical_map_editor/editing/placement_target.gd")
const DOCK_SCRIPT := preload("res://addons/tactical_map_editor/ui/tactical_map_dock.gd")
const AUTHOR_SCRIPT_PATH := "res://scripts/map_authoring/tactical_map_author.gd"

var _dock: TacticalMapDock
var _session: TacticalMapEditSession
var _selection: EditorSelection
var _preview_root: Node3D
var _preview_mesh: MeshInstance3D
var _drag_button: int = 0
var _saved_tool_for_right_drag: int = -1
var _bake_and_play_in_progress: bool = false


func _enter_tree() -> void:
	_session = SESSION_SCRIPT.new()
	_dock = DOCK_SCRIPT.new()
	_dock.name = "TacticalMapBuilder"
	_dock.set_session(_session)
	_dock.edit_mode_changed.connect(_on_edit_mode_changed)
	_dock.floor_changed.connect(_on_floor_changed)
	_dock.target_layer_changed.connect(_on_target_layer_changed)
	_dock.tool_changed.connect(_on_tool_changed)
	_dock.rotate_requested.connect(_on_rotate_requested)
	_dock.placeable_selected.connect(_on_placeable_selected)
	_dock.validate_requested.connect(_validate_author)
	_dock.bake_requested.connect(_bake_author)
	_dock.save_requested.connect(_save_scene)
	_dock.play_requested.connect(_bake_and_play)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_selection = get_editor_interface().get_selection()
	if _selection != null:
		_selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed()


func _exit_tree() -> void:
	_clear_preview()
	if _selection != null and _selection.selection_changed.is_connected(_on_selection_changed):
		_selection.selection_changed.disconnect(_on_selection_changed)
	if _session != null:
		_session.cancel_stroke()
	_bake_and_play_in_progress = false
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
	_dock = null
	_session = null


func _handles(object: Object) -> bool:
	return _find_author(object) != null


func _edit(object: Object) -> void:
	var selected_author := _find_author(object)
	if selected_author != null:
		_activate_author(selected_author)


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if _session == null or not _session.has_author() or not _session.edit_mode:
		return AFTER_GUI_INPUT_PASS
	if viewport_camera == null:
		return AFTER_GUI_INPUT_PASS

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_R:
			_session.rotate_selection()
			return AFTER_GUI_INPUT_STOP
		if key_event.keycode == KEY_ESCAPE:
			_drag_button = 0
			_saved_tool_for_right_drag = -1
			_session.cancel_stroke()
			_clear_preview()
			return AFTER_GUI_INPUT_STOP

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var target := _target_from_screen(viewport_camera, motion.position)
		_update_preview(target)
		if _drag_button != 0:
			if target.valid:
				_session.apply_at(target.cell)
			return AFTER_GUI_INPUT_STOP
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				var left_target := _target_from_screen(viewport_camera, mouse.position)
				_update_preview(left_target)
				if not left_target.valid:
					_session.set_status_message(left_target.reason, false)
					return AFTER_GUI_INPUT_STOP
				if _session.tool == TacticalMapEditSession.Tool.PICK:
					_session.pick_at(left_target.cell)
					return AFTER_GUI_INPUT_STOP
				_drag_button = MOUSE_BUTTON_LEFT
				_session.begin_stroke(_session.tool_name())
				_session.apply_at(left_target.cell)
				return AFTER_GUI_INPUT_STOP
			if _drag_button == MOUSE_BUTTON_LEFT:
				_drag_button = 0
				_session.finish_stroke(get_undo_redo())
				return AFTER_GUI_INPUT_STOP

		if mouse.button_index == MOUSE_BUTTON_RIGHT:
			if mouse.pressed:
				# Erase is intentionally validated independently of the current
				# Paint selection: a blank palette or invalid paint target must not
				# prevent removing existing content from the active layer.
				var right_target := _target_from_screen(viewport_camera, mouse.position, TacticalMapEditSession.Tool.ERASE)
				_update_preview(right_target)
				if not right_target.valid:
					_session.set_status_message(right_target.reason, false)
					return AFTER_GUI_INPUT_STOP
				_saved_tool_for_right_drag = _session.tool
				_session.set_tool(TacticalMapEditSession.Tool.ERASE)
				_drag_button = MOUSE_BUTTON_RIGHT
				_session.begin_stroke("擦除")
				_session.apply_at(right_target.cell)
				return AFTER_GUI_INPUT_STOP
			if _drag_button == MOUSE_BUTTON_RIGHT:
				_drag_button = 0
				_session.finish_stroke(get_undo_redo())
				if _saved_tool_for_right_drag >= 0:
					_session.set_tool(_saved_tool_for_right_drag)
				_saved_tool_for_right_drag = -1
				return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS


func _on_selection_changed() -> void:
	if _selection == null:
		return
	var nodes := _selection.get_selected_nodes()
	var next_author: Node = null
	for node in nodes:
		next_author = _find_author(node)
		if next_author != null:
			break
	if next_author == null:
		_clear_preview()
		_session.clear_author()
		_dock.set_session(_session)
		return
	_activate_author(next_author)


func _activate_author(next_author: Node) -> void:
	if next_author == null:
		return
	if _session.author == next_author:
		return
	_clear_preview()
	var scene_root := get_editor_interface().get_edited_scene_root()
	_session.begin_for_author(next_author, scene_root)
	_dock.set_session(_session)


func _on_edit_mode_changed(enabled: bool) -> void:
	_session.set_edit_mode(enabled)
	if not enabled:
		_clear_preview()


func _on_floor_changed(level: int) -> void:
	_session.set_floor_level(level)
	_clear_preview()


func _on_target_layer_changed(layer: int) -> void:
	_session.set_target_layer(layer)


func _on_tool_changed(tool: int) -> void:
	_session.set_tool(tool)


func _on_rotate_requested() -> void:
	_session.rotate_selection()


func _on_placeable_selected(index: int) -> void:
	_session.select_placeable(index)


func _validate_author() -> void:
	if not _session.has_author():
		return
	var result = _session.author.call("validate_map")
	if result is Dictionary:
		_dock.show_result("Validate", result)


func _bake_author() -> void:
	if not _session.has_author():
		return
	var result = _session.author.call("bake_map")
	if result is Dictionary:
		_dock.show_result("Bake", result)


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
		_bake_and_play_in_progress = false
		return
	var bake_result: Dictionary = bake_value
	var errors: Array = bake_result.get(&"errors", [])
	if not errors.is_empty():
		_dock.show_result("Bake & Play", bake_result)
		_bake_and_play_in_progress = false
		return

	_dock.show_result("Bake", bake_result)
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
	if not _session.edit_mode or not _session.has_author() or not target.valid:
		_clear_preview()
		return
	_ensure_preview()
	if _preview_mesh == null:
		return
	var author: Node3D = _session.author as Node3D
	_preview_mesh.global_position = target.world_position
	var dimensions: Vector3 = author.get("cell_dimensions")
	var box := _preview_mesh.mesh as BoxMesh
	if box != null:
		box.size = Vector3(dimensions.x * 0.92, maxf(dimensions.y * 0.12, 0.06), dimensions.z * 0.92)
	var material := _preview_mesh.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(0.25, 0.95, 0.4, 0.28) if target.valid else Color(0.95, 0.2, 0.2, 0.28)
	_preview_mesh.visible = true


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
	_preview_mesh = MeshInstance3D.new()
	_preview_mesh.name = "CellGhost"
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 0.12, 1.8)
	_preview_mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.25, 0.95, 0.4, 0.28)
	_preview_mesh.material_override = material
	_preview_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_root.add_child(_preview_mesh)
	_preview_root.owner = null
	_preview_mesh.owner = null


func _clear_preview() -> void:
	if _preview_root != null and is_instance_valid(_preview_root):
		if _preview_root.get_parent() != null:
			_preview_root.get_parent().remove_child(_preview_root)
		_preview_root.free()
	_preview_root = null
	_preview_mesh = null


func _find_author(object: Object) -> Node:
	var node := object as Node
	while node != null:
		var script := node.get_script()
		if script != null and script.resource_path == AUTHOR_SCRIPT_PATH:
			return node
		node = node.get_parent()
	return null
