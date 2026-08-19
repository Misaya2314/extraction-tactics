@tool
class_name TacticalMapEditSession
extends RefCounted

## Editor-only state for one TacticalMapAuthor editing session.
##
## This class deliberately talks to the authoring scene through the small
## properties and methods that already exist.  The optional placeable library
## is discovered dynamically so the plugin can run before the data task lands.

signal changed
signal status_changed(message: String, valid: bool)

enum Tool {
	PAINT,
	ERASE,
	PICK,
	ROTATE,
}

enum TargetLayer {
	FLOOR,
	STRUCTURE,
	DECORATION,
	OBJECT,
}

const MARKER_SCRIPT_PATH := "res://scripts/map_authoring/map_object_marker_3d.gd"
const FLOOR_GRID_NAME := "FloorGrid"
const STRUCTURE_GRID_NAME := "StructureGrid"
const DECORATION_GRID_NAME := "DecorationGrid"
const OBJECTS_NODE_NAME := "Objects"

var author: Node
var edited_scene_root: Node
var floor_level: int = 0
var target_layer: int = TargetLayer.FLOOR
var tool: int = Tool.PAINT
var rotation_quarters: int = 0
var edit_mode: bool = false
var placeables: Array = []
var selected_placeable: Dictionary = {}

var stroke_active: bool = false
var stroke_label: String = ""
var _stroke_before: Dictionary = {}
var _stroke_after: Dictionary = {}
var _object_serial: int = 1
var _last_status: String = "选择一个 TacticalMapAuthor 开始编辑。"
var _last_status_valid: bool = true


func begin_for_author(new_author: Node, new_scene_root: Node = null) -> void:
	cancel_stroke()
	author = new_author
	edited_scene_root = new_scene_root
	floor_level = 0
	target_layer = TargetLayer.FLOOR
	tool = Tool.PAINT
	rotation_quarters = 0
	edit_mode = false
	placeables.clear()
	selected_placeable.clear()
	if author != null:
		floor_level = clampi(floor_level, 0, _level_count() - 1)
		_load_placeables()
		if not placeables.is_empty():
			select_placeable(0)
	_set_status("已连接地图作者：%s。打开编辑模式开始操作。" % author.name, true)
	_emit_changed()


func clear_author() -> void:
	cancel_stroke()
	author = null
	edited_scene_root = null
	placeables.clear()
	selected_placeable.clear()
	edit_mode = false
	_set_status("选择一个 TacticalMapAuthor 开始编辑。", true)
	_emit_changed()


func has_author() -> bool:
	return is_instance_valid(author)


func set_edit_mode(value: bool) -> void:
	if edit_mode == value:
		return
	edit_mode = value and has_author()
	if not edit_mode:
		cancel_stroke()
	_set_status("地图编辑模式已开启。" if edit_mode else "地图编辑模式已关闭。", true)
	_emit_changed()


func set_floor_level(value: int) -> void:
	var next_level := clampi(value, 0, maxi(_level_count() - 1, 0))
	if floor_level == next_level:
		return
	cancel_stroke()
	floor_level = next_level
	_set_status("当前编辑楼层：%d。" % floor_level, true)
	_emit_changed()


func set_target_layer(value: int) -> void:
	var next_layer := clampi(value, TargetLayer.FLOOR, TargetLayer.OBJECT)
	if target_layer == next_layer:
		return
	cancel_stroke()
	target_layer = next_layer
	_set_status("目标层：%s。" % target_layer_name(target_layer), true)
	_emit_changed()


func set_tool(value: int) -> void:
	var next_tool := clampi(value, Tool.PAINT, Tool.ROTATE)
	if tool == next_tool:
		return
	cancel_stroke()
	tool = next_tool
	_set_status("工具：%s。" % tool_name(tool), true)
	_emit_changed()


func rotate_selection() -> void:
	rotation_quarters = posmod(rotation_quarters + 1, 4)
	_set_status("旋转：%d°。" % (rotation_quarters * 90), true)
	_emit_changed()


