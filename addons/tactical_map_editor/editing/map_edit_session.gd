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
	SELECT,
	BOX_PAINT,
}

## Stable debug-view IDs.  Keep these values append-only because Dock state can
## survive a tool-script hot reload and because tests/other editor helpers may
## persist the numeric selection.
enum DebugView {
	NORMAL = 0,
	WALKABILITY = 1,
	MOVE_COST = 2,
	SIGHT_BLOCK = 3,
	PROJECTILE_BLOCK = 4,
	OCCLUDER_HEIGHT = 5,
	VALIDATION = 6,
	COVER = 7,
}

enum TargetLayer {
	FLOOR,
	STRUCTURE,
	DECORATION,
	TRAVERSAL,
	SPAWNER,
	OBJECT,
	AI,
}

const MARKER_SCRIPT_PATH := "res://scripts/map_authoring/map_object_marker_3d.gd"
const PROPERTY_SERVICE_SCRIPT := preload("res://scripts/map_authoring/tactical_map_property_service.gd")
const BAKER_SCRIPT := preload("res://scripts/map_authoring/tactical_map_baker.gd")
const FLOOR_GRID_NAME := "FloorGrid"
const STRUCTURE_GRID_NAME := "StructureGrid"
const DECORATION_GRID_NAME := "DecorationGrid"
const OBJECTS_NODE_NAME := "Objects"
const SPAWNS_NODE_NAME := "Spawns"
const TRAVERSAL_LINKS_NODE_NAME := "TraversalLinks"
const PATROL_ROUTES_NODE_NAME := "PatrolRoutes"
const PROPERTY_FIELDS: Array[StringName] = [
	&"WALKABLE",
	&"MOVE_COST",
	&"SIGHT_BLOCK",
	&"PROJECTILE_BLOCK",
	&"OCCLUDER_HEIGHT",
]

var author: Node
var edited_scene_root: Node
var floor_level: int = 0
var target_layer: int = TargetLayer.FLOOR
var tool: int = Tool.PAINT
var rotation_quarters: int = 0
var edit_mode: bool = false
var placeables: Array = []
var selected_placeable: Dictionary = {}
var selected_cells: Array[Vector3i] = []
var _selection_clipboard: Dictionary = {}
var debug_view: int = DebugView.NORMAL
var debug_focus_cell: Vector3i = Vector3i(-1, -1, -1)
var selected_cover_edge_key: String = ""
var _property_service: TacticalMapPropertyService = PROPERTY_SERVICE_SCRIPT.new()
var _cover_debug_snapshot_cache: Dictionary = {}
var _cover_debug_snapshot_cache_valid: bool = false
var _default_baselines: Dictionary = {}

var stroke_active: bool = false
var stroke_label: String = ""
var _stroke_before: Dictionary = {}
var _stroke_after: Dictionary = {}
var _stroke_global_before: Dictionary = {}
var _stroke_global_after: Dictionary = {}
var _object_serial: int = 1
var _marker_serial: int = 1
var _pending_traversal_from: Vector3i = Vector3i(-1, -1, -1)
var _active_patrol_route_id: StringName = &""
var _last_status: String = "选择一个 TacticalMapAuthor 开始编辑。"
var _last_status_valid: bool = true


## A map author is qualified only when the selected object itself is the
## edited scene root.  Do not infer the root by walking parents: the Godot
## editor may place an edited scene below internal editor nodes.
static func is_qualified_author(candidate: Node, edited_scene_root: Node) -> bool:
	if candidate == null or edited_scene_root == null:
		return false
	if not is_instance_valid(candidate) or not is_instance_valid(edited_scene_root):
		return false
	if candidate != edited_scene_root:
		return false
	return candidate is TacticalMapAuthor


## Bind only after validating the exact author/root identity.  Invalid input
## returns before canceling strokes or changing the current scene binding.
func begin_for_author(new_author: Node, new_scene_root: Node = null) -> bool:
	if not is_qualified_author(new_author, new_scene_root):
		_set_status("无法绑定地图：选中节点必须是当前编辑场景根节点且挂载 TacticalMapAuthor。", false)
		return false
	cancel_stroke()
	_clear_selection_internal()
	_selection_clipboard.clear()
	author = new_author
	edited_scene_root = new_scene_root
	floor_level = 0
	target_layer = TargetLayer.FLOOR
	tool = Tool.PAINT
	rotation_quarters = 0
	debug_view = DebugView.NORMAL
	debug_focus_cell = Vector3i(-1, -1, -1)
	selected_cover_edge_key = ""
	_default_baselines.clear()
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
	return true


func clear_author() -> void:
	cancel_stroke()
	_clear_selection_internal()
	_selection_clipboard.clear()
	author = null
	edited_scene_root = null
	placeables.clear()
	selected_placeable.clear()
	_pending_traversal_from = Vector3i(-1, -1, -1)
	_active_patrol_route_id = &""
	debug_view = DebugView.NORMAL
	debug_focus_cell = Vector3i(-1, -1, -1)
	selected_cover_edge_key = ""
	_default_baselines.clear()
	edit_mode = false
	_set_status("选择一个 TacticalMapAuthor 开始编辑。", true)
	_emit_changed()


func has_author() -> bool:
	return is_qualified_author(author, edited_scene_root)


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
	_clear_selection_internal()
	debug_focus_cell = Vector3i(-1, -1, -1)
	selected_cover_edge_key = ""
	floor_level = next_level
	_set_status("当前编辑楼层：%d。" % floor_level, true)
	_emit_changed()


func set_target_layer(value: int) -> void:
	var next_layer := clampi(value, TargetLayer.FLOOR, TargetLayer.AI)
	if target_layer == next_layer:
		return
	cancel_stroke()
	target_layer = next_layer
	_set_status("目标层：%s。" % target_layer_name(target_layer), true)
	_emit_changed()


func set_tool(value: int) -> void:
	var next_tool := clampi(value, Tool.PAINT, Tool.BOX_PAINT)
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
	var next_id := String(placeables[index].get("id", ""))
	var current_id := String(selected_placeable.get("id", ""))
	if not current_id.is_empty() and current_id != next_id and _has_special_edit_in_progress():
		# A special stroke has no implicit editor UndoRedo argument here.  Cancel
		# it instead of silently committing a route/connection without history;
		# the explicit finish_special_edit() API is the commit boundary.
		cancel_stroke()
	selected_placeable = placeables[index].duplicate(true)
	var entry_layer: int = int(selected_placeable.get("layer", TargetLayer.FLOOR))
	if _is_target_layer(entry_layer):
		target_layer = entry_layer
	rotation_quarters = 0
	_set_status("已选择：%s。目标层：%s。" % [selected_placeable.get("label", "素材"), target_layer_name(target_layer)], true)
	_emit_changed()


## Re-read the author/library palette after another editor task adds or edits
## placeable definitions. Selection is restored by stable entry ID whenever
## possible so previews do not silently switch material.
func reload_placeables(preserve_selection: bool = true) -> void:
	var previous_id := String(selected_placeable.get("id", "")) if preserve_selection else ""
	var previous_rotation := rotation_quarters if preserve_selection else 0
	_load_placeables()
	var restored_index := -1
	for index in range(placeables.size()):
		if String(placeables[index].get("id", "")) == previous_id:
			restored_index = index
			break
	if restored_index >= 0:
		selected_placeable = placeables[restored_index].duplicate(true)
		rotation_quarters = previous_rotation
	elif not placeables.is_empty():
		selected_placeable = placeables[0].duplicate(true)
		rotation_quarters = 0
	else:
		selected_placeable.clear()
		rotation_quarters = 0
	_set_status("素材列表已刷新%s。" % ("并保留当前选择" if restored_index >= 0 else "。"), true)
	_emit_changed()


## Configure the template used by the selected player/enemy spawn entry.
## Values are copied into the new marker; this does not mutate definitions.
func set_selected_spawn_configuration(configuration: Dictionary) -> bool:
	if String(selected_placeable.get("kind", "")) != "spawn":
		_set_status("当前素材不是出生点。", false)
		return false
	for key in [&"faction", &"archetype", &"weapon", &"encounter_id", &"patrol_route_id", &"visual_color", &"unit_name_prefix"]:
		if configuration.has(key):
			selected_placeable[key] = configuration[key]
	_set_status("已更新出生点模板配置。", true)
	_emit_changed()
	return true


## Return the configuration currently attached to the selected spawn template.
## The returned dictionary is a copy so a Dock/editor form cannot mutate the
## palette entry without going through set_selected_spawn_configuration().
func get_selected_spawn_configuration() -> Dictionary:
	if String(selected_placeable.get("kind", "")) != "spawn":
		return {}
	return {
		&"archetype": selected_placeable.get("archetype", null),
		&"weapon": selected_placeable.get("weapon", null),
		&"encounter_id": StringName(selected_placeable.get("encounter_id", &"")),
		&"patrol_route_id": StringName(selected_placeable.get("patrol_route_id", &"")),
		&"faction": String(selected_placeable.get("faction", "enemy")),
		&"visual_color": selected_placeable.get("visual_color", Color.WHITE),
		&"unit_name_prefix": String(selected_placeable.get("unit_name_prefix", "EnemySpawn")),
	}


## Stable state contract for the Dock's special placement controls.
## "pending" describes a traversal waiting for its second endpoint;
## "active" describes a patrol route that is still receiving points.
func get_special_edit_state() -> Dictionary:
	var pending := _pending_traversal_from != Vector3i(-1, -1, -1)
	var active_route := _active_patrol_route_id != &""
	var kind := ""
	var label := ""
	if pending:
		kind = "traversal"
		label = "连接已选择起点 %s，请选择终点或取消连接。" % _pending_traversal_from
	elif active_route:
		kind = "patrol"
		label = "巡逻路线 %s 正在绘制，可结束路线。" % _active_patrol_route_id
	else:
		kind = String(selected_placeable.get("kind", "")) if _is_special_placeable() else ""
		if kind == "spawn":
			label = "出生点素材已选中。"
	return {
		&"kind": kind,
		&"pending": pending,
		&"active": active_route,
		&"active_route_id": _active_patrol_route_id,
		&"pending_from": _pending_traversal_from if pending else Vector3i(-1, -1, -1),
		&"can_finish": pending or active_route,
		&"label": label,
	}


## Finish a patrol stroke or cancel a pending traversal.  This is the single
## UI-facing special edit command; the legacy named methods remain available.
func finish_special_edit(undo_redo: Object = null) -> bool:
	if _pending_traversal_from != Vector3i(-1, -1, -1):
		return finish_traversal(undo_redo)
	if _active_patrol_route_id != &"":
		return finish_patrol_route(undo_redo)
	return false


func _has_special_edit_in_progress() -> bool:
	return _pending_traversal_from != Vector3i(-1, -1, -1) or _active_patrol_route_id != &"" or (stroke_active and _is_special_placeable())


func finish_traversal(_undo_redo: Object = null) -> bool:
	if _pending_traversal_from == Vector3i(-1, -1, -1):
		return false
	# The first endpoint starts a stroke and may have created a content root.
	# Cancel the whole uncommitted stroke so the command is a true cancel, not
	# a half-open Undo-less edit.
	if stroke_active and String(selected_placeable.get("kind", "")) == "traversal":
		cancel_stroke()
	else:
		_pending_traversal_from = Vector3i(-1, -1, -1)
	_set_status("已取消待放置的连接起点。", true)
	_emit_changed()
	return true


func finish_patrol_route(undo_redo: Object = null) -> bool:
	if _active_patrol_route_id == &"":
		return false
	var route_id := _active_patrol_route_id
	if stroke_active:
		finish_stroke(undo_redo)
	_active_patrol_route_id = &""
	_set_status("已结束巡逻路线：%s。" % route_id, true)
	_emit_changed()
	return true


func get_placeables(query: String = "", layer_filter: int = -1) -> Array:
	# -1 deliberately means "all layers" for the Dock and older callers.  A
	# concrete layer is an exact semantic filter; searching happens after this
	# filter so a query cannot bring a different author layer back into view.
	if layer_filter != -1 and not _is_target_layer(layer_filter):
		return []
	var needle := query.strip_edges().to_lower()
	var filtered: Array = []
	for entry in placeables:
		if layer_filter != -1 and int(entry.get("layer", -1)) != layer_filter:
			continue
		if not needle.is_empty():
			var haystack := "%s %s %s" % [entry.get("label", ""), entry.get("category", ""), entry.get("id", "")]
			if not haystack.to_lower().contains(needle):
				continue
		filtered.append(entry.duplicate(true))
	return filtered


func get_selected_placeable() -> Dictionary:
	return selected_placeable.duplicate(true)


func get_default_property_context() -> Dictionary:
	if selected_placeable.is_empty():
		return {
			&"available": false,
			&"editable": false,
			&"label": "",
			&"source_id": "",
			&"supported": {},
			&"values": {},
			&"reasons": {},
			&"descriptors": {},
		}
	var source_value := selected_placeable.get("definition", null)
	if source_value == null:
		source_value = selected_placeable.get("rule", null)
	var source := source_value as Resource
	var inspection: Dictionary = _property_service.inspect_default_source(source)
	var supported: Dictionary = {}
	var values: Dictionary = {}
	var reasons: Dictionary = {}
	var descriptors: Dictionary = {}
	for field in PROPERTY_FIELDS:
		supported[field] = false
		reasons[field] = "该素材来源未提供此字段。"
	for descriptor in inspection.get(&"fields", []):
		if not descriptor is Dictionary:
			continue
		var descriptor_id := StringName(String((descriptor as Dictionary).get(&"id", "")).to_upper())
		if not PROPERTY_FIELDS.has(descriptor_id):
			continue
		var descriptor_copy: Dictionary = (descriptor as Dictionary).duplicate(true)
		var field_supported := bool(descriptor_copy.get(&"field_supported", descriptor_copy.get(&"supported", false)))
		if inspection.get(&"source_kind", &"") == &"legacy" and descriptor_id == &"SIGHT_BLOCK":
			# Prefer source-specific constraints from Task A.  Older formal
			# descriptors do not expose them yet; the service still accepts only
			# binary values, so make that constraint explicit in the editor copy.
			if not descriptor_copy.has(&"allowed_values") and not descriptor_copy.has(&"choices") and not descriptor_copy.has(&"constraint") and not descriptor_copy.has(&"constraints"):
				descriptor_copy[&"allowed_values"] = [0.0, 1.0]
				descriptor_copy[&"step"] = 1.0
				descriptor_copy[&"min"] = 0.0
				descriptor_copy[&"max"] = 1.0
		descriptors[descriptor_id] = descriptor_copy
		supported[descriptor_id] = field_supported
		if field_supported:
			values[descriptor_id] = descriptor_copy.get(&"value", null)
		else:
			reasons[descriptor_id] = String(descriptor_copy.get(&"reason", "该素材来源未提供此字段。"))
	var default_api_available := bool(inspection.get(&"valid", false))
	if source == null:
		default_api_available = false
		for field in PROPERTY_FIELDS:
			reasons[field] = "当前素材没有正式默认属性来源。"
	var source_id = inspection.get(&"source_id", selected_placeable.get("id", ""))
	if source != null and not _default_baselines.has(source_id) and default_api_available:
		_default_baselines[source_id] = _property_service.capture_default_state(source)
	return {
		&"available": source != null and bool(inspection.get(&"valid", false)),
		&"editable": has_author() and default_api_available,
		&"label": selected_placeable.get("label", selected_placeable.get("id", "素材")),
		&"source_id": source_id,
		&"source": source,
		&"legacy": selected_placeable.has("rule") and not selected_placeable.has("definition"),
		&"supported": supported,
		&"values": values,
		&"reasons": reasons,
		&"descriptors": descriptors,
		&"formal_service": default_api_available,
	}


