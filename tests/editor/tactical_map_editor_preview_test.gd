extends SceneTree

## Synthetic preview coverage. It tests the pure preview builder directly, so
## ordinary headless regression never instantiates the editor-only plugin.

const Builder := preload("res://addons/tactical_map_editor/preview/tactical_preview_builder.gd")
const EditorPluginScript := preload("res://addons/tactical_map_editor/tactical_map_editor_plugin.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_cell_preview_grid_mapping()
	call_deferred("_run")


func _test_cell_preview_grid_mapping() -> void:
	_expect(EditorPluginScript._cell_preview_grid_name(0) == "FloorGrid", "preview: Floor cells should use FloorGrid")
	_expect(EditorPluginScript._cell_preview_grid_name(1) == "StructureGrid", "preview: Structure cells should use StructureGrid")
	_expect(EditorPluginScript._cell_preview_grid_name(2) == "DecorationGrid", "preview: Decoration cells should use DecorationGrid")
	_expect(EditorPluginScript._cell_preview_grid_name(3).is_empty(), "preview: Traversal must not use a GridMap preview")
	_expect(EditorPluginScript._cell_preview_grid_name(4).is_empty(), "preview: Spawner must not use a GridMap preview")
	_expect(EditorPluginScript._cell_preview_grid_name(5).is_empty(), "preview: Object must not use a GridMap preview")
	_expect(EditorPluginScript._cell_preview_grid_name(6).is_empty(), "preview: AI must not use a GridMap preview")


func _run() -> void:
	var author := _make_author()
	get_root().add_child(author)
	var preview_root := Node3D.new()
	preview_root.name = "PreviewRootFixture"
	author.add_child(preview_root)
	var mesh_library := (author.get_node("FloorGrid") as GridMap).mesh_library
	var preview_mesh := Builder.build_cell_mesh(preview_root, mesh_library, 0, 1)
	_expect(preview_mesh != null, "preview: valid cell should create a model ghost")
	_expect(preview_mesh != null and preview_mesh.mesh == mesh_library.get_item_mesh(0), "preview: ghost should use the selected MeshLibrary item mesh")
	_expect(preview_mesh != null and not is_equal_approx(preview_mesh.transform.basis.x.dot(Vector3.RIGHT), 1.0), "preview: quarter rotation should affect the mesh transform")
	Builder.apply_preview_visual_defaults(preview_mesh)
	_expect(preview_mesh != null and (preview_mesh.material_override as StandardMaterial3D).albedo_color.a > 0.0, "preview: model should have a translucent material override")
	Builder.tint_preview(preview_root, Color(0.95, 0.2, 0.2, 0.28))
	var invalid_material := preview_mesh.material_override as StandardMaterial3D if preview_mesh != null else null
	_expect(invalid_material != null and invalid_material.albedo_color.r > invalid_material.albedo_color.g, "preview: invalid target should tint the model red")
	_expect(preview_root.find_children("*", "CollisionObject3D", true, false).is_empty(), "preview: model ghost must not add collision objects")
	var non_node_scene_root := Node.new()
	var non_node_scene := PackedScene.new()
	_expect(non_node_scene.pack(non_node_scene_root) == OK, "preview: non-Node3D fixture scene should pack")
	var rejected_instance := Builder.instantiate_scene_preview(preview_root, non_node_scene, 0)
	_expect(rejected_instance == null, "preview: non-Node3D scene root should be rejected and freed")
	non_node_scene_root.free()
	preview_root.free()
	author.free()
	_finish()


func _make_author() -> TacticalMapAuthor:
	var author := TacticalMapAuthor.new()
	author.map_id = &"preview_synthetic"
	author.footprint_size = Vector2i(1, 1)
	author.level_count = 1
	author.cell_dimensions = Vector3(2.0, 2.0, 2.0)
	var mesh_library := MeshLibrary.new()
	mesh_library.create_item(0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.2, 0.6, 1.2)
	mesh_library.set_item_mesh(0, mesh)
	var floor_grid := GridMap.new()
	floor_grid.name = "FloorGrid"
	floor_grid.mesh_library = mesh_library
	author.add_child(floor_grid)
	var structure_grid := GridMap.new()
	structure_grid.name = "StructureGrid"
	structure_grid.mesh_library = mesh_library
	author.add_child(structure_grid)
	var definition := TacticalCellTileDefinition.new()
	definition.placeable_id = &"preview.synthetic"
	definition.display_name = "Preview Synthetic"
	definition.target_layer = MapTileRule.Layer.FLOOR
	definition.mesh_item_id = 0
	definition.mesh_library = mesh_library
	var library := TacticalPlaceableLibrary.new()
	library.definitions = [definition]
	var binding := MeshItemBinding.new()
	binding.placeable_id = definition.placeable_id
	binding.target_layer = MapTileRule.Layer.FLOOR
	binding.mesh_item_id = 0
	binding.mesh_library = mesh_library
	library.item_bindings = [binding]
	author.placeable_library = library
	return author


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_MAP_EDITOR_PREVIEW_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_MAP_EDITOR_PREVIEW_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