func select_placeable(index: int) -> void:
	if index < 0 or index >= placeables.size():
		return
	selected_placeable = placeables[index].duplicate(true)
	var entry_layer: int = int(selected_placeable.get("layer", TargetLayer.FLOOR))
	if entry_layer >= TargetLayer.FLOOR and entry_layer <= TargetLayer.OBJECT:
		target_layer = entry_layer
	rotation_quarters = 0
	_set_status("已选择：%s。目标层：%s。" % [selected_placeable.get("label", "素材"), target_layer_name(target_layer)], true)
	_emit_changed()


func get_placeables(query: String = "") -> Array:
	if query.strip_edges().is_empty():
		return placeables.duplicate(true)
	var needle := query.strip_edges().to_lower()
	var filtered: Array = []
	for entry in placeables:
		var haystack := "%s %s %s" % [entry.get("label", ""), entry.get("category", ""), entry.get("id", "")]
		if haystack.to_lower().contains(needle):
			filtered.append(entry.duplicate(true))
	return filtered


func get_selected_placeable() -> Dictionary:
	return selected_placeable.duplicate(true)


func get_last_status() -> Dictionary:
	return {"message": _last_status, "valid": _last_status_valid}


func set_status_message(message: String, valid: bool = true) -> void:
	_set_status(message, valid)


func level_count() -> int:
	return _level_count()


func target_layer_name(value: int = target_layer) -> String:
	match value:
		TargetLayer.FLOOR:
			return "Floor"
		TargetLayer.STRUCTURE:
			return "Structure"
		TargetLayer.DECORATION:
			return "Decoration"
		TargetLayer.OBJECT:
			return "Object"
	return "Unknown"


func tool_name(value: int = tool) -> String:
	match value:
		Tool.PAINT:
			return "Paint"
		Tool.ERASE:
			return "Erase"
		Tool.PICK:
			return "Pick"
		Tool.ROTATE:
			return "Rotate"
	return "Unknown"


func can_edit_cell(cell: Vector3i, for_tool: int = tool) -> Dictionary:
	if not has_author():
		return {"valid": false, "reason": "没有活动的 TacticalMapAuthor。"}
	if not _inside_volume(cell):
		return {"valid": false, "reason": "坐标超出地图体积。"}
	if for_tool == Tool.PICK:
		return {"valid": true, "reason": "可吸取。"}
	if for_tool == Tool.ERASE:
		return {"valid": true, "reason": "可擦除。"}
	if for_tool == Tool.ROTATE:
		if target_layer == TargetLayer.OBJECT:
			return {"valid": not _markers_at(cell).is_empty(), "reason": "目标格没有对象。" if _markers_at(cell).is_empty() else "可旋转对象。"}
		var rotate_grid := _grid_for_layer(target_layer)
		var rotate_item := -1 if rotate_grid == null else rotate_grid.get_cell_item(cell)
		return {"valid": rotate_item >= 0, "reason": "目标格没有地格。" if rotate_item < 0 else "可旋转地格。"}
	if selected_placeable.is_empty():
		return {"valid": false, "reason": "素材栏中没有选中素材。"}
	var effective_layer := _paint_effective_layer()
	if effective_layer == TargetLayer.OBJECT:
		if _objects_root() == null:
			return {"valid": false, "reason": "作者场景缺少 Objects 节点。"}
		if _grid_for_layer(TargetLayer.FLOOR) == null or _grid_for_layer(TargetLayer.FLOOR).get_cell_item(cell) < 0:
			return {"valid": false, "reason": "对象需要放在有效 Floor 上。"}
		return {"valid": true, "reason": "可放置对象。"}
	var grid := _grid_for_layer(effective_layer)
	if grid == null:
		return {"valid": false, "reason": "%s GridMap 不存在。" % target_layer_name(effective_layer)}
	if effective_layer == TargetLayer.STRUCTURE:
		var floor_grid := _grid_for_layer(TargetLayer.FLOOR)
		if floor_grid == null or floor_grid.get_cell_item(cell) < 0:
			return {"valid": false, "reason": "Structure 下方没有 Floor。"}
	if int(selected_placeable.get("item_id", -1)) < 0:
		return {"valid": false, "reason": "素材没有有效 GridMap item_id。"}
	return {"valid": true, "reason": "可放置。"}


func begin_stroke(label: String = "地图编辑") -> void:
	if stroke_active:
		return
	stroke_active = true
	stroke_label = label
	_stroke_before.clear()
	_stroke_after.clear()