func write_default_property(field: StringName, value: Variant, undo_redo: Object = null) -> bool:
	var normalized_field := _normalize_property_field(field)
	var context := get_default_property_context()
	var source := context.get(&"source", null) as Resource
	var descriptor := _property_descriptor(normalized_field)
	if source == null or descriptor.is_empty() or not bool(context.get(&"editable", false)) or not bool(context.get(&"supported", {}).get(normalized_field, false)):
		_set_status("当前素材默认属性尚不可编辑。", false)
		return false
	var before: Dictionary = _property_service.capture_default_state(source)
	if not _property_service.apply_default_field(source, int(descriptor.get(&"field", -1)), value):
		_set_status("默认属性写入失败：正式属性服务拒绝该字段或值。", false)
		return false
	var after: Dictionary = _property_service.capture_default_state(source)
	_property_service.restore_default_state(source, before)
	_commit_default_snapshot(source, before, after, "写入素材默认属性", undo_redo)
	return true


func restore_default_property(field: StringName, undo_redo: Object = null) -> bool:
	var normalized_field := _normalize_property_field(field)
	var context := get_default_property_context()
	var source := context.get(&"source", null) as Resource
	if source == null or _property_descriptor(normalized_field).is_empty() or not bool(context.get(&"editable", false)) or not bool(context.get(&"supported", {}).get(normalized_field, false)):
		_set_status("当前素材默认属性尚不可恢复。", false)
		return false
	var source_id = context.get(&"source_id", selected_placeable.get("id", ""))
	var baseline = _default_baselines.get(source_id, null)
	if not baseline is Dictionary:
		_set_status("没有可恢复的默认属性快照。", false)
		return false
	var before: Dictionary = _property_service.capture_default_state(source)
	var field_snapshot := _default_snapshot_for_field(source, before, baseline, normalized_field)
	if not _property_service.restore_default_state(source, field_snapshot):
		_set_status("默认属性恢复失败：当前值已经是基线或正式服务拒绝恢复。", false)
		return false
	var after: Dictionary = _property_service.capture_default_state(source)
	_property_service.restore_default_state(source, before)
	_commit_default_snapshot(source, before, after, "恢复素材默认属性", undo_redo)
	return true


func _default_snapshot_for_field(source: Resource, current: Dictionary, baseline: Dictionary, field: StringName) -> Dictionary:
	if source is TacticalCellTileDefinition and baseline.get(&"source_kind", &"") == &"definition":
		var current_rules := current.get(&"rules", null) as TacticalCellRules
		var baseline_rules := baseline.get(&"rules", null) as TacticalCellRules
		var target_rules := current_rules.duplicate_rules() if current_rules != null else TacticalCellRules.new()
		var default_rules := baseline_rules if baseline_rules != null else TacticalCellRules.new()
		var descriptor := _property_descriptor(field)
		_write_default_rules_field(target_rules, int(descriptor.get(&"field", -1)), _read_rules_field(default_rules, int(descriptor.get(&"field", -1))))
		var snapshot := baseline.duplicate(true)
		if baseline_rules == null and _rules_match_builtin_defaults(target_rules):
			snapshot[&"rule_contribution_present"] = false
			snapshot[&"rules"] = null
		else:
			snapshot[&"rule_contribution_present"] = true
			snapshot[&"rules"] = target_rules
		return snapshot
	if source is MapTileRule and baseline.get(&"source_kind", &"") == &"legacy":
		var snapshot := current.duplicate(true)
		match field:
			&"WALKABLE":
				snapshot[&"walkable"] = baseline.get(&"walkable", snapshot.get(&"walkable", true))
			&"MOVE_COST":
				snapshot[&"move_cost"] = baseline.get(&"move_cost", snapshot.get(&"move_cost", 1))
			&"SIGHT_BLOCK":
				snapshot[&"blocks_los"] = baseline.get(&"blocks_los", snapshot.get(&"blocks_los", false))
			&"OCCLUDER_HEIGHT":
				snapshot[&"occluder_height"] = baseline.get(&"occluder_height", snapshot.get(&"occluder_height", 0.0))
		return snapshot
	return baseline.duplicate(true)


func get_last_status() -> Dictionary:
	return {"message": _last_status, "valid": _last_status_valid}


func set_debug_view(value: int) -> void:
	var next_view := clampi(value, DebugView.NORMAL, DebugView.COVER)
	if debug_view == next_view:
		return
	debug_view = next_view
	if debug_view != DebugView.COVER:
		selected_cover_edge_key = ""
	_set_status("调试视图：%s。" % debug_view_name(), true)
	_emit_changed()


func get_debug_view() -> int:
	return debug_view


func debug_view_name(value: int = debug_view) -> String:
	match value:
		DebugView.NORMAL:
			return "Normal"
		DebugView.WALKABILITY:
			return "Walkability"
		DebugView.MOVE_COST:
			return "Move Cost"
		DebugView.SIGHT_BLOCK:
			return "Sight Block"
		DebugView.PROJECTILE_BLOCK:
			return "Projectile Block"
		DebugView.OCCLUDER_HEIGHT:
			return "Occluder Height"
		DebugView.VALIDATION:
			return "Validation"
		DebugView.COVER:
			return "Cover / 掩体"
	return "Normal"


func debug_view_legend(value: int = debug_view) -> String:
	match value:
		DebugView.NORMAL:
			return "正常模型；调试覆盖已关闭。"
		DebugView.WALKABILITY:
			return "绿色=地图初始可走；红色=被地格、Structure 或 Object 阻挡。"
		DebugView.MOVE_COST:
			return "绿色=低消耗，红色=高消耗。"
		DebugView.SIGHT_BLOCK:
			return "蓝绿色=低阻挡，橙红色=高阻挡。"
		DebugView.PROJECTILE_BLOCK:
			return "蓝绿色=低阻挡，橙红色=高阻挡。"
		DebugView.OCCLUDER_HEIGHT:
			return "按遮挡高度由低到高渐变。"
		DebugView.VALIDATION:
			return "红色=错误，黄色=警告；点击列表可定位。"
		DebugView.COVER:
			return "边界线=掩体边；箭头指向受保护侧；颜色/长度区分 HALF 与 FULL。红色表示冲突或非法来源。"
	return ""


func set_debug_focus(cell: Vector3i, allow_missing_floor: bool = false) -> bool:
	if not has_author():
		_set_status("无法定位：没有活动的 TacticalMapAuthor。", false)
		return false
	if not allow_missing_floor and not _inside_volume(cell):
		_set_status("无法定位：楼层坐标超出可编辑范围。", false)
		return false
	if not allow_missing_floor and not _has_floor_cell(cell):
		_set_status("无法定位：该坐标没有可编译 Floor 地格。", false)
		return false
	debug_focus_cell = cell
	if not _inside_volume(cell):
		_set_status("已记录非法楼层诊断坐标 %s，使用最佳努力高亮。" % cell, true)
	elif not _has_floor_cell(cell):
		_set_status("已定位到缺少 Floor 的诊断坐标 %s。" % cell, true)
	else:
		_set_status("已定位到地格 %s。" % cell, true)
	_emit_changed()
	return true


func clear_debug_focus() -> void:
	if debug_focus_cell == Vector3i(-1, -1, -1):
		return
	debug_focus_cell = Vector3i(-1, -1, -1)
	_emit_changed()


func focus_validation_cell(cell: Vector3i) -> bool:
	if not has_author():
		_set_status("无法定位：没有活动的 TacticalMapAuthor。", false)
		return false
	var inside_volume := _inside_volume(cell)
	var legal_floor := _inside_volume(cell)
	if legal_floor and cell.y != floor_level:
		set_floor_level(cell.y)
	# Ordinary selection remains Floor-only.  Validation focus is deliberately
	# broader so missing-Floor and out-of-volume diagnostics can still be shown.
	if inside_volume and _has_floor_cell(cell):
		if not select_cell(cell) and not is_cell_selected(cell):
			return false
	return set_debug_focus(cell, true)


func inspect_debug_cells() -> Dictionary:
	var map_author := author as TacticalMapAuthor
	if map_author == null:
		return {&"cells": [], &"errors": [], &"warnings": [], &"diagnostics": []}
	var inspection := _merge_validation_debug_cells(
		_property_service.inspect_all_cells(map_author),
		get_validation_diagnostics()
	)
	_annotate_initial_object_walkability(inspection)
	return inspection


## Read-only cover view contract. The Baker remains the sole source of final
## Edge data; this adapter only copies the in-memory result into stable plain
## dictionaries for the editor overlay and diagnostics panel.
func get_cover_debug_snapshot() -> Dictionary:
	var map_author := author as TacticalMapAuthor
	var empty_snapshot := {
		&"floor_level": floor_level,
		&"author_grid_origin": Vector3.ZERO,
		&"definition_origin": Vector3.ZERO,
		&"cell_size": Vector3.ZERO,
		&"edges": [],
		&"diagnostics": [],
		&"errors": [],
		&"warnings": [],
	}
	if map_author == null or not has_author():
		return empty_snapshot
	if _cover_debug_snapshot_cache_valid:
		return _cover_debug_snapshot_cache.duplicate(true)
	var build_result: Dictionary = BAKER_SCRIPT.build(map_author)
	var definition := build_result.get(&"definition", null) as TacticalMapDefinition
	if definition == null:
		return empty_snapshot
	var raw_diagnostics: Array = build_result.get(&"diagnostics", [])
	var diagnostics: Array[Dictionary] = []
	for value in raw_diagnostics:
		if value is Dictionary and _cover_diagnostic_on_floor(value as Dictionary):
			diagnostics.append((value as Dictionary).duplicate(true))
	var edges: Array[Dictionary] = []
	var matched_diagnostic_indices: Dictionary = {}
	for edge in definition.edges:
		if edge == null:
			continue
		if edge.cell_a.y != floor_level and edge.cell_b.y != floor_level:
			continue
		var author_a := runtime_cell_to_author_cell(edge.cell_a, definition, map_author)
		var author_b := runtime_cell_to_author_cell(edge.cell_b, definition, map_author)
		var author_source := runtime_cell_to_author_cell(edge.source_cell, definition, map_author)
		var edge_diagnostics: Array[Dictionary] = []
		for diagnostic_index in range(diagnostics.size()):
			var diagnostic: Dictionary = diagnostics[diagnostic_index]
			if _cover_diagnostic_matches_edge(diagnostic, edge, author_a, author_b, author_source):
				edge_diagnostics.append(diagnostic.duplicate(true))
				matched_diagnostic_indices[diagnostic_index] = true
		edges.append(_cover_debug_edge_record(edge, author_a, author_b, author_source, edge_diagnostics))
	for diagnostic_index in range(diagnostics.size()):
		if matched_diagnostic_indices.has(diagnostic_index):
			continue
		var diagnostic: Dictionary = diagnostics[diagnostic_index]
		var code := String(diagnostic.get(&"code", diagnostic.get(&"id", "")))
		if code not in ["TMB-067", "TMB-068"]:
			continue
		var coordinate := diagnostic.get(&"coordinate", null)
		if not coordinate is Vector3i:
			continue
		var author_cell: Vector3i = coordinate
		edges.append({
			&"edge_key": "diagnostic:%s:%s" % [code, author_cell],
			&"runtime_edge_key": "",
			&"cell_a": author_cell,
			&"cell_b": null,
			&"source_cell": author_cell,
			&"source_type": &"diagnostic",
			&"source_layer": &"",
			&"source_placeable_id": &"",
			&"source_mesh_item_id": -1,
			&"runtime_source_cell": null,
			&"profile_a": {},
			&"profile_b": {},
			&"diagnostics": [diagnostic.duplicate(true)],
			&"invalid_or_conflict": true,
			&"diagnostic_only": true,
		})
	edges.sort_custom(_cover_debug_edge_less)
	var snapshot := {
		&"floor_level": floor_level,
		&"author_grid_origin": map_author.grid_origin,
		&"definition_origin": definition.origin,
		&"cell_size": definition.cell_size,
		&"edges": edges,
		&"diagnostics": diagnostics,
		&"errors": Array(build_result.get(&"errors", [])).duplicate(),
		&"warnings": Array(build_result.get(&"warnings", [])).duplicate(),
	}
	_cover_debug_snapshot_cache = snapshot.duplicate(true)
	_cover_debug_snapshot_cache_valid = true
	return snapshot


## Return the currently selected baked edge as a detached dictionary. The
## selection stores only the stable canonical edge key so a map rebuild cannot
## leave the Dock holding a stale Resource reference.
func get_selected_cover_edge() -> Dictionary:
	if selected_cover_edge_key.is_empty():
		return {}
	var snapshot := get_cover_debug_snapshot()
	for edge_value in snapshot.get(&"edges", []):
		if not edge_value is Dictionary:
			continue
		var edge := edge_value as Dictionary
		if String(edge.get(&"edge_key", "")) == selected_cover_edge_key:
			return edge.duplicate(true)
	# A bake/resource refresh may remove the selected edge. Drop the key as soon
	# as that happens so the inspector cannot keep pointing at a phantom edge or
	# unexpectedly reselect it if a resource later comes back.
	selected_cover_edge_key = ""
	return {}


