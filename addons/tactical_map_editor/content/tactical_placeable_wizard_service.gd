@tool
class_name TacticalPlaceableWizardService
extends RefCounted

## Editor-side orchestration for the Add Placeable wizard.
##
## This service only supports the safe, already-authored source in the current
## project: an item from a GridMap's MeshLibrary.  It creates ordinary core
## Resources and never edits a map layout.  Legacy Catalog entries are copied
## into the new library before the new definition is appended, so assigning a
## non-empty library cannot make the old palette disappear.

const MIGRATOR_SCRIPT := preload("res://scripts/map_authoring/tactical_map_migrator.gd")

const GRID_SOURCES: Array[Dictionary] = [
	{"node": "FloorGrid", "layer": MapTileRule.Layer.FLOOR, "label": "Floor"},
	{"node": "StructureGrid", "layer": MapTileRule.Layer.STRUCTURE, "label": "Structure"},
]


static func default_request() -> Dictionary:
	return {
		&"placeable_id": "terrain.new.cell",
		&"display_name": "新地格",
		&"description": "",
		&"category": &"地面",
		&"tags": PackedStringArray(),
		&"target_layer": MapTileRule.Layer.FLOOR,
		&"mesh_library": null,
		&"mesh_item_id": -1,
		&"walkable": true,
		&"move_cost": 1,
		&"sight_block": 0.0,
		&"projectile_block": 0.0,
		&"occluder_height": 0.0,
		&"sound_cost": 0.0,
		&"terrain_tags": PackedStringArray(),
		&"hazard_id": &"",
	}


static func collect_mesh_options(author: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if author == null:
		return result
	var seen: Dictionary = {}
	for source in GRID_SOURCES:
		var grid := author.get_node_or_null(NodePath(String(source[&"node"]))) as GridMap
		if grid == null or grid.mesh_library == null:
			continue
		var mesh_library := grid.mesh_library
		for item_value in mesh_library.get_item_list():
			var item_id := int(item_value)
			var key := "%d:%d:%d" % [int(source[&"layer"]), mesh_library.get_instance_id(), item_id]
			if seen.has(key):
				continue
			seen[key] = true
			var item_name := "item_%d" % item_id
			if mesh_library.has_method("get_item_name"):
				var configured_name := String(mesh_library.get_item_name(item_id)).strip_edges()
				if not configured_name.is_empty():
					item_name = configured_name
			result.append({
				&"layer": int(source[&"layer"]),
				&"layer_label": String(source[&"label"]),
				&"mesh_library": mesh_library,
				&"mesh_item_id": item_id,
				&"item_label": item_name,
				&"label": "%s · %d · %s" % [source[&"label"], item_id, item_name],
			})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left.get(&"layer", 0)) != int(right.get(&"layer", 0)):
			return int(left.get(&"layer", 0)) < int(right.get(&"layer", 0))
		if int(left.get(&"mesh_item_id", -1)) != int(right.get(&"mesh_item_id", -1)):
			return int(left.get(&"mesh_item_id", -1)) < int(right.get(&"mesh_item_id", -1))
		return String(left.get(&"label", "")) < String(right.get(&"label", ""))
	)
	return result