func apply_at(cell: Vector3i) -> bool:
	if not stroke_active:
		begin_stroke()
	if tool == Tool.PICK:
		return pick_at(cell)
	var check := can_edit_cell(cell)
	if not bool(check.get("valid", false)):
		_set_status(String(check.get("reason", "无法编辑。")), false)
		return false
	if not _stroke_before.has(cell):
		_stroke_before[cell] = _capture_snapshot(cell)
	var changed_now := false
	match tool:
		Tool.PAINT:
			changed_now = _paint_at(cell)
		Tool.ERASE:
			changed_now = _erase_at(cell)
		Tool.ROTATE:
			changed_now = _rotate_at(cell)
	if changed_now:
		_stroke_after[cell] = _capture_snapshot(cell)
		_set_status("%s：%s" % [tool_name(), cell], true)
		_emit_changed()
	return changed_now


func finish_stroke(undo_redo: Object) -> bool:
	if not stroke_active:
		return false
	stroke_active = false
	var committed_label := stroke_label if not stroke_label.is_empty() else "地图编辑"
	var before := _sorted_snapshots(_stroke_before)
	var after := _sorted_snapshots(_stroke_after)
	var changed_any := false
	# Only cells with a real mutation are recorded in _stroke_after.  An
	# invalid/no-op stroke therefore cannot manufacture an Undo Action, and a
	# stroke that returns a cell to its original snapshot is also ignored.
	for after_snapshot in after:
		var cell: Vector3i = after_snapshot.get("cell", Vector3i.ZERO)
		var before_snapshot: Dictionary = _snapshot_for_cell(before, cell)
		if before_snapshot.is_empty() or not _snapshot_equal(before_snapshot, after_snapshot):
			changed_any = true
			break
	if changed_any and undo_redo != null:
		var action_context: Object = edited_scene_root if edited_scene_root != null else author
		if undo_redo is EditorUndoRedoManager:
			# EditorUndoRedoManager owns per-scene history. Keep the action in the
			# current edited scene instead of the global editor history.
			var manager := undo_redo as EditorUndoRedoManager
			manager.create_action(committed_label, UndoRedo.MERGE_DISABLE, action_context)
			manager.add_do_method(self, &"_apply_snapshot_set", after)
			manager.add_undo_method(self, &"_apply_snapshot_set", before)
			manager.commit_action()
		elif undo_redo is UndoRedo:
			# A plain UndoRedo is useful for isolated Session tests; the editor
			# path above is the one that preserves scene ownership.
			var generic_undo_redo := undo_redo as UndoRedo
			generic_undo_redo.create_action(committed_label)
			generic_undo_redo.add_do_method(Callable(self, &"_apply_snapshot_set").bind(after))
			generic_undo_redo.add_undo_method(Callable(self, &"_apply_snapshot_set").bind(before))
			generic_undo_redo.commit_action()
	_stroke_before.clear()
	_stroke_after.clear()
	stroke_label = ""
	if changed_any:
		_set_status("已提交一个 %s Undo Action。" % committed_label, true)
		_emit_changed()
	return changed_any


func cancel_stroke() -> void:
	if not stroke_active:
		return
	_apply_snapshot_set(_sorted_snapshots(_stroke_before))
	stroke_active = false
	_stroke_before.clear()
	_stroke_after.clear()
	stroke_label = ""
	_emit_changed()


func pick_at(cell: Vector3i) -> bool:
	if not _inside_volume(cell):
		_set_status("坐标超出地图体积。", false)
		return false
	if target_layer == TargetLayer.OBJECT:
		var markers := _markers_at(cell)
		if markers.is_empty():
			_set_status("目标格没有可吸取对象。", false)
			return false
		var marker: Node = markers[0]
		var picked := _entry_from_marker(marker)
		if picked.is_empty():
			_set_status("对象没有可识别的素材定义。", false)
			return false
		placeables.append(picked)
		select_placeable(placeables.size() - 1)
		_set_status("已吸取对象：%s。" % picked.get("label", marker.name), true)
		return true
	var grid := _grid_for_layer(target_layer)
	if grid == null:
		_set_status("目标 GridMap 不存在。", false)
		return false
	var item_id := grid.get_cell_item(cell)
	if item_id < 0:
		_set_status("目标格没有可吸取地格。", false)
		return false
	for index in range(placeables.size()):
		var entry: Dictionary = placeables[index]
		if String(entry.get("kind", "")) == "cell" and int(entry.get("layer", -1)) == target_layer and int(entry.get("item_id", -2)) == item_id:
			select_placeable(index)
			rotation_quarters = _rotation_from_grid(grid, cell)
			_set_status("已吸取：%s。" % entry.get("label", "地格"), true)
			_emit_changed()
			return true
	_set_status("item_id=%d 尚未出现在素材栏。" % item_id, false)
	return false


