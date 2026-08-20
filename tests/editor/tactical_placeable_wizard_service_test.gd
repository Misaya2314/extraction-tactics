extends SceneTree

## Pure resource/save coverage for the Add Placeable wizard.  All resources
## are synthetic and written under user://; no production map or scene is
## loaded or modified.

const SERVICE := preload("res://addons/tactical_map_editor/content/tactical_placeable_wizard_service.gd")

var _failures: Array[String] = []
var _root_path := "res://.godot/tactical_placeable_wizard_%d" % Time.get_ticks_usec()


func _init() -> void:
	_test_basic_save_and_definition_fields()
	_test_legacy_catalog_is_preserved()
	_test_transaction_rolls_back_definition_when_library_save_fails()
	_test_existing_library_path_and_uid_are_reused()
	_finish()


func _test_basic_save_and_definition_fields() -> void:
	var author := _make_author()
	var paths := _paths("basic")
	var request := _request(author, &"terrain.wizard.basic", 0)
	request[&"display_name"] = "向导地格"
	request[&"category"] = &"测试地面"
	request[&"tags"] = PackedStringArray(["factory", "metal"])
	request[&"walkable"] = false
	request[&"move_cost"] = 4
	request[&"sight_block"] = 0.25
	request[&"projectile_block"] = 0.5
	request[&"occluder_height"] = 1.5
	request[&"sound_cost"] = 2.0
	request[&"terrain_tags"] = PackedStringArray(["indoor"])
	request[&"hazard_id"] = &"hazard.test"
	var result := SERVICE.save_new_cell(author, request, paths[&"definition"], paths[&"library"])
	_expect(bool(result.get(&"valid", false)), "wizard: basic resource save should succeed")
	_expect(FileAccess.file_exists(paths[&"definition"]), "wizard: Definition should be written")
	_expect(FileAccess.file_exists(paths[&"library"]), "wizard: Library should be written")
	var definition := ResourceLoader.load(paths[&"definition"]) as TacticalCellTileDefinition
	var library := ResourceLoader.load(paths[&"library"]) as TacticalPlaceableLibrary
	_expect(definition != null and definition.placeable_id == &"terrain.wizard.basic", "wizard: saved Definition should retain stable ID")
	_expect(definition != null and definition.category == &"测试地面" and definition.tags.has("factory"), "wizard: saved metadata should be retained")
	_expect(definition != null and definition.rule_contribution != null and not definition.rule_contribution.walkable and definition.rule_contribution.move_cost == 4, "wizard: saved rule defaults should be retained")
	_expect(definition != null and is_equal_approx(definition.rule_contribution.sight_block, 0.25) and is_equal_approx(definition.rule_contribution.projectile_block, 0.5), "wizard: blocking defaults should be retained")
	_expect(library != null and library.find_definition(&"terrain.wizard.basic") == definition, "wizard: Library should reference the saved Definition")
	_expect(author.placeable_library != null and author.placeable_library.find_binding(MapTileRule.Layer.FLOOR, 0) != null, "wizard: active author should receive the new Library binding")
	_cleanup_paths(paths)
	author.free()


func _test_legacy_catalog_is_preserved() -> void:
	var author := _make_author()
	var catalog := MapTileCatalog.new()
	var floor_rule := MapTileRule.new()
	floor_rule.layer = MapTileRule.Layer.FLOOR
	floor_rule.item_id = 0
	floor_rule.tile_id = &"legacy_floor"
	var structure_rule := MapTileRule.new()
	structure_rule.layer = MapTileRule.Layer.STRUCTURE
	structure_rule.item_id = 1
	structure_rule.tile_id = &"legacy_wall"
	catalog.rules = [floor_rule, structure_rule]
	author.tile_catalog = catalog
	var paths := _paths("legacy")
	var result := SERVICE.save_new_cell(author, _request(author, &"terrain.wizard.with_legacy", 2), paths[&"definition"], paths[&"library"])
	_expect(bool(result.get(&"valid", false)), "wizard: legacy migration save should succeed")
	var library := ResourceLoader.load(paths[&"library"]) as TacticalPlaceableLibrary
	_expect(library != null and library.find_definition(&"legacy.floor.legacy_floor") != null, "wizard: legacy Floor entry must survive Library assignment")
	_expect(library != null and library.find_definition(&"legacy.structure.legacy_wall") != null, "wizard: legacy Structure entry must survive Library assignment")
	_expect(library != null and library.find_definition(&"terrain.wizard.with_legacy") != null, "wizard: new entry should coexist with migrated entries")
	_cleanup_paths(paths)
	author.free()


func _test_transaction_rolls_back_definition_when_library_save_fails() -> void:
	var author := _make_author()
	var blocker := "%s_parent_file" % _root_path
	var blocker_file := FileAccess.open(blocker, FileAccess.WRITE)
	if blocker_file != null:
		blocker_file.store_string("not a directory")
		blocker_file.close()
	var definition_path := "%s_transaction.tres" % _root_path
	var library_path := "%s_parent_file/library.tres" % _root_path
	var result := SERVICE.save_new_cell(author, _request(author, &"terrain.wizard.rollback", 0), definition_path, library_path)
	_expect(not bool(result.get(&"valid", false)), "wizard: a Library save failure should reject the transaction")
	_expect(not FileAccess.file_exists(definition_path), "wizard: failed Library save must remove only the newly created Definition")
	_cleanup_file(definition_path)
	_cleanup_file(library_path)
	_cleanup_file(blocker)
	author.free()


