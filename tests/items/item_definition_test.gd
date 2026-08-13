extends SceneTree

const ItemDefinitionScript = preload("res://scripts/core/items/item_definition.gd")
const ScrapMetal = preload("res://resources/items/scrap_metal.tres")
const Medkit = preload("res://resources/items/medkit.tres")
const RareWatch = preload("res://resources/items/rare_watch.tres")
const SecureChip = preload("res://resources/items/secure_chip.tres")

var _failures: Array[String] = []


func _init() -> void:
	_test_valid_configuration_and_normalization()
	_test_rotations_and_sizes()
	_test_invalid_configuration()
	_test_demo_shapes()
	_test_resource_roundtrip()
	_finish()


func _test_valid_configuration_and_normalization() -> void:
	var item = ItemDefinitionScript.new()
	item.item_id = &"test_item"
	item.display_name = "Test Item"
	item.kind = ItemDefinitionScript.Kind.MATERIAL
	item.value = 12
	item.set_shape_cells([Vector2i(2, 3), Vector2i(2, 3), Vector2i(3, 3)])
	_expect(item.is_valid(), "definition: a complete item should be valid")
	_expect(item.get_shape_cells() == [Vector2i(0, 0), Vector2i(1, 0)], "definition: shape should deduplicate and normalize")
	_expect(item.slot_size == 2, "definition: slot_size should be derived from shape cells")
	_expect(item.validate(), "definition: validate should agree with is_valid")


func _test_rotations_and_sizes() -> void:
	var item = ItemDefinitionScript.new()
	item.item_id = &"rotation_test"
	item.display_name = "Rotation Test"
	item.set_shape_cells([Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)])
	_expect(item.get_rotated_cells(0) == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], "definition: zero-degree shape")
	_expect(item.get_rotated_cells(90) == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)], "definition: 90-degree L shape")
	_expect(item.get_rotated_cells(180) == [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], "definition: 180-degree L shape")
	_expect(item.get_rotated_cells(270) == [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)], "definition: 270-degree L shape")
	_expect(item.get_shape_size(0) == Vector2i(2, 2), "definition: L shape zero-degree size")
	_expect(item.get_shape_size(90) == Vector2i(2, 2), "definition: L shape rotated size")
	_expect(ItemDefinitionScript.normalize_rotation(450) == 1, "definition: degree rotation should normalize")


func _test_invalid_configuration() -> void:
	var missing_id = ItemDefinitionScript.new()
	missing_id.display_name = "Missing ID"
	_expect(not missing_id.is_valid(), "definition: missing ID should be invalid")

	var missing_name = ItemDefinitionScript.new()
	missing_name.item_id = &"missing_name"
	missing_name.display_name = "  "
	_expect(not missing_name.is_valid(), "definition: blank display name should be invalid")

	var empty_shape = ItemDefinitionScript.new()
	empty_shape.item_id = &"empty_shape"
	empty_shape.display_name = "Empty Shape"
	empty_shape.set_shape_cells([])
	_expect(not empty_shape.is_valid(), "definition: empty shape should be invalid")

	var bad_value = ItemDefinitionScript.new()
	bad_value.item_id = &"bad_value"
	bad_value.display_name = "Bad Value"
	bad_value.value = -1
	_expect(not bad_value.is_valid(), "definition: negative value should be invalid")


func _test_demo_shapes() -> void:
	var resources := [ScrapMetal, Medkit, RareWatch, SecureChip]
	var kinds := [
		ItemDefinitionScript.Kind.MATERIAL,
		ItemDefinitionScript.Kind.CONSUMABLE,
		ItemDefinitionScript.Kind.VALUABLE,
		ItemDefinitionScript.Kind.CHIP,
	]
	for index in range(resources.size()):
		var item = resources[index]
		_expect(item != null and item.is_valid(), "definition: demo resource %d should be valid" % index)
		_expect(item.kind == kinds[index], "definition: demo resource %d should cover its kind" % index)
	_expect(ScrapMetal.get_shape_size() == Vector2i(1, 1), "definition: material should be 1x1")
	_expect(Medkit.get_shape_size() == Vector2i(1, 2), "definition: consumable should be 1x2")
	_expect(RareWatch.get_shape_size() == Vector2i(2, 2), "definition: valuable should be 2x2")
	_expect(SecureChip.slot_size == 3 and SecureChip.get_shape_size() == Vector2i(2, 2), "definition: chip should be an L shape")
	_expect(SecureChip.get_rotated_cells(90).size() == 3, "definition: L shape rotation preserves occupied count")
	_expect(ScrapMetal.icon == null, "definition: icon field remains available as a placeholder")


func _test_resource_roundtrip() -> void:
	var path := "res://tests/items/.item_roundtrip.tres"
	var original := ItemDefinitionScript.new()
	original.item_id = &"roundtrip_item"
	original.display_name = "Roundtrip Item"
	original.kind = ItemDefinitionScript.Kind.CHIP
	original.value = 77
	original.set_shape_cells([Vector2i.ZERO, Vector2i(0, 1), Vector2i(1, 1)])
	var save_error := ResourceSaver.save(original, path)
	_expect(save_error == OK, "definition: ResourceSaver should save shape data")
	if save_error == OK:
		var loaded = ResourceLoader.load(path)
		_expect(loaded is ItemDefinition, "definition: ResourceLoader should restore ItemDefinition")
		if loaded is ItemDefinition:
			_expect(loaded.get_shape_cells() == original.get_shape_cells(), "definition: resource roundtrip should preserve shape")
			_expect(loaded.get_rotated_cells(90) == original.get_rotated_cells(90), "definition: resource roundtrip should preserve rotation")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("ITEM_DEFINITION_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ITEM_DEFINITION_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