func _paint_at(cell: Vector3i) -> bool:
	var selected_kind := String(selected_placeable.get("kind", "cell"))
	var effective_layer := _paint_effective_layer()
	if selected_kind == "object" or effective_layer == TargetLayer.OBJECT:
		return _replace_object_at(cell)
	var grid := _grid_for_layer(effective_layer)
	if grid == null:
		return false
	var item_id := int(selected_placeable.get("item_id", -1))
	var orientation := _orientation_for_quarters(effective_layer)
	if grid.get_cell_item(cell) == item_id and grid.get_cell_item_orientation(cell) == orientation:
		return false
	grid.set_cell_item(cell, item_id, orientation)
	return true


func _erase_at(cell: Vector3i) -> bool:
	if target_layer == TargetLayer.OBJECT:
		var markers := _markers_at(cell)
		if markers.is_empty():
			return false
		for marker in markers:
			var node: Node = marker
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
		return true
	var grid := _grid_for_layer(target_layer)
	if grid == null or grid.get_cell_item(cell) < 0:
		return false
	grid.set_cell_item(cell, -1)
	return true


func _rotate_at(cell: Vector3i) -> bool:
	if target_layer == TargetLayer.OBJECT:
		var markers := _markers_at(cell)
		if markers.is_empty():
			return false
		for marker in markers:
			var facing: Vector2i = marker.get("facing")
			marker.set("facing", _rotate_facing(facing))
		return true
	var grid := _grid_for_layer(target_layer)
	if grid == null or grid.get_cell_item(cell) < 0:
		return false
	var next_orientation := _orientation_from_basis(grid.get_cell_item_basis(cell) * Basis(Vector3.UP, PI * 0.5))
	grid.set_cell_item(cell, grid.get_cell_item(cell), next_orientation)
	return true


func _replace_object_at(cell: Vector3i) -> bool:
	var objects_root := _objects_root()
	if objects_root == null:
		return false
	var old_markers := _markers_at(cell)
	var entry := selected_placeable
	for marker in old_markers:
		var old_node: Node = marker
		if old_node.get_parent() != null:
			old_node.get_parent().remove_child(old_node)
		old_node.free()
	var record := {
		"object_id": _next_object_id(String(entry.get("label", "object"))),
		"kind": int(entry.get("object_kind", 4)),
		"cell": cell,
		"facing": _facing_for_quarters(),
		"scene": entry.get("scene"),
		"blocks_movement": bool(entry.get("blocks_movement", false)),
		"blocks_los": bool(entry.get("blocks_los", false)),
		"loot_table": entry.get("loot_table"),
		"loot_seed": int(entry.get("loot_seed", -1)),
	}
	_create_marker(record, objects_root)
	return true


func _capture_snapshot(cell: Vector3i) -> Dictionary:
	var snapshot_layer := _paint_effective_layer() if tool == Tool.PAINT else target_layer
	if snapshot_layer == TargetLayer.OBJECT:
		return {"kind": "object", "layer": TargetLayer.OBJECT, "cell": cell, "records": _capture_marker_records(cell)}
	var grid := _grid_for_layer(snapshot_layer)
	if grid == null:
		return {"kind": "grid", "layer": snapshot_layer, "cell": cell, "item": -1, "orientation": 0}
	var item := grid.get_cell_item(cell)
	return {
		"kind": "grid",
		"layer": snapshot_layer,
		"cell": cell,
		"item": item,
		"orientation": grid.get_cell_item_orientation(cell) if item >= 0 else 0,
	}


func _apply_snapshot_set(snapshots: Array) -> void:
	for snapshot in snapshots:
		_apply_snapshot(snapshot)
	if not snapshots.is_empty():
		_set_status("已应用地图编辑快照。", true)
		_emit_changed()


