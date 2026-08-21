extends SceneTree

## Pure validation coverage for the New Map core service.  The fixtures are
## synthetic Resources only; no production map scene/resource is loaded or
## written.

const SERVICE := preload("res://addons/tactical_map_editor/content/tactical_map_creation_service.gd")

const EXISTING_SCENE_PATH := "res://.godot/tactical_map_creation_service_existing.tscn"
const EXISTING_OUTPUT_PATH := "res://.godot/tactical_map_creation_service_existing.tres"

var _failures: Array[String] = []


func _init() -> void:
	_cleanup_file(EXISTING_SCENE_PATH)
	_cleanup_file(EXISTING_OUTPUT_PATH)
	_test_message_normalization_and_order()
	_test_validate_and_create_dedupe()
	_test_existing_target_errors_are_unique()
	_cleanup_file(EXISTING_SCENE_PATH)
	_cleanup_file(EXISTING_OUTPUT_PATH)
	_finish()


func _test_message_normalization_and_order() -> void:
	var messages: Array = ["  second  ", "first", "second", " first ", "", "\r\n", "third\r\n", "third\n"]
	var unique: Array[String] = SERVICE._unique_messages(messages)
	_expect(unique == ["second", "first", "third"], "creation: message dedupe must preserve first normalized order")
	_assert_unique_non_empty(unique, "creation: helper output")


func _test_validate_and_create_dedupe() -> void:
	var request := _request(
		"res://.godot/tactical_map_creation_service_dedupe_scene.tscn",
		"res://.godot/tactical_map_creation_service_dedupe_output.tres",
		_duplicate_library()
	)
	var validation := SERVICE.validate_request(request)
	var validation_errors: Array = validation.get(&"errors", [])
	var validation_warnings: Array = validation.get(&"warnings", [])
	_expect(validation_errors.size() == 1, "creation: validate_request must dedupe repeated errors")
	_expect(validation_warnings.size() == 1, "creation: validate_request must dedupe repeated warnings")
	_expect(not validation_errors.is_empty() and String(validation_errors[0]).begins_with("TML-003:"), "creation: duplicate definition error should be retained")
	_expect(not validation_warnings.is_empty() and String(validation_warnings[0]).begins_with("TML-009:"), "creation: duplicate unbound warning should be retained")
	_assert_unique_non_empty(validation_errors, "creation: validate errors")
	_assert_unique_non_empty(validation_warnings, "creation: validate warnings")

	var create_result := SERVICE.create_map(request)
	var create_errors: Array = create_result.get(&"errors", [])
	var create_warnings: Array = create_result.get(&"warnings", [])
	_expect(not bool(create_result.get(&"valid", false)), "creation: invalid library must prevent create_map")
	_expect(create_errors.size() == 1 and create_errors == validation_errors, "creation: create_map must not stack validation errors")
	_expect(create_warnings.size() == 1 and create_warnings == validation_warnings, "creation: create_map must not stack validation warnings")
	_assert_unique_non_empty(create_errors, "creation: create errors")
	_assert_unique_non_empty(create_warnings, "creation: create warnings")


func _test_existing_target_errors_are_unique() -> void:
	_write_temp_file(EXISTING_SCENE_PATH)
	_write_temp_file(EXISTING_OUTPUT_PATH)
	var request := _request(EXISTING_SCENE_PATH, EXISTING_OUTPUT_PATH, _valid_library())
	var validation := SERVICE.validate_request(request)
	var errors: Array = validation.get(&"errors", [])
	_expect(errors.size() == 2, "creation: existing scene/output should report two distinct errors")
	_expect(_count_containing(errors, "场景已存在") == 1, "creation: existing scene error should appear once")
	_expect(_count_containing(errors, "烘焙资源已存在") == 1, "creation: existing output error should appear once")
	_assert_unique_non_empty(errors, "creation: existing target errors")

	var create_result := SERVICE.create_map(request)
	var create_errors: Array = create_result.get(&"errors", [])
	_expect(create_errors.size() == 2, "creation: create_map should preserve distinct existing-target errors")
	_expect(_count_containing(create_errors, "场景已存在") == 1, "creation: create_map existing scene error should appear once")
	_expect(_count_containing(create_errors, "烘焙资源已存在") == 1, "creation: create_map existing output error should appear once")
	_assert_unique_non_empty(create_errors, "creation: create existing target errors")


func _request(scene_path: String, output_path: String, library: TacticalPlaceableLibrary) -> Dictionary:
	return {
		&"map_id": &"creation_service_dedupe_test",
		&"display_name": "创建服务去重测试",
		&"scene_path": scene_path,
		&"output_resource_path": output_path,
		&"level_count": 1,
		&"cell_dimensions": Vector3(2.0, 2.0, 2.0),
		&"grid_origin": Vector3.ZERO,
		&"placeable_library": library,
	}


func _valid_library() -> TacticalPlaceableLibrary:
	var library := TacticalPlaceableLibrary.new()
	var mesh_library := MeshLibrary.new()
	mesh_library.create_item(0)
	library.generated_mesh_library = mesh_library
	return library


func _duplicate_library() -> TacticalPlaceableLibrary:
	var library := _valid_library()
	var definitions: Array[TacticalPlaceableDefinition] = []
	for _index in range(3):
		var definition := TacticalCellTileDefinition.new()
		definition.placeable_id = &"duplicate.creation_service"
		definition.display_name = "重复素材"
		definition.mesh_item_id = 0
		definition.target_layer = MapTileRule.Layer.FLOOR
		definitions.append(definition)
	library.definitions = definitions
	return library


func _write_temp_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "creation: temporary fixture should be writable: %s" % path)
	if file != null:
		file.store_string("temporary validation fixture")
		file.close()


func _cleanup_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _count_containing(messages: Array, fragment: String) -> int:
	var count := 0
	for message in messages:
		if String(message).contains(fragment):
			count += 1
	return count


func _assert_unique_non_empty(messages: Array, label: String) -> void:
	var seen: Dictionary = {}
	for message in messages:
		var text := String(message)
		_expect(not text.strip_edges().is_empty(), "%s must not contain empty messages" % label)
		_expect(not seen.has(text), "%s must not contain duplicate messages" % label)
		seen[text] = true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_MAP_CREATION_SERVICE_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_MAP_CREATION_SERVICE_TEST: FAIL (%d)" % _failures.size())
	quit(1)