func get_selected_cover_edge_key() -> String:
	return selected_cover_edge_key


func select_cover_edge(edge_key: String) -> bool:
	if not has_author():
		_set_status("无法选择掩体边：没有活动的 TacticalMapAuthor。", false)
		return false
	var requested_key := edge_key.strip_edges()
	if requested_key.is_empty():
		return clear_cover_edge_selection()
	var snapshot := get_cover_debug_snapshot()
	for edge_value in snapshot.get(&"edges", []):
		if not edge_value is Dictionary:
			continue
		var edge := edge_value as Dictionary
		if String(edge.get(&"edge_key", "")) != requested_key:
			continue
		selected_cover_edge_key = requested_key
		_set_status("已选中掩体边：%s。" % requested_key, true)
		_emit_changed()
		return true
	_set_status("未找到掩体边：%s。" % requested_key, false)
	return false


func clear_cover_edge_selection() -> bool:
	if selected_cover_edge_key.is_empty():
		return false
	selected_cover_edge_key = ""
	_set_status("已清除掩体边选择。", true)
	_emit_changed()
	return true


## Baker normalizes X/Z coordinates but moves the definition origin by the
## same physical amount. Recovering the integer authoring shift from those two
## origins avoids assuming a particular map minimum or fixed layout.
static func runtime_cell_to_author_cell(runtime_cell: Vector3i, definition: TacticalMapDefinition, map_author: TacticalMapAuthor) -> Vector3i:
	if definition == null or map_author == null:
		return runtime_cell
	var cell_size := definition.cell_size
	if cell_size.x <= 0.0 or cell_size.z <= 0.0:
		cell_size = map_author.cell_dimensions
	if cell_size.x <= 0.0 or cell_size.z <= 0.0:
		return runtime_cell
	var origin_delta := definition.origin - map_author.grid_origin
	var shift := Vector3i(
		int(roundf(origin_delta.x / cell_size.x)),
		0,
		int(roundf(origin_delta.z / cell_size.z))
	)
	return runtime_cell + shift


func _cover_debug_edge_record(edge: MapEdgeData, author_a: Vector3i, author_b: Vector3i, author_source: Vector3i, edge_diagnostics: Array[Dictionary]) -> Dictionary:
	var profile_a := _cover_debug_profile(edge.cover_profile_a)
	var profile_b := _cover_debug_profile(edge.cover_profile_b)
	var invalid_or_conflict := false
	for diagnostic in edge_diagnostics:
		var code := String(diagnostic.get(&"code", diagnostic.get(&"id", "")))
		if code in ["TMB-063", "TMB-067", "TMB-068"]:
			invalid_or_conflict = true
			break
	return {
		&"edge_key": _cover_edge_key(author_a, author_b),
		&"runtime_edge_key": edge.key_string(),
		&"cell_a": author_a,
		&"cell_b": author_b,
		&"runtime_cell_a": edge.cell_a,
		&"runtime_cell_b": edge.cell_b,
		&"source_cell": author_source,
		&"runtime_source_cell": edge.source_cell,
		&"source_type": edge.source_type,
		&"source_layer": edge.source_layer,
		&"source_placeable_id": edge.source_placeable_id,
		&"source_mesh_item_id": edge.source_mesh_item_id,
		&"cover_a": int(edge.cover_a),
		&"cover_b": int(edge.cover_b),
		&"profile_a": profile_a,
		&"profile_b": profile_b,
		&"blocks_movement": edge.blocks_movement,
		&"sight_block": edge.sight_block,
		&"projectile_block": edge.projectile_block,
		&"height": edge.height,
		&"destructible": edge.destructible,
		&"runtime_state_id": edge.runtime_state_id,
		&"diagnostics": edge_diagnostics,
		&"invalid_or_conflict": invalid_or_conflict,
		&"diagnostic_only": false,
	}


func _cover_debug_profile(profile: TacticalCoverProfile) -> Dictionary:
	if profile == null:
		return {}
	return {
		&"id": profile.cover_id,
		&"display_name": profile.display_name,
		&"level": profile.cover_level,
		&"level_name": profile.get_level_name(),
		&"reduction": profile.damage_reduction_ratio,
		&"damage_reduction_ratio": profile.damage_reduction_ratio,
		&"debug_color": profile.debug_color,
		&"tags": profile.tags.duplicate(),
		&"valid": profile.is_valid(),
	}


func _cover_diagnostic_on_floor(diagnostic: Dictionary) -> bool:
	var coordinate := diagnostic.get(&"coordinate", null)
	return not coordinate is Vector3i or (coordinate as Vector3i).y == floor_level


func _cover_diagnostic_matches_edge(diagnostic: Dictionary, edge: MapEdgeData, author_a: Vector3i, author_b: Vector3i, author_source: Vector3i) -> bool:
	var coordinate := diagnostic.get(&"coordinate", null)
	var message := String(diagnostic.get(&"message", diagnostic.get(&"text", "")))
	if coordinate is Vector3i and (coordinate == edge.source_cell or coordinate == author_a or coordinate == author_b or coordinate == author_source):
		return true
	return message.contains(edge.key_string()) or message.contains(_cover_edge_key(author_a, author_b))


static func _cover_edge_key(cell_a: Vector3i, cell_b: Vector3i) -> String:
	var first := cell_a
	var second := cell_b
	if _cover_cell_less(second, first):
		first = cell_b
		second = cell_a
	return "%d,%d,%d|%d,%d,%d" % [first.x, first.y, first.z, second.x, second.y, second.z]


static func _cover_cell_less(first: Vector3i, second: Vector3i) -> bool:
	if first.y != second.y:
		return first.y < second.y
	if first.z != second.z:
		return first.z < second.z
	return first.x < second.x


static func _cover_debug_edge_less(first: Dictionary, second: Dictionary) -> bool:
	return String(first.get(&"edge_key", "")) < String(second.get(&"edge_key", ""))


func get_debug_cells() -> Array:
	return get_debug_cells_for_view(debug_view)


func get_debug_cells_for_view(view: int = debug_view) -> Array[Dictionary]:
	## Return only records that are drawable for the requested debug view.
	## Validation-only coordinates are diagnostic locations, not compiled Floor
	## cells, so heatmap views must never render them as ordinary terrain.
	var requested_view := clampi(view, DebugView.NORMAL, DebugView.COVER)
	if requested_view == DebugView.COVER:
		return []
	var result: Array[Dictionary] = []
	for value in inspect_debug_cells().get(&"cells", []):
		if not value is Dictionary:
			continue
		var record: Dictionary = value as Dictionary
		var validation_only := bool(record.get(&"validation_only", false))
		if validation_only and requested_view != DebugView.VALIDATION:
			continue
		if not validation_only and record.has(&"has_floor") and not bool(record.get(&"has_floor", false)):
			continue
		result.append(record)
	return result


func get_validation_diagnostics() -> Array[Dictionary]:
	var map_author := author as TacticalMapAuthor
	if map_author == null:
		return []
	return _copy_structured_diagnostics(_property_service.validation_diagnostics(map_author))


func get_debug_focus_cell() -> Vector3i:
	return debug_focus_cell


func get_debug_value(cell_inspection: Dictionary, field: StringName) -> Variant:
	var normalized := String(field).to_lower()
	# Cell rules intentionally exclude dynamic Object occupancy so a destroyed
	# blocker can make its cell available again at runtime. The authoring
	# Walkability view, however, describes the initial playable map and must
	# include blocking MapObjectPlacement instances just like Controller setup.
	if normalized == "walkable" and cell_inspection.has(&"initial_walkable"):
		return cell_inspection[&"initial_walkable"]
	var descriptor := _property_descriptor(StringName(normalized.to_upper()))
	var field_bit := int(descriptor.get(&"field", -1))
	var rules: Variant = cell_inspection.get(&"effective_rules", cell_inspection.get(&"effective", cell_inspection.get(&"rules", null)))
	return _read_debug_rules_field(rules, field_bit, normalized)


func get_selected_cells() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for cell in selected_cells:
		result.append(cell)
	return result


func selected_cell_count() -> int:
	return selected_cells.size()


func is_cell_selected(cell: Vector3i) -> bool:
	return selected_cells.has(cell)


func clear_selection() -> bool:
	if selected_cells.is_empty():
		return false
	_clear_selection_internal()
	_set_status("已清空地格选择。", true)
	_emit_changed()
	return true


func select_cell(cell: Vector3i, additive: bool = false, toggle: bool = false) -> bool:
	if not has_author():
		_set_status("没有活动的 TacticalMapAuthor。", false)
		return false
	if not _inside_volume(cell):
		_set_status("楼层坐标超出可编辑范围。", false)
		return false
	var selection_check := can_edit_cell(cell, Tool.SELECT)
	if not bool(selection_check.get("valid", false)):
		_set_status(String(selection_check.get("reason", "该坐标没有可编译 Floor 地格。")), false)
		return false

	var next_selection: Array[Vector3i] = []
	if additive:
		next_selection = get_selected_cells()
		if toggle and next_selection.has(cell):
			next_selection.erase(cell)
		else:
			next_selection.append(cell)
	else:
		next_selection.append(cell)
	_sort_cells(next_selection)
	if next_selection == selected_cells:
		return false
	selected_cells = next_selection
	_set_status("已选择 %d 格。" % selected_cells.size(), true)
	_emit_changed()
	return true


## Select every compiled Floor cell inside the X/Z rectangle on the current
## floor. Shift-style additive/toggle selection is handled here so the editor
## viewport can provide a real drag-to-select interaction instead of relying
## on a modifier key for every individual cell.
func select_cells_in_rect(from_cell: Vector3i, to_cell: Vector3i, additive: bool = false, toggle: bool = false) -> bool:
	if not has_author():
		_set_status("没有活动的 TacticalMapAuthor。", false)
		return false
	if from_cell.y != to_cell.y or from_cell.y != floor_level:
		_set_status("框选范围必须位于当前编辑楼层。", false)
		return false
	var min_x := mini(from_cell.x, to_cell.x)
	var max_x := maxi(from_cell.x, to_cell.x)
	var min_z := mini(from_cell.z, to_cell.z)
	var max_z := maxi(from_cell.z, to_cell.z)
	var rectangle: Array[Vector3i] = []
	for z in range(min_z, max_z + 1):
		for x in range(min_x, max_x + 1):
			var cell := Vector3i(x, floor_level, z)
			if _inside_volume(cell) and _has_floor_cell(cell):
				rectangle.append(cell)
	var next_selection: Array[Vector3i] = []
	if additive:
		next_selection = get_selected_cells()
		for cell in rectangle:
			if toggle and next_selection.has(cell):
				next_selection.erase(cell)
			elif not next_selection.has(cell):
				next_selection.append(cell)
	else:
		next_selection = rectangle
	_sort_cells(next_selection)
	if next_selection == selected_cells:
		return false
	selected_cells = next_selection
	_set_status("已选择 %d 格。" % selected_cells.size(), true)
	_emit_changed()
	return true


func has_selection_clipboard() -> bool:
	return not _selection_clipboard.is_empty()


## Replace the content on every selected cell with the currently selected
## Cell/Object placeable. One call produces one editor Undo action.
func selection_replace(undo_redo: Object = null) -> bool:
	var cells := get_selected_cells()
	if cells.is_empty():
		_set_status("没有选中的地格。", false)
		return false
	if selected_placeable.is_empty():
		_set_status("素材栏中没有选中素材。", false)
		return false
	var layer := _paint_effective_layer()
	if not _is_grid_layer(layer) and layer != TargetLayer.OBJECT:
		_set_status("当前素材不能用于替换选中的地格。", false)
		return false
	if layer == TargetLayer.OBJECT and _objects_root() == null:
		_set_status("作者场景缺少 Objects 节点。", false)
		return false
	var before := _capture_selection_layer_snapshots(cells, layer)
	var changed := false
	if layer == TargetLayer.OBJECT:
		for cell in cells:
			if _replace_object_at(cell):
				changed = true
	else:
		var grid := _grid_for_layer(layer)
		var item_id := int(selected_placeable.get("item_id", -1))
		if grid == null or item_id < 0:
			_set_status("当前素材没有有效的 GridMap item_id。", false)
			return false
		var orientation := _orientation_for_quarters(layer)
		for cell in cells:
			if grid.get_cell_item(cell) != item_id or grid.get_cell_item_orientation(cell) != orientation:
				grid.set_cell_item(cell, item_id, orientation)
				changed = true
	if not changed:
		_set_status("替换没有产生变化。", true)
		return false
	var after := _capture_selection_layer_snapshots(cells, layer)
	return _commit_selection_operation(before, after, "替换选中地格", undo_redo, cells, cells)


## Rotate every selected cell on the current target layer by 90 degrees.
func selection_rotate(undo_redo: Object = null) -> bool:
	var cells := get_selected_cells()
	if cells.is_empty():
		_set_status("没有选中的地格。", false)
		return false
	var layer := target_layer
	if not _is_grid_layer(layer) and layer != TargetLayer.OBJECT and layer != TargetLayer.SPAWNER:
		_set_status("当前目标层不支持批量旋转。", false)
		return false
	var before := _capture_selection_layer_snapshots(cells, layer)
	var changed := false
	for cell in cells:
		if _rotate_at(cell):
			changed = true
	if not changed:
		_set_status("选中的地格没有可旋转内容。", false)
		return false
	var after := _capture_selection_layer_snapshots(cells, layer)
	return _commit_selection_operation(before, after, "旋转选中地格", undo_redo, cells, cells)


## Delete the current target-layer content from every selected cell.
func selection_delete(undo_redo: Object = null) -> bool:
	var cells := get_selected_cells()
	if cells.is_empty():
		_set_status("没有选中的地格。", false)
		return false
	var layer := target_layer
	if not _is_grid_layer(layer) and layer != TargetLayer.OBJECT and layer != TargetLayer.SPAWNER and layer != TargetLayer.TRAVERSAL and layer != TargetLayer.AI:
		_set_status("当前目标层不支持删除。", false)
		return false
	var before := _capture_selection_layer_snapshots(cells, layer)
	var changed := false
	for cell in cells:
		var cell_changed := false
		match layer:
			TargetLayer.OBJECT:
				cell_changed = _clear_layer_at(cell, layer)
			TargetLayer.SPAWNER:
				cell_changed = _erase_spawn_at(cell)
			TargetLayer.TRAVERSAL:
				cell_changed = _erase_traversal_at(cell)
			TargetLayer.AI:
				cell_changed = _erase_patrol_at(cell)
			_:
				cell_changed = _clear_layer_at(cell, layer)
		changed = changed or cell_changed
	if not changed:
		_set_status("选中的地格没有可删除内容。", false)
		return false
	var after := _capture_selection_layer_snapshots(cells, layer)
	return _commit_selection_operation(before, after, "删除选中地格内容", undo_redo, cells, cells)