func _apply_snapshot(snapshot: Dictionary) -> void:
	var kind := String(snapshot.get("kind", "grid"))
	var cell: Vector3i = snapshot.get("cell", Vector3i.ZERO)
	if kind == "object":
		var objects_root := _objects_root()
		if objects_root == null:
			return
		for marker in _markers_at(cell):
			var node: Node = marker
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
		for record in snapshot.get("records", []):
			_create_marker(record, objects_root)
		return
	var layer := int(snapshot.get("layer", TargetLayer.FLOOR))
	var grid := _grid_for_layer(layer)
	if grid == null:
		return
	var item := int(snapshot.get("item", -1))
	if item < 0:
		grid.set_cell_item(cell, -1)
	else:
		grid.set_cell_item(cell, item, int(snapshot.get("orientation", 0)))


func _capture_marker_records(cell: Vector3i) -> Array:
	var records: Array = []
	for marker in _markers_at(cell):
		records.append({
			"object_id": _property(marker, "object_id", marker.name),
			"kind": int(_property(marker, "kind", 4)),
			"cell": _property(marker, "cell", cell),
			"facing": _property(marker, "facing", Vector2i(0, 1)),
			"scene": _property(marker, "scene", null),
			"blocks_movement": bool(_property(marker, "blocks_movement", false)),
			"blocks_los": bool(_property(marker, "blocks_los", false)),
			"loot_table": _property(marker, "loot_table", null),
			"loot_seed": int(_property(marker, "loot_seed", -1)),
		})
	return records


func _create_marker(record: Dictionary, objects_root: Node) -> Node:
	var marker := Node3D.new()
	var marker_script := load(MARKER_SCRIPT_PATH)
	if marker_script != null:
		marker.set_script(marker_script)
	var object_id := StringName(record.get("object_id", _next_object_id("object")))
	marker.name = String(object_id)
	marker.set("object_id", object_id)
	marker.set("kind", int(record.get("kind", 4)))
	marker.set("facing", record.get("facing", Vector2i(0, 1)))
	marker.set("scene", record.get("scene"))
	marker.set("blocks_movement", bool(record.get("blocks_movement", false)))
	marker.set("blocks_los", bool(record.get("blocks_los", false)))
	marker.set("loot_table", record.get("loot_table"))
	marker.set("loot_seed", int(record.get("loot_seed", -1)))
	objects_root.add_child(marker)
	marker.owner = edited_scene_root if edited_scene_root != null else author
	marker.set("cell", record.get("cell", Vector3i.ZERO))
	marker.call_deferred("snap_to_grid")
	return marker


func _entry_from_marker(marker: Node) -> Dictionary:
	var object_id = _property(marker, "object_id", marker.name)
	return {
		"id": "object:%s" % String(object_id),
		"label": "对象 / %s" % String(object_id),
		"category": "对象",
		"kind": "object",
		"layer": TargetLayer.OBJECT,
		"object_kind": int(_property(marker, "kind", 4)),
		"scene": _property(marker, "scene", null),
		"blocks_movement": bool(_property(marker, "blocks_movement", false)),
		"blocks_los": bool(_property(marker, "blocks_los", false)),
		"loot_table": _property(marker, "loot_table", null),
		"loot_seed": int(_property(marker, "loot_seed", -1)),
	}


func _load_placeables() -> void:
	placeables.clear()
	var library := _property(author, "placeable_library", null)
	if library != null:
		var definitions := _property(library, "definitions", [])
		if definitions is Array:
			for definition in definitions:
				var entry := _entry_from_definition(definition)
				if not entry.is_empty():
					placeables.append(entry)
	if placeables.is_empty():
		_load_catalog_fallback()
	_load_object_templates()
	placeables.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_layer := int(a.get("layer", 0))
		var b_layer := int(b.get("layer", 0))
		if a_layer != b_layer:
			return a_layer < b_layer
		return String(a.get("label", "")) < String(b.get("label", ""))
	)