func _test_existing_library_path_and_uid_are_reused() -> void:
	var author := _make_author()
	var paths := _paths("existing")
	var existing_library := TacticalPlaceableLibrary.new()
	var old_definition := TacticalCellTileDefinition.new()
	old_definition.placeable_id = &"terrain.wizard.old"
	old_definition.display_name = "旧素材"
	old_definition.target_layer = MapTileRule.Layer.FLOOR
	old_definition.mesh_item_id = 0
	old_definition.mesh_library = _mesh_library(author)
	existing_library.definitions = [old_definition]
	var old_binding := MeshItemBinding.new()
	old_binding.placeable_id = old_definition.placeable_id
	old_binding.target_layer = MapTileRule.Layer.FLOOR
	old_binding.mesh_item_id = 0
	old_binding.mesh_library = old_definition.mesh_library
	existing_library.item_bindings = [old_binding]
	var save_error := ResourceSaver.save(existing_library, paths[&"library"])
	_expect(save_error == OK, "wizard: fixture Library should save")
	_inject_fixture_uid(paths[&"library"])
	var original_header := _first_line(paths[&"library"])
	author.placeable_library = ResourceLoader.load(paths[&"library"]) as TacticalPlaceableLibrary
	if author.placeable_library != null and String(author.placeable_library.resource_path).is_empty():
		author.placeable_library.resource_path = paths[&"library"]
	var result := SERVICE.save_new_cell(author, _request(author, &"terrain.wizard.reuse", 1), paths[&"definition"], paths[&"library"])
	_expect(bool(result.get(&"valid", false)), "wizard: saving to the active existing Library should succeed")
	var saved_library := result.get(&"library") as Resource
	_expect(saved_library != null and String(saved_library.resource_path) == paths[&"library"], "wizard: existing Library resource_path should remain stable")
	_expect(_first_line(paths[&"library"]) == original_header, "wizard: existing Library UID/header should be preserved")
	var reloaded := ResourceLoader.load(paths[&"library"]) as TacticalPlaceableLibrary
	_expect(reloaded != null and reloaded.find_definition(&"terrain.wizard.old") != null and reloaded.find_definition(&"terrain.wizard.reuse") != null, "wizard: updating existing Library must retain old and new definitions")
	_cleanup_paths(paths)
	author.free()


func _make_author() -> TacticalMapAuthor:
	var author := TacticalMapAuthor.new()
	author.map_id = &"wizard_synthetic"
	author.footprint_size = Vector2i(2, 1)
	author.level_count = 1
	author.cell_dimensions = Vector3(2.0, 2.0, 2.0)
	var mesh_library := MeshLibrary.new()
	for item_id in range(3):
		mesh_library.create_item(item_id)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.5, 0.3 + item_id * 0.1, 1.5)
		mesh_library.set_item_mesh(item_id, mesh)
		mesh_library.set_item_name(item_id, "synthetic_%d" % item_id)
	var floor_grid := GridMap.new()
	floor_grid.name = "FloorGrid"
	floor_grid.mesh_library = mesh_library
	author.add_child(floor_grid)
	var structure_grid := GridMap.new()
	structure_grid.name = "StructureGrid"
	structure_grid.mesh_library = mesh_library
	author.add_child(structure_grid)
	return author


func _mesh_library(author: TacticalMapAuthor) -> MeshLibrary:
	return (author.get_node("FloorGrid") as GridMap).mesh_library


func _request(author: TacticalMapAuthor, placeable_id: StringName, item_id: int) -> Dictionary:
	var options := SERVICE.collect_mesh_options(author)
	var selected: Dictionary = {}
	for option in options:
		if int(option.get(&"layer", -1)) == MapTileRule.Layer.FLOOR and int(option.get(&"mesh_item_id", -1)) == item_id:
			selected = option
			break
	var request := SERVICE.default_request()
	request[&"placeable_id"] = placeable_id
	request[&"display_name"] = String(placeable_id)
	request[&"mesh_library"] = selected.get(&"mesh_library", null)
	request[&"mesh_item_id"] = item_id
	request[&"target_layer"] = MapTileRule.Layer.FLOOR
	return request


func _paths(suffix: String) -> Dictionary:
	return {
		&"definition": "%s_%s_definition.tres" % [_root_path, suffix],
		&"library": "%s_%s_library.tres" % [_root_path, suffix],
	}


func _first_line(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var line := file.get_line()
	file.close()
	return line


func _inject_fixture_uid(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var content := file.get_as_text()
	file.close()
	var first_end := content.find("\n")
	if first_end < 0:
		return
	var first_line := content.substr(0, first_end)
	if not first_line.begins_with("[gd_resource") or first_line.contains("uid=\""):
		return
	first_line = first_line.trim_suffix("]") + " uid=\"uid://d1a2b3c4d5e6f\"]"
	content = first_line + content.substr(first_end)
	var write_file := FileAccess.open(path, FileAccess.WRITE)
	if write_file != null:
		write_file.store_string(content)
		write_file.close()


func _cleanup_paths(paths: Dictionary) -> void:
	_cleanup_file(String(paths.get(&"definition", "")))
	_cleanup_file(String(paths.get(&"library", "")))


func _cleanup_file(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_PLACEABLE_WIZARD_SERVICE_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_PLACEABLE_WIZARD_SERVICE_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