## Move the selected content as a group. The destination must be inside the
## map volume and cannot overwrite unrelated content.
func selection_move(delta: Vector3i, undo_redo: Object = null) -> bool:
	var cells := get_selected_cells()
	if cells.is_empty():
		_set_status("没有选中的地格。", false)
		return false
	if delta == Vector3i.ZERO or delta.y != 0:
		_set_status("移动方向必须是 X/Z 轴上的非零偏移。", false)
		return false
	var layer := target_layer
	if not _is_grid_layer(layer) and layer != TargetLayer.OBJECT:
		_set_status("当前目标层暂不支持批量移动。", false)
		return false
	var destinations: Array[Vector3i] = []
	for cell in cells:
		var destination := cell + delta
		if not _inside_volume(destination):
			_set_status("移动目标超出地图楼层范围。", false)
			return false
		if layer != TargetLayer.FLOOR and not _has_floor_cell(destination):
			_set_status("移动目标必须位于有效 Floor 上。", false)
			return false
		destinations.append(destination)
	var has_content := false
	for cell in cells:
		if _selection_layer_has_content(cell, layer):
			has_content = true
			break
	if not has_content:
		_set_status("选中的目标层没有可移动内容。", false)
		return false
	for destination in destinations:
		if cells.has(destination):
			continue
		if _selection_layer_has_content(destination, layer):
			_set_status("移动目标已有内容，操作已取消。", false)
			return false
	var operation_cells: Array[Vector3i] = []
	for cell in cells:
		if not operation_cells.has(cell):
			operation_cells.append(cell)
	for destination in destinations:
		if not operation_cells.has(destination):
			operation_cells.append(destination)
	_sort_cells(operation_cells)
	var before := _capture_selection_layer_snapshots(operation_cells, layer)
	var source_snapshots := _capture_selection_layer_snapshots(cells, layer)
	for cell in cells:
		_clear_layer_at(cell, layer)
	for index in range(source_snapshots.size()):
		var moved_snapshot := _relocate_content_snapshot(source_snapshots[index], destinations[index], false)
		_apply_snapshot(moved_snapshot)
	var after := _capture_selection_layer_snapshots(operation_cells, layer)
	var next_selection: Array[Vector3i] = []
	for destination in destinations:
		next_selection.append(destination)
	_sort_cells(next_selection)
	return _commit_selection_operation(before, after, "移动选中地格内容", undo_redo, cells, next_selection)


## Copy the current target-layer content to the session clipboard. Clipboard
## state is editor-session state and is intentionally not an Undo action.
func selection_copy() -> bool:
	var cells := get_selected_cells()
	if cells.is_empty():
		_set_status("没有选中的地格。", false)
		return false
	var layer := target_layer
	if not _is_grid_layer(layer) and layer != TargetLayer.OBJECT:
		_set_status("当前目标层暂不支持复制。", false)
		return false
	var anchor := cells[0]
	var entries: Array = []
	for cell in cells:
		entries.append({
			&"offset": cell - anchor,
			&"snapshot": _capture_layer_snapshot(cell, layer),
		})
	_selection_clipboard = {
		&"layer": layer,
		&"entries": entries,
		&"source_cells": cells.duplicate(),
	}
	_set_status("已复制 %d 格，可选择目标起点后粘贴。" % entries.size(), true)
	_emit_changed()
	return true


## Paste the clipboard with the first selected cell as its anchor. Pasted
## content replaces the destination cells and is recorded as one Undo action.
func selection_paste(undo_redo: Object = null) -> bool:
	if _selection_clipboard.is_empty():
		_set_status("剪贴板为空，请先复制选中地格。", false)
		return false
	var cells := get_selected_cells()
	if cells.is_empty():
		_set_status("请先选择粘贴起点。", false)
		return false
	var layer := int(_selection_clipboard.get(&"layer", -1))
	if layer != target_layer:
		_set_status("粘贴需要切换到与剪贴板相同的目标层：%s。" % target_layer_name(layer), false)
		return false
	var entries: Array = _selection_clipboard.get(&"entries", [])
	if entries.is_empty():
		_set_status("剪贴板中没有可粘贴内容。", false)
		return false
	var anchor := cells[0]
	var valid_entries: Array = []
	var destinations: Array[Vector3i] = []
	for entry_value in entries:
		if not entry_value is Dictionary:
			continue
		valid_entries.append(entry_value)
		var offset_value = entry_value.get(&"offset", Vector3i.ZERO)
		var offset: Vector3i = offset_value if offset_value is Vector3i else Vector3i.ZERO
		var destination := anchor + offset
		if not _inside_volume(destination):
			_set_status("粘贴目标超出地图楼层范围。", false)
			return false
		if layer != TargetLayer.FLOOR and not _has_floor_cell(destination):
			_set_status("粘贴目标必须位于有效 Floor 上。", false)
			return false
		destinations.append(destination)
	if destinations.is_empty():
		_set_status("剪贴板中没有有效粘贴目标。", false)
		return false
	var before := _capture_selection_layer_snapshots(destinations, layer)
	for index in range(destinations.size()):
		var source_entry: Dictionary = valid_entries[index]
		var source_snapshot: Dictionary = source_entry.get(&"snapshot", {})
		var pasted_snapshot := _relocate_content_snapshot(source_snapshot, destinations[index], layer == TargetLayer.OBJECT)
		_apply_snapshot(pasted_snapshot)
	var after := _capture_selection_layer_snapshots(destinations, layer)
	var next_selection: Array[Vector3i] = []
	for destination in destinations:
		next_selection.append(destination)
	_sort_cells(next_selection)
	return _commit_selection_operation(before, after, "粘贴选中地格内容", undo_redo, cells, next_selection)


func get_property_fields() -> Array[StringName]:
	var result: Array[StringName] = []
	for descriptor in get_property_descriptors():
		var field := StringName(String(descriptor.get(&"id", "")).to_upper())
		result.append(field)
	return result


func get_property_descriptors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for descriptor in _property_service.field_descriptors():
		var field := StringName(String(descriptor.get(&"id", "")).to_upper())
		if PROPERTY_FIELDS.has(field):
			result.append(descriptor.duplicate(true))
	return result


func get_cell_properties(cell: Vector3i) -> Dictionary:
	var coordinates: Array[Vector3i] = [cell]
	var inspected_result := _property_service.inspect_cells(author as TacticalMapAuthor, coordinates)
	var inspected: Array = inspected_result.get(&"cells", [])
	return _properties_from_inspection(inspected[0]) if not inspected.is_empty() else {}


func get_selected_property_summary() -> Dictionary:
	var result: Dictionary = {}
	var cells := get_selected_cells()
	var inspected_result := _property_service.inspect_cells(author as TacticalMapAuthor, cells) if not cells.is_empty() else {}
	var properties_by_cell: Dictionary = {}
	for inspection in inspected_result.get(&"cells", []):
		var inspection_dictionary: Dictionary = inspection
		properties_by_cell[inspection_dictionary.get(&"coordinate", Vector3i.ZERO)] = _properties_from_inspection(inspection_dictionary)
	for field in PROPERTY_FIELDS:
		if cells.is_empty():
			result[field] = {"mixed": false, "value": null, "state": "未选择", "inherited": true}
			continue
		var first_value = null
		var first_base = null
		var first_override = null
		var same_value := true
		var same_base := true
		var same_override := true
		var inherited_count := 0
		for index in range(cells.size()):
			var cell_properties: Dictionary = properties_by_cell.get(cells[index], {})
			var property_value: Dictionary = cell_properties.get(field, {"value": null, "inherited": true})
			if index == 0:
				first_value = property_value.get("value")
				first_base = property_value.get("base")
				first_override = property_value.get("override")
			elif property_value.get("value") != first_value:
				same_value = false
			# Keep each comparison independent: a base difference must not hide
			# an override/final difference in the same multi-cell selection.
			if index > 0:
				if property_value.get("base") != first_base:
					same_base = false
				if property_value.get("override") != first_override:
					same_override = false
			if bool(property_value.get("inherited", true)):
				inherited_count += 1
		var state := "继承"
		if inherited_count == 0:
			state = "覆盖"
		elif inherited_count != cells.size():
			state = "混合"
		var base_display := _format_property_value(first_base) if same_base else "混合"
		var override_display := "—" if inherited_count == cells.size() else (_format_property_value(first_override) if same_override else "混合")
		result[field] = {
			"mixed": not same_value,
			"value": first_value if same_value else null,
			"display": _format_property_value(first_value) if same_value else "混合",
			"base": first_base if same_base else null,
			"base_mixed": not same_base,
			"base_display": base_display,
			"override": first_override if same_override else null,
			"override_mixed": not same_override,
			"override_display": override_display,
			"state": state,
			"inherited": inherited_count == cells.size(),
			"override_count": cells.size() - inherited_count,
		}
	return result


func write_property_override(field: StringName, value: Variant, cells: Array = [], undo_redo: Object = null) -> bool:
	var normalized_field := _normalize_property_field(field)
	var descriptor := _property_descriptor(normalized_field)
	var map_author := author as TacticalMapAuthor
	if normalized_field == &"" or descriptor.is_empty() or map_author == null:
		_set_status("未知地格属性：%s。" % field, false)
		return false
	var target_cells := _property_target_cells(cells)
	if target_cells.is_empty():
		_set_status("没有可写入覆盖的地格。", false)
		return false
	var before := _property_service.capture_override_state(map_author, target_cells)
	if not _property_service.apply_override_field(map_author, target_cells, int(descriptor[&"field"]), value):
		_set_status("属性覆盖写入失败：正式属性服务拒绝该字段、值或目标地格。", false)
		return false
	var after := _property_service.capture_override_state(map_author, target_cells)
	_property_service.restore_override_state(map_author, before)
	_commit_property_snapshot(map_author, target_cells, before, after, "写入地格属性覆盖", undo_redo)
	return true


func clear_property_override(field: StringName, cells: Array = [], undo_redo: Object = null) -> bool:
	var normalized_field := _normalize_property_field(field)
	var descriptor := _property_descriptor(normalized_field)
	var map_author := author as TacticalMapAuthor
	if normalized_field == &"" or descriptor.is_empty() or map_author == null:
		_set_status("未知地格属性：%s。" % field, false)
		return false
	var target_cells := _property_target_cells(cells)
	if target_cells.is_empty():
		_set_status("没有可恢复继承的地格。", false)
		return false
	var before := _property_service.capture_override_state(map_author, target_cells)
	if not _property_service.clear_override_field(map_author, target_cells, int(descriptor[&"field"])):
		_set_status("恢复继承失败：正式属性服务拒绝该字段或目标地格。", false)
		return false
	var after := _property_service.capture_override_state(map_author, target_cells)
	_property_service.restore_override_state(map_author, before)
	_commit_property_snapshot(map_author, target_cells, before, after, "恢复地格属性继承", undo_redo)
	return true


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
		TargetLayer.TRAVERSAL:
			return "Traversal"
		TargetLayer.SPAWNER:
			return "Spawner"
		TargetLayer.OBJECT:
			return "Object"
		TargetLayer.AI:
			return "AI"
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
		Tool.SELECT:
			return "Select"
		Tool.BOX_PAINT:
			return "Box Paint"
	return "Unknown"


func can_edit_cell(cell: Vector3i, for_tool: int = tool) -> Dictionary:
	if not has_author():
		return {"valid": false, "reason": "没有活动的 TacticalMapAuthor。"}
	if not _inside_volume(cell):
		return {"valid": false, "reason": "楼层坐标超出可编辑范围。"}
	if for_tool == Tool.PICK:
		return {"valid": true, "reason": "可吸取。"}
	if for_tool == Tool.ERASE:
		return {"valid": true, "reason": "可擦除。"}
	if for_tool == Tool.BOX_PAINT:
		if String(selected_placeable.get("kind", "")) != "cell":
			return {"valid": false, "reason": "框选绘制只支持 Cell 地格素材。"}
		for_tool = Tool.PAINT
	if for_tool == Tool.SELECT:
		if not _has_floor_cell(cell):
			return {"valid": false, "reason": "该坐标没有可编译 Floor 地格。"}
		return {"valid": true, "reason": "可选择。"}
	if for_tool == Tool.ROTATE:
		if target_layer == TargetLayer.OBJECT:
			return {"valid": not _markers_at(cell).is_empty(), "reason": "目标格没有对象。" if _markers_at(cell).is_empty() else "可旋转对象。"}
		if target_layer == TargetLayer.SPAWNER:
			var spawn_markers := _spawn_markers_at(cell)
			return {"valid": not spawn_markers.is_empty(), "reason": "目标格没有出生点。" if spawn_markers.is_empty() else "可旋转出生点。"}
		if not _is_grid_layer(target_layer):
			return {"valid": false, "reason": "%s 层没有可旋转的地格内容。" % target_layer_name(target_layer)}
		var rotate_grid := _grid_for_layer(target_layer)
		var rotate_item := -1 if rotate_grid == null else rotate_grid.get_cell_item(cell)
		return {"valid": rotate_item >= 0, "reason": "目标格没有地格。" if rotate_item < 0 else "可旋转地格。"}
	if selected_placeable.is_empty():
		return {"valid": false, "reason": "素材栏中没有选中素材。"}
	var selected_kind := String(selected_placeable.get("kind", "cell"))
	if selected_kind == "spawn" or selected_kind == "traversal" or selected_kind == "patrol":
		if not _has_floor_cell(cell):
			return {"valid": false, "reason": "出生点、连接和巡逻点必须位于有效 Floor 上。"}
		if selected_kind == "spawn" and not _spawn_markers_at(cell).is_empty():
			return {"valid": true, "reason": "将替换并归一化该格已有出生点。"}
		return {"valid": true, "reason": "可放置 %s。" % selected_kind}
	var effective_layer := _paint_effective_layer()
	if effective_layer == TargetLayer.OBJECT:
		if _objects_root() == null:
			return {"valid": false, "reason": "作者场景缺少 Objects 节点。"}
		if _grid_for_layer(TargetLayer.FLOOR) == null or _grid_for_layer(TargetLayer.FLOOR).get_cell_item(cell) < 0:
			return {"valid": false, "reason": "对象需要放在有效 Floor 上。"}
		return {"valid": true, "reason": "可放置对象。"}
	if not _is_grid_layer(effective_layer):
		return {"valid": false, "reason": "当前素材未路由到可绘制的 GridMap 层。"}
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
	_stroke_global_before.clear()
	_stroke_global_after.clear()