func _entry_from_definition(definition: Object) -> Dictionary:
	if definition == null:
		return {}
	var placement_kind := _placement_kind_from_value(_property(definition, "placement_kind", _property(definition, "kind", "cell")))
	if placement_kind == "object":
		return {
			"id": String(_property(definition, "placeable_id", "object")),
			"label": String(_property(definition, "display_name", _property(definition, "placeable_id", "对象"))),
			"category": String(_property(definition, "category", "对象")),
			"kind": "object",
			"layer": TargetLayer.OBJECT,
			"definition": definition,
			"object_kind": _object_kind_from_value(_property(definition, "object_kind", 4)),
			"scene": _property(definition, "scene", _property(definition, "preview_scene", null)),
			"blocks_movement": bool(_property(definition, "blocks_movement", false)),
			"blocks_los": bool(_property(definition, "blocks_los", false)),
			"loot_table": _property(definition, "loot_table", null),
			"loot_seed": int(_property(definition, "loot_seed", -1)),
		}
	# MVP deliberately accepts only cell/object definitions.  EDGE and STAMP
	# are not GridMap cell placements and must never fall through as cells.
	if placement_kind != "cell":
		return {}
	var item_id := int(_property(definition, "mesh_item_id", _property(definition, "item_id", -1)))
	if item_id < 0:
		return {}
	var layer := _layer_from_value(_property(definition, "target_layer", _property(definition, "layer", 0)))
	return {
		"id": String(_property(definition, "placeable_id", "grid:%d:%d" % [layer, item_id])),
		"label": String(_property(definition, "display_name", _property(definition, "placeable_id", "item %d" % item_id))),
		"category": String(_property(definition, "category", target_layer_name(layer))),
		"kind": "cell",
		"layer": layer,
		"item_id": item_id,
		"definition": definition,
	}


func _load_catalog_fallback() -> void:
	var catalog := _property(author, "tile_catalog", null)
	var rules := _property(catalog, "rules", []) if catalog != null else []
	if not rules is Array:
		return
	for rule in rules:
		var layer := _layer_from_value(_property(rule, "layer", 0))
		var item_id := int(_property(rule, "item_id", -1))
		if item_id < 0:
			continue
		var tile_id := String(_property(rule, "tile_id", "item_%d" % item_id))
		placeables.append({
			"id": "catalog:%d:%d" % [layer, item_id],
			"label": "%s / %s" % [target_layer_name(layer), tile_id],
			"category": target_layer_name(layer),
			"kind": "cell",
			"layer": layer,
			"item_id": item_id,
			"rule": rule,
		})
	# The legacy catalog has no Decoration enum.  Reuse its visual binding in
	# the DecorationGrid as a presentation-only fallback without changing the
	# catalog or Baker rules.
	var has_decoration := false
	for entry in placeables:
		if int(entry.get("layer", -1)) == TargetLayer.DECORATION:
			has_decoration = true
			break
	if not has_decoration:
		var aliases: Array = []
		for entry in placeables:
			if String(entry.get("kind", "")) != "cell":
				continue
			var alias: Dictionary = entry.duplicate(true)
			alias["id"] = "%s:decoration" % entry.get("id", "grid")
			alias["label"] = "Decoration / %s" % String(entry.get("label", "素材"))
			alias["category"] = "Decoration"
			alias["layer"] = TargetLayer.DECORATION
			aliases.append(alias)
		placeables.append_array(aliases)


func _load_object_templates() -> void:
	var seen: Dictionary = {}
	for node in _descendants(author):
		if not _is_marker(node):
			continue
		var kind := int(_property(node, "kind", 4))
		if seen.has(kind):
			continue
		seen[kind] = true
		placeables.append({
			"id": "marker:%d" % kind,
			"label": "对象 / %s" % _object_kind_name(kind),
			"category": "对象",
			"kind": "object",
			"layer": TargetLayer.OBJECT,
			"object_kind": kind,
			"scene": _property(node, "scene", null),
			"blocks_movement": bool(_property(node, "blocks_movement", false)),
			"blocks_los": bool(_property(node, "blocks_los", false)),
			"loot_table": _property(node, "loot_table", null),
			"loot_seed": int(_property(node, "loot_seed", -1)),
		})


