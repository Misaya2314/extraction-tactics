@tool
class_name TacticalMapCreationService
extends RefCounted

## Pure file-generation service for the editor's New Map workflow.
##
## The service creates only an empty authoring scene. It never copies an
## existing map layout, and it refuses every pre-existing target path before
## writing anything.

const DEFAULT_PLACEABLE_LIBRARY_PATH := "res://resources/map_tiles/libraries/default_placeable_library.tres"
const DEFAULT_SCENE_PATH := "res://scenes/maps/new_map.tscn"
const DEFAULT_OUTPUT_RESOURCE_PATH := "res://resources/maps/new_map.tres"


static func default_request() -> Dictionary:
	return {
		&"map_id": &"new_map",
		&"display_name": "新地图",
		&"scene_path": DEFAULT_SCENE_PATH,
		&"output_resource_path": DEFAULT_OUTPUT_RESOURCE_PATH,
		&"level_count": 1,
		&"cell_dimensions": Vector3(2.0, 2.0, 2.0),
		&"grid_origin": Vector3.ZERO,
		&"placeable_library": load(DEFAULT_PLACEABLE_LIBRARY_PATH) as TacticalPlaceableLibrary,
	}


static func validate_request(request: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var normalized := default_request()
	for key in request.keys():
		normalized[key] = request[key]

	var map_id_value = normalized.get(&"map_id", &"")
	var map_id := StringName(String(map_id_value).strip_edges())
	if not _is_valid_stable_id(map_id):
		errors.append("地图 ID 不能为空，且不能包含空白、斜杠或反斜杠。")
	normalized[&"map_id"] = map_id

	var display_name := String(normalized.get(&"display_name", "")).strip_edges()
	if display_name.is_empty():
		errors.append("地图显示名不能为空。")
	normalized[&"display_name"] = display_name

	var scene_path := _normalize_target_path(normalized.get(&"scene_path", ""), ".tscn")
	if scene_path.is_empty():
		errors.append("场景路径必须是 res:// 下的 .tscn 文件，且不能包含 ..。")
	elif _target_exists(scene_path):
		errors.append("场景已存在，为避免覆盖请更换路径：%s" % scene_path)
	normalized[&"scene_path"] = scene_path

	var output_path := _normalize_target_path(normalized.get(&"output_resource_path", ""), ".tres")
	if output_path.is_empty():
		errors.append("烘焙资源路径必须是 res:// 下的 .tres 文件，且不能包含 ..。")
	elif _target_exists(output_path):
		errors.append("烘焙资源已存在，为避免覆盖请更换路径：%s" % output_path)
	normalized[&"output_resource_path"] = output_path
	if not scene_path.is_empty() and scene_path == output_path:
		errors.append("场景路径与烘焙资源路径不能相同。")

	var level_value = normalized.get(&"level_count", 0)
	if typeof(level_value) != TYPE_INT:
		errors.append("楼层数必须是整数。")
	var level_count := int(level_value)
	if level_count < 1 or level_count > 32:
		errors.append("楼层数必须在 1～32 之间。")
	normalized[&"level_count"] = level_count

	var dimensions_value = normalized.get(&"cell_dimensions", Vector3.ZERO)
	if not dimensions_value is Vector3:
		errors.append("格子尺寸必须是 Vector3。")
	var cell_dimensions := dimensions_value as Vector3 if dimensions_value is Vector3 else Vector3.ZERO
	if cell_dimensions.x <= 0.0 or cell_dimensions.y <= 0.0 or cell_dimensions.z <= 0.0:
		errors.append("格子尺寸的 X/Y/Z 都必须大于 0。")
	normalized[&"cell_dimensions"] = cell_dimensions

	var origin_value = normalized.get(&"grid_origin", Vector3.ZERO)
	if not origin_value is Vector3:
		errors.append("网格原点必须是 Vector3。")
	var grid_origin := origin_value as Vector3 if origin_value is Vector3 else Vector3.ZERO
	normalized[&"grid_origin"] = grid_origin

	var library_value = normalized.get(&"placeable_library", null)
	if not library_value is TacticalPlaceableLibrary:
		errors.append("必须提供有效的 TacticalPlaceableLibrary 素材库。")
	else:
		var library := library_value as TacticalPlaceableLibrary
		var library_validation := TacticalMapValidator.validate_library(library)
		errors.append_array(library_validation.get(&"errors", []))
		warnings.append_array(library_validation.get(&"warnings", []))
		var mesh_result := _resolve_mesh_library(library)
		errors.append_array(mesh_result.get(&"errors", []))
		if mesh_result.get(&"mesh_library", null) != null:
			var mesh_library := mesh_result[&"mesh_library"] as MeshLibrary
			errors.append_array(_validate_mesh_library_items(library, mesh_library))
	errors = _unique_messages(errors)
	warnings = _unique_messages(warnings)

	return {
		&"valid": errors.is_empty(),
		&"errors": errors,
		&"warnings": warnings,
		&"request": normalized,
	}


static func create_map(request: Dictionary) -> Dictionary:
	var validation := validate_request(request)
	var errors: Array[String] = _unique_messages(validation.get(&"errors", []))
	var warnings: Array[String] = _unique_messages(validation.get(&"warnings", []))
	if not errors.is_empty():
		return _failure(errors, warnings)

	var normalized: Dictionary = validation[&"request"]
	var scene_path := String(normalized[&"scene_path"])
	var output_path := String(normalized[&"output_resource_path"])
	# Recheck immediately before any write in case another editor action created
	# either target after validation returned.
	if _target_exists(scene_path) or _target_exists(output_path):
		return _failure(["目标场景或烘焙资源在创建前已出现；为避免覆盖，本次创建已取消。"], warnings)

	var mesh_result := _resolve_mesh_library(normalized[&"placeable_library"] as TacticalPlaceableLibrary)
	var mesh_library := mesh_result.get(&"mesh_library", null) as MeshLibrary
	if mesh_library == null:
		return _failure(mesh_result.get(&"errors", []), warnings)

	var author := _build_empty_author(normalized, mesh_library)
	var directory_error := _ensure_parent_directory(scene_path)
	if directory_error != OK:
		return _failure(["创建场景目录失败：%s" % error_string(directory_error)], warnings)
	var packed := PackedScene.new()
	var pack_error := packed.pack(author)
	if pack_error != OK:
		return _failure(["打包空地图场景失败：%s" % error_string(pack_error)], warnings)
	var save_error := ResourceSaver.save(packed, scene_path)
	if save_error != OK:
		return _failure(["保存空地图场景失败：%s" % error_string(save_error)], warnings)

	return {
		&"valid": true,
		&"errors": [],
		&"warnings": _unique_messages(warnings),
		&"scene_path": scene_path,
		&"output_resource_path": output_path,
		&"map_id": normalized[&"map_id"],
	}


static func _build_empty_author(request: Dictionary, mesh_library: MeshLibrary) -> TacticalMapAuthor:
	var author := TacticalMapAuthor.new()
	author.name = "MapAuthoring_%s" % String(request[&"map_id"])
	author.map_id = request[&"map_id"] as StringName
	author.level_count = int(request[&"level_count"])
	author.cell_dimensions = request[&"cell_dimensions"] as Vector3
	author.grid_origin = request[&"grid_origin"] as Vector3
	author.placeable_library = request[&"placeable_library"] as TacticalPlaceableLibrary
	author.authoring_data = TacticalMapAuthoringData.new()
	author.output_resource_path = String(request[&"output_resource_path"])
	# TacticalMapAuthor has no display-name/scene-path exports. Metadata keeps
	# those request fields on the root without changing the shared core script.
	author.set_meta(&"display_name", String(request[&"display_name"]))
	author.set_meta(&"scene_path", String(request[&"scene_path"]))
	author.set_meta(&"output_resource_path", String(request[&"output_resource_path"]))

	_add_owned(author, _new_grid("FloorGrid", mesh_library, author.cell_dimensions, 1))
	_add_owned(author, _new_grid("StructureGrid", mesh_library, author.cell_dimensions, 2))
	_add_owned(author, _new_grid("DecorationGrid", mesh_library, author.cell_dimensions, 0))
	for child_name in ["Objects", "Spawns", "PatrolRoutes", "TraversalLinks", "TraversalVisuals", "ArtDecorations"]:
		_add_owned(author, Node3D.new(), child_name)
	return author


static func _new_grid(node_name: String, mesh_library: MeshLibrary, cell_size: Vector3, collision_layer: int) -> GridMap:
	var grid := GridMap.new()
	grid.name = node_name
	grid.mesh_library = mesh_library
	grid.cell_size = cell_size
	grid.collision_layer = collision_layer
	grid.collision_mask = 0
	return grid


static func _add_owned(parent: Node, child: Node, child_name: String = "") -> void:
	if not child_name.is_empty():
		child.name = child_name
	parent.add_child(child)
	child.owner = parent


static func _resolve_mesh_library(library: TacticalPlaceableLibrary) -> Dictionary:
	if library == null:
		return {&"mesh_library": null, &"errors": ["素材库为空，无法解析 MeshLibrary。"]}
	if library.generated_mesh_library != null:
		if library.generated_mesh_library.get_item_list().is_empty():
			return {&"mesh_library": null, &"errors": ["素材库的 generated_mesh_library 为空，无法创建地图。"]}
		return {&"mesh_library": library.generated_mesh_library, &"errors": []}

	var candidates: Array[MeshLibrary] = []
	var seen: Dictionary = {}
	for definition in library.definitions:
		if definition is TacticalCellTileDefinition:
			var cell_definition := definition as TacticalCellTileDefinition
			if cell_definition.mesh_library != null:
				_add_mesh_candidate(candidates, seen, cell_definition.mesh_library)
	for binding in library.item_bindings:
		if binding != null and binding.mesh_library != null:
			_add_mesh_candidate(candidates, seen, binding.mesh_library)
	if candidates.is_empty():
		return {&"mesh_library": null, &"errors": ["素材库缺少可解析的 MeshLibrary；请先配置 generated_mesh_library 或定义/绑定的 mesh_library。"]}
	if candidates.size() > 1:
		return {&"mesh_library": null, &"errors": ["素材库包含多个不一致的 MeshLibrary，无法确定新地图的实体素材来源。"]}
	if candidates[0].get_item_list().is_empty():
		return {&"mesh_library": null, &"errors": ["素材库解析出的 MeshLibrary 为空，无法创建地图。"]}
	return {&"mesh_library": candidates[0], &"errors": []}


static func _add_mesh_candidate(candidates: Array[MeshLibrary], seen: Dictionary, candidate: MeshLibrary) -> void:
	var key := candidate.get_instance_id()
	if seen.has(key):
		return
	seen[key] = true
	candidates.append(candidate)


static func _validate_mesh_library_items(library: TacticalPlaceableLibrary, mesh_library: MeshLibrary) -> Array[String]:
	var errors: Array[String] = []
	var item_ids := mesh_library.get_item_list()
	for definition in library.definitions:
		if definition is TacticalCellTileDefinition:
			var cell_definition := definition as TacticalCellTileDefinition
			if not item_ids.has(cell_definition.mesh_item_id):
				errors.append("素材定义 %s 引用了不存在的 MeshLibrary item %d。" % [cell_definition.placeable_id, cell_definition.mesh_item_id])
	for binding in library.item_bindings:
		if binding != null and not item_ids.has(binding.mesh_item_id):
			errors.append("素材绑定 %s 引用了不存在的 MeshLibrary item %d。" % [binding.placeable_id, binding.mesh_item_id])
	return errors


static func _is_valid_stable_id(value: StringName) -> bool:
	var text := String(value).strip_edges()
	if text.is_empty():
		return false
	for character in [" ", "\t", "\r", "\n", "/", "\\"]:
		if text.contains(character):
			return false
	return true


static func _normalize_target_path(value: Variant, extension: String) -> String:
	var path := String(value).strip_edges().replace("\\", "/")
	if not path.begins_with("res://") or path.contains("..") or not path.ends_with(extension):
		return ""
	if path == "res://" or path.get_file().is_empty():
		return ""
	return path


static func _target_exists(path: String) -> bool:
	if path.is_empty():
		return false
	if FileAccess.file_exists(path):
		return true
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))


static func _ensure_parent_directory(path: String) -> Error:
	var absolute := ProjectSettings.globalize_path(path.get_base_dir())
	return DirAccess.make_dir_recursive_absolute(absolute)


static func _failure(errors: Array[String], warnings: Array[String]) -> Dictionary:
	return {
		&"valid": false,
		&"errors": _unique_messages(errors),
		&"warnings": _unique_messages(warnings),
	}


static func _unique_messages(messages: Array) -> Array[String]:
	## Keep diagnostics deterministic while removing only exact normalized repeats.
	## Normalization is deliberately limited to line endings and surrounding
	## whitespace; message wording/case is never merged heuristically.
	var unique: Array[String] = []
	var seen: Dictionary = {}
	for message in messages:
		if message == null:
			continue
		var normalized := String(message).replace("\r\n", "\n").replace("\r", "\n").strip_edges()
		if normalized.is_empty() or seen.has(normalized):
			continue
		seen[normalized] = true
		unique.append(normalized)
	return unique