func apply_at(cell: Vector3i) -> bool:
	if tool == Tool.SELECT:
		return select_cell(cell)
	if not stroke_active:
		begin_stroke()
	if tool == Tool.PICK:
		return pick_at(cell)
	return _apply_at_internal(cell, true)


## Applies every cell in an X/Z rectangle as one stroke.  The editor uses this
## for Box Paint so large areas do not emit a change signal for every cell.
func apply_rectangle(from_cell: Vector3i, to_cell: Vector3i, erase: bool = false) -> bool:
	if tool != Tool.BOX_PAINT:
		_set_status("当前工具不是框选绘制。", false)
		return false
	if from_cell.y != to_cell.y:
		_set_status("框选%s必须位于同一楼层。" % ("擦除" if erase else "绘制"), false)
		return false
	if erase:
		if not stroke_active:
			begin_stroke("框选擦除")
		# Temporarily treat the stroke as ERASE so snapshot captures and
		# validation follow the target_layer, not the selected Cell placeable.
		var saved_tool := tool
		tool = Tool.ERASE
		var min_x := mini(from_cell.x, to_cell.x)
		var max_x := maxi(from_cell.x, to_cell.x)
		var min_z := mini(from_cell.z, to_cell.z)
		var max_z := maxi(from_cell.z, to_cell.z)
		var changed_count := 0
		for z in range(min_z, max_z + 1):
			for x in range(min_x, max_x + 1):
				if _apply_at_internal(Vector3i(x, from_cell.y, z), false):
					changed_count += 1
		tool = saved_tool
		if changed_count > 0:
			_set_status("框选擦除：已擦除 %d 格。" % changed_count, true)
			_emit_changed()
		return changed_count > 0
	if not stroke_active:
		begin_stroke("框选绘制")
	var min_x := mini(from_cell.x, to_cell.x)
	var max_x := maxi(from_cell.x, to_cell.x)
	var min_z := mini(from_cell.z, to_cell.z)
	var max_z := maxi(from_cell.z, to_cell.z)
	var changed_count := 0
	for z in range(min_z, max_z + 1):
		for x in range(min_x, max_x + 1):
			if _apply_at_internal(Vector3i(x, from_cell.y, z), false):
				changed_count += 1
	if changed_count > 0:
		_set_status("框选绘制：已修改 %d 格。" % changed_count, true)
		_emit_changed()
	return changed_count > 0


func _apply_at_internal(cell: Vector3i, emit_change: bool) -> bool:
	var check := can_edit_cell(cell)
	if not bool(check.get("valid", false)):
		_set_status(String(check.get("reason", "无法编辑。")), false)
		return false
	if not _stroke_before.has(cell):
		var before_snapshot := _capture_snapshot(cell)
		_stroke_before[cell] = before_snapshot
		if _uses_content_root_snapshot() and _stroke_global_before.is_empty():
			_stroke_global_before = before_snapshot
	var changed_now := false
	match tool:
		Tool.PAINT, Tool.BOX_PAINT:
			changed_now = _paint_at(cell)
		Tool.ERASE:
			changed_now = _erase_at(cell)
		Tool.ROTATE:
			changed_now = _rotate_at(cell)
	if changed_now:
		var after_snapshot := _capture_snapshot(cell)
		_stroke_after[cell] = after_snapshot
		if _uses_content_root_snapshot():
			_stroke_global_after = after_snapshot
		if emit_change:
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
	if _uses_content_root_snapshot():
		before = [_stroke_global_before.duplicate(true)] if not _stroke_global_before.is_empty() else []
		after = [_stroke_global_after.duplicate(true)] if not _stroke_global_after.is_empty() else []
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
	_stroke_global_before.clear()
	_stroke_global_after.clear()
	stroke_label = ""
	if changed_any:
		_set_status("已提交一个 %s Undo Action。" % committed_label, true)
		_emit_changed()
	return changed_any


func cancel_stroke() -> void:
	if not stroke_active:
		_pending_traversal_from = Vector3i(-1, -1, -1)
		_active_patrol_route_id = &""
		return
	var before := _sorted_snapshots(_stroke_before)
	if _uses_content_root_snapshot() and not _stroke_global_before.is_empty():
		before = [_stroke_global_before]
	_apply_snapshot_set(before)
	stroke_active = false
	_stroke_before.clear()
	_stroke_after.clear()
	_stroke_global_before.clear()
	_stroke_global_after.clear()
	stroke_label = ""
	_pending_traversal_from = Vector3i(-1, -1, -1)
	_active_patrol_route_id = &""
	_emit_changed()


func pick_at(cell: Vector3i) -> bool:
	if not _inside_volume(cell):
		_set_status("楼层坐标超出可编辑范围。", false)
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
	if not _is_grid_layer(target_layer):
		_set_status("%s 层的内容不能通过 GridMap 吸取。" % target_layer_name(target_layer), false)
		return false
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
	match selected_kind:
		"spawn":
			return _place_spawn_at(cell)
		"traversal":
			return _place_traversal_at(cell)
		"patrol":
			return _place_patrol_point_at(cell)
	var effective_layer := _paint_effective_layer()
	if selected_kind == "object" or effective_layer == TargetLayer.OBJECT:
		return _replace_object_at(cell)
	if not _is_grid_layer(effective_layer):
		return false
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
	# Erase is controlled by the current author layer, not by whichever
	# palette entry happens to be selected.  This prevents a manually changed
	# target layer from deleting a different content root or falling through to
	# a GridMap with the old four-layer numeric assumptions.
	match target_layer:
		TargetLayer.SPAWNER:
			return _erase_spawn_at(cell)
		TargetLayer.TRAVERSAL:
			return _erase_traversal_at(cell)
		TargetLayer.AI:
			return _erase_patrol_at(cell)
		TargetLayer.OBJECT:
			var markers := _markers_at(cell)
			if markers.is_empty():
				return false
			for marker in markers:
				var node: Node = marker
				if node.get_parent() != null:
					node.get_parent().remove_child(node)
				node.free()
			return true
		_:
			pass
	if not _is_grid_layer(target_layer):
		return false
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
	if target_layer == TargetLayer.SPAWNER:
		return false
	if not _is_grid_layer(target_layer):
		return false
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
		"definition_id": StringName(entry.get("definition_id", &"")),
		"scene": entry.get("scene"),
		"blocks_movement": bool(entry.get("blocks_movement", false)),
		"blocks_los": bool(entry.get("blocks_los", false)),
		"loot_table": entry.get("loot_table"),
		"loot_seed": int(entry.get("loot_seed", -1)),
	}
	_create_marker(record, objects_root)
	return true


func _place_spawn_at(cell: Vector3i) -> bool:
	# A cell is a single spawn slot.  Inspect it before creating/ensuring any
	# root so an equivalent single marker is a true no-op with no new name or
	# scene mutation.  Multiple legacy markers are always normalized below.
	var existing_markers := _spawn_markers_at(cell)
	var equivalent_marker: UnitSpawnMarker3D = null
	for node in existing_markers:
		if node is UnitSpawnMarker3D and _spawn_configuration_equal(node as UnitSpawnMarker3D, selected_placeable):
			equivalent_marker = node as UnitSpawnMarker3D
			break
	if existing_markers.size() == 1 and equivalent_marker != null:
		return false

	var root := _ensure_content_root(SPAWNS_NODE_NAME)
	if root == null:
		return false
	var entry := selected_placeable
	var faction := _spawn_faction(entry)
	var prefix := String(entry.get("unit_name_prefix", "PlayerSpawn" if faction == "player" else "EnemySpawn"))
	var unit_name := StringName()
	if equivalent_marker != null:
		# Normalizing duplicate legacy markers should not consume another name.
		unit_name = equivalent_marker.unit_name
		if unit_name == &"":
			unit_name = StringName(equivalent_marker.name)
	for node in existing_markers:
		var old_marker: Node = node
		if old_marker.get_parent() != null:
			old_marker.get_parent().remove_child(old_marker)
		old_marker.free()
	if unit_name == &"":
		unit_name = StringName(_next_content_id(prefix, root, &"unit_name"))
	var record := {
		&"name": unit_name,
		&"unit_name": unit_name,
		&"faction": faction,
		&"cell": cell,
		&"facing": _facing_for_quarters(),
		&"visual_color": _spawn_visual_color(entry, faction),
		&"patrol_route_id": StringName(entry.get("patrol_route_id", &"")),
		&"archetype": entry.get("archetype", null),
		&"weapon": entry.get("weapon", null),
		&"encounter_id": StringName(entry.get("encounter_id", &"")),
	}
	_create_spawn_marker(record, root)
	return true


func _spawn_faction(entry: Dictionary) -> String:
	return String(entry.get(&"faction", "enemy"))


func _spawn_default_visual_color(faction: String) -> Color:
	return Color("4f9dff") if faction == "player" else Color("ff5b5b")


func _spawn_visual_color(entry: Dictionary, faction: String) -> Color:
	var fallback := _spawn_default_visual_color(faction)
	var configured = entry.get(&"visual_color", fallback)
	return configured if configured is Color else fallback


func _spawn_configuration_equal(marker: UnitSpawnMarker3D, entry: Dictionary) -> bool:
	if marker == null:
		return false
	var expected_faction := _spawn_faction(entry)
	var expected_color := _spawn_visual_color(entry, expected_faction)
	var expected_patrol_route := StringName(entry.get(&"patrol_route_id", &""))
	var expected_encounter := StringName(entry.get(&"encounter_id", &""))
	return (
		marker.faction == expected_faction
		and marker.visual_color.is_equal_approx(expected_color)
		and marker.patrol_route_id == expected_patrol_route
		and _resources_equivalent(marker.archetype, entry.get(&"archetype", null))
		and _resources_equivalent(marker.weapon, entry.get(&"weapon", null))
		and marker.encounter_id == expected_encounter
	)


func _place_traversal_at(cell: Vector3i) -> bool:
	if _pending_traversal_from == Vector3i(-1, -1, -1):
		_pending_traversal_from = cell
		_set_status("已选择连接起点 %s，请继续选择终点。" % cell, true)
		_emit_changed()
		return true
	if cell == _pending_traversal_from:
		_set_status("连接终点不能与起点相同。", false)
		return false
	var root := _ensure_content_root(TRAVERSAL_LINKS_NODE_NAME)
	if root == null:
		return false
	var from_cell := _pending_traversal_from
	var record := {
		&"name": _next_content_id("TraversalLink", root, &"name"),
		&"from_cell": from_cell,
		&"to_cell": cell,
		&"move_cost": int(selected_placeable.get("move_cost", 1)),
		&"bidirectional": bool(selected_placeable.get("bidirectional", true)),
		&"enabled": true,
		&"kind": int(selected_placeable.get("traversal_kind", MapTransitionData.Kind.STAIRS)),
	}
	_create_traversal_marker(record, root)
	_pending_traversal_from = Vector3i(-1, -1, -1)
	_set_status("已创建连接：%s → %s。" % [from_cell, cell], true)
	return true


func _place_patrol_point_at(cell: Vector3i) -> bool:
	var root := _ensure_content_root(PATROL_ROUTES_NODE_NAME)
	if root == null:
		return false
	var route: PatrolRoute3D = _find_patrol_route(_active_patrol_route_id) if _active_patrol_route_id != &"" else null
	if route == null:
		var route_id := _next_content_id("PatrolRoute", root, &"route_id")
		route = PatrolRoute3D.new()
		route.name = route_id
		route.route_id = StringName(route_id)
		route.loop = bool(selected_placeable.get("loop", true))
		root.add_child(route)
		route.owner = edited_scene_root if edited_scene_root != null else author
		_active_patrol_route_id = route.route_id
	if route.points.is_empty() or route.points[route.points.size() - 1] != cell:
		route.points.append(cell)
		_set_status("巡逻路线 %s 已添加点 %s。继续绘制或调用 finish_patrol_route() 结束。" % [route.route_id, cell], true)
		return true
	return false


func _erase_spawn_at(cell: Vector3i) -> bool:
	var removed := false
	var root := _content_root(SPAWNS_NODE_NAME)
	if root == null:
		return false
	for node in _descendants(root):
		if node is UnitSpawnMarker3D and (node as UnitSpawnMarker3D).cell == cell:
			var spawn_node: Node = node
			if spawn_node.get_parent() != null:
				spawn_node.get_parent().remove_child(spawn_node)
			spawn_node.free()
			removed = true
	return removed


func _erase_traversal_at(cell: Vector3i) -> bool:
	var root := _content_root(TRAVERSAL_LINKS_NODE_NAME)
	if root == null:
		return false
	var removed := false
	for node in _descendants(root):
		if not node is TraversalLink3D:
			continue
		var link := node as TraversalLink3D
		if link.from_cell == cell or link.to_cell == cell:
			link.get_parent().remove_child(link)
			link.free()
			removed = true
	return removed


func _erase_patrol_at(cell: Vector3i) -> bool:
	var root := _content_root(PATROL_ROUTES_NODE_NAME)
	if root == null:
		return false
	var removed := false
	for node in _descendants(root):
		if not node is PatrolRoute3D:
			continue
		var route := node as PatrolRoute3D
		if route.points.has(cell):
			route.get_parent().remove_child(route)
			route.free()
			if route.route_id == _active_patrol_route_id:
				_active_patrol_route_id = &""
			removed = true
	return removed