func _layer_from_value(value: Variant) -> int:
	if value is int:
		match int(value):
			TargetLayer.FLOOR:
				return TargetLayer.FLOOR
			TargetLayer.STRUCTURE:
				return TargetLayer.STRUCTURE
			TargetLayer.DECORATION:
				return TargetLayer.DECORATION
			TargetLayer.OBJECT:
				return TargetLayer.OBJECT
		return TargetLayer.FLOOR
	if value is String or value is StringName:
		var text_value := String(value).to_lower()
		if text_value == "0":
			return TargetLayer.FLOOR
		if text_value == "1":
			return TargetLayer.STRUCTURE
		if text_value == "2":
			return TargetLayer.DECORATION
		if text_value == "3":
			return TargetLayer.OBJECT
		if text_value.contains("structure"):
			return TargetLayer.STRUCTURE
		if text_value.contains("decoration") or text_value.contains("decor"):
			return TargetLayer.DECORATION
		if text_value.contains("object"):
			return TargetLayer.OBJECT
	return TargetLayer.FLOOR


func _placement_kind_from_value(value: Variant) -> String:
	if value is int:
		match int(value):
			0:
				return "cell"
			1:
				return "edge"
			2:
				return "object"
			3:
				return "stamp"
		return ""
	var text_value := String(value).to_lower()
	if text_value == "0" or text_value.contains("cell"):
		return "cell"
	if text_value == "1" or text_value.contains("edge"):
		return "edge"
	if text_value == "2" or text_value.contains("object") or text_value.contains("loot"):
		return "object"
	if text_value == "3" or text_value.contains("stamp"):
		return "stamp"
	return ""


func _object_kind_from_value(value: Variant) -> int:
	if value is int:
		return clampi(int(value), 0, 4)
	var text_value := String(value).to_lower()
	match text_value:
		"loot":
			return 0
		"extraction":
			return 1
		"explosive":
			return 2
		"door":
			return 3
		"generic":
			return 4
	return 4


func _object_kind_name(kind: int) -> String:
	match kind:
		0:
			return "Loot"
		1:
			return "Extraction"
		2:
			return "Explosive"
		3:
			return "Door"
	return "Generic"


func _grid_for_layer(layer: int) -> GridMap:
	if not has_author():
		return null
	var node_name := ""
	match layer:
		TargetLayer.FLOOR:
			node_name = FLOOR_GRID_NAME
		TargetLayer.STRUCTURE:
			node_name = STRUCTURE_GRID_NAME
		TargetLayer.DECORATION:
			node_name = DECORATION_GRID_NAME
	return author.get_node_or_null(NodePath(node_name)) as GridMap


func _objects_root() -> Node:
	return author.get_node_or_null(NodePath(OBJECTS_NODE_NAME)) if has_author() else null


func _inside_volume(cell: Vector3i) -> bool:
	var footprint: Vector2i = _property(author, "footprint_size", Vector2i.ZERO)
	return cell.x >= 0 and cell.z >= 0 and cell.y >= 0 \
		and cell.x < footprint.x and cell.z < footprint.y and cell.y < _level_count()


func _level_count() -> int:
	return maxi(int(_property(author, "level_count", 1)), 1)


func _markers_at(cell: Vector3i) -> Array:
	var result: Array = []
	if _objects_root() == null:
		return result
	for node in _descendants(_objects_root()):
		if _is_marker(node) and _property(node, "cell", Vector3i(-999, -999, -999)) == cell:
			result.append(node)
	return result


func _is_marker(node: Node) -> bool:
	if node == null:
		return false
	var script := node.get_script()
	return script != null and script.resource_path == MARKER_SCRIPT_PATH


func _descendants(root: Node) -> Array:
	var result: Array = []
	if root == null:
		return result
	var pending: Array = root.get_children()
	while not pending.is_empty():
		var node: Node = pending.pop_front()
		result.append(node)
		pending.append_array(node.get_children())
	return result


func _property(object: Object, property_name: StringName, fallback: Variant) -> Variant:
	if object == null:
		return fallback
	for property_info in object.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			var value = object.get(property_name)
			return fallback if value == null and fallback != null else value
	return fallback


func _orientation_for_quarters(layer: int = -1) -> int:
	return _orientation_from_basis(Basis(Vector3.UP, float(rotation_quarters) * PI * 0.5), layer)


