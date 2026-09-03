extends SceneTree

## Pure editor-session coverage. This test builds an in-memory author with
## synthetic GridMaps and definitions; it never loads a production map scene.

const SessionScript = preload("res://addons/tactical_map_editor/editing/map_edit_session.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_author_root_qualification()
	_test_catalog_integer_layer_routing()
	_test_library_integer_placement_and_layer_routing()
	_test_formal_target_layers_and_palette_filtering()
	_test_default_library_object_entries()
	_test_library_decoration_aliases()
	_test_paint_uses_selected_entry_layer()
	_test_box_paint_writes_one_rectangle_as_one_stroke()
	_test_noop_stroke_does_not_commit()
	_test_undo_snapshot_call_signature()
	_test_object_snapshot_includes_facing()
	_test_erase_validation_ignores_paint_selection()
	_test_next_object_id_scans_existing_markers()
	_test_selection_is_deterministic_and_clears_on_floor_change()
	_test_selection_content_operations_and_undo()
	_test_property_override_batch_undo_and_inherit()
	_test_debug_views_validation_and_focus()
	_test_cover_debug_snapshot_and_coordinate_restore()
	_test_legacy_default_descriptor_constraints()
	_test_default_property_service_undo_and_null_restore()
	_test_special_spawn_configuration_and_state()
	_test_special_undo_redo_roundtrips()
	_finish()


func _test_author_root_qualification() -> void:
	var session = SessionScript.new()

	# An edited scene root may be parented below an editor-internal node.  The
	# root identity, rather than parent == null, is the qualification contract.
	var editor_internal_parent := Node3D.new()
	var valid_author := _make_author()
	valid_author.name = "PrototypeMapAuthoring"
	editor_internal_parent.add_child(valid_author)
	_expect(SessionScript.is_qualified_author(valid_author, valid_author), "author qualification: the selected author/root identity should qualify even with an internal parent")
	_expect(session.begin_for_author(valid_author, valid_author), "author qualification: a valid edited scene root should bind")
	_expect(session.has_author() and session.author == valid_author and session.edited_scene_root == valid_author, "author qualification: bound author and edited root should be the same instance")

	# A normal child of the current scene root is never a map root, even if its
	# display name resembles the author scene.
	var scene_root := _make_author()
	scene_root.name = "PrototypeMapAuthoring"
	var ordinary_child := Node3D.new()
	ordinary_child.name = "PrototypeMapAuthoring"
	scene_root.add_child(ordinary_child)
	_expect(not SessionScript.is_qualified_author(ordinary_child, scene_root), "author qualification: a normal child must not qualify")
	_expect(not session.begin_for_author(ordinary_child, scene_root), "author qualification: a normal child must be rejected")

	# A nested TacticalMapAuthor is also rejected when the edited scene root is
	# the outer map author.
	var nested_author := TacticalMapAuthor.new()
	nested_author.name = "PrototypeMapAuthoring"
	scene_root.add_child(nested_author)
	_expect(not SessionScript.is_qualified_author(nested_author, scene_root), "author qualification: nested TacticalMapAuthor must not qualify against the outer root")
	_expect(not session.begin_for_author(nested_author, scene_root), "author qualification: nested TacticalMapAuthor must be rejected")

	var same_name_non_author := Node3D.new()
	same_name_non_author.name = "PrototypeMapAuthoring"
	_expect(not SessionScript.is_qualified_author(same_name_non_author, same_name_non_author), "author qualification: a same-name non-Author node must not qualify")
	_expect(not session.begin_for_author(same_name_non_author, same_name_non_author), "author qualification: a same-name non-Author node must be rejected")

	# Invalid rebinding must not cancel or replace the currently valid session.
	var child_count_before := valid_author.get_child_count()
	_expect(not session.begin_for_author(nested_author, scene_root), "author qualification: invalid rebinding should return false")
	_expect(session.author == valid_author and session.edited_scene_root == valid_author, "author qualification: invalid rebinding must preserve the valid session")
	_expect(valid_author.get_child_count() == child_count_before, "author qualification: invalid rebinding must not alter scene contents")

	session.clear_author()
	valid_author.free()
	editor_internal_parent.free()
	scene_root.free()
	same_name_non_author.free()


func _test_catalog_integer_layer_routing() -> void:
	var author := _make_author()
	var catalog := MapTileCatalog.new()
	catalog.rules = [
		_legacy_rule(0, 1, &"floor"),
		_legacy_rule(1, 2, &"wall"),
		_legacy_rule(1, 3, &"low_cover"),
	]
	author.tile_catalog = catalog

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var wall_index := _find_placeable(session.get_placeables(), "catalog:1:2")
	var low_cover_index := _find_placeable(session.get_placeables(), "catalog:1:3")
	var floor_alias_index := _find_placeable(session.get_placeables(), "catalog:0:1:decoration")
	_expect(wall_index >= 0 and low_cover_index >= 0 and floor_alias_index >= 0, "catalog: wall, low_cover, and Decoration alias should be discoverable")
	if wall_index < 0 or low_cover_index < 0:
		author.free()
		return
	var wall_entry: Dictionary = session.get_placeables()[wall_index]
	var low_cover_entry: Dictionary = session.get_placeables()[low_cover_index]
	_expect(int(wall_entry.get("layer", -1)) == SessionScript.TargetLayer.STRUCTURE, "catalog: wall integer layer should route to Structure")
	_expect(int(low_cover_entry.get("layer", -1)) == SessionScript.TargetLayer.STRUCTURE, "catalog: low_cover integer layer should route to Structure")
	if floor_alias_index >= 0:
		_expect(int(session.get_placeables()[floor_alias_index].get("layer", -1)) == SessionScript.TargetLayer.DECORATION, "catalog: shared Decoration alias should target Decoration")

	session.select_placeable(wall_index)
	session.begin_stroke("catalog wall")
	_expect(session.apply_at(Vector3i(0, 0, 0)), "catalog: wall should paint")
	session.finish_stroke(null)
	session.select_placeable(low_cover_index)
	session.begin_stroke("catalog low cover")
	_expect(session.apply_at(Vector3i(1, 0, 0)), "catalog: low_cover should paint")
	session.finish_stroke(null)
	var structure_grid := author.get_node("StructureGrid") as GridMap
	_expect(structure_grid.get_cell_item(Vector3i(0, 0, 0)) == 2, "catalog: wall should be written to StructureGrid")
	_expect(structure_grid.get_cell_item(Vector3i(1, 0, 0)) == 3, "catalog: low_cover should be written to StructureGrid")
	_expect((author.get_node("FloorGrid") as GridMap).get_cell_item(Vector3i(0, 0, 0)) == 0, "catalog: FloorGrid should remain unchanged")
	author.free()


func _test_library_integer_placement_and_layer_routing() -> void:
	var author := _make_author()
	var library := TacticalPlaceableLibrary.new()
	var structure := TacticalCellTileDefinition.new()
	structure.placeable_id = &"library.structure"
	structure.display_name = "Library Structure"
	structure.placement_kind = 0
	structure.target_layer = 1
	structure.mesh_item_id = 4
	var object := TacticalObjectDefinition.new()
	object.placeable_id = &"library.object"
	object.display_name = "Library Object"
	object.placement_kind = 2
	object.blocks_movement = true
	object.blocks_los = true
	var edge := TacticalEdgeDefinition.new()
	edge.placeable_id = &"library.edge"
	var stamp := TacticalStampDefinition.new()
	stamp.placeable_id = &"library.stamp"
	library.definitions = [structure, object, edge, stamp]
	author.placeable_library = library

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var entries: Array = session.get_placeables()
	var structure_index := _find_placeable(entries, "library.structure")
	var object_index := _find_placeable(entries, "library.object")
	_expect(structure_index >= 0, "library: integer CELL definition should be discoverable")
	_expect(object_index >= 0, "library: integer OBJECT definition should be discoverable")
	_expect(_find_placeable(entries, "library.edge") < 0, "library: EDGE definition should be skipped")
	_expect(_find_placeable(entries, "library.stamp") < 0, "library: STAMP definition should be skipped")
	if structure_index < 0 or object_index < 0:
		author.free()
		return
	_expect(int(entries[structure_index].get("layer", -1)) == SessionScript.TargetLayer.STRUCTURE, "library: integer target_layer should route to Structure")
	_expect(String(entries[object_index].get("kind", "")) == "object", "library: integer placement_kind OBJECT should route to object")
	_expect(int(entries[object_index].get("layer", -1)) == SessionScript.TargetLayer.OBJECT, "library: object should target Object layer")
	_expect(bool(entries[object_index].get("blocks_movement", false)), "library: object blocks_movement should reach the palette entry")
	_expect(bool(entries[object_index].get("blocks_los", false)), "library: object blocks_los should reach the palette entry")

	session.select_placeable(structure_index)
	session.begin_stroke("library structure")
	_expect(session.apply_at(Vector3i(0, 0, 0)), "library: structure should paint")
	session.finish_stroke(null)
	_expect((author.get_node("StructureGrid") as GridMap).get_cell_item(Vector3i(0, 0, 0)) == 4, "library: structure should be written to StructureGrid")
	session.select_placeable(object_index)
	session.begin_stroke("library object")
	_expect(session.apply_at(Vector3i(1, 0, 0)), "library: object should paint on a Floor cell")
	session.finish_stroke(null)
	var marker := (author.get_node("Objects") as Node).get_child(0) as MapObjectMarker3D
	_expect(marker != null and marker.blocks_movement, "library: placed object should retain blocks_movement")
	_expect(marker != null and marker.blocks_los, "library: placed object should retain blocks_los")
	_expect(marker != null and marker.definition_id == object.placeable_id, "library: placed object should retain its stable Definition association")
	author.free()


func _test_formal_target_layers_and_palette_filtering() -> void:
	_expect(SessionScript.TargetLayer.FLOOR == 0, "layers: Floor must remain numeric 0")
	_expect(SessionScript.TargetLayer.STRUCTURE == 1, "layers: Structure must remain numeric 1")
	_expect(SessionScript.TargetLayer.DECORATION == 2, "layers: Decoration must remain numeric 2")
	_expect(SessionScript.TargetLayer.TRAVERSAL == 3, "layers: Traversal must be numeric 3")
	_expect(SessionScript.TargetLayer.SPAWNER == 4, "layers: Spawner must be numeric 4")
	_expect(SessionScript.TargetLayer.OBJECT == 5, "layers: Object must be numeric 5, not the legacy 3")
	_expect(SessionScript.TargetLayer.AI == 6, "layers: AI must be numeric 6")

	var author := _make_author()
	var library := TacticalPlaceableLibrary.new()
	var floor_definition := TacticalCellTileDefinition.new()
	floor_definition.placeable_id = &"formal.floor"
	floor_definition.display_name = "Formal Floor"
	floor_definition.target_layer = 0
	floor_definition.mesh_item_id = 0
	var invalid_cell_definition := TacticalCellTileDefinition.new()
	invalid_cell_definition.placeable_id = &"formal.invalid_special_cell"
	invalid_cell_definition.display_name = "Invalid Special Cell"
	invalid_cell_definition.target_layer = 3
	invalid_cell_definition.mesh_item_id = 4
	var object_definition := TacticalObjectDefinition.new()
	object_definition.placeable_id = &"formal.object"
	object_definition.display_name = "Formal Object"
	object_definition.object_kind = &"generic"
	var spawn_definition := TacticalObjectDefinition.new()
	spawn_definition.placeable_id = &"formal.spawn"
	spawn_definition.display_name = "Formal Spawn"
	spawn_definition.object_kind = &"enemy_spawn"
	var traversal_definition := TacticalObjectDefinition.new()
	traversal_definition.placeable_id = &"formal.traversal"
	traversal_definition.display_name = "Formal Traversal"
	traversal_definition.object_kind = &"traversal"
	var patrol_definition := TacticalObjectDefinition.new()
	patrol_definition.placeable_id = &"formal.patrol"
	patrol_definition.display_name = "Formal Patrol"
	patrol_definition.object_kind = &"patrol_route"
	library.definitions = [floor_definition, invalid_cell_definition, object_definition, spawn_definition, traversal_definition, patrol_definition]
	author.placeable_library = library

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var entries: Array = session.get_placeables()
	var floor_index := _find_placeable(entries, "formal.floor")
	var object_index := _find_placeable(entries, "formal.object")
	var spawn_index := _find_placeable(entries, "formal.spawn")
	var traversal_index := _find_placeable(entries, "formal.traversal")
	var patrol_index := _find_placeable(entries, "formal.patrol")
	_expect(floor_index >= 0 and object_index >= 0 and spawn_index >= 0 and traversal_index >= 0 and patrol_index >= 0, "layers: all formal definitions should be discoverable")
	_expect(_find_placeable(entries, "formal.invalid_special_cell") < 0, "layers: a Cell using special numeric layer 3 must not become an Object or GridMap entry")
	if floor_index >= 0:
		_expect(int(entries[floor_index].get("layer", -1)) == SessionScript.TargetLayer.FLOOR, "layers: cell definition should target Floor")
	if object_index >= 0:
		_expect(int(entries[object_index].get("layer", -1)) == SessionScript.TargetLayer.OBJECT, "layers: ordinary object should target Object")
	if spawn_index >= 0:
		_expect(int(entries[spawn_index].get("layer", -1)) == SessionScript.TargetLayer.SPAWNER, "layers: spawn definition should target Spawner")
	if traversal_index >= 0:
		_expect(int(entries[traversal_index].get("layer", -1)) == SessionScript.TargetLayer.TRAVERSAL, "layers: traversal definition should target Traversal")
	if patrol_index >= 0:
		_expect(int(entries[patrol_index].get("layer", -1)) == SessionScript.TargetLayer.AI, "layers: patrol definition should target AI")

	_expect(session._layer_from_value(3) == SessionScript.TargetLayer.TRAVERSAL, "layers: numeric 3 must remain Traversal after enum expansion")
	_expect(session._layer_from_value(5) == SessionScript.TargetLayer.OBJECT, "layers: numeric 5 must map to Object")
	_expect(session.target_layer_name(SessionScript.TargetLayer.TRAVERSAL) == "Traversal", "layers: Traversal name should be stable")
	_expect(session.target_layer_name(SessionScript.TargetLayer.SPAWNER) == "Spawner", "layers: Spawner name should be stable")
	_expect(session.target_layer_name(SessionScript.TargetLayer.AI) == "AI", "layers: AI name should be stable")

	for layer in [SessionScript.TargetLayer.FLOOR, SessionScript.TargetLayer.TRAVERSAL, SessionScript.TargetLayer.SPAWNER, SessionScript.TargetLayer.OBJECT, SessionScript.TargetLayer.AI]:
		var layer_entries: Array = session.get_placeables("", layer)
		for entry in layer_entries:
			_expect(int(entry.get("layer", -1)) == layer, "layers: layer filter must return only the requested semantic layer")
	_expect(session.get_placeables("spawn", SessionScript.TargetLayer.OBJECT).is_empty(), "layers: Object query must not include spawn entries")
	_expect(not session.get_placeables("spawn", SessionScript.TargetLayer.SPAWNER).is_empty(), "layers: filtered search should find spawn entries inside Spawner")
	_expect(session.get_placeables("formal", SessionScript.TargetLayer.TRAVERSAL).size() == 1, "layers: query should run after the Traversal filter")
	_expect(session.get_placeables("", -1).size() == entries.size(), "layers: -1 filter must preserve all-placeables compatibility")

	if spawn_index >= 0 and traversal_index >= 0 and patrol_index >= 0:
		session.select_placeable(spawn_index)
		_expect(session.target_layer == SessionScript.TargetLayer.SPAWNER and session._paint_effective_layer() == SessionScript.TargetLayer.SPAWNER, "layers: selecting spawn must route to Spawner")
		session.begin_stroke("formal spawn route")
		_expect(session.apply_at(Vector3i(0, 0, 0)), "layers: spawn paint should use Spawns root")
		session.finish_stroke(null)
		_expect(author.get_node_or_null("Spawns") != null and author.get_node("Spawns").get_child_count() == 1, "layers: spawn paint must create a Spawns marker")
		_expect((author.get_node("FloorGrid") as GridMap).get_cell_item(Vector3i(0, 0, 0)) == 0, "layers: spawn paint must not write FloorGrid")
		_expect((author.get_node("StructureGrid") as GridMap).get_cell_item(Vector3i(0, 0, 0)) < 0, "layers: spawn paint must not write StructureGrid")

		session.set_tool(SessionScript.Tool.ERASE)
		session.set_target_layer(SessionScript.TargetLayer.FLOOR)
		session.begin_stroke("formal erase target layer")
		_expect(session.apply_at(Vector3i(0, 0, 0)), "layers: erase should follow the manually selected Floor target")
		session.finish_stroke(null)
		_expect(author.get_node("Spawns").get_child_count() == 1, "layers: Floor erase must not remove a Spawner marker")

		session.set_target_layer(SessionScript.TargetLayer.SPAWNER)
		session.begin_stroke("formal erase spawn")
		_expect(session.apply_at(Vector3i(0, 0, 0)), "layers: Spawner erase should target the Spawns root")
		session.finish_stroke(null)
		_expect(author.get_node("Spawns").get_child_count() == 0, "layers: Spawner erase must remove the spawn marker")

		session.set_tool(SessionScript.Tool.PAINT)
		session.select_placeable(traversal_index)
		_expect(session.target_layer == SessionScript.TargetLayer.TRAVERSAL and session._paint_effective_layer() == SessionScript.TargetLayer.TRAVERSAL, "layers: traversal selection must never route to a GridMap")
		session.select_placeable(patrol_index)
		_expect(session.target_layer == SessionScript.TargetLayer.AI and session._paint_effective_layer() == SessionScript.TargetLayer.AI, "layers: patrol selection must never route to a GridMap")
	author.free()


func _test_default_library_object_entries() -> void:
	var library := load("res://resources/map_tiles/libraries/default_placeable_library.tres") as TacticalPlaceableLibrary
	_expect(library != null, "default objects: default placeable library should load")
	if library == null:
		return
	var validation := TacticalMapValidator.validate_library(library)
	_expect(bool(validation.get(&"valid", false)), "default objects: default placeable library should validate")
	var author := _make_author()
	author.placeable_library = library
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var object_entries: Array = session.get_placeables("", SessionScript.TargetLayer.OBJECT)
	for required_id in ["prototype_loot_crate", "prototype_extraction_marker", "prototype_explosive_barrel"]:
		var index := _find_placeable(object_entries, required_id)
		_expect(index >= 0, "default objects: Object palette should contain %s" % required_id)
	if _find_placeable(object_entries, "prototype_loot_crate") >= 0:
		var loot_entry: Dictionary = object_entries[_find_placeable(object_entries, "prototype_loot_crate")]
		var loot_table := loot_entry.get("loot_table", null) as LootTableDefinition
		_expect(loot_table != null and loot_table.is_valid(), "default objects: loot crate entry should retain a valid loot table")
	author.free()


func _test_library_decoration_aliases() -> void:
	var author := _make_author()
	var library := TacticalPlaceableLibrary.new()
	var floor_definition := TacticalCellTileDefinition.new()
	floor_definition.placeable_id = &"library.alias_floor"
	floor_definition.display_name = "Alias Floor"
	floor_definition.placement_kind = 0
	floor_definition.target_layer = 0
	floor_definition.mesh_item_id = 0
	var structure_definition := TacticalCellTileDefinition.new()
	structure_definition.placeable_id = &"library.alias_structure"
	structure_definition.display_name = "Alias Structure"
	structure_definition.placement_kind = 0
	structure_definition.target_layer = 1
	structure_definition.mesh_item_id = 1
	library.definitions = [floor_definition, structure_definition]
	author.placeable_library = library

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var entries: Array = session.get_placeables()
	var floor_id := "library.alias_floor"
	var structure_id := "library.alias_structure"
	var floor_alias_index := _find_placeable(entries, "%s:decoration" % floor_id)
	var structure_alias_index := _find_placeable(entries, "%s:decoration" % structure_id)
	_expect(_find_placeable(entries, floor_id) >= 0, "aliases: non-empty Library must retain the Floor source entry")
	_expect(_find_placeable(entries, structure_id) >= 0, "aliases: non-empty Library must retain the Structure source entry")
	_expect(floor_alias_index >= 0 and structure_alias_index >= 0, "aliases: migrated/non-empty Library must expose Decoration aliases for every Cell source")
	if floor_alias_index >= 0 and structure_alias_index >= 0:
		_expect(int(entries[floor_alias_index].get("layer", -1)) == SessionScript.TargetLayer.DECORATION, "aliases: Floor alias must target Decoration")
		_expect(int(entries[structure_alias_index].get("layer", -1)) == SessionScript.TargetLayer.DECORATION, "aliases: Structure alias must target Decoration")
	var seen_ids: Dictionary = {}
	for entry in entries:
		var entry_id := String(entry.get("id", ""))
		_expect(not seen_ids.has(entry_id), "aliases: palette IDs must remain unique")
		seen_ids[entry_id] = true
	author.free()


func _test_paint_uses_selected_entry_layer() -> void:
	var author := _make_author()
	var library := TacticalPlaceableLibrary.new()
	var floor_definition := TacticalCellTileDefinition.new()
	floor_definition.placeable_id = &"library.authoritative_floor"
	floor_definition.display_name = "Authoritative Floor"
	floor_definition.placement_kind = 0
	floor_definition.target_layer = 0
	floor_definition.mesh_item_id = 1
	library.definitions = [floor_definition]
	author.placeable_library = library

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	session.select_placeable(0)
	var floor_grid := author.get_node("FloorGrid") as GridMap
	var structure_grid := author.get_node("StructureGrid") as GridMap
	var objects := author.get_node("Objects") as Node
	session.target_layer = SessionScript.TargetLayer.OBJECT
	session.begin_stroke("paint floor while object selected")
	_expect(session.apply_at(Vector3i(0, 0, 0)), "paint: Floor entry should route away from manually selected Object layer")
	session.finish_stroke(null)
	_expect(floor_grid.get_cell_item(Vector3i(0, 0, 0)) == 1, "paint: Floor entry should write FloorGrid")
	_expect(structure_grid.get_cell_item(Vector3i(0, 0, 0)) < 0, "paint: Floor entry should not write StructureGrid")
	_expect(objects.get_child_count() == 0, "paint: Floor entry should not create an object")

	session.target_layer = SessionScript.TargetLayer.STRUCTURE
	session.begin_stroke("paint floor while structure selected")
	_expect(session.apply_at(Vector3i(1, 0, 0)), "paint: Floor entry should keep routing to Floor from Structure")
	session.finish_stroke(null)
	_expect(floor_grid.get_cell_item(Vector3i(1, 0, 0)) == 1, "paint: manual Structure target should not redirect the Floor entry")
	_expect(structure_grid.get_cell_item(Vector3i(1, 0, 0)) < 0, "paint: manual Structure target should remain untouched")
	author.free()


func _test_noop_stroke_does_not_commit() -> void:
	var author := _make_author()
	var library := TacticalPlaceableLibrary.new()
	var floor_definition := TacticalCellTileDefinition.new()
	floor_definition.placeable_id = &"library.floor"
	floor_definition.display_name = "Library Floor"
	floor_definition.placement_kind = 0
	floor_definition.target_layer = 0
	floor_definition.mesh_item_id = 0
	library.definitions = [floor_definition]
	author.placeable_library = library

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	session.select_placeable(0)
	session.begin_stroke("no-op")
	_expect(not session.apply_at(Vector3i(0, 0, 0)), "stroke: painting the existing identical cell should be a no-op")
	var undo_redo := UndoRedo.new()
	_expect(not session.finish_stroke(undo_redo), "stroke: no-op should not report a committed action")
	_expect(not undo_redo.has_undo(), "stroke: no-op should not create an Undo Action")
	undo_redo.free()
	author.free()


func _test_box_paint_writes_one_rectangle_as_one_stroke() -> void:
	var author := _make_author()
	var library := TacticalPlaceableLibrary.new()
	var floor_definition := TacticalCellTileDefinition.new()
	floor_definition.placeable_id = &"library.box_floor"
	floor_definition.display_name = "Box Floor"
	floor_definition.placement_kind = 0
	floor_definition.target_layer = 0
	floor_definition.mesh_item_id = 1
	library.definitions = [floor_definition]
	author.placeable_library = library

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	session.select_placeable(0)
	session.set_tool(SessionScript.Tool.BOX_PAINT)
	session.begin_stroke("框选绘制")
	var undo_redo := UndoRedo.new()
	_expect(session.apply_rectangle(Vector3i(1, 0, 0), Vector3i(0, 0, 0)), "box paint: reverse drag should apply")
	_expect(session.finish_stroke(undo_redo), "box paint: changed rectangle should commit")
	var floor_grid := author.get_node("FloorGrid") as GridMap
	_expect(floor_grid.get_cell_item(Vector3i(0, 0, 0)) == 1 and floor_grid.get_cell_item(Vector3i(1, 0, 0)) == 1, "box paint: all cells in the rectangle should receive the item")
	_expect(undo_redo.has_undo(), "box paint: rectangle should be one Undo Action")
	undo_redo.undo()
	_expect(floor_grid.get_cell_item(Vector3i(0, 0, 0)) == 0 and floor_grid.get_cell_item(Vector3i(1, 0, 0)) == 0, "box paint: undo should restore the complete rectangle")
	undo_redo.free()
	author.free()


func _test_undo_snapshot_call_signature() -> void:
	var author := _make_author()
	var library := TacticalPlaceableLibrary.new()
	var floor_definition := TacticalCellTileDefinition.new()
	floor_definition.placeable_id = &"library.undo_floor"
	floor_definition.display_name = "Undo Floor"
	floor_definition.placement_kind = 0
	floor_definition.target_layer = 0
	floor_definition.mesh_item_id = 1
	library.definitions = [floor_definition]
	author.placeable_library = library

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	session.select_placeable(0)
	session.begin_stroke("undo signature")
	_expect(session.apply_at(Vector3i(0, 0, 0)), "undo: synthetic change should apply")
	var undo_redo := UndoRedo.new()
	_expect(session.finish_stroke(undo_redo), "undo: changed stroke should commit")
	_expect(undo_redo.has_undo(), "undo: generic UndoRedo should contain the action")
	var floor_grid := author.get_node("FloorGrid") as GridMap
	_expect(floor_grid.get_cell_item(Vector3i(0, 0, 0)) == 1, "undo: do snapshot should retain the new item")
	undo_redo.undo()
	_expect(floor_grid.get_cell_item(Vector3i(0, 0, 0)) == 0, "undo: bound snapshot argument should restore the old item")
	undo_redo.redo()
	_expect(floor_grid.get_cell_item(Vector3i(0, 0, 0)) == 1, "undo: redo should reapply the new item")
	undo_redo.free()
	author.free()


func _test_object_snapshot_includes_facing() -> void:
	var author := _make_author()
	var objects := author.get_node("Objects")
	var marker := MapObjectMarker3D.new()
	marker.object_id = &"rotate_me"
	marker.kind = MapObjectPlacement.Kind.LOOT
	marker.cell = Vector3i(0, 0, 0)
	marker.facing = Vector2i.DOWN
	objects.add_child(marker)

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var object_template_index := _find_placeable(session.get_placeables(), "marker:0")
	if object_template_index >= 0:
		session.select_placeable(object_template_index)
	session.target_layer = SessionScript.TargetLayer.OBJECT
	var before: Dictionary = session._capture_snapshot(Vector3i(0, 0, 0))
	marker.facing = Vector2i.RIGHT
	var after: Dictionary = session._capture_snapshot(Vector3i(0, 0, 0))
	_expect(not session._snapshot_equal(before, after), "snapshot: facing change should be undo-visible")
	author.free()


func _test_erase_validation_ignores_paint_selection() -> void:
	var author := _make_author()
	var structure_grid := author.get_node("StructureGrid") as GridMap
	structure_grid.set_cell_item(Vector3i(0, 0, 0), 1)
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	session.target_layer = SessionScript.TargetLayer.STRUCTURE
	session.selected_placeable.clear()
	var cell := Vector3i(0, 0, 0)
	_expect(not session.can_edit_cell(cell, SessionScript.Tool.PAINT).get("valid", false), "erase: paint should reject without a selected material")
	_expect(session.can_edit_cell(cell, SessionScript.Tool.ERASE).get("valid", false), "erase: in-bounds erase should remain valid without a selected material")
	session.set_tool(SessionScript.Tool.ERASE)
	session.begin_stroke("erase")
	_expect(session.apply_at(cell), "erase: existing structure should be removable")
	session.finish_stroke(null)
	_expect(structure_grid.get_cell_item(cell) < 0, "erase: StructureGrid cell should be cleared")
	author.free()


func _test_next_object_id_scans_existing_markers() -> void:
	var author := _make_author()
	var objects := author.get_node("Objects") as Node
	for object_id in [&"crate_001", &"crate_002", &"crate_004"]:
		var marker := MapObjectMarker3D.new()
		marker.object_id = object_id
		objects.add_child(marker)

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var first_id: StringName = session._next_object_id("crate")
	_expect(first_id == &"crate_003", "object id: existing IDs should force the first available suffix")
	var new_marker := MapObjectMarker3D.new()
	new_marker.object_id = first_id
	objects.add_child(new_marker)
	var second_id: StringName = session._next_object_id("crate")
	_expect(second_id == &"crate_005", "object id: a newly occupied suffix should be skipped")
	author.free()


func _test_selection_is_deterministic_and_clears_on_floor_change() -> void:
	var author := _make_author()
	author.level_count = 2
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var floor_grid := author.get_node("FloorGrid") as GridMap
	var before_item := floor_grid.get_cell_item(Vector3i(0, 0, 0))
	var empty_cell := Vector3i(0, 0, 0)
	floor_grid.set_cell_item(empty_cell, -1)
	_expect(not session.select_cell(empty_cell), "selection: an empty Floor coordinate should be rejected")
	_expect(session.get_selected_cells().is_empty(), "selection: an empty Floor coordinate must not enter selected_cells")
	_expect(session.get_last_status().get("valid", true) == false and String(session.get_last_status().get("message", "")).contains("Floor"), "selection: empty Floor rejection should expose a clear status reason")
	_expect(floor_grid.get_cell_item(empty_cell) < 0, "selection: rejected selection must not mutate the existing GridMap")
	floor_grid.set_cell_item(empty_cell, before_item)
	_expect(session.select_cell(Vector3i(1, 0, 0)), "selection: single click should select one cell")
	_expect(session.select_cell(Vector3i(0, 0, 0), true, true), "selection: Shift click should extend selection")
	var selected := session.get_selected_cells()
	_expect(selected.size() == 2, "selection: Shift click should keep both selected cells")
	_expect(selected[0] == Vector3i(0, 0, 0) and selected[1] == Vector3i(1, 0, 0), "selection: cells should have deterministic x/z/y ordering")
	_expect(floor_grid.get_cell_item(Vector3i(0, 0, 0)) == before_item, "selection: selecting cells must not modify GridMap")
	_expect(session.select_cell(Vector3i(0, 0, 0), true, true), "selection: Shift click on selected cell should toggle it")
	_expect(session.get_selected_cells().size() == 1 and session.is_cell_selected(Vector3i(1, 0, 0)), "selection: toggled cell should be removed")
	session.clear_selection()
	_expect(session.select_cells_in_rect(Vector3i(0, 0, 0), Vector3i(1, 0, 0)), "selection: rectangle drag should select the Floor cells in its area")
	_expect(session.get_selected_cells().size() == 2 and session.is_cell_selected(Vector3i(0, 0, 0)) and session.is_cell_selected(Vector3i(1, 0, 0)), "selection: rectangle selection should support multiple cells")
	session.set_floor_level(1)
	_expect(session.get_selected_cells().is_empty(), "selection: changing floor should clear cells from the old floor")
	author.free()


func _test_selection_content_operations_and_undo() -> void:
	var author := _make_author()
	var floor_grid := author.get_node("FloorGrid") as GridMap
	floor_grid.set_cell_item(Vector3i(2, 0, 0), 0)
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	session.placeables = [
		{"id": "selection.floor.0", "label": "Selection Floor 0", "kind": "cell", "layer": SessionScript.TargetLayer.FLOOR, "item_id": 0},
		{"id": "selection.floor.1", "label": "Selection Floor 1", "kind": "cell", "layer": SessionScript.TargetLayer.FLOOR, "item_id": 1},
	]
	session.select_placeable(1)
	session.set_tool(SessionScript.Tool.SELECT)
	_expect(session.select_cell(Vector3i(0, 0, 0)), "selection ops: first cell should be selectable")
	_expect(session.select_cell(Vector3i(1, 0, 0), true, false), "selection ops: Shift-style additive selection should work")
	var selected := session.get_selected_cells()
	_expect(selected.size() == 2 and selected[0] == Vector3i(0, 0, 0) and selected[1] == Vector3i(1, 0, 0), "selection ops: selected cells should be deterministic")

	var replace_undo := UndoRedo.new()
	_expect(session.selection_replace(replace_undo), "selection ops: replace should mutate every selected cell")
	_expect(floor_grid.get_cell_item(Vector3i(0, 0, 0)) == 1 and floor_grid.get_cell_item(Vector3i(1, 0, 0)) == 1, "selection ops: replace should write the selected material")
	_expect(replace_undo.has_undo(), "selection ops: replace should create one Undo action")
	replace_undo.undo()
	_expect(floor_grid.get_cell_item(Vector3i(0, 0, 0)) == 0 and floor_grid.get_cell_item(Vector3i(1, 0, 0)) == 0, "selection ops: replace undo should restore all cells")
	replace_undo.redo()
	_expect(floor_grid.get_cell_item(Vector3i(0, 0, 0)) == 1 and floor_grid.get_cell_item(Vector3i(1, 0, 0)) == 1, "selection ops: replace redo should restore the replacement")

	var before_orientation := floor_grid.get_cell_item_orientation(Vector3i(0, 0, 0))
	var rotate_undo := UndoRedo.new()
	_expect(session.selection_rotate(rotate_undo), "selection ops: rotate should mutate selected cells")
	var rotated_orientation := floor_grid.get_cell_item_orientation(Vector3i(0, 0, 0))
	_expect(rotated_orientation != before_orientation, "selection ops: rotate should change the GridMap orientation")
	rotate_undo.undo()
	_expect(floor_grid.get_cell_item_orientation(Vector3i(0, 0, 0)) == before_orientation, "selection ops: rotate undo should restore orientation")
	rotate_undo.redo()
	_expect(floor_grid.get_cell_item_orientation(Vector3i(0, 0, 0)) == rotated_orientation, "selection ops: rotate redo should restore orientation")

	var copy_undo := UndoRedo.new()
	_expect(session.selection_copy(), "selection ops: copy should fill the selection clipboard")
	_expect(session.has_selection_clipboard(), "selection ops: clipboard should report copied content")
	_expect(session.select_cell(Vector3i(2, 0, 0)), "selection ops: destination anchor should be selectable")
	_expect(session.selection_paste(copy_undo), "selection ops: paste should write the copied shape")
	_expect(floor_grid.get_cell_item(Vector3i(2, 0, 0)) == 1 and floor_grid.get_cell_item(Vector3i(3, 0, 0)) == 1, "selection ops: paste should preserve copied content and shape")
	_expect(copy_undo.has_undo(), "selection ops: paste should create one Undo action")
	copy_undo.undo()
	_expect(floor_grid.get_cell_item(Vector3i(2, 0, 0)) == 0 and floor_grid.get_cell_item(Vector3i(3, 0, 0)) < 0, "selection ops: paste undo should restore the destination")
	copy_undo.redo()
	_expect(floor_grid.get_cell_item(Vector3i(2, 0, 0)) == 1 and floor_grid.get_cell_item(Vector3i(3, 0, 0)) == 1, "selection ops: paste redo should restore the copied shape")

	var move_undo := UndoRedo.new()
	_expect(session.selection_move(Vector3i(1, 0, 0), move_undo), "selection ops: move should move the selected group")
	_expect(floor_grid.get_cell_item(Vector3i(2, 0, 0)) < 0 and floor_grid.get_cell_item(Vector3i(3, 0, 0)) == 1 and floor_grid.get_cell_item(Vector3i(4, 0, 0)) == 1, "selection ops: move should translate content as a group")
	_expect(session.get_selected_cells().has(Vector3i(3, 0, 0)) and session.get_selected_cells().has(Vector3i(4, 0, 0)), "selection ops: move should translate the selection")
	move_undo.undo()
	_expect(floor_grid.get_cell_item(Vector3i(2, 0, 0)) == 1 and floor_grid.get_cell_item(Vector3i(3, 0, 0)) == 1 and floor_grid.get_cell_item(Vector3i(4, 0, 0)) < 0, "selection ops: move undo should restore source and destination")
	move_undo.redo()
	_expect(floor_grid.get_cell_item(Vector3i(3, 0, 0)) == 1 and floor_grid.get_cell_item(Vector3i(4, 0, 0)) == 1, "selection ops: move redo should reapply the translation")

	var delete_undo := UndoRedo.new()
	_expect(session.selection_delete(delete_undo), "selection ops: delete should remove all selected content")
	_expect(floor_grid.get_cell_item(Vector3i(3, 0, 0)) < 0 and floor_grid.get_cell_item(Vector3i(4, 0, 0)) < 0, "selection ops: delete should clear selected content")
	_expect(delete_undo.has_undo(), "selection ops: delete should create one Undo action")
	delete_undo.undo()
	_expect(floor_grid.get_cell_item(Vector3i(3, 0, 0)) == 1 and floor_grid.get_cell_item(Vector3i(4, 0, 0)) == 1, "selection ops: delete undo should restore selected content")
	delete_undo.redo()
	_expect(floor_grid.get_cell_item(Vector3i(3, 0, 0)) < 0 and floor_grid.get_cell_item(Vector3i(4, 0, 0)) < 0, "selection ops: delete redo should remove selected content again")

	delete_undo.free()
	move_undo.free()
	copy_undo.free()
	rotate_undo.free()
	replace_undo.free()
	author.free()


func _test_property_override_batch_undo_and_inherit() -> void:
	var author := _make_author()
	var catalog := MapTileCatalog.new()
	var floor_rule := _legacy_rule(0, 0, &"floor")
	floor_rule.walkable = true
	floor_rule.move_cost = 1
	floor_rule.blocks_los = false
	floor_rule.occluder_height = 0.25
	catalog.rules = [floor_rule]
	author.tile_catalog = catalog
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	session.select_cell(Vector3i(0, 0, 0))
	session.select_cell(Vector3i(1, 0, 0), true, false)
	var undo_redo := UndoRedo.new()
	_expect(session.write_property_override(&"MOVE_COST", 3, [], undo_redo), "property: batch write should change selected cells")
	var summary: Dictionary = session.get_selected_property_summary()
	_expect(summary[&"MOVE_COST"].get("state") == "覆盖", "property: batch write should report override state")
	_expect(summary[&"MOVE_COST"].get("value") == 3, "property: batch write should expose the final value")
	_expect(summary[&"MOVE_COST"].get("base") == 1 and summary[&"MOVE_COST"].get("base_display") == "1", "property: summary should expose the common formal-service base value")
	_expect(summary[&"MOVE_COST"].get("override") == 3 and summary[&"MOVE_COST"].get("override_display") == "3", "property: summary should expose the common override value")
	_expect(author.authoring_data != null, "property: formal service should create authoring data on first write")
	_expect(author.authoring_data != null and author.authoring_data.find_cell_override(Vector3i(0, 0, 0)) != null, "property: formal service should persist the first cell override")
	_expect(author.authoring_data != null and author.authoring_data.find_cell_override(Vector3i(1, 0, 0)) != null, "property: formal service should persist the second cell override")
	_expect(undo_redo.has_undo(), "property: batch write should create one generic Undo action")
	undo_redo.undo()
	summary = session.get_selected_property_summary()
	_expect(summary[&"MOVE_COST"].get("state") == "继承", "property: undo should restore inheritance")
	_expect(summary[&"MOVE_COST"].get("value") == 1, "property: undo should restore the inherited value")
	_expect(author.authoring_data == null, "property: undo should restore null authoring_data when the first edit created it")
	undo_redo.redo()
	_expect(session.get_selected_property_summary()[&"MOVE_COST"].get("value") == 3, "property: redo should restore the batch override")
	_expect(author.authoring_data != null and author.authoring_data.find_cell_override(Vector3i(0, 0, 0)) != null and author.authoring_data.find_cell_override(Vector3i(1, 0, 0)) != null, "property: redo should recreate authoring_data and restore both persisted records")
	_expect(not session.write_property_override(&"MOVE_COST", 0), "property: formal service should reject an invalid value")
	_expect(not session.get_last_status().get("valid", true) and String(session.get_last_status().get("message", "")).contains("失败"), "property: rejected service mutation should expose a failure status")
	_expect(session.write_property_override(&"WALKABLE", false, [Vector3i(0, 0, 0)]), "property: single-cell override should succeed")
	summary = session.get_selected_property_summary()
	_expect(summary[&"WALKABLE"].get("state") == "混合", "property: mixed inherited/override cells should show mixed state")
	_expect(summary[&"WALKABLE"].get("mixed"), "property: differing final values should show mixed value")
	_expect(summary[&"WALKABLE"].get("base_display") == "是" and summary[&"WALKABLE"].get("override_display") == "混合", "property: mixed summary should preserve common base and mixed override display")
	_expect(session.clear_property_override(&"WALKABLE", [Vector3i(0, 0, 0)]), "property: restoring one cell should clear only that field override")
	_expect(session.get_selected_property_summary()[&"WALKABLE"].get("state") == "继承", "property: restoring inheritance should return all cells to inherited state")
	undo_redo.free()

	var retained_author := _make_author()
	retained_author.tile_catalog = catalog
	retained_author.authoring_data = TacticalMapAuthoringData.new()
	var retained_session = SessionScript.new()
	retained_session.begin_for_author(retained_author, retained_author)
	retained_session.select_cell(Vector3i(0, 0, 0))
	var retained_undo := UndoRedo.new()
	_expect(retained_session.write_property_override(&"MOVE_COST", 4, [], retained_undo), "property: edit with a pre-existing empty authoring Resource should succeed")
	retained_undo.undo()
	_expect(retained_author.authoring_data != null and retained_author.authoring_data.is_empty(), "property: undo must retain a pre-existing empty authoring Resource")
	retained_undo.redo()
	_expect(retained_author.authoring_data != null and retained_author.authoring_data.find_cell_override(Vector3i(0, 0, 0)) != null, "property: redo must restore the pre-existing Resource override")
	retained_undo.free()
	retained_author.free()
	author.free()


func _test_debug_views_validation_and_focus() -> void:
	var author := _make_author()
	var catalog := MapTileCatalog.new()
	var floor_rule := _legacy_rule(0, 0, &"floor")
	var wall_rule := _legacy_rule(1, 1, &"wall")
	wall_rule.walkable = false
	catalog.rules = [floor_rule, wall_rule]
	author.tile_catalog = catalog
	var structure_grid := author.get_node("StructureGrid") as GridMap
	structure_grid.set_cell_item(Vector3i(0, 0, 0), 1)
	var blocking_object := MapObjectMarker3D.new()
	blocking_object.object_id = &"synthetic_blocker"
	blocking_object.cell = Vector3i(1, 0, 0)
	blocking_object.blocks_movement = true
	author.get_node("Objects").add_child(blocking_object)
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	for view in range(SessionScript.DebugView.NORMAL, SessionScript.DebugView.VALIDATION + 1):
		session.set_debug_view(view)
		_expect(session.get_debug_view() == view, "debug: view enum should remain stable")
		_expect(not session.debug_view_name().is_empty() and not session.debug_view_legend().is_empty(), "debug: every view should expose a name and legend")
	var inspection := session.inspect_debug_cells()
	_expect(inspection.has("cells"), "debug: formal inspect_all_cells result should expose cells")
	_expect((inspection.get("cells", []) as Array).size() == 2, "debug: formal all-cell inspection should include both Floor cells")
	var initial_heatmap_records := session.get_debug_cells_for_view(SessionScript.DebugView.WALKABILITY)
	var wall_walkable: Variant = null
	var object_walkable: Variant = null
	var object_blocker_ids := PackedStringArray()
	for record in initial_heatmap_records:
		if record.get("coordinate", null) == Vector3i(0, 0, 0):
			wall_walkable = session.get_debug_value(record, &"walkable")
		if record.get("coordinate", null) == Vector3i(1, 0, 0):
			object_walkable = session.get_debug_value(record, &"walkable")
			object_blocker_ids = record.get(&"blocking_object_ids", PackedStringArray())
	_expect(wall_walkable == false, "debug: Structure walkability contribution should remain visible as blocked")
	_expect(object_walkable == false, "debug: blocking Object markers should make the initial Walkability view blocked")
	_expect(object_blocker_ids == PackedStringArray(["synthetic_blocker"]), "debug: Walkability records should identify blocking Object instances")
	var diagnostics := session.get_validation_diagnostics()
	for diagnostic in diagnostics:
		_expect(diagnostic is Dictionary and diagnostic.has("severity") and diagnostic.has("message"), "debug: validation entries must remain structured")
	_expect(session.select_cell(Vector3i(0, 0, 0)), "debug: a real Floor cell should be selectable for focus")
	_expect(session.set_debug_focus(Vector3i(1, 0, 0)), "debug: valid Floor cell should accept a debug focus")
	_expect(session.debug_focus_cell == Vector3i(1, 0, 0), "debug: focus state should retain the structured coordinate")
	var floor_grid := author.get_node("FloorGrid") as GridMap
	var old_item := floor_grid.get_cell_item(Vector3i(0, 0, 0))
	floor_grid.set_cell_item(Vector3i(0, 0, 0), -1)
	var empty_cell := Vector3i(0, 0, 0)
	var has_missing_floor_diagnostic := false
	for diagnostic in session.get_validation_diagnostics():
		if diagnostic.get("coordinate", null) == empty_cell:
			has_missing_floor_diagnostic = true
			break
	_expect(has_missing_floor_diagnostic, "debug: missing-Floor coordinate should come from a structured diagnostic")
	_expect(not session.select_cell(empty_cell), "debug: ordinary selection must still reject an empty Floor coordinate")
	_expect(not session.set_debug_focus(Vector3i(0, 0, 0)), "debug: empty Floor coordinate must not become a focus target")
	_expect(session.debug_focus_cell == Vector3i(1, 0, 0), "debug: rejected focus must preserve the previous focus")
	_expect(session.focus_validation_cell(empty_cell), "debug: structured missing-Floor coordinate should be focusable")
	_expect(session.get_debug_focus_cell() == empty_cell, "debug: validation focus should retain a missing-Floor coordinate")
	var validation_records := session.get_debug_cells_for_view(SessionScript.DebugView.VALIDATION)
	var heatmap_records := session.get_debug_cells_for_view(SessionScript.DebugView.WALKABILITY)
	var validation_only_found := false
	var heatmap_missing_found := false
	for record in validation_records:
		if record.get("coordinate", null) == empty_cell:
			validation_only_found = bool(record.get("validation_only", false))
			break
	for record in heatmap_records:
		if record.get("coordinate", null) == empty_cell:
			heatmap_missing_found = true
	_expect(validation_only_found, "debug: Validation view should include the missing-Floor diagnostic record")
	_expect(not heatmap_missing_found, "debug: heatmap views must exclude validation-only coordinates")
	floor_grid.set_cell_item(Vector3i(0, 0, 0), old_item)
	author.free()


func _test_cover_debug_snapshot_and_coordinate_restore() -> void:
	var author := _make_cover_author()
	var session = SessionScript.new()
	_expect(session.begin_for_author(author, author), "cover debug: synthetic author should bind")
	for view in range(SessionScript.DebugView.NORMAL, SessionScript.DebugView.COVER + 1):
		session.set_debug_view(view)
		_expect(session.get_debug_view() == view, "cover debug: appended view ID should remain selectable")
	var snapshot: Dictionary = session.get_cover_debug_snapshot()
	var edges: Array = snapshot.get(&"edges", [])
	_expect(snapshot.get(&"floor_level", -1) == 0, "cover debug: snapshot should report the current floor")
	_expect(snapshot.get(&"definition_origin", Vector3.ZERO) == Vector3(-16.0, 0.0, -28.0), "cover debug: definition origin should preserve Baker normalization offset for negative author coordinates")
	_expect(edges.size() >= 1, "cover debug: Baker-derived edge should be exposed")
	var found_derived := false
	var derived_edge_key := ""
	for edge_value in edges:
		if not edge_value is Dictionary or bool((edge_value as Dictionary).get(&"diagnostic_only", false)):
			continue
		var edge: Dictionary = edge_value
		if edge.get(&"source_type", &"") != &"structure_derived":
			continue
		found_derived = true
		if derived_edge_key.is_empty():
			derived_edge_key = String(edge.get(&"edge_key", ""))
		_expect(edge.get(&"source_cell", Vector3i.ZERO) == Vector3i(-3, 0, -3), "cover debug: provenance source cell should be restored to negative author coordinates")
		_expect(edge.get(&"runtime_source_cell", Vector3i(-1, -1, -1)) == Vector3i(0, 0, 1), "cover debug: runtime provenance source cell should remain available separately")
		_expect(edge.get(&"cell_a", Vector3i.ZERO) == Vector3i(-3, 0, -4) and edge.get(&"cell_b", Vector3i.ZERO) == Vector3i(-3, 0, -3), "cover debug: canonical edge endpoints should be restored to negative author coordinates")
		var profile_a: Dictionary = edge.get(&"profile_a", {})
		var profile_b: Dictionary = edge.get(&"profile_b", {})
		_expect(int(profile_a.get(&"level", 0)) == 1 or int(profile_b.get(&"level", 0)) == 1, "cover debug: final edge snapshot should expose the HALF profile")
	_expect(found_derived, "cover debug: structure provenance should be visible in the snapshot")
	_expect(not derived_edge_key.is_empty() and session.select_cover_edge(derived_edge_key), "cover debug: a baked edge should be selectable by its stable key")
	var selected_edge: Dictionary = session.get_selected_cover_edge()
	_expect(String(selected_edge.get(&"edge_key", "")) == derived_edge_key, "cover debug: selected edge getter should expose a detached matching snapshot")
	_expect(session.get_selected_cover_edge_key() == derived_edge_key, "cover debug: selected edge key should remain stable")
	_expect(session.clear_cover_edge_selection(), "cover debug: selected edge should be clearable")
	_expect(session.get_selected_cover_edge().is_empty(), "cover debug: clearing selection should remove the inspection snapshot")
	var baked := TacticalMapBaker.build(author)
	var definition := baked.get(&"definition", null) as TacticalMapDefinition
	_expect(definition != null and not definition.edges.is_empty(), "cover debug: synthetic Baker output should contain an edge")
	if definition != null and not definition.edges.is_empty():
		var runtime_cell := definition.edges[0].cell_a
		var restored := SessionScript.runtime_cell_to_author_cell(runtime_cell, definition, author)
		_expect(restored == Vector3i(-3, 0, -4), "cover debug: public coordinate helper should restore negative runtime X/Z")
	author.free()


func _make_cover_author() -> TacticalMapAuthor:
	var author := TacticalMapAuthor.new()
	author.map_id = &"editor_cover_synthetic"
	author.footprint_size = Vector2i(8, 8)
	author.level_count = 1
	author.cell_dimensions = Vector3(2.0, 2.0, 2.0)
	author.grid_origin = Vector3(-10.0, 0.0, -20.0)
	var mesh_library := MeshLibrary.new()
	mesh_library.create_item(0)
	mesh_library.create_item(1)
	var floor_grid := GridMap.new()
	floor_grid.name = "FloorGrid"
	floor_grid.mesh_library = mesh_library
	floor_grid.cell_size = author.cell_dimensions
	floor_grid.set_cell_item(Vector3i(-3, 0, -4), 0)
	floor_grid.set_cell_item(Vector3i(-3, 0, -3), 0)
	author.add_child(floor_grid)
	var structure_grid := GridMap.new()
	structure_grid.name = "StructureGrid"
	structure_grid.mesh_library = mesh_library
	structure_grid.cell_size = author.cell_dimensions
	structure_grid.set_cell_item(Vector3i(-3, 0, -3), 1)
	author.add_child(structure_grid)
	var floor_definition := TacticalCellTileDefinition.new()
	floor_definition.placeable_id = &"test.cover.floor"
	floor_definition.display_name = "Synthetic Floor"
	floor_definition.target_layer = MapTileRule.Layer.FLOOR
	floor_definition.mesh_item_id = 0
	floor_definition.mesh_library = mesh_library
	var structure_definition := TacticalCellTileDefinition.new()
	structure_definition.placeable_id = &"test.cover.structure"
	structure_definition.display_name = "Synthetic Cover"
	structure_definition.target_layer = MapTileRule.Layer.STRUCTURE
	structure_definition.mesh_item_id = 1
	structure_definition.mesh_library = mesh_library
	var rules := TacticalEdgeRules.new()
	rules.cover_a = TacticalEdgeRules.CoverLevel.NONE
	rules.cover_b = TacticalEdgeRules.CoverLevel.HALF
	rules.cover_profile_a = TacticalCoverProfile.default_for_level(0)
	rules.cover_profile_b = TacticalCoverProfile.default_for_level(1)
	var contribution := TacticalLocalEdgeContribution.new()
	contribution.local_direction = TacticalLocalEdgeContribution.LocalDirection.NORTH
	contribution.edge_rules = rules
	structure_definition.edge_contributions = [contribution]
	var library := TacticalPlaceableLibrary.new()
	library.generated_mesh_library = mesh_library
	library.definitions = [floor_definition, structure_definition]
	var floor_binding := MeshItemBinding.new()
	floor_binding.placeable_id = floor_definition.placeable_id
	floor_binding.target_layer = MapTileRule.Layer.FLOOR
	floor_binding.mesh_item_id = 0
	floor_binding.mesh_library = mesh_library
	var structure_binding := MeshItemBinding.new()
	structure_binding.placeable_id = structure_definition.placeable_id
	structure_binding.target_layer = MapTileRule.Layer.STRUCTURE
	structure_binding.mesh_item_id = 1
	structure_binding.mesh_library = mesh_library
	library.item_bindings = [floor_binding, structure_binding]
	author.placeable_library = library
	return author


func _test_legacy_default_descriptor_constraints() -> void:
	var author := _make_author()
	var legacy_rule := _legacy_rule(0, 1, &"legacy_floor")
	legacy_rule.blocks_los = true
	var catalog := MapTileCatalog.new()
	catalog.rules = [legacy_rule]
	author.tile_catalog = catalog
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var legacy_index := _find_placeable(session.get_placeables(), "catalog:0:1")
	_expect(legacy_index >= 0, "default: legacy catalog entry should be selectable")
	if legacy_index >= 0:
		session.select_placeable(legacy_index)
		var legacy_context := session.get_default_property_context()
		var legacy_descriptor: Dictionary = legacy_context.get("descriptors", {}).get(&"SIGHT_BLOCK", {})
		var legacy_allowed: Array = legacy_descriptor.get("allowed_values", [])
		_expect(legacy_allowed.size() == 2 and is_equal_approx(float(legacy_allowed[0]), 0.0) and is_equal_approx(float(legacy_allowed[1]), 1.0), "default: legacy sight descriptor should expose only 0/1")
		_expect(is_equal_approx(float(legacy_descriptor.get("step", 0.0)), 1.0), "default: legacy sight descriptor should use step 1")
		_expect(not session.write_default_property(&"SIGHT_BLOCK", 0.5), "default: legacy sight mutation must reject fractional values")

	var definition := TacticalCellTileDefinition.new()
	definition.placeable_id = &"formal.sight"
	definition.display_name = "Formal Sight"
	definition.placement_kind = 0
	definition.target_layer = 0
	definition.mesh_item_id = 1
	var library := TacticalPlaceableLibrary.new()
	library.definitions = [definition]
	author.placeable_library = library
	session.begin_for_author(author, author)
	var formal_context := session.get_default_property_context()
	var formal_descriptor: Dictionary = formal_context.get("descriptors", {}).get(&"SIGHT_BLOCK", {})
	_expect(is_equal_approx(float(formal_descriptor.get("step", 0.0)), 0.01), "default: formal definition should restore sight step 0.01")
	_expect(Array(formal_descriptor.get("allowed_values", [])).is_empty(), "default: formal definition should not retain legacy binary choices")
	author.free()


func _test_default_property_service_undo_and_null_restore() -> void:
	var author := _make_author()
	var definition := TacticalCellTileDefinition.new()
	definition.placeable_id = &"default.null_contribution"
	definition.display_name = "Null Contribution"
	definition.placement_kind = 0
	definition.target_layer = 0
	definition.mesh_item_id = 1
	var library := TacticalPlaceableLibrary.new()
	library.definitions = [definition]
	author.placeable_library = library
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var context := session.get_default_property_context()
	_expect(bool(context.get("available", false)), "default: formal source inspection should mark a cell definition available")
	_expect(bool(context.get("supported", {}).get(&"SIGHT_BLOCK", false)), "default: TacticalCellRules source should support sight blocking")
	_expect(definition.rule_contribution == null, "default: fixture should start without rule_contribution")
	var undo_redo := UndoRedo.new()
	_expect(session.write_default_property(&"MOVE_COST", 4, undo_redo), "default: formal service mutation should succeed")
	_expect(definition.rule_contribution != null and definition.rule_contribution.move_cost == 4, "default: do state should create and write rule_contribution")
	undo_redo.undo()
	_expect(definition.rule_contribution == null, "default: undo must restore a null rule_contribution exactly")
	undo_redo.redo()
	_expect(definition.rule_contribution != null and definition.rule_contribution.move_cost == 4, "default: redo should recreate the contribution")
	var restore_undo := UndoRedo.new()
	_expect(session.restore_default_property(&"MOVE_COST", restore_undo), "default: restore should be a formal undoable action")
	_expect(definition.rule_contribution == null, "default: restore action should return to the captured baseline")
	restore_undo.undo()
	_expect(definition.rule_contribution != null and definition.rule_contribution.move_cost == 4, "default: undoing restore should recover the edited contribution")
	undo_redo.free()
	restore_undo.free()
	author.free()


func _test_special_spawn_configuration_and_state() -> void:
	var author := _make_author()
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var enemy_index := _find_placeable(session.get_placeables(), "marker:enemy_spawn")
	var traversal_index := _find_placeable(session.get_placeables(), "marker:traversal_link")
	var patrol_index := _find_placeable(session.get_placeables(), "marker:patrol_route")
	_expect(enemy_index >= 0 and traversal_index >= 0 and patrol_index >= 0, "special: builtin spawn, traversal, and patrol entries must be available")
	if enemy_index < 0 or traversal_index < 0 or patrol_index < 0:
		author.free()
		return
	session.select_placeable(enemy_index)
	var archetype := UnitArchetype.new()
	archetype.archetype_id = &"synthetic_assault"
	var weapon := WeaponDefinition.new()
	weapon.weapon_id = &"synthetic_carbine"
	var configuration := {
		&"archetype": archetype,
		&"weapon": weapon,
		&"encounter_id": &"encounter_alpha",
		&"patrol_route_id": &"route_alpha",
		&"faction": "enemy",
		&"visual_color": Color("ff8844"),
	}
	_expect(session.set_selected_spawn_configuration(configuration), "special: selected enemy spawn must accept its configurable fields")
	var selected_configuration: Dictionary = session.get_selected_spawn_configuration()
	_expect(selected_configuration.get("archetype", null) == archetype and selected_configuration.get("weapon", null) == weapon, "special: spawn getter must return configured archetype and weapon")
	_expect(selected_configuration.get("encounter_id", &"") == &"encounter_alpha" and selected_configuration.get("patrol_route_id", &"") == &"route_alpha", "special: spawn getter must return encounter and patrol route IDs")
	_expect(selected_configuration.get("faction", "") == "enemy" and selected_configuration.get("visual_color", Color.WHITE) == Color("ff8844"), "special: spawn getter must return faction and visual color")

	session.select_placeable(patrol_index)
	session.begin_stroke("patrol state")
	_expect(session.apply_at(Vector3i(0, 0, 0)), "special: patrol first point should apply")
	var patrol_state: Dictionary = session.get_special_edit_state()
	_expect(patrol_state.get("kind", "") == "patrol" and patrol_state.get("active", false) and patrol_state.get("can_finish", false), "special: active patrol state must be exposed to the UI")
	# Selecting another material cancels the uncommitted special stroke rather
	# than leaving a hidden route that can be appended after reselection.
	session.select_placeable(enemy_index)
	var switched_state: Dictionary = session.get_special_edit_state()
	_expect(not switched_state.get("active", false) and not switched_state.get("pending", false) and not switched_state.get("can_finish", false), "special: changing placeable must deterministically clear the prior patrol state")
	_expect(author.get_node_or_null("PatrolRoutes") == null, "special: canceled patrol stroke must not leave an uncommitted route root")

	session.select_placeable(traversal_index)
	session.begin_stroke("traversal state")
	_expect(session.apply_at(Vector3i(0, 0, 0)), "special: traversal start should apply")
	var traversal_state: Dictionary = session.get_special_edit_state()
	_expect(traversal_state.get("kind", "") == "traversal" and traversal_state.get("pending", false) and traversal_state.get("can_finish", false), "special: pending traversal state must be exposed to the UI")
	_expect(session.finish_special_edit(), "special: finish_special_edit must cancel a pending traversal")
	_expect(not session.get_special_edit_state().get("can_finish", false), "special: canceled traversal must no longer be finishable")
	author.free()


func _test_special_undo_redo_roundtrips() -> void:
	var author := _make_author()
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var spawn_index := _find_placeable(session.get_placeables(), "marker:enemy_spawn")
	var traversal_index := _find_placeable(session.get_placeables(), "marker:traversal_link")
	var patrol_index := _find_placeable(session.get_placeables(), "marker:patrol_route")
	if spawn_index < 0 or traversal_index < 0 or patrol_index < 0:
		_expect(false, "special undo: required builtin placeables must be available")
		author.free()
		return

	# Spawn root creation and restoration.
	session.select_placeable(spawn_index)
	var spawn_undo := UndoRedo.new()
	session.begin_stroke("spawn undo")
	_expect(session.apply_at(Vector3i(0, 0, 0)), "special undo: spawn should apply")
	_expect(session.finish_stroke(spawn_undo), "special undo: spawn should commit")
	_expect(author.get_node_or_null("Spawns") != null and author.get_node("Spawns").get_child_count() == 1, "special undo: spawn do state should contain one marker")
	spawn_undo.undo()
	_expect(author.get_node_or_null("Spawns") == null, "special undo: spawn undo should remove a newly created root")
	spawn_undo.redo()
	_expect(author.get_node_or_null("Spawns") != null and author.get_node("Spawns").get_child_count() == 1, "special undo: spawn redo should recreate the marker")
	spawn_undo.free()

	# Traversal is a two-endpoint placement and must be a single stroke action.
	session.select_placeable(traversal_index)
	var traversal_undo := UndoRedo.new()
	session.begin_stroke("traversal undo")
	_expect(session.apply_at(Vector3i(0, 0, 0)) and session.apply_at(Vector3i(1, 0, 0)), "special undo: traversal should accept two endpoints")
	_expect(session.finish_stroke(traversal_undo), "special undo: traversal should commit as one action")
	var link := author.get_node("TraversalLinks").get_child(0) as TraversalLink3D
	_expect(link != null and link.from_cell == Vector3i(0, 0, 0) and link.to_cell == Vector3i(1, 0, 0), "special undo: traversal do state should preserve endpoint order")
	traversal_undo.undo()
	_expect(author.get_node_or_null("TraversalLinks") == null, "special undo: traversal undo should remove a newly created root")
	traversal_undo.redo()
	link = author.get_node("TraversalLinks").get_child(0) as TraversalLink3D
	_expect(link != null and link.from_cell == Vector3i(0, 0, 0) and link.to_cell == Vector3i(1, 0, 0), "special undo: traversal redo should restore both endpoints")
	traversal_undo.free()

	# Patrol A -> B -> A must remain exactly ordered through Undo/Redo.
	session.select_placeable(patrol_index)
	var patrol_undo := UndoRedo.new()
	session.begin_stroke("patrol undo")
	var point_a := Vector3i(0, 0, 0)
	var point_b := Vector3i(1, 0, 0)
	_expect(session.apply_at(point_a) and session.apply_at(point_b) and session.apply_at(point_a), "special undo: patrol should accept a repeated non-consecutive point")
	_expect(session.finish_special_edit(patrol_undo), "special undo: finish_special_edit should commit patrol")
	var route := author.get_node("PatrolRoutes").get_child(0) as PatrolRoute3D
	_expect(route != null and route.points == [point_a, point_b, point_a], "special undo: patrol do state must preserve A->B->A order")
	patrol_undo.undo()
	_expect(author.get_node_or_null("PatrolRoutes") == null, "special undo: patrol undo should remove a newly created root")
	patrol_undo.redo()
	route = author.get_node("PatrolRoutes").get_child(0) as PatrolRoute3D
	_expect(route != null and route.points == [point_a, point_b, point_a], "special undo: patrol redo must preserve repeated route points")
	patrol_undo.free()
	author.free()


func _make_author() -> TacticalMapAuthor:
	var author := TacticalMapAuthor.new()
	author.map_id = &"editor_session_synthetic"
	author.footprint_size = Vector2i(2, 1)
	author.level_count = 1
	author.cell_dimensions = Vector3(2.0, 2.0, 2.0)
	var mesh_library := MeshLibrary.new()
	for item_id in range(5):
		mesh_library.create_item(item_id)
	var floor_grid := GridMap.new()
	floor_grid.name = "FloorGrid"
	floor_grid.mesh_library = mesh_library
	floor_grid.cell_size = author.cell_dimensions
	floor_grid.set_cell_item(Vector3i(0, 0, 0), 0)
	floor_grid.set_cell_item(Vector3i(1, 0, 0), 0)
	author.add_child(floor_grid)
	var structure_grid := GridMap.new()
	structure_grid.name = "StructureGrid"
	structure_grid.mesh_library = mesh_library
	structure_grid.cell_size = author.cell_dimensions
	author.add_child(structure_grid)
	var objects := Node3D.new()
	objects.name = "Objects"
	author.add_child(objects)
	return author


func _legacy_rule(layer: int, item_id: int, tile_id: StringName) -> MapTileRule:
	var rule := MapTileRule.new()
	rule.layer = layer
	rule.item_id = item_id
	rule.tile_id = tile_id
	return rule


func _find_placeable(entries: Array, placeable_id: String) -> int:
	for index in range(entries.size()):
		if String(entries[index].get("id", "")) == placeable_id:
			return index
	return -1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_MAP_EDITOR_SESSION_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_MAP_EDITOR_SESSION_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