func _capture_snapshot(cell: Vector3i) -> Dictionary:
	var selected_kind := String(selected_placeable.get("kind", ""))
	# Painting is routed by the selected entry kind, while Erase/Rotate are
	# routed by target_layer.  Capture the corresponding content root so the
	# Undo snapshot follows the same semantic route as the mutation.
	var snapshot_content_layer := _paint_effective_layer() if tool == Tool.PAINT or tool == Tool.BOX_PAINT else target_layer
	if selected_kind == "spawn" and (tool == Tool.PAINT or tool == Tool.BOX_PAINT):
		return {"kind": "spawn_root", "layer": TargetLayer.SPAWNER, "cell": cell, "root_exists": _content_root(SPAWNS_NODE_NAME) != null, "records": _capture_spawn_records()}
	if selected_kind == "traversal" and (tool == Tool.PAINT or tool == Tool.BOX_PAINT):
		return {"kind": "traversal_root", "layer": TargetLayer.TRAVERSAL, "cell": cell, "root_exists": _content_root(TRAVERSAL_LINKS_NODE_NAME) != null, "records": _capture_traversal_records()}
	if selected_kind == "patrol" and (tool == Tool.PAINT or tool == Tool.BOX_PAINT):
		return {"kind": "patrol_root", "layer": TargetLayer.AI, "cell": cell, "root_exists": _content_root(PATROL_ROUTES_NODE_NAME) != null, "records": _capture_patrol_records()}
	if snapshot_content_layer == TargetLayer.SPAWNER:
		return _capture_layer_snapshot(cell, TargetLayer.SPAWNER)
	if snapshot_content_layer == TargetLayer.TRAVERSAL:
		return _capture_layer_snapshot(cell, TargetLayer.TRAVERSAL)
	if snapshot_content_layer == TargetLayer.AI:
		return _capture_layer_snapshot(cell, TargetLayer.AI)
	var snapshot_layer := _paint_effective_layer() if tool == Tool.PAINT or tool == Tool.BOX_PAINT else target_layer
	return _capture_layer_snapshot(cell, snapshot_layer)


func _capture_layer_snapshot(cell: Vector3i, layer: int) -> Dictionary:
	if layer == TargetLayer.SPAWNER:
		return {"kind": "spawn_root", "layer": TargetLayer.SPAWNER, "cell": cell, "root_exists": _content_root(SPAWNS_NODE_NAME) != null, "records": _capture_spawn_records()}
	if layer == TargetLayer.TRAVERSAL:
		return {"kind": "traversal_root", "layer": TargetLayer.TRAVERSAL, "cell": cell, "root_exists": _content_root(TRAVERSAL_LINKS_NODE_NAME) != null, "records": _capture_traversal_records()}
	if layer == TargetLayer.AI:
		return {"kind": "patrol_root", "layer": TargetLayer.AI, "cell": cell, "root_exists": _content_root(PATROL_ROUTES_NODE_NAME) != null, "records": _capture_patrol_records()}
	if layer == TargetLayer.OBJECT:
		return {"kind": "object", "layer": TargetLayer.OBJECT, "cell": cell, "records": _capture_marker_records(cell)}
	var grid := _grid_for_layer(layer)
	if grid == null:
		return {"kind": "grid", "layer": layer, "cell": cell, "item": -1, "orientation": 0}
	var item := grid.get_cell_item(cell)
	return {
		"kind": "grid",
		"layer": layer,
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
	if kind == "spawn_root":
		_restore_spawn_records(snapshot.get("records", []), bool(snapshot.get("root_exists", true)))
		return
	if kind == "traversal_root":
		_restore_traversal_records(snapshot.get("records", []), bool(snapshot.get("root_exists", true)))
		return
	if kind == "patrol_root":
		_restore_patrol_records(snapshot.get("records", []), bool(snapshot.get("root_exists", true)))
		return
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


func _capture_selection_layer_snapshots(cells: Array[Vector3i], layer: int) -> Array:
	var result: Array = []
	if cells.is_empty():
		return result
	if _selection_layer_uses_global_snapshot(layer):
		result.append(_capture_layer_snapshot(cells[0], layer))
		return result
	for cell in cells:
		result.append(_capture_layer_snapshot(cell, layer))
	return result


func _selection_layer_uses_global_snapshot(layer: int) -> bool:
	return layer == TargetLayer.SPAWNER or layer == TargetLayer.TRAVERSAL or layer == TargetLayer.AI


func _selection_layer_has_content(cell: Vector3i, layer: int) -> bool:
	if layer == TargetLayer.OBJECT:
		return not _markers_at(cell).is_empty()
	if not _is_grid_layer(layer):
		return false
	var grid := _grid_for_layer(layer)
	return grid != null and grid.get_cell_item(cell) >= 0


func _clear_layer_at(cell: Vector3i, layer: int) -> bool:
	if layer == TargetLayer.OBJECT:
		var markers := _markers_at(cell)
		if markers.is_empty():
			return false
		for marker in markers:
			var node: Node = marker
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
		return true
	if not _is_grid_layer(layer):
		return false
	var grid := _grid_for_layer(layer)
	if grid == null or grid.get_cell_item(cell) < 0:
		return false
	grid.set_cell_item(cell, -1)
	return true


func _relocate_content_snapshot(source: Dictionary, cell: Vector3i, duplicate_object_ids: bool) -> Dictionary:
	var result := source.duplicate(true)
	result[&"cell"] = cell
	if String(result.get(&"kind", "")) != "object":
		return result
	var relocated_records: Array = []
	for record_value in result.get(&"records", []):
		if not record_value is Dictionary:
			continue
		var record: Dictionary = (record_value as Dictionary).duplicate(true)
		record[&"cell"] = cell
		if duplicate_object_ids:
			record[&"object_id"] = _next_object_id("copy")
		relocated_records.append(record)
	result[&"records"] = relocated_records
	return result


func _selection_snapshots_equal(before: Array, after: Array) -> bool:
	if before.size() != after.size():
		return false
	for index in range(before.size()):
		if not _snapshot_equal(before[index], after[index]):
			return false
	return true


func _copy_cell_array(source: Array) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for value in source:
		if value is Vector3i:
			result.append(value)
	return result


func _apply_selection_operation(snapshots: Array, selection: Array) -> void:
	for snapshot_value in snapshots:
		if snapshot_value is Dictionary:
			_apply_snapshot(snapshot_value as Dictionary)
	selected_cells = _copy_cell_array(selection)
	_set_status("已应用选择编辑快照。", true)
	_emit_changed()


func _commit_selection_operation(before: Array, after: Array, label: String, undo_redo: Object, before_selection: Array[Vector3i], after_selection: Array[Vector3i]) -> bool:
	if _selection_snapshots_equal(before, after):
		_set_status("%s没有产生变化。" % label, true)
		return false
	var before_cells := _copy_cell_array(before_selection)
	var after_cells := _copy_cell_array(after_selection)
	selected_cells = after_cells.duplicate()
	var action_context: Object = edited_scene_root if edited_scene_root != null else author
	if undo_redo is EditorUndoRedoManager:
		var manager := undo_redo as EditorUndoRedoManager
		manager.create_action(label, UndoRedo.MERGE_DISABLE, action_context)
		manager.add_do_method(self, &"_apply_selection_operation", after, after_cells)
		manager.add_undo_method(self, &"_apply_selection_operation", before, before_cells)
		# The operation has already been applied. Do not execute the do callback
		# once more during commit; this is especially important for Object markers
		# whose preview/snap callbacks may be deferred by Godot.
		manager.commit_action(false)
	elif undo_redo is UndoRedo:
		var generic_undo_redo := undo_redo as UndoRedo
		generic_undo_redo.create_action(label)
		generic_undo_redo.add_do_method(Callable(self, &"_apply_selection_operation").bind(after, after_cells))
		generic_undo_redo.add_undo_method(Callable(self, &"_apply_selection_operation").bind(before, before_cells))
		generic_undo_redo.commit_action(false)
	_set_status("%s：已修改 %d 格，并创建一个 Undo Action。" % [label, after_cells.size()], true)
	_emit_changed()
	return true


func _capture_marker_records(cell: Vector3i) -> Array:
	var records: Array = []
	for marker in _markers_at(cell):
		records.append({
			"object_id": _property(marker, "object_id", marker.name),
			"definition_id": StringName(_property(marker, "definition_id", &"")),
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
	marker.set("definition_id", StringName(record.get("definition_id", &"")))
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


func _create_spawn_marker(record: Dictionary, spawns_root: Node) -> UnitSpawnMarker3D:
	var marker := UnitSpawnMarker3D.new()
	marker.name = String(record.get(&"name", record.get(&"unit_name", "Spawn")))
	marker.unit_name = StringName(record.get(&"unit_name", marker.name))
	marker.faction = String(record.get(&"faction", "enemy"))
	marker.visual_color = record.get(&"visual_color", Color.WHITE)
	marker.patrol_route_id = StringName(record.get(&"patrol_route_id", &""))
	marker.archetype = record.get(&"archetype", null) as UnitArchetype
	marker.weapon = record.get(&"weapon", null) as WeaponDefinition
	marker.encounter_id = StringName(record.get(&"encounter_id", &""))
	spawns_root.add_child(marker)
	marker.owner = edited_scene_root if edited_scene_root != null else author
	marker.cell = record.get(&"cell", Vector3i.ZERO)
	return marker


func _create_traversal_marker(record: Dictionary, links_root: Node) -> TraversalLink3D:
	var link := TraversalLink3D.new()
	link.name = String(record.get(&"name", "TraversalLink"))
	link.from_cell = record.get(&"from_cell", Vector3i.ZERO)
	link.to_cell = record.get(&"to_cell", Vector3i.ZERO)
	link.move_cost = int(record.get(&"move_cost", 1))
	link.bidirectional = bool(record.get(&"bidirectional", true))
	link.enabled = bool(record.get(&"enabled", true))
	link.kind = int(record.get(&"kind", MapTransitionData.Kind.STAIRS))
	links_root.add_child(link)
	link.owner = edited_scene_root if edited_scene_root != null else author
	if author != null and author.has_method("cell_to_local"):
		link.position = author.cell_to_local(link.from_cell)
	return link


func _create_patrol_route(record: Dictionary, routes_root: Node) -> PatrolRoute3D:
	var route := PatrolRoute3D.new()
	route.name = String(record.get(&"name", record.get(&"route_id", "PatrolRoute")))
	route.route_id = StringName(record.get(&"route_id", route.name))
	route.loop = bool(record.get(&"loop", true))
	var points: Array[Vector3i] = []
	for point in record.get(&"points", []):
		# Route order is gameplay data: A -> B -> A is a valid loop.  Do not
		# globally deduplicate while restoring an Undo/Redo snapshot.
		if point is Vector3i:
			points.append(point)
	route.points = points
	routes_root.add_child(route)
	route.owner = edited_scene_root if edited_scene_root != null else author
	return route


func _capture_spawn_records() -> Array:
	var records: Array = []
	var root := _content_root(SPAWNS_NODE_NAME)
	if root == null:
		return records
	for node in _descendants(root):
		if not node is UnitSpawnMarker3D:
			continue
		var marker := node as UnitSpawnMarker3D
		records.append({
			&"name": marker.name,
			&"unit_name": marker.unit_name,
			&"faction": marker.faction,
			&"cell": marker.cell,
			&"visual_color": marker.visual_color,
			&"patrol_route_id": marker.patrol_route_id,
			&"archetype": marker.archetype,
			&"weapon": marker.weapon,
			&"encounter_id": marker.encounter_id,
		})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get(&"unit_name", "")) < String(b.get(&"unit_name", ""))
	)
	return records


func _capture_traversal_records() -> Array:
	var records: Array = []
	var root := _content_root(TRAVERSAL_LINKS_NODE_NAME)
	if root == null:
		return records
	for node in _descendants(root):
		if not node is TraversalLink3D:
			continue
		var link := node as TraversalLink3D
		records.append({
			&"name": link.name,
			&"from_cell": link.from_cell,
			&"to_cell": link.to_cell,
			&"move_cost": link.move_cost,
			&"bidirectional": link.bidirectional,
			&"enabled": link.enabled,
			&"kind": link.kind,
		})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get(&"name", "")) < String(b.get(&"name", ""))
	)
	return records


func _capture_patrol_records() -> Array:
	var records: Array = []
	var root := _content_root(PATROL_ROUTES_NODE_NAME)
	if root == null:
		return records
	for node in _descendants(root):
		if not node is PatrolRoute3D:
			continue
		var route := node as PatrolRoute3D
		records.append({
			&"name": route.name,
			&"route_id": route.route_id,
			&"points": route.points.duplicate(),
			&"loop": route.loop,
		})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get(&"route_id", "")) < String(b.get(&"route_id", ""))
	)
	return records


func _restore_spawn_records(records: Array, root_should_exist: bool = true) -> void:
	var root := _content_root(SPAWNS_NODE_NAME)
	if root == null and root_should_exist:
		root = _ensure_content_root(SPAWNS_NODE_NAME)
	if root == null:
		return
	if not root_should_exist and records.is_empty():
		_remove_content_root(root)
		return
	if root == null:
		return
	_clear_content_root(root)
	for record in records:
		if record is Dictionary:
			_create_spawn_marker(record, root)


func _restore_traversal_records(records: Array, root_should_exist: bool = true) -> void:
	var root := _content_root(TRAVERSAL_LINKS_NODE_NAME)
	if root == null and root_should_exist:
		root = _ensure_content_root(TRAVERSAL_LINKS_NODE_NAME)
	if root == null:
		return
	if not root_should_exist and records.is_empty():
		_remove_content_root(root)
		return
	if root == null:
		return
	_clear_content_root(root)
	for record in records:
		if record is Dictionary:
			_create_traversal_marker(record, root)


func _restore_patrol_records(records: Array, root_should_exist: bool = true) -> void:
	var root := _content_root(PATROL_ROUTES_NODE_NAME)
	if root == null and root_should_exist:
		root = _ensure_content_root(PATROL_ROUTES_NODE_NAME)
	if root == null:
		return
	if not root_should_exist and records.is_empty():
		_remove_content_root(root)
		return
	if root == null:
		return
	_clear_content_root(root)
	for record in records:
		if record is Dictionary:
			_create_patrol_route(record, root)