static func validate_request(request: Dictionary, author: Node, library: TacticalPlaceableLibrary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var normalized := default_request()
	for key in request.keys():
		normalized[key] = request[key]
	var placeable_id := StringName(String(normalized.get(&"placeable_id", "")).strip_edges())
	if not TacticalPlaceableDefinition.is_valid_id(placeable_id):
		errors.append("稳定 ID 不能为空，且不能包含空白、斜杠或反斜杠。")
	normalized[&"placeable_id"] = placeable_id
	if library != null and library.find_definition(placeable_id) != null:
		errors.append("稳定 ID 已存在：%s。请使用新的 ID。" % placeable_id)
	var display_name := String(normalized.get(&"display_name", "")).strip_edges()
	if display_name.is_empty():
		errors.append("显示名不能为空。")
	normalized[&"display_name"] = display_name
	var category := StringName(String(normalized.get(&"category", "")).strip_edges())
	if category == &"":
		warnings.append("未填写分类，将使用“地面”。")
		category = &"地面"
	normalized[&"category"] = category
	var target_layer := int(normalized.get(&"target_layer", MapTileRule.Layer.FLOOR))
	if target_layer < MapTileRule.Layer.FLOOR or target_layer > MapTileRule.Layer.STRUCTURE:
		errors.append("当前 Cell 向导只支持 Floor 或 Structure 目标层。")
	normalized[&"target_layer"] = target_layer
	var mesh_library := normalized.get(&"mesh_library", null) as MeshLibrary
	var mesh_item_id := int(normalized.get(&"mesh_item_id", -1))
	if mesh_library == null:
		errors.append("必须选择当前地图已有 MeshLibrary。")
	elif not mesh_library.get_item_list().has(mesh_item_id):
		errors.append("MeshLibrary 中不存在 item %d。" % mesh_item_id)
	normalized[&"mesh_item_id"] = mesh_item_id
	if author == null:
		errors.append("没有活动的 TacticalMapAuthor。")
	if library != null:
		for binding in library.item_bindings:
			if binding == null:
				continue
			if int(binding.target_layer) == target_layer and binding.mesh_item_id == mesh_item_id:
				errors.append("目标层与 MeshLibrary item 已绑定到 %s，不能重复绑定。" % binding.placeable_id)
				break
	var move_cost := int(normalized.get(&"move_cost", 1))
	if move_cost < 1 or move_cost > 99:
		errors.append("move_cost 必须在 1～99 之间。")
	normalized[&"move_cost"] = move_cost
	var sight_block := float(normalized.get(&"sight_block", 0.0))
	var projectile_block := float(normalized.get(&"projectile_block", 0.0))
	if sight_block < 0.0 or sight_block > 1.0:
		errors.append("sight_block 必须在 0～1 之间。")
	if projectile_block < 0.0 or projectile_block > 1.0:
		errors.append("projectile_block 必须在 0～1 之间。")
	normalized[&"sight_block"] = sight_block
	normalized[&"projectile_block"] = projectile_block
	var occluder_height := float(normalized.get(&"occluder_height", 0.0))
	var sound_cost := float(normalized.get(&"sound_cost", 0.0))
	if occluder_height < 0.0 or occluder_height > 20.0:
		errors.append("occluder_height 必须在 0～20 之间。")
	if sound_cost < 0.0 or sound_cost > 99.0:
		errors.append("sound_cost 必须在 0～99 之间。")
	normalized[&"occluder_height"] = occluder_height
	normalized[&"sound_cost"] = sound_cost
	normalized[&"tags"] = normalize_tags(normalized.get(&"tags", []))
	normalized[&"terrain_tags"] = normalize_tags(normalized.get(&"terrain_tags", []))
	var hazard_id := StringName(String(normalized.get(&"hazard_id", "")).strip_edges())
	if not hazard_id.is_empty() and not TacticalPlaceableDefinition.is_valid_id(hazard_id):
		errors.append("hazard_id 不是合法稳定 ID。")
	normalized[&"hazard_id"] = hazard_id
	return {&"valid": errors.is_empty(), &"errors": errors, &"warnings": warnings, &"request": normalized}


static func normalize_tags(value: Variant) -> PackedStringArray:
	var tags: Array[String] = []
	if value is PackedStringArray or value is Array:
		for item in value:
			var tag := String(item).strip_edges()
			if not tag.is_empty() and not tags.has(tag):
				tags.append(tag)
	else:
		for item in String(value).split(","):
			var tag := String(item).strip_edges()
			if not tag.is_empty() and not tags.has(tag):
				tags.append(tag)
	tags.sort()
	return PackedStringArray(tags)


static func build_definition(request: Dictionary) -> TacticalCellTileDefinition:
	var definition := TacticalCellTileDefinition.new()
	definition.placeable_id = StringName(request.get(&"placeable_id", &""))
	definition.display_name = String(request.get(&"display_name", ""))
	definition.description = String(request.get(&"description", ""))
	definition.category = StringName(request.get(&"category", &"地面"))
	definition.tags = normalize_tags(request.get(&"tags", []))
	# Enum properties are represented as ints at runtime in Godot.  Assign the
	# validated integer directly; using `as MapTileRule.Layer` is not a valid
	# runtime cast for every 4.7 parser configuration.
	definition.target_layer = int(request.get(&"target_layer", MapTileRule.Layer.FLOOR))
	definition.mesh_library = request.get(&"mesh_library", null) as MeshLibrary
	definition.mesh_item_id = int(request.get(&"mesh_item_id", -1))
	definition.tile_id = definition.placeable_id
	var rules := TacticalCellRules.new()
	rules.walkable = bool(request.get(&"walkable", true))
	rules.move_cost = int(request.get(&"move_cost", 1))
	rules.sight_block = float(request.get(&"sight_block", 0.0))
	rules.projectile_block = float(request.get(&"projectile_block", 0.0))
	rules.occluder_height = float(request.get(&"occluder_height", 0.0))
	rules.sound_cost = float(request.get(&"sound_cost", 0.0))
	rules.terrain_tags = normalize_tags(request.get(&"terrain_tags", []))
	rules.hazard_id = StringName(request.get(&"hazard_id", &""))
	definition.rule_contribution = rules
	return definition


static func build_library_for_author(author: Node, seed_library: TacticalPlaceableLibrary = null) -> Dictionary:
	var library := TacticalPlaceableLibrary.new()
	library.schema_version = TacticalPlaceableLibrary.CURRENT_SCHEMA_VERSION
	var warnings: Array[String] = []
	var current := author.get("placeable_library") as TacticalPlaceableLibrary if author != null else null
	var source_libraries: Array[TacticalPlaceableLibrary] = []
	if current != null:
		source_libraries.append(current)
	if seed_library != null and seed_library != current:
		source_libraries.append(seed_library)
	for source in source_libraries:
		if source == null:
			continue
		if library.generated_mesh_library == null and source.generated_mesh_library != null:
			library.generated_mesh_library = source.generated_mesh_library
		for definition in source.definitions:
			if definition != null and library.find_definition(definition.placeable_id) == null:
				library.definitions.append(definition)
		for binding in source.item_bindings:
			if binding != null and not _has_binding_key(library, binding.target_layer, binding.mesh_item_id):
				library.item_bindings.append(binding)
	var catalog := author.get("tile_catalog") as MapTileCatalog if author != null else null
	if catalog != null:
		var migrated := MIGRATOR_SCRIPT.migrate_catalog(catalog) as TacticalPlaceableLibrary
		if current == null:
			warnings.append("当前地图只有 legacy Catalog；已先迁移全部旧条目到新 Library。")
		else:
			warnings.append("已检查 legacy Catalog，并补齐新 Library 中缺失的旧条目。")
		if migrated != null:
			for definition in migrated.definitions:
				if definition == null or library.find_definition(definition.placeable_id) != null:
					continue
				library.definitions.append(definition)
			for binding in migrated.item_bindings:
				if binding == null or _has_binding_key(library, binding.target_layer, binding.mesh_item_id):
					continue
				library.item_bindings.append(binding)
	return {&"library": library, &"warnings": warnings}


## Import a pre-authored Cell or Object Definition into the author's active
## placeable library.  The source Definition is never overwritten: only the
## library index/bindings are updated, so ResourceTables remains the place
## where the authored data is edited.
static func import_definition(author: Node, definition_path: String, library_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var normalized_definition_path := normalize_resource_path(definition_path)
	var normalized_library_path := normalize_resource_path(library_path)
	if author == null:
		errors.append("没有活动的 TacticalMapAuthor。")
	if not _valid_resource_path(normalized_definition_path):
		errors.append("Definition 路径必须是 res:// 或 user:// 下的 .tres 文件。")
	if not _valid_resource_path(normalized_library_path):
		errors.append("Library 路径必须是 res:// 或 user:// 下的 .tres 文件。")
	if normalized_definition_path == normalized_library_path and not normalized_definition_path.is_empty():
		errors.append("Definition 与 Library 不能使用同一路径。")
	if not errors.is_empty():
		return {&"valid": false, &"errors": errors, &"warnings": warnings}

	var definition := ResourceLoader.load(normalized_definition_path) as TacticalPlaceableDefinition
	if definition == null:
		errors.append("所选资源不是 TacticalCellTileDefinition 或 TacticalObjectDefinition。")
		return {&"valid": false, &"errors": errors, &"warnings": warnings}
	if not definition.is_valid():
		errors.append("Definition 无效：%s。" % String(definition.placeable_id))
	var is_cell := definition is TacticalCellTileDefinition
	var is_object := definition is TacticalObjectDefinition
	var target_mesh_library: MeshLibrary = null
	if not is_cell and not is_object:
		errors.append("当前素材导入只支持 Cell 地格和 Object 对象。")
	if is_object:
		var object_definition := definition as TacticalObjectDefinition
		if object_definition.scene == null:
			errors.append("Object Definition 没有指定 scene PackedScene。")
	if is_cell:
		var cell_definition := definition as TacticalCellTileDefinition
		var target_layer := int(cell_definition.target_layer)
		if target_layer != MapTileRule.Layer.FLOOR and target_layer != MapTileRule.Layer.STRUCTURE:
			errors.append("当前 Cell 导入只支持 Floor 或 Structure 目标层。")
		var grid := _grid_for_author_layer(author, target_layer)
		if grid == null:
			errors.append("目标层没有对应的 GridMap。")
		elif grid.mesh_library == null:
			errors.append("目标 GridMap 没有 MeshLibrary。")
		else:
			target_mesh_library = grid.mesh_library
			if not target_mesh_library.get_item_list().has(cell_definition.mesh_item_id):
				errors.append("目标 GridMap 的 MeshLibrary 中不存在 item %d。" % cell_definition.mesh_item_id)
	if not errors.is_empty():
		return {&"valid": false, &"errors": errors, &"warnings": warnings}

	var seed_library: TacticalPlaceableLibrary = null
	if FileAccess.file_exists(normalized_library_path):
		seed_library = ResourceLoader.load(normalized_library_path) as TacticalPlaceableLibrary
		if seed_library == null:
			errors.append("已有 Library 不是有效的 TacticalPlaceableLibrary：%s" % normalized_library_path)
			return {&"valid": false, &"errors": errors, &"warnings": warnings}
	var library_result := build_library_for_author(author, seed_library)
	var library := library_result.get(&"library") as TacticalPlaceableLibrary
	warnings.append_array(library_result.get(&"warnings", []))
	if library == null:
		errors.append("无法构建当前地图的素材库。")
		return {&"valid": false, &"errors": errors, &"warnings": warnings}
	if library.generated_mesh_library == null and target_mesh_library != null:
		library.generated_mesh_library = target_mesh_library

	var existing_index := -1
	for index in range(library.definitions.size()):
		var existing := library.definitions[index]
		if existing != null and existing.placeable_id == definition.placeable_id:
			existing_index = index
			if (existing is TacticalCellTileDefinition) != is_cell:
				errors.append("稳定 ID 已被另一种素材类型使用：%s。" % definition.placeable_id)
			break
	if not errors.is_empty():
		return {&"valid": false, &"errors": errors, &"warnings": warnings}
	if existing_index >= 0:
		# Re-importing the same stable ID updates the library reference, which
		# lets ResourceTables edits flow into the map editor without duplicates.
		library.definitions[existing_index] = definition
	else:
		library.definitions.append(definition)

	if is_cell:
		var cell_definition := definition as TacticalCellTileDefinition
		var binding_index := -1
		for index in range(library.item_bindings.size()):
			var binding := library.item_bindings[index]
			if binding == null:
				continue
			if binding.placeable_id == definition.placeable_id:
				binding_index = index
				continue
			if binding.target_layer == cell_definition.target_layer and binding.mesh_item_id == cell_definition.mesh_item_id:
				errors.append("目标层与 MeshLibrary item 已绑定到 %s，不能重复绑定。" % binding.placeable_id)
		if not errors.is_empty():
			return {&"valid": false, &"errors": errors, &"warnings": warnings}
		var new_binding := MeshItemBinding.new()
		new_binding.placeable_id = definition.placeable_id
		new_binding.target_layer = cell_definition.target_layer
		new_binding.mesh_item_id = cell_definition.mesh_item_id
		new_binding.mesh_library = cell_definition.mesh_library
		if new_binding.mesh_library == null:
			new_binding.mesh_library = target_mesh_library
		if binding_index >= 0:
			library.item_bindings[binding_index] = new_binding
		else:
			library.item_bindings.append(new_binding)

	var library_errors := library.get_validation_errors()
	if not library_errors.is_empty():
		errors.append_array(library_errors)
		return {&"valid": false, &"errors": errors, &"warnings": warnings}
	var directory_error := _ensure_parent_directory(normalized_library_path)
	if directory_error != OK:
		errors.append("创建 Library 目录失败：%s" % error_string(directory_error))
		return {&"valid": false, &"errors": errors, &"warnings": warnings}

	var library_preexists := FileAccess.file_exists(normalized_library_path)
	var existing_uid := _read_resource_uid(normalized_library_path) if library_preexists else ""
	var output_library := library
	if library_preexists:
		var existing_library := ResourceLoader.load(normalized_library_path) as TacticalPlaceableLibrary
		if existing_library == null:
			errors.append("无法重新载入已有 Library：%s" % normalized_library_path)
			return {&"valid": false, &"errors": errors, &"warnings": warnings}
		existing_library.schema_version = library.schema_version
		existing_library.generated_mesh_library = library.generated_mesh_library
		existing_library.definitions = library.definitions
		existing_library.item_bindings = library.item_bindings
		output_library = existing_library
	else:
		library.resource_path = normalized_library_path
	var save_error := ResourceSaver.save(output_library, normalized_library_path)
	if save_error != OK:
		errors.append("保存 Library 失败：%s" % error_string(save_error))
		return {&"valid": false, &"errors": errors, &"warnings": warnings}
	if not existing_uid.is_empty():
		_restore_resource_uid(normalized_library_path, existing_uid)
	author.set("placeable_library", output_library)
	return {
		&"valid": true,
		&"errors": [],
		&"warnings": warnings,
		&"definition": definition,
		&"library": output_library,
		&"placeable_id": definition.placeable_id,
		&"definition_path": normalized_definition_path,
		&"library_path": normalized_library_path,
		&"imported_kind": "cell" if is_cell else "object",
	}


static func _grid_for_author_layer(author: Node, layer: int) -> GridMap:
	if author == null:
		return null
	var node_name := "FloorGrid" if layer == MapTileRule.Layer.FLOOR else "StructureGrid"
	return author.get_node_or_null(NodePath(node_name)) as GridMap


static func save_new_cell(author: Node, request: Dictionary, definition_path: String, library_path: String) -> Dictionary:
	var library_result := build_library_for_author(author)
	var library := library_result.get(&"library") as TacticalPlaceableLibrary
	var validation := validate_request(request, author, library)
	var errors: Array[String] = validation.get(&"errors", [])
	var warnings: Array[String] = []
	warnings.append_array(library_result.get(&"warnings", []))
	warnings.append_array(validation.get(&"warnings", []))
	if not errors.is_empty():
		return {&"valid": false, &"errors": errors, &"warnings": warnings}
	var normalized: Dictionary = validation[&"request"]
	var normalized_definition_path := normalize_resource_path(definition_path)
	var normalized_library_path := normalize_resource_path(library_path)
	if not _valid_resource_path(normalized_definition_path):
		errors.append("Definition 路径必须是 res:// 或 user:// 下的 .tres 文件。")
	if not _valid_resource_path(normalized_library_path):
		errors.append("Library 路径必须是 res:// 或 user:// 下的 .tres 文件。")
	if normalized_definition_path == normalized_library_path:
		errors.append("Definition 与 Library 不能使用同一路径。")
	var definition_previously_absent := not FileAccess.file_exists(normalized_definition_path)
	if not definition_previously_absent:
		errors.append("Definition 文件已存在，为避免覆盖请更换路径：%s" % normalized_definition_path)
	var current_library := author.get("placeable_library") as TacticalPlaceableLibrary if author != null else null
	var current_library_path := String(current_library.resource_path) if current_library != null else ""
	var library_preexists := FileAccess.file_exists(normalized_library_path)
	if library_preexists and current_library_path != normalized_library_path:
		errors.append("Library 文件已存在且不是当前作者正在使用的 Library，为避免覆盖请换用当前 Library 路径。")
	if not errors.is_empty():
		return {&"valid": false, &"errors": errors, &"warnings": warnings}
	var definition := build_definition(normalized)
	# Give the standalone resource its exact path before saving the Library so
	# the Library stores an ExtResource reference instead of embedding a second
	# copy of the Definition.
	definition.resource_path = normalized_definition_path
	library.definitions.append(definition)
	var binding := MeshItemBinding.new()
	binding.placeable_id = definition.placeable_id
	binding.target_layer = definition.target_layer
	binding.mesh_item_id = definition.mesh_item_id
	binding.mesh_library = definition.mesh_library
	library.item_bindings.append(binding)
	var library_errors := library.get_validation_errors()
	if not library_errors.is_empty():
		errors.append_array(library_errors)
		return {&"valid": false, &"errors": errors, &"warnings": warnings}
	var directory_error := _ensure_parent_directory(normalized_definition_path)
	if directory_error != OK:
		errors.append("创建 Definition 目录失败：%s" % error_string(directory_error))
		return {&"valid": false, &"errors": errors, &"warnings": warnings}
	var save_error := ResourceSaver.save(definition, normalized_definition_path)
	if save_error != OK:
		errors.append("保存 Definition 失败：%s" % error_string(save_error))
		_remove_new_definition(normalized_definition_path, definition_previously_absent)
		return {&"valid": false, &"errors": errors, &"warnings": warnings, &"definition_saved": false}
	directory_error = _ensure_parent_directory(normalized_library_path)
	if directory_error != OK:
		errors.append("创建 Library 目录失败：%s" % error_string(directory_error))
		_remove_new_definition(normalized_definition_path, definition_previously_absent)
		return {&"valid": false, &"errors": errors, &"warnings": warnings, &"definition_saved": true}
	var existing_uid := _read_resource_uid(normalized_library_path) if library_preexists else ""
	var output_library := library
	if library_preexists:
		# Reuse the loaded Resource at an existing path.  Assigning that path to a
		# newly-created Resource can collide with Godot's ResourceLoader cache and
		# would risk breaking references/UID identity.
		var existing_library := ResourceLoader.load(normalized_library_path) as TacticalPlaceableLibrary
		if existing_library != null:
			existing_library.schema_version = library.schema_version
			existing_library.generated_mesh_library = library.generated_mesh_library
			existing_library.definitions = library.definitions
			existing_library.item_bindings = library.item_bindings
			output_library = existing_library
		else:
			library.resource_path = normalized_library_path
	save_error = ResourceSaver.save(output_library, normalized_library_path)
	if save_error != OK:
		errors.append("保存 Library 失败：%s" % error_string(save_error))
		_remove_new_definition(normalized_definition_path, definition_previously_absent)
		return {&"valid": false, &"errors": errors, &"warnings": warnings, &"definition_saved": false}
	if not existing_uid.is_empty():
		_restore_resource_uid(normalized_library_path, existing_uid)
	if author != null:
		author.set("placeable_library", output_library)
	return {
		&"valid": true,
		&"errors": [],
		&"warnings": warnings,
		&"definition": definition,
		&"library": output_library,
		&"placeable_id": definition.placeable_id,
		&"definition_path": normalized_definition_path,
		&"library_path": normalized_library_path,
	}


static func normalize_resource_path(value: String) -> String:
	return value.strip_edges().replace("\\", "/")


static func _valid_resource_path(path: String) -> bool:
	return (path.begins_with("res://") or path.begins_with("user://")) and path.ends_with(".tres") and not path.contains("..")


static func _ensure_parent_directory(path: String) -> Error:
	var absolute := ProjectSettings.globalize_path(path.get_base_dir())
	return DirAccess.make_dir_recursive_absolute(absolute)


static func _remove_new_definition(path: String, was_previously_absent: bool) -> void:
	if not was_previously_absent or not FileAccess.file_exists(path):
		return
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.remove_absolute(absolute)


static func _read_resource_uid(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var first_line := file.get_line()
	file.close()
	var marker := "uid=\"uid://"
	var start := first_line.find(marker)
	if start < 0:
		return ""
	start += marker.length()
	var end := first_line.find("\"", start)
	return "" if end < 0 else "uid://%s" % first_line.substr(start, end - start)


static func _restore_resource_uid(path: String, uid: String) -> void:
	if uid.is_empty() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var content := file.get_as_text()
	file.close()
	var marker := "uid=\"uid://"
	var start := content.find(marker)
	var replacement := uid.trim_prefix("uid://")
	if start >= 0:
		var value_start := start + marker.length()
		var value_end := content.find("\"", value_start)
		if value_end < 0:
			return
		content = content.substr(0, value_start) + replacement + content.substr(value_end)
	else:
		# ResourceSaver may omit a UID when the loaded Resource had a manually
		# authored UID. Reinsert it into the gd_resource header so the existing
		# UID contract is still preserved.
		var first_end := content.find("\n")
		if first_end < 0:
			return
		var first_line := content.substr(0, first_end)
		if not first_line.begins_with("[gd_resource"):
			return
		first_line = first_line.trim_suffix("]") + " uid=\"uid://%s\"]" % replacement
		content = first_line + content.substr(first_end)
	var write_file := FileAccess.open(path, FileAccess.WRITE)
	if write_file == null:
		return
	write_file.store_string(content)
	write_file.close()


static func _has_binding_key(library: TacticalPlaceableLibrary, layer: MapTileRule.Layer, item_id: int) -> bool:
	if library == null:
		return false
	for binding in library.item_bindings:
		if binding != null and binding.target_layer == layer and binding.mesh_item_id == item_id:
			return true
	return false
