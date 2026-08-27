extends SceneTree

## Synthetic preview coverage. It tests the pure preview builder directly, so
## ordinary headless regression never instantiates the editor-only plugin.

const Builder := preload("res://addons/tactical_map_editor/preview/tactical_preview_builder.gd")
const EditorPluginScript := preload("res://addons/tactical_map_editor/tactical_map_editor_plugin.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_cell_preview_grid_mapping()
	_test_cover_preview_geometry()
	call_deferred("_run")


func _test_cell_preview_grid_mapping() -> void:
	_expect(EditorPluginScript._cell_preview_grid_name(0) == "FloorGrid", "preview: Floor cells should use FloorGrid")
	_expect(EditorPluginScript._cell_preview_grid_name(1) == "StructureGrid", "preview: Structure cells should use StructureGrid")
	_expect(EditorPluginScript._cell_preview_grid_name(2) == "DecorationGrid", "preview: Decoration cells should use DecorationGrid")
	_expect(EditorPluginScript._cell_preview_grid_name(3).is_empty(), "preview: Traversal must not use a GridMap preview")
	_expect(EditorPluginScript._cell_preview_grid_name(4).is_empty(), "preview: Spawner must not use a GridMap preview")
	_expect(EditorPluginScript._cell_preview_grid_name(5).is_empty(), "preview: Object must not use a GridMap preview")
	_expect(EditorPluginScript._cell_preview_grid_name(6).is_empty(), "preview: AI must not use a GridMap preview")


func _test_cover_preview_geometry() -> void:
	var half := {&"id": &"cover.half", &"level": 1, &"reduction": 0.5, &"debug_color": Color("f0b52a")}
	var none := {&"id": &"cover.none", &"level": 0, &"reduction": 0.0, &"debug_color": Color("999999")}
	var local_north := {&"local_direction": 0, &"enabled": true, &"profile_a": none, &"profile_b": half}
	var expected_directions := [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]
	for quarter in range(4):
		var arrows := Builder.build_local_cover_preview_records([local_north], quarter)
		_expect(arrows.size() == 1, "cover preview: one-sided contribution should expose one protected arrow")
		if arrows.size() == 1:
			_expect(arrows[0].get(&"direction", Vector2i.ZERO) == expected_directions[quarter], "cover preview: local direction should rotate with the four quarter turns")
	var double_sided := local_north.duplicate(true)
	double_sided[&"profile_a"] = half
	var local_arrows := Builder.build_local_cover_preview_records([double_sided], 0)
	_expect(local_arrows.size() == 2, "cover preview: both profile sides should produce two arrows")
	var four_sided: Array[Dictionary] = []
	for local_direction in range(4):
		four_sided.append({&"local_direction": local_direction, &"enabled": true, &"profile_a": none, &"profile_b": half})
	var four_arrows := Builder.build_local_cover_preview_records(four_sided, 2)
	_expect(four_arrows.size() == 4, "cover preview: four local contributions should expose four rotated arrows")
	var visual_edges := [{
		&"edge_key": "0,0,0|1,0,0",
		&"cell_a": Vector3i(0, 0, 0),
		&"cell_b": Vector3i(1, 0, 0),
		&"center_a": Vector3(0, 0, 0),
		&"center_b": Vector3(2, 0, 0),
		&"profile_a": half,
		&"profile_b": half,
		&"invalid_or_conflict": false,
	}]
	var visual_records := Builder.build_cover_edge_visual_records(visual_edges, Vector3(2, 2, 2))
	_expect(visual_records.size() == 1, "cover preview: one valid edge should produce one visual record")
	if visual_records.size() == 1:
		_expect((visual_records[0].get(&"arrows", []) as Array).size() == 2, "cover preview: valid two-sided edge should expose A/B arrows")
		_expect(float((visual_records[0].get(&"line", {}) as Dictionary).get(&"width", 0.0)) > 0.0, "cover preview: edge boundary should expose a visible width")
	var center_author := TacticalMapAuthor.new()
	center_author.cell_dimensions = Vector3(2, 2, 2)
	var adapted_edge := EditorPluginScript._cover_edge_visual_input(visual_edges[0], center_author)
	_expect(adapted_edge.get(&"center_a", Vector3.INF) == center_author.cell_to_local(Vector3i(0, 0, 0)), "cover preview: plugin adapter should provide center_a")
	_expect(adapted_edge.get(&"center_b", Vector3.INF) == center_author.cell_to_local(Vector3i(1, 0, 0)), "cover preview: plugin adapter should provide center_b")
	center_author.free()
	var missing_center_b: Dictionary = visual_edges[0].duplicate(true)
	missing_center_b.erase(&"center_b")
	_expect(Builder.build_cover_edge_visual_records([missing_center_b], Vector3(2, 2, 2)).is_empty(), "cover preview: an ordinary edge without center_b must not be rendered")
	var no_profile: Dictionary = visual_edges[0].duplicate(true)
	no_profile[&"profile_a"] = {}
	no_profile[&"profile_b"] = {}
	_expect(Builder.build_cover_edge_visual_records([no_profile], Vector3(2, 2, 2)).is_empty(), "cover preview: edges without profiles should not draw normally")
	var invalid: Dictionary = visual_edges[0].duplicate(true)
	invalid[&"profile_a"] = {}
	invalid[&"profile_b"] = {}
	invalid[&"invalid_or_conflict"] = true
	var invalid_records := Builder.build_cover_edge_visual_records([invalid], Vector3(2, 2, 2))
	_expect(invalid_records.size() == 1 and bool(invalid_records[0].get(&"invalid", false)), "cover preview: invalid source should remain visible as a diagnostic record")


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