func _entry_from_marker(marker: Node) -> Dictionary:
	var object_id = _property(marker, "object_id", marker.name)
	return {
		"id": "object:%s" % String(object_id),
		"label": "对象 / %s" % String(object_id),
		"category": "对象",
		"kind": "object",
		"layer": TargetLayer.OBJECT,
		"definition": null,
		"definition_id": StringName(_property(marker, "definition_id", &"")),
		"item_id": -1,
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
	if library is TacticalPlaceableLibrary:
		# Keep the palette safe even when a hot-reloaded Session reaches this
		# loader before the EditorPlugin's filesystem-repair callback.
		(library as TacticalPlaceableLibrary).prune_missing_definition_references()
	if library != null:
		var definitions := _property(library, "definitions", [])
		if definitions is Array:
			for definition in definitions:
				var entry := _entry_from_definition(definition)
				if not entry.is_empty():
					placeables.append(entry)
	if placeables.is_empty():
		_load_catalog_fallback()
	_append_decoration_aliases()
	_load_object_templates()
	_append_builtin_marker_placeables()
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
		var object_kind_value := _property(definition, "object_kind", 4)
		var special_kind := _special_content_kind(object_kind_value)
		if special_kind != "":
			var special_entry := _marker_entry_from_definition(definition, special_kind)
			if special_kind == "spawn":
				var faction := String(_property(definition, "faction", "enemy"))
				special_entry["faction"] = faction
				special_entry["unit_name_prefix"] = String(_property(definition, "unit_name_prefix", "PlayerSpawn" if faction == "player" else "EnemySpawn"))
				special_entry["archetype"] = _property(definition, "archetype", null)
				special_entry["weapon"] = _property(definition, "weapon", null)
				special_entry["encounter_id"] = StringName(_property(definition, "encounter_id", &""))
				special_entry["patrol_route_id"] = StringName(_property(definition, "patrol_route_id", &""))
				special_entry["visual_color"] = _property(definition, "visual_color", Color("4f9dff") if faction == "player" else Color("ff5b5b"))
			return special_entry
		return {
			"id": String(_property(definition, "placeable_id", "object")),
			"label": String(_property(definition, "display_name", _property(definition, "placeable_id", "对象"))),
			"category": String(_property(definition, "category", "对象")),
			"kind": "object",
			"layer": TargetLayer.OBJECT,
			"definition": definition,
			"definition_id": StringName(_property(definition, "placeable_id", &"")),
			"item_id": -1,
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
	if not _is_grid_layer(layer):
		# Cell definitions may only be routed to one of the three GridMaps.  A
		# malformed entry using a special/content layer must not silently become
		# an Object or an accidental Floor entry.
		return {}
	return {
		"id": String(_property(definition, "placeable_id", "grid:%d:%d" % [layer, item_id])),
		"label": String(_property(definition, "display_name", _property(definition, "placeable_id", "item %d" % item_id))),
		"category": String(_property(definition, "category", target_layer_name(layer))),
		"kind": "cell",
		"layer": layer,
		"item_id": item_id,
		"definition": definition,
		"scene": null,
	}


func _load_catalog_fallback() -> void:
	var catalog := _property(author, "tile_catalog", null)
	var rules := _property(catalog, "rules", []) if catalog != null else []
	if not rules is Array:
		return
	for rule in rules:
		var layer := _layer_from_value(_property(rule, "layer", 0))
		if not _is_grid_layer(layer):
			continue
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
			"definition": null,
			"scene": null,
			"rule": rule,
		})


func _append_decoration_aliases() -> void:
	# Library migration keeps a non-empty Library, so the old catalog fallback
	# is not entered.  Generate the same visual-only Decoration aliases for
	# every source Cell entry regardless of whether it came from Catalog or
	# Library.  Existing real Decoration entries and aliases are never cloned.
	var existing_ids: Dictionary = {}
	for entry in placeables:
		existing_ids[String(entry.get("id", ""))] = true
	var source_entries: Array = placeables.duplicate(true)
	for entry in source_entries:
		if String(entry.get("kind", "")) != "cell":
			continue
		if int(entry.get("layer", -1)) == TargetLayer.DECORATION:
			continue
		var alias_id := "%s:decoration" % String(entry.get("id", "grid"))
		if existing_ids.has(alias_id):
			continue
		var alias: Dictionary = entry.duplicate(true)
		alias["id"] = alias_id
		alias["label"] = "Decoration / %s" % String(entry.get("label", "素材"))
		alias["category"] = "Decoration"
		alias["layer"] = TargetLayer.DECORATION
		placeables.append(alias)
		existing_ids[alias_id] = true


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
			"definition": null,
			"item_id": -1,
			"object_kind": kind,
			"definition_id": StringName(_property(node, "definition_id", &"")),
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
			TargetLayer.TRAVERSAL:
				return TargetLayer.TRAVERSAL
			TargetLayer.SPAWNER:
				return TargetLayer.SPAWNER
			TargetLayer.OBJECT:
				return TargetLayer.OBJECT
			TargetLayer.AI:
				return TargetLayer.AI
		return -1
	if value is String or value is StringName:
		var text_value := String(value).to_lower()
		if text_value == "0":
			return TargetLayer.FLOOR
		if text_value == "1":
			return TargetLayer.STRUCTURE
		if text_value == "2":
			return TargetLayer.DECORATION
		if text_value == "3":
			return TargetLayer.TRAVERSAL
		if text_value == "4":
			return TargetLayer.SPAWNER
		if text_value == "5":
			return TargetLayer.OBJECT
		if text_value == "6":
			return TargetLayer.AI
		if text_value.contains("structure"):
			return TargetLayer.STRUCTURE
		if text_value.contains("decoration") or text_value.contains("decor"):
			return TargetLayer.DECORATION
		if text_value.contains("traversal") or text_value.contains("transition") or text_value == "link":
			return TargetLayer.TRAVERSAL
		if text_value.contains("spawner") or text_value.contains("spawn") or text_value.contains("unit"):
			return TargetLayer.SPAWNER
		if text_value.contains("object"):
			return TargetLayer.OBJECT
		if text_value == "ai" or text_value.contains("patrol") or text_value.contains("route"):
			return TargetLayer.AI
	return -1


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


func _is_grid_layer(layer: int) -> bool:
	return layer == TargetLayer.FLOOR or layer == TargetLayer.STRUCTURE or layer == TargetLayer.DECORATION


func _is_target_layer(layer: int) -> bool:
	return layer >= TargetLayer.FLOOR and layer <= TargetLayer.AI


func _has_floor_cell(cell: Vector3i) -> bool:
	var floor_grid := _grid_for_layer(TargetLayer.FLOOR)
	return floor_grid != null and floor_grid.get_cell_item(cell) >= 0


func _copy_structured_diagnostics(items: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in items:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


func _merge_validation_debug_cells(base: Dictionary, diagnostics: Array[Dictionary]) -> Dictionary:
	var result := base.duplicate(true)
	var records: Array[Dictionary] = []
	var by_coordinate: Dictionary = {}
	for value in base.get(&"cells", []):
		if not value is Dictionary:
			continue
		var record: Dictionary = (value as Dictionary).duplicate(true)
		var coordinate = record.get(&"coordinate", null)
		if coordinate is Vector3i:
			var attached := _copy_structured_diagnostics(record.get(&"diagnostics", []))
			record[&"diagnostics"] = attached
			record[&"validation_only"] = false
			record[&"validation_severity"] = _diagnostic_severity(attached)
			by_coordinate[coordinate] = records.size()
		records.append(record)
	for diagnostic in diagnostics:
		var coordinate = diagnostic.get(&"coordinate", null)
		if not coordinate is Vector3i:
			continue
		if by_coordinate.has(coordinate):
			var existing_index: int = by_coordinate[coordinate]
			var existing: Dictionary = records[existing_index]
			var attached: Array[Dictionary] = _copy_structured_diagnostics(existing.get(&"diagnostics", []))
			if not _contains_structured_diagnostic(attached, diagnostic):
				attached.append(diagnostic.duplicate(true))
			existing[&"diagnostics"] = attached
			existing[&"validation_severity"] = _diagnostic_severity(attached)
			records[existing_index] = existing
			continue
		var validation_record := {
			&"coordinate": coordinate,
			&"exists": false,
			&"in_bounds": _inside_volume(coordinate),
			&"has_floor": false,
			&"has_structure": false,
			&"effective_rules": null,
			&"diagnostics": [diagnostic.duplicate(true)],
			&"validation_only": true,
			&"validation_severity": String(diagnostic.get(&"severity", &"warning")),
		}
		by_coordinate[coordinate] = records.size()
		records.append(validation_record)
	records.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_coordinate: Vector3i = first.get(&"coordinate", Vector3i.ZERO)
		var second_coordinate: Vector3i = second.get(&"coordinate", Vector3i.ZERO)
		if first_coordinate.y != second_coordinate.y:
			return first_coordinate.y < second_coordinate.y
		if first_coordinate.z != second_coordinate.z:
			return first_coordinate.z < second_coordinate.z
		return first_coordinate.x < second_coordinate.x
	)
	result[&"cells"] = records
	result[&"diagnostics"] = diagnostics.duplicate(true)
	return result


func _annotate_initial_object_walkability(inspection: Dictionary) -> void:
	var blocker_ids_by_cell: Dictionary = {}
	var objects_root := _objects_root()
	if objects_root != null:
		for node in _descendants(objects_root):
			if not node is MapObjectMarker3D:
				continue
			var marker := node as MapObjectMarker3D
			if not marker.blocks_movement:
				continue
			var blocker_ids: PackedStringArray = blocker_ids_by_cell.get(marker.cell, PackedStringArray())
			var blocker_id := String(marker.object_id).strip_edges()
			if blocker_id.is_empty():
				blocker_id = String(marker.name)
			if not blocker_ids.has(blocker_id):
				blocker_ids.append(blocker_id)
				blocker_ids.sort()
			blocker_ids_by_cell[marker.cell] = blocker_ids

	var records: Array = inspection.get(&"cells", [])
	for index in range(records.size()):
		if not records[index] is Dictionary:
			continue
		var record: Dictionary = records[index]
		var coordinate = record.get(&"coordinate", null)
		if not coordinate is Vector3i or bool(record.get(&"validation_only", false)):
			continue
		var rules := record.get(&"effective_rules", null) as TacticalCellRules
		if rules == null:
			continue
		var blocking_object_ids: PackedStringArray = blocker_ids_by_cell.get(coordinate, PackedStringArray())
		record[&"cell_rule_walkable"] = rules.walkable
		record[&"blocking_object_ids"] = blocking_object_ids.duplicate()
		record[&"initial_walkable"] = rules.walkable and blocking_object_ids.is_empty()
		records[index] = record
	inspection[&"cells"] = records


func _marker_entry_from_definition(definition: Object, special_kind: String) -> Dictionary:
	var placeable_id := String(_property(definition, "placeable_id", special_kind))
	var layer := _special_layer_for_kind(special_kind)
	if layer < 0:
		return {}
	return {
		"id": placeable_id,
		"label": String(_property(definition, "display_name", placeable_id)),
		"category": String(_property(definition, "category", "地图标记")),
		"kind": special_kind,
		"layer": layer,
		"definition": definition,
		"item_id": -1,
		"scene": _property(definition, "scene", _property(definition, "preview_scene", null)),
		"move_cost": int(_property(definition, "move_cost", 1)),
		"bidirectional": bool(_property(definition, "bidirectional", true)),
		"enabled": bool(_property(definition, "enabled", true)),
		"traversal_kind": int(_property(definition, "traversal_kind", MapTransitionData.Kind.STAIRS)),
		"loop": bool(_property(definition, "loop", true)),
	}


func _append_builtin_marker_placeables() -> void:
	var entries: Array[Dictionary] = [
		{
			"id": "marker:player_spawn",
			"label": "出生点 / 玩家",
			"category": "出生点",
			"kind": "spawn",
			"layer": TargetLayer.SPAWNER,
			"definition": null,
			"item_id": -1,
			"scene": null,
			"faction": "player",
			"unit_name_prefix": "PlayerSpawn",
			"visual_color": Color("4f9dff"),
		},
		{
			"id": "marker:enemy_spawn",
			"label": "出生点 / 敌人",
			"category": "出生点",
			"kind": "spawn",
			"layer": TargetLayer.SPAWNER,
			"definition": null,
			"item_id": -1,
			"scene": null,
			"faction": "enemy",
			"unit_name_prefix": "EnemySpawn",
			"visual_color": Color("ff5b5b"),
		},
		{
			"id": "marker:traversal_link",
			"label": "连接 / 跨层",
			"category": "连接",
			"kind": "traversal",
			"layer": TargetLayer.TRAVERSAL,
			"definition": null,
			"item_id": -1,
			"scene": null,
		},
		{
			"id": "marker:patrol_route",
			"label": "路线 / 巡逻",
			"category": "巡逻",
			"kind": "patrol",
			"layer": TargetLayer.AI,
			"definition": null,
			"item_id": -1,
			"scene": null,
			"loop": true,
		},
	]
	for entry in entries:
		var duplicate := false
		for existing in placeables:
			if String(existing.get("id", "")) == String(entry.get("id", "")):
				duplicate = true
				break
		if not duplicate:
			placeables.append(entry)


func _special_content_kind(value: Variant) -> String:
	var text_value := String(value).to_lower()
	if text_value.contains("player_spawn") or text_value == "player":
		return "spawn"
	if text_value.contains("enemy_spawn") or text_value == "spawn" or text_value.contains("unit_spawn"):
		return "spawn"
	if text_value.contains("traversal") or text_value.contains("transition") or text_value == "link":
		return "traversal"
	if text_value.contains("patrol") or text_value.contains("route"):
		return "patrol"
	return ""


func _special_layer_for_kind(special_kind: String) -> int:
	match special_kind.to_lower():
		"traversal":
			return TargetLayer.TRAVERSAL
		"spawn":
			return TargetLayer.SPAWNER
		"patrol":
			return TargetLayer.AI
	return -1


func _contains_structured_diagnostic(items: Array[Dictionary], candidate: Dictionary) -> bool:
	var candidate_key := "%s|%s|%s" % [candidate.get(&"code", ""), candidate.get(&"severity", ""), candidate.get(&"message", "")]
	for item in items:
		var item_key := "%s|%s|%s" % [item.get(&"code", ""), item.get(&"severity", ""), item.get(&"message", "")]
		if item_key == candidate_key:
			return true
	return false


func _diagnostic_severity(items: Array[Dictionary]) -> StringName:
	for item in items:
		if _diagnostic_is_error(item):
			return &"error"
	for item in items:
		if String(item.get(&"severity", &"")) == "warning":
			return &"warning"
	return &""


func _diagnostic_is_error(diagnostic: Dictionary) -> bool:
	var severity := String(diagnostic.get(&"severity", diagnostic.get(&"level", &""))).to_lower()
	return severity == "error" or severity == "错误"