func _orientation_from_basis(basis: Basis, layer: int = -1) -> int:
	var grid := _grid_for_layer(target_layer if layer < 0 else layer)
	if grid == null:
		grid = _grid_for_layer(TargetLayer.FLOOR)
	return grid.get_orthogonal_index_from_basis(basis) if grid != null else 0


func _paint_effective_layer() -> int:
	if selected_placeable.is_empty():
		return target_layer
	var selected_kind := String(selected_placeable.get("kind", "cell"))
	if selected_kind == "object":
		return TargetLayer.OBJECT
	if selected_kind == "cell":
		var selected_layer := int(selected_placeable.get("layer", target_layer))
		if selected_layer >= TargetLayer.FLOOR and selected_layer <= TargetLayer.OBJECT:
			return selected_layer
	return target_layer


func _rotation_from_grid(grid: GridMap, cell: Vector3i) -> int:
	var basis := grid.get_cell_item_basis(cell)
	var forward := basis * Vector3(0, 0, 1)
	var angle := atan2(forward.x, forward.z)
	return posmod(roundi(angle / (PI * 0.5)), 4)


func _facing_for_quarters() -> Vector2i:
	var directions: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	return directions[rotation_quarters]


func _rotate_facing(facing: Vector2i) -> Vector2i:
	return Vector2i(-facing.y, facing.x)


func _next_object_id(prefix: String) -> StringName:
	var normalized := prefix.to_lower().replace("/", "_").replace(" ", "_")
	var used_ids: Dictionary = {}
	if has_author():
		for node in _descendants(author):
			if _is_marker(node):
				var existing_id := StringName(_property(node, "object_id", node.name))
				if not String(existing_id).is_empty():
					used_ids[existing_id] = true
	var serial := maxi(_object_serial, 1)
	while true:
		var candidate := StringName("%s_%03d" % [normalized, serial])
		serial += 1
		_object_serial = serial
		if not used_ids.has(candidate):
			return candidate
	return StringName()


func _sorted_snapshots(source: Dictionary) -> Array:
	var result: Array = []
	for value in source.values():
		result.append(value)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ac: Vector3i = a.get("cell", Vector3i.ZERO)
		var bc: Vector3i = b.get("cell", Vector3i.ZERO)
		if ac.y != bc.y:
			return ac.y < bc.y
		if ac.z != bc.z:
			return ac.z < bc.z
		return ac.x < bc.x
	)
	return result


func _snapshot_for_cell(snapshots: Array, cell: Vector3i) -> Dictionary:
	for snapshot in snapshots:
		if snapshot.get("cell", Vector3i.ZERO) == cell:
			return snapshot
	return {}


func _snapshot_equal(a: Dictionary, b: Dictionary) -> bool:
	if String(a.get("kind", "")) != String(b.get("kind", "")):
		return false
	if int(a.get("layer", -1)) != int(b.get("layer", -1)):
		return false
	if String(a.get("kind", "")) == "grid":
		return int(a.get("item", -1)) == int(b.get("item", -1)) and int(a.get("orientation", 0)) == int(b.get("orientation", 0))
	var ar: Array = a.get("records", [])
	var br: Array = b.get("records", [])
	if ar.size() != br.size():
		return false
	for index in range(ar.size()):
		var left: Dictionary = ar[index]
		var right: Dictionary = br[index]
		if String(left.get("object_id", "")) != String(right.get("object_id", "")):
			return false
		if int(left.get("kind", 4)) != int(right.get("kind", 4)):
			return false
		if left.get("cell", Vector3i.ZERO) != right.get("cell", Vector3i.ZERO):
			return false
		if left.get("facing", Vector2i.DOWN) != right.get("facing", Vector2i.DOWN):
			return false
		if left.get("scene", null) != right.get("scene", null):
			return false
		if bool(left.get("blocks_movement", false)) != bool(right.get("blocks_movement", false)):
			return false
		if bool(left.get("blocks_los", false)) != bool(right.get("blocks_los", false)):
			return false
		if left.get("loot_table", null) != right.get("loot_table", null):
			return false
		if int(left.get("loot_seed", -1)) != int(right.get("loot_seed", -1)):
			return false
	return true


func _set_status(message: String, valid: bool) -> void:
	_last_status = message
	_last_status_valid = valid
	status_changed.emit(message, valid)


func _emit_changed() -> void:
	changed.emit()
