extends SceneTree

## Pure editor-session coverage. This test builds an in-memory author with
## synthetic GridMaps and definitions; it never loads a production map scene.

const SessionScript = preload("res://addons/tactical_map_editor/editing/map_edit_session.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_catalog_integer_layer_routing()
	_test_library_integer_placement_and_layer_routing()
	_test_paint_uses_selected_entry_layer()
	_test_noop_stroke_does_not_commit()
	_test_undo_snapshot_call_signature()
	_test_object_snapshot_includes_facing()
	_test_erase_validation_ignores_paint_selection()
	_test_next_object_id_scans_existing_markers()
	_finish()


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
	_expect(wall_index >= 0 and low_cover_index >= 0, "catalog: wall and low_cover should be discoverable")
	if wall_index < 0 or low_cover_index < 0:
		author.free()
		return
	var wall_entry: Dictionary = session.get_placeables()[wall_index]
	var low_cover_entry: Dictionary = session.get_placeables()[low_cover_index]
	_expect(int(wall_entry.get("layer", -1)) == SessionScript.TargetLayer.STRUCTURE, "catalog: wall integer layer should route to Structure")
	_expect(int(low_cover_entry.get("layer", -1)) == SessionScript.TargetLayer.STRUCTURE, "catalog: low_cover integer layer should route to Structure")

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