func _read_debug_rules_field(rules: Variant, field: int, normalized: String) -> Variant:
	if rules == null:
		return null
	if rules is Dictionary:
		var values: Dictionary = rules
		for key in [normalized, normalized.to_upper(), StringName(normalized), StringName(normalized.to_upper())]:
			if values.has(key):
				return values[key]
		return null
	if rules is TacticalCellRules:
		return _read_rules_field(rules as TacticalCellRules, field)
	if rules is Object:
		return _property(rules as Object, StringName(normalized), null)
	return null


func _objects_root() -> Node:
	return author.get_node_or_null(NodePath(OBJECTS_NODE_NAME)) if has_author() else null


func _content_root(root_name: String) -> Node:
	return author.get_node_or_null(NodePath(root_name)) if has_author() else null


func _ensure_content_root(root_name: String) -> Node:
	if not has_author():
		return null
	var root := _content_root(root_name)
	if root != null:
		return root
	root = Node3D.new()
	root.name = root_name
	author.add_child(root)
	root.owner = edited_scene_root if edited_scene_root != null else author
	return root


func _clear_content_root(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		root.remove_child(child)
		child.free()


func _remove_content_root(root: Node) -> void:
	if root == null:
		return
	if root.get_parent() != null:
		root.get_parent().remove_child(root)
	root.free()


func _find_patrol_route(route_id: StringName) -> PatrolRoute3D:
	if route_id == &"":
		return null
	var root := _content_root(PATROL_ROUTES_NODE_NAME)
	if root == null:
		return null
	for node in _descendants(root):
		if node is PatrolRoute3D and (node as PatrolRoute3D).route_id == route_id:
			return node as PatrolRoute3D
	return null


func _inside_volume(cell: Vector3i) -> bool:
	return has_author() and cell.y >= 0 and cell.y < _level_count()


func _level_count() -> int:
	return TacticalMapDefinition.MAX_LEVEL_COUNT if has_author() else 1


func _markers_at(cell: Vector3i) -> Array:
	var result: Array = []
	if _objects_root() == null:
		return result
	for node in _descendants(_objects_root()):
		if _is_marker(node) and _property(node, "cell", Vector3i(-999, -999, -999)) == cell:
			result.append(node)
	return result


func _spawn_markers_at(cell: Vector3i) -> Array:
	var result: Array = []
	var root := _content_root(SPAWNS_NODE_NAME)
	if root == null:
		return result
	for node in _descendants(root):
		if node is UnitSpawnMarker3D and (node as UnitSpawnMarker3D).cell == cell:
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


func _resources_equivalent(left: Variant, right: Variant) -> bool:
	if left == right:
		return true
	if left == null or right == null:
		return false
	if not left is Resource or not right is Resource:
		return left == right
	var left_resource := left as Resource
	var right_resource := right as Resource
	var left_path := String(left_resource.resource_path)
	var right_path := String(right_resource.resource_path)
	if not left_path.is_empty() or not right_path.is_empty():
		return not left_path.is_empty() and left_path == right_path
	return _resource_signature(left_resource, {}) == _resource_signature(right_resource, {})


func _resource_signature(resource: Resource, seen: Dictionary) -> Dictionary:
	var signature: Dictionary = {&"class": resource.get_class()}
	for property_info in resource.get_property_list():
		var property_name := StringName(property_info.get("name", ""))
		if property_name in [&"resource_path", &"resource_name", &"resource_local_to_scene", &"script"]:
			continue
		if (int(property_info.get("usage", 0)) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		signature[property_name] = _stable_resource_value(resource.get(property_name), seen)
	return signature


func _stable_resource_value(value: Variant, seen: Dictionary) -> Variant:
	if value is Resource:
		var resource := value as Resource
		var path := String(resource.resource_path)
		if not path.is_empty():
			return {&"resource_path": path}
		var instance_id := resource.get_instance_id()
		if seen.has(instance_id):
			return {&"resource_class": resource.get_class(), &"cycle": true}
		var nested_seen := seen.duplicate()
		nested_seen[instance_id] = true
		return _resource_signature(resource, nested_seen)
	if value is Array:
		var array_value: Array = []
		for item in value:
			array_value.append(_stable_resource_value(item, seen))
		return array_value
	if value is Dictionary:
		var dictionary_value: Dictionary = {}
		for key in value.keys():
			dictionary_value[key] = _stable_resource_value(value[key], seen)
		return dictionary_value
	return value


func _orientation_for_quarters(layer: int = -1) -> int:
	return _orientation_from_basis(Basis(Vector3.UP, float(rotation_quarters) * PI * 0.5), layer)


func _orientation_from_basis(basis: Basis, layer: int = -1) -> int:
	var grid := _grid_for_layer(target_layer if layer < 0 else layer)
	if grid == null:
		grid = _grid_for_layer(TargetLayer.FLOOR)
	return grid.get_orthogonal_index_from_basis(basis) if grid != null else 0


func _paint_effective_layer() -> int:
	if selected_placeable.is_empty():
		return target_layer if _is_target_layer(target_layer) else -1
	var selected_kind := String(selected_placeable.get("kind", "cell"))
	if selected_kind == "object":
		return TargetLayer.OBJECT
	if selected_kind == "spawn" or selected_kind == "traversal" or selected_kind == "patrol":
		return _special_layer_for_kind(selected_kind)
	if selected_kind == "cell":
		var selected_layer := int(selected_placeable.get("layer", target_layer))
		if _is_grid_layer(selected_layer):
			return selected_layer
		return -1
	return target_layer if _is_target_layer(target_layer) else -1


func _is_special_placeable() -> bool:
	var selected_kind := String(selected_placeable.get("kind", ""))
	return selected_kind == "spawn" or selected_kind == "traversal" or selected_kind == "patrol"


func _uses_content_root_snapshot() -> bool:
	if tool == Tool.PAINT:
		return _is_special_placeable()
	return target_layer == TargetLayer.SPAWNER or target_layer == TargetLayer.TRAVERSAL or target_layer == TargetLayer.AI


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


func _next_content_id(prefix: String, root: Node, property_name: StringName) -> String:
	var normalized := prefix.to_lower().replace("/", "_").replace(" ", "_")
	var used: Dictionary = {}
	if root != null:
		for node in _descendants(root):
			var value := _property(node, property_name, node.name)
			used[String(value)] = true
		var direct_children := root.get_children()
		for child in direct_children:
			var direct_value := _property(child, property_name, child.name)
			used[String(direct_value)] = true
	var serial := maxi(_marker_serial, 1)
	while true:
		var candidate := "%s_%03d" % [normalized, serial]
		serial += 1
		_marker_serial = serial
		if not used.has(candidate):
			return candidate
	return "%s_%03d" % [normalized, serial]


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
	var snapshot_kind := String(a.get("kind", ""))
	if snapshot_kind == "spawn_root" or snapshot_kind == "traversal_root" or snapshot_kind == "patrol_root":
		return bool(a.get("root_exists", true)) == bool(b.get("root_exists", true)) and a.get("records", []) == b.get("records", [])
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


func _clear_selection_internal() -> void:
	selected_cells.clear()


func _sort_cells(cells: Array[Vector3i]) -> void:
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		if a.z != b.z:
			return a.z < b.z
		return a.x < b.x
	)


func _normalize_property_field(field: StringName) -> StringName:
	var normalized := StringName(String(field).to_upper())
	return normalized if PROPERTY_FIELDS.has(normalized) else &""


func _property_target_cells(cells: Array) -> Array[Vector3i]:
	var source: Array = get_selected_cells() if cells.is_empty() else cells
	var result: Array[Vector3i] = []
	for value in source:
		if value is Vector3i and _inside_volume(value) and not result.has(value):
			result.append(value)
	_sort_cells(result)
	return result


func _property_descriptor(field: StringName) -> Dictionary:
	for descriptor in _property_service.field_descriptors():
		var descriptor_id := StringName(String(descriptor.get(&"id", "")).to_upper())
		if descriptor_id == field:
			return descriptor
	return {}


func _properties_from_inspection(inspection: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var base_rules := inspection.get(&"base_rules") as TacticalCellRules
	var override_values := inspection.get(&"override_values") as TacticalCellRules
	var effective_rules := inspection.get(&"effective_rules") as TacticalCellRules
	var override_mask := int(inspection.get(&"override_mask", 0))
	for field in PROPERTY_FIELDS:
		var descriptor := _property_descriptor(field)
		var field_bit := int(descriptor.get(&"field", 0))
		var has_override := (override_mask & field_bit) != 0
		result[field] = {
			"inherited": not has_override,
			"base": _read_rules_field(base_rules, field_bit),
			"override": _read_rules_field(override_values, field_bit) if has_override else null,
			"value": _read_rules_field(effective_rules, field_bit),
		}
	return result


func _read_rules_field(rules: TacticalCellRules, field: int) -> Variant:
	if rules == null:
		return null
	match field:
		TacticalCellOverride.Field.WALKABLE:
			return rules.walkable
		TacticalCellOverride.Field.MOVE_COST:
			return rules.move_cost
		TacticalCellOverride.Field.SIGHT_BLOCK:
			return rules.sight_block
		TacticalCellOverride.Field.PROJECTILE_BLOCK:
			return rules.projectile_block
		TacticalCellOverride.Field.OCCLUDER_HEIGHT:
			return rules.occluder_height
	return null


func _write_default_rules_field(rules: TacticalCellRules, field: int, value: Variant) -> void:
	if rules == null:
		return
	match field:
		TacticalCellOverride.Field.WALKABLE:
			rules.walkable = bool(value)
		TacticalCellOverride.Field.MOVE_COST:
			rules.move_cost = int(value)
		TacticalCellOverride.Field.SIGHT_BLOCK:
			rules.sight_block = float(value)
		TacticalCellOverride.Field.PROJECTILE_BLOCK:
			rules.projectile_block = float(value)
		TacticalCellOverride.Field.OCCLUDER_HEIGHT:
			rules.occluder_height = float(value)


func _rules_match_builtin_defaults(rules: TacticalCellRules) -> bool:
	if rules == null:
		return true
	var defaults := TacticalCellRules.new()
	for field in PROPERTY_FIELDS:
		var descriptor := _property_descriptor(field)
		var field_bit := int(descriptor.get(&"field", -1))
		if not _values_equal(_read_rules_field(rules, field_bit), _read_rules_field(defaults, field_bit)):
			return false
	return is_equal_approx(rules.sound_cost, defaults.sound_cost) \
		and rules.terrain_tags == defaults.terrain_tags \
		and rules.hazard_id == defaults.hazard_id


func _format_property_value(value: Variant) -> String:
	if value == null:
		return "—"
	if value is bool:
		return "是" if bool(value) else "否"
	if value is float:
		return "%.2f" % float(value)
	return str(value)


func _values_equal(first: Variant, second: Variant) -> bool:
	if (first is float or first is int) and (second is float or second is int):
		return is_equal_approx(float(first), float(second))
	return first == second


func _commit_property_snapshot(map_author: TacticalMapAuthor, cells: Array[Vector3i], before: Array[Dictionary], after: Array[Dictionary], label: String, undo_redo: Object) -> void:
	if undo_redo == null:
		_restore_property_snapshot(map_author, cells, after)
		_set_status("已应用 %s。" % label, true)
		return
	# The service mutation has already produced the after snapshot. Restore the
	# captured before state so UndoRedo.commit_action() can execute the do step
	# exactly once and the editor scene starts from a clean before state.
	_restore_property_snapshot(map_author, cells, before)
	var action_context: Object = edited_scene_root if edited_scene_root != null else author
	if undo_redo is EditorUndoRedoManager:
		var manager := undo_redo as EditorUndoRedoManager
		manager.create_action(label, UndoRedo.MERGE_DISABLE, action_context)
		manager.add_do_method(self, &"_restore_property_snapshot", map_author, cells, after)
		manager.add_undo_method(self, &"_restore_property_snapshot", map_author, cells, before)
		manager.commit_action()
	elif undo_redo is UndoRedo:
		var generic_undo_redo := undo_redo as UndoRedo
		generic_undo_redo.create_action(label)
		generic_undo_redo.add_do_method(Callable(self, &"_restore_property_snapshot").bind(map_author, cells, after))
		generic_undo_redo.add_undo_method(Callable(self, &"_restore_property_snapshot").bind(map_author, cells, before))
		generic_undo_redo.commit_action()
	_set_status("已提交一个 %s Undo Action。" % label, true)


func _commit_default_snapshot(source: Resource, before: Dictionary, after: Dictionary, label: String, undo_redo: Object) -> void:
	if source == null:
		return
	if undo_redo == null:
		_restore_default_snapshot(source, after)
		_set_status("已应用 %s。" % label, true)
		return
	_restore_default_snapshot(source, before)
	var action_context: Object = edited_scene_root if edited_scene_root != null else author
	if undo_redo is EditorUndoRedoManager:
		var manager := undo_redo as EditorUndoRedoManager
		manager.create_action(label, UndoRedo.MERGE_DISABLE, action_context)
		manager.add_do_method(self, &"_restore_default_snapshot", source, after)
		manager.add_undo_method(self, &"_restore_default_snapshot", source, before)
		manager.commit_action()
	elif undo_redo is UndoRedo:
		var generic_undo_redo := undo_redo as UndoRedo
		generic_undo_redo.create_action(label)
		generic_undo_redo.add_do_method(Callable(self, &"_restore_default_snapshot").bind(source, after))
		generic_undo_redo.add_undo_method(Callable(self, &"_restore_default_snapshot").bind(source, before))
		generic_undo_redo.commit_action()
	_set_status("已提交一个 %s Undo Action。" % label, true)


func _restore_default_snapshot(source: Resource, snapshot: Dictionary) -> bool:
	if source == null:
		return false
	var changed := _property_service.restore_default_state(source, snapshot)
	if changed:
		_emit_changed()
	return changed


func _restore_property_snapshot(map_author: TacticalMapAuthor, cells: Array[Vector3i], snapshot: Array[Dictionary]) -> bool:
	if map_author == null:
		return false
	var changed := _property_service.restore_override_state(map_author, snapshot)
	if changed:
		_emit_changed()
	return changed


func _set_status(message: String, valid: bool) -> void:
	_last_status = message
	_last_status_valid = valid
	status_changed.emit(message, valid)


func _emit_changed() -> void:
	_cover_debug_snapshot_cache.clear()
	_cover_debug_snapshot_cache_valid = false
	changed.emit()
